local ADDON, CRT = ...

-- The alert editor: one popout window for every alert, a line of the boss's raid note or one of your
-- own reminders. It opens from Edit on the Reminders tab and from a double-click on the Timeline, edits
-- a draft, and saves it as a note line (Notes:AddLine or ReplaceLine, through Parser.FormatLine) or as
-- a reminder (CRT.AlertReminders). Switching Save as on a saved alert moves it: the new place is written
-- first, then the old one removed. A note line is only ever written back over the raw line it was
-- opened from, so a note changed elsewhere (a new share) is never overwritten blind.
-- Test runs the draft as it stands on screen without saving anything: its items go to a block of their
-- own ("minetest") that gives them out only to a run started with reason "test". A note line's item is
-- the note block's own (CRT.NoteEngine.ItemFor) and stays a "note" item, so the note's switches apply.
-- Export shows the draft as a note line in a copy box.
-- Only the raid leader or an assistant changes the raid note (CRT.Notes:CanEditRaid): for anyone else
-- Save as Raid note is greyed out, a new alert set to it opens as Only me, a note line opens read-only
-- (ctx.readOnly: nothing can be changed, no Save or Delete) with Export and Copy to my reminders, which
-- turns the draft into a new reminder of your own. Every raid note write asks CanEditRaid again.
-- Save as saved alert keeps the draft's setup, without its time, as a saved alert (CRT.AlertSaved), and
-- Open takes prefill.saved to start from one. EditSaved opens a saved alert itself: no Save as saved alert,
-- Export, Relative to, Time or Difficulty; Save overwrites it (keeping the name its chip gave it, and
-- making nothing once it was deleted), and Test previews it ten seconds ahead.

local TEXT = {
    title = "Alert",
    saveAs = "Save as",
    asNote = "Raid note",
    asMine = "Only me",
    forLabel = "For",
    everyone = "Everyone",
    noOne = "No one (timers window only)",
    me = "Me",
    tanks = "Tanks",
    healers = "Healers",
    damage = "Damage",
    melee = "Melee",
    ranged = "Ranged",
    group = "Group %d",
    difficulty = "Difficulty",
    any = "Any",
    normal = PLAYER_DIFFICULTY1 or "Normal",
    heroic = PLAYER_DIFFICULTY2 or "Heroic",
    mythic = PLAYER_DIFFICULTY6 or "Mythic",
    savesTo = "Saves to: %s",
    newNote = "a new note for this boss",
    noteName = "%s (%s)",
    relativeTo = "Relative to",
    pull = "Pull",
    phase = "Phase %s",
    time = "Time",
    timeHelpTitle = "Time",
    timeHelp = "Minutes:seconds or plain seconds, from the pull or from the start of the phase in "
        .. "Relative to: 1:30 or 90.\n\nA reminder with several times keeps them all until you change "
        .. "Relative to or Time.",
    showFrom = "Show from",
    linger = "Linger",
    seconds = "%d s",
    icon = "Icon",
    iconSpell = "Spell",
    iconID = "Icon ID",
    iconHelpTitle = "Icon",
    iconHelp = "Spell: type the spell's ID. The alert shows its icon and, with no text, its name.\n\n"
        .. "Icon ID: type an icon's file ID to show that icon instead.",
    text = "Text",
    color = "Color",
    colorDefault = "Default",
    showAs = "Show as",
    nextSpell = "Next spell alert",
    showText = "Text",
    showIcon = "Icon",
    bar = "Bar",
    circle = "Circle",
    also = "Also",
    speak = "Speak the text",
    count = "Count down 3 2 1",
    glow = "Glow at 0",
    sound = "Sound",
    none = "None",
    fromPrefix = "From ",
    timesPrefix = "Times: ",
    noTimes = "No times",
    delete = "Delete",
    deleteConfirm = "Delete this alert?",
    export = "Export",
    exportTitle = "Alert as a note line",
    test = "Test",
    save = "Save",
    saveAsSaved = "Save as saved alert",
    savedNamePrompt = "Name this saved alert:",
    savedAccept = ACCEPT or "Accept",
    savedTitle = "Saved alert: %s",
    savedTitleNew = "New saved alert",
    savedMade = "Saved alert \"%s\" saved.",
    deleteSavedConfirm = "Delete this saved alert?",
    savedFailed = "The saved alert could not be saved.",
    savedGone = "This saved alert was deleted, so there is nothing to save it to. Cancel to close.",
    cancel = CANCEL or "Cancel",
    testInPull = "Test is off during a pull.",
    testTrigger = "Nothing to test: this alert starts in phase %s, which waits for its trigger.",
    testBlock = "Alert test",
    saveFailed = "The reminder could not be saved.",
    noEncounter = "Pick a boss first: this alert has no boss to be saved for.",
    keptBad = "The saved times don't read (%s). Type a time to replace them.",
    nothing = "Tick a Show as box, Speak the text or Count down: a sound alone shows nothing.",
    noTime = "Type a time.",
    badTime = "bad time '%s'",
    noBoss = "This boss has no encounter ID, so it can't have a raid note line.",
    stale = "This note line was changed elsewhere, such as by a new share. Close the editor and open it again.",
    noteFailed = "The note line could not be saved.",
    reopen = "You can change the raid note now. Close this line and open it again to edit it.",
    noteLineTitle = "Raid note line",
    copyToMine = "Copy to my reminders",
}

local Alerts = CRT.Alerts
local Reminders = CRT.AlertReminders
local UI = CRT.UI

local Editor = {}
CRT.AlertEditor = Editor

local TEST_BLOCK = "minetest"
local TEST_LEAD = 10 -- a test starts this many seconds before the alert's first time
local ANY = "any"    -- the difficulty dropdown's key for "any difficulty" (saved as nil)
local NO_SOUND = "none"
local FRAME_NAME = "CowfeeRaidToolsAlertEditor"
local EXPORT_NAME = "CowfeeRaidToolsAlertExport"
local WIDTH, HEIGHT = 600, 480
local SHOW_KEYS = { "alert", "text", "icon", "bar", "circle" }
local LEFT = 16
local MENU_MAX_HEIGHT = 400 -- the For and Sound menus scroll past this (a full raid is taller than the screen)
local FIELD_X = 91 -- where the boxes and checkboxes of the labelled rows start
local SAVED_SHIFT = 48 -- a saved alert has no Relative to / Time row or Saves to line: the rows below move up by this
local ROW1_EXTRA = 14 -- room under the first row for the Saves to line; every row below moves down by it
local EXPORT_CHROME = 56 -- the copy window above and below its text box
local EXPORT_PAD, EXPORT_MIN_TEXT, EXPORT_MAX_TEXT = 6, 16, 180
local EXPORT_WIDTH = WIDTH - 88 -- the text box
local EXPORT_TEXT_WIDTH = EXPORT_WIDTH - 2 * EXPORT_PAD
local PREVIEW_INSET = 16 -- the editor Previews opens sits this far into the screen's bottom right corner

local POPUP_NAME = "COWFEE_RAID_TOOLS_SAVED_ALERT_NAME"

