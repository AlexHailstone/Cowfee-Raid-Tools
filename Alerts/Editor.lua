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

local TEXT = {
    title = "Alert",
    saveAs = "Save as",
    asNote = "Raid note",
    asMine = "Only me",
    forLabel = "For",
    everyone = "Everyone",
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

local frame, exportFrame
-- ctx: where the draft came from. { encounterID, id (a reminder) and reminder (its saved copy), or
-- noteID, line, expected (the raw line), timer and noteDifficulty for a note line }
local ctx
-- draft: the fields on screen. { saveAs, tag, difficulty, ph, timeText, timeTouched, keptTimes, spellID,
-- iconType, iconID, text, color, show = { alert, text, icon, bar, circle }, speak, count, glow, sound,
-- warn, linger, boss }
local draft
local notice -- the message from the last Save, Test or Delete, shown until the draft changes
local testItems
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

-- The message for a time that does not read; `strict` (Save and Test) also asks a note line for one.
-- A reminder's kept times text is checked while Relative to and Time are untouched.
local function timeError(strict)
    if not draft.timeTouched and draft.saveAs == "mine" and draft.keptTimes then
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

-- Who a note line is for, as its tag: Everyone (no tag), you, a role, a class, a group or a name; and
-- the line's own tag when none of those is it.
local function forOptions()
    local out, seen = {}, {}
    local function add(key, label)
        if not seen[key:lower()] then
            seen[key:lower()] = true
            out[#out + 1] = { key = key, label = label }
        end
    end
    add("", TEXT.everyone)
    local me = playerName()
    if me then
        add(me, TEXT.me)
    end
    add("tank", TEXT.tanks)
    add("healer", TEXT.healers)
    add("dps", TEXT.damage)
    add("melee", TEXT.melee)
    add("ranged", TEXT.ranged)
    -- a class as one word, so the line's tag reads back as one choice
    for i = 1, GetNumClasses and GetNumClasses() or 0 do
        local name = GetClassInfo(i)
        if readable(name) and type(name) == "string" and name ~= "" then
            add((name:gsub("%s+", "")), name)
        end
    end
    for g = 1, 8 do
        add("G" .. g, string.format(TEXT.group, g))
    end
    for _, name in ipairs(roster()) do
        add(name, name)
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

local function sourceLine()
    if draft.timeTouched or draft.saveAs == "note" then
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

-- Everything on the window from the draft, except the boxes being typed in. `rows` also redraws the
-- dropdowns and sliders (on open and when one of them is set), so typing never rebuilds their menus.
local function refresh(rows)
    if not (frame and draft) then
        return
    end
    frame.forRow:SetShown(draft.saveAs == "note")
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
    local message = timeError(false) or notice
    frame.messageText:SetText(message and ("|cffff6060" .. message .. "|r") or "")
    frame.deleteBtn:SetShown(ctx ~= nil and (ctx.id ~= nil or ctx.noteID ~= nil))
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

function Editor:Close()
    if frame then
        frame:Hide()
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
    local encounterID = ctx.encounterID
    if type(encounterID) ~= "number" then
        return fail(TEXT.noBoss)
    end
    local Notes = CRT.Notes
    local line = CRT.NoteParser.FormatLine(noteTimer())
    local difficulty = draft.difficulty and trim(draft.difficulty) or nil
    if ctx.noteID then
        if not lineUnchanged() then
            return fail(TEXT.stale)
        end
        if lower(ctx.noteDifficulty) == lower(difficulty) then
            if not Notes:ReplaceLine(ctx.noteID, ctx.line, line, ctx.expected) then
                return fail(TEXT.stale)
            end
            Editor:Close()
            return true
        end
    end
    -- a new line, or one moving here from a reminder or another difficulty's note
    if not Notes:AddLine(encounterID, difficulty, draft.boss, line) then
        return fail(TEXT.noteFailed)
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

-- Saves the draft and closes. A time that does not read, nothing ticked, or a note line changed
-- elsewhere leaves the window open with the message shown.
function Editor:Save()
    if not (ctx and draft) then
        return false
    end
    local err = timeError(true)
    if err then
        return fail(err)
    end
    if not anyOutput() then
        return fail(TEXT.nothing)
    end
    if draft.saveAs == "note" then
        return saveNote()
    end
    return saveMine()
end

-- Runs the draft alone as a test, starting TEST_LEAD seconds before its first time. Saves nothing.
function Editor:Test()
    if not (ctx and ctx.encounterID and draft) then
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
        local t = noteTimer()
        local item = CRT.NoteEngine.ItemFor(t, 1, true)
        item.id = "note:test:1"
        item.block = "note"
        items, lowest, first = { item }, t.ph, t.time
    else
        local r = buildReminder()
        local list = Reminders:Times(ctx.encounterID, r)
        if #list == 0 then
            refresh()
            return false
        end
        lowest, first = firstTime(list)
        items = Reminders:Items(ctx.encounterID, "test", r)
    end
    testItems = items
    Alerts:Start(ctx.encounterID, nil, "test", {
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

local function makeLabel(parent, label, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(label)
    return fs
end

-- onChange(text, userInput): userInput is false when the editor itself set the text.
local function makeEdit(parent, x, y, width, onChange)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontEdit)
    edit:SetSize(width, 20)
    edit:SetPoint("TOPLEFT", x, y)
    edit:SetScript("OnTextChanged", function(self, userInput)
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
    check:SetPoint("TOPLEFT", x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check.label = text
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return check
end

-- A setter for a dropdown, slider or checkbox: edits the draft (when there is one) and redraws.
local function setter(fn)
    return function(v)
        if draft then
            fn(v)
            changed(true)
        end
    end
end

local function applyPosition()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
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
    x:SetSize(WIDTH - 40, 84)
    x:SetPoint("CENTER", frame, "CENTER", 0, 0)
    x:SetClampedToScreen(true)
    x:EnableMouse(true)
    UI:RegisterLayer("panel", x)
    UI.SetFrameTitle(x, TEXT.exportTitle)
    tinsert(UISpecialFrames, EXPORT_NAME)
    x.text = ""
    x.edit = makeEdit(x, LEFT + 4, -40, WIDTH - 88, function(_, userInput)
        if userInput then
            x.edit:SetText(x.text)
            x.edit:HighlightText()
        end
    end)
    x.edit:SetScript("OnEscapePressed", function()
        x:Hide()
    end)
    x.edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    UI:SkinTree(x)
    x:Hide()
end

-- Shows the draft as a note line in the copy box. Saves nothing. Returns the line.
function Editor:Export()
    if not (frame and draft) then
        return nil
    end
    -- a note line needs a time that reads, as Save does
    local err = timeError(true) or (parseTime(draft.timeText) == nil and TEXT.noTime or nil)
    if err then
        fail(err)
        return nil
    end
    buildExport()
    local line = CRT.NoteParser.FormatLine(noteTimer())
    exportFrame.text = line
    exportFrame.edit:SetText(line)
    exportFrame:Show()
    exportFrame:Raise()
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
    return line
end

-- The game's color picker on the draft's color; Cancel puts the old one back.
local function pickColor()
    if not (draft and ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
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
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI:RegisterLayer("panel", f)
    -- Previews never touch an alert being edited: on opens an empty editor only when none is open,
    -- and off closes only the one Previews opened.
    UI:RegisterPreview("alerteditor", function(on)
        local open = draft ~= nil and frame:IsShown()
        if on then
            if not open then
                Editor:Open(nil, nil)
                previewDraft = draft
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
        if exportFrame then
            exportFrame:Hide()
        end
    end)
    f.rows = {}
    local function row(r, x, y)
        r:SetPoint("TOPLEFT", x, y)
        f.rows[#f.rows + 1] = r
        return r
    end

    -- Save as, For, Difficulty
    row(UI.Dropdown(f, TEXT.saveAs, {
        labelWidth = 56, width = 118,
        options = { { key = "note", label = TEXT.asNote }, { key = "mine", label = TEXT.asMine } },
        get = function() return draft and draft.saveAs or "mine" end,
        set = setter(function(v) draft.saveAs = v end),
    }), LEFT, -30)
    f.forRow = row(UI.Dropdown(f, TEXT.forLabel, {
        labelWidth = 30, width = 160, maxHeight = MENU_MAX_HEIGHT,
        options = forOptions,
        get = function() return draft and draft.tag or "" end,
        set = setter(function(v) draft.tag = v end),
    }), 205, -30)
    row(UI.Dropdown(f, TEXT.difficulty, {
        labelWidth = 60, width = 114,
        options = difficultyOptions,
        get = function() return draft and draft.difficulty or ANY end,
        set = setter(function(v) draft.difficulty = v ~= ANY and v or nil end),
    }), 405, -30)

    -- Relative to, Time
    row(UI.Dropdown(f, TEXT.relativeTo, {
        labelWidth = 70, width = 120,
        options = phaseOptions,
        get = function() return draft and draft.ph or 1 end,
        set = setter(function(v)
            draft.ph = v
            draft.timeTouched = true
        end),
    }), LEFT, -64)
    makeLabel(f, TEXT.time, 226, -74)
    f.timeEdit = makeEdit(f, 264, -70, 64, function(text, userInput)
        if draft then
            draft.timeText = text
            if userInput then
                draft.timeTouched = true
            end
            changed()
        end
    end)
    UI.Help(f, TEXT.timeHelpTitle, TEXT.timeHelp):SetPoint("TOPLEFT", 332, -72)
    f.sourceText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    f.sourceText:SetPoint("TOPLEFT", 360, -74)
    f.sourceText:SetWidth(WIDTH - 360 - LEFT)
    f.sourceText:SetJustifyH("LEFT")
    f.sourceText:SetWordWrap(false)

    -- Show from, Linger
    row(UI.Slider(f, TEXT.showFrom, {
        min = 1, max = 60, step = 1, labelWidth = 70, width = 150,
        format = function(v) return string.format(TEXT.seconds, v) end,
        get = function() return draft and draft.warn or 5 end,
        set = setter(function(v) draft.warn = v end),
    }), LEFT, -98)
    row(UI.Slider(f, TEXT.linger, {
        min = 0, max = 10, step = 1, labelWidth = 50, width = 150,
        format = function(v) return string.format(TEXT.seconds, v) end,
        get = function() return draft and draft.linger or 0 end,
        set = setter(function(v) draft.linger = v end),
    }), 306, -98)

    -- Icon: Spell or Icon ID, the ID box and a preview
    row(UI.Dropdown(f, TEXT.icon, {
        labelWidth = 70, width = 110,
        options = { { key = "spell", label = TEXT.iconSpell }, { key = "id", label = TEXT.iconID } },
        get = function() return draft and draft.iconType or "spell" end,
        set = function(v)
            if draft then
                draft.iconType = v
                local id = v == "id" and draft.iconID or draft.spellID
                f.idEdit:SetText(id and tostring(id) or "")
                changed(true)
            end
        end,
    }), LEFT, -132)
    f.idEdit = makeEdit(f, 212, -138, 80, function(text)
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
    UI.Help(f, TEXT.iconHelpTitle, TEXT.iconHelp):SetPoint("TOPLEFT", 296, -140)
    f.iconPreview = f:CreateTexture(nil, "ARTWORK")
    f.iconPreview:SetSize(24, 24)
    f.iconPreview:SetPoint("TOPLEFT", 326, -136)
    f.iconPreview:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.spellName = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    f.spellName:SetPoint("TOPLEFT", 358, -142)
    f.spellName:SetWidth(WIDTH - 358 - LEFT)
    f.spellName:SetJustifyH("LEFT")
    f.spellName:SetWordWrap(false)

    -- Text
    makeLabel(f, TEXT.text, LEFT, -178)
    f.textEdit = makeEdit(f, FIELD_X + 4, -174, WIDTH - FIELD_X - LEFT - 8, function(text)
        if draft then
            draft.text = text
            changed()
        end
    end)

    -- Color: a swatch that opens the game's color picker, and Default for none
    makeLabel(f, TEXT.color, LEFT, -210)
    f.colorSwatch = CreateFrame("Button", nil, f)
    f.colorSwatch:SetSize(20, 20)
    f.colorSwatch:SetPoint("TOPLEFT", FIELD_X, -206)
    f.colorSwatch.edge = f.colorSwatch:CreateTexture(nil, "BACKGROUND")
    f.colorSwatch.edge:SetAllPoints()
    f.colorSwatch.edge:SetColorTexture(0.5, 0.5, 0.5, 1)
    f.colorSwatch.tex = f.colorSwatch:CreateTexture(nil, "ARTWORK")
    f.colorSwatch.tex:SetPoint("TOPLEFT", 1, -1)
    f.colorSwatch.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.colorSwatch:SetScript("OnClick", pickColor)
    f.colorDefault = makeButton(f, TEXT.colorDefault, 80)
    f.colorDefault:SetPoint("TOPLEFT", FIELD_X + 28, -204)
    f.colorDefault:SetScript("OnClick", function()
        if draft then
            draft.color = nil
            changed()
        end
    end)

    -- Show as
    makeLabel(f, TEXT.showAs, LEFT, -246)
    f.checks = {}
    for _, spec in ipairs({ { "alert", TEXT.nextSpell, FIELD_X }, { "text", TEXT.showText, 226 },
        { "icon", TEXT.showIcon, 296 }, { "bar", TEXT.bar, 366 }, { "circle", TEXT.circle, 430 } }) do
        local key = spec[1]
        f.checks[key] = makeCheck(f, spec[2], spec[3], -240, setter(function(on) draft.show[key] = on end))
    end

    -- Also
    makeLabel(f, TEXT.also, LEFT, -280)
    f.also = {
        speak = makeCheck(f, TEXT.speak, FIELD_X, -274, setter(function(on) draft.speak = on end)),
        count = makeCheck(f, TEXT.count, 226, -274, setter(function(on) draft.count = on end)),
        glow = makeCheck(f, TEXT.glow, 386, -274, setter(function(on) draft.glow = on end)),
    }
    row(UI.Dropdown(f, TEXT.sound, {
        labelWidth = 70, width = 160, maxHeight = MENU_MAX_HEIGHT,
        options = soundOptions,
        get = function() return draft and draft.sound or NO_SOUND end,
        set = setter(function(v) draft.sound = v ~= NO_SOUND and v or nil end),
    }), LEFT, -304)

    f.messageText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    f.messageText:SetPoint("TOPLEFT", LEFT, -350)
    f.messageText:SetWidth(WIDTH - 2 * LEFT)
    f.messageText:SetJustifyH("LEFT")

    -- Buttons
    f.deleteBtn = makeButton(f, TEXT.delete, 80)
    f.deleteBtn:SetPoint("BOTTOMLEFT", LEFT, 14)
    f.deleteBtn:SetScript("OnClick", function()
        if not (ctx and (ctx.id or ctx.noteID)) then
            return
        end
        local from = ctx
        StaticPopup_ShowCustomGenericConfirmation({
            text = TEXT.deleteConfirm,
            acceptText = TEXT.delete,
            cancelText = TEXT.cancel,
            showAlert = true,
            callback = function()
                if from.noteID then
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
    return { saveAs = "mine", tag = "", ph = 1, timeText = "", timeTouched = false, iconType = "spell",
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

-- Fills the boxes from the draft and shows the window on top.
local function show()
    notice = nil
    if not draft.timeTouched then
        local ph, t = firstTime((Reminders:Times(ctx.encounterID, timesProbe())))
        if ph then
            draft.ph, draft.timeText = ph, clock(t)
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
    if saved then
        ctx.id = id
        ctx.reminder = copy(saved)
        fromReminder(saved)
    else
        prefill = prefill or {}
        draft.spellID = validID(prefill.spellID)
        if type(prefill.text) == "string" and trim(prefill.text) ~= "" then
            draft.text = prefill.text
        else
            draft.text = (spellInfo(draft.spellID)) or ""
        end
        if prefill.saveAs == "note" then
            draft.saveAs = "note"
        end
        if type(prefill.time) == "number" then
            draft.ph = type(prefill.ph) == "number" and prefill.ph or 1
            draft.timeText = clock(prefill.time)
            draft.timeTouched = true
        elseif type(prefill.times) == "string" and trim(prefill.times) ~= "" then
            draft.keptTimes = prefill.times
        end
    end
    if prefill and prefill.boss and not draft.boss then
        draft.boss = prefill.boss
    end
    show()
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
    draft.tag = table.concat(timer.tags or {}, " ")
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
    show()
    return true
end
