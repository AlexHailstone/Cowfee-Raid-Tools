local ADDON, CRT = ...

-- The reminder editor: one window for a new or saved reminder. It opens from the Reminders tab and from
-- a double-click on the Timeline, edits a draft copy, and saves through CRT.AlertReminders. Test runs
-- the draft as it stands on screen without saving anything: the draft's items go to a block of their
-- own ("minetest") that gives them out only to a run started with reason "test".

local TEXT = {
    title = "Reminder",
    own = "Your own reminder",
    text = "Text",
    times = "Times",
    timesHelpTitle = "Times",
    timesHelp = "Type times as minutes:seconds or plain seconds, with a phase in front when it is not "
        .. "the first: P1 0:02, 1:17; P2 +0:18.\n\nLeave the box empty to use the boss's reference.",
    fromPrefix = "From ",
    typed = "Typed",
    none = "No times",
    useReference = "Use reference",
    showAs = "Show as",
    nextSpell = "Next spell alert",
    bar = "Bar",
    speech = "Speech",
    icon = "Icon",
    circle = "Circle",
    flash = "Screen flash",
    laterHelpTitle = "Coming later",
    laterHelp = "Icon, Circle and Screen flash arrive in a later version.",
    warn = "Warn",
    warnFormat = "%d s",
    speechLabel = "Speech",
    speechText = "Text",
    speechTextCount = "Text, then 3 2 1",
    speechCount = "3 2 1 only",
    priority = "Priority",
    high = "High",
    normal = "Normal",
    low = "Low",
    difficulty = "Difficulty",
    any = "Any",
    delete = "Delete",
    deleteConfirm = "Delete this reminder?",
    test = "Test",
    save = "Save",
    cancel = CANCEL or "Cancel",
    dragHint = "Reminder: drag to move",
    testInPull = "Test is off during a pull.",
    testTrigger = "Nothing to test: this reminder starts in phase %s, which waits for its trigger.",
}

local Alerts = CRT.Alerts
local Reminders = CRT.AlertReminders
local UI = CRT.UI

local Editor = {}
CRT.AlertEditor = Editor

local TEST_BLOCK = "minetest"
local TEST_LEAD = 10 -- a test starts this many seconds before the reminder's first time
local ANY = "any"    -- the difficulty dropdown's key for "any difficulty" (saved as nil)
local FRAME_NAME = "CowfeeRaidToolsAlertEditor"
local LABEL_W = 90

local frame
local ctx   -- { encounterID, id }
local draft -- the reminder being edited, in the saved shape
local testItems
local previewDraft -- the empty draft Previews opened, so Previews only ever closes that one

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
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

local function spellInfo(id)
    if type(id) ~= "number" or id <= 0 then
        return nil, nil
    end
    local name = Reminders.SpellName(id)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex ~= nil and CRT.Timeline.readable(tex) then
            icon = tex
        end
    end
    return name, icon
end

-- The times of the draft: the list, where they come from and the message for times that do not read.
local function timesState()
    local list, source, err = Reminders:Times(ctx and ctx.encounterID, draft)
    return list, source, err
end

local function sourceLine(source)
    if source == "reference" then
        local ref = Reminders.ReferenceFor(ctx and ctx.encounterID, draft)
        if ref then
            return TEXT.fromPrefix .. CRT.TimelineReference.Label(ref)
        end
    elseif source == "typed" then
        return TEXT.typed
    end
    return TEXT.none
end

