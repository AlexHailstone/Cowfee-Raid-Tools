local ADDON, CRT = ...

-- Pace: where a boss's health should be at each point of the fight, to compare with where it is.
-- A plan is shipped (Pace/Database.lua) or your own (CRTDB.pace.own[encounterID], used in place of the
-- shipped one), with a mode ("phase" or "time") and rows of phase, seconds, boss unit and expected
-- health. CRTDB.pace.disabled[encounterID] turns a boss's pace window off for you.
--
-- Phases come from the alerts engine's phase clock (the pull, a phase event or Next phase), so in
-- "phase" mode a row's seconds count from when its phase started. In "time" mode they count from the
-- pull and the phase column is ignored.

local Pace = { listeners = {} }
CRT.Pace = Pace

local UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
Pace.UNITS = UNITS

local function db()
    return CRT.db.pace
end

function Pace:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Pace:Fire()
    for _, fn in ipairs(self.listeners) do
        pcall(fn)
    end
end

local function copyPlan(plan)
    local out = { mode = plan.mode or "phase", rows = {} }
    for _, r in ipairs(plan.rows or {}) do
        out.rows[#out.rows + 1] = { ph = r.ph or 1, t = r.t or 0, unit = r.unit or "boss1", hp = r.hp or 100 }
    end
    return out
end

-- The plan for a boss: your own, else the shipped one, else nil.
function Pace:Plan(encounterID)
    return encounterID and (db().own[encounterID] or CRT.PaceDB.bosses[encounterID]) or nil
end

function Pace:IsOwn(encounterID)
    return encounterID and db().own[encounterID] ~= nil or false
end

function Pace:IsShipped(encounterID)
    return encounterID and CRT.PaceDB.bosses[encounterID] ~= nil or false
end

-- Your own copy of a boss's plan, made from the shipped one (or empty) the first time it is edited.
local function own(encounterID)
    local mine = db().own[encounterID]
    if not mine then
        mine = copyPlan(CRT.PaceDB.bosses[encounterID] or {})
        db().own[encounterID] = mine
    end
    return mine
end

local function sortRows(rows)
    table.sort(rows, function(a, b)
        if a.unit ~= b.unit then
            return a.unit < b.unit
        end
        if a.ph ~= b.ph then
            return a.ph < b.ph
        end
        return a.t < b.t
    end)
end

function Pace:AddRow(encounterID, ph, t, unit, hp)
    local plan = own(encounterID)
    plan.rows[#plan.rows + 1] = { ph = math.max(1, math.floor(ph or 1)), t = math.max(0, t or 0), unit = unit or "boss1", hp = math.max(0, math.min(100, hp or 100)) }
    sortRows(plan.rows)
    self:Fire()
end

function Pace:RemoveRow(encounterID, index)
    local plan = own(encounterID)
    table.remove(plan.rows, index)
    self:Fire()
end

function Pace:SetMode(encounterID, mode)
    own(encounterID).mode = (mode == "time") and "time" or "phase"
    self:Fire()
end

-- Back to the shipped plan (or none), dropping your own.
function Pace:Reset(encounterID)
    db().own[encounterID] = nil
    self:Fire()
end

function Pace:Enabled(encounterID)
    return not db().disabled[encounterID]
end

function Pace:SetEnabled(encounterID, on)
    db().disabled[encounterID] = (not on) and true or nil
    self:Fire()
end

-- The units a plan has rows for, in order.
function Pace.Units(plan)
    local seen, out = {}, {}
    for _, u in ipairs(UNITS) do
        for _, r in ipairs(plan and plan.rows or {}) do
            if r.unit == u and not seen[u] then
                seen[u] = true
                out[#out + 1] = u
            end
        end
    end
    return out
end

-- The expected health of a unit: in phase mode at `seconds` into phase `ph`, in time mode at `seconds`
-- from the pull. Rows of that phase (or all rows in time mode) are joined by straight lines; before the
-- first row it is the first row's value, after the last the last row's. nil when there is no row.
function Pace.Expected(plan, unit, ph, seconds)
    if not plan then
        return nil
    end
    local pts = {}
    for _, r in ipairs(plan.rows or {}) do
        if r.unit == unit and (plan.mode == "time" or r.ph == ph) then
            pts[#pts + 1] = r
        end
    end
    if #pts == 0 then
        return nil
    end
    table.sort(pts, function(a, b)
        return a.t < b.t
    end)
    if seconds <= pts[1].t then
        return pts[1].hp
    end
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if seconds <= b.t then
            local span = b.t - a.t
            if span <= 0 then
                return b.hp
            end
            return a.hp + (b.hp - a.hp) * (seconds - a.t) / span
        end
    end
    return pts[#pts].hp
end

-- Text in and out: one row per line, "phase seconds unit health", such as "1 30 boss1 72.1". A line
-- "mode time" or "mode phase" sets the mode. Commas work in place of spaces.
function Pace:Export(encounterID)
    local plan = self:Plan(encounterID)
    if not plan then
        return ""
    end
    local lines = { "mode " .. (plan.mode or "phase") }
    for _, r in ipairs(plan.rows) do
        lines[#lines + 1] = string.format("%d %s %s %s", r.ph, tostring(r.t), r.unit, tostring(r.hp))
    end
    return table.concat(lines, "\n")
end

-- The Lua line for Pace/Database.lua, for shipping a plan to everyone.
function Pace:ExportLua(encounterID)
    local plan = self:Plan(encounterID)
    if not plan then
        return ""
    end
    local rows = {}
    for _, r in ipairs(plan.rows) do
        rows[#rows + 1] = string.format('{ ph = %d, t = %s, unit = %q, hp = %s }', r.ph, tostring(r.t), r.unit, tostring(r.hp))
    end
    return string.format('[%d] = { mode = %q, rows = { %s } },', encounterID, plan.mode or "phase", table.concat(rows, ", "))
end

-- Replaces your plan for a boss with pasted text. Returns the number of rows, or nil and the reason.
function Pace:Import(encounterID, text)
    local plan = { mode = "phase", rows = {} }
    local n = 0
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = line:gsub(",", " "):gsub("^%s+", ""):gsub("%s+$", "")
        local mode = line:lower():match("^mode%s+(%a+)$")
        if mode then
            plan.mode = (mode == "time") and "time" or "phase"
        elseif line ~= "" and not line:match("^#") then
            local ph, t, unit, hp = line:match("^(%d+)%s+([%d%.]+)%s+(%S+)%s+([%d%.]+)$")
            if not ph then
                return nil, "Line " .. (n + 1) .. " should be \"phase seconds unit health\", such as 1 30 boss1 72.1."
            end
            n = n + 1
            plan.rows[n] = { ph = tonumber(ph), t = tonumber(t), unit = unit:lower(), hp = math.max(0, math.min(100, tonumber(hp))) }
        end
    end
    if n == 0 then
        return nil, "Nothing to import."
    end
    sortRows(plan.rows)
    db().own[encounterID] = plan
    self:Fire()
    return n
end
