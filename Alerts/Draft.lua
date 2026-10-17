local ADDON, CRT = ...

-- The alert draft: the fields an alert is edited as, and how a draft becomes one of your reminders. No
-- frames here, so the pop-out editor (Alerts/Editor.lua) and the Mech Alerts panel (Notes/Reminders.lua)
-- share one copy of it.
--   ctx    where the draft came from: { encounterID, id (a reminder) and reminder (its saved copy) },
--          and for the editor also a note line (noteID, line, expected) or a saved alert (savedMode)
--   draft  { saveAs, tag, difficulty, ph, timeText, timeTouched, keptTimes, spellID, iconType, iconID,
--          text, color, show = { alert, text, icon, bar, circle }, speak, count, glow, sound, warn,
--          linger, boss, baseDifficulty, difficultyTouched }
-- Every function takes ctx and the draft it works on; none keeps either.
-- A cooldown dropped on the Timeline (or placed from its menu) is saved at once, without the editor:
-- Draft.PlaceCooldown, with Draft.CooldownDefaults (the one place those are set). A note line, from the
-- editor or a drop, is written by Draft.SaveNote.

local Reminders = CRT.AlertReminders

local Draft = {}
CRT.AlertDraft = Draft

-- The messages a check or a save can give. Keep the keys, change the text in quotes.
local TEXT = {
    keptBad = "The saved times don't read (%s). Type a time to replace them.",
    nothing = "Tick a Show as box, Speak the text or Count down: a sound alone shows nothing.",
    noTime = "Type a time.",
    badTime = "bad time '%s'",
    noEncounter = "Pick a boss first: this alert has no boss to be saved for.",
    saveFailed = "The reminder could not be saved.",
    stale = "This note line was changed elsewhere, such as by a new share. Close the editor and open it again.",
    noBoss = "This boss has no encounter ID, so it can't have a raid note line.",
    noteFailed = "The note line could not be saved.",
}
Draft.TEXT = TEXT

local SHOW_KEYS = { "alert", "text", "icon", "bar", "circle" }
Draft.SHOW_KEYS = SHOW_KEYS
local DEFAULT_WARN = 5

-- A cooldown placed from the Timeline's Cooldowns row: shown as Text only and read out, from this many
-- seconds ahead, gone at once (Linger), in the default colour. Draft.CooldownDefaults gives them.
local COOLDOWN_WARN = 5
local COOLDOWN_LINGER = 0

function Draft.trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
local trim = Draft.trim

function Draft.copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = Draft.copy(x)
    end
    return out
end
local copy = Draft.copy

function Draft.readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

function Draft.validID(v)
    return type(v) == "number" and v > 0 and v or nil
end
local validID = Draft.validID

-- The time rule of Reminders.ParseTimes ("1:30" or "90"), plus plain seconds with a fraction.
function Draft.parseTime(text)
    text = trim(text)
    local t = CRT.TimelineReference.ParseTime(text)
    if not t and text:match("^%d+%.%d+$") then
        t = tonumber(text)
    end
    return t
end
local parseTime = Draft.parseTime

function Draft.words(s)
    local out = {}
    for word in tostring(s or ""):gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

-- Whether you may change the raid note now, and the reason when not. Asked again at every write, so
-- a promotion or demotion while an alert is open counts.
function Draft.CanEditRaid()
    local Notes = CRT.Notes
    if not (Notes and Notes.CanEditRaid) then
        return false
    end
    local ok, why = Notes:CanEditRaid()
    if ok then
        return true
    end
    return false, why
end

-- Making drafts -------------------------------------------------------------------------------------

-- A new alert's draft: Only me, for everyone, the Next spell alert and a bar, read out, 5 s ahead.
function Draft.New()
    return { saveAs = "mine", tag = "everyone", ph = 1, timeText = "", timeTouched = false, iconType = "spell",
        text = "", show = { alert = true, bar = true }, speak = true, count = false, glow = false,
        warn = DEFAULT_WARN, linger = 0 }
end

-- A draft's Show as boxes and Read out choices as a reminder's outputs and speech (nil when neither
-- read out choice is ticked).
function Draft.Outputs(d)
    local outputs = {}
    for _, k in ipairs(SHOW_KEYS) do
        outputs[k] = d.show[k] and true or false
    end
    outputs.speech = (d.speak or d.count) and true or false
    local speech
    if d.speak and d.count then
        speech = "textcount"
    elseif d.speak then
        speech = "text"
    elseif d.count then
        speech = "count"
    end
    return outputs, speech
end

