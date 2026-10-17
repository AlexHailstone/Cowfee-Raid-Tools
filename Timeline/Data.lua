local ADDON, CRT = ...

-- Timeline: the saved pulls of each raid boss, for the Timeline page. This file is the store: it
-- keeps the last few pulls of every boss, per difficulty, in CRTDB.timeline.bosses (a pull is when the boss spells
-- were cast and when players died, in seconds from the pull start), drops the oldest past the
-- keep limit, and answers the questions the page asks (the bosses, a boss's pulls, the deaths of
-- recent pulls). Everything is read from CRT.db.timeline fresh each time, so switching profile
-- gives the new profile's pulls. Change listeners are told when anything is saved or deleted.
-- The bottom half records the pulls: during a raid boss fight it notes each boss spell when its
-- timeline event finishes, and after the fight (out of combat, when the game's damage meter has
-- stopped hiding values) it reads who died and what killed them, then saves the pull.

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
        -- A listener (the page) failing must never stop the recording.
        local ok, err = pcall(fn)
        if not ok and geterrorhandler then
            geterrorhandler()(err)
        end
    end
end

function Timeline:Settings()
    return tdb()
end

function Timeline:Set(field, value)
    tdb()[field] = value
    self:Fire()
end

-- The name of each group, as the dropdowns and messages show it.
Timeline.GROUP_NAMES = { nh = "Normal/Heroic", mythic = "Mythic" }

-- The difficulty group a difficultyID belongs to: Mythic (16) is "mythic", every other
-- difficulty (or none) is "nh" (Normal/Heroic).
function Timeline.DifficultyGroup(difficultyID)
    return difficultyID == 16 and "mythic" or "nh"
end

local groupOf = Timeline.DifficultyGroup

-- True when a pull belongs in the asked group; no group asks for every pull.
local function inGroup(pull, group)
    return group == nil or groupOf(pull.difficultyID) == group
end

-- Saves a finished pull under its boss, numbers it, and keeps only the newest `keep` pulls of its
-- difficulty group for that boss (the other group's pulls are never dropped).
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
    local group = groupOf(pull.difficultyID)
    local inGroupCount = 0
    for _, p in ipairs(boss.pulls) do
        if groupOf(p.difficultyID) == group then
            inGroupCount = inGroupCount + 1
        end
    end
    local keep = db.keep or 10
    local i = 1
    while inGroupCount > keep and i <= #boss.pulls do
        if groupOf(boss.pulls[i].difficultyID) == group then
            table.remove(boss.pulls, i)
            inGroupCount = inGroupCount - 1
        else
            i = i + 1
        end
    end
    self:Fire()
    return pull.id
end

-- Every boss with saved pulls, by name. With a group, count is that group's pull count (a boss
-- with pulls only in the other group is still listed, with count 0).
function Timeline:Bosses(group)
    local list = {}
    for encounterID, boss in pairs(tdb().bosses) do
        local count = #boss.pulls
        if group then
            count = 0
            for _, pull in ipairs(boss.pulls) do
                if inGroup(pull, group) then
                    count = count + 1
                end
            end
        end
        list[#list + 1] = { encounterID = encounterID, name = boss.name or "", count = count }
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.encounterID < b.encounterID
    end)
    return list
end

