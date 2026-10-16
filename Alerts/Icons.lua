local ADDON, CRT = ...

-- The icons area: a spell icon for every line whose outputs.icon is on, a countdown swipe over it, the
-- seconds in its middle and the alert's text beside it. Built on Alerts/Areas.lua; its settings are
-- CRT.db.alerts.areas.icons (size, font, fontSize, outline, showText, beside the common shown, cap, grow).

local Areas = CRT.AlertAreas

local TEXT = {
    title = "Alert icons",
    now = "NOW",
    size = "Size",
    font = "Font",
    textSize = "Text size",
    outline = "Outline",
    none = "None",
    thin = "Outline",
    thick = "Thick",
    showText = "Show the text",
    fade = "Fade to grey as time runs out",
    sampleNow = "Spread",
    sampleSoon = "Stack on the boss",
    sampleLater = "Soak",
}

local NOW_BELOW = 0.1     -- under this many seconds left reads NOW
local MIN_ICON, MAX_ICON, DEFAULT_ICON = 24, 96, 44
local MIN_FONT, MAX_FONT, DEFAULT_FONT = 10, 40, 20
local MIN_SECONDS_FONT = 8
local TRIM = { 0.07, 0.93, 0.07, 0.93 }
local TEXT_GAP = 6        -- between the icon and its text
local PAD = 4             -- after the text
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = -300, y = 100 }
local WHITE = { 1, 1, 1 }
-- Spell icons for the preview.
local SAMPLE_ICONS = { 136243, 135808, 136116 }
local SAMPLE_GAP = 1      -- seconds between preview ticks that mean it was turned off
local SAMPLE_SPAN = 14    -- the preview starts over this long after it began

local OUTLINE_OPTIONS = {
    { key = "", label = TEXT.none },
    { key = "OUTLINE", label = TEXT.thin },
    { key = "THICKOUTLINE", label = TEXT.thick },
}

local function clamp(v, min, max, default)
    v = type(v) == "number" and v or default
    return math.max(min, math.min(max, v))
end

local function iconSize(s)
    return clamp(s.size, MIN_ICON, MAX_ICON, DEFAULT_ICON)
end

local function fontSize(s)
    return clamp(s.fontSize, MIN_FONT, MAX_FONT, DEFAULT_FONT)
end

local function showText(s)
    return s.showText ~= false
end

local function fadeOn(s)
    return s.fade ~= false
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
    -- The icon square: the picture and the swipe live in a frame exactly its size, so the swipe sweeps from
    -- the icon's centre and never reaches the text.
    w.iconFrame = CreateFrame("Frame", nil, w)
    w.iconFrame:SetPoint("LEFT", w, "LEFT", 0, 0)
    w.icon = w.iconFrame:CreateTexture(nil, "ARTWORK")
    w.icon:SetAllPoints(w.iconFrame)
    w.icon:SetTexCoord(TRIM[1], TRIM[2], TRIM[3], TRIM[4])
    w.cooldown = CreateFrame("Cooldown", nil, w.iconFrame, "CooldownFrameTemplate")
    w.cooldown:SetAllPoints(w.iconFrame)
    if w.cooldown.SetHideCountdownNumbers then
        w.cooldown:SetHideCountdownNumbers(true) -- the seconds are drawn here
    end
    if w.cooldown.SetDrawEdge then
        w.cooldown:SetDrawEdge(false)
    end
    if w.cooldown.SetDrawBling then
        w.cooldown:SetDrawBling(false) -- no finish flash over NOW and the glow
    end
    w.cooldown.noCooldownCount = true -- other addons paint no numbers over ours
    -- The seconds sit on a frame above the swipe, centred on the icon.
    w.over = CreateFrame("Frame", nil, w)
    w.over:SetPoint("CENTER", w.iconFrame, "CENTER", 0, 0)
    w.over:SetFrameLevel((w.cooldown:GetFrameLevel() or 1) + 2)
    w.seconds = w.over:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    w.seconds:SetPoint("CENTER", w.over, "CENTER", 0, 0)
    w.seconds:SetShadowOffset(1, -1)
    -- Anchored by one point, not to the widget's edges, so its width is never bounded by the widget.
    w.text = w:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    w.text:SetWordWrap(false)
    w.text:SetShadowOffset(1, -1)
    w.text:SetJustifyH("LEFT")
    return w
end

