local ADDON, CRT = ...

-- The row of consumable icons shown above the ready check: one icon per category with the
-- time left, or the number in your bags when it is missing. Edited on the Consumables page.

local Consumables = CRT.Consumables
local Display = {}
CRT.ConsumablesDisplay = Display

local ICON_SIZE = 44
local GAP = 6
local PAD = 6
local REFRESH_SECONDS = 0.5
local PREVIEW_SECONDS = 20

local COLORS = {
    active = { 0.35, 0.35, 0.35 },
    low = { 1, 0.82, 0 },
    missing = { 0.9, 0.2, 0.2 },
    unknown = { 0.6, 0.6, 0.6 },
    unset = { 0.45, 0.45, 0.45 },
}

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local frame
local slots = {}
local shownUntil -- time at which a ready check or preview row hides by itself
local sawReadyCheckFrame -- true once Blizzard's ready check dialog has been seen on screen
local elapsed = 0

-- 36s under a minute, then whole minutes: 230m.
local function formatTime(seconds)
    if seconds < 60 then
        return format("%ds", math.max(0, math.floor(seconds + 0.5)))
    end
    return format("%dm", math.floor(seconds / 60 + 0.5))
end

local function createSlot(parent, index)
    local slot = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    slot:SetSize(ICON_SIZE, ICON_SIZE)
    slot:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + (index - 1) * (ICON_SIZE + GAP), -PAD)
    slot:SetBackdrop(BACKDROP)
    slot:SetBackdropColor(0, 0, 0, 0.6)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    slot.time = slot:CreateFontString(nil, "OVERLAY", "CRTFontHighlight")
    slot.time:SetPoint("BOTTOM", 0, 3)

    slot.count = slot:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    slot.count:SetPoint("TOPRIGHT", -3, -3)

    slot.tag = slot:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    slot.tag:SetPoint("TOPLEFT", 3, -3)
    slot.tag:SetTextColor(0.3, 0.9, 1)
    return slot
end

local function build()
    if frame then
        return frame
    end
    local count = #Consumables.CATEGORIES
    frame = CreateFrame("Frame", "CowfeeRaidToolsReadyCheckRow", UIParent, "BackdropTemplate")
    frame:SetSize(PAD * 2 + count * ICON_SIZE + (count - 1) * GAP, PAD * 2 + ICON_SIZE)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.45)
    frame:SetBackdropBorderColor(0.2, 0.8, 0.9, 1)
    frame:Hide()

    for index in ipairs(Consumables.CATEGORIES) do
        slots[index] = createSlot(frame, index)
    end

    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < REFRESH_SECONDS then
            return
        end
        elapsed = 0
        Display:Refresh()
    end)
    return frame
end

local function place()
    local rc = _G.ReadyCheckFrame
    frame:ClearAllPoints()
    if rc and rc.IsShown and rc:IsShown() then
        frame:SetPoint("BOTTOM", rc, "TOP", 0, 18)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end
end

function Display:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    -- Hide when the check has timed out, or when Blizzard's dialog was shown and has gone,
    -- which means you answered it.
    local rc = _G.ReadyCheckFrame
    if rc and rc.IsShown then
        if rc:IsShown() then
            sawReadyCheckFrame = true
        elseif sawReadyCheckFrame and not self.preview then
            return self:Hide()
        end
    end
    if shownUntil and GetTime() >= shownUntil then
        return self:Hide()
    end
    place()

    for index, def in ipairs(Consumables.CATEGORIES) do
        local slot = slots[index]
        local status = Consumables:Status(def.key)
        local color = COLORS[status.state] or COLORS.unknown

        slot:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        slot.icon:SetTexture(status.icon or Consumables.QUESTION_MARK)
        local dim = status.state == "missing" or status.state == "unset" or status.state == "unknown"
        slot.icon:SetDesaturated(dim)
        slot.icon:SetAlpha(dim and 0.6 or 1)

        if status.state == "unknown" then
            slot.time:SetText("?")
        elseif status.state == "unset" then
            slot.time:SetText("set up")
        elseif status.left then
            slot.time:SetText(formatTime(status.left))
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
end

function Display:Hide()
    if frame then
        frame:Hide()
    end
    shownUntil = nil
    self.preview = false
end

local function show(seconds, preview)
    if not Consumables:Enabled() and not preview then
        return
    end
    build()
    Display.preview = preview
    sawReadyCheckFrame = false
    shownUntil = GetTime() + seconds
    place()
    frame:Show()
    elapsed = REFRESH_SECONDS
    Display:Refresh()
end

-- Shows the row for a few seconds without a real ready check, for testing.
function Display:Preview()
    show(PREVIEW_SECONDS, true)
    CRT:Print("Showing the consumables row for " .. PREVIEW_SECONDS .. " seconds.")
end

local events = CreateFrame("Frame")
events:RegisterEvent("READY_CHECK")
events:RegisterEvent("READY_CHECK_FINISHED")
events:SetScript("OnEvent", function(_, event, _, timeLeft)
    if event == "READY_CHECK" then
        local seconds = type(timeLeft) == "number" and timeLeft or 30
        show(seconds + 1, false)
        -- Blizzard's dialog may not be on screen yet when this event arrives, so place it again shortly.
        C_Timer.After(0.3, function()
            if frame and frame:IsShown() then
                place()
            end
        end)
    else
        Display:Hide()
    end
end)
