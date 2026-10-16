local ADDON, CRT = ...

-- Your next assignment: a movable alert that appears only when a timer with your name (or your role) is
-- coming up, shows the spell or text with a countdown, and can read it out with text to speech.

local Notes = CRT.Notes
local Engine = CRT.NoteEngine
local Alert = {}
CRT.NoteAlert = Alert

local REFRESH_SECONDS = 0.1
local ICON_GAP = 8 -- between the icon and the text
local LINE_GAP = 2 -- between the name and the countdown

local frame, handle, icon, block, label, countdown
local handleText -- the drag box's title
local handleMin -- the drag box's least width: its whole title and Reset
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 220 }
local previewOn = false
local elapsed = 0

local function settings()
    return Notes:Alert()
end

-- Text to speech is the alerts speech queue; the Settings tab's Test speech button speaks through here.
function Alert:Speak(text)
    CRT.AlertSpeech:SpeakNow(text)
end

-- The alert -------------------------------------------------------------------------------

-- Wide enough for the whole title left of Reset (44 wide), and at least as wide as the alert. Measured
-- again whenever Previews turn on, so a font change applies.
local function measureHandle()
    if not (handle and handleText) then
        return
    end
    local titleWidth = handleText.GetUnboundedStringWidth and handleText:GetUnboundedStringWidth() or handleText:GetStringWidth()
    handleMin = math.ceil(6 + titleWidth + 4 + 44 + 2)
    handle:SetWidth(math.max(handleMin, frame and frame:GetWidth() or 0))
end

-- Lays the alert out: the name and the countdown centered under each other, and the icon, two text
-- lines tall, on the side chosen on the Raid Notes Settings tab. The alert is kept centered on its
-- saved position, so it grows evenly as the name changes.
local function layout()
    local nameHeight = select(2, label:GetFont()) or 18
    local timeHeight = select(2, countdown:GetFont()) or 18
    local height = math.floor(nameHeight + LINE_GAP + timeHeight + 0.5)
    local width = math.max(label:GetStringWidth(), countdown:GetStringWidth(), 20)
    block:SetSize(width, height)
    icon:SetSize(height, height)

    icon:ClearAllPoints()
    block:ClearAllPoints()
    local position = settings().iconPosition or "left"
    if not icon:IsShown() then
        block:SetPoint("CENTER")
        frame:SetSize(width, height)
    elseif position == "right" then
        block:SetPoint("LEFT")
        icon:SetPoint("LEFT", block, "RIGHT", ICON_GAP, 0)
        frame:SetSize(width + ICON_GAP + height, height)
    elseif position == "above" then
        icon:SetPoint("TOP")
        block:SetPoint("TOP", icon, "BOTTOM", 0, -ICON_GAP / 2)
        frame:SetSize(math.max(width, height), height * 2 + ICON_GAP / 2)
    elseif position == "below" then
        block:SetPoint("TOP")
        icon:SetPoint("TOP", block, "BOTTOM", 0, -ICON_GAP / 2)
        frame:SetSize(math.max(width, height), height * 2 + ICON_GAP / 2)
    else
        icon:SetPoint("LEFT")
        block:SetPoint("LEFT", icon, "RIGHT", ICON_GAP, 0)
        frame:SetSize(height + ICON_GAP + width, height)
    end
    if handle and handleMin then
        handle:SetWidth(math.max(handleMin, frame:GetWidth() or 0))
    end
end

-- What the alert last drew, so a refresh that changes nothing skips the work.
local drawn

local function show(iconTexture, text, time, color)
    local key = tostring(iconTexture) .. "|" .. text .. "|" .. time .. "|" .. (color and table.concat(color, ",") or "") .. "|" .. tostring(settings().iconPosition) .. "|" .. tostring((select(2, label:GetFont())))
    if key == drawn and frame:IsShown() then
        return
    end
    drawn = key
    icon:SetShown(iconTexture ~= nil)
    if iconTexture then
        icon:SetTexture(iconTexture)
    end
    label:SetText(text)
    if color then
        label:SetTextColor(color[1], color[2], color[3])
    else
        label:SetTextColor(1, 0.82, 0)
    end
    countdown:SetText(time)
    layout()
    frame:Show()
