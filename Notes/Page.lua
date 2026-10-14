local ADDON, CRT = ...

-- The Raid Notes page, with two tabs:
--   Notes     the list of notes (one per boss), the text of the selected one, importing, sharing with
--             the group, the roster link to Raid Groups, your personal note, and a test run
--   Settings  the three note windows, your alert and sharing (Notes/Settings.lua)
-- The note windows and your alert are moved with "Toggle previews".

local Notes = CRT.Notes
local Engine = CRT.NoteEngine
local UI = CRT.UI

local ROW_H = 24
local MAX_ROWS = 9

local GRAY = { 0.35, 0.35, 0.35 }
local GOLD = { 1, 0.82, 0 }
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local page, rows, editor, status, selected = nil, {}, nil, nil, nil
local controls = {}
local importDialog
local refresh

local function skin(frame, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, alpha or 0.5)
    frame:SetBackdropBorderColor(GRAY[1], GRAY[2], GRAY[3], 1)
end

-- The edit box only covers the lines it holds, so a click on the empty part of its box would do
-- nothing. This makes the whole box and its scroll area put the cursor at the end of the text.
local function clickToType(box, scroll, edit)
    local function focus()
        edit:SetFocus()
        edit:SetCursorPosition(#(edit:GetText() or ""))
    end
    for _, frame in ipairs({ box, scroll }) do
        frame:EnableMouse(true)
        frame:SetScript("OnMouseDown", focus)
    end
end

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 24)
    b:SetText(label)
    return b
end

-- Import dialog: paste a note. -------------------------------------------------------------

local function getImportDialog()
    if importDialog then
        return importDialog
    end
    local d = CreateFrame("Frame", "CowfeeRaidToolsNoteImport", UIParent, "BasicFrameTemplateWithInset")
    d:SetSize(560, 420)
    d:SetPoint("CENTER")
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CowfeeRaidToolsNoteImport")
    UI.SetFrameTitle(d, "Import a raid note (paste it below)")

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsNoteImportScroll", d, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -34)
    scroll:SetPoint("BOTTOMRIGHT", -34, 46)
    d.edit = CreateFrame("EditBox", nil, scroll)
    d.edit:SetMultiLine(true)
    d.edit:SetAutoFocus(false)
    d.edit:SetFontObject(ChatFontNormal)
    d.edit:SetWidth(500)
    d.edit:SetScript("OnEscapePressed", function()
        d:Hide()
    end)
    scroll:SetScrollChild(d.edit)

    local ok = makeButton(d, "Import", 110, 26)
    ok:SetPoint("BOTTOM", -60, 12)
    ok:SetScript("OnClick", function()
        local id, message = Notes:Import(d.edit:GetText(), nil)
        CRT:Print(message)
        if id then
            selected = id
            d:Hide()
            refresh()
        end
    end)
    local cancel = makeButton(d, CANCEL, 110, 26)
    cancel:SetPoint("BOTTOM", 60, 12)
    cancel:SetScript("OnClick", function()
        d:Hide()
    end)
    d:Hide()
    importDialog = d
    return d
end

-- The page ---------------------------------------------------------------------------------

