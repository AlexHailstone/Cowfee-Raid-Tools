local ADDON, CRT = ...

-- The low-health sound: the game's own low-health pulse, from its Combat Audio Alerts (Options >
-- Accessibility). An addon can't play a sound for low health itself in Midnight, because your health
-- is a secret value and choosing to play a sound would mean comparing it. The game's pulse compares
-- it for us: it plays a sound while your health is under a threshold.
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
-- Your choice of sound: the game decides the pulse from your health and passes that decision as a
-- secret value, which no addon can read (seen in game on 2026-10-15), so the addon can't play a sound
-- of its own at the right moment. Instead it swaps the sound inside the game's pulse: the game reads
-- CombatAudioAlertPulseSoundData[tier] each time it starts the pulse (Blizzard's CombatAudioAlertUtil
-- says it does this "so addons can substitute their own sounds"), so every tier is set to your sound
-- and the game plays it itself, on its own output. Only game sounds (sound kits) can go there.
-- Blizzard's own CombatAudioAlertUtil.SetPulseHealthSoundKit also re-runs the game's health check
-- straight away, which would then run as addon code, so the table is written directly instead and the
-- game picks it up at the next health change.
--
-- With one sound on every tier, a game alert sound plays once each time you drop under the threshold:
-- the game only starts a new sound when the tier's sound changes. The game's own pulse sounds loop and
-- speed up at each lower tier.

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
local PREVIEW_SECONDS = 3

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

local function settings()
    return CRT.db.qol.lowHealth
end

-- The sound kit for a choice, or nil for the game's own pulse (and for choices from 0.14.0 test
-- builds, such as shared sounds and your own files, which can't go into the game's pulse).
local function kitFor(choice)
    local c = choiceByKey[choice or settings().soundChoice or "pulse"]
    if not c or c.key == "pulse" then
        return nil
    end
    return (SOUNDKIT and SOUNDKIT[c.key]) or c.id
end

-- The game's settings ------------------------------------------------------------------------------

local function getCVar(name)
    if not (C_CVar and C_CVar.GetCVar) then
        return nil
    end
    local ok, value = pcall(C_CVar.GetCVar, name)
    return ok and value or nil
end

local function setCVar(name, value)
    if value == nil or not (C_CVar and C_CVar.SetCVar) then
        return
    end
    -- Only when it differs: every change makes the game refresh its pulse, and a volume change makes it
    -- play a 3-second preview.
    if getCVar(name) ~= tostring(value) then
        pcall(C_CVar.SetCVar, name, tostring(value))
    end
end

local function setPulseVolume(volume)
    if not (C_CombatAudioAlert and C_CombatAudioAlert.SetCategoryVolume) then
        return
    end
    local category = Enum.CombatAudioAlertCategory.PlayerHealthPulse
    local ok, current = pcall(C_CombatAudioAlert.GetCategoryVolume, category)
    if ok and current == volume then
        return
    end
    pcall(C_CombatAudioAlert.SetCategoryVolume, category, volume)
end

local function sayIfTargeted()
    return Enum and Enum.CombatAudioAlertSpecSetting and Enum.CombatAudioAlertSpecSetting.SayIfTargeted
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
    if saved.volume ~= nil then
        setPulseVolume(saved.volume)
    end
    setCVar(PULSE, saved[PULSE])
    setCVar(ENABLED, saved[ENABLED])
    s.caaSaved = nil
end

-- Your sound inside the game's pulse ---------------------------------------------------------------

local originalKits -- the game's own pulse sounds per tier, copied before the first swap
local swapped -- the sound kit now in every tier, or nil

-- Puts a sound kit in every tier of the game's pulse, or the game's own sounds back for nil. Each slot
-- is only written when it differs.
local function setKits(kit)
    local data = _G.CombatAudioAlertPulseSoundData
    if type(data) ~= "table" then
        return
    end
    if kit and not originalKits then
        originalKits = {}
        for percent, id in pairs(data) do
            originalKits[percent] = id
        end
    end
    if not originalKits then
        return
    end
    for percent, id in pairs(originalKits) do
        local want = kit or id
        if data[percent] ~= want then
            data[percent] = want
        end
    end
    swapped = kit
end

-- Matches the game to the settings: Combat Audio Alerts on with only the pulse, at your threshold and
-- volume, with your sound in it, while the low-health alert and its sound are both ticked. Off, every
-- game setting and the game's own sounds go back.
function Sound:Apply()
    if not self:Available() then
        return
    end
    local s = settings()
    if not (s.enabled and s.sound) then
        self:StopAll()
        setKits(nil)
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
    setKits(kitFor(s.soundChoice))
    setCVar(ENABLED, 1)
    setCVar(PULSE, pulseValue())
    setPulseVolume(s.soundVolume or 100)
end

-- Trying a sound ----------------------------------------------------------------------------------
-- A Play button in the Sound menu, or Test sound, plays a sound the way the game's pulse will: on the
-- game's voice output at your volume. The game's pulse at your threshold's tier loops, so it stops
-- after PREVIEW_SECONDS; an alert sound plays once and is never cut short, but stays stoppable.

