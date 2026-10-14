local ADDON, CRT = ...

-- The Your bar tab of the Ready Check page (ReadyCheck/Page.lua builds it into its tab). The list of
-- consumables ships with the addon, and here you can:
--   * see the same bar that shows on the ready check, with live status,
--   * drag an item from your bags onto an icon to add it to that category (optional),
--   * set the icon order, and which item is used first when you click an icon.
-- The buff of a food or flask is learned the first time you use it, see Consumables/Data.lua.

local Consumables = CRT.Consumables
local Ants = CRT.Ants
local Bar = CRT.ConsumablesBar
local UI = CRT.UI

local CAT_ROW_H = 32
local ITEM_ROW_H = 36
local LEFT_W = 290
local RIGHT_X = 316
local REFRESH_SECONDS = 0.5

local GRAY = { 0.35, 0.35, 0.35 }
local GOLD = { 1, 0.82, 0 }

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

local page, enabledCheck, lowEdit, itemTitle, itemHint, itemEmpty, footer, learning, itemChild, barFrame
local selected = "food"
local catRows, itemRows, barSlots = {}, {}, {}
local refresh
local barElapsed = 0

-- Dropping an item from your bags on a category adds it to that category. ---------------------

-- Returns true if an item was being dragged, so a plain click can fall through to selecting.
local function drop(key)
    local kind = GetCursorInfo()
    if kind ~= "item" then
        return false
    end
    local _, message = Consumables:AddFromCursor(key)
    CRT:Print(message)
    selected = key
    refresh()
    return true
end

-- The bar: the same icons as the ready check row, live, and a drop target for each. -----------

local function barTooltip(self)
    local def = Consumables:Def(self.key)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(def and def.label or "", 1, 1, 1)
    GameTooltip:AddLine("Click to see its items.", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag an item from your bags here to add it.", 0.6, 0.9, 0.6)
    GameTooltip:Show()
end

local function refreshBar()
    Consumables:RefreshBags()
    for index, key in ipairs(Consumables:Order()) do
        local slot = barSlots[index]
        slot.key = key
        Bar.Apply(slot, Consumables:Status(key))
        if key == selected then
            slot:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
        end
    end
end

local function buildBar(pf)
    local label = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    label:SetPoint("TOPLEFT", 8, -44)
    label:SetText("Your bar")
    UI.Help(pf, "Your bar", "Your own bar of consumable icons that appears during a ready check. It uses a built-in list of consumables kept up to date with the addon. You can add your own, and choose the order.\n\nDrag an item from your bags onto an icon to add it. Click an icon to see its items."):SetPoint("LEFT", label, "RIGHT", 6, 0)

    local count = #Consumables.CATEGORIES
    barFrame = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    barFrame:SetSize(Bar.Size(count))
    barFrame:SetPoint("TOPLEFT", pf, "TOPLEFT", 8, -66)
    barFrame:SetBackdrop(Bar.BACKDROP)
    barFrame:SetBackdropColor(0, 0, 0, 0.45)
    barFrame:SetBackdropBorderColor(0.2, 0.8, 0.9, 1)

    for index = 1, count do
        local slot = Bar.CreateSlot(barFrame, index, false)
        slot:SetScript("OnClick", function(self)
            if not drop(self.key) then
                selected = self.key
                refresh()
            end
        end)
        slot:SetScript("OnReceiveDrag", function(self)
            drop(self.key)
        end)
        slot:SetScript("OnEnter", barTooltip)
        slot:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        barSlots[index] = slot
    end
end

-- Icon order: five rows, each with Up and Down. Clicking a row selects its category. -----------

local function buildCategoryRows(pf)
    local top = -156
    for i = 1, #Consumables.CATEGORIES do
        local row = CreateFrame("Button", nil, pf, "BackdropTemplate")
        row:SetSize(LEFT_W, CAT_ROW_H - 4)
        row:SetPoint("TOPLEFT", pf, "TOPLEFT", 8, top - (i - 1) * CAT_ROW_H)
        skin(row, 0.5)

        row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetJustifyH("LEFT")

        row.down = makeButton(row, "Down", 54, 24)
        row.down:SetPoint("RIGHT", -4, 0)
        row.down:SetScript("OnClick", function()
            Consumables:MoveCategory(row.key, 1)
        end)
        row.up = makeButton(row, "Up", 44, 24)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
        row.up:SetScript("OnClick", function()
            Consumables:MoveCategory(row.key, -1)
        end)

        row:SetScript("OnClick", function(self)
            if not drop(self.key) then
                selected = self.key
                refresh()
            end
        end)
        row:SetScript("OnReceiveDrag", function(self)
            drop(self.key)
        end)
        catRows[i] = row
    end
end

-- Items for the selected category, in a scrolling list. ---------------------------------------

local function itemRow(index)
    local row = itemRows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, itemChild, "BackdropTemplate")
    row:SetHeight(ITEM_ROW_H - 4)
    row:SetPoint("TOPLEFT", itemChild, "TOPLEFT", 0, -(index - 1) * ITEM_ROW_H)
    row:SetPoint("TOPRIGHT", itemChild, "TOPRIGHT", 0, -(index - 1) * ITEM_ROW_H)
    skin(row, 0.4)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.down = makeButton(row, "Down", 46, 22)
    row.down:SetPoint("RIGHT", -4, 0)
    row.down:SetScript("OnClick", function()
        Consumables:MoveItem(selected, row.itemId, 1)
    end)
    row.up = makeButton(row, "Up", 34, 22)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -3, 0)
    row.up:SetScript("OnClick", function()
        Consumables:MoveItem(selected, row.itemId, -1)
    end)
    row.remove = makeButton(row, "Remove", 58, 22)
    row.remove:SetPoint("RIGHT", row.up, "LEFT", -3, 0)
    row.remove:SetScript("OnClick", function()
        Consumables:RemoveExtra(selected, row.itemId)
    end)

    -- The name on the top line, and how many are in your bags under it, so a long name has room.
    row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.side = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.side:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)

    itemRows[index] = row
    return row
