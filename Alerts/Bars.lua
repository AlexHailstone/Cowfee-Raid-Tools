local ADDON, CRT = ...

-- The alert bars: a movable window listing what is coming up, soonest first, each line with its icon,
-- text, seconds left and a fill that empties as the time nears. It shows your note lines and your
-- reminders (every line whose outputs.bar is on) from the alerts engine. Settings are in
-- CRT.db.alerts.bars; see the Settings tab of the Raid Notes page.

local Notes = CRT.Notes
local Alerts = CRT.Alerts
local Rules = CRT.AlertRules
local Bars = {}
CRT.AlertBars = Bars

local REFRESH_SECONDS = 0.1
local MAX_BARS = 10
local BAR_GAP = 2
local ICON_GAP = 4 -- between the icon and the text, and at the edges
local TIME_WIDTH = 36
local MORE_HEIGHT = 14
local DEFAULT_COLOR = { 0.44, 0.31, 0.22 }
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 }
local SAMPLE_SPELL = 31884
local TEST_SECONDS = 12
local TEST_STEP = 4 -- seconds between the three test bars

local frame, handle, moreText
local build
local pool = {}
local previewOn = false
local testAt -- the three times of the test bars, or nil
local elapsed = 0
local drawn, drawnMore = {}, 0

local function readable(v)
    return CRT.Timeline.readable(v)
end

local function settings()
    return (Alerts:Settings() or {}).bars or {}
end

local function number(v, default)
    return type(v) == "number" and v or default
end

-- The line's text, else its spell's name, else nothing. Values the game hides never reach a string call.
local function lineText(line)
    local t = line.text
    if readable(t) and type(t) == "string" and t ~= "" then
        return t
    end
    local id = line.spellID
    if readable(id) and type(id) == "number" then
        local info = Notes:SpellInfo(id)
        if info and readable(info.name) and type(info.name) == "string" then
            return info.name
        end
    end
    return ""
end

local function lineIcon(line)
    local icon = line.icon
    if readable(icon) and (type(icon) == "number" or type(icon) == "string") then
        return icon
    end
    local id = line.spellID
    if readable(id) and type(id) == "number" then
        local info = Notes:SpellInfo(id)
        if info and readable(info.icon) and (type(info.icon) == "number" or type(info.icon) == "string") then
            return info.icon
        end
    end
    return nil
end

local function lineColor(line)
    local c = line.color
    if readable(c) and type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return DEFAULT_COLOR
end

local function timeText(remaining)
    if remaining < 10 then
        return format("%.1f", math.max(0, remaining))
    end
    return format("%d", math.floor(remaining))
end

local function row(line, now, ahead)
    local fraction = (line.at - now) / ahead
    return {
        text = lineText(line),
        time = timeText(line.at - now),
        icon = lineIcon(line),
        color = lineColor(line),
        fraction = math.max(0, math.min(1, fraction)),
    }
end

-- The bars -------------------------------------------------------------------------------

local function makeBar()
    local bar = CreateFrame("Frame", nil, frame)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.55)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.time = bar:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    bar.time:SetPoint("RIGHT", -ICON_GAP, 0)
    bar.time:SetJustifyH("RIGHT")
    bar.time:SetShadowOffset(1, -1)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    bar.text:SetJustifyH("LEFT")
    bar.text:SetWordWrap(false)
    bar.text:SetShadowOffset(1, -1)
    return bar
end

local function drawBar(bar, index, r, width, height)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * (height + BAR_GAP))
    bar:SetSize(width, height)

    local left = 0
    bar.icon:SetShown(r.icon ~= nil)
    if r.icon ~= nil then
        bar.icon:ClearAllPoints()
        bar.icon:SetPoint("LEFT")
        bar.icon:SetSize(height, height)
        bar.icon:SetTexture(r.icon)
        left = height
    end

    local fillWidth = (width - left) * r.fraction
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("LEFT", left, 0)
    bar.fill:SetSize(math.max(fillWidth, 1), height)
    bar.fill:SetColorTexture(r.color[1], r.color[2], r.color[3], 0.9)
    bar.fill:SetShown(fillWidth > 0)

    bar.time:SetText(r.time)
    bar.text:ClearAllPoints()
    bar.text:SetPoint("LEFT", left + ICON_GAP, 0)
    bar.text:SetPoint("RIGHT", bar.time, "LEFT", -ICON_GAP, 0)
    bar.text:SetText(r.text)
    bar:Show()
end

