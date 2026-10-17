local ADDON, CRT = ...

-- The Raid Notes page, with five tabs:
--   Notes      the list of notes (one per boss), the text of the selected one, importing, sharing with
--              the group, the roster link to Raid Groups, your personal note, and a test run
--   Reminders  a boss's Journal abilities and your own reminders (Notes/Reminders.lua)
--   Phases     what starts each phase of a boss (Notes/Phases.lua)
--   Alerts     where your note lines show and how each kind of alert looks (Notes/AlertsTab.lua)
--   Settings   the three note windows, your alert's timing and voice, and sharing (Notes/Settings.lua)
-- The note windows and your alert are moved with "Previews".

local Notes = CRT.Notes
local Engine = CRT.NoteEngine
local UI = CRT.UI

local TEXT = {
    noteText = "Note text",
    saveText = "Save text changes",
    saved = "Saved.",
}

local ROW_H = 24
local MAX_ROWS = 9
-- The Notes tab in three columns across the page (UI.PAGE_W): the notes list, the note text, and your
-- personal note with Try it. The tab is UI.PAGE_H - 66 high, under the tabs.
local LIST_W = 250
local RIGHT_W = 250
local TEXT_X = 8 + LIST_W + 14
local RIGHT_X = UI.PAGE_W - 8 - RIGHT_W
local TEXT_W = RIGHT_X - 14 - TEXT_X
local TAB_H = UI.PAGE_H - 66

