local ADDON, CRT = ...

local Groups = CRT.Groups
local UI = CRT.UI

local NUM_SLOTS = Groups.NUM_SLOTS
-- The grid: the 8 groups as GRID_COLS across and 8 / GRID_COLS down, beside a right column RIGHT_W wide.
-- Slots are as wide as the page leaves them (UI.PAGE_W), about 148 at 866.
local GRID_COLS = 4
local COL_GAP = 10
local RIGHT_W = 220
local SLOT_W = math.floor((UI.PAGE_W - 8 - RIGHT_W - 16 - (GRID_COLS - 1) * COL_GAP) / GRID_COLS)
local SLOT_H = 22 -- the slot height in UI.SlotGrid, for the drag ghost
local GRID_TOP = -52
local PICK_ROWS = 10
local ROW_H = 22
local LIST_ROW_H = 26 -- a Quick Load box (24) and the gap under it

local GRAY = { 0.35, 0.35, 0.35 }
local GREEN = { 0.3, 1, 0.3 }
local GOLD = { 1, 0.82, 0 }
local ABSENT_BORDER = { 0.65, 0.25, 0.35 }
local ABSENT_TEXT = { 0.5, 0.5, 0.5 }

local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local function gdb()
    return CRT.db.groups
end

local function skin(frame, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, alpha or 0.5)
    frame:SetBackdropBorderColor(GRAY[1], GRAY[2], GRAY[3], 1)
end

local function styleButton(b)
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    return b
end

local function setBorder(frame, color)
    frame:SetBackdropBorderColor(color[1], color[2], color[3], 1)
end

-- Page state, filled in when the page is built.
local slotButtons = {}
local presetButtons = {}
local radios = {}
local page, listChild, emptyText, editingText, keepCheck
local extraButtons, extraChild, extraTitle, extraEmpty = {}, nil, nil, nil
local editingLabel, nameEdit, dirtyText
local picker, catcher, pickerRows = nil, nil, {}
local refresh

-- Text / name dialog ------------------------------------------------------

local dialog

local function getDialog()
    if dialog then
        return dialog
    end
    local d = CreateFrame("Frame", "CowfeeRaidToolsDialog", UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(d)
    UI:RegisterLayer("popups", d)
    d:SetPoint("CENTER")
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CowfeeRaidToolsDialog")
    d:Hide()

    d.edit = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
    d.edit:SetAutoFocus(false)
    d.edit:SetFontObject(CRTFontHighlight)
    d.edit:SetHeight(24)
    d.edit:SetMaxLetters(40)
    d.edit:SetPoint("TOPLEFT", d, "TOPLEFT", 24, -52)
    d.edit:SetPoint("TOPRIGHT", d, "TOPRIGHT", -20, -52)
    d.edit:SetScript("OnEnterPressed", function()
        d.ok:Click()
    end)
    d.edit:SetScript("OnEscapePressed", function()
        d:Hide()
    end)

    d.scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsDialogScroll", d, "UIPanelScrollFrameTemplate")
    d.scroll:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -34)
    d.scroll:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -34, 44)
    d.multi = CreateFrame("EditBox", nil, d.scroll)
    d.multi:SetMultiLine(true)
    d.multi:SetAutoFocus(false)
    d.multi:SetFontObject(CRTFontEdit)
    d.multi:SetWidth(420)
    d.multi:SetScript("OnEscapePressed", function()
        d:Hide()
    end)
    d.scroll:SetScrollChild(d.multi)

    -- Message for confirm mode.
    d.msg = d:CreateFontString(nil, "OVERLAY", "CRTFontHighlight")
    d.msg:SetPoint("TOPLEFT", d, "TOPLEFT", 22, -42)
    d.msg:SetPoint("TOPRIGHT", d, "TOPRIGHT", -22, -42)
    d.msg:SetJustifyH("LEFT")
    d.msg:SetJustifyV("TOP")
    d.msg:Hide()

    d.ok = styleButton(CreateFrame("Button", nil, d, "UIPanelButtonTemplate"))
    d.ok:SetSize(110, 26)
    d.ok:SetScript("OnClick", function()
        local value
        if d.mode == "name" then
            value = d.edit:GetText()
        elseif d.mode ~= "confirm" then
            value = d.multi:GetText()
        end
        if d.onAccept and d.onAccept(value) == false then
            return
        end
        d:Hide()
    end)

    d.cancel = styleButton(CreateFrame("Button", nil, d, "UIPanelButtonTemplate"))
    d.cancel:SetSize(110, 26)
    d.cancel:SetText(CANCEL)
    d.cancel:SetPoint("BOTTOM", d, "BOTTOM", 60, 12)
    d.cancel:SetScript("OnClick", function()
        d:Hide()
    end)

    dialog = d
    return d
