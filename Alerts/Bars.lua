local ADDON, CRT = ...

-- The alert bars: a list of what is coming up, soonest first, each bar with its icon, text, seconds left and
-- a fill that empties as the time nears. It shows your note lines and your reminders (every line whose
-- outputs.bar is on) from the alerts engine. Built on Alerts/Areas.lua; the settings stay in
-- CRT.db.alerts.bars (shown, cap, ahead, width, height, grow, noteLines) and open from the area's gear.
-- A bar starts full: its fill runs over the time left when it first showed, at most `ahead`.

local Areas = CRT.AlertAreas
local Alerts = CRT.Alerts
local Rules = CRT.AlertRules
local Notes = CRT.Notes

local TEXT = {
    title = "Alert bars",
    ahead = "Show bars from",
    width = "Width",
    height = "Height",
    more = "+%d more",
    sampleThree = "Sample bar 3",
    sampleTwo = "Sample bar 2",
    testBar = "Test bar %d",
}

local ICON_GAP = 4 -- between the icon and the text, and at the edges
local MORE_GAP = 2
local DEFAULT_COLOR = { 0.44, 0.31, 0.22 }
-- The first bar's centre. The old window was centred here, three sample bars tall, so this is its top.
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 142 }
local SAMPLE_SPELL = 31884
local SAMPLE_TIMES = { 8, 14, 19 }
local SAMPLE_GAP = 1      -- seconds between preview ticks that mean it was turned off
local TEST_SECONDS = 12
local TEST_STEP = 4       -- seconds between the three test bars
local OLD_GAP = 2         -- between bars in the old window
local OLD_PREVIEW_BARS = 3 -- the old window could only be dragged showing its three samples
local POSITION_VERSION = 2

local Bars
local moreText

local function readable(v)
    return CRT.Timeline.readable(v)
end

local function number(v, default)
    return type(v) == "number" and v or default
end

-- The saved position of the old window was its centre, with three sample bars showing. The area saves
-- the first bar's centre, which is (h + OLD_GAP) higher than the old centre when the top is the same; so
-- that is moved once, marked by positionV, and a position saved later is left alone.
local function settings()
    local alerts = Alerts:Settings()
    if not alerts then
        return {}
    end
    alerts.bars = alerts.bars or {}
    local s = alerts.bars
    if s.positionV ~= POSITION_VERSION then
        s.positionV = POSITION_VERSION
        local p = s.position
        if type(p) == "table" and type(p.y) == "number" then
            local h = math.max(8, number(s.height, 20))
            local old = OLD_PREVIEW_BARS * (h + OLD_GAP) - OLD_GAP
            p.y = p.y + old / 2 - h / 2
        end
    end
    return s
end

local function aheadOf(s)
    local ahead = number(s.ahead, 20)
    return ahead > 0 and ahead or 20
end

local function timeText(remaining)
    if remaining < 10 then
        return format("%.1f", math.max(0, remaining))
    end
    return format("%d", math.floor(remaining))
end

-- What one bar shows. The fill is over the time left when the line first showed, at most `ahead`.
local function row(line, now, ahead, shownAt)
    local total = math.min(ahead, line.at - (shownAt or now))
    local fraction = total > 0 and (line.at - now) / total or 0
    return {
        text = Areas.LineText(line),
        time = timeText(line.at - now),
        icon = Areas.LineIcon(line),
        color = Areas.LineColor(line) or DEFAULT_COLOR,
        fraction = math.max(0, math.min(1, fraction)),
    }
end

local function make(parent)
    local bar = CreateFrame("Frame", nil, parent)
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

local function draw(bar, line, now, s, shownAt)
    local width = math.max(60, number(s.width, 240))
    local height = math.max(8, number(s.height, 20))
    local r = row(line, now, aheadOf(s), shownAt)
    bar.row = r
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
end

-- The lines the bars show: those due within `ahead`, soonest first, and how many the cap left out.
local function lines(now, s, cap)
    return Rules.Bars(Alerts:Lines(now), now, aheadOf(s), cap)
end

