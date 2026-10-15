local ADDON, CRT = ...

-- The Your bar tab of the Ready Check page (ReadyCheck/Page.lua builds it into its tab). The list of
-- consumables ships with the addon, and here you can:
--   * see the same bar that shows on the ready check, with live status,
--   * drag an item from your bags onto an icon to add it to that category (optional),
--   * drag the rows to set the icon order, and which item is used first when you click an icon.
-- Whether the bar shows, and the warning time, are on the Ready Check page's Settings tab.
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

local page, itemTitle, itemHint, itemEmpty, footer, learning, itemChild, barFrame
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
    Bar.AddStatusLines(self.status)
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
    UI.Help(pf, "Your bar", "Your own bar of consumable icons that appears during a ready check. It uses a built-in list of consumables kept up to date with the addon. You can add your own, and choose the order.\n\nDrag an item from your bags onto an icon to add it. Click an icon to see its items. Drag the rows below to change the order.\n\nWhether it shows, and when it warns, are on the Settings tab."):SetPoint("LEFT", label, "RIGHT", 6, 0)

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

-- Drag to reorder ------------------------------------------------------------------------------
-- A row in either list can be dragged up or down. While it is dragged, a gold line shows where it
-- will land, and letting go moves it there. Clicking a row without dragging still selects it.

local drag -- { rows = the shown rows, top to bottom, from = the dragged row's place, onDrop = function(place) }
local marker

-- Where the dragged row would land: before row i, or after the last row (#rows + 1).
local function insertAt(rows)
    local _, y = GetCursorPosition()
    y = y / rows[1]:GetEffectiveScale()
    local index = 1
    for i, row in ipairs(rows) do
        local _, centre = row:GetCenter()
        if centre and y < centre then
            index = i + 1
        end
    end
    return index
end

local function placeMarker()
    if not drag then
        return
    end
    local rows = drag.rows
    local index = insertAt(rows)
    marker:ClearAllPoints()
    if index <= #rows then
        marker:SetPoint("BOTTOMLEFT", rows[index], "TOPLEFT", 0, 1)
        marker:SetPoint("BOTTOMRIGHT", rows[index], "TOPRIGHT", 0, 1)
    else
        marker:SetPoint("TOPLEFT", rows[#rows], "BOTTOMLEFT", 0, -1)
        marker:SetPoint("TOPRIGHT", rows[#rows], "BOTTOMRIGHT", 0, -1)
    end
    marker:Show()
end

-- Makes a row draggable. getRows returns the list's shown rows in order, and onDrop(place) moves the
-- row's entry to that place (1 is the top).
local function draggable(row, getRows, onDrop)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        local rows = getRows()
        for i, r in ipairs(rows) do
            if r == self then
                drag = { rows = rows, from = i, onDrop = onDrop, row = self }
            end
        end
        if drag then
            self:SetAlpha(0.5)
            placeMarker()
        end
    end)
    row:SetScript("OnDragStop", function(self)
        self:SetAlpha(1)
        marker:Hide()
        if not drag then
            return
        end
        local index = insertAt(drag.rows)
        -- The row leaves its old place first, so a place below it moves up by one.
        local place = index > drag.from and index - 1 or index
        local d = drag
        drag = nil
        if place ~= d.from then
            d.onDrop(place)
        end
    end)
end

-- Icon order: five rows to drag into order. Clicking a row selects its category. ----------------

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

        draggable(row, function()
            return catRows
        end, function(place)
            Consumables:MoveCategoryTo(row.key, place)
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

    -- Drag the row to change which item is used first. Dropping an item from your bags on a row
    -- still adds it to the list.
    row:EnableMouse(true)
    draggable(row, function()
        local rows = {}
        for _, r in ipairs(itemRows) do
            if r:IsShown() then
                rows[#rows + 1] = r
            end
        end
        return rows
    end, function(place)
        Consumables:MoveItemTo(selected, row.itemId, place)
    end)
    row:SetScript("OnReceiveDrag", function()
        drop(selected)
    end)
    row.remove = makeButton(row, "Remove", 58, 22)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.remove:SetScript("OnClick", function()
        Consumables:RemoveExtra(selected, row.itemId)
    end)

    -- The name on the top line, and how many are in your bags under it, so a long name has room.
    row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
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
        itemHint:SetText("Clicking the icon uses the first item you have in your bags. Drag the rows to change which comes first. Drag more items here to add them.")
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
        -- The name runs to the row's edge, or up to Remove for your own items.
        if entry.user then
            row.text:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
        else
            row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end
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
    local order = Consumables:Order()
    for i, row in ipairs(catRows) do
        local key = order[i]
        local def = Consumables:Def(key)
        row.key = key
        row.text:SetText(i .. ".  " .. (def and def.label or key))
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

    -- The gold line that shows where a dragged row will land. It is its own frame, drawn above the
    -- lists, so the item box's background does not cover it.
    marker = CreateFrame("Frame", nil, pf)
    marker:SetFrameStrata("DIALOG")
    marker:SetHeight(2)
    local line = marker:CreateTexture(nil, "OVERLAY")
    line:SetAllPoints()
    line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    marker:Hide()

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
    -- A drag that is still going when the tab closes is dropped, without moving anything.
    pf:SetScript("OnHide", function()
        if drag then
            drag.row:SetAlpha(1)
            drag = nil
        end
        marker:Hide()
    end)
    pf:SetScript("OnUpdate", function(_, dt)
        -- The gold line follows the mouse while a row is dragged.
        placeMarker()
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
