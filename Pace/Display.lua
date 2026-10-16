local ADDON, CRT = ...

-- The pace window: during a pull of a boss with a pace plan, one bar per boss unit in the plan showing
-- its health, a tick where its health should be now, and AHEAD or BEHIND.
--
-- In combat the game hides boss health from addons (a secret value), so the addon never compares it.
-- The bar gets UnitHealthPercent through the game's ScaleTo100 curve, which a status bar accepts as it
-- is. AHEAD and BEHIND are faded in by two step curves built around the expected health: the game
-- runs the hidden health through them and SetAlpha takes the result, so the game does the comparing.
-- The curves are rebuilt only when the expected health moves.

local Pace = CRT.Pace
local UI = CRT.UI

local BAR_W, BAR_H = 220, 16
local ROW_H = 40
local TICK_EVERY = 0.2

local frame, handle
local bars = {}
local run -- { encounterID, plan, units, pullAt } while a pull with a plan runs
local previewOn = false

local function db()
    return CRT.db.pace
end

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- A step curve on health 0 to 1: `below` under the expected health e, `above` from e up.
local function stepCurve(e, below, above)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then
        return nil
    end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then
        return nil
    end
    local built = pcall(function()
        if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
            c:SetType(Enum.LuaCurveType.Linear)
        end
        local x = math.max(0.002, math.min(0.998, e))
        c:AddPoint(0, below)
        c:AddPoint(x - 0.001, below)
        c:AddPoint(x, above)
        c:AddPoint(1, above)
    end)
    return built and c or nil
end

-- The window ---------------------------------------------------------------------------------------

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    db().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function applyPosition()
    local p = db().position
    frame:ClearAllPoints()
    if p then
        frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -260)
    end
end

function Pace:ResetPosition()
    db().position = nil
    if frame then
        applyPosition()
    end
end

local function bar(i)
    local b = bars[i]
    if b then
        return b
    end
    b = CreateFrame("Frame", nil, frame)
    b:SetSize(BAR_W + 16, ROW_H)
    b:SetPoint("TOPLEFT", 0, -6 - (i - 1) * ROW_H)
    b.label = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    b.label:SetPoint("TOPLEFT", 8, 0)
    b.state = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    b.state:SetPoint("TOPRIGHT", -8, 0)
    b.bar = CreateFrame("StatusBar", nil, b)
    b.bar:SetSize(BAR_W, BAR_H)
    b.bar:SetPoint("TOPLEFT", 8, -16)
    b.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b.bar:SetStatusBarColor(0.75, 0.2, 0.2, 1)
    b.bar:SetMinMaxValues(0, 100)
    local bg = b.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    b.tick = b.bar:CreateTexture(nil, "OVERLAY")
    b.tick:SetSize(2, BAR_H + 6)
    b.tick:SetColorTexture(1, 1, 1, 1)
    b.ahead = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    b.ahead:SetPoint("RIGHT", b.state, "LEFT", -4, 0)
    b.ahead:SetText("|cff60ff60AHEAD|r")
    b.behind = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    b.behind:SetPoint("RIGHT", b.state, "LEFT", -4, 0)
    b.behind:SetText("|cffff6060BEHIND|r")
    bars[i] = b
    return b
end

local function build()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "CowfeeRaidToolsPace", UIParent, "BackdropTemplate")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    UI:RegisterThemed(frame, { bg = { 0.05, 0.05, 0.07, 0.8 }, border = { 0.78, 0.63, 0.31 } })
    UI:RegisterLayer("alert", frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)

    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    UI:RegisterThemed(handle, { bg = { 0.3, 0.25, 0.05, 0.9 }, border = { 0.78, 0.63, 0.31 } })
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", 6, 0)
    text:SetText("Pace: drag to move")
    handle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    UI.ResetButton(handle, function()
        Pace:ResetPosition()
    end):SetPoint("RIGHT", -2, 0)
    handle:Hide()

    applyPosition()
    frame:Hide()
end