local preview -- { key, handles, timer, onStop, once }
local lingering = {}

local function playKit(kit)
    local volume = (settings().soundVolume or 100) / 100
    if C_Sound and C_Sound.PlaySoundWithOptions then
        local ok, success, handle = pcall(C_Sound.PlaySoundWithOptions, { soundKitID = kit, uiSoundSubType = "Voice", volumeOverride = volume })
        if ok and success then
            return handle
        end
    end
    local ok, willPlay, handle = pcall(PlaySound, kit, "Dialog")
    return ok and willPlay and handle or nil
end

function Sound:StopPreview()
    local ended = preview
    if ended then
        for _, handle in ipairs(ended.handles) do
            pcall(StopSound, handle)
        end
        if ended.timer then
            ended.timer:Cancel()
        end
    end
    preview = nil
    if ended and ended.onStop then
        ended.onStop()
    end
end

-- Stops every sound the addon is playing (previews). The game's own pulse is left to the game.
function Sound:StopAll()
    self:StopPreview()
    for _, handle in ipairs(lingering) do
        pcall(StopSound, handle)
    end
    for i = #lingering, 1, -1 do
        lingering[i] = nil
    end
end

-- Plays a choice once (or the game's pulse for PREVIEW_SECONDS). Calling it again for the same choice
-- while it plays stops it. onStop, if given, is called however it ends. Returns true when it started.
function Sound:Preview(choice, onStop)
    local key = tostring(choice)
    local wasPlaying = preview and preview.key == key
    self:StopPreview()
    if wasPlaying then
        return false
    end
    local kit = kitFor(choice)
    local once = kit ~= nil
    if not kit then
        local kits = originalKits or _G.CombatAudioAlertPulseSoundData
        kit = kits and kits[self:StepPercent()]
    end
    if not kit then
        CRT:Print("This client has no low-health pulse sound.")
        return false
    end
    local handle = playKit(kit)
    if not handle then
        CRT:Print("The game didn't play that sound. Check the Dialog volume (voice output) in the game's Sound settings.")
        return false
    end
    local mine = { key = key, handles = { handle }, once = once, onStop = onStop }
    preview = mine
    mine.timer = C_Timer.NewTimer(PREVIEW_SECONDS, function()
        if preview ~= mine then
            return
        end
        if mine.once then
            -- Played once: let it finish, but keep it stoppable.
            lingering[#lingering + 1] = handle
            preview = nil
            if onStop then
                onStop()
            end
        else
            Sound:StopPreview()
        end
    end)
    return true
end

function Sound:IsPreviewing(choice)
    return preview ~= nil and preview.key == tostring(choice)
end

-- Test sound: your current choice.
function Sound:Test(onStop)
    return self:Preview(settings().soundChoice or "pulse", onStop)
end

-- Diagnostics -------------------------------------------------------------------------------------
-- A read-only hook counts the game's pulse decisions, for /crt lowhp info.

local seen = { decisions = 0, readable = 0, last = "none yet" }

local function hook()
    local manager = _G.CombatAudioAlertManager
    if Sound.hooked or not manager then
        return
    end
    Sound.hooked = true
    hooksecurefunc(manager, "SetHealthPulseSoundKit", function(_, kit)
        seen.decisions = seen.decisions + 1
        if issecretvalue and issecretvalue(kit) then
            seen.last = "hidden (secret)"
        else
            seen.readable = seen.readable + 1
            seen.last = kit and ("sound " .. tostring(kit)) or "no pulse"
        end
    end)
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", hook)

-- Lines for /crt lowhp info.
function Sound:Info()
    local enabled = "unknown"
    if C_CombatAudioAlert and C_CombatAudioAlert.IsEnabled then
        local ok, value = pcall(C_CombatAudioAlert.IsEnabled)
        enabled = ok and tostring(value) or "error"
    end
    local manager = _G.CombatAudioAlertManager
    local watching = "no manager"
    if manager then
        local lookup = manager.unitHealthUnitsLookup
        watching = type(lookup) == "table" and tostring(lookup.player ~= nil) or "unknown"
    end
    local data = _G.CombatAudioAlertPulseSoundData
    return format("sound: setting %s, available %s, CAAEnabled %s, pulse %s (under %d%%), saved settings %s, sound %s, in the game's pulse %s (tier %d holds %s)",
        tostring(settings().sound), tostring(self:Available()), tostring(getCVar(ENABLED)), tostring(getCVar(PULSE)),
        self:StepPercent(), tostring(settings().caaSaved ~= nil), tostring(settings().soundChoice),
        swapped and tostring(swapped) or "the game's own", self:StepPercent(), tostring(data and data[self:StepPercent()]))
        .. format("\n  game: Combat Audio Alerts on %s, listening to your health %s, pulse decisions since login %d (%d readable), last decision %s",
            enabled, watching, seen.decisions, seen.readable, seen.last)
end