end

local function countdownText(remaining)
    if remaining <= 0 then
        return "NOW"
    elseif remaining < 10 then
        return format("%.1fs", remaining)
    end
    return math.floor(remaining) .. "s"
end

function Alert:Refresh()
    if not frame then
        return
    end
    handle:SetShown(previewOn)
    if previewOn then
        local info = Notes:SpellInfo(31884)
        show(info and info.icon or 134400, info and info.name or "Your spell", "5.0s")
        return
    end
    local s = settings()
    if not (s.enabled and CRT.Alerts.running) then
        frame:Hide()
        return
    end

    -- The alert: the engine's line inside its warn and hold window, soonest first.
    local now = GetTime()
    local best = CRT.AlertRules.Alert(CRT.Alerts:Lines(now), now)
    if not best then
        frame:Hide()
        return
    end
    local remaining = best.at - now
    if best.block == "note" and type(best.spellID) == "number" and not best.ownLabel then
        -- A note's spell line shows the spell's own name, as it always did. A line with show:
        -- (ownLabel) shows its own text, icon and colour below, like a reminder.
        local info = Notes:SpellInfo(best.spellID)
        show(info and info.icon or best.icon, info and info.name or best.text or ("Spell " .. best.spellID), countdownText(remaining))
    else
        -- Any other line (a reminder, or a merged "Soak + Defensive") shows its own text, with the
        -- spell's icon when the line has none of its own.
        local icon = best.icon
        if icon == nil and type(best.spellID) == "number" then
            local info = Notes:SpellInfo(best.spellID)
            icon = info and info.icon
        end
        show(icon, best.text or "", countdownText(remaining), best.color)
    end
end

local function applyPosition()
    local p = settings().position or DEFAULT_POSITION
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
end

function Alert:ResetPosition()
    settings().position = nil
    if frame then
        applyPosition()
    end
end

local function build()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "CowfeeRaidToolsNoteAlert", UIParent)
    frame:SetSize(320, 56)
    CRT.UI:RegisterLayer("alert", frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)

    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- The two text lines, centered under each other in their own frame.
    block = CreateFrame("Frame", nil, frame)
    label = block:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    label:SetPoint("TOP")
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetShadowOffset(1, -1)

    countdown = block:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    countdown:SetPoint("TOP", label, "BOTTOM", 0, -LINE_GAP)
    countdown:SetJustifyH("CENTER")
    countdown:SetTextColor(1, 1, 1)
    countdown:SetShadowOffset(1, -1)

    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    handle:SetBackdropColor(0.3, 0.25, 0.05, 0.9)
    handle:SetBackdropBorderColor(1, 0.82, 0, 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", 6, 0)
    text:SetText("Your next spell: drag to move")
    CRT.UI.ResetButton(handle, function()
        Alert:ResetPosition()
    end):SetPoint("RIGHT", -2, 0)
    handleText = text
    measureHandle()
    handle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    -- Saved by its center, so the alert grows evenly around where you put it.
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        settings().position = { point = "CENTER", relativePoint = "CENTER", x = x - ux, y = y - uy }
        applyPosition()
    end)
    handle:Hide()

    applyPosition()
    frame:Hide()
end

-- The alert hides itself when there is nothing to show, so this frame keeps it updated.
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < REFRESH_SECONDS then
        return
    end
    elapsed = 0
    if frame then
        Alert:Refresh()
    end
end)
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function()
    build()
end)

CRT.UI:RegisterPreview("alert", function(on)
    build()
    if on then
        measureHandle()
    end
    previewOn = on and true or false
    Alert:Refresh()
    if not previewOn and not Engine.running then
        frame:Hide()
    end
end)
