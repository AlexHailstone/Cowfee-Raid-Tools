local ADDON, CRT = ...

-- Shared drawing for the consumables bar. The ready check row (Display.lua) and the bar on the
-- Consumables tab (Page.lua) both build their icons with these, so they always look the same.

local Consumables = CRT.Consumables
local Ants = CRT.Ants
local Bar = {}
CRT.ConsumablesBar = Bar

Bar.ICON_SIZE = 44
Bar.GAP = 6
Bar.PAD = 6

local BORDER = { 0.35, 0.35, 0.35 }
local ANT_COLORS = {
    missing = { 1, 0.25, 0.25 },
    low = { 1, 0.82, 0 },
}

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

Bar.BORDER = BORDER
Bar.BACKDROP = BACKDROP

-- Width and height of a bar holding count icons.
function Bar.Size(count)
    return Bar.PAD * 2 + count * Bar.ICON_SIZE + (count - 1) * Bar.GAP, Bar.PAD * 2 + Bar.ICON_SIZE
end

-- 36s under a minute, then whole minutes: 230m.
function Bar.FormatTime(seconds)
    if seconds < 60 then
        return format("%ds", math.max(0, math.floor(seconds + 0.5)))
    end
    return format("%dm", math.floor(seconds / 60 + 0.5))
end

-- Time left for a tooltip: 45 s, 42 min, or 1 h 05 min.
function Bar.LongTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then
        return seconds .. " s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60 + 0.5) .. " min"
    end
    return format("%d h %02d min", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

-- The lines a tooltip shows for an icon's status (from Consumables:Status): what is active and how
-- long it has left, or that it is missing.
function Bar.AddStatusLines(status)
    if not status then
        return
    end
    if status.state == "active" or status.state == "low" then
        local name = status.name or "Active"
        local left = status.left and (Bar.LongTime(status.left) .. " left") or "no time limit"
        if status.state == "low" then
            GameTooltip:AddLine(name .. ": " .. left .. " (running low)", 1, 0.82, 0)
        else
            GameTooltip:AddLine(name .. ": " .. left, 0.4, 1, 0.4)
        end
        if status.charges then
            GameTooltip:AddLine(status.charges .. " charges left", 0.8, 0.8, 0.8)
        end
    elseif status.state == "missing" then
        GameTooltip:AddLine("Missing", 1, 0.3, 0.3)
    elseif status.state == "unknown" then
        GameTooltip:AddLine("The game is hiding your buffs right now", 0.6, 0.6, 0.6)
    elseif status.state == "unset" then
        GameTooltip:AddLine("Nothing is listed for this icon yet", 0.6, 0.6, 0.6)
    end
end

-- One icon. secure = true makes a protected button that can run a click action.
function Bar.CreateSlot(parent, index, secure)
    local slot
    if secure then
        slot = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
        slot:RegisterForClicks("AnyUp")
        slot:SetAttribute("useOnKeyDown", false)
    else
        slot = CreateFrame("Button", nil, parent, "BackdropTemplate")
        slot:RegisterForClicks("AnyUp")
    end
    slot:SetSize(Bar.ICON_SIZE, Bar.ICON_SIZE)
    slot:SetPoint("TOPLEFT", parent, "TOPLEFT", Bar.PAD + (index - 1) * (Bar.ICON_SIZE + Bar.GAP), -Bar.PAD)
    slot:SetBackdrop(BACKDROP)
    slot:SetBackdropColor(0, 0, 0, 0.6)
    slot:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    slot.hl = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.hl:SetAllPoints()
    slot.hl:SetColorTexture(1, 1, 1, 0.18)

    slot.time = slot:CreateFontString(nil, "OVERLAY", "CRTFontHighlight")
    slot.time:SetPoint("BOTTOM", 0, 3)

    slot.count = slot:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    slot.count:SetPoint("TOPRIGHT", -3, -3)

    slot.tag = slot:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    slot.tag:SetPoint("TOPLEFT", 3, -3)
    slot.tag:SetTextColor(0.3, 0.9, 1)

    Ants:Attach(slot)
    return slot
end

-- Shows a status (from Consumables:Status) on an icon: the picture, the ants, and the text.
function Bar.Apply(slot, status)
    slot.status = status -- kept for the icon's tooltip
    -- Reset the border every time, so a highlight set by a caller (the selected icon on the
    -- Consumables tab) goes away as soon as it stops being applied.
    slot:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    slot.icon:SetTexture(status.icon or Consumables.QUESTION_MARK)
    local dim = status.state == "missing" or status.state == "unset" or status.state == "unknown"
    slot.icon:SetDesaturated(dim)
    slot.icon:SetAlpha(dim and 0.6 or 1)

    -- Ants for a missing or expiring consumable.
    local color = ANT_COLORS[status.state]
    if color then
        Ants:Start(slot, color[1], color[2], color[3])
    else
        Ants:Stop(slot)
    end

    -- "no data" is too wide for one line under a 44 pixel icon, so it is two small lines.
    slot.time:SetFontObject(status.state == "unset" and CRTFontSmall or CRTFontHighlight)
    if status.state == "unknown" then
        slot.time:SetText("?")
    elseif status.state == "unset" then
        slot.time:SetText("no\ndata")
    elseif status.left then
        slot.time:SetText(Bar.FormatTime(status.left))
    else
        slot.time:SetText("")
    end
    if status.state == "low" then
        slot.time:SetTextColor(1, 0.82, 0)
    else
        slot.time:SetTextColor(1, 1, 1)
    end

    if status.count then
        slot.count:SetText(status.count)
        if status.count == 0 then
            slot.count:SetTextColor(0.9, 0.2, 0.2)
        else
            slot.count:SetTextColor(1, 1, 1)
        end
    else
        slot.count:SetText("")
    end
    slot.tag:SetText(status.tag or "")
end