local function layout(units)
    for i, b in ipairs(bars) do
        b:SetShown(i <= #units)
    end
    for i = 1, #units do
        bar(i):Show()
    end
    frame:SetSize(BAR_W + 16, 10 + #units * ROW_H)
end

-- The phase and seconds into it, from the alerts engine's phase clock, else phase 1 from the pull.
local function where()
    local now = GetTime()
    local Alerts = CRT.Alerts
    local ph = Alerts and Alerts.CurrentPhase and Alerts:CurrentPhase()
    local at = ph and Alerts:PhaseStart(ph)
    if run.plan.mode == "time" then
        return 1, now - run.pullAt
    end
    if ph and at then
        return ph, now - at
    end
    return 1, now - run.pullAt
end

local function setBar(b, unit, expected)
    local name = UnitName(unit)
    b.label:SetText(readable(name) and name or unit)
    -- The health: hidden in combat, given to the bar as it is.
    local scale = CurveConstants and CurveConstants.ScaleTo100
    local ok, hp = pcall(UnitHealthPercent, unit, true, scale)
    if ok and hp ~= nil then
        pcall(b.bar.SetValue, b.bar, hp)
    end
    if not expected then
        b.tick:Hide()
        b.state:SetText("")
        b.ahead:SetAlpha(0)
        b.behind:SetAlpha(0)
        return
    end
    b.tick:ClearAllPoints()
    b.tick:SetPoint("CENTER", b.bar, "LEFT", BAR_W * expected / 100, 0)
    b.tick:Show()
    b.state:SetText(string.format("should be %.0f%%", expected))
    -- Curves are rebuilt only when the expected health moves by a tenth of a percent.
    local key = math.floor(expected * 10 + 0.5)
    if b.curveKey ~= key then
        b.curveKey = key
        b.aheadCurve = stepCurve(expected / 100, 1, 0)
        b.behindCurve = stepCurve(expected / 100, 0, 1)
    end
    for _, pair in ipairs({ { b.ahead, b.aheadCurve }, { b.behind, b.behindCurve } }) do
        local fs, curve = pair[1], pair[2]
        local shown = false
        if curve then
            local okA, alpha = pcall(UnitHealthPercent, unit, true, curve)
            if okA and alpha ~= nil then
                shown = pcall(fs.SetAlpha, fs, alpha)
            end
        end
        if not shown then
            fs:SetAlpha(0)
        end
    end
end

local elapsed = 0
local function onUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed < TICK_EVERY or not run then
        return
    end
    elapsed = 0
    local ph, seconds = where()
    for i, unit in ipairs(run.units) do
        if UnitExists(unit) then
            setBar(bar(i), unit, Pace.Expected(run.plan, unit, ph, seconds))
            bar(i):SetAlpha(1)
        else
            bar(i):SetAlpha(0.3)
        end
    end
end

function Pace:Start(encounterID)
    local plan = self:Plan(encounterID)
    if not plan or not self:Enabled(encounterID) or db().shown == false then
        self:Stop()
        return
    end
    build()
    local units = Pace.Units(plan)
    if #units == 0 then
        return
    end
    run = { encounterID = encounterID, plan = plan, units = units, pullAt = GetTime() }
    for _, b in ipairs(bars) do
        b.curveKey = nil
    end
    layout(units)
    frame:SetScript("OnUpdate", onUpdate)
    frame:Show()
end

function Pace:Stop()
    run = nil
    if frame then
        frame:SetScript("OnUpdate", nil)
        if not previewOn then
            frame:Hide()
        end
    end
end

-- Previews: a sample bar, half way, with the tick at 60%.
UI:RegisterPreview("pace", function(on)
    previewOn = on and true or false
    build()
    handle:SetShown(previewOn)
    if previewOn then
        layout({ "boss1" })
        local b = bar(1)
        b.label:SetText("Boss")
        b.bar:SetValue(50)
        b.tick:ClearAllPoints()
        b.tick:SetPoint("CENTER", b.bar, "LEFT", BAR_W * 0.6, 0)
        b.tick:Show()
        b.state:SetText("should be 60%")
        b.ahead:SetAlpha(1)
        b.behind:SetAlpha(0)
        frame:Show()
    elseif not run then
        frame:Hide()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ENCOUNTER_START")
events:RegisterEvent("ENCOUNTER_END")
events:SetScript("OnEvent", function(_, event, encounterID)
    if not CRT.db then
        return
    end
    if event == "ENCOUNTER_START" then
        Pace:Start(readable(encounterID) and encounterID or nil)
    else
        Pace:Stop()
    end
end)
