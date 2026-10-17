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
-- A curve's input is health from 0 to 1: the CurveObject wiki page's own example builds its curves on
-- points 0.0 and 1.0, and uses a ScaleTo100 curve to get 0 to 100 out. So the curve is built on 0 to
-- 1 and never needs your health to be readable. The first in-game test (2026-10-14) showed your
-- health is secret even out of combat, so the plain fallback below rarely applies.
--
-- If it misbehaves, untick it on the Quality of Life page or type /crt lowhp off.

local LowHealth = {}
CRT.LowHealth = LowHealth

local frame, curve
local SCALE = 1 -- the curve's input range, 0 to 1
local previewOn = false
local warned = false

local function settings()
    return CRT.db.qol.lowHealth
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- The curve ------------------------------------------------------------------------------------

-- 1 from 0 up to the threshold, then 0 from just above it to full health.
local function buildCurve()
    curve = nil
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent) then
        return
    end
    local threshold = math.max(1, math.min(99, settings().threshold or 35)) / 100 * SCALE
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
        c:AddPoint(threshold + 0.001 * SCALE, 0)
        c:AddPoint(SCALE, 0)
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

-- How the last update went, for /crt lowhp info: "preview", "off", "dead", "curve" or "plain",
-- and the last error from the curve route, if any.
local lastPath, lastError

function LowHealth:Update()
    if not frame then
        return
    end
    if previewOn then
        lastPath = "preview"
        frame:SetAlpha(1)
        return
    end
    if not settings().enabled or isDead() then
        lastPath = settings().enabled and "dead" or "off"
        frame:SetAlpha(0)
        return
    end
    if curve then
        local ok, alpha = pcall(UnitHealthPercent, "player", true, curve)
        if not ok then
            lastError = "UnitHealthPercent with the curve failed: " .. tostring(alpha)
        elseif alpha == nil then
            lastError = "UnitHealthPercent with the curve returned nothing"
        else
            local set, err = pcall(frame.SetAlpha, frame, alpha)
            if set then
                lastPath = "curve"
                return
            end
            lastError = "SetAlpha refused the curve result: " .. tostring(err)
        end
    end
    lastPath = "plain"
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
    -- By default above the main panel (HIGH), so the panel never covers it.
    CRT.UI:RegisterLayer("lowhealth", frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    frame:SetBackdropColor(0.35, 0, 0, 0.55)
    frame:SetBackdropBorderColor(1, 0.15, 0.15, 1)
    local text = frame:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    text:SetPoint("CENTER")
    text:SetText("|cffff3030LOW HEALTH|r")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:EnableMouse(false)
    frame.reset = CRT.UI.ResetButton(frame, function()
        LowHealth:ResetPosition()
    end)
    frame.reset:SetPoint("TOPRIGHT", -4, -4)
    frame.reset:Hide()
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
    frame.reset:SetShown(previewOn)
    self:Update()
    -- The game's low-health pulse follows the same threshold (QoL/LowHealthSound.lua).
    if CRT.LowHealthSound then
        CRT.LowHealthSound:Apply()
    end
end

function LowHealth:SetEnabled(on)
    settings().enabled = on and true or false
    warned = false
    self:Apply()
end

-- /crt lowhp info: every step of the check, so a report shows where it stops.
function LowHealth:Info()
    build()
    local lines = {}
    local function add(s)
        lines[#lines + 1] = s
    end
    local function show(v)
        if isSecret(v) then
            return "(secret)"
        end
        return tostring(v)
    end
    local s = settings()
    add(format("enabled %s, threshold %s%%, in combat %s", tostring(s.enabled), tostring(s.threshold), tostring(InCombatLockdown())))
    add(format("game has: UnitHealthPercent %s, C_CurveUtil.CreateCurve %s, Enum.LuaCurveType %s", tostring(UnitHealthPercent ~= nil), tostring(C_CurveUtil and C_CurveUtil.CreateCurve ~= nil), tostring(Enum and Enum.LuaCurveType ~= nil)))
    if Enum and Enum.LuaCurveType then
        local names = {}
        for name, value in pairs(Enum.LuaCurveType) do
            names[#names + 1] = name .. "=" .. tostring(value)
        end
        add("curve types: " .. table.concat(names, ", "))
    end
    add(format("curve on 0 to %d, built %s", SCALE, tostring(curve ~= nil)))
    if UnitHealthPercent then
        local ok, raw = pcall(UnitHealthPercent, "player", false)
        add("UnitHealthPercent(player): " .. (ok and show(raw) or ("error " .. tostring(raw))))
        if curve then
            local okc, result = pcall(UnitHealthPercent, "player", true, curve)
            add("with the curve: " .. (okc and show(result) or ("error " .. tostring(result))))
            if ok and type(raw) == "number" and not isSecret(raw) then
                local okv, expected = pcall(curve.Evaluate, curve, raw)
                add("curve at that health, worked out by the addon: " .. (okv and show(expected) or ("error " .. tostring(expected))))
            end
        end
    end
    local health, maximum = UnitHealth("player"), UnitHealthMax("player")
    add(format("UnitHealth %s, UnitHealthMax %s", show(health), show(maximum)))
    add(format("last update path: %s%s", tostring(lastPath), lastError and (", last error: " .. lastError) or ""))
    local point, _, _, x, y = frame:GetPoint()
    add(format("banner shown %s, visible %s, layer %s, at %s %s %s", tostring(frame:IsShown() and true or false), tostring(frame:IsVisible() and true or false), tostring((frame:GetFrameStrata())), tostring(point), show(x), show(y)))
    local okAlpha, alpha = pcall(frame.GetAlpha, frame)
    add("banner alpha: " .. (okAlpha and show(alpha) or "unreadable"))
    if CRT.LowHealthSound then
        add(CRT.LowHealthSound:Info())
    end
    CRT:Print("Low-health alert diagnostics:")
    for _, line in ipairs(lines) do
        print("  " .. line)
    end
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
        LowHealth:Apply()
    elseif frame then
        LowHealth:Update()
    end
end)