-- The difficulties of the boss's references, "Any" first, and the reminder's own if none matches it.
local function difficultyOptions()
    local out = { { key = ANY, label = TEXT.any } }
    local seen = {}
    local function add(d)
        if type(d) == "string" and trim(d) ~= "" and not seen[d:lower()] then
            seen[d:lower()] = true
            out[#out + 1] = { key = d, label = d }
        end
    end
    local Ref = CRT.TimelineReference
    if Ref and ctx then
        for _, entry in ipairs(Ref:ForBoss(ctx.encounterID, draft and draft.boss)) do
            add(entry.ref.difficulty)
        end
    end
    add(draft and draft.difficulty)
    return out
end

-- Everything on the window from the draft.
local function refresh()
    if not (frame and draft) then
        return
    end
    local name, icon = spellInfo(draft.spellID)
    frame.nameText:SetText(name or (draft.spellID and trim(draft.text) ~= "" and draft.text) or TEXT.own)
    frame.icon:SetTexture(icon)
    frame.icon:SetShown(icon ~= nil)

    local list, source, err = timesState()
    frame.sourceText:SetText(sourceLine(source))
    frame.errorText:SetText(err and ("|cffff6060" .. err .. "|r") or "")
    frame.useRef:SetEnabled(draft.times ~= nil)
    frame.deleteBtn:SetShown(ctx and ctx.id ~= nil)

    frame.checks.alert:SetChecked(draft.outputs.alert and true or false)
    frame.checks.bar:SetChecked(draft.outputs.bar and true or false)
    frame.checks.speech:SetChecked(draft.outputs.speech and true or false)
    frame.warnRow.refresh()
    frame.speechRow.refresh()
    frame.priorityRow.refresh()
    frame.diffRow.refresh()
end

-- Saving and testing ----------------------------------------------------------------------------

function Editor:Close()
    if frame then
        frame:Hide()
    end
    ctx, draft = nil, nil
end

-- Saves the draft and closes. Times that do not read leave the window open with the message shown.
function Editor:Save()
    if not (ctx and ctx.encounterID and draft) then
        return false
    end
    local _, _, err = timesState()
    if err then
        refresh()
        return false
    end
    local r = copy(draft)
    r.text = trim(r.text)
    local id = Reminders:Save(ctx.encounterID, ctx.id, r)
    if not id then
        return false
    end
    Editor:Close()
    return true
end

-- Runs the draft alone as a test, starting TEST_LEAD seconds before its first time. Saves nothing.
function Editor:Test()
    if not (ctx and ctx.encounterID and draft) then
        return false
    end
    -- A real pull is never cut short by a test.
    if Alerts.running and Alerts.run and Alerts.run.reason == "encounter" then
        CRT:Print(TEXT.testInPull)
        return false
    end
    local list, _, err = timesState()
    if err or #list == 0 then
        refresh()
        return false
    end
    local r = copy(draft)
    r.text = trim(r.text)
    local lowest, first
    for _, t in ipairs(list) do
        if not lowest or t.ph < lowest then
            lowest, first = t.ph, t.t
        elseif t.ph == lowest and t.t < first then
            first = t.t
        end
    end
    testItems = Reminders:Items(ctx.encounterID, "test", r)
    Alerts:Start(ctx.encounterID, nil, "test", {
        blocks = { [TEST_BLOCK] = true },
        filter = function(_, item)
            return type(item.id) == "string" and item.id:find("^mine:test:") ~= nil
        end,
        firstAt = GetTime() + TEST_LEAD - first,
    })
    testItems = nil
    -- A lowest phase with an event trigger waits for its event, so the test would show nothing.
    if Alerts.running and Alerts.run and Alerts.run.reason == "test" and not Alerts:PhaseStart(lowest) then
        Alerts:Stop()
        CRT:Print(string.format(TEXT.testTrigger, tostring(lowest)))
        return false
    end
    return true
end

-- The draft's items, given out once and only to a test run.
Alerts:RegisterBlock(TEST_BLOCK, { label = "Reminder test", group = true, Entries = function(run)
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

local function makeEdit(parent, x, y, width, onChange)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontEdit)
    edit:SetSize(width, 20)
    edit:SetPoint("TOPLEFT", x, y)
    edit:SetScript("OnTextChanged", function(self)
        onChange(self:GetText())
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

local function applyPosition()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

function Editor:ResetPosition()
    if frame then
        applyPosition()
    end
end

local function build()
    if frame then
        return
    end
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
    frame = f
    f:SetSize(440, 450)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI:RegisterLayer("panel", f)
    -- Previews never touch a reminder being edited: on opens an empty editor only when none is open,
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

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("TOPLEFT", 16, -34)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.nameText = f:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    f.nameText:SetPoint("TOPLEFT", 58, -42)

    makeLabel(f, TEXT.text, 16, -88)
    f.textEdit = makeEdit(f, 110, -84, 300, function(value)
        if draft then
            draft.text = value
            refresh()
        end
    end)

    makeLabel(f, TEXT.times, 16, -118)
    UI.Help(f, TEXT.timesHelpTitle, TEXT.timesHelp):SetPoint("TOPLEFT", 60, -116)
    f.timesEdit = makeEdit(f, 110, -114, 300, function(value)
        if draft then
            draft.times = trim(value) ~= "" and trim(value) or nil
            refresh()
        end
    end)
    f.sourceText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    f.sourceText:SetPoint("TOPLEFT", 110, -140)
    f.sourceText:SetWidth(190)
    f.sourceText:SetJustifyH("LEFT")
    f.sourceText:SetWordWrap(false)
    f.useRef = makeButton(f, TEXT.useReference, 110)
    f.useRef:SetPoint("TOPLEFT", 306, -135)
    f.useRef:SetScript("OnClick", function()
        f.timesEdit:SetText("")
        if draft then
            draft.times = nil
            refresh()
        end
    end)
    f.errorText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    f.errorText:SetPoint("TOPLEFT", 110, -162)
    f.errorText:SetWidth(300)
    f.errorText:SetJustifyH("LEFT")

    makeLabel(f, TEXT.showAs, 16, -192)
    f.checks = {}
    local function output(key, label, x, y)
        f.checks[key] = makeCheck(f, label, x, y, function(on)
            if draft then
                draft.outputs[key] = on
            end
        end)
    end
    output("alert", TEXT.nextSpell, 106, -186)
    output("bar", TEXT.bar, 246, -186)
    output("speech", TEXT.speech, 316, -186)
    for i, spec in ipairs({ { "icon", TEXT.icon, 106 }, { "circle", TEXT.circle, 186 }, { "flash", TEXT.flash, 266 } }) do
        local c = makeCheck(f, spec[2], spec[3], -212, function() end)
        c:SetChecked(false)
        c:SetEnabled(false)
        c.label:SetFontObject(CRTFontDisableSmall)
        f.checks[spec[1]] = c
    end
    UI.Help(f, TEXT.laterHelpTitle, TEXT.laterHelp):SetPoint("TOPLEFT", 390, -216)

    f.warnRow = UI.Slider(f, TEXT.warn, {
        min = 1, max = 30, step = 1, labelWidth = LABEL_W, width = 180,
        format = function(v) return string.format(TEXT.warnFormat, v) end,
        get = function() return draft and draft.warn or 5 end,
        set = function(v) if draft then draft.warn = v end end,
    })
    f.warnRow:SetPoint("TOPLEFT", 16, -244)

    f.speechRow = UI.Dropdown(f, TEXT.speechLabel, {
        labelWidth = LABEL_W, width = 200,
        options = {
            { key = "text", label = TEXT.speechText },
            { key = "textcount", label = TEXT.speechTextCount },
            { key = "count", label = TEXT.speechCount },
        },
        get = function() return draft and draft.speech or "text" end,
        set = function(v) if draft then draft.speech = v end end,
    })
    f.speechRow:SetPoint("TOPLEFT", 16, -278)

    f.priorityRow = UI.Dropdown(f, TEXT.priority, {
        labelWidth = LABEL_W, width = 200,
        options = {
            { key = "high", label = TEXT.high },
            { key = "normal", label = TEXT.normal },
            { key = "low", label = TEXT.low },
        },
        get = function() return draft and draft.priority or "normal" end,
        set = function(v) if draft then draft.priority = v end end,
    })
    f.priorityRow:SetPoint("TOPLEFT", 16, -312)

    f.diffRow = UI.Dropdown(f, TEXT.difficulty, {
        labelWidth = LABEL_W, width = 200,
        options = difficultyOptions,
        get = function() return draft and draft.difficulty or ANY end,
        set = function(v) if draft then draft.difficulty = v ~= ANY and v or nil end end,
    })
    f.diffRow:SetPoint("TOPLEFT", 16, -346)

    f.deleteBtn = makeButton(f, TEXT.delete, 90)
    f.deleteBtn:SetPoint("BOTTOMLEFT", 16, 14)
    f.deleteBtn:SetScript("OnClick", function()
        if not (ctx and ctx.id) then
            return
        end
        local encounterID, id = ctx.encounterID, ctx.id
        StaticPopup_ShowCustomGenericConfirmation({
            text = TEXT.deleteConfirm,
            acceptText = TEXT.delete,
            cancelText = TEXT.cancel,
            showAlert = true,
            callback = function()
                Reminders:Delete(encounterID, id)
                Editor:Close()
            end,
        })
    end)
    f.testBtn = makeButton(f, TEXT.test, 90)
    f.testBtn:SetPoint("BOTTOMRIGHT", -116, 14)
    f.testBtn:SetScript("OnClick", function()
        Editor:Test()
    end)
    f.saveBtn = makeButton(f, TEXT.save, 90)
    f.saveBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    f.saveBtn:SetScript("OnClick", function()
        Editor:Save()
    end)
    f:Hide()
end

-- Opens the editor for a boss: a saved reminder (id), or a new one. prefill is { spellID, text, times,
-- boss } from a spell or a Timeline row; a new reminder from a spell is named after it.
function Editor:Open(encounterID, id, prefill)
    build()
    ctx = { encounterID = encounterID, id = id }
    local saved = id and Reminders:Get(encounterID, id)
    if saved then
        draft = copy(saved)
    else
        ctx.id = nil
        prefill = prefill or {}
        draft = { spellID = prefill.spellID, text = prefill.text, times = prefill.times,
            boss = prefill.boss }
        if type(draft.times) ~= "string" or trim(draft.times) == "" then
            draft.times = nil
        end
        if type(draft.text) ~= "string" or trim(draft.text) == "" then
            draft.text = (spellInfo(draft.spellID)) or ""
        end
    end
    if prefill and prefill.boss and not draft.boss then
        draft.boss = prefill.boss
    end
    draft.outputs = draft.outputs or {}
    for _, k in ipairs({ "alert", "bar", "speech" }) do
        if draft.outputs[k] == nil then
            draft.outputs[k] = true
        end
    end
    draft.warn = draft.warn or 5
    draft.speech = draft.speech or "text"
    draft.priority = draft.priority or "normal"
    frame.textEdit:SetText(draft.text or "")
    frame.timesEdit:SetText(draft.times or "")
    -- Setting the boxes runs their change handlers, which read them back; the draft is already right.
    refresh()
    frame:Show()
    -- Above the Timeline pop-out and any other window it opened from.
    frame:Raise()
end