local GRAY = { 0.35, 0.35, 0.35 }
local GOLD = { 1, 0.82, 0 }
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local page, rows, editor, status, selected = nil, {}, nil, nil, nil
-- The active note the page last followed. When the active note changes (shared from here or the
-- Timeline, received from the raid leader, or made from the Timeline), the page selects it, so the
-- text shown is the note that runs; clicking another note still shows that one until the next change.
local followedActive
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
        -- a box that is read-only (greyed) takes no typing
        if edit.IsEnabled and not edit:IsEnabled() then
            return
        end
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
    UI:StyleWindow(d)
    d:SetSize(560, 420)
    d:SetPoint("CENTER")
    UI:RegisterLayer("popups", d)
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CowfeeRaidToolsNoteImport")
    UI.SetFrameTitle(d, "Import a raid note (paste it below)")

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsNoteImportScroll", d, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -34)
    scroll:SetPoint("BOTTOMRIGHT", -34, 46)
    d.edit = CreateFrame("EditBox", nil, scroll)
    d.edit:SetMultiLine(true)
    d.edit:SetAutoFocus(false)
    d.edit:SetFontObject(CRTFontEdit)
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
    local newActive = Notes:Active()
    -- not while you are typing in the note text: the jump waits for the next refresh after that
    if newActive ~= followedActive and not (editor and editor:HasFocus()) then
        followedActive = newActive
        if newActive then
            selected = newActive
        end
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

    -- The note's text, as saved. A box with the keyboard focus keeps it until something else takes it,
    -- so focus alone can't mean "being typed in": the box follows the saved text whenever it holds
    -- no unsaved typing (its text is still what it last loaded), so a line moved, copied or deleted
    -- on the Timeline shows here at once. Unsaved typing is never replaced.
    local raw = record and record.raw or ""
    if not editor:HasFocus() or editor:GetText() == editor.loaded then
        if editor:GetText() ~= raw then
            local cursor = editor:GetCursorPosition() or 0
            editor:SetText(raw)
            if editor:HasFocus() then
                editor:SetCursorPosition(math.min(cursor, #raw))
            end
        end
        editor.loaded = raw
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
    local Alerts = CRT.Alerts
    if Engine.running then
        lines[#lines + 1] = "Running: phase " .. tostring(Engine:CurrentPhase()) .. (Engine.reason == "test" and " (test)" or "")
    elseif Alerts.running then
        -- A run with reminders but no note for this boss: the note windows stay idle.
        lines[#lines + 1] = "Running reminders, no note: phase " .. tostring(Engine:CurrentPhase())
            .. (Alerts.run and Alerts.run.reason == "test" and " (test)" or "")
    end
    status:SetText(table.concat(lines, "\n"))

    for _, control in ipairs(controls) do
        control.refresh()
    end
end

local function buildNotes(pf)
    page = pf


    -- Left: the notes.
    local listLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    listLabel:SetPoint("TOPLEFT", 8, -14)
    listLabel:SetText("Notes")
    UI.Help(pf, "Raid notes", "Import a note, share it with the raid before the pull, and its timers count down from the start of the fight. The note's other text goes to the Assignments window.\n\nWindow, alert timing and sharing settings are on the Notes Settings tab; where your note lines show is on the Alert Settings tab, and your alerts for boss mechanics are on Mech Alerts."):SetPoint("LEFT", listLabel, "RIGHT", 6, 0)
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, pf, "BackdropTemplate")
        row:SetSize(LIST_W, ROW_H - 2)
        row:SetPoint("TOPLEFT", 8, -36 - (i - 1) * ROW_H)
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
    import:SetPoint("TOPLEFT", 8, -36 - MAX_ROWS * ROW_H - 6)
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
        -- with no note picked, Share sends the Empty note (Notes/Comm.lua)
        CRT.NoteComm:Share(selected)
        refresh()
    end)
    local roster = makeButton(pf, "Open roster in Raid Groups", LIST_W)
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

    -- Middle: the note text, editable, down to the Save button at the bottom of the tab.
    local textLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    textLabel:SetPoint("TOPLEFT", TEXT_X, -14)
    textLabel:SetText(TEXT.noteText)
    local box = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    box:SetPoint("TOPLEFT", TEXT_X, -36)
    box:SetSize(TEXT_W, TAB_H - 36 - 44)
    skin(box, 0.4)
    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsNoteTextScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    editor = CreateFrame("EditBox", nil, scroll)
    editor:SetMultiLine(true)
    editor:SetAutoFocus(false)
    editor:SetFontObject(CRTFontEdit)
    editor:SetWidth(TEXT_W - 40)
    editor:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scroll:SetScrollChild(editor)
    clickToType(box, scroll, editor)

    local save = makeButton(pf, TEXT.saveText, 170)
    save:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -6)
    save:SetScript("OnClick", function()
        if selected then
            -- asked again at the click: you may have lost the right since the page drew
            local allowed, why = Notes:CanEditRaid()
            if not allowed then
                CRT:Print(why)
                return
            end
            editor:ClearFocus()
            editor.loaded = editor:GetText()
            Notes:UpdateRaw(selected, editor:GetText())
            CRT:Print(TEXT.saved)
        end
    end)

    -- Only the raid leader or an assistant changes the raid note (P4): for anyone else the text is
    -- read-only and Save is greyed, with a (?) saying why. Set again at every redraw and show, so a
    -- promotion unlocks it. Import, Use this note and Delete stay: they choose which note you hold.
    local lockHelp = UI.Help(pf, TEXT.noteText, function()
        local _, why = Notes:CanEditRaid()
        return why or ""
    end)
    lockHelp:SetPoint("LEFT", textLabel, "RIGHT", 6, 0)
    lockHelp.refresh = function()
        local allowed = Notes:CanEditRaid()
        editor:SetEnabled(allowed and true or false)
        save:SetEnabled(allowed and true or false)
        lockHelp:SetShown(not allowed)
    end
    controls[#controls + 1] = lockHelp

    status = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
    status:SetPoint("RIGHT", save, "LEFT", -8, 0)
    status:SetJustifyH("LEFT")

    -- Right: your personal note, shown in its own window.
    local top = -14
    local personalLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    personalLabel:SetPoint("TOPLEFT", RIGHT_X, top)
    personalLabel:SetText("Personal note (only you see it)")
    local pbox = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    pbox:SetPoint("TOPLEFT", RIGHT_X, top - 22)
    pbox:SetSize(RIGHT_W, 220)
    skin(pbox, 0.4)
    local pscroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsPersonalNoteScroll", pbox, "UIPanelScrollFrameTemplate")
    pscroll:SetPoint("TOPLEFT", 6, -6)
    pscroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local personal = CreateFrame("EditBox", nil, pscroll)
    personal:SetMultiLine(true)
    personal:SetAutoFocus(false)
    personal:SetFontObject(CRTFontEdit)
    personal:SetWidth(RIGHT_W - 40)
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
    -- Right, under the personal note: try the note in use. Next phase has its own row, since its text
    -- grows with the phase it starts ("Next phase (1.5)").
    top = top - 22 - 220 - 6 - 26 - 20
    local runLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    runLabel:SetPoint("TOPLEFT", RIGHT_X, top)
    runLabel:SetText("Try it")
    UI.Help(pf, "Try it", "Test run starts the selected note now, as if the boss was pulled. Later phases start with Next phase, which shows the phase it starts next, including intermissions such as 1.5. It also works on a pull with only reminders. Stop ends it."):SetPoint("LEFT", runLabel, "RIGHT", 6, 0)

    local testRun = makeButton(pf, "Test run", 100)
    testRun:SetPoint("TOPLEFT", RIGHT_X, top - 24)
    testRun:SetScript("OnClick", function()
        local id = selected or Notes:Active()
        if id then
            Notes:SetActive(id)
            Engine:Start(Notes:Parsed(id), "test")
        end
    end)
    -- Named after the phase it starts, e.g. "Next phase (1.5)", so an intermission is not a surprise.
    local nextPhase = makeButton(pf, "Next phase", 176)
    nextPhase:SetPoint("TOPLEFT", testRun, "BOTTOMLEFT", 0, -6)
    nextPhase:SetScript("OnClick", function()
        local ph = Engine:NextPhase()
        CRT:Print(ph and ("Phase " .. ph .. " started.") or "No phase left to start, or nothing is running.")
    end)
    nextPhase.refresh = function()
        local ph = Engine:PeekNextPhase()
        nextPhase:SetText(ph and ("Next phase (" .. tostring(ph) .. ")") or "Next phase")
    end
    controls[#controls + 1] = nextPhase
    local stop = makeButton(pf, "Stop", 70)
    stop:SetPoint("LEFT", testRun, "RIGHT", 6, 0)
    stop:SetScript("OnClick", function()
        Engine:Stop()
    end)

    pf:SetScript("OnShow", refresh)
    Notes:OnChange(refresh)
    CRT.Bosses:OnRouteChange(refresh) -- the raid route, the note list's order
end

-- Tabs ---------------------------------------------------------------------------------------

-- The Phases tab (Notes/Phases.lua) was taken off the page; its triggers, shipped and saved, still
-- start the phases, and its file is kept so it can be put back or moved.
local TABS = {
    { key = "notes", label = "Notes" },
    { key = "reminders", label = "Mech Alerts" },
    { key = "alerts", label = "Alert Settings" },
    { key = "settings", label = "Notes Settings" },
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
        elseif key == "reminders" then
            CRT.NoteReminders.Build(tabFrames[key])
        elseif key == "alerts" then
            CRT.NoteAlertsTab.Build(tabFrames[key])
        else
            CRT.NoteSettings.Build(tabFrames[key])
        end
    end
    for _, tab in ipairs(TABS) do
        local on = tab.key == key
        tabFrames[tab.key]:SetShown(on)
        UI:SetTabSelected(tabButtons[tab.key], on)
    end
end

local function build(pf)
    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Raid Notes")

    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, pf, "BackdropTemplate")
        -- Four tabs across the 686 px page, Settings last.
        b:SetSize(164, 26)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 168, -36)
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
        UI:RegisterTab(b)

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

-- Opens the Raid Notes page on a tab: "notes", "reminders" (Mech Alerts), "alerts" (Alert Settings) or
-- "settings". TAB_H is a tab's height under the tabs, for the tabs that size themselves from it.
CRT.NotesPage = {
    TAB_H = TAB_H,
    Open = function(tab)
        currentTab = tab
        UI:Show("notes")
        if tabFrames[tab] then
            selectTab(tab)
        end
    end,
}
