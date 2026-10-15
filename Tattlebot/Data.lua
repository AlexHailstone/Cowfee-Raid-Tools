local ADDON, CRT = ...

-- Tattlebot: who took damage from the boss mechanics in Tattlebot/Database.lua. Midnight closes the
-- combat log to addons during boss fights, so after each boss pull (ENCOUNTER_END, then out of
-- combat) this reads the game's own damage meter instead: C_DamageMeter, Damage Taken, the current
-- session. The meter's values are secret while in combat, so nothing is read until combat ends, and
-- a read that still finds a secret is tried again a few times. The meter has damage per spell but no
-- hit count, so each player gets the damage taken per spell and the number of pulls it hit them in.
-- Pulls go into a night (CRTDB.tattle.current), which ends after NIGHT_GAP without a pull or by End
-- night, and then moves to CRTDB.tattle.history.

local Tattle = { listeners = {} }
CRT.Tattle = Tattle

local NIGHT_GAP = 6 * 3600 -- a pull this long after the last one starts a new night
local READ_DELAY = 1 -- seconds after combat ends before reading, so the meter has the whole fight
local RETRY_DELAY = 2
local RETRIES = 5

local function tdb()
    return CRT.db.tattle
end

local function enum(group, key, fallback)
    local e = Enum and Enum[group]
    return (e and e[key]) or fallback
end

-- The values from DamageMeterConstantsDocumentation.lua, used if the Enum table is missing.
local CURRENT = enum("DamageMeterSessionType", "Current", 1)
local TAKEN = enum("DamageMeterType", "DamageTaken", 7)
local AVOIDABLE = enum("DamageMeterType", "AvoidableDamageTaken", 8)

function Tattle:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Tattle:Fire()
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

function Tattle:Settings()
    return tdb()
end

function Tattle:Set(field, value)
    tdb()[field] = value
    self:Fire()
end

function Tattle:Current()
    return tdb().current
end

function Tattle:History()
    return tdb().history
end

function Tattle:Find(id)
    for _, night in ipairs(tdb().history) do
        if night.id == id then
            return night
        end
    end
end

function Tattle:Delete(id)
    local history = tdb().history
    for i, night in ipairs(history) do
        if night.id == id then
            table.remove(history, i)
            self:Fire()
            return
        end
    end
end

-- The tracked mechanics. The shipped list in Tattlebot/Database.lua is grouped by boss, and the
-- player's own spells are in CRTDB.tattle.custom: [spellID] = { name, boss, encounterID } when added
-- from the Last fight view (boss and encounterID only when that fight was a boss), or a plain
-- mechanic name string when typed in by hand.
-- Every tracked spell ID maps to its mechanic, { key, name, boss, own }, and the reports add up all
-- the spells of one mechanic under its name. Pulls store damage per spell ID, so a mechanic that
-- gains or loses an ID later still adds up right in old nights.

local index -- [spellID] = mechanic, rebuilt when the player's own list changes

function Tattle.Bosses()
    return (CRT.TattleDB and CRT.TattleDB.bosses) or {}
end

local function buildIndex()
    index = {}
    for _, boss in ipairs(Tattle.Bosses()) do
        for _, mech in ipairs(boss.mechanics or {}) do
            local name = mech.name or "?"
            local entry = { key = (boss.boss or "") .. "/" .. name:lower(), name = name, boss = boss.boss, encounterID = boss.encounterID }
            for _, id in ipairs(mech.spells or {}) do
                index[id] = index[id] or entry
            end
        end
    end
    for id, v in pairs(tdb().custom) do
        if not index[id] then
            local name, boss, encounterID = v, nil, nil
            if type(v) == "table" then
                name, boss, encounterID = v.name, v.boss, v.encounterID
            end
            local label = (type(name) == "string" and name ~= "") and name or Tattle.SpellName(id)
            index[id] = { key = "own/" .. (boss or ""):lower() .. "/" .. label:lower(), name = label, own = true, boss = boss, encounterID = encounterID }
        end
    end
    return index
end

-- The tracked spells, [spellID] = mechanic.
function Tattle.List()
    return index or buildIndex()
end

function Tattle.ListSize()
    local n = 0
    for _ in pairs(Tattle.List()) do
        n = n + 1
    end
    return n
