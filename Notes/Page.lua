local ADDON, CRT = ...

-- The Raid Notes page: the list of notes (one per boss), the text of the selected one, importing,
-- sharing with the group, the roster link to Raid Groups, a test run, and the note window and alert
-- settings. The note window and your alert are moved with "Toggle previews".

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

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 24)
    b:SetText(label)
    return b
end

local function makeCheck(parent, x, y, label, getter, setter)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    check.refresh = function()
        check:SetChecked(getter() and true or false)
    end
    controls[#controls + 1] = check
    return check
end

local function makeNumber(parent, x, y, label, getter, setter, low, high)
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("TOPLEFT", x + 4, y - 4)
    text:SetText(label)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontHighlight)
    edit:SetNumeric(true)
    edit:SetMaxLetters(4)
    edit:SetSize(48, 20)
    edit:SetPoint("TOPLEFT", x + 200, y - 2)
    local function apply(self)
        local value = tonumber(self:GetText())
        if value then
            setter(math.max(low, math.min(high, math.floor(value))))
        end
        self:SetText(tostring(getter()))
    end
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(getter()))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", apply)
    edit.refresh = function()
        if not edit:HasFocus() then
            edit:SetText(tostring(getter()))
        end
    end
    controls[#controls + 1] = edit
    return edit
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

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Raid Notes")

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -32)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")
    hint:SetText("Import a note, share it with the raid before the pull, and its timers count down from the start of the fight. Use Toggle previews (top right) to place the note window and your alert.")

    -- Left: the notes.
    local listLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    listLabel:SetPoint("TOPLEFT", 8, -70)
    listLabel:SetText("Notes")
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, pf, "BackdropTemplate")
        row:SetSize(250, ROW_H - 2)
        row:SetPoint("TOPLEFT", 8, -92 - (i - 1) * ROW_H)
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
    import:SetPoint("TOPLEFT", 8, -92 - MAX_ROWS * ROW_H - 6)
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
    textLabel:SetPoint("TOPLEFT", 272, -70)
    textLabel:SetText("Note text")
    local box = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 272, -92)
    box:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, -92)
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

    -- Settings: the note window (left) and your alert (right).
    local top = -440
    local windowLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    windowLabel:SetPoint("TOPLEFT", 8, top)
    windowLabel:SetText("Note window")
    local function win(key)
        return function()
            return Notes:Window()[key]
        end, function(value)
            Notes:Set("window", key, value)
        end
    end
    makeCheck(pf, 4, top - 20, "Show the note window", win("shown"))
    makeCheck(pf, 4, top - 44, "Hide lines once their time has passed", win("hidePassed"))
    makeNumber(pf, 4, top - 70, "Font size (8 to 32)", win("fontSize"), 8, 32)
    makeNumber(pf, 4, top - 94, "Window alpha % (10 to 100)", win("alpha"), 10, 100)
    makeNumber(pf, 4, top - 118, "Background alpha % (0 to 100)", win("bgAlpha"), 0, 100)
    makeNumber(pf, 4, top - 142, "Width (200 to 900)", win("width"), 200, 900)
    makeNumber(pf, 4, top - 166, "Height (100 to 800)", win("height"), 100, 800)
    local font = makeButton(pf, "Font: ", 250)
    font:SetPoint("TOPLEFT", 8, top - 194)
    font:SetScript("OnClick", function()
        local current = Notes:Window().font
        local fonts = CRT.NoteWindow.FONTS
        local nextIndex = 1
        for i, f in ipairs(fonts) do
            if f.name == current then
                nextIndex = i % #fonts + 1
            end
        end
        Notes:Set("window", "font", fonts[nextIndex].name)
    end)
    font.refresh = function()
        font:SetText("Font: " .. (Notes:Window().font or "Friz Quadrata"))
    end
    controls[#controls + 1] = font

    local alertLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    alertLabel:SetPoint("TOPLEFT", 360, top)
    alertLabel:SetText("Your alert")
    local function alert(key)
        return function()
            return Notes:Alert()[key]
        end, function(value)
            Notes:Set("alert", key, value)
        end
    end
    makeCheck(pf, 356, top - 20, "Show your next spell or callout", alert("enabled"))
    makeNumber(pf, 356, top - 46, "Show it this many seconds early", alert("seconds"), 1, 60)
    makeCheck(pf, 356, top - 70, "Read it out (text to speech)", alert("tts"))
    makeNumber(pf, 356, top - 96, "Read it out at seconds left", alert("ttsSeconds"), 0, 30)
    makeNumber(pf, 356, top - 120, "Speech volume (0 to 100)", alert("ttsVolume"), 0, 100)
    makeCheck(pf, 356, top - 144, "Only accept notes from leader or assistants", function()
        return Notes:TrustedOnly()
    end, function(value)
        Notes:Set(nil, "trustedOnly", value)
    end)

    local speak = makeButton(pf, "Test speech", 100)
    speak:SetPoint("TOPLEFT", 360, top - 172)
    speak:SetScript("OnClick", function()
        CRT.NoteAlert:Speak("Cowfee Raid Tools. Avenging Wrath in three.")
    end)
    local testRun = makeButton(pf, "Test run", 100)
    testRun:SetPoint("LEFT", speak, "RIGHT", 6, 0)
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

UI:RegisterPage("notes", "Raid Notes", build)