-- 0 in colour to 1 grey as the time left runs out over `total`; grey at and after zero.
local function setGrey(texture, grey)
    if texture.SetDesaturation then
        texture:SetDesaturation(grey)
    elseif texture.SetDesaturated then
        texture:SetDesaturated(grey >= 0.5)
    end
end

local function greyness(total, left)
    if left <= 0 then
        return 1
    end
    if total <= 0 then
        return 0
    end
    return math.max(0, math.min(1, (total - left) / total))
end

-- The swipe starts full: it runs over the time left when the line first showed, at most `warn`. It is
-- set only when the line or its time changes, since widgets are pooled by position and lines move up.
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
    local size, textSize = iconSize(s), fontSize(s)
    local at = line.at
    local texture = Areas.LineIcon(line)
    w.icon:SetSize(size, size)
    w.iconFrame:SetSize(size, size)
    if texture then
        w.icon:SetTexture(texture)
        w.icon:Show()
        w.cooldown:Show()
        local total = at - (shownAt or now)
        if type(line.warn) == "number" then
            total = math.min(line.warn, total)
        end
        setSwipe(w, line, total)
        setGrey(w.icon, fadeOn(s) and greyness(total, at - now) or 0)
    else
        setGrey(w.icon, 0)
        w.icon:Hide()
        w.cooldown:Hide()
        w.swipeKey = nil
    end
    Areas.SetFont(w.seconds, s.font, math.max(MIN_SECONDS_FONT, math.floor(size / 2)), s.outline)
    w.seconds:SetText(seconds(at - now))
    local width = size
    if showText(s) then
        Areas.SetFont(w.text, s.font, textSize, s.outline)
        if w.textAt ~= size then
            w.textAt = size
            w.text:ClearAllPoints()
            w.text:SetPoint("LEFT", w, "LEFT", size + TEXT_GAP, 0) -- right of the icon square, on the widget
        end
        w.text:SetText(Areas.LineText(line))
        local c = Areas.LineColor(line) or WHITE
        w.text:SetTextColor(c[1], c[2], c[3])
        w.text:Show()
        local words = math.ceil(textWidth(w.text))
        if words > 0 then
            width = size + TEXT_GAP + words + PAD
        end
    else
        w.text:Hide()
    end
    w:SetSize(width, size)
end

-- The samples keep one base time while the preview runs (a gap between calls means it was turned off
-- and on), so their swipes run instead of restarting every tick; they start over once all have passed.
local sampleBase, sampleLast
local function sample(now)
    if not sampleBase or now - sampleLast > SAMPLE_GAP or now > sampleBase + SAMPLE_SPAN then
        sampleBase = now
    end
    sampleLast = now
    return {
        { id = "sample1", text = TEXT.sampleNow, icon = SAMPLE_ICONS[1], at = sampleBase, warn = 8, glow = true },
        { id = "sample2", text = TEXT.sampleSoon, icon = SAMPLE_ICONS[2], at = sampleBase + 5, warn = 8 },
        { id = "sample3", text = TEXT.sampleLater, icon = SAMPLE_ICONS[3], at = sampleBase + 12, warn = 12 },
    }
end

local function settings(panel, s)
    panel:Slider(TEXT.size, {
        min = MIN_ICON,
        max = MAX_ICON,
        get = function()
            return iconSize(s)
        end,
        set = function(value)
            s.size = value
        end,
    })
    panel:Dropdown(TEXT.font, {
        -- Read each time the menu opens, so fonts another addon shares later appear.
        options = function()
            local out = {}
            for _, font in ipairs(CRT:FontList()) do
                out[#out + 1] = { key = font.name, label = font.name }
            end
            return out
        end,
        enabledIf = function()
            return showText(s)
        end,
        get = function()
            return s.font
        end,
        set = function(name)
            s.font = name
        end,
    })
    panel:Slider(TEXT.textSize, {
        min = MIN_FONT,
        max = MAX_FONT,
        enabledIf = function()
            return showText(s)
        end,
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
    panel:Check(TEXT.showText, function()
        return showText(s)
    end, function(on)
        s.showText = on
    end)
    panel:Check(TEXT.fade, function()
        return fadeOn(s)
    end, function(on)
        s.fade = on
    end)
end

CRT.AlertIcons = Areas.New({
    key = "icons",
    output = "icon",
    layer = "alerticons",
    title = TEXT.title,
    settingsKey = "icons",
    defaultPosition = DEFAULT_POSITION,
    make = make,
    draw = draw,
    sample = sample,
    settings = settings,
    align = function()
        return "LEFT" -- icons share a left edge; the texts differ in width
    end,
})
