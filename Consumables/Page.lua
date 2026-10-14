local ADDON, CRT = ...

-- The Consumables page: the list of consumables ships with the addon, so this page only chooses
-- the order. Move the icons left or right on the ready check row, and choose which item is used
-- first when you click an icon.

local Consumables = CRT.Consumables
local UI = CRT.UI

local CAT_ROW_H = 36
local ITEM_ROW_H = 32
local LEFT_W = 270
local RIGHT_X = 300

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

local page, enabledCheck, lowEdit, itemTitle, itemHint, itemEmpty, footer, itemChild
local selected = "food"
local catRows, itemRows = {}, {}
local refresh

-- Icon order: five rows, each with Up and Down. Clicking a row selects its category. -----

local function buildCategoryRows(pf)
    local top = -138
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
            selected = self.key
            refresh()
        end)
        catRows[i] = row
    end
end

-- Item priority for the selected category, in a scrolling list. ---------------------------

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
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.down = makeButton(row, "Down", 54, 22)
    row.down:SetPoint("RIGHT", -4, 0)
    row.down:SetScript("OnClick", function()
        Consumables:MoveItem(selected, row.itemId, 1)
    end)
    row.up = makeButton(row, "Up", 44, 22)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
    row.up:SetScript("OnClick", function()
        Consumables:MoveItem(selected, row.itemId, -1)
    end)

    row.side = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.side:SetPoint("RIGHT", row.up, "LEFT", -8, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row.side, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")

    itemRows[index] = row
    return row
end

local function refreshItems()
    Consumables:RefreshBags()
    local entries = Consumables:Entries(selected)
    local def = Consumables:Def(selected)
    itemTitle:SetText("Items: " .. (def and def.label or selected))
    if def and def.kind == "count" then
        itemHint:SetText("Only the total in your bags is shown for this icon.")
    elseif def and def.clickable then
        itemHint:SetText("Clicking the icon uses the first item you have in your bags.")
    else
        itemHint:SetText("This icon is not clickable.")
    end

    for i, entry in ipairs(entries) do
        local row = itemRow(i)
        row.itemId = entry.item
        row.icon:SetTexture(Consumables:ItemIcon(entry.item))
        row.text:SetText(Consumables:ItemName(entry))
        local count = Consumables:ItemCount(entry.item)
        if count > 0 then
            row.side:SetText("|cff55dd55x" .. count .. " in bags|r")
        else
            row.side:SetText("|cff888888none|r")
        end
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

    refreshItems()

    local db = Consumables:Database()
    local total = 0
    for _, list in pairs(db.categories or {}) do
        total = total + #list
    end
    footer:SetText(format("Built-in list: %s, updated %s, %d consumables.", tostring(db.expansion), tostring(db.updated), total))
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
    hint:SetText("The ready check row uses a built-in list of consumables that is kept up to date with the addon. Here you only choose the order.")

    enabledCheck = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    enabledCheck:SetSize(26, 26)
    enabledCheck:SetPoint("TOPLEFT", 4, -66)
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
    preview:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, -64)
    preview:SetScript("OnClick", function()
        CRT.ConsumablesDisplay:Preview()
    end)

    -- Left: icon order.
    local orderTitle = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    orderTitle:SetPoint("TOPLEFT", 8, -108)
    orderTitle:SetText("Icon order, left to right")
    buildCategoryRows(pf)

    -- Right: item priority for the selected category.
    itemTitle = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    itemTitle:SetPoint("TOPLEFT", RIGHT_X, -108)
    itemHint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    itemHint:SetPoint("TOPLEFT", RIGHT_X, -130)

    local box = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    box:SetPoint("TOPLEFT", pf, "TOPLEFT", RIGHT_X, -152)
    box:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, 40)
    skin(box, 0.3)

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsConsumableScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    itemChild = CreateFrame("Frame", nil, scroll)
    itemChild:SetSize(340, 1)
    scroll:SetScrollChild(itemChild)

    itemEmpty = box:CreateFontString(nil, "OVERLAY", "CRTFontDisable")
    itemEmpty:SetPoint("TOP", box, "TOP", 0, -24)
    itemEmpty:SetText("Nothing is listed for this category yet.")
    itemEmpty:Hide()

    footer = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", 8, 12)

    pf:SetScript("OnShow", refresh)
    Consumables:OnChange(refresh)
end

UI:RegisterPage("consumables", "Consumables", build)
