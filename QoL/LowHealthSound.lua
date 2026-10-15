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
-- sound is turned off.
--
-- Your own sound and output: with the game's pulse on the game's output, the game plays it as usual.
-- Otherwise the game's pulse still runs, muted (its volume set to 0), and the addon follows it: the
-- game calls CombatAudioAlertManager:SetHealthPulseSoundKit(kit) when the pulse starts, changes tier
-- or stops (kit nil), and StopHealthPulse on a loading screen. A hook on those plays your choice through
-- your channel instead, so your health is never read by the addon. The game's pulse kits loop by
-- themselves; the other sounds repeat, faster at each lower 10% tier, until the pulse stops.

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

-- The sounds to choose from: the game's pulse, then game alert sounds by their SOUNDKIT name (checked
-- in Blizzard_SharedXML/Mainline/SoundKitConstants.lua, with the ID there as a fallback).
Sound.CHOICES = {
    { key = "pulse", label = "Game pulse (speeds up)" },
    { key = "RAID_WARNING", label = "Raid warning", id = 8959 },
    { key = "RAID_BOSS_EMOTE_WARNING", label = "Boss emote warning", id = 12197 },
    { key = "UI_RAID_BOSS_WHISPER_WARNING", label = "Boss whisper warning", id = 37666 },
    { key = "ALARM_CLOCK_WARNING_3", label = "Alarm clock", id = 12889 },
    { key = "READY_CHECK", label = "Ready check", id = 8960 },
    { key = "PVP_THROUGH_QUEUE", label = "Queue pop", id = 8459 },
    { key = "TELL_MESSAGE", label = "Whisper", id = 3081 },
}
local choiceByKey = {}
for _, c in ipairs(Sound.CHOICES) do
    choiceByKey[c.key] = c
end

-- The outputs to choose from: the game's own (the pulse plays as a voice sound), then every channel.
function Sound.Outputs()
    local out = { { key = "game", label = "Game default (voice)" } }
    for _, c in ipairs(CRT.SOUND_CHANNELS) do
        out[#out + 1] = c
    end
    return out
end

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
        self:StopOurs()
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
    -- The game plays it unless you picked another sound or output, when it runs muted and the addon
    -- plays yours.
    local custom = self:Custom()
    if custom then
        self:Hook()
    else
        self:StopOurs()
    end
    if C_CombatAudioAlert.SetCategoryVolume then
        pcall(C_CombatAudioAlert.SetCategoryVolume, Enum.CombatAudioAlertCategory.PlayerHealthPulse, custom and 0 or (s.soundVolume or 100))
    end
end

-- True when the addon plays the sound: any sound or output other than the game's pulse on its own.
function Sound:Custom()
    local s = settings()
    return (s.soundChoice or "pulse") ~= "pulse" or (s.soundChannel or "game") ~= "game"
end

-- Playing your sound -----------------------------------------------------------------------------

local playing -- { handle, ticker, kit } while the addon's sound plays

local function channel()
    local c = settings().soundChannel or "game"
    return c == "game" and "Voice" or c
end

-- Plays a sound kit on your output at your volume. Returns its handle.
local function play(kit)
    local volume = (settings().soundVolume or 100) / 100
    if C_Sound and C_Sound.PlaySoundWithOptions then
        local ok, success, handle = pcall(C_Sound.PlaySoundWithOptions, { soundKitID = kit, uiSoundSubType = channel(), volumeOverride = volume })
        if ok and success then
            return handle
        end
    end
    local ok, willPlay, handle = pcall(PlaySound, kit, channel())
    return ok and willPlay and handle or nil
end

-- The tier a game pulse kit belongs to (90 down to 10), from the game's own table.
local function tierOf(kit)
    for percent, id in pairs(_G.CombatAudioAlertPulseSoundData or {}) do
        if id == kit then
            return percent
        end
    end
    return 50
end

local function chosenKit()
    local c = choiceByKey[settings().soundChoice or "pulse"]
    if not c or c.key == "pulse" then
        return nil
    end
    return (SOUNDKIT and SOUNDKIT[c.key]) or c.id
end

function Sound:StopOurs()
    if playing then
        if playing.handle then
            pcall(StopSound, playing.handle)
        end
        if playing.ticker then
            playing.ticker:Cancel()
        end
        playing = nil
    end
end

-- Starts your sound for a game pulse kit: the same kit on your output, or your chosen sound repeating,
-- every 2.4 seconds at 90% down to every 0.8 seconds at 10%.
local function start(kit)
    local alert = chosenKit()
    if not alert then
        playing = { kit = kit, handle = play(kit) }
        return
    end
    local tier = tierOf(kit)
    local every = 0.6 + tier / 50
    playing = { kit = kit, handle = play(alert) }
    playing.ticker = C_Timer.NewTicker(every, function()
        play(alert)
    end)
end

local function onPulse(_, kit)
    if not (Sound:Active() and Sound:Custom()) then
        return
    end
    if issecretvalue and issecretvalue(kit) then
        -- The game hid which tier it picked, so the addon can't follow it. Let the game play its own.
        if C_CombatAudioAlert.SetCategoryVolume then
            pcall(C_CombatAudioAlert.SetCategoryVolume, Enum.CombatAudioAlertCategory.PlayerHealthPulse, settings().soundVolume or 100)
        end
        Sound.hidden = true
        return
    end
    if playing and playing.kit == kit then
        return
    end
    Sound:StopOurs()
    if kit then
        start(kit)
    end
end

function Sound:Active()
    local s = settings()
    return s.enabled and s.sound and true or false
end

-- Hooks the game's pulse once, after its manager has loaded.
function Sound:Hook()
    if self.hooked or not _G.CombatAudioAlertManager then
        return
    end
    self.hooked = true
    hooksecurefunc(CombatAudioAlertManager, "SetHealthPulseSoundKit", onPulse)
    hooksecurefunc(CombatAudioAlertManager, "StopHealthPulse", function()
        if not (playing and playing.kit) then
            return
        end
        -- SetHealthPulseSoundKit stops the old pulse before it starts a new one, and its own hook then
        -- starts ours again, so this only ends ours for good on a loading screen.
        Sound:StopOurs()
    end)
end

-- Plays your sound for your threshold for a few seconds, on your output at your volume.
function Sound:Test()
    local kits = _G.CombatAudioAlertPulseSoundData
    local kit = kits and kits[self:StepPercent()]
    if not kit then
        CRT:Print("This client has no low-health pulse sound.")
        return
    end
    self:StopOurs()
    start(kit)
    C_Timer.After(TEST_SECONDS, function()
        if playing and playing.kit == kit then
            Sound:StopOurs()
        end
    end)
end

-- Lines for /crt lowhp info.
function Sound:Info()
    return format("sound: setting %s, available %s, CAAEnabled %s, pulse %s (under %d%%), saved settings %s, sound %s, output %s, addon plays it %s, hooked %s%s",
        tostring(settings().sound), tostring(self:Available()), tostring(getCVar(ENABLED)), tostring(getCVar(PULSE)),
        self:StepPercent(), tostring(settings().caaSaved ~= nil), tostring(settings().soundChoice), tostring(settings().soundChannel),
        tostring(self:Custom()), tostring(self.hooked and true or false), self.hidden and ", the game hid the tier so it played its own" or "")
end