local frame, exportFrame
-- ctx: where the draft came from. { encounterID, id (a reminder) and reminder (its saved copy), or
-- noteID, line, expected (the raw line), timer, noteDifficulty, untagged and readOnly (opened by someone
-- who can't change the raid note) for a note line; or, for a
-- saved alert itself, savedMode, savedID (nil for a new one) and savedName }
local ctx
-- draft: the fields on screen. { saveAs, tag, difficulty, ph, timeText, timeTouched, keptTimes, spellID,
-- iconType, iconID, text, color, show = { alert, text, icon, bar, circle }, speak, count, glow, sound,
-- warn, linger, boss, baseDifficulty (a reminder's own), difficultyTouched }
local draft
local notice -- the message from the last Save, Test or Delete, shown until the draft changes
local testItems
local inCorner -- Previews put the editor in the corner, so closing it puts it back
local previewDraft -- the empty draft Previews opened, so Previews only ever closes that one

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(s)
    return trim(s):lower()
end

local function copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = copy(x)
    end
    return out
end

local function readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

-- Whether you may change the raid note now, and the reason when not. Asked again at every write, so
-- a promotion or demotion while the editor is open counts.
local function canEditRaid()
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

-- The reason Raid note is greyed out, from CRT.Notes:CanEditRaid (empty when you may change it).
local function notAdminReason()
    local _, why = canEditRaid()
    return why or ""
end

-- A raid note line opened by someone who can't change it: shown, never edited.
local function readOnly()
    return ctx ~= nil and ctx.readOnly == true
end

local function editable()
    return not readOnly()
end

local function validID(v)
    return type(v) == "number" and v > 0 and v or nil
end

-- "m:ss" for whole seconds; a note line's time with a fraction stays plain seconds.
local function clock(t, exact)
    if exact and t ~= math.floor(t) then
        return (("%.10g"):format(t))
    end
    t = math.floor(t + 0.5)
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

-- The time rule of Reminders.ParseTimes ("1:30" or "90"), plus plain seconds with a fraction.
local function parseTime(text)
    text = trim(text)
    local t = CRT.TimelineReference.ParseTime(text)
    if not t and text:match("^%d+%.%d+$") then
        t = tonumber(text)
    end
    return t
end

local function words(s)
    local out = {}
    for word in tostring(s or ""):gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

-- Text fit for a note line: no ";" (it ends a field) and no line ends.
local function clean(s)
    return trim((tostring(s or ""):gsub(";", ""):gsub("[\r\n]+", " ")))
end

local function spellInfo(id)
    id = validID(id)
    if not id then
        return nil, nil
    end
    local name = Reminders.SpellName(id)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex ~= nil and readable(tex) then
            icon = tex
        end
    end
    return name, icon
end

-- The draft as reminder text fields, for Reminders:Times.
local function timesProbe()
    return { times = draft.keptTimes, spellID = draft.spellID, text = draft.text, boss = draft.boss,
        difficulty = draft.difficulty }
end

-- The time the box shows for times kept from Stage 1: the first of the lowest phase.
local function firstTime(list)
    local ph, t
    for _, e in ipairs(list) do
        if not ph or e.ph < ph or (e.ph == ph and e.t < t) then
            ph, t = e.ph, e.t
        end
    end
    return ph, t
end

-- Whether the draft still uses a saved reminder's own times: one being kept, or one moving to the raid
-- note with Relative to and Time untouched (it then becomes one note line per time).
local function keepsTimes()
    if ctx and ctx.savedMode then
        return false
    end
    return not draft.timeTouched and (draft.saveAs == "mine" or (ctx ~= nil and ctx.id ~= nil))
end

-- The message for a time that does not read; `strict` (Save and Test) also asks a note line for one.
-- A reminder's kept times text is checked while Relative to and Time are untouched.
local function timeError(strict)
    if ctx and ctx.savedMode then
        return nil -- a saved alert has no time
    end
    if keepsTimes() and draft.keptTimes then
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

local function anyOutput()
    for _, k in ipairs(SHOW_KEYS) do
        if draft.show[k] then
            return true
        end
    end
    return draft.speak or draft.count
end

-- The draft as a note line's timer (Parser.FormatLine writes it). A line keeps its dur:.
local function noteTimer()
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
        tags = words(draft.tag),
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

-- The fields of the raw line the editor opened that FormatLine doesn't write (such as DisplayType:),
-- kept on the end of the line written back.
local function keptFields()
    return ctx and ctx.expected and CRT.NoteParser.UnknownFields(ctx.expected) or ""
end

-- The times of a reminder moving here (keepsTimes), or nil.
local function keptTimeList()
    if keepsTimes() then
        local list = Reminders:Times(ctx.encounterID, timesProbe())
        if #list > 0 then
            return list
        end
    end
    return nil
end

-- The draft as note line timers: one per time of a reminder moving here (keepsTimes), else one.
local function noteTimers()
    local base = noteTimer()
    local list = keptTimeList()
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

-- The reminder's times text: the one it was saved with until Relative to or Time is touched.
local function reminderTimes()
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
local function buildReminder()
    local r = copy(ctx and ctx.reminder or {})
    r.boss = draft.boss
    r.spellID = validID(draft.spellID)
    r.text = trim(draft.text)
    r.difficulty = draft.difficulty
    r.times = reminderTimes()
    r.outputs = r.outputs or {}
    for _, k in ipairs(SHOW_KEYS) do
        r.outputs[k] = draft.show[k] and true or false
    end
    r.outputs.speech = (draft.speak or draft.count) and true or false
    if draft.speak and draft.count then
        r.speech = "textcount"
    elseif draft.speak then
        r.speech = "text"
    elseif draft.count then
        r.speech = "count"
    end
    r.warn = draft.warn
    r.linger = draft.linger > 0 and draft.linger or nil
    r.sound = draft.sound
    r.glow = draft.glow or nil
    r.iconID = draft.iconType == "id" and validID(draft.iconID) or nil
    r.color = copy(draft.color)
    return r
end

-- Choices -----------------------------------------------------------------------------------------

local function playerName()
    local name = UnitName and UnitName("player")
    if readable(name) and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

-- The names of your raid or party, without you, in name order.
local function roster()
    local out = {}
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, raid and n or (n - 1) do
        local name, realm = UnitName((raid and "raid" or "party") .. i)
        if readable(name) and type(name) == "string" and name ~= "" then
            if readable(realm) and type(realm) == "string" and realm ~= "" then
                name = name .. "-" .. realm
            end
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

-- The game's classes: { file, name } with file the class file name ("DEATHKNIGHT"), which is what a
-- note line's tag carries, so it matches on every client whatever its language.
local function classes()
    local out = {}
    for i = 1, GetNumClasses and GetNumClasses() or 0 do
        local name, file = GetClassInfo(i)
        if readable(name) and readable(file) and type(name) == "string" and name ~= ""
            and type(file) == "string" and file ~= "" then
            out[#out + 1] = { file = file, name = name }
        end
    end
    return out
end

-- A one-word tag naming a class, by its file name or its name without spaces (in any case), as the
-- class file name; any other tag as it is.
local function classTag(tag)
    if tag:find("%s") then
        return tag
    end
    local word = tag:lower()
    for _, c in ipairs(classes()) do
        if word == c.file:lower() or word == (c.name:gsub("%s+", "")):lower() then
            return c.file
        end
    end
    return tag
end

-- Who a note line is for, as its tag: everyone, you, a role, a class, a group or a name; and the line's
-- own tag when none of those is it. A line with no tag alerts no one (it only shows in the timers
-- window), so it has a choice of its own.
local function forOptions()
    local out, seen = {}, {}
    local function add(key, label)
        if not seen[key:lower()] then
            seen[key:lower()] = true
            out[#out + 1] = { key = key, label = label }
        end
    end
    add("everyone", TEXT.everyone)
    local me = playerName()
    if me then
        add(me, TEXT.me)
    end
    add("tank", TEXT.tanks)
    add("healer", TEXT.healers)
    add("dps", TEXT.damage)
    add("melee", TEXT.melee)
    add("ranged", TEXT.ranged)
    for _, c in ipairs(classes()) do
        add(c.file, c.name)
    end
    for g = 1, 8 do
        add("G" .. g, string.format(TEXT.group, g))
    end
    for _, name in ipairs(roster()) do
        add(name, name)
    end
    if draft and (draft.tag == "" or (ctx and ctx.untagged)) then
        add("", TEXT.noOne)
    end
    if draft and draft.tag ~= "" then
        add(draft.tag, draft.tag)
    end
    return out
end

-- "Any" first, the boss's reference difficulties, the raid difficulties, and the draft's own.
local function difficultyOptions()
    local out = { { key = ANY, label = TEXT.any } }
    local seen = {}
    local function add(d)
        if type(d) == "string" and trim(d) ~= "" and not seen[lower(d)] then
            seen[lower(d)] = true
            out[#out + 1] = { key = d, label = d }
        end
    end
    local Ref = CRT.TimelineReference
    if Ref and ctx then
        for _, entry in ipairs(Ref:ForBoss(ctx.encounterID, draft and draft.boss)) do
            add(entry.ref.difficulty)
        end
    end
    add(TEXT.normal)
    add(TEXT.heroic)
    add(TEXT.mythic)
    add(draft and draft.difficulty)
    return out
end

-- The raid difficulty you are in now, by the name a pull there gets (GetDifficultyInfo, as the engine
-- names it on ENCOUNTER_START), or nil outside a raid.
local function currentDifficulty()
    if not GetInstanceInfo then
        return nil
    end
    local ok, _, kind, difficultyID, name = pcall(GetInstanceInfo)
    if not (ok and readable(kind) and kind == "raid") then
        return nil
    end
    if GetDifficultyInfo and readable(difficultyID) and type(difficultyID) == "number" then
        local okName, n = pcall(GetDifficultyInfo, difficultyID)
        if okName and readable(n) and type(n) == "string" and trim(n) ~= "" then
            return n
        end
    end
    if readable(name) and type(name) == "string" and trim(name) ~= "" then
        return name
    end
    return nil
end

-- The note a raid note line saved now goes to: the line's own note while its difficulty is unchanged,
-- else the one a pull of that difficulty reads (Notes:AddLine writes there). Nil: a new note is made.
local function targetNote()
    if not (ctx and type(ctx.encounterID) == "number") then
        return nil
    end
    local difficulty = draft.difficulty and trim(draft.difficulty) or nil
    if ctx.noteID and lower(ctx.noteDifficulty) == lower(difficulty) then
        return ctx.noteID
    end
    return CRT.Notes:FindForEncounter(ctx.encounterID, difficulty)
end

-- The Difficulty a new raid note line starts on: that of the note the pull you are in would read, or,
-- outside a raid, of the boss's only note. Nil (Any) when there is no such note.
local function defaultDifficulty()
    local encounterID = ctx and ctx.encounterID
    if type(encounterID) ~= "number" then
        return nil
    end
    local Notes = CRT.Notes
    local current = currentDifficulty()
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

-- Save as changed, or the editor opened: a draft whose difficulty you haven't picked takes the raid
-- note's default as a note line, and its own (a reminder's, or Any) otherwise.
local function applyDefaultDifficulty()
    if draft.difficultyTouched or (ctx and ctx.noteID) or draft.baseDifficulty ~= nil then
        return
    end
    draft.difficulty = draft.saveAs == "note" and defaultDifficulty() or nil
end

-- Pull, then a Phase N for every later phase the boss has, and the draft's own.
local function phaseOptions()
    local list = { 1 }
    local seen = { [1] = true }
    local ok, phases = pcall(Alerts.PhasesFor, Alerts, { encounterID = ctx and ctx.encounterID })
    for _, ph in ipairs(ok and type(phases) == "table" and phases or {}) do
        if type(ph) == "number" and not seen[ph] then
            seen[ph] = true
            list[#list + 1] = ph
        end
    end
    if draft and type(draft.ph) == "number" and not seen[draft.ph] then
        list[#list + 1] = draft.ph
    end
    table.sort(list)
    local out = {}
    for _, ph in ipairs(list) do
        out[#out + 1] = { key = ph, label = ph == 1 and TEXT.pull or string.format(TEXT.phase, tostring(ph)) }
    end
    return out
end

local function soundOptions()
    local out = { { key = NO_SOUND, label = TEXT.none } }
    for _, s in ipairs(CRT.AlertSpeech and CRT.AlertSpeech.SOUNDS or {}) do
        out[#out + 1] = { key = s.key, label = s.label }
    end
    return out
end

-- Showing the draft -------------------------------------------------------------------------------

-- Where the times come from while a reminder's own are kept (also when it moves to the raid note).
local function sourceLine()
    if not keepsTimes() then
        return ""
    end
    local list, source = Reminders:Times(ctx and ctx.encounterID, timesProbe())
    if source == "typed" then
        return TEXT.timesPrefix .. draft.keptTimes
    elseif source == "reference" and #list > 0 then
        local ref = Reminders.ReferenceFor(ctx and ctx.encounterID, timesProbe())
        if ref then
            return TEXT.fromPrefix .. CRT.TimelineReference.Label(ref)
        end
    end
    return TEXT.noTimes
end

-- The note a raid note line saves to, by name and difficulty.
local function savesToLine()
    if draft.saveAs ~= "note" or not (ctx and type(ctx.encounterID) == "number") then
        return ""
    end
    local record = CRT.Notes:Get(targetNote())
    if not record then
        return string.format(TEXT.savesTo, TEXT.newNote)
    end
    local name = record.name or ""
    if record.difficulty then
        name = string.format(TEXT.noteName, name, record.difficulty)
    end
    return string.format(TEXT.savesTo, name)
end

-- Everything on the window from the draft, except the boxes being typed in. `rows` also redraws the
-- dropdowns and sliders (on open and when one of them is set), so typing never rebuilds their menus.
local function refresh(rows)
    if not (frame and draft) then
        return
    end
    local savedMode = ctx ~= nil and ctx.savedMode == true
    -- a raid note line opened read-only, by someone promoted since: editable as for any leader
    if ctx ~= nil and ctx.readOnly and canEditRaid() then
        ctx.readOnly = nil
        UI.SetFrameTitle(frame, TEXT.title)
        rows = true
    end
    frame.forRow:SetShown(draft.saveAs == "note")
    frame.relativeRow:SetShown(not savedMode)
    frame.difficultyRow:SetShown(not savedMode)
    frame.timeLabel:SetShown(not savedMode)
    frame.timeEdit:SetShown(not savedMode)
    frame.timeHelp:SetShown(not savedMode)
    local locked = readOnly()
    frame.saveSavedBtn:SetShown(not savedMode and not locked)
    frame.exportBtn:SetShown(not savedMode) -- a saved alert has no time to write a note line with
    frame.saveBtn:SetShown(not locked)
    frame.copyBtn:SetShown(locked)
    -- a copy needs a boss to be saved for
    frame.copyBtn:SetEnabled(locked and type(ctx.encounterID) == "number")
    -- why Raid note is greyed out (a saved alert may keep Raid note: it changes no note by itself)
    frame.saveAsHelp:SetShown(not savedMode and not canEditRaid())
    for _, el in ipairs({ frame.textEdit, frame.timeEdit, frame.idEdit, frame.colorSwatch, frame.colorDefault }) do
        el:SetEnabled(not locked)
    end
    for _, k in ipairs(SHOW_KEYS) do
        frame.checks[k]:SetEnabled(not locked)
    end
    for _, check in pairs(frame.also) do
        check:SetEnabled(not locked)
    end
    if rows then
        for _, row in ipairs(frame.rows) do
            row.refresh()
        end
    end
    local name, icon = spellInfo(draft.spellID)
    if draft.iconType == "id" then
        icon = validID(draft.iconID)
    end
    frame.iconPreview:SetTexture(icon)
    frame.iconPreview:SetShown(icon ~= nil)
    frame.spellName:SetText(name or "")
    for _, k in ipairs(SHOW_KEYS) do
        frame.checks[k]:SetChecked(draft.show[k] and true or false)
    end
    frame.also.speak:SetChecked(draft.speak and true or false)
    frame.also.count:SetChecked(draft.count and true or false)
    frame.also.glow:SetChecked(draft.glow and true or false)
    local c = draft.color or { 1, 1, 1 }
    frame.colorSwatch.tex:SetColorTexture(c[1], c[2], c[3], 1)
    frame.sourceText:SetText(sourceLine())
    frame.savesText:SetText(savesToLine())
    local message = timeError(false) or notice
    frame.messageText:SetText(message and ("|cffff6060" .. message .. "|r") or "")
    frame.deleteBtn:SetShown(not locked and ctx ~= nil and (ctx.id ~= nil or ctx.noteID ~= nil or ctx.savedID ~= nil))
end

-- A field changed: any message about the last Save is out of date.
local function changed(rows)
    notice = nil
    refresh(rows)
end

local function fail(message)
    notice = message
    refresh()
    return false
end

-- Saving and testing ------------------------------------------------------------------------------

local function applyPosition()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

-- Back to the centre if Previews had put the editor in the corner.
local function leaveCorner()
    if inCorner then
        inCorner = false
        applyPosition()
    end
end

-- The editor's window (nil until first opened), for a drag on the Timeline released over it.
function Editor:Frame()
    return frame
end

function Editor:Close()
    if frame then
        frame:Hide()
        leaveCorner()
    end
    if exportFrame then
        exportFrame:Hide()
    end
    ctx, draft, notice = nil, nil, nil
end

-- Whether the note line is still the one the editor opened.
local function lineUnchanged()
    local _, raw = CRT.Notes:TimerAt(ctx.noteID, ctx.line)
    return raw ~= nil and raw == ctx.expected
end

local function saveNote()
    local allowed, why = canEditRaid()
    if not allowed then
        return fail(why)
    end
    local encounterID = ctx.encounterID
    if type(encounterID) ~= "number" then
        return fail(TEXT.noBoss)
    end
    local Notes = CRT.Notes
    local extra = keptFields()
    local lines = {}
    for i, t in ipairs(noteTimers()) do
        lines[i] = CRT.NoteParser.FormatLine(t) .. extra
    end
    local difficulty = draft.difficulty and trim(draft.difficulty) or nil
    if ctx.noteID then
        if not lineUnchanged() then
            return fail(TEXT.stale)
        end
        -- still going to its own note: the line is replaced where it is
        if targetNote() == ctx.noteID then
            if not Notes:ReplaceLine(ctx.noteID, ctx.line, lines[1], ctx.expected) then
                return fail(TEXT.stale)
            end
            Editor:Close()
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
            return fail(TEXT.noteFailed)
        end
        written[#written + 1] = { id = id, n = n, line = line }
    end
    if ctx.noteID then
        Notes:RemoveLine(ctx.noteID, ctx.line, ctx.expected)
    elseif ctx.id then
        Reminders:Delete(encounterID, ctx.id)
    end
    Editor:Close()
    return true
end

local function saveMine()
    local encounterID = ctx.encounterID
    if encounterID == nil then
        return fail(TEXT.noEncounter)
    end
    -- a note line moving to your reminders is taken out of the raid note
    if ctx.noteID then
        local allowed, why = canEditRaid()
        if not allowed then
            return fail(why)
        end
    end
    if ctx.noteID and not lineUnchanged() then
        return fail(TEXT.stale)
    end
    if not Reminders:Save(encounterID, ctx.id, buildReminder()) then
        return fail(TEXT.saveFailed)
    end
    if ctx.noteID then
        CRT.Notes:RemoveLine(ctx.noteID, ctx.line, ctx.expected)
    end
    Editor:Close()
    return true
end

-- The draft as a saved alert's fields (CRT.AlertSaved:Save keeps only the ones a saved alert has). No
-- name: Save keeps the stored one, so a rename on its chip while the editor is open stays.
local function savedFields()
    local r = buildReminder()
    r.saveAs = draft.saveAs
    r.tags = words(draft.tag)
    return r
end

-- Saving a saved alert itself: overwrites it, or makes it for a new one. One deleted while it was open
-- (from its chip) is not made again.
local function saveSaved()
    local Saved = CRT.AlertSaved
    if ctx.savedID and not (Saved and Saved:Get(ctx.savedID)) then
        return fail(TEXT.savedGone)
    end
    if not (Saved and Saved:Save(ctx.savedID, savedFields())) then
        return fail(TEXT.savedFailed)
    end
    Editor:Close()
    return true
end

-- Saves the draft and closes. A time that does not read, nothing ticked, or a note line changed
-- elsewhere leaves the window open with the message shown.
function Editor:Save()
    if not (ctx and draft) then
        return false
    end
    if ctx.readOnly then
        -- promoted since it opened, before anything redrew it
        local allowed, why = canEditRaid()
        return fail(allowed and TEXT.reopen or why)
    end
    local err = timeError(true)
    if err then
        return fail(err)
    end
    if not anyOutput() then
        return fail(TEXT.nothing)
    end
    if ctx.savedMode then
        return saveSaved()
    end
    if draft.saveAs == "note" then
        return saveNote()
    end
    return saveMine()
end

-- Runs the draft alone as a test, starting TEST_LEAD seconds before its first time. Saves nothing.
function Editor:Test()
    if not (ctx and (ctx.encounterID or ctx.savedMode) and draft) then
        return false
    end
    -- A real pull is never cut short by a test.
    if Alerts.running and Alerts.run and Alerts.run.reason == "encounter" then
        return fail(TEXT.testInPull)
    end
    local err = timeError(true)
    if err then
        return fail(err)
    end
    if not anyOutput() then
        return fail(TEXT.nothing)
    end
    local items, lowest, first
    if draft.saveAs == "note" then
        local list = {}
        items = {}
        for i, t in ipairs(noteTimers()) do
            if ctx.savedMode then
                t.ph, t.time = 1, TEST_LEAD -- a saved alert has no time: ten seconds from the start
            end
            local item = CRT.NoteEngine.ItemFor(t, i, true)
            item.id = "note:test:" .. i
            item.block = "note"
            items[i] = item
            list[i] = { ph = t.ph, t = t.time }
        end
        lowest, first = firstTime(list)
    else
        local r = buildReminder()
        if ctx.savedMode then
            r.times = Reminders.FormatTimes({ { ph = 1, t = TEST_LEAD } })
        end
        local list = Reminders:Times(ctx.encounterID, r)
        if #list == 0 then
            refresh()
            return false
        end
        lowest, first = firstTime(list)
        items = Reminders:Items(ctx.encounterID, "test", r)
    end
    testItems = items
    Alerts:Start(ctx.encounterID or 0, nil, "test", {
        blocks = { [TEST_BLOCK] = true },
        filter = function(_, item)
            return type(item.id) == "string" and (item.id:find("^mine:test:") or item.id:find("^note:test:")) ~= nil
        end,
        firstAt = GetTime() + TEST_LEAD - first,
    })
    testItems = nil
    -- A lowest phase with an event trigger waits for its event, so the test would show nothing.
    if Alerts.running and Alerts.run and Alerts.run.reason == "test" and not Alerts:PhaseStart(lowest) then
        Alerts:Stop()
        return fail(string.format(TEXT.testTrigger, tostring(lowest)))
    end
    return true
end

-- The draft's items, given out once and only to a test run. A note line's item keeps block "note".
Alerts:RegisterBlock(TEST_BLOCK, { label = TEXT.testBlock, group = true, keepBlock = true, Entries = function(run)
    if not (run and run.reason == "test" and testItems) then
        return {}
    end
    return testItems
end })

-- The window ------------------------------------------------------------------------------------

local function makeButton(parent, label, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, 24)
    b:SetText(label)
    return b
end

-- Where the rows below the Relative to / Time row sit, so a saved alert's editor can close the gap.
local placed = {}
local LOWER_Y = -(98 + ROW1_EXTRA)

local function lay(el, x, y)
    el:SetPoint("TOPLEFT", x, y)
    if y <= LOWER_Y then
        placed[#placed + 1] = { el, x, y }
    end
    return el
end

local function applyLayout(savedMode)
    local d = savedMode and SAVED_SHIFT or 0
    for _, p in ipairs(placed) do
        p[1]:ClearAllPoints()
        p[1]:SetPoint("TOPLEFT", p[2], p[3] + d)
    end
    frame:SetHeight(HEIGHT - d)
end

local function makeLabel(parent, label, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    lay(fs, x, y)
    fs:SetText(label)
    return fs
end

-- onChange(text, userInput): userInput is false when the editor itself set the text.
local function makeEdit(parent, x, y, width, onChange)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontEdit)
    edit:SetSize(width, 20)
    lay(edit, x, y)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if readOnly() then
            return -- the box is disabled, and a read-only draft is filled before its boxes are
        end
        onChange(self:GetText(), userInput)
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return edit
end

local function makeCheck(parent, label, x, y, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    lay(check, x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check.label = text
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return check
end

-- A setter for a dropdown, slider or checkbox: edits the draft (when there is one) and redraws. A
-- read-only draft is only redrawn, which puts the control back.
local function setter(fn)
    return function(v)
        if draft then
            if readOnly() then
                refresh(true)
                return
            end
            fn(v)
            changed(true)
        end
    end
end

function Editor:ResetPosition()
    if frame then
        applyPosition()
    end
end

-- The box Export opens: the note line, selected, to copy with Ctrl+C. Typing in it puts the line back.
local function buildExport()
    if exportFrame then
        return
    end
    local x = CreateFrame("Frame", EXPORT_NAME, UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(x)
    exportFrame = x
    x:SetSize(WIDTH - 40, EXPORT_CHROME + EXPORT_MIN_TEXT + 2 * EXPORT_PAD)
    x:SetPoint("CENTER", frame, "CENTER", 0, 0)
    x:SetClampedToScreen(true)
    x:EnableMouse(true)
    -- above every window, not on the "panel" layer (that one follows the main window's strata)
    x:SetFrameStrata("FULLSCREEN_DIALOG")
    UI.SetFrameTitle(x, TEXT.exportTitle)
    tinsert(UISpecialFrames, EXPORT_NAME)
    x.text = ""
    -- A plain multi-line box on its own backdrop (the line template's art is one row tall), inside a
    -- scroll frame for text taller than the window has room for. Its height follows the measured text.
    local box = CreateFrame("Frame", nil, x, "BackdropTemplate")
    x.box = box
    box:SetPoint("TOPLEFT", LEFT + 4, -40)
    box:SetWidth(EXPORT_WIDTH)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    local roast, caramel = CRT.MOCHA.roast, CRT.MOCHA.caramel
    box:SetBackdropColor(roast[1], roast[2], roast[3], 0.95)
    box:SetBackdropBorderColor(caramel[1], caramel[2], caramel[3], 1)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    x.scroll = scroll
    scroll:SetPoint("TOPLEFT", EXPORT_PAD, -EXPORT_PAD)
    scroll:SetWidth(EXPORT_TEXT_WIDTH)
    local edit = CreateFrame("EditBox", nil, scroll)
    x.edit = edit
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontEdit)
    edit:SetWidth(EXPORT_TEXT_WIDTH)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local top = math.max(0, edit:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(top, (self:GetVerticalScroll() or 0) - delta * 14)))
    end)
    -- the same font and width, hidden, to measure what the text needs
    x.measure = x:CreateFontString(nil, "OVERLAY")
    x.measure:SetFontObject(CRTFontEdit)
    x.measure:SetWidth(EXPORT_TEXT_WIDTH)
    -- wraps anywhere, like the edit box (a long line has no spaces to break at)
    x.measure:SetNonSpaceWrap(true)
    x.measure:Hide()
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(x.text)
            self:HighlightText()
        end
    end)
    x.edit:SetScript("OnEscapePressed", function()
        x:Hide()
    end)
    x.edit:SetScript("OnEditFocusGained", function(self)
        x:Raise() -- over the editor when clicked, without being toplevel itself
        self:HighlightText()
    end)
    UI:SkinTree(x)
    x:Hide()
end

-- Shows the draft as note lines in the copy box, one per time as Save writes them. Saves nothing.
-- Returns the text.
function Editor:Export()
    if not (frame and draft) then
        return nil
    end
    -- a note line needs a time that reads, as Save does
    local err = timeError(true) or (not ctx.savedMode and not keptTimeList() and parseTime(draft.timeText) == nil
        and TEXT.noTime or nil)
    if err then
        fail(err)
        return nil
    end
    buildExport()
    local extra, lines = keptFields(), {}
    for i, t in ipairs(noteTimers()) do
        lines[i] = CRT.NoteParser.FormatLine(t) .. extra
    end
    local line = table.concat(lines, "\n")
    -- the box is as tall as the text wraps to, up to what the window has room for, then it scrolls
    exportFrame.measure:SetText(line)
    local textHeight = math.max(EXPORT_MIN_TEXT, math.ceil(exportFrame.measure:GetStringHeight() or 0))
    local shown = math.min(textHeight, EXPORT_MAX_TEXT)
    exportFrame.edit:SetHeight(textHeight)
    exportFrame.scroll:SetHeight(shown)
    exportFrame.scroll:SetVerticalScroll(0)
    exportFrame.box:SetHeight(shown + EXPORT_PAD * 2)
    exportFrame:SetHeight(EXPORT_CHROME + shown + EXPORT_PAD * 2)
    exportFrame.text = line
    exportFrame.edit:SetText(line)
    exportFrame:Show()
    exportFrame:Raise()
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
    return line
end

local function confirm(info)
    UI.LiftOver(UI.ShownPopup(StaticPopup_ShowCustomGenericConfirmation(info), "GENERIC_CONFIRMATION"))
end

-- The name popup of Save as saved alert: an edit box with the default name in it. data = { fields, default }.
local function acceptName(edit, data)
    local fields = data and data.fields
    if not (edit and fields and CRT.AlertSaved) then
        return
    end
    fields.name = trim(edit:GetText())
    local id = CRT.AlertSaved:Save(nil, fields)
    if not id then
        if draft then
            fail(TEXT.savedFailed)
        end
        return
    end
    local s = CRT.AlertSaved:Get(id)
    if s and CRT.Print then
        CRT:Print(string.format(TEXT.savedMade, s.name))
    end
end

local function ensureNamePopup()
    if not StaticPopupDialogs then
        return false
    end
    if StaticPopupDialogs[POPUP_NAME] then
        return true
    end
    StaticPopupDialogs[POPUP_NAME] = {
        text = TEXT.savedNamePrompt,
        button1 = TEXT.savedAccept,
        button2 = TEXT.cancel,
        hasEditBox = true,
        maxLetters = 64,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self, data)
            local edit = UI.PopupEditBox(self)
            if edit then
                edit:SetText(data and data.default or "")
                edit:HighlightText()
            end
        end,
        OnAccept = function(self, data)
            acceptName(UI.PopupEditBox(self), data)
        end,
        -- the game passes the dialog's data; the box's parent is only a fallback (layouts change)
        EditBoxOnEnterPressed = function(edit, data)
            local parent = edit:GetParent()
            acceptName(edit, data or (parent and parent.data))
            StaticPopup_Hide(POPUP_NAME)
        end,
        EditBoxOnEscapePressed = function()
            StaticPopup_Hide(POPUP_NAME)
        end,
    }
    return true
end

-- Asks for a name for the draft as a saved alert, over the editor; Accept makes it (an empty name takes
-- the default), Cancel leaves the draft as it was.
local function askSavedName()
    if not (draft and CRT.AlertSaved and ensureNamePopup()) then
        return
    end
    if not anyOutput() then
        return fail(TEXT.nothing)
    end
    local fields = savedFields()
    fields.name = nil
    local data = { fields = fields, default = CRT.AlertSaved.DefaultName(fields) }
    -- already asking: the open popup is reused, taking the draft as it is now
    local openName = StaticPopup_Visible and StaticPopup_Visible(POPUP_NAME)
    local open = openName and _G[openName]
    if open and open.IsShown and open:IsShown() then
        open.data = data
        UI.LiftOver(open)
        return
    end
    UI.LiftOver(UI.ShownPopup(StaticPopup_Show(POPUP_NAME, nil, nil, data), POPUP_NAME))
end

-- The game's color picker on the draft's color; Cancel puts the old one back.
local function pickColor()
    if not (draft and ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) or readOnly() then
        return
    end
    -- the alert open now: a picker left open never writes into the next one
    local target = draft
    local before = copy(draft.color)
    local c = draft.color or { 1, 1, 1, 1 }
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c[1], g = c[2], b = c[3], hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            if draft and draft == target then
                draft.color = { r, g, b, 1 }
                changed()
            end
        end,
        cancelFunc = function()
            if draft and draft == target then
                draft.color = copy(before)
                changed()
            end
        end,
    })
    -- the picker is DIALOG strata, below the editor: lift it over until it hides
    UI.LiftOver(ColorPickerFrame)
end

local function build()
    if frame then
        return
    end
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(f)
    frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        inCorner = false -- dragged: it keeps the spot it was put in
    end)
    -- above every window, the Timeline pop-out included; not on the "panel" layer, which follows the
    -- main window's strata
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    -- Previews never touch an alert being edited: on opens an empty editor only when none is open,
    -- and off closes only the one Previews opened.
    -- The one Previews opens sits in the bottom right corner, clear of the alert areas it shows with.
    UI:RegisterPreview("alerteditor", function(on)
        local open = draft ~= nil and frame:IsShown()
        if on then
            if not open then
                Editor:Open(nil, nil)
                previewDraft = draft
                f:ClearAllPoints()
                f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -PREVIEW_INSET, PREVIEW_INSET)
                inCorner = true
            end
        else
            if open and draft == previewDraft then
                Editor:Close()
            end
            previewDraft = nil
        end
    end)
    UI.SetFrameTitle(f, TEXT.title)
    tinsert(UISpecialFrames, FRAME_NAME)
    applyPosition()
    UI.ResetButton(f, function()
        Editor:ResetPosition()
    end):SetPoint("TOPRIGHT", -28, -4)
    f:SetScript("OnHide", function()
        -- closed any way (Escape, Save, Close, Previews off): the next Open starts at the centre
        leaveCorner()
        if exportFrame then
            exportFrame:Hide()
        end
    end)
    f.rows = {}
    local function row(r, x, y)
        lay(r, x, y)
        f.rows[#f.rows + 1] = r
        return r
    end

    -- Save as, For, Difficulty
    -- Raid note is greyed out for anyone who can't change the raid note, with a (?) saying why
    row(UI.Dropdown(f, TEXT.saveAs, {
        labelWidth = 56, width = 104, enabledIf = editable,
        options = function()
            local locked = not (ctx and ctx.savedMode) and not canEditRaid()
            return { { key = "note", label = TEXT.asNote, disabled = locked or nil }, { key = "mine", label = TEXT.asMine } }
        end,
        get = function() return draft and draft.saveAs or "mine" end,
        set = function(v)
            if not draft then
                return
            end
            if readOnly() then
                refresh(true)
                return
            end
            if v == "note" and not ctx.savedMode then
                local allowed, why = canEditRaid()
                if not allowed then
                    return fail(why)
                end
            end
            draft.saveAs = v
            applyDefaultDifficulty()
            changed(true)
        end,
    }), LEFT, -30)
    f.saveAsHelp = UI.Help(f, TEXT.asNote, notAdminReason)
    f.saveAsHelp:SetPoint("TOPLEFT", LEFT + 56 + 5 + 104, -38)
    f.forRow = row(UI.Dropdown(f, TEXT.forLabel, {
        labelWidth = 30, width = 160, maxHeight = MENU_MAX_HEIGHT, enabledIf = editable,
        options = forOptions,
        get = function() return draft and draft.tag or "" end,
        set = setter(function(v) draft.tag = v end),
    }), 205, -30)
    f.difficultyRow = row(UI.Dropdown(f, TEXT.difficulty, {
        labelWidth = 60, width = 114, enabledIf = editable,
        options = difficultyOptions,
        get = function() return draft and draft.difficulty or ANY end,
        set = setter(function(v)
            draft.difficulty = v ~= ANY and v or nil
            draft.difficultyTouched = true
        end),
    }), 405, -30)
    -- Saves to: the note a raid note line goes to, under For and Difficulty
    f.savesText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    f.savesText:SetPoint("TOPRIGHT", -LEFT, -62)
    f.savesText:SetWidth(WIDTH - 205 - LEFT)
    f.savesText:SetJustifyH("RIGHT")
    f.savesText:SetWordWrap(false)

    -- Relative to, Time
    f.relativeRow = row(UI.Dropdown(f, TEXT.relativeTo, {
        labelWidth = 70, width = 120, enabledIf = editable,
        options = phaseOptions,
        get = function() return draft and draft.ph or 1 end,
        set = setter(function(v)
            draft.ph = v
            draft.timeTouched = true
        end),
    }), LEFT, -64 - ROW1_EXTRA)
    f.timeLabel = makeLabel(f, TEXT.time, 226, -74 - ROW1_EXTRA)
    f.timeEdit = makeEdit(f, 264, -70 - ROW1_EXTRA, 64, function(text, userInput)
        if draft then
            draft.timeText = text
            if userInput then
                draft.timeTouched = true
            end
            changed()
        end
    end)
    f.timeHelp = UI.Help(f, TEXT.timeHelpTitle, TEXT.timeHelp)
    f.timeHelp:SetPoint("TOPLEFT", 332, -72 - ROW1_EXTRA)
    f.sourceText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    f.sourceText:SetPoint("TOPLEFT", 360, -74 - ROW1_EXTRA)
    f.sourceText:SetWidth(WIDTH - 360 - LEFT)
    f.sourceText:SetJustifyH("LEFT")
    f.sourceText:SetWordWrap(false)

    -- Show from, Linger
    row(UI.Slider(f, TEXT.showFrom, {
        min = 1, max = 60, step = 1, labelWidth = 70, width = 150, enabledIf = editable,
        format = function(v) return string.format(TEXT.seconds, v) end,
        get = function() return draft and draft.warn or 5 end,
        set = setter(function(v) draft.warn = v end),
    }), LEFT, -98 - ROW1_EXTRA)
    row(UI.Slider(f, TEXT.linger, {
        min = 0, max = 10, step = 1, labelWidth = 50, width = 150, enabledIf = editable,
        format = function(v) return string.format(TEXT.seconds, v) end,
        get = function() return draft and draft.linger or 0 end,
        set = setter(function(v) draft.linger = v end),
    }), 306, -98 - ROW1_EXTRA)

    -- Icon: Spell or Icon ID, the ID box and a preview
    row(UI.Dropdown(f, TEXT.icon, {
        labelWidth = 70, width = 110, enabledIf = editable,
        options = { { key = "spell", label = TEXT.iconSpell }, { key = "id", label = TEXT.iconID } },
        get = function() return draft and draft.iconType or "spell" end,
        set = function(v)
            if draft and readOnly() then
                refresh(true)
            elseif draft then
                draft.iconType = v
                local id = v == "id" and draft.iconID or draft.spellID
                f.idEdit:SetText(id and tostring(id) or "")
                changed(true)
            end
        end,
    }), LEFT, -132 - ROW1_EXTRA)
    f.idEdit = makeEdit(f, 212, -138 - ROW1_EXTRA, 80, function(text)
        if draft then
            local id = validID(tonumber(trim(text)))
            if draft.iconType == "id" then
                draft.iconID = id
            else
                draft.spellID = id
            end
            changed()
        end
    end)
    lay(UI.Help(f, TEXT.iconHelpTitle, TEXT.iconHelp), 296, -140 - ROW1_EXTRA)
    f.iconPreview = f:CreateTexture(nil, "ARTWORK")
    f.iconPreview:SetSize(24, 24)
    lay(f.iconPreview, 326, -136 - ROW1_EXTRA)
    f.iconPreview:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.spellName = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    lay(f.spellName, 358, -142 - ROW1_EXTRA)
    f.spellName:SetWidth(WIDTH - 358 - LEFT)
    f.spellName:SetJustifyH("LEFT")
    f.spellName:SetWordWrap(false)

    -- Text
    makeLabel(f, TEXT.text, LEFT, -178 - ROW1_EXTRA)
    f.textEdit = makeEdit(f, FIELD_X + 4, -174 - ROW1_EXTRA, WIDTH - FIELD_X - LEFT - 8, function(text)
        if draft then
            draft.text = text
            changed()
        end
    end)

    -- Color: a swatch that opens the game's color picker, and Default for none
    makeLabel(f, TEXT.color, LEFT, -210 - ROW1_EXTRA)
    f.colorSwatch = CreateFrame("Button", nil, f)
    f.colorSwatch:SetSize(20, 20)
    lay(f.colorSwatch, FIELD_X, -206 - ROW1_EXTRA)
    f.colorSwatch.edge = f.colorSwatch:CreateTexture(nil, "BACKGROUND")
    f.colorSwatch.edge:SetAllPoints()
    f.colorSwatch.edge:SetColorTexture(0.5, 0.5, 0.5, 1)
    f.colorSwatch.tex = f.colorSwatch:CreateTexture(nil, "ARTWORK")
    f.colorSwatch.tex:SetPoint("TOPLEFT", 1, -1)
    f.colorSwatch.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.colorSwatch:SetScript("OnClick", pickColor)
    f.colorDefault = makeButton(f, TEXT.colorDefault, 80)
    lay(f.colorDefault, FIELD_X + 28, -204 - ROW1_EXTRA)
    f.colorDefault:SetScript("OnClick", function()
        if draft and not readOnly() then
            draft.color = nil
            changed()
        end
    end)

    -- Show as
    makeLabel(f, TEXT.showAs, LEFT, -246 - ROW1_EXTRA)
    f.checks = {}
    for _, spec in ipairs({ { "alert", TEXT.nextSpell, FIELD_X }, { "text", TEXT.showText, 226 },
        { "icon", TEXT.showIcon, 296 }, { "bar", TEXT.bar, 366 }, { "circle", TEXT.circle, 430 } }) do
        local key = spec[1]
        f.checks[key] = makeCheck(f, spec[2], spec[3], -240 - ROW1_EXTRA, setter(function(on) draft.show[key] = on end))
    end

    -- Also
    makeLabel(f, TEXT.also, LEFT, -280 - ROW1_EXTRA)
    f.also = {
        speak = makeCheck(f, TEXT.speak, FIELD_X, -274 - ROW1_EXTRA, setter(function(on) draft.speak = on end)),
        count = makeCheck(f, TEXT.count, 226, -274 - ROW1_EXTRA, setter(function(on) draft.count = on end)),
        glow = makeCheck(f, TEXT.glow, 386, -274 - ROW1_EXTRA, setter(function(on) draft.glow = on end)),
    }
    row(UI.Dropdown(f, TEXT.sound, {
        labelWidth = 70, width = 160, maxHeight = MENU_MAX_HEIGHT, enabledIf = editable,
        options = soundOptions,
        get = function() return draft and draft.sound or NO_SOUND end,
        set = setter(function(v) draft.sound = v ~= NO_SOUND and v or nil end),
    }), LEFT, -304 - ROW1_EXTRA)

    f.messageText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    lay(f.messageText, LEFT, -350 - ROW1_EXTRA)
    f.messageText:SetWidth(WIDTH - 2 * LEFT)
    f.messageText:SetJustifyH("LEFT")

    -- Buttons
    f.deleteBtn = makeButton(f, TEXT.delete, 80)
    f.deleteBtn:SetPoint("BOTTOMLEFT", LEFT, 14)
    f.deleteBtn:SetScript("OnClick", function()
        if not (ctx and (ctx.id or ctx.noteID or ctx.savedID)) then
            return
        end
        local from = ctx
        confirm({
            text = from.savedMode and TEXT.deleteSavedConfirm or TEXT.deleteConfirm,
            acceptText = TEXT.delete,
            cancelText = TEXT.cancel,
            showAlert = true,
            callback = function()
                if from.savedMode then
                    if CRT.AlertSaved then
                        CRT.AlertSaved:Delete(from.savedID)
                    end
                elseif from.noteID then
                    local allowed, why = canEditRaid()
                    if not allowed or from.readOnly then
                        local message = why or TEXT.reopen
                        if ctx == from then
                            fail(message)
                        elseif CRT.Print then
                            CRT:Print(message)
                        end
                        return
                    end
                    if not CRT.Notes:RemoveLine(from.noteID, from.line, from.expected) then
                        if ctx == from then
                            fail(TEXT.stale)
                        end
                        return
                    end
                else
                    Reminders:Delete(from.encounterID, from.id)
                end
                if ctx == from then
                    Editor:Close()
                end
            end,
        })
    end)
    f.exportBtn = makeButton(f, TEXT.export, 80)
    f.exportBtn:SetPoint("BOTTOMLEFT", LEFT + 88, 14)
    f.exportBtn:SetScript("OnClick", function()
        Editor:Export()
    end)
    f.saveSavedBtn = makeButton(f, TEXT.saveAsSaved, 134)
    f.saveSavedBtn:SetPoint("BOTTOMLEFT", LEFT + 176, 14)
    f.saveSavedBtn:SetScript("OnClick", askSavedName)
    -- in its place on a read-only raid note line
    f.copyBtn = makeButton(f, TEXT.copyToMine, 134)
    f.copyBtn:SetPoint("BOTTOMLEFT", LEFT + 176, 14)
    f.copyBtn:SetScript("OnClick", function()
        Editor:CopyToMine()
    end)
    f.copyBtn:Hide()
    f.saveBtn = makeButton(f, TEXT.save, 80)
    f.saveBtn:SetPoint("BOTTOMRIGHT", -LEFT, 14)
    f.saveBtn:SetScript("OnClick", function()
        Editor:Save()
    end)
    f.cancelBtn = makeButton(f, TEXT.cancel, 80)
    f.cancelBtn:SetPoint("BOTTOMRIGHT", -LEFT - 88, 14)
    f.cancelBtn:SetScript("OnClick", function()
        Editor:Close()
    end)
    f.testBtn = makeButton(f, TEXT.test, 80)
    f.testBtn:SetPoint("BOTTOMRIGHT", -LEFT - 176, 14)
    f.testBtn:SetScript("OnClick", function()
        Editor:Test()
    end)
    UI:SkinTree(f)
    f:Hide()
end

-- Opening -------------------------------------------------------------------------------------------

local function newDraft()
    return { saveAs = "mine", tag = "everyone", ph = 1, timeText = "", timeTouched = false, iconType = "spell",
        text = "", show = { alert = true, bar = true }, speak = true, count = false, glow = false, warn = 5,
        linger = 0 }
end

-- A saved reminder into the draft. Its times text is kept until Relative to or Time is touched.
local function fromReminder(r)
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
    draft.warn = r.warn or 5
    draft.linger = type(r.linger) == "number" and r.linger or 0
    draft.iconID = validID(r.iconID)
    draft.iconType = draft.iconID and "id" or "spell"
    draft.color = copy(r.color)
end

-- A saved alert into the draft: a reminder's fields, and its For choice and Save as.
local function fromSaved(s)
    fromReminder(s)
    if s.tags then
        draft.tag = table.concat(s.tags, " ")
    end
    draft.saveAs = s.saveAs == "note" and "note" or "mine"
end

-- The window's title: Alert, or the saved alert's name (New saved alert for a new one).
local function setTitle()
    local title = TEXT.title
    if ctx.readOnly then
        title = TEXT.noteLineTitle
    elseif ctx.savedMode then
        title = ctx.savedName and string.format(TEXT.savedTitle, ctx.savedName) or TEXT.savedTitleNew
    end
    UI.SetFrameTitle(frame, title)
end

-- A saved alert changed somewhere (its chip renamed or deleted it): the one open here shows its new
-- name, or says it is gone (Save then makes nothing).
local function savedChanged()
    if not (frame and frame:IsShown() and ctx and ctx.savedMode and ctx.savedID) then
        return
    end
    local s = CRT.AlertSaved and CRT.AlertSaved:Get(ctx.savedID)
    if s then
        ctx.savedName = s.name
        setTitle()
    else
        fail(TEXT.savedGone)
    end
end

-- Saved.lua loads after this file: the editor starts listening the first time it opens a saved alert.
local listening = false
local function listenToSaved()
    if not listening and CRT.AlertSaved then
        listening = true
        CRT.AlertSaved:OnChange(savedChanged)
    end
end

-- Fills the boxes from the draft and shows the window on top.
local function show()
    notice = nil
    setTitle()
    applyLayout(ctx.savedMode == true)
    if not ctx.savedMode and not draft.timeTouched then
        local ph, t = firstTime((Reminders:Times(ctx.encounterID, timesProbe())))
        if ph then
            draft.ph, draft.timeText = ph, clock(t, true)
        end
    end
    frame.textEdit:SetText(draft.text or "")
    frame.timeEdit:SetText(draft.timeText)
    local id = draft.iconType == "id" and draft.iconID or draft.spellID
    frame.idEdit:SetText(id and tostring(id) or "")
    -- Setting the boxes runs their change handlers, which read them back; the draft is already right.
    refresh(true)
    frame:Show()
    -- Above the Timeline pop-out and any other window it opened from.
    frame:Raise()
end

-- Opens the editor for a boss: one of your reminders (id), or a new alert. prefill is { spellID, text,
-- times, boss, ph, time, saveAs } from a spell, a Timeline row or a click on the Timeline: time is
-- seconds into phase ph, saveAs "note" or "mine". A new alert from a spell is named after it.
function Editor:Open(encounterID, id, prefill)
    build()
    ctx = { encounterID = encounterID }
    draft = newDraft()
    local saved = id and Reminders:Get(encounterID, id)
    local savedAlert = prefill and prefill.saved and CRT.AlertSaved and CRT.AlertSaved:Get(prefill.saved)
    if saved then
        ctx.id = id
        ctx.reminder = copy(saved)
        fromReminder(saved)
    else
        prefill = prefill or {}
        if savedAlert then
            fromSaved(savedAlert)
            -- a spell dropped on an icon replaces the saved alert's own, and its icon with it; text that
            -- only named its own spell (or none) becomes the new spell's name, typed text stays
            local dropped = validID(prefill.spellID)
            if dropped and dropped ~= savedAlert.spellID then
                draft.iconID, draft.iconType = nil, "spell"
                local own = validID(savedAlert.spellID)
                local ownName = own and Reminders.SpellName(own)
                local text = trim(draft.text)
                if text == "" or (ownName and text == trim(ownName)) then
                    draft.text = Reminders.SpellName(dropped) or ""
                end
            end
        end
        draft.spellID = validID(prefill.spellID) or (savedAlert and draft.spellID) or nil
        if type(prefill.text) == "string" and trim(prefill.text) ~= "" then
            draft.text = prefill.text
        elseif trim(draft.text) == "" then
            draft.text = (spellInfo(draft.spellID)) or ""
        end
        -- the caller's Save as wins over a saved alert's own (the Personal notes row asks for Only me)
        if prefill.saveAs == "note" or prefill.saveAs == "mine" then
            draft.saveAs = prefill.saveAs
        end
        if type(prefill.time) == "number" then
            draft.ph = type(prefill.ph) == "number" and prefill.ph or 1
            draft.timeText = clock(prefill.time, true) -- a click on the Timeline gives tenths
            draft.timeTouched = true
        elseif type(prefill.times) == "string" and trim(prefill.times) ~= "" then
            draft.keptTimes = prefill.times
        end
    end
    if prefill and prefill.boss and not draft.boss then
        draft.boss = prefill.boss
    end
    -- a new alert set to Raid note (a Timeline click, a saved alert) is your own when you can't change it
    if draft.saveAs == "note" and not canEditRaid() then
        draft.saveAs = "mine"
    end
    -- a reminder's own difficulty stays; a new one as a note line starts where the pull would read it
    draft.baseDifficulty = draft.difficulty
    applyDefaultDifficulty()
    show()
end

-- Opens a saved alert itself (nil for a new one): Save overwrites it. False when there is no such one.
function Editor:EditSaved(id)
    local Saved = CRT.AlertSaved
    local s = id and Saved and Saved:Get(id)
    if id and not s then
        return false
    end
    listenToSaved()
    build()
    ctx = { savedMode = true, savedID = id, savedName = s and s.name }
    draft = newDraft()
    if s then
        fromSaved(s)
    end
    show()
    return true
end

-- Opens a line of a raid note (its line number in the note). False when that line isn't a timed line.
-- A line without show: opens as it shows today: the Next spell alert and a bar, read out.
function Editor:OpenNote(noteID, lineNumber)
    local Notes = CRT.Notes
    local record = Notes and Notes:Get(noteID)
    local timer, raw
    if record then
        timer, raw = Notes:TimerAt(noteID, lineNumber)
    end
    if not timer then
        return false
    end
    build()
    ctx = { encounterID = record.encounterID, noteID = noteID, line = lineNumber, expected = raw,
        timer = copy(timer), noteDifficulty = record.difficulty }
    draft = newDraft()
    draft.saveAs = "note"
    draft.boss = record.name
    draft.difficulty = record.difficulty
    -- a one-word class tag reads back as its class choice; a line with no tag as No one
    draft.tag = #(timer.tags or {}) == 1 and classTag(timer.tags[1]) or table.concat(timer.tags or {}, " ")
    ctx.untagged = draft.tag == ""
    draft.ph = timer.ph or 1
    draft.timeText = clock(timer.time or 0, true)
    draft.timeTouched = true
    draft.spellID = validID(timer.spellId)
    draft.text = timer.text or ""
    draft.color = copy(timer.color)
    if timer.show then
        for _, k in ipairs(SHOW_KEYS) do
            draft.show[k] = timer.show[k] and true or false
        end
        draft.speak, draft.count = timer.tts and true or false, timer.count and true or false
        draft.glow = timer.glow and true or false
        draft.sound = timer.sound
        draft.linger = timer.linger or 0
        draft.iconID = validID(timer.iconID)
        draft.iconType = draft.iconID and "id" or "spell"
    end
    local s = Notes:Alert() or {}
    draft.warn = timer.warn or s.seconds or 10
    -- someone who can't change the raid note only sees it, and may copy it to their reminders
    if not canEditRaid() then
        ctx.readOnly = true
    end
    show()
    return true
end

-- Copy to my reminders, on a read-only raid note line: the draft becomes a new reminder of your own with
-- the line's fields (spell, text, colour, displays, speech, sound, glow, Show from, Linger, icon) and
-- its time as "P<ph> <time>", for any difficulty. Nothing is saved until Save. False when not read-only.
function Editor:CopyToMine()
    if not (ctx and draft and ctx.readOnly and type(ctx.encounterID) == "number") then
        return false
    end
    local t = parseTime(draft.timeText)
    ctx = { encounterID = ctx.encounterID }
    draft.saveAs = "mine"
    draft.tag = "everyone"
    draft.difficulty, draft.baseDifficulty, draft.difficultyTouched = nil, nil, nil
    draft.keptTimes = t and Reminders.FormatTimes({ { ph = draft.ph or 1, t = t } }) or nil
    draft.timeTouched = false
    show()
    return true
end