end

-- The mechanic a spell counts under. A spell in neither list (avoidable damage) is its own.
function Tattle.Mechanic(id)
    return Tattle.List()[id] or { key = "spell/" .. id, name = Tattle.SpellName(id) }
end

-- The player's own spells. name may be empty, and then the game's spell name is used. Spells given
-- the same name (and boss) are reported as one mechanic. boss and encounterID tie the mechanic to a
-- boss, for the History filter's pull count; without them it counts on every pull.
function Tattle:AddCustom(id, name, boss, encounterID)
    if boss or encounterID then
        tdb().custom[id] = { name = name or "", boss = boss, encounterID = encounterID }
    else
        tdb().custom[id] = name or ""
    end
    index = nil
    self:Fire()
end

-- Adds several spells in one go, from the Last fight view. names[id] is each spell's mechanic name.
function Tattle:AddCustomMany(ids, names, boss, encounterID)
    for _, id in ipairs(ids) do
        if boss or encounterID then
            tdb().custom[id] = { name = names[id] or "", boss = boss, encounterID = encounterID }
        else
            tdb().custom[id] = names[id] or ""
        end
    end
    index = nil
    self:Fire()
end

function Tattle:RemoveCustom(id)
    tdb().custom[id] = nil
    index = nil
    self:Fire()
end

-- Reading the meter -------------------------------------------------------------------------------

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

-- GUID to "Name-Realm" for everyone in your group, to name the meter's players.
local function groupGuids()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
    else
        units[1] = "player"
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    end
    local map = {}
    for _, unit in ipairs(units) do
        local ok, guid = pcall(UnitGUID, unit)
        if ok and guid and readable(guid) then
            local okName, name, realm = pcall(UnitFullName, unit)
            if okName and name and readable(name) and readable(realm) then
                if realm and realm ~= "" then
                    name = name .. "-" .. realm
                end
                map[guid] = CRT.Groups.Normalize(name)
            end
        end
    end
    return map
end

-- The player's "Name-Realm": from the group by GUID first, then the meter's own name.
local function sourceKey(src, guids)
    local guid = src.sourceGUID
    if guid and readable(guid) and guids[guid] then
        return guids[guid]
    end
    local name = src.name
    if type(name) == "string" and readable(name) and name ~= "" then
        return CRT.Groups.Normalize(name)
    end
    return nil
end

-- The damage one player took per spell, { [spellID] = amount }, from one meter type. Spells listed
-- more than once (one entry per caster) are added together. all keeps every spell, otherwise only
-- the tracked ones. The second return is true when something was secret.
local function spellsFor(meterType, src, all)
    local sums, secret = {}, false
    local ok, detail = pcall(C_DamageMeter.GetCombatSessionSourceFromType, CURRENT, meterType, src.sourceGUID, src.sourceCreatureID)
    if not ok or type(detail) ~= "table" or type(detail.combatSpells) ~= "table" then
        return sums, not ok
    end
    local list = Tattle.List()
    for _, spell in ipairs(detail.combatSpells) do
        local id, amount = spell.spellID, spell.totalAmount
        if readable(id) and readable(amount) and type(id) == "number" and type(amount) == "number" then
            if all or list[id] then
                sums[id] = (sums[id] or 0) + amount
            end
        else
            secret = true
        end
    end
    return sums, secret
end

-- Why the meter can't be read now, or nil.
function Tattle.Unavailable()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        return "This game client has no damage meter for addons to read."
    end
    if C_DamageMeter.IsDamageMeterAvailable then
        local ok, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
        if ok and available == false then
            return "The game's damage meter is not available: " .. tostring(reason or "no reason given") .. "."
        end
    end
    return nil
end

