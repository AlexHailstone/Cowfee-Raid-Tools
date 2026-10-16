local ADDON, CRT = ...

-- The circles area: a ring that empties as the time runs out, the seconds inside it and the alert's text
-- under it. Built on Alerts/Areas.lua; its settings are CRT.db.alerts.areas.circles (size, thickness,
-- ringColor, fontSize, font, outline, beside the common shown, cap, grow). The ring is a Cooldown whose swipe
-- is a ring texture from Media/ (Thin, Medium or Thick, a see-through centre), so its coloured part shrinks as
-- the time runs out (REVERSE below) over a faint full ring of the same texture. The centre is left clear.

local Areas = CRT.AlertAreas

local TEXT = {
    title = "Alert circles",
    now = "NOW",
    size = "Size",
    font = "Font",
    textSize = "Text size",
    outline = "Outline",
    none = "None",
    thin = "Outline",
    thick = "Thick",
    thickness = "Ring thickness",
    ringThin = "Thin",
    ringMedium = "Medium",
    ringThick = "Thick",
    ringColor = "Ring colour",
    sampleNow = "Spread",
    sampleSoon = "Stack on the boss",
    sampleLater = "Soak",
}

-- Tune the look in game here.
-- The swipe and the faint ring: 256 px white rings, outer radius 126 px, 12 / 22 / 36 px wide (make_rings.js).
local MEDIA = "Interface\\AddOns\\CowfeeRaidTools\\Media\\"
local RING_TEXTURES = {
    thin = MEDIA .. "RingThin",
    medium = MEDIA .. "RingMedium",
    thick = MEDIA .. "RingThick",
}
local DEFAULT_THICKNESS = "medium"
local DEFAULT_RING_COLOR = { 1, 1, 1, 0.9 }
local TRACK_ALPHA = 0.2      -- the faint full ring behind the swipe, of the ring colour's alpha
-- A default cooldown shrinks its swiped part as time runs out, which is the emptying ring; reversed it
-- grows. Flip this if the ring fills instead of empties in game.
local REVERSE = false
local DEFAULT_FONT_NAME = "Friz Quadrata" -- until a font is chosen

local NOW_BELOW = 0.1        -- under this many seconds left reads NOW
local MIN_SIZE, MAX_SIZE, DEFAULT_SIZE = 32, 160, 64
local MIN_FONT, MAX_FONT, DEFAULT_FONT = 10, 32, 16
local MIN_SECONDS_FONT = 8
local TEXT_GAP = 2           -- between the ring and its text
-- Over the player's character, a little below the middle of the screen.
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -40 }
local WHITE = { 1, 1, 1 }
local SAMPLE_GAP = 1         -- seconds between preview ticks that mean it was turned off
local SAMPLE_SPAN = 14       -- the preview starts over this long after it began

local OUTLINE_OPTIONS = {
    { key = "", label = TEXT.none },
    { key = "OUTLINE", label = TEXT.thin },
    { key = "THICKOUTLINE", label = TEXT.thick },
}

local THICKNESS_OPTIONS = {
    { key = "thin", label = TEXT.ringThin },
    { key = "medium", label = TEXT.ringMedium },
    { key = "thick", label = TEXT.ringThick },
}

local function clamp(v, min, max, default)
    v = type(v) == "number" and v or default
    return math.max(min, math.min(max, v))
end

local function ringSize(s)
    return clamp(s.size, MIN_SIZE, MAX_SIZE, DEFAULT_SIZE)
end

local function ringTexture(s)
    return RING_TEXTURES[s.thickness] or RING_TEXTURES[DEFAULT_THICKNESS]
end

local function ringColor(s)
    local c = s.ringColor
    if type(c) ~= "table" then
        return DEFAULT_RING_COLOR
    end
    local out = {}
    for i = 1, 4 do
        out[i] = clamp(c[i], 0, 1, DEFAULT_RING_COLOR[i])
    end
    return out
end

local function fontSize(s)
    return clamp(s.fontSize, MIN_FONT, MAX_FONT, DEFAULT_FONT)
end

-- Whole seconds, rounded up, and NOW once under a tenth is left.
local function seconds(remaining)
    if remaining < NOW_BELOW then
        return TEXT.now
    end
    return tostring(math.ceil(remaining))
end

-- The words' full width. GetStringWidth is bounded by the region's size, GetUnboundedStringWidth is not.
local function textWidth(fs)
    if fs.GetUnboundedStringWidth then
        return fs:GetUnboundedStringWidth()
    end
    return fs:GetStringWidth()
end

