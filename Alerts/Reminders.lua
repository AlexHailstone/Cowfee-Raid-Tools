local ADDON, CRT = ...

-- Your own reminders: a timed alert you save for a boss. Its times come from the boss's reference
-- timeline (the cast schedule of one ability, converted to a phase and seconds into it) or from times
-- you type, and it runs on the alerts engine as the "mine" block beside the raid note. A reminder is
-- saved in CRT.db.alerts.reminders[encounterID][id] as
--   { boss, spellID, text, times, outputs = { alert, bar, speech, text, icon, circle }, warn, speech,
--     priority, difficulty, enabled, linger, sound, glow, iconID, color }
-- where `times` is typed text ("P1 0:02, 1:17; P2 +0:18") or nil for the reference, `speech` is
-- "text", "textcount" (the text, then 3, 2, 1) or "count", and `difficulty` nil means any.

local Alerts = CRT.Alerts
local Rules = CRT.AlertRules

local Reminders = {}
CRT.AlertReminders = Reminders

local BLOCK = "mine"

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

local function copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = copy(x)
    end
    return out
end

-- The first number in a phase label: "P1.5" gives 1.5, "Phase 2" gives 2, "Intermission" nil.
function Reminders.PhaseNumber(label)
    if type(label) ~= "string" then
        return nil
    end
    local num = label:match("%d+%.%d+") or label:match("%d+")
    return num and tonumber(num) or nil
end

-- The phase and the seconds into it of a time t from the pull: the phase is that of the last numbered
-- phase line at or before t (1 before any), and the seconds count from that line (from the pull before
-- any). With no reference (a recorded pull) it is phase 1 from the pull.
function Reminders.PhaseAt(ref, t)
    local ph, from = 1, 0
    for _, p in ipairs(ref and ref.phases or {}) do
        local n = Reminders.PhaseNumber(p.label)
        if n and type(p.t) == "number" and p.t <= t then
            ph, from = n, p.t
        end
    end
    return ph, t - from
end