-- A boss's pulls, newest first; with a group, only that group's pulls.
function Timeline:Pulls(encounterID, group)
    local list = {}
    local boss = tdb().bosses[encounterID]
    if boss then
        for i = #boss.pulls, 1, -1 do
            if inGroup(boss.pulls[i], group) then
                list[#list + 1] = boss.pulls[i]
            end
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
-- newest first, for drawing earlier pulls' deaths over the shown one. With a group, only that
-- group's pulls are counted and walked.
function Timeline:RecentDeaths(encounterID, count, fromID, group)
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
    for i = start, 1, -1 do
        if #list >= count then
            break
        end
        local pull = boss.pulls[i]
        if inGroup(pull, group) then
            list[#list + 1] = { pull = pull, deaths = pull.deaths or {} }
        end
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

-- Recording ---------------------------------------------------------------------------------------

local READ_DELAY = 1 -- seconds after combat ends before reading, so the meter has the whole fight
local RETRY_DELAY = 2
local RETRIES = 5

local function enum(group, key, fallback)
    local e = Enum and Enum[group]
    return (e and e[key]) or fallback
end

-- The values from the game's documentation, used if the Enum table is missing.
local CURRENT = enum("DamageMeterSessionType", "Current", 1)
local DEATHS = enum("DamageMeterType", "Deaths", 9)
local ENCOUNTER = enum("EncounterTimelineEventSource", "Encounter", 0)
local FINISHED = enum("EncounterTimelineEventState", "Finished", 2)
local CANCELED = enum("EncounterTimelineEventState", "Canceled", 3)

-- False for a secret value, which can't be compared, used as a key or added up.
local function readable(v)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then
            return false
        end
    end
    return true
end
Timeline.readable = readable

-- Seconds to a tenth (Lua 5.1 has no math.round).
local function round1(x)
    return math.floor(x * 10 + 0.5) / 10
end

local current -- the pull being recorded: its fields plus startTime and pending = { [eventID] = { dur, spellID } }
local awaiting = {} -- ended pulls waiting for combat to end before their deaths are read
local unsaved = {} -- every ended pull not yet saved (waiting, in READ_DELAY or retrying)
local done = setmetatable({}, { __mode = "k" }) -- pulls already saved, so queued callbacks skip them

function Timeline:Recording()
    return current
end

local function inRaid()
    local ok, _, kind = pcall(GetInstanceInfo)
    return ok and kind == "raid"
end

-- Role of everyone in the group, by GUID and by name.
local function groupRoles()
    local byGuid, byName = {}, {}
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
    else
        units[1] = "player"
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    end
    for _, unit in ipairs(units) do
        local ok, role = pcall(UnitGroupRolesAssigned, unit)
        if ok and type(role) == "string" and readable(role) then
            local okGuid, guid = pcall(UnitGUID, unit)
            if okGuid and readable(guid) and guid then
                byGuid[guid] = role
            end
            local okName, name = pcall(UnitName, unit)
            if okName and type(name) == "string" and readable(name) then
                byName[name] = role
            end
        end
    end
    return byGuid, byName
end

-- The spell that killed a player: the first readable spell in their death recap (the game lists
-- recap events newest first, so the first is the killing blow), else the first spell the meter
-- marks as deadly, else 0.
local function killingBlow(recapID, sourceGUID)
    local ok, events = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if ok and type(events) == "table" then
        for i = 1, #events do
            local id = events[i] and events[i].spellId
            if readable(id) and id and type(id) == "number" and id > 0 then
                return id
            end
        end
    end
    if readable(sourceGUID) and sourceGUID then
        local okSrc, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, CURRENT, DEATHS, sourceGUID)
        if okSrc and type(src) == "table" and type(src.combatSpells) == "table" then
            for _, spell in ipairs(src.combatSpells) do
                local id, deadly = spell.spellID, spell.isDeadly
                if readable(deadly) and deadly and readable(id) and id and type(id) == "number" then
                    return id
                end
            end
        end
    end
    return 0
end

-- The deaths in the meter's current session. The second return is true when a name or a time was
-- still secret.
local function readDeaths()
    local deaths, secret = {}, false
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, CURRENT, DEATHS)
    if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then
        return deaths, false
    end
    local byGuid, byName = groupRoles()
    for _, src in ipairs(session.combatSources) do
        local recapID = src.deathRecapID
        if readable(recapID) and recapID and type(recapID) == "number" and recapID ~= 0 then
            local death = { recapID = recapID }
            local name = src.name
            if type(name) == "string" and readable(name) then
                death.name = name
            else
                secret = true
            end
            local class = src.classFilename
            if type(class) == "string" and readable(class) then
                death.class = class
            end
            local at = src.deathTimeSeconds
            if type(at) == "number" and readable(at) and at >= 0 then
                death.t = round1(at)
            else
                secret = true
            end
            local guid = src.sourceGUID
            local role = readable(guid) and guid and byGuid[guid]
            death.role = role or (death.name and byName[death.name]) or "NONE"
            death.spellID = killingBlow(recapID, guid)
            deaths[#deaths + 1] = death
        end
    end
    return deaths, secret
end

-- Saves an ended pull once. A saved pull ignores any timer or regen callback still queued for it.
local function save(pull)
    if done[pull] then
        return
    end
    done[pull] = true
    pull.startTime = nil
    pull.pending = nil
    for i, p in ipairs(awaiting) do
        if p == pull then
            table.remove(awaiting, i)
            break
        end
    end
    for i, p in ipairs(unsaved) do
        if p == pull then
            table.remove(unsaved, i)
            break
        end
    end
    Timeline:SavePull(pull)
end

-- Reads the deaths into the ended pull and saves it, trying again while values are still secret.
local function finish(pull, attempt)
    if done[pull] then
        return
    end
    local deaths, secret = readDeaths()
    pull.deaths = deaths -- kept as the last completed read, in case a new pull forces a save
    if secret and attempt < RETRIES then
        C_Timer.After(RETRY_DELAY, function()
            finish(pull, attempt + 1)
        end)
        return
    end
    save(pull)
end

local function scheduleRead(pull)
    C_Timer.After(READ_DELAY, function()
        finish(pull, 0)
    end)
end

-- Saves every ended pull still waiting for its death read, with the deaths of its last completed
-- read. Used when new combat starts, because the meter's current session then becomes the new
-- fight's.
local function saveUnsaved()
    for i = #unsaved, 1, -1 do
        if unsaved[i] then
            save(unsaved[i])
        end
    end
end

local function startPull(encounterID, name, difficultyID)
    saveUnsaved()
    current = nil
    if not tdb().record or not inRaid() or not readable(encounterID) or type(encounterID) ~= "number" then
        return
    end
    current = {
        encounterID = encounterID,
        name = readable(name) and name or nil,
        difficultyID = readable(difficultyID) and difficultyID or nil,
        startedAt = time(),
        startTime = GetTime(),
        pending = {},
        casts = {},
        deaths = {},
    }
end

local function endPull(encounterID, success)
    local pull = current
    if not pull or not readable(encounterID) or encounterID ~= pull.encounterID then
        return
    end
    current = nil
    pull.length = round1(GetTime() - pull.startTime)
    pull.kill = readable(success) and success == 1
    if pull.length < (tdb().minPull or 15) then
        return
    end
    unsaved[#unsaved + 1] = pull
    if InCombatLockdown() then
        awaiting[#awaiting + 1] = pull
    else
        scheduleRead(pull)
    end
end

local function eventState(eventID)
    local ok, state = pcall(C_EncounterTimeline.GetEventState, eventID)
    if ok and readable(state) and state ~= nil then
        return state
    end
end

-- The driver's OnEvent body, exposed so tests can drive it.
function Timeline.HandleEvent(event, ...)
    if event == "ENCOUNTER_START" then
        startPull(...)
    elseif event == "ENCOUNTER_END" then
        local encounterID, _, _, _, success = ...
        endPull(encounterID, success)
    elseif event == "PLAYER_REGEN_DISABLED" then
        saveUnsaved()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local list = awaiting
        awaiting = {}
        for _, pull in ipairs(list) do
            scheduleRead(pull)
        end
    elseif current then
        local pending = current.pending
        if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
            local info = ...
            if type(info) == "table" and info.source == ENCOUNTER and info.id ~= nil then
                local spell = info.spellID
                pending[info.id] = { dur = info.duration, spellID = readable(spell) and spell or 0 }
            end
        elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
            local eventID = ...
            local entry = pending[eventID]
            if entry then
                local state = eventState(eventID)
                if state == FINISHED then
                    local casts = current.casts
                    casts[#casts + 1] = { t = round1(GetTime() - current.startTime), dur = entry.dur, spellID = entry.spellID }
                    pending[eventID] = nil
                elseif state == CANCELED then
                    pending[eventID] = nil
                end
            end
        elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
            local eventID = ...
            pending[eventID] = nil
        end
    end
end

local driver = CreateFrame("Frame")
for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_TIMELINE_EVENT_ADDED", "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", "ENCOUNTER_TIMELINE_EVENT_REMOVED" }) do
    driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function(_, event, ...)
    Timeline.HandleEvent(event, ...)
end)
