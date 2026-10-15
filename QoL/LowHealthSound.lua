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
-- Otherwise the game's pulse still runs, muted (its volume set to 1%), and the addon follows it: the
-- game calls CombatAudioAlertManager:SetHealthPulseSoundKit(kit) when the pulse starts, changes tier
-- or stops (kit nil), and StopHealthPulse on a loading screen. A hook on those plays your choice through
-- your channel instead, so your health is never read by the addon. The game's pulse kits loop by
-- themselves; the other sounds repeat, faster at each lower 10% tier, until the pulse stops.
--
-- Where the sounds come from (Sound.Choices):
--   * the game's pulse and game alert sounds (sound kits), played with C_Sound.PlaySoundWithOptions,
--     which takes your volume
--   * sounds other addons share through LibSharedMedia-3.0 (List("sound") and Fetch("sound", name)),
--     when one of them loaded it; the library is not shipped
--   * your own .ogg or .mp3 files in Interface\AddOns\CowfeeRaidTools\Sounds, added by name on the
--     Quality of Life page, since the game can't list a folder. A file must be there before you log in
--     or /reload. Updating the addon by replacing its folder removes them, so keep a copy.
-- Files play with PlaySoundFile(path, channel), which has no volume of its own: they follow the
-- channel's volume.
--
-- Play once (soundOnce, on by default): any sound other than the game's pulse plays one time, in full,
-- each time your health drops under the threshold; dropping into a lower 10% tier during the same dip
-- doesn't play it again. Off, it repeats, faster at each lower tier, each repeat stopping the one
-- before. The game's pulse is a loop by nature and keeps looping either way.

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
-- The game's pulse volume while the addon plays yours. Not 0: at 0 the game plays nothing, so it never
-- starts the timer that ends its own 3-second volume preview, and the addon's copy of that preview
-- was never told to stop. At 1% the game plays and ends it as usual.
local MUTED_VOLUME = 1
local SOUNDS_FOLDER = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\"

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

-- LibSharedMedia-3.0, if another addon loaded it.
local function sharedMedia()
    if not LibStub then
        return nil
    end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibSharedMedia-3.0", true)
    return ok and lib or nil
end

