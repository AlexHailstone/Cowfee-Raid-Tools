local ADDON, CRT = ...

-- Maintainer tools for the consumables list: a copyable text window (also used by the Late Tracker's
-- Discord export), and the two commands that use it. `/crt consumables scan` prints your buffs and bag consumables as lines to paste into
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
    w:SetSize(760, 560)
    w:SetPoint("CENTER")
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:SetResizable(true)
    w:SetResizeBounds(420, 260, 1400, 1000)
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
    w.edit:SetFontObject(CRTFontEdit)
    w.edit:SetWidth(700)
    w.edit:SetScript("OnEscapePressed", function()
        w:Hide()
    end)
    scroll:SetScrollChild(w.edit)
    scroll:SetScript("OnSizeChanged", function(_, width)
        w.edit:SetWidth(width)
    end)

    -- Drag the bottom-right corner to resize.
    local grip = CreateFrame("Button", nil, w)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        w:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        w:StopMovingOrSizing()
    end)

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
