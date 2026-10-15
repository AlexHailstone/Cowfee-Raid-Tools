local ADDON, CRT = ...

-- Ready button lock: when a ready check starts and your class gives a raid buff (Report.BUFFS) that
-- someone in the group is missing, the game's Ready button is greyed out until everyone has it, so you
-- buff before you ready. On by default (CRTDB.readycheck.buffLock), set on the Ready Check Settings tab.
--
--   * Who counts: everyone the game lets us read. Players who are offline, out of sight, or whose buffs
--     the game hides never lock you, since they can't be checked (Report gives them no auras).
--   * Hold Shift to ready anyway: while Shift is down the lock steps aside and the game's own Ready
--     button works, so the addon never answers the ready check for you.
--   * It unlocks by itself after UNLOCK_SECONDS, in case you can't buff (dead, out of mana, out of range).
--
-- The game's button is ReadyCheckFrameYesButton (Blizzard_FrameXML/Mainline/ReadyCheck.xml), a plain
-- UIPanelButtonTemplate whose OnClick calls C_PartyInfo.ConfirmReadyCheck(true). The lock only
-- disables it and lays a cover over it; it never clicks it.

local Report = CRT.RaidReport
local BuffLock = {}
CRT.BuffLock = BuffLock

local UNLOCK_SECONDS = 10
local RECHECK_SECONDS = 0.25

local cover
local myBuffs = {} -- your class's raid buffs for this ready check
local lockedUntil -- GetTime() when the lock lifts by itself, nil when not locked
local missing = {} -- buff label -> { names }, from the last check
local auraChanged = false
local sinceCheck = 0

local function settings()
    return CRT.db.readycheck
end

local function yesButton()
    return _G.ReadyCheckFrameYesButton
end

local function classBuffs()
    local _, class = UnitClass("player")
    local out = {}
    for _, buff in ipairs(Report.BUFFS) do
        if buff.class == class then
            out[#out + 1] = buff
        end
    end
    return out
end

-- Who is missing one of your buffs. Returns { [label] = { names } } and how many are missing.
local function whoIsMissing()
    local out, total = {}, 0
    for _, m in ipairs(Report:ReadGroup()) do
        if m.auras then
            for _, buff in ipairs(myBuffs) do
                if Report.Cell(m, buff.key).state == "missing" then
                    out[buff.label] = out[buff.label] or {}
                    table.insert(out[buff.label], m.name)
                    total = total + 1
                end
            end
        end
    end
    return out, total
end

local events = CreateFrame("Frame")

function BuffLock:Unlock()
    lockedUntil = nil
    events:UnregisterEvent("UNIT_AURA")
    if cover then
        cover:Hide()
    end
    local yes = yesButton()
    if yes then
        yes:Enable()
    end
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Ready is locked", 1, 1, 1)
    for label, names in pairs(missing) do
        GameTooltip:AddLine("Missing your " .. label .. ": " .. table.concat(names, ", "), 1, 0.82, 0, true)
    end
    GameTooltip:AddLine("Buff them and Ready unlocks. Hold Shift and click Ready to ready anyway.", 0.8, 0.8, 0.8, true)
    if lockedUntil then
        GameTooltip:AddLine(format("Unlocks by itself in %d s.", math.max(0, math.ceil(lockedUntil - GetTime()))), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- The cover over the game's Ready button: it takes the click while locked, and steps aside while
-- Shift is held so the game's button can be pressed.
local function buildCover(yes)
    if cover then
        return cover
    end
    cover = CreateFrame("Button", nil, yes)
    cover:SetAllPoints(yes)
    cover:SetFrameLevel(yes:GetFrameLevel() + 5)
    cover:RegisterForClicks("AnyUp")
    cover:SetScript("OnEnter", showTooltip)
    cover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    cover.hint = cover:CreateFontString(nil, "OVERLAY", "CRTFontButtonSmall")
    cover.hint:SetPoint("TOP", yes, "BOTTOM", 0, -1)
    cover.hint:SetTextColor(1, 0.82, 0)
    cover:SetScript("OnUpdate", function(self, dt)
        if not lockedUntil then
            return
        end
        -- Shift: let the click reach the game's button.
        local shift = IsShiftKeyDown()
        self:EnableMouse(not shift)
        yes:SetEnabled(shift)
        local left = lockedUntil - GetTime()
        if left <= 0 then
            BuffLock:Unlock()
            return
        end
        self.hint:SetText(format("Buff first, or hold Shift  (%d)", math.ceil(left)))
        -- Check again soon after a buff changes on someone in the group.
        sinceCheck = sinceCheck + dt
        if auraChanged and sinceCheck >= RECHECK_SECONDS then
            auraChanged, sinceCheck = false, 0
            local list, total = whoIsMissing()
            missing = list
            if total == 0 then
                BuffLock:Unlock()
            end
        end
    end)
    cover:Hide()
    return cover
end

-- Locks Ready if someone is missing one of your buffs. Called just after the ready check appears.
function BuffLock:Check()
    local yes = yesButton()
    if not (yes and yes:IsVisible()) then
        return
    end
    myBuffs = classBuffs()
    if #myBuffs == 0 then
        return
    end
    local list, total = whoIsMissing()
    if total == 0 then
        return
    end
    missing = list
    lockedUntil = GetTime() + UNLOCK_SECONDS
    auraChanged, sinceCheck = false, 0
    buildCover(yes)
    yes:Disable()
    cover:EnableMouse(true)
    cover:Show()
    events:RegisterEvent("UNIT_AURA")
end

events:RegisterEvent("READY_CHECK")
events:RegisterEvent("READY_CHECK_FINISHED")
events:SetScript("OnEvent", function(_, event)
    if not CRT.db then
        return
    end
    if event == "READY_CHECK" then
        if settings().buffLock then
            -- The game shows its ready check dialog on this same event, so look once it is up.
            C_Timer.After(0.1, function()
                BuffLock:Check()
            end)
        end
    elseif event == "READY_CHECK_FINISHED" then
        BuffLock:Unlock()
    elseif event == "UNIT_AURA" then
        auraChanged = true
    end
end)