-- Every sound to choose from: the game's, then shared ones, then your own files. Read each time the
-- menu opens, so sounds shared by other addons appear.
function Sound.Choices()
    local out = {}
    for _, c in ipairs(Sound.CHOICES) do
        out[#out + 1] = c
    end
    local lib = sharedMedia()
    if lib then
        local ok, list = pcall(lib.List, lib, "sound")
        if ok and type(list) == "table" then
            for _, name in ipairs(list) do
                if name ~= "None" then
                    out[#out + 1] = { key = "lsm:" .. name, label = name .. " (shared)" }
                end
            end
        end
    end
    for _, file in ipairs(CRT.db.qol.lowHealth.customSounds or {}) do
        out[#out + 1] = { key = "file:" .. file, label = file .. " (yours)" }
    end
    return out
end

-- What a choice plays: { kind = "pulse" }, { kind = "kit", id } or { kind = "file", path }, or nil
-- when it is gone (a shared sound whose addon isn't loaded).
local function resolve(choice)
    choice = choice or "pulse"
    if choice == "pulse" then
        return { kind = "pulse" }
    end
    local shared = choice:match("^lsm:(.+)$")
    if shared then
        local lib = sharedMedia()
        local ok, path = false, nil
        if lib then
            ok, path = pcall(lib.Fetch, lib, "sound", shared, true)
        end
        if ok and path then
            return { kind = "file", path = path }
        end
        return nil
    end
    local file = choice:match("^file:(.+)$")
    if file then
        return { kind = "file", path = SOUNDS_FOLDER .. file }
    end
    local c = choiceByKey[choice]
    if c then
        return { kind = "kit", id = (SOUNDKIT and SOUNDKIT[c.key]) or c.id }
    end
    return nil
end
Sound.Resolve = resolve

-- Adds one of your own sound files by name. Returns ok, message.
function Sound:AddCustom(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return false, "Type the file's name, such as airhorn.ogg."
    end
    if name:find("[/\\]") then
        return false, "Just the file name, without a folder."
    end
    if not (name:lower():find("%.ogg$") or name:lower():find("%.mp3$")) then
        return false, "The game plays .ogg and .mp3 files."
    end
    local list = CRT.db.qol.lowHealth.customSounds
    for _, existing in ipairs(list) do
        if existing:lower() == name:lower() then
            return false, name .. " is already in the list."
        end
    end
    list[#list + 1] = name
    return true, "Added " .. name .. ". If you just copied it into the Sounds folder, /reload first so the game can find it."
end

function Sound:RemoveCustom(name)
    local list = CRT.db.qol.lowHealth.customSounds
    for i, existing in ipairs(list) do
        if existing == name then
            table.remove(list, i)
            if CRT.db.qol.lowHealth.soundChoice == "file:" .. name then
                CRT.db.qol.lowHealth.soundChoice = "pulse"
            end
            return true
        end
    end
    return false
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
        self:StopAll()
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
    setPulseVolume(custom and MUTED_VOLUME or (s.soundVolume or 100))
end

-- True when the addon plays the sound: any sound or output other than the game's pulse on its own.
function Sound:Custom()
    local s = settings()
    return (s.soundChoice or "pulse") ~= "pulse" or (s.soundChannel or "game") ~= "game"
end

-- Playing your sound -----------------------------------------------------------------------------

-- Two kinds of playing, kept apart so a stop always finds its sound:
--   following  the addon's copy of the game's pulse, started and stopped by the game's own calls
--   preview    a Play button or Test sound, which ends by itself after PREVIEW_SECONDS
-- Each holds every handle, repeat ticker and timer it started, and stopping one stops all of them.
-- A sound played once is never cut short: when its preview ends it keeps playing to its end, and its
-- handle waits in lingering so Stop and /crt lowhp stop can still stop it.

local following, preview
local lingering = {}

local function stopEntry(entry)
    if not entry then
        return
    end
    for _, handle in ipairs(entry.handles) do
        pcall(StopSound, handle)
    end
    if entry.ticker then
        entry.ticker:Cancel()
    end
    if entry.timer then
        entry.timer:Cancel()
    end
end

-- The channel for an output key: "game" is the game's voice output, like its pulse.
local function channelFor(output)
    output = output or settings().soundChannel or "game"
    return output == "game" and "Voice" or output
end

-- Plays a sound on an output, adding its handle to the entry. A kit plays at your volume; a file plays
-- at the channel's volume (on Master for Game default, since files can't use the game's voice output).
-- With replace, it stops the sound the entry played before (a repeat cuts off the one before it).
local function play(entry, source, output, replace)
    local handle
    if source.kind == "file" then
        local channel = channelFor(output)
        if channel == "Voice" then
            channel = "Master"
        end
        local ok, willPlay, h = pcall(PlaySoundFile, source.path, channel)
        handle = ok and willPlay and h or nil
    else
        local volume = (settings().soundVolume or 100) / 100
        if C_Sound and C_Sound.PlaySoundWithOptions then
            local ok, success, h = pcall(C_Sound.PlaySoundWithOptions, { soundKitID = source.id, uiSoundSubType = channelFor(output), volumeOverride = volume })
            if ok and success then
                handle = h
            end
        end
        if not handle then
            local ok, willPlay, h = pcall(PlaySound, source.id, channelFor(output))
            handle = ok and willPlay and h or nil
        end
    end
    if not handle then
        return
    end
    if replace and entry.last then
        pcall(StopSound, entry.last)
    end
    entry.last = handle
    entry.handles[#entry.handles + 1] = handle
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

-- Starts a choice for a game pulse kit: the same looping kit on the output, or the chosen sound, played
-- once in full (Play once), or repeating every 2.4 seconds at 90% down to every 0.8 seconds at 10%.
-- A choice that is gone (a shared sound whose addon isn't loaded) falls back to the game's pulse.
local function begin(kit, choice, output)
    local entry = { kit = kit, handles = {} }
    local source = resolve(choice or settings().soundChoice)
    if not source or source.kind == "pulse" then
        play(entry, { kind = "kit", id = kit }, output)
        return entry
    end
    play(entry, source, output, true)
    if settings().soundOnce ~= false then
        entry.once = true
        return entry
    end
    entry.ticker = C_Timer.NewTicker(0.6 + tierOf(kit) / 50, function()
        play(entry, source, output, true)
    end)
    return entry
end

function Sound:StopOurs()
    stopEntry(following)
    following = nil
end

function Sound:StopPreview()
    stopEntry(preview)
    preview = nil
end

local function stopLingering()
    for _, handle in ipairs(lingering) do
        pcall(StopSound, handle)
    end
    for i = #lingering, 1, -1 do
        lingering[i] = nil
    end
end

-- Stops every sound the addon is playing. The game's own pulse is left to the game.
function Sound:StopAll()
    self:StopOurs()
    self:StopPreview()
    stopLingering()
end

-- Following the game's pulse. The game re-decides its pulse every time your health changes
-- (ProcessUnitHealthChange -> UpdateHealthPulse -> SetHealthPulseSoundKit), passing the tier's sound
-- when you are under the threshold and nil when you are not. That decision is what the addon follows,
-- not whether the game's muted copy managed to play:
--   * Inside one call the game may stop its pulse and start it again (StopHealthPulse, then play), so
--     the addon notes each change and settles it once, at the end of the frame. Your sound keeps
--     playing through a restart of the same tier instead of starting over.
--   * The game's own 3-second volume preview (RefreshHealthPulseVolume) is not a real pulse, so a
--     decision made inside it is ignored. Its end, a StopHealthPulse, settles back to the last real one.
--   * A loading screen or death stops the game's pulse, and so yours.
local decided -- the kit the game last decided on, nil for no pulse
local fromPreview = false
local settling = false

local function settle()
    settling = false
    if fromPreview then
        fromPreview = false
        return
    end
    local kit = decided
    if following and following.kit == kit then
        return
    end
    -- Played once: a lower tier in the same dip doesn't play it again, and it is never cut short.
    if following and following.once and kit then
        following.kit = kit
        return
    end
    if following and following.once and not kit then
        -- Healed: the next dip plays it again. The sound itself finishes on its own.
        for _, handle in ipairs(following.handles) do
            lingering[#lingering + 1] = handle
        end
        following = nil
        return
    end
    Sound:StopOurs()
    if kit and Sound:Active() and Sound:Custom() then
        following = begin(kit)
    end
end

local function changed()
    if not settling then
        settling = true
        C_Timer.After(0, settle)
    end
end

local function onPulse(_, kit)
    if not (Sound:Active() and Sound:Custom()) then
        return
    end
    if issecretvalue and issecretvalue(kit) then
        -- The game hid which tier it picked, so the addon can't follow it. Let the game play its own.
        setPulseVolume(settings().soundVolume or 100)
        Sound.hidden = true
        return
    end
    decided = kit
    changed()
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
        decided = nil
        changed()
    end)
    if CombatAudioAlertManager.RefreshHealthPulseVolume then
        hooksecurefunc(CombatAudioAlertManager, "RefreshHealthPulseVolume", function()
            -- Runs after the preview's own SetHealthPulseSoundKit, in the same frame, before it settles.
            fromPreview = true
        end)
    end
end

-- Plays a choice on an output for PREVIEW_SECONDS, at the tier of your threshold. Calling it again for
-- the same choice and output while it plays stops it. onStop, if given, is called when it ends.
function Sound:Preview(choice, output, onStop)
    local key = tostring(choice) .. "|" .. tostring(output)
    local wasPlaying = preview and preview.key == key
    self:StopPreview()
    if wasPlaying then
        return false
    end
    local kits = _G.CombatAudioAlertPulseSoundData
    local kit = kits and kits[self:StepPercent()]
    if not kit then
        CRT:Print("This client has no low-health pulse sound.")
        return false
    end
    preview = begin(kit, choice, output)
    preview.key = key
    local mine = preview
    preview.timer = C_Timer.NewTimer(PREVIEW_SECONDS, function()
        if preview == mine then
            if mine.once then
                -- Played once: let it finish, but keep it stoppable.
                for _, handle in ipairs(mine.handles) do
                    lingering[#lingering + 1] = handle
                end
                preview = nil
            else
                Sound:StopPreview()
            end
        end
        if onStop then
            onStop()
        end
    end)
    return true
end

function Sound:IsPreviewing(choice, output)
    return preview ~= nil and preview.key == (tostring(choice) .. "|" .. tostring(output))
end

-- Test sound: your current choice on your current output.
function Sound:Test(onStop)
    local s = settings()
    return self:Preview(s.soundChoice or "pulse", s.soundChannel or "game", onStop)
end

-- Lines for /crt lowhp info.
function Sound:Info()
    return format("sound: setting %s, available %s, CAAEnabled %s, pulse %s (under %d%%), saved settings %s, sound %s, output %s, addon plays it %s, hooked %s%s",
        tostring(settings().sound), tostring(self:Available()), tostring(getCVar(ENABLED)), tostring(getCVar(PULSE)),
        self:StepPercent(), tostring(settings().caaSaved ~= nil), tostring(settings().soundChoice), tostring(settings().soundChannel),
        tostring(self:Custom()), tostring(self.hooked and true or false), self.hidden and ", the game hid the tier so it played its own" or "")
end