local function draw(rows, more)
    drawn, drawnMore = rows, more
    if #rows == 0 then
        frame:Hide()
        return
    end
    local s = settings()
    local width = math.max(60, number(s.width, 240))
    local height = math.max(8, number(s.height, 20))
    for i, r in ipairs(rows) do
        pool[i] = pool[i] or makeBar()
        drawBar(pool[i], i, r, width, height)
    end
    for i = #rows + 1, #pool do
        pool[i]:Hide()
    end
    local total = #rows * (height + BAR_GAP) - BAR_GAP
    if more > 0 then
        moreText:ClearAllPoints()
        moreText:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_GAP, -(total + BAR_GAP))
        moreText:SetText("+" .. more .. " more")
        moreText:Show()
        total = total + BAR_GAP + MORE_HEIGHT
    else
        moreText:Hide()
    end
    frame:SetSize(width, total)
    frame:Show()
end

local function sampleRows(ahead)
    local info = Notes:SpellInfo(SAMPLE_SPELL)
    local out = {}
    for i, remaining in ipairs({ 8, 14, 19 }) do
        out[i] = {
            text = i == 1 and info and info.name or ("Sample bar " .. i),
            time = timeText(remaining),
            icon = i == 1 and info and info.icon or nil,
            color = DEFAULT_COLOR,
            fraction = math.max(0, math.min(1, remaining / ahead)),
        }
    end
    return out
end

local function testRows(now, ahead)
    local out = {}
    for _, at in ipairs(testAt) do
        if at > now then
            out[#out + 1] = row({ at = at, text = "Test bar " .. (#out + 1) }, now, ahead)
        end
    end
    return out
end

function Bars:Refresh()
    if not frame then
        return
    end
    handle:SetShown(previewOn)
    local now = GetTime()
    local s = settings()
    local ahead = number(s.ahead, 20)
    if ahead <= 0 then
        ahead = 20
    end

    if previewOn then
        draw(sampleRows(ahead), 0)
        return
    end
    if testAt then
        local rows = testRows(now, ahead)
        if #rows > 0 then
            draw(rows, 0)
            return
        end
        testAt = nil
    end

    -- Nothing shows while the bars are off, whichever block the lines come from.
    if not (s.shown and Alerts.running) then
        draw({}, 0)
        return
    end
    local cap = math.max(1, math.min(MAX_BARS, number(s.cap, 5)))
    local list, left = Rules.Bars(Alerts:Lines(now), now, ahead, cap)
    local rows = {}
    for i, line in ipairs(list) do
        rows[i] = row(line, now, ahead)
    end
    draw(rows, left)
end

-- What is on screen, for the tests: one table per bar, and the count left out.
function Bars:Visible()
    return drawn
end

function Bars:More()
    return drawnMore
end

-- Three sample bars counting down from `seconds`, without a run; the Settings tab's Test bars button.
function Bars:Test(seconds)
    seconds = number(seconds, TEST_SECONDS)
    if seconds <= 0 then
        seconds = TEST_SECONDS
    end
    build()
    local now = GetTime()
    testAt = { now + seconds, now + seconds + TEST_STEP, now + seconds + 2 * TEST_STEP }
    Bars:Refresh()
end

-- The window -----------------------------------------------------------------------------

local function applyPosition()
    local p = settings().position or DEFAULT_POSITION
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
end

function Bars:ResetPosition()
    local s = Alerts:Settings()
    if s and s.bars then
        s.bars.position = nil
    end
    if frame then
        applyPosition()
    end
end

function build()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "CowfeeRaidToolsAlertBars", UIParent)
    frame:SetSize(240, 20)
    CRT.UI:RegisterLayer("alertbars", frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)

    moreText = frame:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    moreText:SetJustifyH("LEFT")
    moreText:SetShadowOffset(1, -1)
    moreText:Hide()

    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    handle:SetBackdropColor(0.3, 0.25, 0.05, 0.9)
    handle:SetBackdropBorderColor(1, 0.82, 0, 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("CENTER")
    text:SetText("Alert bars: drag to move")
    CRT.UI.ResetButton(handle, function()
        Bars:ResetPosition()
    end):SetPoint("RIGHT", -2, 0)
    handle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    -- Saved by its center, so the window grows evenly around where you put it.
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local s = Alerts:Settings()
        s.bars = s.bars or {}
        s.bars.position = { point = "CENTER", relativePoint = "CENTER", x = x - ux, y = y - uy }
        applyPosition()
    end)
    handle:Hide()

    applyPosition()
    frame:Hide()
end

-- The window hides itself when there is nothing to show, so this frame keeps it updated.
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < REFRESH_SECONDS then
        return
    end
    elapsed = 0
    if frame then
        Bars:Refresh()
    end
end)
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function()
    build()
end)

CRT.UI:RegisterPreview("alertbars", function(on)
    build()
    previewOn = on and true or false
    Bars:Refresh()
end)
