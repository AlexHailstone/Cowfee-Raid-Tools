local ADDON, CRT = ...

-- DEVELOPER ONLY. Boss order (Development page, /crt dev bosses): the raid progression route of the
-- current season, the order every boss list in the addon follows (CRT.Bosses:Route). Each raid is a
-- heading with its name, its bosses under it; up and down move a boss, across raid headings too. Every
-- change applies at once on this computer (CRTDB.dev.bossRoute[season]) and boss lists redraw.
--   New raid           adds an empty raid at the end, to move bosses into
--   Reset to shipped   drops this computer's order; the season's Season.lua order applies again
--   Export             the raids table to paste into the season's Season.lua, which is what ships
-- This file never ships: its .toc line is inside the do-not-package block.

local Order = {}
CRT.BossOrder = Order

local UI = CRT.UI
local Bosses = CRT.Bosses

local ROW_H = 26
local WIN_W = 420
local TOP = 64

local win, seasonKey
local raids -- the working route: { { key, name, bosses = { encounterID, ... } } }
local rowPool = {}

local function devRoutes()
    CRT.db.dev = CRT.db.dev or {}
    CRT.db.dev.bossRoute = CRT.db.dev.bossRoute or {}
    return CRT.db.dev.bossRoute
end

-- The route as it applies now (shipped, or this computer's), as plain IDs, every boss placed.
local function load()
    seasonKey = Bosses:Current() and Bosses:Current().key
    raids = {}
    if not seasonKey then
        return
    end
    for _, group in ipairs(Bosses:Route(seasonKey)) do
        local raid = { key = group.raid.key, name = group.raid.name, bosses = {} }
        for _, def in ipairs(group.bosses) do
            raid.bosses[#raid.bosses + 1] = def.encounterID
        end
        raids[#raids + 1] = raid
    end
end

local function save()
    devRoutes()[seasonKey] = raids
    Bosses:FireRoute()
end

local refresh

local function move(gi, bi, dir)
    local list = raids[gi].bosses
    local id = list[bi]
    if dir < 0 then
        if bi > 1 then
            list[bi], list[bi - 1] = list[bi - 1], list[bi]
        elseif gi > 1 then
            table.remove(list, bi)
            table.insert(raids[gi - 1].bosses, id)
        end
    else
        if bi < #list then
            list[bi], list[bi + 1] = list[bi + 1], list[bi]
        elseif gi < #raids then
            table.remove(list, bi)
            table.insert(raids[gi + 1].bosses, 1, id)
        end
    end
    save()
    refresh()
end

local function exportText()
    local lines = { "    raids = {" }
    for _, raid in ipairs(raids) do
        lines[#lines + 1] = "        {"
        lines[#lines + 1] = string.format("            key = %q,", raid.key)
        lines[#lines + 1] = string.format("            name = %q,", raid.name)
        lines[#lines + 1] = "            bosses = {"
        for _, id in ipairs(raid.bosses) do
            local def = Bosses:Get(id)
            lines[#lines + 1] = string.format("                %d, -- %s", id, def and def.name or "?")
        end
        lines[#lines + 1] = "            },"
        lines[#lines + 1] = "        },"
    end
    lines[#lines + 1] = "    },"
    return table.concat(lines, "\n")
end

local function smallButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

-- One row: a raid heading (an editable name, Remove when empty) or a boss (its name, up and down).
local function getRow(i)
    local r = rowPool[i]
    if r then
        return r
    end
    r = CreateFrame("Frame", nil, win)
    r:SetSize(WIN_W - 28, ROW_H)
    r:SetPoint("TOPLEFT", 14, -TOP - (i - 1) * ROW_H)
    r.nameEdit = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
    r.nameEdit:SetSize(230, 20)
    r.nameEdit:SetPoint("LEFT", 6, 0)
    r.nameEdit:SetAutoFocus(false)
    r.nameEdit:SetFontObject(CRTFontEdit)
    r.nameEdit:SetScript("OnEnterPressed", r.nameEdit.ClearFocus)
    r.nameEdit:SetScript("OnEditFocusLost", function(self)
        local raid = raids[r.gi]
        local text = strtrim(self:GetText() or "")
        if raid and text ~= "" and text ~= raid.name then
            raid.name = text
            save()
        end
        refresh()
    end)
    r.remove = smallButton(r, "Remove", 70)
    r.remove:SetPoint("LEFT", r.nameEdit, "RIGHT", 8, 0)
    r.remove:SetScript("OnClick", function()
        if raids[r.gi] and #raids[r.gi].bosses == 0 then
            table.remove(raids, r.gi)
            save()
            refresh()
        end
    end)
    r.boss = r:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    r.boss:SetPoint("LEFT", 28, 0)
    r.boss:SetWidth(260)
    r.boss:SetJustifyH("LEFT")
    r.boss:SetWordWrap(false)
    r.up = smallButton(r, "Up", 44)
    r.up:SetPoint("RIGHT", -52, 0)
    r.up:SetScript("OnClick", function()
        move(r.gi, r.bi, -1)
    end)
    r.down = smallButton(r, "Down", 48)
    r.down:SetPoint("RIGHT", 0, 0)
    r.down:SetScript("OnClick", function()
        move(r.gi, r.bi, 1)
    end)
    UI:SkinTree(r)
    rowPool[i] = r
    return r
end

refresh = function()
    if not win then
        return
    end
    local i = 0
    for gi, raid in ipairs(raids) do
        i = i + 1
        local r = getRow(i)
        r.gi, r.bi = gi, nil
        r.nameEdit:Show()
        if not r.nameEdit:HasFocus() then
            r.nameEdit:SetText(raid.name or "")
        end
        r.remove:SetShown(#raid.bosses == 0)
        r.boss:Hide()
        r.up:Hide()
        r.down:Hide()
        r:Show()
        for bi, id in ipairs(raid.bosses) do
            i = i + 1
            local b = getRow(i)
            b.gi, b.bi = gi, bi
            b.nameEdit:Hide()
            b.remove:Hide()
            local def = Bosses:Get(id)
            b.boss:SetText(string.format("%d. %s", bi, def and def.name or tostring(id)))
            b.boss:Show()
            b.up:Show()
            b.down:Show()
            b.up:SetEnabled(bi > 1 or gi > 1)
            b.down:SetEnabled(bi < #raid.bosses or gi < #raids)
            b:Show()
        end
    end
    for j = i + 1, #rowPool do
        rowPool[j]:Hide()
    end
    local _, custom = Bosses:Raids(seasonKey)
    win.status:SetText(custom and "Your order (this computer only). Export it into Season.lua to ship it." or "The shipped order, from Season.lua.")
    win:SetHeight(TOP + math.max(i, 1) * ROW_H + 70)
end

local function build()
    win = CreateFrame("Frame", "CowfeeRaidToolsBossOrder", UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(win)
    win:SetSize(WIN_W, 400)
    win:SetPoint("CENTER")
    UI:RegisterLayer("popups", win)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "CowfeeRaidToolsBossOrder")
    UI.SetFrameTitle(win, "Boss order (dev)")

    local season = win:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    season:SetPoint("TOPLEFT", 16, -34)
    win.season = season
    UI.Help(win, "Boss order", "The raid progression route: the order every boss list in the addon shows, grouped by raid. Up and Down move a boss, into the raid before or after at the ends. Type a raid's name to rename it; an empty raid can be removed.\n\nChanges apply at once, on this computer only. Export gives the raids table for the season's Season.lua, which is what ships. Reset to shipped goes back to Season.lua's order."):SetPoint("LEFT", season, "RIGHT", 6, 0)

    win.status = win:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    win.status:SetPoint("BOTTOMLEFT", 16, 40)
    win.status:SetWidth(WIN_W - 32)
    win.status:SetJustifyH("LEFT")

    local newRaid = smallButton(win, "New raid", 90)
    newRaid:SetPoint("BOTTOMLEFT", 14, 12)
    newRaid:SetScript("OnClick", function()
        raids[#raids + 1] = { key = seasonKey .. "-raid" .. (#raids + 1), name = "New raid", bosses = {} }
        save()
        refresh()
    end)
    local reset = smallButton(win, "Reset to shipped", 130)
    reset:SetPoint("LEFT", newRaid, "RIGHT", 6, 0)
    reset:SetScript("OnClick", function()
        devRoutes()[seasonKey] = nil
        Bosses:FireRoute()
        load()
        refresh()
    end)
    local export = smallButton(win, "Export", 90)
    export:SetPoint("LEFT", reset, "RIGHT", 6, 0)
    export:SetScript("OnClick", function()
        CRT.ConsumablesTools:ShowText("Boss order for Season.lua (Ctrl+C to copy, paste to Claude)", exportText())
    end)
    UI:SkinTree(win)
end

function Order:Toggle()
    if not win then
        build()
    end
    if win:IsShown() then
        win:Hide()
        return
    end
    load()
    if not seasonKey then
        CRT:Print("Boss order: no season pack is loaded.")
        return
    end
    win.season:SetText(Bosses:Current().name)
    win:Show()
    refresh()
end
