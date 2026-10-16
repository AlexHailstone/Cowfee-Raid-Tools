local ADDON, CRT = ...

-- The late tracker. A raid night starts from the weekly schedule or from "Start raid now". Everyone
-- in the chosen Raid Groups layout who is not in your group at the start is late, and their clock
-- runs until they join. If they never join, it stops when the raid ends: the group disbands, End raid
-- is pressed, or MAX_HOURS pass. Only the first join counts. The running night is saved in
-- CRTDB.late.current so it survives a reload, and finished nights go to CRTDB.late.history.
-- Times are time() values, so the schedule follows this computer's clock.

local Late = { listeners = {} }
CRT.Late = Late

local MAX_HOURS = 8 -- a night still running after this long ends on its own
local AUTO_WINDOW = 5 * 60 -- a scheduled start only fires this soon after the start time
local CHECK_EVERY = 5 -- seconds between schedule and roster checks
local DISBAND_DELAY = 3 -- seconds out of a group before the night counts as disbanded

local function ldb()
    return CRT.db.late
end

function Late:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Late:Fire()
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

function Late:Settings()
    return ldb()
end

function Late:Set(field, value)
    ldb()[field] = value
    self:Fire()
end

function Late:SetDay(wday, on)
    ldb().days[wday] = on or nil
    self:Fire()
end

function Late:Current()
    return ldb().current
end

function Late:History()
    return ldb().history
end

-- Schedule ---------------------------------------------------------------

local function dayKey(t)
    return date("%Y-%m-%d", t)
end

-- The scheduled start on the day of t, or nil if that is not a raid day.
local function scheduledStart(t)
    local s = ldb()
    local d = date("*t", t)
    if not s.days[d.wday] then
        return nil
    end
    return time({ year = d.year, month = d.month, day = d.day, hour = s.hour, min = s.minute, sec = 0 })
end

-- The next scheduled start from now, within a week, or nil when no day is ticked.
function Late:NextScheduled(now)
    now = now or time()
    for i = 0, 7 do
        local start = scheduledStart(now + i * 86400)
        if start and start >= now then
            return start
        end
    end
    return nil
end

-- The night --------------------------------------------------------------

