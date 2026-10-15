local ADDON, CRT = ...

-- The low-health sound: the game's own low-health pulse, from its Combat Audio Alerts (Options >
-- Accessibility). An addon can't play a sound for low health itself in Midnight, because your health
-- is a secret value and choosing to play a sound would mean comparing it. The game's pulse compares
-- it for us: it loops a sound while your health is under a threshold, faster as it drops.
--
-- From Blizzard_SettingsDefinitions_Frame/CombatAudioAlertConstants.lua and the CombatAudioAlert API:
--   CAAEnabled                    Combat Audio Alerts on or off (off by default)
--   CAAPulsePlayerHealthPercent   0 off, 1 "under 90%" ... 9 "under 10%"
--   PlayerHealthPulse volume      C_CombatAudioAlert.SetCategoryVolume(category, 0 to 100)
-- Turning Combat Audio Alerts on also turns on its spoken alerts (combat start and end, your target's
-- name and so on). If they were off before, this turns those spoken alerts off, so only the pulse
-- plays. Everything changed is saved first in CRTDB.qol.lowHealth.caaSaved and put back when the
-- sound is turned off. The pulse sound itself is the game's (CombatAudioAlertPulseSoundData, which
-- Blizzard reads on demand so an addon could swap in its own later).

local LowHealth = CRT.LowHealth
local Sound = {}
CRT.LowHealthSound = Sound

-- The spoken alerts, switched off when Combat Audio Alerts were off before.
local SPEECH_CVARS = {
    "CAASayCombatStart", "CAASayCombatEnd", "CAAPlayerHealthPercent", "CAASayTargetName", "CAASayIfTargeted",
    "CAATargetHealthPercent", "CAAPartyHealthPercent", "CAAPlayerCastMode", "CAATargetCastMode",
    "CAAInterruptCast", "CAAInterruptCastSuccess", "CAASayYourDebuffs", "CAADebuffSelfAlert",
}
local ENABLED, PULSE = "CAAEnabled", "CAAPulsePlayerHealthPercent"
local TEST_SECONDS = 3

local function settings()
    return CRT.db.qol.lowHealth
end

local function getCVar(name)
    if not (C_CVar and C_CVar.GetCVar) then
        return nil
    end
    local ok, value = pcall(C_CVar.GetCVar, name)
    return ok and value or nil
end

local function setCVar(name, value)
    if value ~= nil and C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, name, tostring(value))
    end
end

local function sayIfTargeted()
    local setting = Enum and Enum.CombatAudioAlertSpecSetting and Enum.CombatAudioAlertSpecSetting.SayIfTargeted
    return setting
end

-- True when this client has the game's pulse.
function Sound:Available()
    return getCVar(PULSE) ~= nil and C_CombatAudioAlert ~= nil
end

-- The game's pulse works in 10% steps: the threshold rounded to the nearest one, 10% to 90%.
function Sound:StepPercent()
    local percent = math.floor((settings().threshold or 35) / 10 + 0.5) * 10
    return math.max(10, math.min(90, percent))
end

local function pulseValue()
    return math.floor((100 - Sound:StepPercent()) / 10 + 0.5)
end

local function save()
    local s = settings()
    if s.caaSaved then
        return
    end
    local saved = { [ENABLED] = getCVar(ENABLED), [PULSE] = getCVar(PULSE), speech = {} }
    for _, name in ipairs(SPEECH_CVARS) do
        saved.speech[name] = getCVar(name)
    end
    local setting = sayIfTargeted()
    if setting and C_CombatAudioAlert and C_CombatAudioAlert.GetSpecSetting then
        local ok, value = pcall(C_CombatAudioAlert.GetSpecSetting, setting)
        saved.sayIfTargeted = ok and value or nil
    end
    if C_CombatAudioAlert and C_CombatAudioAlert.GetCategoryVolume then
        local ok, value = pcall(C_CombatAudioAlert.GetCategoryVolume, Enum.CombatAudioAlertCategory.PlayerHealthPulse)
        saved.volume = ok and value or nil
    end
    s.caaSaved = saved
end

local function restore()
    local s = settings()
    local saved = s.caaSaved
    if not saved then
        return
    end
    for name, value in pairs(saved.speech or {}) do
        setCVar(name, value)
    end
    local setting = sayIfTargeted()
    if setting and saved.sayIfTargeted ~= nil and C_CombatAudioAlert and C_CombatAudioAlert.SetSpecSetting then
        pcall(C_CombatAudioAlert.SetSpecSetting, setting, saved.sayIfTargeted)
    end
    if saved.volume ~= nil and C_CombatAudioAlert and C_CombatAudioAlert.SetCategoryVolume then
        pcall(C_CombatAudioAlert.SetCategoryVolume, Enum.CombatAudioAlertCategory.PlayerHealthPulse, saved.volume)
    end
    setCVar(PULSE, saved[PULSE])
    setCVar(ENABLED, saved[ENABLED])
    s.caaSaved = nil
end

-- Turns the game's pulse on or off to match the settings: on while the low-health alert and its sound
-- are both ticked.
function Sound:Apply()
    if not self:Available() then
        return
    end
    local s = settings()
    if not (s.enabled and s.sound) then
        restore()
        return
    end
    local wasOn = s.caaSaved ~= nil
    save()
    -- Only the pulse: if Combat Audio Alerts were off before, their spoken alerts are switched off.
    if not wasOn and s.caaSaved[ENABLED] == "0" then
        for _, name in ipairs(SPEECH_CVARS) do
            setCVar(name, 0)
        end
        local setting = sayIfTargeted()
        if setting and C_CombatAudioAlert.SetSpecSetting then
            pcall(C_CombatAudioAlert.SetSpecSetting, setting, 0)
        end
    end
    setCVar(ENABLED, 1)
    setCVar(PULSE, pulseValue())
    if C_CombatAudioAlert.SetCategoryVolume then
        pcall(C_CombatAudioAlert.SetCategoryVolume, Enum.CombatAudioAlertCategory.PlayerHealthPulse, s.soundVolume or 100)
    end
end

-- Plays the pulse for your threshold for a few seconds, through the addon's sound channel. The real
-- pulse is played by the game, on its own voice output, at the volume set here.
function Sound:Test()
    local kits = _G.CombatAudioAlertPulseSoundData
    local kit = kits and kits[self:StepPercent()]
    if not kit then
        CRT:Print("This client has no low-health pulse sound.")
        return
    end
    local handle = CRT:PlaySound(kit)
    if handle then
        C_Timer.After(TEST_SECONDS, function()
            StopSound(handle)
        end)
    end
end

-- Lines for /crt lowhp info.
function Sound:Info()
    return format("sound: setting %s, available %s, CAAEnabled %s, pulse %s (under %d%%), saved settings %s",
        tostring(settings().sound), tostring(self:Available()), tostring(getCVar(ENABLED)), tostring(getCVar(PULSE)),
        self:StepPercent(), tostring(settings().caaSaved ~= nil))
end