local function selectedNote()
    if selected and Notes:Get(selected) then
        return selected, Notes:Get(selected)
    end
    local activeId = Notes:Active()
    if activeId then
        selected = activeId
        return activeId, Notes:Get(activeId)
    end
    local list = Notes:List()
    if list[1] then
        selected = list[1].id
        return selected, list[1].record
    end
    selected = nil
    return nil
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    local id, record = selectedNote()
    local activeId = Notes:Active()

    local list = Notes:List()
    for i = 1, MAX_ROWS do
        local row = rows[i]
        local entry = list[i]
        if entry then
            local r = entry.record
            local label = (r.name or "Note") .. (r.difficulty and (" (" .. r.difficulty .. ")") or "")
            if entry.id == activeId then
                label = label .. "  |cff55dd55active|r"
            end
            row.text:SetText(label)
            row.id = entry.id
            local color = entry.id == id and GOLD or GRAY
            row:SetBackdropBorderColor(color[1], color[2], color[3], 1)
            row:Show()
        else
            row:Hide()
        end
    end

    if not editor:HasFocus() then
        editor:SetText(record and record.raw or "")
    end

    local lines = {}
    if record then
        lines[#lines + 1] = "Updated " .. (record.updated or "?") .. (record.from and (", shared by " .. record.from) or "")
        if record.presetId and CRT.Groups:Find(record.presetId) then
            lines[#lines + 1] = "Roster: linked to a Raid Groups layout"
        end
    end
    local sent, total = CRT.NoteComm:Sharing()
    if sent then
        lines[#lines + 1] = format("Sharing: %d of %d parts sent", sent, total)
    end
    if Engine.running then
        lines[#lines + 1] = "Running: phase " .. tostring(Engine:CurrentPhase()) .. (Engine.reason == "test" and " (test)" or "")
    end
    status:SetText(table.concat(lines, "\n"))

    for _, control in ipairs(controls) do
        control.refresh()
    end
end

local function buildNotes(pf)
    page = pf

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -6)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")
    hint:SetText("Import a note, share it with the raid before the pull, and its timers count down from the start of the fight. The note's other text goes to the Assignments window. Window, alert and sharing settings are on the Settings tab.")

    -- Left: the notes.
    local listLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    listLabel:SetPoint("TOPLEFT", 8, -42)
    listLabel:SetText("Notes")
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, pf, "BackdropTemplate")
        row:SetSize(250, ROW_H - 2)
        row:SetPoint("TOPLEFT", 8, -64 - (i - 1) * ROW_H)
        skin(row, 0.45)
        row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            selected = self.id
            refresh()
        end)
        rows[i] = row
    end

    local import = makeButton(pf, "Import", 122)
    import:SetPoint("TOPLEFT", 8, -64 - MAX_ROWS * ROW_H - 6)
    import:SetScript("OnClick", function()
        local d = getImportDialog()
        d.edit:SetText("")
        d:Show()
        d.edit:SetFocus()
    end)
    local delete = makeButton(pf, "Delete", 122)
    delete:SetPoint("LEFT", import, "RIGHT", 6, 0)
    delete:SetScript("OnClick", function()
        if selected then
            Notes:Delete(selected)
            selected = nil
            refresh()
        end
    end)
    local active = makeButton(pf, "Use this note", 122)
    active:SetPoint("TOPLEFT", import, "BOTTOMLEFT", 0, -4)
    active:SetScript("OnClick", function()
        if selected then
            Notes:SetActive(selected)
        end
    end)
    local share = makeButton(pf, "Share to raid", 122)
    share:SetPoint("LEFT", active, "RIGHT", 6, 0)
    share:SetScript("OnClick", function()
        if selected then
            CRT.NoteComm:Share(selected)
            refresh()
        end
    end)
    local roster = makeButton(pf, "Open roster in Raid Groups", 250)
    roster:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 0, -4)
    roster:SetScript("OnClick", function()
        local record = selected and Notes:Get(selected)
        if record and record.presetId and CRT.Groups:Find(record.presetId) then
            CRT.Groups:Select(record.presetId)
            UI:Show("groups")
        else
            CRT:Print("This note has no invite list, so there is no roster for it.")
        end
    end)

    -- Right: the note text, editable.
    local textLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    textLabel:SetPoint("TOPLEFT", 272, -42)
    textLabel:SetText("Note text")
    local box = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 272, -64)
    box:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, -64)
    box:SetHeight(MAX_ROWS * ROW_H + 60)
    skin(box, 0.4)
    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsNoteTextScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    editor = CreateFrame("EditBox", nil, scroll)
    editor:SetMultiLine(true)
    editor:SetAutoFocus(false)
    editor:SetFontObject(ChatFontNormal)
    editor:SetWidth(360)
    editor:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scroll:SetScrollChild(editor)
    clickToType(box, scroll, editor)

    local save = makeButton(pf, "Save text changes", 170)
    save:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -6)
    save:SetScript("OnClick", function()
        if selected then
            editor:ClearFocus()
            Notes:UpdateRaw(selected, editor:GetText())
            CRT:Print("Saved.")
        end
    end)

    status = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
    status:SetPoint("RIGHT", save, "LEFT", -8, 0)
    status:SetJustifyH("LEFT")

    -- Bottom left: your personal note, shown in its own window.
    local top = -412
    local personalLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    personalLabel:SetPoint("TOPLEFT", 8, top)
    personalLabel:SetText("Personal note (only you see it)")
    local pbox = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    pbox:SetPoint("TOPLEFT", 8, top - 22)
    pbox:SetSize(330, 168)
    skin(pbox, 0.4)
    local pscroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsPersonalNoteScroll", pbox, "UIPanelScrollFrameTemplate")
    pscroll:SetPoint("TOPLEFT", 6, -6)
    pscroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local personal = CreateFrame("EditBox", nil, pscroll)
    personal:SetMultiLine(true)
    personal:SetAutoFocus(false)
    personal:SetFontObject(ChatFontNormal)
    personal:SetWidth(290)
    personal:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    pscroll:SetScrollChild(personal)
    clickToType(pbox, pscroll, personal)
    personal.refresh = function()
        if not personal:HasFocus() then
            personal:SetText(Notes:Personal())
        end
    end
    controls[#controls + 1] = personal

    local psave = makeButton(pf, "Save personal note", 170)
    psave:SetPoint("TOPLEFT", pbox, "BOTTOMLEFT", 0, -6)
    psave:SetScript("OnClick", function()
        personal:ClearFocus()
        Notes:SetPersonal(personal:GetText())
        CRT:Print("Personal note saved.")
    end)
    -- Bottom right: try the note in use.
    local runLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    runLabel:SetPoint("TOPLEFT", 360, top)
    runLabel:SetText("Try it")
    local runHint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    runHint:SetPoint("TOPLEFT", 360, top - 22)
    runHint:SetWidth(310)
    runHint:SetJustifyH("LEFT")
    runHint:SetText("Test run starts the selected note now, as if the boss was pulled. Later phases start with Next phase.")

    local testRun = makeButton(pf, "Test run", 100)
    testRun:SetPoint("TOPLEFT", 360, top - 66)
    testRun:SetScript("OnClick", function()
        local id = selected or Notes:Active()
        if id then
            Notes:SetActive(id)
            Engine:Start(Notes:Parsed(id), "test")
        end
    end)
    local nextPhase = makeButton(pf, "Next phase", 100)
    nextPhase:SetPoint("LEFT", testRun, "RIGHT", 6, 0)
    nextPhase:SetScript("OnClick", function()
        local ph = Engine:NextPhase()
        CRT:Print(ph and ("Phase " .. ph .. " started.") or "No phase left to start, or nothing is running.")
    end)
    local stop = makeButton(pf, "Stop", 70)
    stop:SetPoint("LEFT", nextPhase, "RIGHT", 6, 0)
    stop:SetScript("OnClick", function()
        Engine:Stop()
    end)

    pf:SetScript("OnShow", refresh)
    Notes:OnChange(refresh)
end

-- Tabs ---------------------------------------------------------------------------------------

local TABS = {
    { key = "notes", label = "Notes" },
    { key = "settings", label = "Settings" },
}
local tabButtons, tabFrames, built = {}, {}, {}
local currentTab = "notes"

local function selectTab(key)
    if not tabFrames[key] then
        key = "notes"
    end
    currentTab = key
    if not built[key] then
        built[key] = true
        if key == "notes" then
            buildNotes(tabFrames[key])
        else
            CRT.NoteSettings.Build(tabFrames[key])
        end
    end
    for _, tab in ipairs(TABS) do
        local on = tab.key == key
        tabFrames[tab.key]:SetShown(on)
        tabButtons[tab.key].sel:SetShown(on)
        tabButtons[tab.key].text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
    end
end

local function build(pf)
    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Raid Notes")

    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, pf, "BackdropTemplate")
        b:SetSize(160, 26)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 164, -36)
        skin(b, 0.4)
        b.sel = b:CreateTexture(nil, "ARTWORK")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        b.text = b:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(tab.label)
        b:SetScript("OnClick", function()
            selectTab(tab.key)
        end)
        tabButtons[tab.key] = b

        local f = CreateFrame("Frame", nil, pf)
        f:SetPoint("TOPLEFT", 0, -66)
        f:SetPoint("BOTTOMRIGHT", 0, 0)
        f:Hide()
        tabFrames[tab.key] = f
    end

    local line = pf:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(GRAY[1], GRAY[2], GRAY[3], 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -62)
    line:SetPoint("TOPRIGHT", -8, -62)

    pf:SetScript("OnShow", function()
        selectTab(currentTab)
    end)
end

UI:RegisterPage("notes", "Raid Notes", build)

-- Opens the Raid Notes page on a tab: "notes" or "settings".
CRT.NotesPage = {
    Open = function(tab)
        currentTab = tab
        UI:Show("notes")
        if tabFrames[tab] then
            selectTab(tab)
        end
    end,
}