-- What a new alert starts with, as a template's fields (CRT.AlertSaved:Save): its Save as, For, outputs,
-- speech and warning time. A fresh table each call, from the same draft a new alert opens with.
function Draft.NewDefaults()
    local d = Draft.New()
    local outputs, speech = Draft.Outputs(d)
    return { saveAs = d.saveAs, tags = d.tag, outputs = outputs, speech = speech, warn = d.warn }
end

-- A saved reminder into the draft. Its times text is kept until Relative to or Time is touched.
function Draft.FromReminder(draft, r)
    draft.spellID, draft.boss, draft.difficulty = r.spellID, r.boss, r.difficulty
    draft.text = r.text or ""
    draft.keptTimes = r.times
    local o = r.outputs or {}
    for _, k in ipairs(SHOW_KEYS) do
        draft.show[k] = o[k] and true or false
    end
    local speaks = o.speech ~= false
    local mode = r.speech or "text"
    draft.speak = speaks and mode ~= "count"
    draft.count = speaks and (mode == "textcount" or mode == "count")
    draft.glow = r.glow and true or false
    draft.sound = r.sound
    draft.warn = r.warn or DEFAULT_WARN
    draft.linger = type(r.linger) == "number" and r.linger or 0
    draft.iconID = validID(r.iconID)
    draft.iconType = draft.iconID and "id" or "spell"
    draft.color = copy(r.color)
end

-- A new draft from a saved reminder.
function Draft.ForReminder(r)
    local d = Draft.New()
    Draft.FromReminder(d, r)
    d.baseDifficulty = d.difficulty
    return d
end

-- A new draft for a spell of a boss: named after the spell unless text is given.
function Draft.ForSpell(spellID, text, boss)
    local d = Draft.New()
    d.spellID = validID(spellID)
    if type(text) == "string" and trim(text) ~= "" then
        d.text = text
    else
        d.text = (d.spellID and Reminders.SpellName(d.spellID)) or ""
    end
    d.boss = boss
    return d
end

-- A For chosen before the draft opens (a cooldown assigned on the Timeline): a player's name as the note
-- line's tag, or "" for no one (the line then only shows in the timers window, and keeps that choice).
function Draft.ApplyFor(ctx, draft, tag)
    if type(tag) ~= "string" then
        return
    end
    draft.tag = trim(tag)
    if draft.tag == "" and ctx then
        ctx.untagged = true
    end
end

-- What a placed cooldown starts with, as draft fields: Show as Text only, Speak the text, no count,
-- glow or sound, Show from COOLDOWN_WARN, Linger COOLDOWN_LINGER, the default colour, the spell's own
-- icon. A fresh table each call. Not the editor's new-alert defaults (Draft.New): a cooldown has its own.
function Draft.CooldownDefaults()
    return { show = { alert = false, text = true, icon = false, bar = false, circle = false }, speak = true,
        count = false, glow = false, sound = nil, warn = COOLDOWN_WARN, linger = COOLDOWN_LINGER, color = nil,
        iconType = "spell" }
end

-- A new draft for a cooldown: its spell, named after the spell unless text is given, with the cooldown
-- defaults; Only me, for everyone, until the caller says otherwise.
function Draft.ForCooldown(spellID, text, boss)
    local d = Draft.ForSpell(spellID, text, boss)
    for k, v in pairs(Draft.CooldownDefaults()) do
        d[k] = v
    end
    d.iconID = nil
    return d
end

-- The cooldown defaults as a template's fields (CRT.AlertSaved:Save), for Save as template on a cooldown:
-- Only me, for everyone, Text, read out.
function Draft.CooldownTemplate()
    local d = Draft.ForCooldown(nil, nil, nil)
    local outputs, speech = Draft.Outputs(d)
    return { saveAs = d.saveAs, tags = d.tag, outputs = outputs, speech = speech, warn = d.warn,
        linger = d.linger, glow = d.glow or nil, sound = d.sound, color = copy(d.color) }
end

-- Checks ----------------------------------------------------------------------------------------------

-- The draft as reminder text fields, for Reminders:Times.
function Draft.TimesProbe(draft)
    return { times = draft.keptTimes, spellID = draft.spellID, text = draft.text, boss = draft.boss,
        difficulty = draft.difficulty }
end

-- Whether the draft still uses a saved reminder's own times: one being kept, or one moving to the raid
-- note with Relative to and Time untouched (it then becomes one note line per time).
function Draft.KeepsTimes(ctx, draft)
    if ctx and ctx.savedMode then
        return false
    end
    return not draft.timeTouched and (draft.saveAs == "mine" or (ctx ~= nil and ctx.id ~= nil))
