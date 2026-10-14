local ADDON, CRT = ...

-- The low-health alert (experimental): a "LOW HEALTH" banner that shows while your health is at or
-- under the threshold set on the Quality of Life page. Settings in CRTDB.qol.lowHealth.
--
-- In combat the game makes your health a secret value, which addon code cannot compare. So the
-- banner never compares it: UnitHealthPercent("player", true, curve) runs your health through a
-- curve that gives 1 at or under the threshold and 0 above it, and that result goes straight into
-- the banner's SetAlpha, which accepts secret values. The game does the comparison, and the addon
-- only passes the result on. When the curve route is missing or fails, out of combat it falls back
-- to plain UnitHealth and UnitHealthMax, which are readable then.
--
-- The scale of UnitHealthPercent (0 to 1, or 0 to 100) is not on its wiki page, so it is measured out
-- of combat, when the value is readable, and the curve is built to match.
--
-- If it misbehaves, untick it on the Quality of Life page or type /crt lowhp off.

local LowHealth = {}
CRT.LowHealth = LowHealth

local frame, curve
local scale -- 1 or 100, measured from UnitHealthPercent out of combat
local previewOn = false
local warned = false

local function settings()
    return CRT.db.qol.lowHealth
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- The curve ------------------------------------------------------------------------------------

local function measureScale()
    if not UnitHealthPercent then
        return
    end
    local ok, value = pcall(UnitHealthPercent, "player", false)
    if ok and type(value) == "number" and not isSecret(value) and value > 0 then
        scale = value > 1.5 and 100 or 1
    end
end

-- 1 from 0 up to the threshold, then 0 from just above it to full health.
local function buildCurve()
    curve = nil
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent) then
        return
    end
    measureScale()
    if not scale then
        return
    end
    local threshold = math.max(1, math.min(99, settings().threshold or 35)) / 100 * scale
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then
        return
    end
    local built = pcall(function()
        if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
            c:SetType(Enum.LuaCurveType.Linear)
        end
        c:AddPoint(0, 1)
        c:AddPoint(threshold, 1)
        c:AddPoint(threshold + 0.001 * scale, 0)
        c:AddPoint(scale, 0)
    end)
    if built then
        curve = c
    end
end

-- Updating ---------------------------------------------------------------------------------------

local function plainAlpha()
    local health, maximum = UnitHealth("player"), UnitHealthMax("player")
    if isSecret(health) or isSecret(maximum) or not maximum or maximum <= 0 then
        return 0
    end
    return (health / maximum * 100 <= (settings().threshold or 35)) and 1 or 0
end

local function isDead()
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    return ok and not isSecret(dead) and dead and true or false
end

function LowHealth:Update()
    if not frame then
        return
    end
    if previewOn then
        frame:SetAlpha(1)
        return
    end
    if not settings().enabled or isDead() then
        frame:SetAlpha(0)
        return
    end
    if curve then
        local ok, alpha = pcall(UnitHealthPercent, "player", true, curve)
        if ok and alpha ~= nil and pcall(frame.SetAlpha, frame, alpha) then
            return
        end
    end
    if InCombatLockdown() and not warned then
        warned = true
        CRT:Print("The low-health alert can't read your health in combat on this client. Turn it off with /crt lowhp off.")
    end
    frame:SetAlpha(plainAlpha())
end

-- The banner -------------------------------------------------------------------------------------

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    settings().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function applyPosition()
    frame:ClearAllPoints()
    local p = settings().position
    if p then
        frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    end
end

local function build()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "CowfeeRaidToolsLowHealth", UIParent, "BackdropTemplate")
    frame:SetSize(300, 56)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    frame:SetBackdropColor(0.35, 0, 0, 0.55)
    frame:SetBackdropBorderColor(1, 0.15, 0.15, 1)
    local text = frame:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    text:SetPoint("CENTER")
    text:SetText("|cffff3030LOW HEALTH|r")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:EnableMouse(false)
    applyPosition()
    frame:SetAlpha(0)
end

-- Shows or hides the banner frame for the current settings. It stays shown while enabled, invisible
-- above the threshold, since only its alpha may be set from a secret.
function LowHealth:Apply()
    build()
    buildCurve()
    frame:SetShown(previewOn or settings().enabled)
    frame:EnableMouse(previewOn)
    self:Update()
end

function LowHealth:SetEnabled(on)
    settings().enabled = on and true or false
    warned = false
    self:Apply()
end

function LowHealth:ResetPosition()
    settings().position = nil
    if frame then
        applyPosition()
    end
end

CRT.UI:RegisterPreview("lowhealth", function(on)
    previewOn = on and true or false
    LowHealth:Apply()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_HEALTH", "player")
events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
events:SetScript("OnEvent", function(_, event)
    if not CRT.db then
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        -- Out of combat the value is readable, so measure the scale and rebuild the curve.
        LowHealth:Apply()
    elseif frame then
        LowHealth:Update()
    end
end)
