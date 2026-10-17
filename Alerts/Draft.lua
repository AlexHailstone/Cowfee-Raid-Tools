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
}
Draft.TEXT = TEXT

local SHOW_KEYS = { "alert", "text", "icon", "bar", "circle" }
Draft.SHOW_KEYS = SHOW_KEYS
local DEFAULT_WARN = 5

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