end

-- The message for a time that does not read; `strict` (Save and Test) also asks a note line for one.
-- A reminder's kept times text is checked while Relative to and Time are untouched.
function Draft.TimeError(ctx, draft, strict)
    if ctx and ctx.savedMode then
        return nil -- a saved alert has no time
    end
    if Draft.KeepsTimes(ctx, draft) and draft.keptTimes then
        local list, err = Reminders.ParseTimes(draft.keptTimes)
        if not list then
            return string.format(TEXT.keptBad, tostring(err))
        end
        return nil
    end
    local text = trim(draft.timeText)
    if text == "" then
        return (strict and draft.saveAs == "note") and TEXT.noTime or nil
    end
    if not parseTime(text) then
        return string.format(TEXT.badTime, text)
    end
    return nil
end

-- Whether the draft shows or says anything.
function Draft.AnyOutput(draft)
    for _, k in ipairs(SHOW_KEYS) do
        if draft.show[k] then
            return true
        end
    end
    return draft.speak or draft.count
end

-- The first problem that stops the draft being saved, or nil.
function Draft.Problem(ctx, draft)
    local err = Draft.TimeError(ctx, draft, true)
    if err then
        return err
    end
    if not Draft.AnyOutput(draft) then
        return TEXT.nothing
    end
    return nil
end

-- As a reminder ---------------------------------------------------------------------------------------

-- The reminder's times text: the one it was saved with until Relative to or Time is touched.
local function reminderTimes(draft)
    if not draft.timeTouched then
        return draft.keptTimes
    end
    local t = parseTime(draft.timeText)
    if not t then
        return nil
    end
    return Reminders.FormatTimes({ { ph = draft.ph or 1, t = t } })
end

-- The draft as a reminder, laid over the saved one so its other fields (priority, enabled) stay.
function Draft.BuildReminder(ctx, draft)
    local r = copy(ctx and ctx.reminder or {})
    r.boss = draft.boss
    r.spellID = validID(draft.spellID)
    r.text = trim(draft.text)
    r.difficulty = draft.difficulty
    r.times = reminderTimes(draft)
    r.outputs = r.outputs or {}
    local outputs, speech = Draft.Outputs(draft)
    for k, on in pairs(outputs) do
        r.outputs[k] = on
    end
    if speech then
        r.speech = speech
    end
    r.warn = draft.warn
    r.linger = draft.linger > 0 and draft.linger or nil
    r.sound = draft.sound
    r.glow = draft.glow or nil
    r.iconID = draft.iconType == "id" and validID(draft.iconID) or nil
    r.color = copy(draft.color)
    return r
end

-- Whether the note line is still the one the draft was opened from.
function Draft.LineUnchanged(ctx)
    local _, raw = CRT.Notes:TimerAt(ctx.noteID, ctx.line)
    return raw ~= nil and raw == ctx.expected
end

-- Saves the draft as one of your reminders (ctx.id, or a new one). A note line moving to your
-- reminders is taken out of the raid note. Returns the reminder's id, or false and the message.
function Draft.SaveMine(ctx, draft)
    local encounterID = ctx.encounterID
    if encounterID == nil then
        return false, TEXT.noEncounter
    end
    if ctx.noteID then
        local allowed, why = Draft.CanEditRaid()
        if not allowed then
            return false, why
        end
        if not Draft.LineUnchanged(ctx) then
            return false, TEXT.stale
        end
    end
    local id = Reminders:Save(encounterID, ctx.id, Draft.BuildReminder(ctx, draft))
    if not id then
        return false, TEXT.saveFailed
    end
    if ctx.noteID then
        CRT.Notes:RemoveLine(ctx.noteID, ctx.line, ctx.expected)
    end
    return id
end

-- As a raid note line ----------------------------------------------------------------------------------

-- Text fit for a note line: no ";" (it ends a field) and no line ends.
function Draft.clean(s)
    return trim((tostring(s or ""):gsub(";", ""):gsub("[\r\n]+", " ")))
end
local clean = Draft.clean

