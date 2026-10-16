local ADDON, CRT = ...

-- DEVELOPER ONLY. Finds out which boss timeline, boss cast, death and Journal values the game hides
-- from addons ("secret values" in Midnight). /crt dev probe turns it on for the next raid boss pull;
-- it logs, for every value, whether it was "secret", "readable", "missing" (nil) or "error" (the call
-- failed), at three moments: when the event fired, at ENCOUNTER_END, and once combat is left
-- (PLAYER_REGEN_ENABLED). Then it switches itself off and prints a summary. /crt dev probe show
-- prints the summary again.
--
-- The results go in CRTDB.dev.probe:
--   armedAt, encounterID
--   fields["<source>.<field>@<moment>"] = the last class seen
--   counts["<source>.<field>@<moment>"] = { secret = n, readable = n, missing = n, error = n }
-- The sources: added (ENCOUNTER_TIMELINE_EVENT_ADDED fields), getinfo (GetEventInfo, read again at the
-- end for each event ID seen), state (GetEventState), feature (IsFeatureEnabled), bosscast (spell casts
-- on boss1 to boss5), meter (Deaths meter fields), recap.self and recap.other (C_DeathRecap events),
-- deadly (the spells a dead player's meter entry lists) and ej (the Journal lookup of the pulled boss;
-- ej.match says whether it was found). added.prepull holds the timeline events that arrived while
-- armed but before ENCOUNTER_START. The phase event sources are logged while armed in a raid and
-- during the pull: emote and chatemote (RAID_BOSS_EMOTE and CHAT_MSG_RAID_BOSS_EMOTE: text, sender),
-- targetable (UNIT_TARGETABLE_CHANGED: unit, and canAttack, which is UnitCanAttack("player", unit)
-- read after it), engage (INSTANCE_ENCOUNTER_ENGAGE_UNIT: bossN.exists and bossN.guid for boss1 to
-- boss5) and other.<EVENT>.argN (the arguments of any other event whose name starts with
-- ENCOUNTER_TIMELINE_, caught with RegisterAllEvents while armed and during the pull, then
-- unregistered). A value is never compared or tested before the secret check says it is safe.
--
-- This file never ships: the .toc line that loads it is inside a do-not-package block.

local Probe = {}
CRT.TimelineProbe = Probe

local MOMENTS = { "event", "end", "ooc" }
local CLASSES = { "secret", "readable", "missing", "error" }
local BOSS_UNITS = { boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true }
local INFO_FIELDS = { "id", "source", "spellName", "spellID", "iconFileID", "duration", "maxQueueDuration",
    "icons", "severity", "isApproximate" }
local METER_FIELDS = { "sourceGUID", "sourceCreatureID", "name", "classFilename", "totalAmount", "isLocalPlayer",
    "deathRecapID", "deathTimeSeconds" }
local RECAP_FIELDS = { "spellId", "spellName", "amount", "school", "sourceName", "timestamp" }
local DEADLY_FIELDS = { "spellID", "totalAmount", "overkillAmount", "isDeadly" }
local EJ_FIELDS = { "name", "description", "journalEncounterID", "rootSectionID", "link", "journalInstanceID",
    "dungeonEncounterID", "instanceID" }
local EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_ENABLED", "ENCOUNTER_TIMELINE_EVENT_ADDED",
    "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", "RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_EMOTE",
    "UNIT_TARGETABLE_CHANGED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }
local HANDLED = {}
for _, e in ipairs(EVENTS) do
    HANDLED[e] = true
end
local TIMELINE_PREFIX = "ENCOUNTER_TIMELINE_"

local stage = "idle" -- idle, armed (waiting for a raid boss pull), pull, ended (waiting to leave combat)
local seenIDs = {}
local frame

local function probeData()
    local r = CRTDB or CRT.db
    return r and r.dev and r.dev.probe
end

-- The secret check comes first, inside pcall, so a secret value is never compared or tested.
local function classify(v)
    if not issecretvalue then
        return v == nil and "missing" or "readable"
    end
    local ok, secret = pcall(issecretvalue, v)
    if not ok then
        return "error"
    end
    if secret then
        return "secret"
    end
    if v == nil then
        return "missing"
    end
    return "readable"