end

-- mode "name" shows one line, "confirm" shows a message with OK and Cancel, anything else
-- shows a large multi-line box. For "confirm", text is the message.
-- onAccept(text) may return false to keep the dialog open. No onAccept means a read-only close button.
local function openDialog(mode, title, text, okLabel, onAccept)
    local d = getDialog()
    d.mode = mode
    d.onAccept = onAccept
    UI.SetFrameTitle(d, title)
    d.ok:SetText(okLabel)
    d.cancel:SetShown(onAccept ~= nil)
    d.ok:ClearAllPoints()
    d.ok:SetPoint("BOTTOM", d, "BOTTOM", onAccept and -60 or 0, 12)
    d.msg:Hide()

    if mode == "confirm" then
        d:SetSize(440, 170)
        d.scroll:Hide()
        d.edit:Hide()
        d.msg:SetText(text or "")
        d.msg:Show()
        d:Show()
    elseif mode == "name" then
        d:SetSize(360, 130)
        d.scroll:Hide()
        d.edit:Show()
        d.edit:SetText(text or "")
        d:Show()
        d.edit:SetFocus()
        d.edit:HighlightText()
    else
        d:SetSize(480, 320)
        d.edit:Hide()
        d.scroll:Show()
        d.multi:SetText(text or "")
        d:Show()
        d.multi:SetFocus()
        if text and text ~= "" then
            d.multi:HighlightText()
        end
    end
end

-- Name picker ---------------------------------------------------------------

local function candidates(text)
    local list
    if gdb().source == "guild" then
        list = Groups:ReadGuild()
    else
        list = Groups:ReadRoster()
    end
    text = text:lower()
    local out = {}
    for _, entry in ipairs(list) do
        local display = Groups.Display(entry.key)
        if text == "" or display:lower():find(text, 1, true) then
            out[#out + 1] = { key = entry.key, disp = display }
        end
    end
    table.sort(out, function(a, b)
        return a.disp:lower() < b.disp:lower()
    end)
    return out
end

local function pickName(key)
    local index = picker.slotIndex
    picker:Hide()
    if index then
        Groups:SetSlot(index, key)
    end
end

local function refreshPicker()
    if not picker or not picker:IsShown() then
        return
    end
    local list = candidates(strtrim(picker.edit:GetText() or ""))
    picker.matches = list
    for i = 1, PICK_ROWS do
        local row, entry = pickerRows[i], list[i]
        if entry then
            row.key = entry.key
            row.text:SetText(entry.disp)
            row.text:SetTextColor(Groups.ClassColor(entry.key))
            row:Show()
        else
            row:Hide()
        end
    end
    if #list == 0 then
        picker.hint:SetText("No matches. Press Enter to use the typed name.")
    elseif #list > PICK_ROWS then
        picker.hint:SetText(format("Showing %d of %d. Keep typing to narrow.", PICK_ROWS, #list))
    else
        picker.hint:SetText("")
    end
end

local function getPicker()
    if picker then
        return picker
    end

    -- Full-screen click catcher so clicking anywhere else closes the picker.
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetFrameLevel(100)
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()

    picker = CreateFrame("Frame", "CowfeeRaidToolsPicker", UIParent, "BackdropTemplate")
    picker:SetSize(230, 36 + PICK_ROWS * ROW_H + 24)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(110)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    skin(picker, 0.95)
    picker:Hide()

    catcher:SetScript("OnClick", function()
        picker:Hide()
    end)
    picker:SetScript("OnShow", function()
        catcher:Show()
    end)
    picker:SetScript("OnHide", function()
        catcher:Hide()
    end)

    picker.edit = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    picker.edit:SetAutoFocus(false)
    picker.edit:SetFontObject(CRTFontHighlight)
    picker.edit:SetHeight(22)
    picker.edit:SetMaxLetters(48)
    picker.edit:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -6)
    picker.edit:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -8, -6)
    picker.edit:SetScript("OnTextChanged", refreshPicker)
    picker.edit:SetScript("OnEscapePressed", function()
        picker:Hide()
    end)
    picker.edit:SetScript("OnEnterPressed", function(self)
        local text = strtrim(self:GetText())
        if text == "" then
            picker:Hide()
            return
        end
        local lower = text:lower()
        local chosen
        for _, entry in ipairs(picker.matches or {}) do
            if entry.disp:lower() == lower or entry.key:lower() == lower then
                chosen = entry.key
                break
            end
        end
        local first = picker.matches and picker.matches[1]
        pickName(chosen or (first and first.key) or text)
    end)

    for i = 1, PICK_ROWS do
        local row = CreateFrame("Button", nil, picker)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", picker, "TOPLEFT", 4, -34 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -4, -34 - (i - 1) * ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.1)
        row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            pickName(self.key)
        end)
        pickerRows[i] = row
    end

    picker.hint = picker:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    picker.hint:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 8, 6)
    picker.hint:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -8, 6)
    picker.hint:SetJustifyH("LEFT")

    return picker