-- The reverse of PhaseAt: the time from the pull of seconds into phase ph, through the reference's
-- first phase line of that number. Phase 1 always counts from the pull, as PhaseAt does before any
-- numbered line (a later line whose label carries a 1, "Intermission 1", doesn't move it). Nil for a
-- phase the reference doesn't have, and for any phase above 1 with no reference (a recorded pull,
-- whose phase times aren't known).
function Reminders.AbsoluteTime(ref, ph, seconds)
    if type(ph) ~= "number" or type(seconds) ~= "number" then
        return nil
    end
    if ph == 1 then
        return seconds
    end
    for _, p in ipairs(ref and ref.phases or {}) do
        if type(p.t) == "number" and Reminders.PhaseNumber(p.label) == ph then
            return p.t + seconds
        end
    end
    return nil
end

-- The casts of a reference row as { ph, t }, each through PhaseAt.
function Reminders.FromReference(ref, row)
    local out = {}
    if not (ref and row) then
        return out
    end
    for _, cast in ipairs(row.casts or {}) do
        local ph, t = Reminders.PhaseAt(ref, cast.t)
        out[#out + 1] = { ph = ph, t = t }
    end
    return out
end

-- "P1 0:02, 1:17; P2 +0:18" into { { ph, t } }. Groups split by ";", each an optional P<number> and
-- then times split by ",". A time may carry tenths ("3:13.5", "193.5"), as a click on the Timeline
-- gives. Returns nil and a message naming the bad part.
local function parseTime(s)
    local t = CRT.TimelineReference.ParseTime(s)
    if t then
        return t
    end
    s = trim(s)
    local m, sec = s:match("^(%d+):(%d%d%.%d+)$")
    if m and tonumber(sec) < 60 then
        return tonumber(m) * 60 + tonumber(sec)
    end
    if s:match("^%d+%.%d+$") then
        return tonumber(s)
    end
    return nil
end

function Reminders.ParseTimes(text)
    if type(text) ~= "string" then
        return nil, "no times"
    end
    local parse = parseTime
    local out = {}
    for group in (text .. ";"):gmatch("([^;]*);") do
        group = trim(group)
        if group ~= "" then
            local ph, rest = 1, group
            if group:match("^[Pp]") then
                local num, after = group:match("^[Pp]%s*(%d+%.?%d*)%s*(.*)$")
                if not num then
                    return nil, "bad phase '" .. group .. "'"
                end
                ph, rest = tonumber(num), after
            end
            local label = "P" .. tostring(ph)
            local count = 0
            for tok in (rest .. ","):gmatch("([^,]*),") do
                tok = trim(tok)
                if tok ~= "" then
                    local t = parse((tok:gsub("^%+%s*", "")))
                    if not t then
                        return nil, "bad time '" .. tok .. "' in " .. label
                    end
                    out[#out + 1] = { ph = ph, t = t }
                    count = count + 1
                end
            end
            if count == 0 then
                return nil, "no times in " .. label
            end
        end
    end
    if #out == 0 then
        return nil, "no times"
    end
    return out
end

-- m:ss, or m:ss.s when the time has tenths.
local function clock(t)
    t = math.floor(t * 10 + 0.5) / 10
    if t == math.floor(t) then
        return string.format("%d:%02d", math.floor(t / 60), t % 60)
    end
    local m = math.floor(t / 60)
    return string.format("%d:%04.1f", m, t - m * 60)
end

-- The reverse of ParseTimes: phases in order, as "P1 0:02, 1:17; P2 +0:18".
function Reminders.FormatTimes(list)
    local phases, byPhase = {}, {}
    for _, e in ipairs(list or {}) do
        if not byPhase[e.ph] then
            byPhase[e.ph] = {}
            phases[#phases + 1] = e.ph
        end
        local g = byPhase[e.ph]
        g[#g + 1] = (e.ph == 1 and "" or "+") .. clock(e.t)
    end
    table.sort(phases)
    local parts = {}
    for _, ph in ipairs(phases) do
        parts[#parts + 1] = "P" .. tostring(ph) .. " " .. table.concat(byPhase[ph], ", ")
    end
    return table.concat(parts, "; ")
end

-- Saved reminders ----------------------------------------------------------------------------

local function store(create)
    local db = Alerts:Settings()
    if not db then
        return nil
    end
    if create and type(db.reminders) ~= "table" then
        db.reminders = {}
    end
    return db.reminders
end

function Reminders:Get(encounterID, id)
    local all = store()
    local list = all and all[encounterID]
    return list and list[id] or nil
end

-- { { id, r } } for a boss, oldest id first.
function Reminders:List(encounterID)
    local out = {}
    local all = store()
    for id, r in pairs(all and all[encounterID] or {}) do
        out[#out + 1] = { id = id, r = r }
    end
    table.sort(out, function(a, b)
        return a.id < b.id
    end)
    return out
end

-- Saves a copy of r with the defaults filled in. id nil makes a new reminder. Returns the id.
function Reminders:Save(encounterID, id, r)
    local all = store(true)
    local db = Alerts:Settings()
    if not (all and db) then
        return nil
    end
    local saved = copy(r)
    for _, k in ipairs({ "difficulty", "boss" }) do
        if type(saved[k]) ~= "string" or trim(saved[k]) == "" then
            saved[k] = nil
        end
    end
    if saved.times ~= nil and trim(saved.times) == "" then
        saved.times = nil
    end
    saved.outputs = saved.outputs or {}
    for _, k in ipairs({ "alert", "bar", "speech" }) do
        if saved.outputs[k] == nil then
            saved.outputs[k] = true
        end
    end
    saved.warn = saved.warn or 5
    saved.speech = saved.speech or "text"
    saved.priority = saved.priority or "normal"
    if saved.enabled == nil then
        saved.enabled = true
    end
    if not id then
        id = db.nextId or 1
        db.nextId = id + 1
    end
    all[encounterID] = all[encounterID] or {}
    all[encounterID][id] = saved
    Alerts:Fire()
    return id
end

function Reminders:Delete(encounterID, id)
    local all = store()
    if all and all[encounterID] then
        all[encounterID][id] = nil
    end
    Alerts:Fire()
end

-- base with the overrides[blockKey][entryID] fields laid over it. Never writes into base.
function Reminders:Effective(blockKey, entryID, base)
    local out = copy(base or {})
    local db = Alerts:Settings()
    local over = db and db.overrides and db.overrides[blockKey] and db.overrides[blockKey][entryID]
    if type(over) == "table" then
        for k, v in pairs(over) do
            if type(v) == "table" and type(out[k]) == "table" then
                for k2, v2 in pairs(v) do
                    out[k][k2] = copy(v2)
                end
            else
                out[k] = copy(v)
            end
        end
    end
    return out
end

-- Times --------------------------------------------------------------------------------------

local function lower(s)
    return trim(s):lower()
end

-- The reference of the boss to use: the one of the reminder's difficulty, else the first.
local function referenceFor(encounterID, r)
    local ref = CRT.TimelineReference
    if not ref then
        return nil
    end
    local found = ref:ForBoss(encounterID, r.boss)
    if #found == 0 then
        return nil
    end
    if r.difficulty then
        for _, entry in ipairs(found) do
            if entry.ref.difficulty and lower(entry.ref.difficulty) == lower(r.difficulty) then
                return entry.ref
            end
        end
    end
    return found[1].ref
end

Reminders.ReferenceFor = referenceFor

local function spellName(id)
    if type(id) ~= "number" or id <= 0 or not (C_Spell and C_Spell.GetSpellName) then
        return nil
    end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" and readable(name) and name ~= "" then
        return name
    end
    return nil
end

Reminders.SpellName = spellName

-- The row of a reference for a reminder: by spell ID (a row's own [spell] or its Journal spell), else
-- by name (the spell's name or the reminder's text).
local function rowFor(ref, encounterID, r)
    local rows
    if CRT.TimelineJournal then
        local ok, res = pcall(CRT.TimelineJournal.Rows, CRT.TimelineJournal, encounterID)
        rows = ok and res or nil
    end
    local want = type(r.spellID) == "number" and r.spellID > 0 and r.spellID or nil
    if want and CRT.TimelineLanes then
        for _, row in ipairs(ref.rows or {}) do
            local ok, id = pcall(CRT.TimelineLanes.RowSpell, row, encounterID, rows or {})
            if ok and id == want then
                return row
            end
        end
    end
    local names = {}
    local sn = spellName(r.spellID)
    if sn then
        names[lower(sn)] = true
    end
    if trim(r.text) ~= "" then
        names[lower(r.text)] = true
    end
    for _, row in ipairs(ref.rows or {}) do
        if names[lower(row.name)] then
            return row
        end
    end
end

-- The times of a reminder: { { ph, t } } and where they came from ("typed", "reference" or "none").
-- Typed text that does not read gives {}, "typed" and the message.
function Reminders:Times(encounterID, r)
    if type(r.times) == "string" and trim(r.times) ~= "" then
        local list, err = Reminders.ParseTimes(r.times)
        if not list then
            return {}, "typed", err
        end
        return list, "typed"
    end
    local ref = referenceFor(encounterID, r)
    local row = ref and rowFor(ref, encounterID, r)
    if row then
        return Reminders.FromReference(ref, row), "reference"
    end
    return {}, "none"
end

-- Moves one time of a reminder (index in the list Times gives) to phase ph, t seconds in, or adds that
-- time. The times are saved as typed text, so a reminder that followed the reference now holds its own
-- list; every other field stays. False when the reminder, its time or its typed times can't be read.
local function writeTimes(encounterID, id, change)
    local r = Reminders:Get(encounterID, id)
    if not r then
        return false
    end
    local list, source = Reminders:Times(encounterID, r)
    if source == "typed" and #list == 0 then
        return false
    end
    if not change(list) then
        return false
    end
    local saved = copy(r)
    saved.times = Reminders.FormatTimes(list)
    return Reminders:Save(encounterID, id, saved) ~= nil
end

function Reminders:SetTime(encounterID, id, index, ph, t)
    if type(ph) ~= "number" or type(t) ~= "number" then
        return false
    end
    return writeTimes(encounterID, id, function(list)
        if not list[index] then
            return false
        end
        list[index] = { ph = ph, t = t }
        return true
    end)
end

function Reminders:AddTime(encounterID, id, ph, t)
    if type(ph) ~= "number" or type(t) ~= "number" then
        return false
    end
    return writeTimes(encounterID, id, function(list)
        list[#list + 1] = { ph = ph, t = t }
        return true
    end)
end

-- The block -----------------------------------------------------------------------------------

-- A run with anyDifficulty (the Phases tab asking which phases a boss has) takes every difficulty.
local function matchesDifficulty(r, run)
    if not r.difficulty or run.anyDifficulty then
        return true
    end
    return type(run.difficultyName) == "string" and lower(run.difficultyName) == lower(r.difficulty)
end

local function speechList(r, text)
    local mode = r.speech
    return Rules.SpeechItems(text, r.warn or 5, mode ~= "count", mode == "textcount" or mode == "count")
end

-- The alert items of one reminder (r with any overrides already laid over it), one per time. Used by
-- the block and by the editor's Test, which runs a reminder that is not saved.
-- difficulty is not checked here; the block does that.
function Reminders:Items(encounterID, id, r)
    local out = {}
    local times = Reminders:Times(encounterID, r)
    local icon
    if type(r.iconID) == "number" and r.iconID > 0 then
        icon = r.iconID
    elseif type(r.spellID) == "number" and r.spellID > 0 and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, r.spellID)
        if ok and tex ~= nil and readable(tex) then
            icon = tex
        end
    end
    local text
    if type(r.text) == "string" and trim(r.text) ~= "" then
        text = r.text
    else
        text = spellName(r.spellID)
        if not text then
            local hasSpell = type(r.spellID) == "number" and r.spellID > 0
            text = hasSpell and ("Spell " .. tostring(r.spellID)) or "Reminder"
        end
    end
    local o = r.outputs or {}
    for n, t in ipairs(times) do
        out[#out + 1] = {
            id = "mine:" .. tostring(id) .. ":" .. n,
            ph = t.ph,
            time = t.t,
            spellID = r.spellID,
            icon = icon,
            text = text,
            priority = Rules.Priority(3, r.priority),
            warn = r.warn or 5,
            hold = math.max(0.5, type(r.linger) == "number" and r.linger or 0),
            color = r.color,
            sound = r.sound,
            glow = r.glow and true or nil,
            outputs = { alert = o.alert and true or false, bar = o.bar and true or false,
                speech = o.speech and true or false, text = o.text and true or false,
                icon = o.icon and true or false, circle = o.circle and true or false },
            speech = speechList(r, text),
        }
    end
    return out
end

local function entries(run)
    local out = {}
    if not (run and run.encounterID) then
        return out
    end
    for _, e in ipairs(Reminders:List(run.encounterID)) do
        local r = Reminders:Effective(BLOCK, e.id, e.r)
        if r.enabled ~= false and matchesDifficulty(r, run) then
            for _, item in ipairs(Reminders:Items(run.encounterID, e.id, r)) do
                out[#out + 1] = item
            end
        end
    end
    return out
end

Alerts:RegisterBlock(BLOCK, { label = "Your reminders", group = true, Entries = entries })
