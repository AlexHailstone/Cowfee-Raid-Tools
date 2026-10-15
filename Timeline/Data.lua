local ADDON, CRT = ...

-- Timeline: the saved pulls of each raid boss, for the Timeline page. This file is the store: it
-- keeps the last few pulls of every boss in CRTDB.timeline.bosses (a pull is when the boss spells
-- were cast and when players died, in seconds from the pull start), drops the oldest past the
-- keep limit, and answers the questions the page asks (the bosses, a boss's pulls, the deaths of
-- recent pulls). Everything is read from CRT.db.timeline fresh each time, so switching profile
-- gives the new profile's pulls. Change listeners are told when anything is saved or deleted.

local Timeline = { listeners = {} }
CRT.Timeline = Timeline

local function tdb()
    return CRT.db.timeline
end

function Timeline:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Timeline:Fire()
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

function Timeline:Settings()
    return tdb()
end

function Timeline:Set(field, value)
    tdb()[field] = value
    self:Fire()
end

-- Saves a finished pull under its boss, numbers it, and keeps only the newest `keep` of that boss.
function Timeline:SavePull(pull)
    local db = tdb()
    local boss = db.bosses[pull.encounterID]
    if not boss then
        boss = { name = pull.name, pulls = {} }
        db.bosses[pull.encounterID] = boss
    end
    boss.name = pull.name or boss.name
    pull.id = db.nextId
    db.nextId = db.nextId + 1
    boss.pulls[#boss.pulls + 1] = pull
    while #boss.pulls > (db.keep or 10) do
        table.remove(boss.pulls, 1)
    end
    self:Fire()
    return pull.id
end

-- Every boss with saved pulls, by name.
function Timeline:Bosses()
    local list = {}
    for encounterID, boss in pairs(tdb().bosses) do
        list[#list + 1] = { encounterID = encounterID, name = boss.name or "", count = #boss.pulls }
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.encounterID < b.encounterID
    end)
    return list
end

-- A boss's pulls, newest first.
function Timeline:Pulls(encounterID)
    local list = {}
    local boss = tdb().bosses[encounterID]
    if boss then
        for i = #boss.pulls, 1, -1 do
            list[#list + 1] = boss.pulls[i]
        end
    end
    return list
end

function Timeline:Pull(encounterID, id)
    local boss = tdb().bosses[encounterID]
    if boss then
        for _, pull in ipairs(boss.pulls) do
            if pull.id == id then
                return pull
            end
        end
    end
end

function Timeline:DeleteBoss(encounterID)
    tdb().bosses[encounterID] = nil
    self:Fire()
end

-- The deaths of pull fromID (the newest pull when nil) and of the count - 1 pulls saved before it,
-- newest first, for drawing earlier pulls' deaths over the shown one.
function Timeline:RecentDeaths(encounterID, count, fromID)
    local list = {}
    local boss = tdb().bosses[encounterID]
    if not boss then
        return list
    end
    local start = #boss.pulls
    if fromID then
        start = 0
        for i, pull in ipairs(boss.pulls) do
            if pull.id == fromID then
                start = i
            end
        end
    end
    for i = start, math.max(1, start - count + 1), -1 do
        local pull = boss.pulls[i]
        list[#list + 1] = { pull = pull, deaths = pull.deaths or {} }
    end
    return list
end

-- Keeps the deaths whose role is switched on (a death with role "NONE" is always kept), in time
-- order with deaths of unknown time last, and cuts to the first firstDeaths when that is above 0.
function Timeline.FilterDeaths(deaths, settings)
    local kept = {}
    for _, death in ipairs(deaths) do
        local role = death.role
        if role == nil or role == "NONE" or settings.roles[role] then
            kept[#kept + 1] = death
        end
    end
    table.sort(kept, function(a, b)
        if a.t == nil or b.t == nil then
            return a.t ~= nil and b.t == nil
        end
        return a.t < b.t
    end)
    local limit = settings.firstDeaths or 0
    if limit > 0 then
        for i = #kept, limit + 1, -1 do
            kept[i] = nil
        end
    end
    return kept
end