-- Reads the meter's current session. Returns a pull { players = { [key] = { class, spells } },
-- sources, unnamed, duration }, or nil and "missing", "nodata" or "secret". opts.all keeps every
-- spell that did damage (for the scan), opts.avoidable adds the meter's own avoidable damage.
local function readSession(opts)
    if Tattle.Unavailable() then
        return nil, "missing"
    end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, CURRENT, TAKEN)
    if not ok then
        return nil, "secret"
    end
    if type(session) ~= "table" or type(session.combatSources) ~= "table" then
        return nil, "nodata"
    end
    local guids = groupGuids()
    local pull = { players = {}, sources = 0, unnamed = 0 }
    local secret = false
    for _, src in ipairs(session.combatSources) do
        -- Players have a class. Pets and creatures have an empty one.
        local class = src.classFilename
        if type(class) == "string" and class ~= "" then
            pull.sources = pull.sources + 1
            local key = sourceKey(src, guids)
            if not key then
                pull.unnamed = pull.unnamed + 1
            else
                local spells, s1 = spellsFor(TAKEN, src, opts.all)
                secret = secret or s1
                if opts.avoidable then
                    local extra, s2 = spellsFor(AVOIDABLE, src, true)
                    secret = secret or s2
                    for id, amount in pairs(extra) do
                        spells[id] = math.max(spells[id] or 0, amount)
                    end
                end
                if next(spells) then
                    pull.players[key] = { class = class, spells = spells }
                end
            end
        end
    end
    if secret then
        return nil, "secret"
    end
    local duration = session.durationSeconds
    if type(duration) == "number" and readable(duration) then
        pull.duration = math.floor(duration + 0.5)
    end
    return pull
end

-- Any error while reading (a secret value used where it can't be) counts as still secret.
function Tattle:Read(opts)
    local ok, pull, why = pcall(readSession, opts or {})
    if not ok then
        return nil, "secret"
    end
    return pull, why
end

-- The spells the meter marks avoidable for anyone in the current session, { [spellID] = true }.
local function avoidableSet()
    local set = {}
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, CURRENT, AVOIDABLE)
    if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then
        return set
    end
    for _, src in ipairs(session.combatSources) do
        for id in pairs((spellsFor(AVOIDABLE, src, true))) do
            set[id] = true
        end
    end
    return set
end

-- Nights ---------------------------------------------------------------------------------------------