-- The draft as a note line's timer (Parser.FormatLine writes it). A line keeps its dur:.
function Draft.NoteTimer(ctx, draft)
    local base = ctx and ctx.timer or {}
    local spellID = validID(draft.spellID)
    local text = clean(draft.text)
    local show = {}
    for _, k in ipairs(SHOW_KEYS) do
        show[k] = draft.show[k] or nil
    end
    return {
        time = parseTime(draft.timeText) or 0,
        ph = draft.ph or 1,
        tags = Draft.words(draft.tag),
        spellId = spellID,
        kind = spellID and "spell" or "text",
        text = text ~= "" and text or nil,
        dur = base.dur,
        color = copy(draft.color),
        show = show,
        tts = draft.speak or nil,
        count = draft.count or nil,
        sound = draft.sound,
        glow = draft.glow or nil,
        warn = draft.warn,
        linger = draft.linger > 0 and draft.linger or nil,
        iconID = draft.iconType == "id" and validID(draft.iconID) or nil,
    }
end

-- The fields of the raw line the draft was opened from that FormatLine doesn't write (such as
-- DisplayType:), kept on the end of the line written back.
function Draft.KeptFields(ctx)
    return ctx and ctx.expected and CRT.NoteParser.UnknownFields(ctx.expected) or ""
end

-- The times of a reminder moving to the raid note (Draft.KeepsTimes), or nil.
function Draft.KeptTimeList(ctx, draft)
    if Draft.KeepsTimes(ctx, draft) then
        local list = Reminders:Times(ctx.encounterID, Draft.TimesProbe(draft))
        if #list > 0 then
            return list
        end
    end
    return nil
end

-- The draft as note line timers: one per time of a reminder moving here (KeepsTimes), else one.
function Draft.NoteTimers(ctx, draft)
    local base = Draft.NoteTimer(ctx, draft)
    local list = Draft.KeptTimeList(ctx, draft)
    if list then
        local out = {}
        for i, e in ipairs(list) do
            local t = copy(base)
            t.ph, t.time = e.ph, e.t
            out[i] = t
        end
        return out
    end
    return { base }
end

local function lower(s)
    return trim(s):lower()
end

-- The raid difficulty you are in now, by the name a pull there gets (GetDifficultyInfo, as the engine
-- names it on ENCOUNTER_START), or nil outside a raid.
function Draft.CurrentDifficulty()
    if not GetInstanceInfo then
        return nil
    end
    local ok, _, kind, difficultyID, name = pcall(GetInstanceInfo)
    if not (ok and Draft.readable(kind) and kind == "raid") then
        return nil
    end
    if GetDifficultyInfo and Draft.readable(difficultyID) and type(difficultyID) == "number" then
        local okName, n = pcall(GetDifficultyInfo, difficultyID)
        if okName and Draft.readable(n) and type(n) == "string" and trim(n) ~= "" then
            return n
        end
    end
    if Draft.readable(name) and type(name) == "string" and trim(name) ~= "" then
        return name
    end
    return nil
end

-- The Difficulty a new raid note line starts on: that of the note the pull you are in would read, or,
-- outside a raid, of the boss's only note. Nil (Any) when there is no such note.
function Draft.DefaultDifficulty(encounterID)
    if type(encounterID) ~= "number" then
        return nil
    end
    local Notes = CRT.Notes
    local current = Draft.CurrentDifficulty()
    local id
    if current then
        id = Notes:FindForEncounter(encounterID, current)
    else
        for _, e in ipairs(Notes:List()) do
            if e.record.encounterID == encounterID then
                if id then
                    return nil
                end
                id = e.id
            end
        end
    end
    local record = id and Notes:Get(id)
    return record and record.difficulty or nil
end

-- The note a raid note line saved now goes to: the line's own note while its difficulty is unchanged,
-- else the one a pull of that difficulty reads (Notes:AddLine writes there). Nil: a new note is made.
function Draft.TargetNote(ctx, draft)
    if not (ctx and type(ctx.encounterID) == "number") then
        return nil
    end
    local difficulty = draft.difficulty and trim(draft.difficulty) or nil
    if ctx.noteID and lower(ctx.noteDifficulty) == lower(difficulty) then
        return ctx.noteID
    end
    return CRT.Notes:FindForEncounter(ctx.encounterID, difficulty)
end

