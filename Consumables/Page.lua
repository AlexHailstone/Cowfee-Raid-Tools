local ADDON, CRT = ...

-- The Consumables page: choose which buffs and bag items count as food, flask, potion,
-- weapon oil and augment rune for the ready check row. Nothing here needs a code edit.

local Consumables = CRT.Consumables
local UI = CRT.UI

local ICON = 28
local ICON_GAP = 4
local MAX_PER_ROW = 16
local BLOCK_H = 104
local BLOCK_TOP = -130
local PICK_ROW_H = 26

local GRAY = { 0.35, 0.35, 0.35 }

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

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
    b:SetSize(width, height or 26)
    b:SetText(label)
    return b
end

local page, enabledCheck, lowEdit
local blocks = {}
local refresh

-- Picker: a filterable list of your buffs or bag items. Clicking a row adds or removes it. ----

local picker, catcher
local pickRows = {}
local pickState = {}

local function renderPicker()
    if not picker or not picker:IsShown() then
        return
    end
    local filter = strtrim(picker.edit:GetText() or ""):lower()
    local shown = 0
    for _, entry in ipairs(pickState.entries) do
        if filter == "" or entry.name:lower():find(filter, 1, true) then
            shown = shown + 1
            local row = pickRows[shown]
            if not row then
                row = CreateFrame("Button", nil, picker.child)
                row:SetHeight(PICK_ROW_H)
                row:SetPoint("TOPLEFT", picker.child, "TOPLEFT", 0, -(shown - 1) * PICK_ROW_H)
                row:SetPoint("TOPRIGHT", picker.child, "TOPRIGHT", 0, -(shown - 1) * PICK_ROW_H)
                row.hl = row:CreateTexture(nil, "HIGHLIGHT")
                row.hl:SetAllPoints()
                row.hl:SetColorTexture(1, 1, 1, 0.1)
                row.mark = row:CreateTexture(nil, "BACKGROUND")
                row.mark:SetAllPoints()
                row.mark:SetColorTexture(0.2, 0.8, 0.3, 0.22)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(22, 22)
                row.icon:SetPoint("LEFT", 4, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", -70, 0)
                row.text:SetJustifyH("LEFT")
                row.side = row:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
                row.side:SetPoint("RIGHT", -6, 0)
                row:SetScript("OnClick", function(self)
                    pickState.onPick(self.entry)
                    renderPicker()
                end)
                pickRows[shown] = row
            end
            row.entry = entry
            row.icon:SetTexture(entry.icon or Consumables.QUESTION_MARK)
            row.text:SetText(entry.name)
            row.side:SetText(entry.side or "")
            row.mark:SetShown(pickState.isAssigned(entry.id))
            row:Show()
        end
    end
    for i = shown + 1, #pickRows do
        pickRows[i]:Hide()
    end
    picker.child:SetHeight(math.max(1, shown * PICK_ROW_H))
    picker.empty:SetShown(shown == 0)
end

local function getPicker()
    if picker then
        return picker
    end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetFrameLevel(100)
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()

    picker = CreateFrame("Frame", "CowfeeRaidToolsConsumablePicker", UIParent, "BackdropTemplate")
    picker:SetSize(420, 460)
    picker:SetPoint("CENTER")
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(110)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    skin(picker, 0.96)
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

    picker.title = picker:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    picker.title:SetPoint("TOPLEFT", 12, -10)

    picker.hint = picker:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    picker.hint:SetPoint("TOPLEFT", 12, -32)
    picker.hint:SetText("Click a row to add or remove it. Green rows are already assigned.")

    picker.edit = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    picker.edit:SetAutoFocus(false)
    picker.edit:SetFontObject(CRTFontHighlight)
    picker.edit:SetHeight(22)
    picker.edit:SetPoint("TOPLEFT", 18, -54)
    picker.edit:SetPoint("TOPRIGHT", -14, -54)
    picker.edit:SetScript("OnTextChanged", renderPicker)
    picker.edit:SetScript("OnEscapePressed", function()
        picker:Hide()
    end)

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsConsumableScroll", picker, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -84)
    scroll:SetPoint("BOTTOMRIGHT", -30, 44)
    picker.child = CreateFrame("Frame", nil, scroll)
    picker.child:SetSize(370, 1)
    scroll:SetScrollChild(picker.child)

    picker.empty = picker:CreateFontString(nil, "OVERLAY", "CRTFontDisable")
    picker.empty:SetPoint("TOP", scroll, "TOP", 0, -20)
    picker.empty:Hide()

    local done = makeButton(picker, "Done", 110)
    done:SetPoint("BOTTOM", 0, 10)
    done:SetScript("OnClick", function()
        picker:Hide()
    end)
    return picker
end

-- entries: { id, name, icon, side }. onPick(entry) toggles it. isAssigned(id) marks rows.
local function openPicker(title, emptyText, entries, onPick, isAssigned)
    local p = getPicker()
    pickState = { entries = entries, onPick = onPick, isAssigned = isAssigned }
    p.title:SetText(title)
    p.empty:SetText(emptyText)
    p.edit:SetText("")
    p:Show()
    renderPicker()
    p.edit:SetFocus()
end

-- Assigned entries ---------------------------------------------------------------

local function isAssigned(key, which, id)
    for _, entry in ipairs(Consumables:List(key, which)) do
        if entry.id == id then
            return true
        end
    end
    return false
end

local function entryButton(parent, index)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(ICON, ICON)
    skin(b, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.name or "", 1, 1, 1)
        GameTooltip:AddLine(self.detail or "", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Click to remove", 0.9, 0.3, 0.3)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        if self.remove then
            self.remove()
        end
    end)
    return b
end

local function fillRow(row, entries, detailPrefix, removeFn)
    for i = 1, math.min(#entries, MAX_PER_ROW) do
        local b = row.buttons[i]
        if not b then
            b = entryButton(row.frame, i)
            b:SetPoint("LEFT", row.frame, "LEFT", (i - 1) * (ICON + ICON_GAP), 0)
            row.buttons[i] = b
        end
        local entry = entries[i]
        b.icon:SetTexture(entry.icon or Consumables.QUESTION_MARK)
        b.name = entry.name
        b.detail = detailPrefix .. " " .. entry.id
        b.remove = function()
            removeFn(entry.id)
        end
        b:Show()
    end
    for i = #entries + 1, #row.buttons do
        row.buttons[i]:Hide()
    end
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    enabledCheck:SetChecked(Consumables:Enabled())
    if not lowEdit:HasFocus() then
        lowEdit:SetText(tostring(Consumables:LowMinutes()))
    end
    for _, def in ipairs(Consumables.CATEGORIES) do
        local block = blocks[def.key]
        if block.buffRow then
            fillRow(block.buffRow, Consumables:List(def.key, "buffs"), "Buff spell ID", function(id)
                Consumables:RemoveBuff(def.key, id)
            end)
        end
        fillRow(block.itemRow, Consumables:List(def.key, "items"), "Item ID", function(id)
            Consumables:RemoveItem(def.key, id)
        end)
    end
end

local function newRow(parent, x, y)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(MAX_PER_ROW * (ICON + ICON_GAP), ICON)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return { frame = frame, buttons = {} }
end

local function buildBlock(pf, index, def)
    local top = BLOCK_TOP - (index - 1) * BLOCK_H
    local block = {}
    blocks[def.key] = block

    local label = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    label:SetPoint("TOPLEFT", 8, top)
    label:SetText(index .. ". " .. def.label)

    local rowX = 78
    if def.kind == "buff" then
        local addBuff = makeButton(pf, "Add from my buffs", 170)
        addBuff:SetPoint("TOPLEFT", 230, top + 4)
        addBuff:SetScript("OnClick", function()
            local entries = {}
            for _, aura in ipairs(Consumables:ScanBuffs()) do
                entries[#entries + 1] = { id = aura.id, name = aura.name, icon = aura.icon, side = "ID " .. aura.id }
            end
            openPicker(def.label .. ": your current buffs", "No readable buffs on you right now. Eat, drink or use the consumable first.", entries, function(entry)
                if isAssigned(def.key, "buffs", entry.id) then
                    Consumables:RemoveBuff(def.key, entry.id)
                else
                    Consumables:AddBuff(def.key, entry.id, entry.name, entry.icon)
                end
            end, function(id)
                return isAssigned(def.key, "buffs", id)
            end)
        end)

        local buffLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
        buffLabel:SetPoint("TOPLEFT", 8, top - 40)
        buffLabel:SetText("Buffs")
        block.buffRow = newRow(pf, rowX, top - 32)
    elseif def.kind == "count" then
        local note = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
        note:SetPoint("TOPLEFT", 8, top - 40)
        note:SetText("Shows how many are in your bags.")
    else
        local note = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
        note:SetPoint("TOPLEFT", 8, top - 40)
        note:SetText("Any temporary weapon enchant counts. Items set the icon and bag count.")
    end

    local addItem = makeButton(pf, "Add from my bags", 170)
    addItem:SetPoint("TOPLEFT", def.kind == "buff" and 410 or 230, top + 4)
    addItem:SetScript("OnClick", function()
        local entries = {}
        for _, item in ipairs(Consumables:ScanBags()) do
            entries[#entries + 1] = { id = item.id, name = item.name, icon = item.icon, side = "x" .. item.count }
        end
        openPicker(def.label .. ": items in your bags", "Nothing in your bags.", entries, function(entry)
            if isAssigned(def.key, "items", entry.id) then
                Consumables:RemoveItem(def.key, entry.id)
            else
                Consumables:AddItem(def.key, entry.id, entry.name, entry.icon)
            end
        end, function(id)
            return isAssigned(def.key, "items", id)
        end)
    end)

    local itemLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    itemLabel:SetPoint("TOPLEFT", 8, top - 72)
    itemLabel:SetText("Items")
    block.itemRow = newRow(pf, rowX, top - 64)
end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Consumables")

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -34)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")
    hint:SetText("Choose what counts for each icon on the ready check row. Buff up first, then use Add from my buffs, so you never have to look up an ID. Items come from your bags. On the row, click a food, flask or weapon icon to use the first assigned item in your bags (shift-click applies a weapon oil to the off hand).")

    enabledCheck = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    enabledCheck:SetSize(26, 26)
    enabledCheck:SetPoint("TOPLEFT", 4, -88)
    local enabledLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    enabledLabel:SetPoint("LEFT", enabledCheck, "RIGHT", 2, 0)
    enabledLabel:SetText("Show on ready check")
    enabledCheck:SetScript("OnClick", function(self)
        Consumables:SetEnabled(self:GetChecked())
    end)

    local lowLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    lowLabel:SetPoint("LEFT", enabledLabel, "RIGHT", 28, 0)
    lowLabel:SetText("Warn when under")

    lowEdit = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    lowEdit:SetAutoFocus(false)
    lowEdit:SetFontObject(CRTFontHighlight)
    lowEdit:SetNumeric(true)
    lowEdit:SetMaxLetters(3)
    lowEdit:SetSize(44, 22)
    lowEdit:SetPoint("LEFT", lowLabel, "RIGHT", 12, 0)
    lowEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    lowEdit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(Consumables:LowMinutes()))
        self:ClearFocus()
    end)
    lowEdit:SetScript("OnEditFocusLost", function(self)
        Consumables:SetLowMinutes(self:GetText())
        self:SetText(tostring(Consumables:LowMinutes()))
    end)

    local minutes = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    minutes:SetPoint("LEFT", lowEdit, "RIGHT", 6, 0)
    minutes:SetText("minutes left")

    local preview = makeButton(pf, "Preview row", 130)
    preview:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, -86)
    preview:SetScript("OnClick", function()
        CRT.ConsumablesDisplay:Preview()
    end)

    for index, def in ipairs(Consumables.CATEGORIES) do
        buildBlock(pf, index, def)
    end

    pf:SetScript("OnShow", refresh)
    pf:SetScript("OnHide", function()
        if picker then
            picker:Hide()
        end
    end)
    Consumables:OnChange(refresh)
end

UI:RegisterPage("consumables", "Consumables", build)