-- Lowercased, de-duplicated names from the expected layout, or nil and a reason.
local function expectedKeys()
    local s = ldb()
    local preset = s.layoutId and CRT.Groups:Find(s.layoutId)
    if not preset then
        return nil, "Pick the expected roster on the Late Tracker page first."
    end
    local keys, seen = {}, {}
    for i = 1, CRT.Groups.NUM_SLOTS do
        local key = preset.slots[i]
        if key and key ~= "" and not seen[key:lower()] then
            seen[key:lower()] = true
            keys[#keys + 1] = key
        end
    end
    if #keys == 0 then
        return nil, "The expected roster '" .. preset.name .. "' has no names in it."
    end
    return keys, preset.name
end

-- Marks everyone now in your group as joined at the time given. Only the first join counts.
function Late:Scan(at)
    local night = ldb().current
    if not night then
        return
    end
    local lookup = CRT.Groups.MakeLookup(CRT.Groups:ReadRoster())
    local changed = false
    for _, p in ipairs(night.players) do
        if not p.joinedAt and lookup(p.key) then
            p.joinedAt = at
            changed = true
        end
    end
    if changed then
        self:Fire()
    end
end

-- how is "schedule" or "button". A running night is replaced, not kept.
function Late:Start(how, startedAt)
    local keys, nameOrError = expectedKeys()
    if not keys then
        CRT:Print(nameOrError)
        return false
    end
    local s = ldb()
    local night = {
        id = s.nextId,
        startedAt = startedAt,
        how = how,
        layout = nameOrError,
        grace = s.grace,
        hadGroup = IsInGroup() and true or false,
        players = {},
    }
    s.nextId = s.nextId + 1
    for _, key in ipairs(keys) do
        night.players[#night.players + 1] = { key = key }
    end
    s.current = night
    -- A start by hand on a raid day replaces that day's scheduled start.
    s.lastAuto = dayKey(startedAt)
    self:Scan(startedAt)
    self:Fire()
    return true
end

-- reason is "disband", "button", "timeout" or "offline".
function Late:End(reason, at)
    local s = ldb()
    local night = s.current
    if not night then
        return
    end
    night.endedAt = at
    night.endReason = reason
    for _, p in ipairs(night.players) do
        if not p.joinedAt then
            p.never = true
        end
    end
    s.history[#s.history + 1] = night
    s.current = nil
    self:Fire()
end

-- Editing tonight's roster: the list starts as the expected Raid Groups layout, and these change it
-- for the running night only, never the layout itself.

local function findPlayer(night, key)
    local lower = key:lower()
    for i, p in ipairs(night.players) do
        if p.key:lower() == lower then
            return i, p
        end
    end
end

-- Adds someone who should be here tonight. If they are in your group now, they count as joined now.
-- Returns false and a reason when nothing changed.
function Late:AddPlayer(key)
    local night = ldb().current
    key = CRT.Groups.Normalize(key or "")
    if not night then
        return false, "No raid night is running."
    end
    if key == "" then
        return false, "Type a name first."
    end
    if findPlayer(night, key) then
        return false, Ambiguate(key, "none") .. " is already on tonight's list."
    end
    night.players[#night.players + 1] = { key = key, added = true }
    self:Scan(time())
    self:Fire()
    return true
end

-- Takes someone off tonight's list, so they don't count as late or missing.
function Late:RemovePlayer(key)
    local night = ldb().current
    local i = night and findPlayer(night, key)
    if i then
        table.remove(night.players, i)
        self:Fire()
    end
end

-- Counts someone as here on time, for a player who was here under another name or excused.
function Late:SetOnTime(key)
    local night = ldb().current
    if not night then
        return
    end
    local _, p = findPlayer(night, key)
    if p then
        p.joinedAt = night.startedAt
        p.never = nil
        self:Fire()
    end
end

function Late:Delete(id)
    local history = ldb().history
    for i, night in ipairs(history) do
        if night.id == id then
            table.remove(history, i)
            self:Fire()
            return
        end
    end
end

function Late:Find(id)
    for _, night in ipairs(ldb().history) do
        if night.id == id then
            return night
        end
    end
end

-- Seconds a player was late, from the start until they joined, or until the night ended or now.
function Late.Seconds(night, p, now)
    local stop = p.joinedAt or night.endedAt or now or time()
    return math.max(0, stop - night.startedAt)
end

-- Late means joined (or still missing) more than the night's grace minutes after the start.
function Late.IsLate(night, p, now)
    return Late.Seconds(night, p, now) > (night.grace or 0) * 60
end

-- One row per player across all saved nights: nights expected, nights late, nights never joined, and
-- total seconds late. Sorted most late first.
function Late:Totals()
    local byKey, out = {}, {}
    for _, night in ipairs(ldb().history) do
        for _, p in ipairs(night.players) do
            local lower = p.key:lower()
            local t = byKey[lower]
            if not t then
                t = { key = p.key, nights = 0, late = 0, never = 0, seconds = 0 }
                byKey[lower] = t
                out[#out + 1] = t
            end
            t.nights = t.nights + 1
            if Late.IsLate(night, p) then
                t.late = t.late + 1
                t.seconds = t.seconds + Late.Seconds(night, p)
                if p.never then
                    t.never = t.never + 1
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.late ~= b.late then
            return a.late > b.late
        end
        if a.seconds ~= b.seconds then
            return a.seconds > b.seconds
        end
        return a.key:lower() < b.key:lower()
    end)
    return out
end

-- Checks ------------------------------------------------------------------

function Late:Tick()
    local s = ldb()
    local now = time()
    local night = s.current
    if night then
        if now - night.startedAt >= MAX_HOURS * 3600 then
            self:End("timeout", night.startedAt + MAX_HOURS * 3600)
        else
            if IsInGroup() then
                night.hadGroup = true
            end
            self:Scan(now)
        end
        return
    end
    local today = dayKey(now)
    if s.lastAuto == today then
        return
    end
    local start = scheduledStart(now)
    if not start or now < start then
        return
    end
    if now - start <= AUTO_WINDOW and IsInGroup() then
        if self:Start("schedule", start) then
            CRT:Print("Raid night started from the schedule. Late Tracker: /crt late")
        else
            s.lastAuto = today
        end
    elseif now - start > AUTO_WINDOW then
        -- Without a group at the start time there is no way to tell who was on time.
        s.lastAuto = today
        CRT:Print(format("Tonight's %s start passed while you were not in a group, so it is not tracked. Press Start raid now on the Late Tracker page to track from now.", date("%H:%M", start)))
    end
end

local disbandToken = 0

local function onRosterUpdate()
    local night = ldb().current
    if not night then
        return
    end
    if IsInGroup() then
        night.hadGroup = true
        Late:Scan(time())
        return
    end
    if not night.hadGroup then
        return
    end
    -- Wait a moment so a loading screen or a brief roster gap does not end the night.
    disbandToken = disbandToken + 1
    local token = disbandToken
    local leftAt = time()
    C_Timer.After(DISBAND_DELAY, function()
        if token == disbandToken and ldb().current == night and not IsInGroup() then
            Late:End("disband", leftAt)
            CRT:Print("The raid group disbanded, so tonight's late tracking ended.")
        end
    end)
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.NewTicker(CHECK_EVERY, function()
            Late:Tick()
        end)
        -- If the group disbanded while you were logged out, end the night now.
        C_Timer.After(10, function()
            local night = ldb().current
            if night and night.hadGroup and not IsInGroup() then
                Late:End("offline", time())
            end
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        onRosterUpdate()
    end
end)