-- "+N more" under the last bar (above it when they grow up, under the first when they grow sideways).
local function after(area, n, more)
    if not moreText then
        moreText = area.frame:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        moreText:SetJustifyH("LEFT")
        moreText:SetShadowOffset(1, -1)
    end
    if n == 0 or more <= 0 then
        moreText:Hide()
        return
    end
    local grow = Bars:Settings().grow
    moreText:ClearAllPoints()
    if grow == "up" then
        moreText:SetPoint("BOTTOMLEFT", area.pool[n], "TOPLEFT", ICON_GAP, MORE_GAP)
    elseif grow == "left" or grow == "right" then
        moreText:SetPoint("TOPLEFT", area.pool[1], "BOTTOMLEFT", ICON_GAP, -MORE_GAP)
    else
        moreText:SetPoint("TOPLEFT", area.pool[n], "BOTTOMLEFT", ICON_GAP, -MORE_GAP)
    end
    moreText:SetText(format(TEXT.more, more))
    moreText:Show()
end

-- The samples keep one base time while the preview runs (a gap between calls means it was turned off and
-- on), so the bars run down instead of restarting every tick; they start over, full, once all have passed.
local sampleBase, sampleLast
local sampleCycle = 0 -- ids change each cycle, so every bar starts full again
local function sample(now)
    if not sampleBase or now - sampleLast > SAMPLE_GAP or now > sampleBase + SAMPLE_TIMES[#SAMPLE_TIMES] then
        sampleBase = now
        sampleCycle = sampleCycle + 1
    end
    sampleLast = now
    local info = Notes:SpellInfo(SAMPLE_SPELL)
    local out = {}
    for i, remaining in ipairs(SAMPLE_TIMES) do
        out[i] = {
            id = "sample" .. i .. "#" .. sampleCycle,
            text = i == 1 and info and info.name or ("Sample bar " .. i),
            icon = i == 1 and info and info.icon or nil,
            at = sampleBase + remaining,
        }
    end
    return out
end

local function dialogRows(dialog, s)
    local function on()
        return s.shown and true or false
    end
    dialog:Slider(TEXT.ahead, {
        min = 5,
        max = 60,
        get = function()
            return aheadOf(s)
        end,
        set = function(value)
            s.ahead = value
        end,
        enabledIf = on,
    })
    dialog:Slider(TEXT.width, {
        min = 120,
        max = 400,
        step = 10,
        get = function()
            return number(s.width, 240)
        end,
        set = function(value)
            s.width = value
        end,
        enabledIf = on,
    })
    dialog:Slider(TEXT.height, {
        min = 12,
        max = 40,
        get = function()
            return number(s.height, 20)
        end,
        set = function(value)
            s.height = value
        end,
        enabledIf = on,
    })
end

Bars = Areas.New({
    key = "bars",
    output = "bar",
    layer = "alertbars",
    title = TEXT.title,
    settingsKey = "bars",
    store = settings,
    defaultPosition = DEFAULT_POSITION,
    make = make,
    draw = draw,
    lines = lines,
    after = after,
    sample = sample,
    settings = dialogRows,
})
CRT.AlertBars = Bars

-- For the tests: one table per bar on screen (text, time, icon, color, fraction), and the count left out.
local widgets = Bars.Visible
function Bars:Visible()
    local out = {}
    for i, w in ipairs(widgets(self)) do
        out[i] = w.row
    end
    return out
end

function Bars:More()
    return self.more
end

-- Three bars counting down from `seconds`, without a run; the Test bars button's use.
local baseTest = Bars.Test
local testCount = 0
function Bars:Test(seconds)
    seconds = number(seconds, TEST_SECONDS)
    if seconds <= 0 then
        seconds = TEST_SECONDS
    end
    testCount = testCount + 1
    local now = GetTime()
    local list = {}
    for i = 1, 3 do
        list[i] = { id = "test" .. i .. "#" .. testCount, text = format(TEXT.testBar, i), at = now + seconds + (i - 1) * TEST_STEP }
    end
    baseTest(self, list)
end