-- Saves the draft as raid note lines: over the line it was opened from (ctx.noteID, line, expected)
-- while it stays in that note, else as new lines in the note the pull reads (a new note for the boss
-- when it has none), taking the old line or reminder (ctx.id) away once they are written. The raid
-- note is asked again here, and a line changed elsewhere is never overwritten. True, or false and the
-- message.
function Draft.SaveNote(ctx, draft)
    local allowed, why = Draft.CanEditRaid()
    if not allowed then
        return false, why
    end
    local encounterID = ctx.encounterID
    if type(encounterID) ~= "number" then
        return false, TEXT.noBoss
    end
    local Notes = CRT.Notes
    local extra = Draft.KeptFields(ctx)
    local lines = {}
    for i, t in ipairs(Draft.NoteTimers(ctx, draft)) do
        lines[i] = CRT.NoteParser.FormatLine(t) .. extra
    end
    local difficulty = draft.difficulty and trim(draft.difficulty) or nil
    if ctx.noteID then
        if not Draft.LineUnchanged(ctx) then
            return false, TEXT.stale
        end
        -- still going to its own note: the line is replaced where it is
        if Draft.TargetNote(ctx, draft) == ctx.noteID then
            if not Notes:ReplaceLine(ctx.noteID, ctx.line, lines[1], ctx.expected) then
                return false, TEXT.stale
            end
            return true
        end
    end
    -- a new line, or lines moving here from a reminder (one per time) or from another note. If one
    -- can't be written, the ones written are taken out again and the old alert stays as it was.
    local written = {}
    for _, line in ipairs(lines) do
        local id, n = Notes:AddLine(encounterID, difficulty, draft.boss, line)
        if not id then
            for i = #written, 1, -1 do
                Notes:RemoveLine(written[i].id, written[i].n, written[i].line)
            end
            return false, TEXT.noteFailed
        end
        written[#written + 1] = { id = id, n = n, line = line }
    end
    if ctx.noteID then
        Notes:RemoveLine(ctx.noteID, ctx.line, ctx.expected)
    elseif ctx.id then
        Reminders:Delete(encounterID, ctx.id)
    end
    return true
end

-- Placing a cooldown ------------------------------------------------------------------------------------

-- Saves cooldown spellID (named text, or the spell's name) for boss encounterID at once, at ph and
-- seconds into it, with the cooldown defaults. tag nil: one of your reminders (Only me); a name: a raid
-- note line for that player; "": a raid note line for no one. A true value (the reminder's id for Only
-- me), or false and the message.
function Draft.PlaceCooldown(encounterID, spellID, text, boss, ph, seconds, tag)
    local ctx = { encounterID = encounterID }
    local draft = Draft.ForCooldown(spellID, text, boss)
    draft.ph = type(ph) == "number" and ph or 1
    draft.timeText = ("%.10g"):format(type(seconds) == "number" and math.max(0, seconds) or 0)
    draft.timeTouched = true
    if type(tag) ~= "string" then
        return Draft.SaveMine(ctx, draft)
    end
    draft.saveAs = "note"
    Draft.ApplyFor(ctx, draft, tag)
    draft.difficulty = Draft.DefaultDifficulty(encounterID)
    return Draft.SaveNote(ctx, draft)
end

-- The Sound choices: None (key Draft.NO_SOUND, saved as no sound), then the speech module's sounds.
Draft.NO_SOUND = "none"
function Draft.SoundOptions(noneLabel)
    local out = { { key = Draft.NO_SOUND, label = noneLabel } }
    for _, s in ipairs(CRT.AlertSpeech and CRT.AlertSpeech.SOUNDS or {}) do
        out[#out + 1] = { key = s.key, label = s.label }
    end
    return out
end

-- The spell box --------------------------------------------------------------------------------------

-- A number typed in the Spell / Icon ID box: the spell, or in Icon ID mode the icon.
function Draft.SetID(draft, id)
    id = validID(id)
    if draft.iconType == "id" then
        draft.iconID = id
    else
        draft.spellID = id
    end
end

-- The icon a pick in Icon ID mode takes: the source's, else the game's when it reads as a number.
local function matchIcon(m)
    if type(m.icon) == "number" and m.icon > 0 then
        return m.icon
    end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, m.spellID)
        if ok and Draft.readable(tex) then
            return validID(tex)
        end
    end
end

-- A spell picked from a name lookup (CRT.AlertSpellLookup): the spell (or its icon) goes in the draft,
-- and text that was empty or only named the spell before (`before`) becomes the new spell's name; typed
-- text stays. Returns the ID for the box (nil when an icon could not be read) and the new text, if any.
function Draft.ApplyPick(draft, m, before)
    before = validID(before) or validID(draft.spellID)
    local beforeName = before and Reminders.SpellName(before)
    local text = trim(draft.text)
    local id, newText
    if draft.iconType == "id" then
        id = matchIcon(m)
        if id then
            draft.iconID = id
        end
    else
        id = m.spellID
        draft.spellID = id
    end
    -- an icon alone leaves the text: it still names the alert's spell
    if draft.iconType ~= "id" and (text == "" or (beforeName and text == trim(beforeName))) then
        draft.text = m.name
        newText = m.name
    end
    return id, newText
end
