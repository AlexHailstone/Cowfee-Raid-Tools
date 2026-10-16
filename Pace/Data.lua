local ADDON, CRT = ...

-- Pace: where a boss's health should be at each point of the fight, to compare with where it is.
-- A boss can have three plans: the raid's (shared by the raid leader or an assistant, Pace/Comm.lua,
-- in CRTDB.pace.shared[encounterID]), your own (CRTDB.pace.own[encounterID]) and the shipped one
-- (Pace/Database.lua). The plan in use is the raid's while there is one, unless you switched that boss
-- to your own (CRTDB.pace.use[encounterID] = "own"); a new share always switches you back to the
-- raid's. Then your own, then the shipped one. Each has a mode ("phase" or "time") and rows of phase,
-- seconds, boss unit and expected health. CRTDB.pace.disabled[encounterID] turns a boss off for you.
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

-- The plan in use for a boss, and where it comes from: "raid", "own", "shipped", or nil.
function Pace:Source(encounterID)
    if not encounterID then
        return nil
    end
    if db().shared[encounterID] and db().use[encounterID] ~= "own" then
        return "raid"
    elseif db().own[encounterID] then
        return "own"
    elseif CRT.PaceDB.bosses[encounterID] then
        return "shipped"
    end
    return nil
end

function Pace:Plan(encounterID)
    local source = self:Source(encounterID)
    if source == "raid" then
        return db().shared[encounterID]
    elseif source == "own" then
        return db().own[encounterID]
    elseif source == "shipped" then
        return CRT.PaceDB.bosses[encounterID]
    end
    return nil
end

function Pace:Shared(encounterID)
    return encounterID and db().shared[encounterID] or nil
end

-- Which plan to use for a boss: "raid" or "own".
function Pace:SetUse(encounterID, use)
    db().use[encounterID] = (use == "own") and "own" or nil
    self:Fire()
end

function Pace:BossName(encounterID)
    local list = CRT.NoteReminders and CRT.NoteReminders.BossList and CRT.NoteReminders.BossList() or {}
    for _, b in ipairs(list) do
        if b.key == encounterID then
            return b.name or b.label
        end
    end
    return "encounter " .. tostring(encounterID)
end

function Pace:IsOwn(encounterID)
    return encounterID and db().own[encounterID] ~= nil or false
end

function Pace:IsShipped(encounterID)
    return encounterID and CRT.PaceDB.bosses[encounterID] ~= nil or false
end

-- Your own plan for a boss, made from the plan in use (or empty) the first time it is edited. Editing
-- always edits your own plan and makes it the one in use, so you see your change.
local function own(encounterID)
    local mine = db().own[encounterID]
    if not mine then
        mine = copyPlan(Pace:Plan(encounterID) or {})
        db().own[encounterID] = mine
    end
    if db().shared[encounterID] then
        db().use[encounterID] = "own"
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
    db().use[encounterID] = nil
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
-- from the pull. Rows of that phase (or all rows in time mode) are joined by straight lines. The boss
-- starts at 100% at the pull, so in time mode and in phase 1 a first row after 0:00 is reached by a
-- line from 100% at 0:00. A later phase doesn't start full, so before its first row it is that row's
-- value. After the last row it stays at the last row's. nil when there is no row.
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
    if pts[1].t > 0 and (plan.mode == "time" or ph == 1) then
        table.insert(pts, 1, { t = 0, hp = 100 })
    end
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

-- Reads plan text into a plan. Returns the plan and its number of rows, or nil and the reason.
local function parse(text)
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
    return plan, n
end

-- Replaces your own plan for a boss with pasted text, and uses it. Returns the number of rows, or nil
-- and the reason.
function Pace:Import(encounterID, text)
    local plan, n = parse(text)
    if not plan then
        return nil, n
    end
    db().own[encounterID] = plan
    if db().shared[encounterID] then
        db().use[encounterID] = "own"
    end
    self:Fire()
    return n
end

-- A plan shared by the raid leader or an assistant: saved as the raid's plan and put in use, leaving
-- your own plan as it is. Returns the number of rows, or nil and the reason.
function Pace:ReceiveShared(encounterID, text, from)
    local plan, n = parse(text)
    if not plan then
        return nil, n
    end
    plan.from, plan.at = from, time()
    db().shared[encounterID] = plan
    db().use[encounterID] = nil
    self:Fire()
    return n
end

-- Drops the raid's plan for a boss, going back to your own or the shipped one.
function Pace:ClearShared(encounterID)
    db().shared[encounterID] = nil
    db().use[encounterID] = nil
    self:Fire()
end
