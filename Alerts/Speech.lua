local ADDON, CRT = ...

-- The speech queue: every block's spoken lines play one at a time through the game's text to speech.
-- A line plays until the game says it finished (or SPEECH_TIMEOUT seconds pass), then the next starts.
-- When the queue falls behind, the lowest priority line is dropped first: raid-wide lines go first,
-- your note lines are kept longer, and your reminders are kept longest. Speech plays only while the
-- Raid Notes Text to Speech switch is on. A line's sound cue plays once at zero, whatever that switch says.

local Rules = CRT.AlertRules
local Alerts = CRT.Alerts

local TICK = 0.1
local SOUND_LATE = 1  -- a sound whose time passed more than this many seconds ago is not played

-- The sounds an alert can play: the choices in the editor, from the game's own sound kit names.
-- A name this client does not have is left out.
local SOUND_NAMES = {
    { "RAID_WARNING", "Raid warning" },
    { "READY_CHECK", "Ready check" },
    { "ALARM_CLOCK_WARNING_3", "Alarm clock" },
    { "UI_BNET_TOAST", "Toast" },
    { "IG_PLAYER_INVITE", "Invite" },
    { "MAP_PING", "Map ping" },
    { "IG_QUEST_LIST_OPEN", "Quest list" },
    { "IG_MAINMENU_OPTION_CHECKBOX_ON", "Checkbox" },
}

local Speech = {
    queue = {},     -- items waiting, oldest first
    spoken = {},    -- keys Rules.SpeechDue has already handled
    playing = false,
    playingUntil = 0,
    runId = nil,
}
CRT.AlertSpeech = Speech

Speech.SOUNDS = {}  -- { { key, label, kit } }, in the order above
for _, def in ipairs(SOUND_NAMES) do
    local kit = SOUNDKIT and SOUNDKIT[def[1]]
    if kit then
        Speech.SOUNDS[#Speech.SOUNDS + 1] = { key = def[1], label = def[2], kit = kit }
    end
end

local function soundKit(key)
    for _, s in ipairs(Speech.SOUNDS) do
        if s.key == key then return s.kit end
    end
end

local function settings()
    local notes = CRT.db and CRT.db.notes
    return notes and notes.alert or {}
end

local function voiceId()
    if C_TTSSettings and C_TTSSettings.GetVoiceOptionID then
        local voiceType = (Enum and Enum.TtsVoiceType and Enum.TtsVoiceType.Standard) or 0
        local ok, id = pcall(C_TTSSettings.GetVoiceOptionID, voiceType)
        if ok and type(id) == "number" then
            return id
        end
    end
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and type(voices) == "table" and voices[1] then
            return voices[1].voiceID
        end
    end
    return nil
end

-- Speaks now, outside the queue (the Test speech button uses this).
function Speech:SpeakNow(text)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then
        CRT:Print("Text to speech isn't available on this client.")
        return
    end
    local id = voiceId()
    if not id then
        CRT:Print("No text to speech voice is installed. Check the game's Text to Speech settings.")
        return
    end
    local s = settings()
    local ok, err = pcall(C_VoiceChat.SpeakText, id, text, s.ttsRate or 0, s.ttsVolume or 100, false)
    if not ok then
        CRT:Print("Text to speech failed: " .. tostring(err))
    end
end

-- A new run: nothing from the last one is waiting or marked.
function Speech:Reset()
    wipe(self.queue)
    wipe(self.spoken)
    self.playing = false
    self.playingUntil = 0
end

-- Oldest first; at the same time the higher priority goes first, then arrival order.
local function before(a, b)
    if a.at ~= b.at then return a.at < b.at end
    if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
    return a.seq < b.seq
end

local arrivals = 0

function Speech:Tick(now)
    if not Alerts.running then
        if #self.queue > 0 or next(self.spoken) then
            self:Reset()
        end
        self.runId = nil
        return
    end
    if self.runId ~= Alerts.runId then
        self:Reset()
        self.runId = Alerts.runId
    end
    local lines = Alerts:Lines(now)

    -- Sound cues, keyed like speech so a line never plays twice.
    for _, line in ipairs(lines) do
        if line.sound and line.at <= now then
            local key = tostring(line.id) .. "#sound"
            if not self.spoken[key] then
                self.spoken[key] = true
                local kit = soundKit(line.sound)
                if kit and now - line.at <= SOUND_LATE then
                    CRT:PlaySound(kit)
                end
            end
        end
    end

    if not settings().tts then
        return
    end

    local due = Rules.SpeechDue(lines, now, self.spoken)
    if #due > 0 then
        local noteOn = settings().enabled
        for _, item in ipairs(due) do
            -- The raid note's speech also follows the alert switch (checked live); an empty or unreadable
            -- text is skipped.
            local text = item.text
            local readable = not (CRT.Timeline and CRT.Timeline.readable) or CRT.Timeline.readable(text)
            if readable and type(text) == "string" and text ~= "" and (item.block ~= "note" or noteOn) then
                arrivals = arrivals + 1
                item.seq = arrivals
                item.text = text
                self.queue[#self.queue + 1] = item
            end
        end
        table.sort(self.queue, before)
    end
    Rules.Behind(self.queue, now)

    if self.playing and now >= self.playingUntil then
        self.playing = false
    end
    if not self.playing and self.queue[1] then
        local item = table.remove(self.queue, 1)
        self.playing = true
        self.playingUntil = now + Rules.SPEECH_TIMEOUT
        self:SpeakNow(item.text or "")
    end
end

local elapsed = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < TICK then
        return
    end
    elapsed = 0
    if Alerts.running or #Speech.queue > 0 then
        Speech:Tick(GetTime())
    end
end)

-- Only the event itself matters: the speaker is free again. If this client does not know the event,
-- the timeout above keeps the queue moving.
-- This event can fire for any game speech, not only ours, so the timeout is the real guard.
driver:SetScript("OnEvent", function()
    Speech.playing = false
    if Alerts.running then
        Speech:Tick(GetTime())
    end
end)
pcall(driver.RegisterEvent, driver, "VOICE_CHAT_TTS_PLAYBACK_FINISHED")
