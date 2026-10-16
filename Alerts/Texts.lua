local ADDON, CRT = ...

-- The texts area: big text such as "Stack on X (5.0)" for every line whose outputs.text is on, the
-- seconds after it and "NOW" from 0 while it lingers. Built on Alerts/Areas.lua; its settings are
-- CRT.db.alerts.areas.texts (font, fontSize, outline, align, beside the common shown, cap and grow).

local Areas = CRT.AlertAreas

local TEXT = {
    title = "Alert texts",
    now = "NOW",
    font = "Font",
    size = "Size",
    outline = "Outline",
    none = "None",
    thin = "Outline",
    thick = "Thick",
    align = "Align",
    left = "Left",
    center = "Center",
    right = "Right",
    sampleNow = "Spread",
    sampleSoon = "Stack on the boss",
    sampleLater = "Soak",
}

local PAD = 8          -- around the letters, so the glow sits just outside them
local NOW_BELOW = 0.1  -- under this many seconds left reads NOW: tenths are cut, so it would read "0.0"
local MIN_SIZE, MAX_SIZE, DEFAULT_SIZE = 12, 72, 36
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 400, y = 300 }
local WHITE = { 1, 1, 1 }
local ALIGNS = { LEFT = true, CENTER = true, RIGHT = true }

local OUTLINE_OPTIONS = {
    { key = "", label = TEXT.none },
    { key = "OUTLINE", label = TEXT.thin },
    { key = "THICKOUTLINE", label = TEXT.thick },
}
local ALIGN_OPTIONS = {
    { key = "LEFT", label = TEXT.left },
    { key = "CENTER", label = TEXT.center },
    { key = "RIGHT", label = TEXT.right },
}

-- Tenths under 10 (cut, not rounded, so 9.96 never reads 10.0), whole seconds from 10, and NOW once
-- under a tenth is left, through 0 and while the line lingers.
local function seconds(remaining)
    if remaining < NOW_BELOW then
        return TEXT.now
    elseif remaining < 10 then
        return format("%.1f", math.floor(remaining * 10 + 1e-6) / 10)
    end
    return tostring(math.floor(remaining))
end

local function fontSize(s)
    local size = type(s.fontSize) == "number" and s.fontSize or DEFAULT_SIZE
    return math.max(MIN_SIZE, math.min(MAX_SIZE, size))
end

local function make(parent)
    local w = CreateFrame("Frame", nil, parent)
    -- Anchored by one point (set in draw), not to the widget's edges, so its width is never bounded by
    -- the widget's last size.
    w.text = w:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    w.text:SetWordWrap(false)
    w.text:SetShadowOffset(1, -1)
    return w
end

local function align(s)
    return ALIGNS[s.align] and s.align or "CENTER"
end

-- Where the text sits in its widget, for each alignment: the point and its x offset.
local TEXT_POINT = { LEFT = { "LEFT", PAD / 2 }, CENTER = { "CENTER", 0 }, RIGHT = { "RIGHT", -PAD / 2 } }

-- The words' full width. GetStringWidth is bounded by the region's size, GetUnboundedStringWidth is not.
local function textWidth(fs)
    if fs.GetUnboundedStringWidth then
        return fs:GetUnboundedStringWidth()
    end
    return fs:GetStringWidth()
end

-- Each text is as wide as its words, so nothing is cut off; the area lines them up by `align`.
-- The texts area has no use for when a line first showed (Areas' shownAt).
local function draw(w, line, now, s)
    local size, edge = fontSize(s), align(s)
    Areas.SetFont(w.text, s.font, size, s.outline)
    if w.edge ~= edge then
        w.edge = edge
        local p = TEXT_POINT[edge]
        w.text:ClearAllPoints()
        w.text:SetPoint(p[1], w, p[1], p[2], 0)
        w.text:SetJustifyH(edge)
    end
    local text, time = Areas.LineText(line), seconds(line.at - now)
    w.text:SetText(text ~= "" and (text .. " (" .. time .. ")") or time)
    w:SetSize(math.ceil(textWidth(w.text)) + PAD, size + PAD)
    local c = Areas.LineColor(line) or WHITE
    w.text:SetTextColor(c[1], c[2], c[3])
end

local function sample(now)
    return {
        { text = TEXT.sampleNow, at = now, glow = true },
        { text = TEXT.sampleSoon, at = now + 5 },
        { text = TEXT.sampleLater, at = now + 12 },
    }
end

local function settings(panel, s)
    panel:Dropdown(TEXT.font, {
        -- Read each time the menu opens, so fonts another addon shares later appear.
        options = function()
            local out = {}
            for _, font in ipairs(CRT:FontList()) do
                out[#out + 1] = { key = font.name, label = font.name }
            end
            return out
        end,
        get = function()
            return s.font
        end,
        set = function(name)
            s.font = name
        end,
    })
    panel:Slider(TEXT.size, {
        min = MIN_SIZE,
        max = MAX_SIZE,
        get = function()
            return fontSize(s)
        end,
        set = function(value)
            s.fontSize = value
        end,
    })
    panel:Dropdown(TEXT.outline, {
        options = OUTLINE_OPTIONS,
        get = function()
            return s.outline or ""
        end,
        set = function(key)
            s.outline = key
        end,
    })
    panel:Dropdown(TEXT.align, {
        options = ALIGN_OPTIONS,
        get = function()
            return align(s)
        end,
        set = function(key)
            s.align = key
        end,
    })
end

CRT.AlertTexts = Areas.New({
    key = "texts",
    output = "text",
    layer = "alerttexts",
    title = TEXT.title,
    settingsKey = "texts",
    defaultPosition = DEFAULT_POSITION,
    make = make,
    draw = draw,
    sample = sample,
    settings = settings,
    align = align,
})
