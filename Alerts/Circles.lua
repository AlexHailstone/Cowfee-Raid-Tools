local ADDON, CRT = ...

-- The circles area: a ring that empties as the time runs out, the seconds inside it and the alert's text
-- under it. Built on Alerts/Areas.lua; its settings are CRT.db.alerts.areas.circles (size, fontSize, font,
-- outline, beside the common shown, cap, grow). The ring is a Cooldown with a round swipe, reversed so
-- the coloured part empties, over a faint full ring, under a dark disc that makes it read as a ring.

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
    sampleNow = "Spread",
    sampleSoon = "Stack on the boss",
    sampleLater = "Soak",
}

-- Tune the look in game here.
local RING_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- the swipe, the faint ring and the disc
local RING_ALPHA = 0.9       -- the coloured swipe
local TRACK_ALPHA = 0.2      -- the faint full ring behind it
local DISC_ALPHA = 0.6       -- the dark disc inside
local DISC_INSET = 0.18      -- of the size, on each side

local NOW_BELOW = 0.1        -- under this many seconds left reads NOW
local MIN_SIZE, MAX_SIZE, DEFAULT_SIZE = 32, 160, 64
local MIN_FONT, MAX_FONT, DEFAULT_FONT = 10, 32, 16
local MIN_SECONDS_FONT = 8
local TEXT_GAP = 2           -- between the ring and its text
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 100 }
local WHITE = { 1, 1, 1 }
local SAMPLE_GAP = 1         -- seconds between preview ticks that mean it was turned off
local SAMPLE_SPAN = 14       -- the preview starts over this long after it began

local OUTLINE_OPTIONS = {
    { key = "", label = TEXT.none },
    { key = "OUTLINE", label = TEXT.thin },
    { key = "THICKOUTLINE", label = TEXT.thick },
}

local function clamp(v, min, max, default)
    v = type(v) == "number" and v or default
    return math.max(min, math.min(max, v))
end

local function ringSize(s)
    return clamp(s.size, MIN_SIZE, MAX_SIZE, DEFAULT_SIZE)
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
    w.track:SetTexture(RING_TEXTURE)
    w.track:SetVertexColor(1, 1, 1, TRACK_ALPHA)
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
    if w.cooldown.SetSwipeTexture then
        w.cooldown:SetSwipeTexture(RING_TEXTURE)
    end
    if w.cooldown.SetReverse then
        w.cooldown:SetReverse(true) -- the coloured part empties
    end
    w.cooldown.noCooldownCount = true -- other addons paint no numbers over ours
    -- The disc and the seconds sit on a frame above the swipe.
    w.over = CreateFrame("Frame", nil, w.ring)
    w.over:SetAllPoints(w.ring)
    w.over:SetFrameLevel((w.cooldown:GetFrameLevel() or 1) + 2)
    w.disc = w.over:CreateTexture(nil, "ARTWORK")
    w.disc:SetTexture(RING_TEXTURE)
    w.disc:SetVertexColor(0, 0, 0, DISC_ALPHA)
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
    if w.discAt ~= size then
        w.discAt = size
        local inset = math.floor(size * DISC_INSET + 0.5)
        w.disc:ClearAllPoints()
        w.disc:SetPoint("TOPLEFT", w.over, "TOPLEFT", inset, -inset)
        w.disc:SetPoint("BOTTOMRIGHT", w.over, "BOTTOMRIGHT", -inset, inset)
    end
    if w.cooldown.SetSwipeColor then
        w.cooldown:SetSwipeColor(c[1], c[2], c[3], RING_ALPHA)
    end
    local total = at - (shownAt or now)
    if type(line.warn) == "number" then
        total = math.min(line.warn, total)
    end
    setSwipe(w, line, total)
    Areas.SetFont(w.seconds, s.font, math.max(MIN_SECONDS_FONT, math.floor(size / 3)), s.outline)
    w.seconds:SetText(seconds(at - now))
    Areas.SetFont(w.text, s.font, textSize, s.outline)
    w.text:SetText(Areas.LineText(line))
    w.text:SetTextColor(c[1], c[2], c[3])
    local words = math.ceil(textWidth(w.text))
    w:SetSize(math.max(size, words), size + TEXT_GAP + textSize + 2)
end

-- The samples keep one base time while the preview runs (a gap between calls means it was turned off
-- and on), so their rings run instead of restarting every tick; they start over once all have passed.
local sampleBase, sampleLast
local function sample(now)
    if not sampleBase or now - sampleLast > SAMPLE_GAP or now > sampleBase + SAMPLE_SPAN then
        sampleBase = now
    end
    sampleLast = now
    return {
        { id = "sample1", text = TEXT.sampleNow, at = sampleBase, warn = 8, glow = true },
        { id = "sample2", text = TEXT.sampleSoon, at = sampleBase + 5, warn = 8 },
        { id = "sample3", text = TEXT.sampleLater, at = sampleBase + 12, warn = 12 },
    }
end

local function settings(dialog, s)
    dialog:Slider(TEXT.size, {
        min = MIN_SIZE,
        max = MAX_SIZE,
        get = function()
            return ringSize(s)
        end,
        set = function(value)
            s.size = value
        end,
    })
    dialog:Dropdown(TEXT.font, {
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
    dialog:Slider(TEXT.textSize, {
        min = MIN_FONT,
        max = MAX_FONT,
        get = function()
            return fontSize(s)
        end,
        set = function(value)
            s.fontSize = value
        end,
    })
    dialog:Dropdown(TEXT.outline, {
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
