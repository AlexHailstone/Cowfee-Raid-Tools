local ADDON, CRT = ...

-- Phase events: a boss emote, a boss becoming untargetable or targetable, or a new boss unit starts
-- a phase on the alerts engine's clock. Your triggers are saved in CRT.db.alerts.phases[encounterID][ph]
-- = { kind, value }; shipped ones are in CRT.AlertPhaseDB. Midnight can hide values in a boss fight, so
-- every value is checked with CRT.Timeline.readable before it is compared or used; one that fails is
-- ignored without a message.

local Alerts = CRT.Alerts

local Phases = {}
CRT.AlertPhases = Phases

Phases.KINDS = {
    { key = "manual", label = "Next phase only" },
    { key = "emote", label = "Boss emote contains" },
    { key = "untargetable", label = "Boss becomes untargetable" },
    { key = "targetable", label = "Boss becomes targetable" },
    { key = "newboss", label = "New boss unit appears" },
}

local KIND_SET = {}
for _, k in ipairs(Phases.KINDS) do
    KIND_SET[k.key] = true
end
local UNITS = { boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true }

local pullUnits = {} -- boss units that existed at the pull

local function readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

-- A string that is safe to compare, or nil.
local function plainString(v)
    if readable(v) and type(v) == "string" then
        return v
    end
    return nil
end

local function saved()
    local s = Alerts:Settings()
    if s then
        s.phases = s.phases or {}
    end
    return s and s.phases
end

-- Shipped entries with yours laid over them: { [ph] = { kind, value, from = "shipped"|"yours" } }.
function Phases:For(encounterID)
    local out = {}
    local function lay(src, from)
        if type(src) ~= "table" then
            return
        end
        for ph, e in pairs(src) do
            if type(ph) == "number" and type(e) == "table" then
                out[ph] = { kind = e.kind or e[1], value = e.value or e[2], from = from }
            end
        end
    end
    lay(CRT.AlertPhaseDB and CRT.AlertPhaseDB[encounterID], "shipped")
    local mine = saved()
    lay(mine and mine[encounterID], "yours")
    return out
end

local function validValue(kind, value)
    if not readable(value) then
        return false
    end
    if kind == "manual" then
        return true
    elseif kind == "emote" then
        return type(value) == "string" and value:match("%S") ~= nil
    end
    if kind == "newboss" and value == "boss1" then
        return false -- boss1 is the pull's own boss, so it can never be new
    end
    return type(value) == "string" and UNITS[value] == true
end

-- Saves your trigger for a phase. False when the phase, kind or value is not valid.
function Phases:Set(encounterID, ph, kind, value)
    if type(encounterID) ~= "number" or encounterID ~= encounterID or type(ph) ~= "number" or ph ~= ph
        or ph <= 1 or ph >= math.huge or type(kind) ~= "string" or not KIND_SET[kind] or not validValue(kind, value) then
        return false
    end
    local all = saved()
    if not all then
        return false
    end
    all[encounterID] = all[encounterID] or {}
    all[encounterID][ph] = { kind = kind, value = kind ~= "manual" and value or nil }
    Alerts:Fire()
    return true
end

-- Removes your trigger so the shipped one (if any) shows again.
function Phases:UseShipped(encounterID, ph)
    local all = saved()
    local mine = all and all[encounterID]
    if mine then
        mine[ph] = nil
        if next(mine) == nil then
            all[encounterID] = nil
        end
    end
    Alerts:Fire()
end

-- The current run's boss, or nil.
local function currentEncounter()
    if Alerts.running and Alerts.run and Alerts.run.reason == "encounter" then
        return Alerts.run.encounterID
    end
    return nil
end

-- The phases of one boss that have a trigger, in order.
local function triggered(encounterID)
    local list = {}
    for ph, e in pairs(Phases:For(encounterID)) do
        if ph > 1 and e.kind ~= "manual" and KIND_SET[e.kind] then
            list[#list + 1] = ph
        end
    end
    table.sort(list)
    return list
end

local function unitExists(unit)
    local ok, exists = pcall(UnitExists, unit)
    if ok and readable(exists) then
        return exists and true or false
    end
    return false
end

-- Starts the earliest phase whose trigger matches and that has not started. One event, one phase.
local function startFirst(matches)
    local id = currentEncounter()
    if id == nil then
        return
    end
    local defs = Phases:For(id)
    for _, ph in ipairs(triggered(id)) do
        if not Alerts:PhaseStart(ph) and not Alerts:Skipped(ph) then
            local e = defs[ph]
            local ok, hit = pcall(matches, e)
            if ok and hit then
                Alerts:StartPhase(ph, "event")
                return
            end
        end
    end
end

function Phases.HandleEvent(event, ...)
    if not currentEncounter() then
        return
    end
    if event == "RAID_BOSS_EMOTE" or event == "CHAT_MSG_RAID_BOSS_EMOTE" then
        local text = plainString((...))
        if not text then
            return
        end
        local lower = text:lower()
        startFirst(function(e)
            local want = e.kind == "emote" and plainString(e.value)
            return want and want ~= "" and lower:find(want:lower(), 1, true) ~= nil
        end)
    elseif event == "UNIT_TARGETABLE_CHANGED" then
        local unit = plainString((...))
        if not unit or not UNITS[unit] then
            return
        end
        local ok, canAttack = pcall(UnitCanAttack, "player", unit)
        if not ok or not readable(canAttack) or type(canAttack) ~= "boolean" then
            return
        end
        startFirst(function(e)
            if e.value ~= unit then
                return false
            end
            return (e.kind == "untargetable" and canAttack == false) or (e.kind == "targetable" and canAttack == true)
        end)
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        startFirst(function(e)
            return e.kind == "newboss" and UNITS[e.value] == true and unitExists(e.value) and not pullUnits[e.value]
        end)
    end
end

-- Which boss units exist at the pull.
Alerts.onPull[#Alerts.onPull + 1] = function(run)
    pullUnits = {}
    for unit in pairs(UNITS) do
        if unitExists(unit) then
            pullUnits[unit] = true
        end
    end
end

-- Phases with a trigger count for Next phase.
Alerts.phaseSources[#Alerts.phaseSources + 1] = function(run)
    return run and triggered(run.encounterID) or {}
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_EMOTE", "UNIT_TARGETABLE_CHANGED",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }) do
    frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(_, event, ...)
    Phases.HandleEvent(event, ...)
end)
