local ADDON, CRT = ...

-- Maintainer tools for the consumables list: a copyable text window, and the two commands that
-- use it. `/crt consumables scan` prints your buffs and bag consumables as lines to paste into
-- Consumables/Database.lua, and `/crt consumables check` tests every listed ID against the game.

local Consumables = CRT.Consumables
local UI = CRT.UI
local Tools = {}
CRT.ConsumablesTools = Tools

local window

local function getWindow()
    if window then
        return window
    end
    local w = CreateFrame("Frame", "CowfeeRaidToolsTextWindow", UIParent, "BasicFrameTemplateWithInset")
    w:SetSize(620, 460)
    w:SetPoint("CENTER")
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CowfeeRaidToolsTextWindow")
    w:Hide()

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTextWindowScroll", w, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -34)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    w.edit = CreateFrame("EditBox", nil, scroll)
    w.edit:SetMultiLine(true)
    w.edit:SetAutoFocus(false)
    w.edit:SetFontObject(ChatFontNormal)
    w.edit:SetWidth(560)
    w.edit:SetScript("OnEscapePressed", function()
        w:Hide()
    end)
    scroll:SetScrollChild(w.edit)

    window = w
    return w
end

function Tools:ShowText(title, text)
    local w = getWindow()
    UI.SetFrameTitle(w, title)
    w.edit:SetText(text)
    w:Show()
    w.edit:SetFocus()
    w.edit:HighlightText()
end

function Tools:Scan()
    Consumables:RefreshBags()
    self:ShowText("Consumables scan (Ctrl+C to copy)", Consumables:ScanText())
end

function Tools:Check()
    Consumables:RefreshBags()
    self:ShowText("Consumables list check", Consumables:CheckText())
end