local function make(parent)
    local w = CreateFrame("Frame", nil, parent)
    -- The ring's frame, centered at the top of the widget, which is as wide as the text if that is wider.
    w.ring = CreateFrame("Frame", nil, w)
    w.ring:SetPoint("TOP", w, "TOP", 0, 0)
    w.track = w.ring:CreateTexture(nil, "BACKGROUND")
    w.track:SetAllPoints(w.ring)
    w.cooldown = CreateFrame("Cooldown", nil, w.ring, "CooldownFrameTemplate")
    w.cooldown:SetAllPoints(w.ring)
    if w.cooldown.SetHideCountdownNumbers then
        w.cooldown:SetHideCountdownNumbers(true) -- the seconds are drawn here
    end
    if w.cooldown.SetDrawEdge then
        w.cooldown:SetDrawEdge(false)
    end
    if w.cooldown.SetDrawBling then
        w.cooldown:SetDrawBling(false) -- no finish flash over NOW and the glow
    end
    if w.cooldown.SetReverse then
        w.cooldown:SetReverse(REVERSE)
    end
    w.cooldown.noCooldownCount = true -- other addons paint no numbers over ours
    -- The seconds sit on a frame above the swipe.
    w.over = CreateFrame("Frame", nil, w.ring)
    w.over:SetAllPoints(w.ring)
    w.over:SetFrameLevel((w.cooldown:GetFrameLevel() or 1) + 2)
    w.seconds = w.over:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    w.seconds:SetPoint("CENTER", w.over, "CENTER", 0, 0)
    w.seconds:SetShadowOffset(1, -1)
    -- Anchored by one point, not to the widget's edges, so its width is never bounded by the widget.
    w.text = w:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    w.text:SetWordWrap(false)
    w.text:SetShadowOffset(1, -1)
    w.text:SetJustifyH("CENTER")
    w.text:SetPoint("TOP", w.ring, "BOTTOM", 0, -TEXT_GAP)
    return w
end

-- The ring starts full: it runs over the time left when the line first showed, at most `warn`. It is set
-- only when the line or its time changes, since widgets are pooled by position and lines move up.
local function setSwipe(w, line, total)
    local key = tostring(line.id) .. "|" .. tostring(line.at)
    if w.swipeKey == key then
        return
    end
    w.swipeKey = key
    local cd = w.cooldown
    if total > 0 and cd.SetCooldown then
        cd:SetCooldown(line.at - total, total)
    elseif cd.Clear then
        cd:Clear()
    end
end

local function draw(w, line, now, s, shownAt)
    local size, textSize = ringSize(s), fontSize(s)
    local at = line.at
    local c = Areas.LineColor(line) or WHITE
    w.ring:SetSize(size, size)
    local texture, ring = ringTexture(s), ringColor(s)
    if w.ringTexture ~= texture then
        w.ringTexture = texture
        w.track:SetTexture(texture)
        if w.cooldown.SetSwipeTexture then
            w.cooldown:SetSwipeTexture(texture)
        end
    end
    w.track:SetVertexColor(ring[1], ring[2], ring[3], ring[4] * TRACK_ALPHA)
    if w.cooldown.SetSwipeColor then
        w.cooldown:SetSwipeColor(ring[1], ring[2], ring[3], ring[4])
    end
    local total = at - (shownAt or now)
    if type(line.warn) == "number" then
        total = math.min(line.warn, total)
    end
    setSwipe(w, line, total)
    Areas.SetFont(w.seconds, s.font or DEFAULT_FONT_NAME, math.max(MIN_SECONDS_FONT, math.floor(size / 3)), s.outline)
    w.seconds:SetText(seconds(at - now))
    Areas.SetFont(w.text, s.font or DEFAULT_FONT_NAME, textSize, s.outline)
    w.text:SetText(Areas.LineText(line))
    w.text:SetTextColor(c[1], c[2], c[3])
    local words = math.ceil(textWidth(w.text))
    w:SetSize(math.max(size, words), size + TEXT_GAP + textSize + 2)
end

-- The samples keep one base time while the preview runs (a gap between calls means it was turned off
-- and on), so their rings run instead of restarting every tick; they start over once all have passed.
local sampleBase, sampleLast
local sampleCycle = 0 -- ids change each cycle, so every ring starts full again
local function sample(now)
    if not sampleBase or now - sampleLast > SAMPLE_GAP or now > sampleBase + SAMPLE_SPAN then
        sampleBase = now
        sampleCycle = sampleCycle + 1
    end
    sampleLast = now
    return {
        { id = "sample1#" .. sampleCycle, text = TEXT.sampleNow, at = sampleBase, warn = 8, glow = true },
        { id = "sample2#" .. sampleCycle, text = TEXT.sampleSoon, at = sampleBase + 5, warn = 8 },
        { id = "sample3#" .. sampleCycle, text = TEXT.sampleLater, at = sampleBase + 12, warn = 12 },
    }
end

local function settings(panel, s)
    panel:Slider(TEXT.size, {
        min = MIN_SIZE,
        max = MAX_SIZE,
        get = function()
            return ringSize(s)
        end,
        set = function(value)
            s.size = value
        end,
    })
    panel:Dropdown(TEXT.thickness, {
        options = THICKNESS_OPTIONS,
        get = function()
            return RING_TEXTURES[s.thickness] and s.thickness or DEFAULT_THICKNESS
        end,
        set = function(key)
            s.thickness = key
        end,
    })
    panel:Color(TEXT.ringColor, function()
        return ringColor(s)
    end, function(c)
        s.ringColor = c
    end)
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
            return s.font or DEFAULT_FONT_NAME
        end,
        set = function(name)
            s.font = name
        end,
    })
    panel:Slider(TEXT.textSize, {
        min = MIN_FONT,
        max = MAX_FONT,
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
end

CRT.AlertCircles = Areas.New({
    key = "circles",
    output = "circle",
    layer = "alertcircles",
    title = TEXT.title,
    settingsKey = "circles",
    defaultPosition = DEFAULT_POSITION,
    make = make,
    draw = draw,
    sample = sample,
    settings = settings,
})