end

local function refreshItems()
    local entries = Consumables:Entries(selected)
    local def = Consumables:Def(selected)
    itemTitle:SetText("Items: " .. (def and def.label or selected))
    if def and def.kind == "count" then
        itemHint:SetText("Only the total in your bags is shown for this icon. Drag more items here to add them.")
    elseif def and def.clickable then
        itemHint:SetText("Clicking the icon uses the first item you have in your bags. Drag more items here to add them.")
    else
        itemHint:SetText("This icon is not clickable. Drag more items here to add them.")
    end

    for i, entry in ipairs(entries) do
        local row = itemRow(i)
        row.itemId = entry.item
        row.icon:SetTexture(Consumables:ItemIcon(entry.item))
        local name = Consumables:ItemName(entry)
        if entry.user then
            name = name .. "  |cffffd100(yours)|r"
        end
        row.text:SetText(name)
        local count = Consumables:ItemCount(entry.item)
        if count > 0 then
            row.side:SetText("|cff55dd55x" .. count .. " in bags|r")
        else
            row.side:SetText("|cff888888none|r")
        end
        row.remove:SetShown(entry.user and true or false)
        -- The name runs up to the leftmost button, which is Remove only for your own items.
        row.text:SetPoint("RIGHT", entry.user and row.remove or row.up, "LEFT", -6, 0)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #entries)
        row:Show()
    end
    for i = #entries + 1, #itemRows do
        itemRows[i]:Hide()
    end
    itemChild:SetHeight(math.max(1, #entries * ITEM_ROW_H))
    itemEmpty:SetShown(#entries == 0)
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    enabledCheck:SetChecked(Consumables:Enabled())
    if not lowEdit:HasFocus() then
        lowEdit:SetText(tostring(Consumables:LowMinutes()))
    end

    local order = Consumables:Order()
    for i, row in ipairs(catRows) do
        local key = order[i]
        local def = Consumables:Def(key)
        row.key = key
        row.text:SetText(i .. ".  " .. (def and def.label or key))
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #order)
        local color = (key == selected) and GOLD or GRAY
        row:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    end

    Consumables:RefreshBags()
    refreshBar()
    refreshItems()

    local db = Consumables:Database()
    local total = 0
    for _, list in pairs(db.categories or {}) do
        total = total + #list
    end
    footer:SetText(format("Built-in list: %s, updated %s, %d consumables.", tostring(db.expansion), tostring(db.updated), total))
    learning:SetText(Consumables:LearningText())
end

local function build(pf)
    page = pf


    enabledCheck = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    enabledCheck:SetSize(26, 26)
    enabledCheck:SetPoint("TOPLEFT", 4, -12)
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

    local resetBar = makeButton(pf, "Reset bar position", 170)
    resetBar:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -176, -10)
    resetBar:SetScript("OnClick", function()
        CRT.ConsumablesDisplay:ResetPosition()
    end)

    local preview = makeButton(pf, "Preview on screen", 160)
    preview:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, -10)
    preview:SetScript("OnClick", function()
        CRT.ConsumablesDisplay:Preview()
    end)

    buildBar(pf)

    -- Left: icon order.
    local orderTitle = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    orderTitle:SetPoint("TOPLEFT", 8, -132)
    orderTitle:SetText("Icon order, left to right")
    buildCategoryRows(pf)

    -- Right: items for the selected category.
    itemTitle = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    itemTitle:SetPoint("TOPLEFT", RIGHT_X, -132)
    -- The item hint depends on the selected category, so the (?) reads it when hovered.
    itemHint = { text = "", SetText = function(self, t) self.text = t end }
    UI.Help(pf, "Items", function()
        return itemHint.text
    end):SetPoint("LEFT", itemTitle, "RIGHT", 6, 0)

    local box = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    box:SetPoint("TOPLEFT", pf, "TOPLEFT", RIGHT_X, -154)
    box:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, 56)
    box:EnableMouse(true)
    skin(box, 0.3)
    box:SetScript("OnReceiveDrag", function()
        drop(selected)
    end)

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsConsumableScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    itemChild = CreateFrame("Frame", nil, scroll)
    itemChild:SetSize(316, 1)
    scroll:SetScrollChild(itemChild)
    -- The rows fill the box's width, whatever the panel size.
    scroll:SetScript("OnSizeChanged", function(_, w)
        itemChild:SetWidth(w)
    end)

    itemEmpty = box:CreateFontString(nil, "OVERLAY", "CRTFontDisable")
    itemEmpty:SetPoint("TOPLEFT", box, "TOPLEFT", 20, -24)
    itemEmpty:SetPoint("TOPRIGHT", box, "TOPRIGHT", -40, -24)
    itemEmpty:SetJustifyH("CENTER")
    itemEmpty:SetWordWrap(true)
    itemEmpty:SetText("Nothing is listed for this category yet. Drag an item here to add it.")
    itemEmpty:Hide()

    learning = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    learning:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 8, 34)
    learning:SetTextColor(0.6, 0.9, 0.6)
    footer = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 8, 12)

    pf:SetScript("OnShow", refresh)
    pf:SetScript("OnUpdate", function(_, dt)
        -- The ants move every frame, and the bar's status refreshes twice a second.
        for _, slot in ipairs(barSlots) do
            Ants:Update(slot, dt)
        end
        barElapsed = barElapsed + dt
        if barElapsed >= REFRESH_SECONDS then
            barElapsed = 0
            refreshBar()
            learning:SetText(Consumables:LearningText())
        end
    end)
    Consumables:OnChange(refresh)
end

-- Built into the Your bar tab by ReadyCheck/Page.lua.
CRT.ConsumablesPage = { Build = build }