-- reason is "button" or "gap". A night with no pulls is dropped, not saved.
function Tattle:EndNight(reason, at)
    local s = tdb()
    local night = s.current
    if not night then
        return
    end
    s.current = nil
    if #night.pulls > 0 then
        night.endedAt = at or time()
        night.endReason = reason
        s.history[#s.history + 1] = night
    end
    self:Fire()
end

-- info is { encounterID, name, difficulty, success }. Adds the pull to tonight, starting a new night
-- when there is none or the last pull was more than NIGHT_GAP ago.
function Tattle:AddPull(pull, info, now)
    local s = tdb()
    now = now or time()
    local night = s.current
    if night and now - (night.lastAt or night.startedAt) > NIGHT_GAP then
        self:EndNight("gap", night.lastAt)
        night = nil
    end
    if not night then
        night = { id = s.nextId, startedAt = now, season = s.season, pulls = {} }
        s.nextId = s.nextId + 1
        s.current = night
    end
    pull.at = now
    pull.encounterID = info.encounterID
    pull.name = info.name
    pull.difficulty = info.difficulty
    pull.success = info.success
    night.pulls[#night.pulls + 1] = pull
    night.lastAt = now
    self:Fire()
    return pull
end

-- Summaries ------------------------------------------------------------------------------------------

-- One player's spells in one pull, added up per mechanic: { [key] = { key, name, damage } }.
function Tattle.ByMechanic(spells)
    local out = {}
    for id, amount in pairs(spells) do
        local mech = Tattle.Mechanic(id)
        local m = out[mech.key]
        if not m then
            m = { key = mech.key, name = mech.name, damage = 0 }
            out[mech.key] = m
        end
        m.damage = m.damage + amount
    end
    return out
end

-- Seasons and mechanics, for the History filters --------------------------------------------------

-- A night's season. Nights saved before seasons existed count as the first season's default name.
function Tattle.SeasonOf(night)
    return night.season or Tattle.DEFAULT_SEASON
end
Tattle.DEFAULT_SEASON = "Season 1"

-- Every season name in the history and the current one, oldest first.
function Tattle:Seasons()
    local out, seen = {}, {}
    local function add(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    for _, night in ipairs(tdb().history) do
        add(Tattle.SeasonOf(night))
    end
    add(tdb().season)
    return out
end

-- The saved nights of one season, or all of them when season is nil.
function Tattle:NightsIn(season)
    local out = {}
    for _, night in ipairs(tdb().history) do
        if not season or Tattle.SeasonOf(night) == season then
            out[#out + 1] = night
        end
    end
    return out
end

-- The mechanic with this key: from the lists, or rebuilt from the key of a spell counted only as
-- avoidable damage.
function Tattle.MechanicByKey(key)
    for _, mech in pairs(Tattle.List()) do
        if mech.key == key then
            return mech
        end
    end
    local id = tonumber(key:match("^spell/(%d+)$"))
    if id then
        return { key = key, name = Tattle.SpellName(id) }
    end
    return { key = key, name = key }
end

-- "Boss: Mechanic", "Your own: Mechanic" or "Avoidable: Spell", for the filter.
function Tattle.MechanicLabel(mech)
    if mech.boss then
        return mech.boss .. ": " .. mech.name
    elseif mech.own then
        return "Your own: " .. mech.name
    end
    return "Avoidable: " .. mech.name
end

-- The mechanics to filter by: every tracked one in the shipped list's order, then your own, then
-- any other the nights given recorded. { key, label } each.
function Tattle.MechanicOptions(nights)
    local out, seen = {}, {}
    local function add(mech)
        if not seen[mech.key] then
            seen[mech.key] = true
            out[#out + 1] = { key = mech.key, label = Tattle.MechanicLabel(mech) }
        end
    end
    local list = Tattle.List()
    for _, boss in ipairs(Tattle.Bosses()) do
        for _, mech in ipairs(boss.mechanics or {}) do
            local first = mech.spells and mech.spells[1]
            if first and list[first] then
                add(list[first])
            end
        end
    end
    local own = {}
    for _, mech in pairs(list) do
        if mech.own and not seen[mech.key] then
            seen[mech.key] = true
            own[#own + 1] = mech
        end
    end
    table.sort(own, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    for _, mech in ipairs(own) do
        out[#out + 1] = { key = mech.key, label = Tattle.MechanicLabel(mech) }
    end
    local other = {}
    for _, night in ipairs(nights or {}) do
        for _, pull in ipairs(night.pulls) do
            for _, p in pairs(pull.players) do
                for id in pairs(p.spells) do
                    local mech = Tattle.Mechanic(id)
                    if not seen[mech.key] then
                        seen[mech.key] = true
                        other[#other + 1] = mech
                    end
                end
            end
        end
    end
    table.sort(other, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    for _, mech in ipairs(other) do
        out[#out + 1] = { key = mech.key, label = Tattle.MechanicLabel(mech) }
    end
    return out
end

-- Whether a pull was on the mechanic's boss: by the shipped list's encounterID when it has one,
-- otherwise by the boss name. Own and avoidable mechanics count on every pull.
local function onBoss(pull, mech)
    if mech.encounterID then
        return pull.encounterID == mech.encounterID
    end
    if mech.boss then
        return type(pull.name) == "string" and pull.name:lower() == mech.boss:lower()
    end
    return true
end

-- One row per player over the nights given: { key, class, damage, hits (pulls hit), mechanics =
-- { [key] = { name, damage, hits } } }, most damage first, plus the number of pulls. A mechanic
-- counts once per pull, however many of its spells hit.
-- With mechKey, only that mechanic counts, and the pulls are only those on its boss. If no pull
-- matches the boss (its name in the list differs from the game's), every pull counts instead.
function Tattle.Summary(nights, mechKey)
    local byKey, rows, pulls = {}, {}, 0
    local mech = mechKey and Tattle.MechanicByKey(mechKey)
    local matchBoss = false
    if mech then
        for _, night in ipairs(nights) do
            for _, pull in ipairs(night.pulls) do
                matchBoss = matchBoss or onBoss(pull, mech)
            end
        end
    end
    for _, night in ipairs(nights) do
        for _, pull in ipairs(night.pulls) do
            -- With a mechanic picked, pulls on other bosses don't count at all.
            local counts = not mech or not matchBoss or onBoss(pull, mech)
            if counts then
                pulls = pulls + 1
            end
            for key, p in pairs(counts and pull.players or {}) do
                local mechanics = Tattle.ByMechanic(p.spells)
                if mech then
                    mechanics = { [mechKey] = mechanics[mechKey] }
                end
                if next(mechanics) then
                    local lower = key:lower()
                    local row = byKey[lower]
                    if not row then
                        row = { key = key, damage = 0, hits = 0, mechanics = {} }
                        byKey[lower] = row
                        rows[#rows + 1] = row
                    end
                    row.class = p.class or row.class
                    row.hits = row.hits + 1
                    for mkey, m in pairs(mechanics) do
                        local total = row.mechanics[mkey]
                        if not total then
                            total = { name = m.name, damage = 0, hits = 0 }
                            row.mechanics[mkey] = total
                        end
                        total.damage = total.damage + m.damage
                        total.hits = total.hits + 1
                        row.damage = row.damage + m.damage
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.damage ~= b.damage then
            return a.damage > b.damage
        end
        return a.key:lower() < b.key:lower()
    end)
    return rows, pulls
end

function Tattle:Totals()
    return Tattle.Summary(tdb().history)
end

-- Mechanics as a list, most damage first: { name, damage, hits }. hits is 1 for a single pull.
function Tattle.SortedMechanics(mechanics)
    local list = {}
    for _, m in pairs(mechanics) do
        list[#list + 1] = { name = m.name, damage = m.damage, hits = m.hits or 1 }
    end
    table.sort(list, function(a, b)
        if a.damage ~= b.damage then
            return a.damage > b.damage
        end
        return a.name < b.name
    end)
    return list
end

-- A player's total in one pull.
function Tattle.PullDamage(p)
    local total = 0
    for _, amount in pairs(p.spells) do
        total = total + amount
    end
    return total
end

-- Text -------------------------------------------------------------------------------------------------

function Tattle.SpellName(id)
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and type(n) == "string" and n ~= "" then
            name = n
        end
    end
    return name or ("Spell " .. id)
end

-- 1234 -> 1.2K, 56789 -> 57K, 2345678 -> 2.3M.
local function scaled(v, unit)
    local s = v < 10 and format("%.1f", v) or format("%.0f", v)
    return (s:gsub("%.0$", "")) .. unit
end

function Tattle.Short(n)
    n = n or 0
    if n >= 1e9 then
        return scaled(n / 1e9, "B")
    elseif n >= 1e6 then
        return scaled(n / 1e6, "M")
    elseif n >= 1e3 then
        return scaled(n / 1e3, "K")
    end
    return tostring(math.floor(n + 0.5))
end

local function players(n)
    return n .. (n == 1 and " player" or " players")
end

function Tattle.Outcome(pull)
    if pull.success == nil then
        return ""
    end
    return (pull.success == 1 or pull.success == true) and "kill" or "wipe"
end

function Tattle.PullTitle(pull, index)
    local title = pull.name or "Unknown boss"
    local outcome = Tattle.Outcome(pull)
    if outcome ~= "" then
        title = title .. " " .. outcome
    end
    if index then
        title = format("Pull %d: %s", index, title)
    end
    return title
end

-- Plain chat lines for one pull: a heading, then one line per player, most damage first, at most
-- maxPlayers players.
function Tattle.PullChat(pull, index, maxPlayers)
    local players = {}
    for key, p in pairs(pull.players) do
        players[#players + 1] = { key = key, p = p, damage = Tattle.PullDamage(p) }
    end
    table.sort(players, function(a, b)
        if a.damage ~= b.damage then
            return a.damage > b.damage
        end
        return a.key:lower() < b.key:lower()
    end)
    local lines = { "Tattlebot, " .. Tattle.PullTitle(pull, index) .. ":" }
    if #players == 0 then
        lines[1] = lines[1] .. " nobody took damage from a tracked mechanic."
        return lines
    end
    for i = 1, math.min(#players, maxPlayers or #players) do
        local e = players[i]
        local parts = {}
        for _, m in ipairs(Tattle.SortedMechanics(Tattle.ByMechanic(e.p.spells))) do
            parts[#parts + 1] = m.name .. " " .. Tattle.Short(m.damage)
        end
        lines[#lines + 1] = format("%s %s: %s", CRT.Groups.Display(e.key), Tattle.Short(e.damage), table.concat(parts, ", "))
    end
    if #players > (maxPlayers or #players) then
        lines[#lines + 1] = format("and %d more.", #players - maxPlayers)
    end
    return lines
end

-- Plain chat lines for a night: per player, the damage and the pulls they were hit in.
function Tattle.NightChat(night, maxPlayers)
    local rows, pulls = Tattle.Summary({ night })
    local lines = { format("Tattlebot, the night of %s: %d pulls.", date("%a %d %b", night.startedAt), pulls) }
    if #rows == 0 then
        lines[1] = lines[1] .. " Nobody took damage from a tracked mechanic."
        return lines
    end
    for i = 1, math.min(#rows, maxPlayers or #rows) do
        local row = rows[i]
        local parts = {}
        for _, m in ipairs(Tattle.SortedMechanics(row.mechanics)) do
            parts[#parts + 1] = format("%s %s (%d)", m.name, Tattle.Short(m.damage), m.hits)
        end
        lines[#lines + 1] = format("%s %s, hit in %d of %d pulls: %s", CRT.Groups.Display(row.key), Tattle.Short(row.damage), row.hits, pulls, table.concat(parts, ", "))
    end
    if #rows > (maxPlayers or #rows) then
        lines[#lines + 1] = format("and %d more.", #rows - maxPlayers)
    end
    return lines
end

-- Posts to the channel on the Settings tab, through the ready check report's chat output.
function Tattle:Post(lines, output)
    CRT.RaidReport:Output(lines, output or tdb().output)
end

function Tattle:PostLastPull()
    local night = self:Current()
    if not night or #night.pulls == 0 then
        CRT:Print("No pull has been recorded tonight.")
        return
    end
    self:Post(Tattle.PullChat(night.pulls[#night.pulls], #night.pulls, tdb().maxPlayers))
end

function Tattle:PostNight(night)
    night = night or self:Current()
    if not night or #night.pulls == 0 then
        CRT:Print("No pull has been recorded tonight.")
        return
    end
    self:Post(Tattle.NightChat(night, tdb().maxPlayers))
end

-- The scan ---------------------------------------------------------------------------------------------

-- The last boss fight and how many times combat has started, so a scan can tell whether the
-- meter's current session is that boss: it is when no combat started after the boss ended.
local lastBoss -- { name, encounterID, combat }
local combatCount = 0

-- The boss of the meter's current session, { name, encounterID }, or nil for a fight that was not
-- a boss.
function Tattle.LastFightBoss()
    if lastBoss and lastBoss.combat == combatCount then
        return lastBoss
    end
    return nil
end

-- Every spell that damaged the group in the meter's current session, most damage first: { spells =
-- { { id, name, damage, players, avoidable, tracked } }, duration, unnamed, boss }, or nil and why.
-- tracked is the mechanic the spell already counts under, if any.
function Tattle:Scan()
    local why = self.Unavailable()
    if why then
        return nil, why
    end
    local pull, reason = self:Read({ all = true })
    if not pull then
        if reason == "secret" then
            return nil, "The damage meter is still secret. Leave combat and try again."
        end
        return nil, "The damage meter has no fight to read yet."
    end
    local byId = {}
    for _, p in pairs(pull.players) do
        for id, amount in pairs(p.spells) do
            local s = byId[id]
            if not s then
                s = { id = id, damage = 0, players = 0 }
                byId[id] = s
            end
            s.damage = s.damage + amount
            s.players = s.players + 1
        end
    end
    local avoidable = avoidableSet()
    local tracked = Tattle.List()
    local list = {}
    for id, s in pairs(byId) do
        s.name = Tattle.SpellName(id)
        s.avoidable = avoidable[id] or false
        s.tracked = tracked[id]
        list[#list + 1] = s
    end
    table.sort(list, function(a, b)
        if a.damage ~= b.damage then
            return a.damage > b.damage
        end
        return a.id < b.id
    end)
    return { spells = list, duration = pull.duration, unnamed = pull.unnamed, boss = Tattle.LastFightBoss() }
end

-- The scan as lines to paste into Tattlebot/Database.lua.
function Tattle:ScanText()
    local scan, why = self:Scan()
    if not scan then
        return nil, why
    end
    local lines = {
        format("-- Damage taken in the last fight (%s), most first. Copy the lines you want into a", scan.duration and (scan.duration .. " s") or "length unknown"),
        "-- boss's mechanics in Tattlebot/Database.lua.",
    }
    if scan.boss then
        lines[#lines + 1] = format("-- The fight was %s, encounterID = %s", scan.boss.name or "?", tostring(scan.boss.encounterID or "?"))
    end
    for _, s in ipairs(scan.spells) do
        local notes = { Tattle.Short(s.damage) .. " on " .. players(s.players) }
        if s.avoidable then
            notes[#notes + 1] = "the game marks it avoidable"
        end
        if s.tracked then
            notes[#notes + 1] = "already tracked as " .. s.tracked.name
        end
        lines[#lines + 1] = format("{ name = %q, spells = { %d } }, -- %s", s.name, s.id, table.concat(notes, ", "))
    end
    if #scan.spells == 0 then
        lines[#lines + 1] = "-- Nobody in the group took damage in the last fight."
    end
    if scan.unnamed > 0 then
        lines[#lines + 1] = format("-- %s could not be named, so their damage is missing.", players(scan.unnamed))
    end
    return table.concat(lines, "\n")
end

-- Events -------------------------------------------------------------------------------------------------

local inCombat = false
local warnedUnnamed = false
local pending -- the boss pull waiting to be read: { encounterID, name, difficulty, success, waiting }

local function shouldTrack()
    local s = tdb()
    if not s.enabled then
        return false
    end
    if s.raidsOnly then
        local _, instanceType = IsInInstance()
        return instanceType == "raid"
    end
    return true
end

local function autoPost(pull, index)
    local s = tdb()
    if not s.autoPost then
        return
    end
    -- Only the raid leader posts to chat, so a raid full of this addon posts once. Everyone else sees
    -- it in their own chat.
    local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
    Tattle:Post(Tattle.PullChat(pull, index, s.maxPlayers), leader and s.output or "self")
end

local function attempt(info, tries)
    if pending ~= info then
        return
    end
    local pull, why = Tattle:Read({ avoidable = tdb().avoidable })
    if not pull and why == "secret" and tries < RETRIES then
        C_Timer.After(RETRY_DELAY, function()
            attempt(info, tries + 1)
        end)
        return
    end
    pending = nil
    if not pull then
        if why == "secret" then
            CRT:Print("Tattlebot could not read the damage meter after " .. (info.name or "the boss") .. ": its values were still secret.")
        elseif why == "missing" then
            CRT:Print("Tattlebot: " .. (Tattle.Unavailable() or "the damage meter is missing."))
        else
            CRT:Print("Tattlebot found no damage meter data after " .. (info.name or "the boss") .. ".")
        end
        return
    end
    -- Said once per login, so it does not repeat after every pull.
    if pull.unnamed > 0 and not warnedUnnamed then
        warnedUnnamed = true
        CRT:Print(format("Tattlebot could not name %s after %s, so their damage is missing.", players(pull.unnamed), info.name or "the boss"))
    end
    Tattle:AddPull(pull, info)
    local night = Tattle:Current()
    autoPost(pull, night and #night.pulls)
end

local function schedule(info)
    C_Timer.After(READ_DELAY, function()
        attempt(info, 1)
    end)
end

-- For tests outside the game.
Tattle._attempt = attempt

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("ENCOUNTER_END")
driver:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        combatCount = combatCount + 1
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if pending and pending.waiting then
            pending.waiting = false
            schedule(pending)
        end
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, _, success = ...
        -- Remembered even when not tracking, for the Last fight view.
        lastBoss = {
            name = readable(encounterName) and encounterName or nil,
            encounterID = readable(encounterID) and encounterID or nil,
            combat = combatCount,
        }
        if not shouldTrack() then
            return
        end
        local info = {
            encounterID = readable(encounterID) and encounterID or nil,
            name = readable(encounterName) and encounterName or nil,
            difficulty = readable(difficultyID) and difficultyID or nil,
            success = readable(success) and success or nil,
        }
        pending = info
        if inCombat then
            info.waiting = true
        else
            schedule(info)
        end
    elseif event == "PLAYER_LOGIN" then
        -- A night left from an earlier session ends when its last pull is long past.
        local night = tdb().current
        if night and time() - (night.lastAt or night.startedAt) > NIGHT_GAP then
            Tattle:EndNight("gap", night.lastAt)
        end
    end
end)