end

local function openPicker(slotButton)
    local p = getPicker()
    if gdb().source == "guild" and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    p.slotIndex = slotButton.index
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", slotButton, "BOTTOMLEFT", 0, -2)
    p.edit:SetText("")
    p:Show()
    refreshPicker()
    p.edit:SetFocus()
end

-- Drag and drop -------------------------------------------------------------

local drag = {}
local ghost

local function getGhost()
    if ghost then
        return ghost
    end
    ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetSize(SLOT_W, SLOT_H)
    ghost:SetFrameStrata("TOOLTIP")
    skin(ghost, 0.9)
    setBorder(ghost, GOLD)
    ghost.text = ghost:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    ghost.text:SetPoint("LEFT", 6, 0)
    ghost:Hide()
    ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        for i, b in ipairs(slotButtons) do
            local over = (i ~= drag.from) and b:IsMouseOver()
            setBorder(b, over and GREEN or b.baseBorder)
        end
    end)
    return ghost
end

-- The slot under the mouse, if any.
local function slotUnderMouse()
    for i, b in ipairs(slotButtons) do
        if b:IsMouseOver() then
            return i
        end
    end
end

local function onDragStart(self)
    local key = Groups:Working()[self.index]
    if key == "" then
        return
    end
    drag.from = self.index
    local g = getGhost()
    g.text:SetText(Groups.Display(key))
    g.text:SetTextColor(Groups.ClassColor(key))
    g:Show()
    self:SetAlpha(0.4)
end

local function onDragStop(self)
    if not drag.from then
        return
    end
    local from = drag.from
    drag.from = nil
    ghost:Hide()
    self:SetAlpha(1)
    local target
    for i, b in ipairs(slotButtons) do
        setBorder(b, b.baseBorder)
        if b:IsMouseOver() then
            target = i
        end
    end
    if target and target ~= from then
        Groups:Swap(from, target)
    end
end

-- Not in this layout -----------------------------------------------------------
-- The people in your group who aren't anywhere in the grid, such as someone on a renamed or new
-- character. Click a name to put it in the first empty slot of their current raid group (or the
-- first empty slot), or drag it onto a slot.

local function placeExtra(entry)
    local working = Groups:Working()
    local first, sub = (entry.subgroup or 1) - 1, nil
    for pos = 1, 5 do
        local i = first * 5 + pos
        if working[i] == "" then
            sub = i
            break
        end
    end
    if not sub then
        for i = 1, NUM_SLOTS do
            if working[i] == "" then
                sub = i
                break
            end
        end
    end
    if sub then
        Groups:SetSlot(sub, entry.key)
    else
        CRT:Print("Every slot is taken. Drag the name onto a slot to replace that player.")
    end
end

