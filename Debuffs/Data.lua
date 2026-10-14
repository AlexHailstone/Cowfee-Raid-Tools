local ADDON, CRT = ...

-- Settings for the in-combat debuff panel, saved per player in CRTDB.debuffs:
--   enabled, size (icon size), maxCount (how many at once), and the dispel icon and regular row options.
--   The look: swipe, swipeEdge, timerPosition, timerX, timerY and borderScale.
--   A reverse option existed until 0.13.0. Its saved value may remain and is ignored.
--   position = { point, relativePoint, x, y } once the panel has been moved.
-- Each player has their own copy in their own saved variables, so nothing is shared between players.

local Debuffs = { listeners = {} }
CRT.Debuffs = Debuffs

local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 150 }

local function ddb()
    return CRT.db.debuffs
end

function Debuffs:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Debuffs:Fire()
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

function Debuffs:Enabled()
    return ddb().enabled
end

function Debuffs:SetEnabled(value)
    ddb().enabled = value and true or false
    self:Fire()
end

function Debuffs:Size()
    return ddb().size
end

function Debuffs:SetSize(size)
    size = tonumber(size)
    if size then
        ddb().size = math.max(24, math.min(96, math.floor(size)))
    end
    self:Fire()
end

function Debuffs:MaxCount()
    return ddb().maxCount
end

function Debuffs:SetMaxCount(count)
    count = tonumber(count)
    if count then
        ddb().maxCount = math.max(1, math.min(8, math.floor(count)))
    end
    self:Fire()
end

-- Show the dispel type icon on a mechanic debuff.
function Debuffs:DispelIcon()
    return ddb().dispelIcon and true or false
end

function Debuffs:SetDispelIcon(value)
    ddb().dispelIcon = value and true or false
    self:Fire()
end

-- Also show regular debuffs, in a second row. Off by default: they cannot be limited to short ones.
function Debuffs:IncludeRegular()
    return ddb().includeRegular and true or false
end

function Debuffs:SetIncludeRegular(value)
    ddb().includeRegular = value and true or false
    self:Fire()
end

-- The look ----------------------------------------------------------------------------------
-- Boss mechanic debuffs are drawn by the game, which takes only these options from an addon: the
-- swipe, its edge, the countdown numbers, the dispel icon, the border scale and where the timer
-- text is anchored. Blizzard_PrivateAurasUI (in the game's own UI source) sets the timer text to the
-- shared GameFontNormalSmall font, inside a protected environment, so its font can't be changed
-- without changing that font across the whole game. The border it draws is the icon's width plus
-- 5 x borderScale pixels, with the dispel type's colored border art.
--
-- The game draws two different timers: its timer text, placed by the anchor we give it, and the
-- countdown numbers on the swipe. Showing both would show the time twice, so they are one setting.
-- The timer text can't be switched off, so for "numbers" and "hidden" it is anchored far off the
-- top of the screen.

Debuffs.TIMER_POSITIONS = {
    { key = "below", label = "Below the icon" },
    { key = "above", label = "Above the icon" },
    { key = "left", label = "Left of the icon" },
    { key = "right", label = "Right of the icon" },
    { key = "center", label = "On the icon" },
    { key = "numbers", label = "Swipe numbers" },
    { key = "hidden", label = "Hidden" },
}

-- Each timer position as the text's point, the icon's point, and a small gap.
local TIMER_ANCHORS = {
    below = { "TOP", "BOTTOM", 0, -2 },
    above = { "BOTTOM", "TOP", 0, 2 },
    center = { "CENTER", "CENTER", 0, 0 },
    left = { "RIGHT", "LEFT", -3, 0 },
    right = { "LEFT", "RIGHT", 3, 0 },
}

function Debuffs:Get(field)
    return ddb()[field]
end

function Debuffs:Set(field, value)
    ddb()[field] = value
    self:Fire()
end

-- timerX and timerY, -40 to 40 pixels.
function Debuffs:SetNudge(field, value)
    value = tonumber(value)
    if value then
        ddb()[field] = math.max(-40, math.min(40, math.floor(value + 0.5)))
    end
    self:Fire()
end

-- Where the timer text goes beside the icon: point, relativePoint, x, y, or nil when the timer is
-- the swipe numbers or hidden.
function Debuffs:TimerAnchor()
    local position = ddb().timerPosition
    if position == "numbers" or position == "hidden" then
        return nil
    end
    local anchor = TIMER_ANCHORS[position] or TIMER_ANCHORS.below
    return anchor[1], anchor[2], anchor[3] + (ddb().timerX or 0), anchor[4] + (ddb().timerY or 0)
end

-- True when the timer is the game's countdown numbers on the swipe.
function Debuffs:SwipeNumbers()
    return ddb().timerPosition == "numbers"
end

-- The saved position, or the default one in the upper middle of the screen.
function Debuffs:Position()
    return ddb().position or DEFAULT_POSITION
end

function Debuffs:SavePosition(point, relativePoint, x, y)
    ddb().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

function Debuffs:ResetPosition()
    ddb().position = nil
    self:Fire()
end
