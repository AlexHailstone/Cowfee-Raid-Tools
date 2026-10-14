local ADDON, CRT = ...

-- Settings for the in-combat debuff panel, saved per player in CRTDB.debuffs:
--   enabled, size (icon size), maxCount (how many at once), and the dispel icon and regular row options.
--   The look: swipe, swipeEdge, countdownNumbers, timerPosition, timerX, timerY and borderScale.
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
-- text is anchored. Their font, text size and colors can't be changed by any addon.

Debuffs.TIMER_POSITIONS = {
    { key = "below", label = "Below" },
    { key = "above", label = "Above" },
    { key = "center", label = "On the icon" },
    { key = "left", label = "Left" },
    { key = "right", label = "Right" },
    { key = "hidden", label = "Hidden" },
}
Debuffs.BORDERS = {
    { key = 1, label = "Normal" },
    { key = 1.5, label = "Thick" },
    { key = 0.5, label = "Thin" },
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

-- Where the timer text goes: point, relativePoint, x, y, or nil when it is hidden.
function Debuffs:TimerAnchor()
    local anchor = TIMER_ANCHORS[ddb().timerPosition] or (ddb().timerPosition ~= "hidden" and TIMER_ANCHORS.below)
    if not anchor then
        return nil
    end
    return anchor[1], anchor[2], anchor[3] + (ddb().timerX or 0), anchor[4] + (ddb().timerY or 0)
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