end

local function bump(source, field, moment, class)
    local data = probeData()
    local key = source .. "." .. field .. "@" .. moment
    data.fields[key] = class
    local c = data.counts[key]
    if not c then
        c = { secret = 0, readable = 0, missing = 0, error = 0 }
        data.counts[key] = c
    end
    c[class] = c[class] + 1
end

local function record(source, field, moment, v)
    bump(source, field, moment, classify(v))
end

-- Records each named field of a table, or "missing" for all of them when there is no table.
local function recordFields(source, names, moment, t)
    local class = classify(t)
    local usable = class == "readable" and type(t) == "table"
    for _, name in ipairs(names) do
        if not usable then
            bump(source, name, moment, class == "readable" and "missing" or class)
        else
            local ok, v = pcall(function() return t[name] end)
            if ok then
                record(source, name, moment, v)
            else
                bump(source, name, moment, "error")
            end
        end
    end
end

-- Calls fn under pcall and returns its first result and true. A failed call is counted as an error
-- under source.field and returns nil, false, so the caller records nothing more for it.
local function call(source, field, moment, fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then
        bump(source, field, moment, "error")
        return nil, false
    end
    return v, true
end

-- Deaths meter, recaps and the dead players' spells. Run at the end and after combat.
local function readDeaths(moment)
    local sessionType = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local meterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths or 9
    local session, okSession = call("meter", "session", moment, function()
        return C_DamageMeter.GetCombatSessionFromType(sessionType, meterType)
    end)
    if not okSession then
        return
    end
    local sources = type(session) == "table" and session.combatSources
    if type(sources) ~= "table" then
        recordFields("meter", METER_FIELDS, moment, nil)
        return
    end
    local doneSelf, doneOther, doneDeadly = false, false, false
    for i = 1, math.min(#sources, 5) do
        local src = sources[i]
        recordFields("meter", METER_FIELDS, moment, src)
        if type(src) == "table" then
            local mine = src.isLocalPlayer
            local isSelf = classify(mine) == "readable" and mine and true or false
            local recapID = src.deathRecapID
            if classify(recapID) == "readable" and ((isSelf and not doneSelf) or (not isSelf and not doneOther)) then
                if isSelf then
                    doneSelf = true
                else
                    doneOther = true
                end
                local events, okEvents = call("recap", "events", moment, function()
                    return C_DeathRecap.GetRecapEvents(recapID)
                end)
                if okEvents then
                    recordFields(isSelf and "recap.self" or "recap.other", RECAP_FIELDS, moment,
                        type(events) == "table" and events[1] or nil) -- newest first: the killing blow
                end
            end
            if not doneDeadly then
                doneDeadly = true
                local detail, okDetail = call("deadly", "source", moment, function()
                    return C_DamageMeter.GetCombatSessionSourceFromType(sessionType, meterType, src.sourceGUID,
                        src.sourceCreatureID)
                end)
                if okDetail then
                    local spells = type(detail) == "table" and detail.combatSpells
                    if type(spells) == "table" and #spells > 0 then
                        for n = 1, math.min(#spells, 10) do
                            recordFields("deadly", DEADLY_FIELDS, moment, spells[n])
                        end
                    else
                        recordFields("deadly", DEADLY_FIELDS, moment, nil)
                    end
                end
            end
        end
    end
end

local function readFeature(moment)
    local enabled, ok = call("feature", "enabled", moment, function()
        return C_EncounterTimeline.IsFeatureEnabled()
    end)
    if ok then
        record("feature", "enabled", moment, enabled)
    end
end

-- Finds the pulled boss in the Journal. EJ_GetEncounterInfo takes a journal encounter ID, not the
-- dungeon encounter ID of the pull, so this walks the current raid's encounters by index and
-- compares the 7th return (dungeonEncounterID) with the pulled one. ej.match is "readable" when a
-- match is found and "missing" when none is. EJ_SelectInstance is never called.
local function readJournal(moment, encounterID)
    if classify(encounterID) ~= "readable" then
        bump("ej", "match", moment, "missing")
        return
    end
    local instanceID, okInst = call("ej", "instance", moment, function()
        return EJ_GetInstanceForMap(C_Map.GetBestMapForUnit("player"))
    end)
    if not okInst then
        return
    end
    local found = false
    if classify(instanceID) == "readable" and type(instanceID) == "number" and instanceID ~= 0 then
        for i = 1, 30 do
            local entry = { pcall(EJ_GetEncounterInfoByIndex, i, instanceID) }
            local journalID = entry[4]
            if not entry[1] or entry[2] == nil or classify(journalID) ~= "readable" or journalID == nil then
                break
            end
            local results = { pcall(EJ_GetEncounterInfo, journalID) }
            if results[1] then
                local dungeonID = results[8]
                if classify(dungeonID) == "readable" and dungeonID == encounterID then
                    found = true
                    for n, name in ipairs(EJ_FIELDS) do
                        record("ej", name, moment, results[n + 1])
                    end
                    break
                end
            end
        end
    end
    bump("ej", "match", moment, found and "readable" or "missing")
end

-- Reads every event ID seen again through GetEventInfo and GetEventState.
local function readSeen(moment)
    for id in pairs(seenIDs) do
        local info, okInfo = call("getinfo", "info", moment, function()
            return C_EncounterTimeline.GetEventInfo(id)
        end)
        if okInfo then
            recordFields("getinfo", INFO_FIELDS, moment, info)
        end
        local state, okState = call("state", "value", moment, function()
            return C_EncounterTimeline.GetEventState(id)
        end)
        if okState then
            record("state", "value", moment, state)
        end
    end
end

-- Registers the normal event list (after an UnregisterAllEvents).
local function registerNormal()
    for _, e in ipairs(EVENTS) do
        frame:RegisterEvent(e)
    end
end

-- Drops the catch-all: unregisters everything and registers the normal list again.
local function catchAllOff()
    if frame then
        frame:UnregisterAllEvents()
        registerNormal()
    end
end

local function disarm()
    stage = "idle"
    catchAllOff()
end

-- The phase event sources and any other ENCOUNTER_TIMELINE_ event. Returns true when the event was one
-- of them. Armed outside a raid it records nothing.
local function readPhaseSources(event, ...)
    local kind
    if event == "RAID_BOSS_EMOTE" or event == "CHAT_MSG_RAID_BOSS_EMOTE" or event == "UNIT_TARGETABLE_CHANGED"
        or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        kind = event
    elseif not HANDLED[event] and event:sub(1, #TIMELINE_PREFIX) == TIMELINE_PREFIX then
        kind = "other"
    else
        return false
    end
    if stage == "armed" then
        local okType, _, instanceType = pcall(GetInstanceInfo)
        if not okType or instanceType ~= "raid" then
            return true
        end
    end
    if kind == "other" then
        local n = select("#", ...)
        if n == 0 then
            bump("other", event .. ".args", "event", "missing")
        end
        for i = 1, n do
            record("other", event .. ".arg" .. i, "event", (select(i, ...)))
        end
    elseif kind == "RAID_BOSS_EMOTE" or kind == "CHAT_MSG_RAID_BOSS_EMOTE" then
        local source = kind == "RAID_BOSS_EMOTE" and "emote" or "chatemote"
        local text, sender = ...
        record(source, "text", "event", text)
        record(source, "sender", "event", sender)
    elseif kind == "UNIT_TARGETABLE_CHANGED" then
        local unit = ...
        record("targetable", "unit", "event", unit)
        if classify(unit) == "readable" and type(unit) == "string" then
            local canAttack, ok = call("targetable", "canAttack", "event", UnitCanAttack, "player", unit)
            if ok then
                record("targetable", "canAttack", "event", canAttack)
            end
        end
    else
        for i = 1, 5 do
            local unit = "boss" .. i
            local exists, okExists = call("engage", unit .. ".exists", "event", UnitExists, unit)
            if okExists then
                record("engage", unit .. ".exists", "event", exists)
            end
            local guid, okGuid = call("engage", unit .. ".guid", "event", UnitGUID, unit)
            if okGuid then
                record("engage", unit .. ".guid", "event", guid)
            end
        end
    end
    return true
end

function Probe.HandleEvent(event, ...)
    if stage == "idle" or not probeData() then
        return
    end
    local data = probeData()
    if (stage == "armed" or stage == "pull") and readPhaseSources(event, ...) then
        return
    end
    if event == "ENCOUNTER_START" and stage == "armed" then
        local ok, _, instanceType = pcall(GetInstanceInfo)
        if not ok or instanceType ~= "raid" then
            return
        end
        local encounterID = ...
        stage = "pull"
        seenIDs = {}
        if classify(encounterID) == "readable" then
            data.encounterID = encounterID
        end
        readFeature("event")
        readJournal("event", encounterID)
        if frame then
            -- Not RegisterUnitEvent: it listens to at most two units. The handler skips non-boss units.
            frame:RegisterEvent("UNIT_SPELLCAST_START")
            frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end
    elseif stage == "armed" and event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        -- Seen before the pull starts: shows whether the opener's event arrives before ENCOUNTER_START.
        local okType, _, instanceType = pcall(GetInstanceInfo)
        if okType and instanceType == "raid" then
            local info = ...
            recordFields("added.prepull", INFO_FIELDS, "event", info)
        end
    elseif stage == "pull" then
        if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
            local info = ...
            recordFields("added", INFO_FIELDS, "event", info)
            if type(info) == "table" and classify(info) == "readable" then
                local id = info.id
                if classify(id) == "readable" then
                    seenIDs[id] = true
                end
            end
        elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
            local id = ...
            if classify(id) == "readable" then
                seenIDs[id] = true
                local state, okState = call("state", "value", "event", function()
                    return C_EncounterTimeline.GetEventState(id)
                end)
                if okState then
                    record("state", "value", "event", state)
                end
            end
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, castGUID, spellID = ...
            if classify(unit) == "readable" and BOSS_UNITS[unit] then
                record("bosscast", "castGUID", "event", castGUID)
                record("bosscast", "spellID", "event", spellID)
            end
        elseif event == "ENCOUNTER_END" then
            stage = "ended"
            catchAllOff()
            readSeen("end")
            readFeature("end")
            readDeaths("end")
            if data.encounterID then
                readJournal("end", data.encounterID)
            end
        end
    elseif stage == "ended" and event == "PLAYER_REGEN_ENABLED" then
        readSeen("ooc")
        readDeaths("ooc")
        disarm()
        CRT:Print("Timeline probe done, /crt dev probe show")
    end
end

-- Logs the next raid boss pull.
function Probe:Arm()
    local r = CRTDB or CRT.db
    if not r then
        return
    end
    r.dev = r.dev or {}
    r.dev.probe = { armedAt = time(), fields = {}, counts = {} }
    seenIDs = {}
    stage = "armed"
    if not frame and CreateFrame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, ...)
            Probe.HandleEvent(event, ...)
        end)
    end
    if frame then
        frame:UnregisterAllEvents()
        registerNormal()
        -- Dev only: every event arrives, and the handler keeps just the ENCOUNTER_TIMELINE_ ones.
        pcall(frame.RegisterAllEvents, frame)
    end
    CRT:Print("Timeline probe armed for the next raid boss pull.")
end

-- Prints one line per value: its counts at each moment.
function Probe:Show()
    local data = probeData()
    if not data or not next(data.counts) then
        CRT:Print("The timeline probe has no results yet. Run /crt dev probe, then pull a raid boss.")
        return
    end
    local names, byName = {}, {}
    for key, c in pairs(data.counts) do
        local name, moment = key:match("^(.-)@(.+)$")
        if not byName[name] then
            byName[name] = {}
            names[#names + 1] = name
        end
        byName[name][moment] = c
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local parts = {}
        for _, moment in ipairs(MOMENTS) do
            local c = byName[name][moment]
            if c then
                for _, class in ipairs(CLASSES) do
                    if c[class] > 0 then
                        parts[#parts + 1] = moment .. " " .. class .. " " .. c[class]
                    end
                end
            end
        end
        CRT:Print(name .. ": " .. table.concat(parts, ", "))
    end
end