local function extraButton(i)
    local b = extraButtons[i]
    if b then
        return b
    end
    b = CreateFrame("Button", nil, extraChild)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", extraChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
    b:SetPoint("TOPRIGHT", extraChild, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.08)
    b.role = b:CreateTexture(nil, "OVERLAY")
    b.role:SetSize(16, 16)
    b.role:SetPoint("LEFT", 4, 0)
    b.role:SetTexture(ROLE_TEXTURE)
    b.text = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    b.text:SetPoint("LEFT", 25, 0)
    b.text:SetPoint("RIGHT", -34, 0)
    b.text:SetJustifyH("LEFT")
    b.group = b:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    b.group:SetPoint("RIGHT", -4, 0)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self)
        placeExtra(self.entry)
    end)
    b:SetScript("OnDragStart", function(self)
        drag.key = self.entry.key
        local g = getGhost()
        g.text:SetText(Groups.Display(self.entry.key))
        g.text:SetTextColor(Groups.ClassColor(self.entry.key, self.entry.class))
        g:Show()
    end)
    b:SetScript("OnDragStop", function()
        local key = drag.key
        drag.key = nil
        ghost:Hide()
        local target = slotUnderMouse()
        for _, slot in ipairs(slotButtons) do
            setBorder(slot, slot.baseBorder)
        end
        if key and target then
            Groups:SetSlot(target, key)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(Groups.Display(self.entry.key), Groups.ClassColor(self.entry.key, self.entry.class))
        GameTooltip:AddLine("In your group, in raid group " .. (self.entry.subgroup or 1) .. ", but not in this layout.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Click: put them in the first empty slot of that group. Drag: drop them on any slot.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    extraButtons[i] = b
    return b
end

local function refreshExtras(roster, working)
    local inLayout = {}
    for i = 1, NUM_SLOTS do
        if working[i] ~= "" then
            inLayout[#inLayout + 1] = { key = working[i] }
        end
    end
    local layoutLookup = Groups.MakeLookup(inLayout)
    local extras = {}
    for _, entry in ipairs(roster) do
        if not layoutLookup(entry.key) then
            extras[#extras + 1] = entry
        end
    end
    table.sort(extras, function(a, b)
        if (a.subgroup or 1) ~= (b.subgroup or 1) then
            return (a.subgroup or 1) < (b.subgroup or 1)
        end
        return a.key:lower() < b.key:lower()
    end)
    for i, entry in ipairs(extras) do
        local b = extraButton(i)
        b.entry = entry
        b.text:SetText(Groups.Display(entry.key))
        b.text:SetTextColor(Groups.ClassColor(entry.key, entry.class))
        b.group:SetText("G" .. (entry.subgroup or 1))
        local coords = entry.role and ROLE_COORDS[entry.role]
        if coords then
            b.role:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            b.role:Show()
        else
            b.role:Hide()
        end
        b:Show()
    end
    for i = #extras + 1, #extraButtons do
        extraButtons[i]:Hide()
    end
    extraChild:SetHeight(math.max(1, #extras * ROW_H))
    extraTitle:SetText(format("In group, not in layout (%d)", #extras))
    extraEmpty:SetShown(#extras == 0)
end

-- Refresh ---------------------------------------------------------------------

local function refreshPresets()
    local g = gdb()
    local presets = Groups:Presets()
    for i, preset in ipairs(presets) do
        local b = presetButtons[i]
        if not b then
            b = CreateFrame("Button", nil, listChild, "BackdropTemplate")
            b:SetHeight(LIST_ROW_H - 2)
            b:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(i - 1) * LIST_ROW_H)
            b:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -(i - 1) * LIST_ROW_H)
            skin(b, 0.45)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(1, 1, 1, 0.08)
            b.active = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
            b.active:SetPoint("RIGHT", -6, 0)
            b.active:SetText("|cff40ff40active|r")
            b.text = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
            b.text:SetPoint("LEFT", 6, 0)
            b.text:SetPoint("RIGHT", -52, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b:SetScript("OnClick", function(self)
                Groups:Select(self.presetId)
            end)
            presetButtons[i] = b
        end
        b.presetId = preset.id
        b.text:SetText(preset.name)
        b.active:SetShown(preset.id == Groups:Active())
        setBorder(b, preset.id == g.selected and GOLD or GRAY)
        b:Show()
    end
    for i = #presets + 1, #presetButtons do
        presetButtons[i]:Hide()
    end
    listChild:SetHeight(math.max(1, #presets * LIST_ROW_H))
    emptyText:SetShown(#presets == 0)
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    local g = gdb()
    local working = Groups:Working()

    local roster = Groups:ReadRoster()
    local lookup = Groups.MakeLookup(roster)

    for i = 1, NUM_SLOTS do
        local b, key = slotButtons[i], working[i]
        if key == "" then
            b.text:SetText("")
            UI.FitText(b.text)
            b.role:Hide()
            b.baseBorder = GRAY
        else
            b.text:SetText(Groups.Display(key))
            UI.FitText(b.text)
            local member = lookup(key)
            local role = (member and member.role) or Groups.CachedRole(key)
            if member then
                -- In your group: bright, class colored.
                b.text:SetTextColor(Groups.ClassColor(key, member.class))
                b.baseBorder = GRAY
            else
                -- Not in your group: grey text and a muted red border.
                b.text:SetTextColor(ABSENT_TEXT[1], ABSENT_TEXT[2], ABSENT_TEXT[3])
                b.baseBorder = ABSENT_BORDER
            end
            local coords = role and ROLE_COORDS[role]
            if coords then
                b.role:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                b.role:SetDesaturated(member == nil)
                b.role:SetAlpha(member and 1 or 0.45)
                b.role:Show()
            else
                b.role:Hide()
            end
        end
        if not b:IsMouseOver() or drag.from then
            setBorder(b, b.baseBorder)
        end
    end

    for _, rb in ipairs(radios) do
        rb:SetChecked(g.source == rb.value)
    end
    keepCheck:SetChecked(g.keepChanges)

    local preset = g.selected and Groups:Find(g.selected)
    if preset then
        editingText:Hide()
        editingLabel:Show()
        nameEdit:Show()
        -- Do not overwrite what is being typed.
        if not nameEdit:HasFocus() then
            nameEdit:SetText(preset.name)
            nameEdit:SetCursorPosition(0)
        end
        dirtyText:SetShown(Groups.dirty and true or false)
    else
        editingLabel:Hide()
        nameEdit:Hide()
        dirtyText:Hide()
        editingText:SetText("Unsaved layout")
        editingText:Show()
    end

    refreshPresets()
    refreshExtras(roster, working)
end

-- Page ------------------------------------------------------------------------

local function makeButton(parent, label, width, height)
    local b = styleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(width, height or 26)
    b:SetText(label)
    return b
end

local function buildPage(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Raid Groups")

    local namesFrom = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    namesFrom:SetPoint("TOPLEFT", 150, -12)
    namesFrom:SetText("Pick names from:")

    local function makeRadio(label, value, x)
        local rb = CreateFrame("CheckButton", nil, pf, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", pf, "TOPLEFT", x, -8)
        local fs = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        fs:SetPoint("LEFT", rb, "RIGHT", 2, 0)
        fs:SetText(label)
        rb.value = value
        rb:SetScript("OnClick", function()
            gdb().source = value
            refresh()
            refreshPicker()
        end)
        radios[#radios + 1] = rb
    end
    makeRadio("Raid", "raid", 250)
    makeRadio("Guild", "guild", 305)

    -- Shown when the grid is not a saved layout.
    editingText = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    editingText:SetPoint("TOPLEFT", 8, -30)

    -- Shown when a saved layout is loaded: an edit box that renames it.
    editingLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    editingLabel:SetPoint("TOPLEFT", 8, -31)
    editingLabel:SetText("Editing:")

    nameEdit = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    nameEdit:SetAutoFocus(false)
    nameEdit:SetFontObject(CRTFontHighlight)
    nameEdit:SetMaxLetters(40)
    nameEdit:SetSize(190, 20)
    nameEdit:SetPoint("LEFT", editingLabel, "RIGHT", 10, 0)
    nameEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    nameEdit:SetScript("OnEscapePressed", function(self)
        local preset = gdb().selected and Groups:Find(gdb().selected)
        if preset then
            self:SetText(preset.name)
        end
        self:ClearFocus()
    end)
    -- Leaving the box (Enter, Escape, or clicking elsewhere) saves the new name.
    nameEdit:SetScript("OnEditFocusLost", function(self)
        local id = gdb().selected
        if not id then
            return
        end
        local used = Groups:Rename(id, self:GetText())
        if used then
            self:SetText(used)
        end
        self:HighlightText(0, 0)
    end)

    dirtyText = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    dirtyText:SetPoint("LEFT", nameEdit, "RIGHT", 8, 0)
    dirtyText:SetText("unsaved changes")
    dirtyText:Hide()
    editingLabel:Hide()
    nameEdit:Hide()

    -- Group grid (UI.SlotGrid, shared with the Late Tracker's Tonight tab); the slot's icon is its role
    local grid = UI.SlotGrid(pf, { cols = GRID_COLS, x = 8, top = GRID_TOP, width = GRID_COLS * SLOT_W + (GRID_COLS - 1) * COL_GAP, colGap = COL_GAP, skin = skin })
    for index, b in ipairs(grid.slots) do
        b.baseBorder = GRAY
        b.role = b.icon
        b.role:SetTexture(ROLE_TEXTURE)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnEnter", function(self)
            if not drag.from then
                setBorder(self, GOLD)
            end
        end)
        b:SetScript("OnLeave", function(self)
            if not drag.from then
                setBorder(self, self.baseBorder)
            end
        end)
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                Groups:SetSlot(self.index, "")
            else
                openPicker(self)
            end
        end)
        b:SetScript("OnDragStart", onDragStart)
        b:SetScript("OnDragStop", onDragStop)
        slotButtons[index] = b
    end

    local editHelp = UI.Help(pf, "Editing the groups", "Click a slot to choose a name, drag to move or swap, right-click to clear.")

    -- Bottom left buttons
    local setRoster = makeButton(pf, "Set current roster", SLOT_W)
    setRoster:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 8, 48)
    setRoster:SetScript("OnClick", function()
        local roster = Groups:ReadRoster()
        if #roster == 0 then
            CRT:Print("You are not in a group.")
            return
        end
        local slots, used = {}, {}
        for i = 1, NUM_SLOTS do
            slots[i] = ""
        end
        for _, entry in ipairs(roster) do
            local g = entry.subgroup
            used[g] = (used[g] or 0) + 1
            if used[g] <= 5 then
                slots[(g - 1) * 5 + used[g]] = entry.key
            end
        end

        -- An empty grid has nothing to lose, so only ask when names would be replaced.
        local hasNames = false
        for _, key in ipairs(Groups:Working()) do
            if key ~= "" then
                hasNames = true
                break
            end
        end
        if not hasNames then
            Groups:ReplaceWorking(slots)
            return
        end

        local g = gdb()
        local preset = g.selected and Groups:Find(g.selected)
        local message = "This replaces everything in the grid with your current group."
        if preset and g.keepChanges then
            message = message .. format('\n\nKeep changes is on, so the saved layout "|cffffd100%s|r" will be overwritten too.', preset.name)
        elseif preset then
            message = message .. format('\n\nThe saved layout "|cffffd100%s|r" is not changed until you save it.', preset.name)
        end
        openDialog("confirm", "Replace the grid?", message, "Replace", function()
            Groups:ReplaceWorking(slots)
        end)
    end)

    local clear = makeButton(pf, "Clear grid", SLOT_W)
    clear:SetPoint("LEFT", setRoster, "RIGHT", COL_GAP, 0)
    clear:SetScript("OnClick", function()
        Groups:ReplaceWorking({})
    end)

    editHelp:SetPoint("LEFT", clear, "RIGHT", 6, 0)

    -- Use This Group: the open layout becomes the raid's active roster (tagged active in Quick Load),
    -- which the Late Tracker expects.
    local useGroup = makeButton(pf, "Use This Group", 2 * SLOT_W + COL_GAP, 32)
    useGroup:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 8, 84)
    useGroup:SetScript("OnClick", function()
        local preset = gdb().selected and Groups:Find(gdb().selected)
        if preset then
            Groups:SetActive(preset.id)
            CRT:Print(preset.name .. " is now the active group. The Late Tracker expects it.")
        else
            CRT:Print("Pick a saved layout in Quick Load first.")
        end
    end)
    UI.Help(pf, "Use This Group", "Makes the layout you have open the raid's active roster, marked active in Quick Load. The Late Tracker expects the people in it, in their groups. During a raid night, using another layout, or changing this one, updates tonight's list straight away; everyone's clock keeps running."):SetPoint("LEFT", useGroup, "RIGHT", 6, 0)

    local apply = makeButton(pf, "Arrange Groups", 2 * SLOT_W + COL_GAP, 32)
    apply:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 8, 8)
    apply:SetScript("OnClick", function()
        CRT.Apply:Start(Groups:Working())
    end)

    -- Right column: Quick Load
    local quick = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    quick:SetPoint("TOPLEFT", pf, "TOPRIGHT", -8 - RIGHT_W, -12)
    quick:SetText("Quick Load:")

    local listBox = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    listBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, -32)
    listBox:SetSize(RIGHT_W, 214)
    skin(listBox, 0.4)

    extraTitle = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    extraTitle:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -10)
    extraTitle:SetWidth(RIGHT_W)
    extraTitle:SetJustifyH("LEFT")
    extraTitle:SetWordWrap(false)
    local extraBox = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    extraBox:SetPoint("TOPRIGHT", listBox, "BOTTOMRIGHT", 0, -30)
    extraBox:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, 172)
    extraBox:SetWidth(RIGHT_W)
    skin(extraBox, 0.4)
    local extraScroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsGroupExtraScroll", extraBox, "UIPanelScrollFrameTemplate")
    extraScroll:SetPoint("TOPLEFT", extraBox, "TOPLEFT", 4, -4)
    extraScroll:SetPoint("BOTTOMRIGHT", extraBox, "BOTTOMRIGHT", -26, 4)
    extraChild = CreateFrame("Frame", nil, extraScroll)
    extraChild:SetSize(RIGHT_W - 36, 1)
    extraScroll:SetScrollChild(extraChild)
    extraEmpty = extraBox:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    extraEmpty:SetPoint("TOP", extraBox, "TOP", 0, -12)
    extraEmpty:SetWidth(RIGHT_W - 20)
    extraEmpty:SetText("Everyone in your group is in this layout.")

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsPresetScroll", listBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -26, 4)
    listChild = CreateFrame("Frame", nil, scroll)
    listChild:SetSize(RIGHT_W - 36, 1)
    scroll:SetScrollChild(listChild)

    emptyText = listBox:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    emptyText:SetPoint("TOP", listBox, "TOP", 0, -12)
    emptyText:SetText("No saved layouts yet.")

    local import = makeButton(pf, "Import", RIGHT_W)
    import:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, 8)
    import:SetScript("OnClick", function()
        openDialog("text", "Import: paste names (one per line) or an export", "", "Import", function(text)
            local name, slots = Groups:Import(text)
            if not name then
                CRT:Print(slots)
                return false
            end
            local id = Groups:CreatePreset(name, slots)
            Groups:Select(id)
        end)
    end)

    local export = makeButton(pf, "Export current groups", RIGHT_W)
    export:SetPoint("BOTTOM", import, "TOP", 0, 6)
    export:SetScript("OnClick", function()
        local g = gdb()
        local preset = g.selected and Groups:Find(g.selected)
        openDialog("text", "Export layout (Ctrl+C to copy)", Groups:Export(preset and preset.name or "Layout", Groups:Working()), "Close")
    end)

    local delete = makeButton(pf, "Delete layout", RIGHT_W)
    delete:SetPoint("BOTTOM", export, "TOP", 0, 6)
    local armToken = 0
    delete:SetScript("OnClick", function(self)
        local id = gdb().selected
        if not id then
            CRT:Print("Select a saved layout first.")
            return
        end
        if not self.armed then
            self.armed = true
            armToken = armToken + 1
            local token = armToken
            self:SetText("Click again to delete")
            C_Timer.After(3, function()
                if token == armToken then
                    self.armed = false
                    self:SetText("Delete layout")
                end
            end)
            return
        end
        armToken = armToken + 1
        self.armed = false
        self:SetText("Delete layout")
        Groups:Delete(id)
    end)

    local saveNew = makeButton(pf, "Save current roster as new", RIGHT_W)
    saveNew:SetPoint("BOTTOM", delete, "TOP", 0, 6)
    saveNew:SetScript("OnClick", function()
        openDialog("name", "Save layout", "", "Save", function(text)
            text = strtrim(text)
            if text == "" then
                CRT:Print("Enter a name for the layout.")
                return false
            end
            local id = Groups:CreatePreset(text, Groups:Working())
            Groups:Select(id)
        end)
    end)

    keepCheck = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    keepCheck:SetSize(26, 26)
    keepCheck:SetPoint("BOTTOMLEFT", saveNew, "TOPLEFT", -2, 4)
    local keepLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    keepLabel:SetPoint("LEFT", keepCheck, "RIGHT", 2, 0)
    keepLabel:SetText("Keep changes (auto-save edits)")
    keepCheck:SetScript("OnClick", function(self)
        local g = gdb()
        g.keepChanges = self:GetChecked() and true or false
        if g.keepChanges and g.selected and Groups.dirty then
            Groups:CommitSelected()
        end
        refresh()
    end)

    pf:SetScript("OnShow", refresh)
    pf:SetScript("OnHide", function()
        if picker then
            picker:Hide()
        end
        if dialog then
            dialog:Hide()
        end
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("GUILD_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    events:SetScript("OnEvent", function(_, event)
        if event == "GUILD_ROSTER_UPDATE" then
            refreshPicker()
        else
            refresh()
        end
    end)

    Groups:OnChange(refresh)
end

UI:RegisterPage("groups", "Raid Groups", buildPage)
