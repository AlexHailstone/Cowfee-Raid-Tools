local ADDON, CRT = ...

-- The boss library: everything the addon ships about each raid boss, in one file per boss, grouped
-- in season packs (Seasons/<season>/). Features never name a boss in their code; once every file has
-- loaded, this fills each feature's shipped table from the bosses of the loaded seasons:
--   references  -> CRT.TimelineDB.references   (Timeline reference timelines, text blocks)
--   phases      -> CRT.AlertPhaseDB[encounterID] (the alerts engine's phase triggers)
--   mechanics   -> CRT.TattleDB.bosses           (Tattlebot's tracked mechanics)
--   markers     -> CRT.MarkerDisplayDB.displays  (marker displays)
--   pace        -> CRT.PaceDB.bosses             (pace plans)
-- Features that don't depend on a boss (the Late Tracker, Raid Groups, ready checks, consumables)
-- never read it. Which seasons load is a dev-only choice (Dev/SeasonTools.lua, CRTDB.dev.seasons):
-- the current season only, by default, or all. See the vault note "Cowfee Raid Tools - Boss Library
-- Design".

local Bosses = { seasons = {}, bosses = {}, order = {} }
CRT.Bosses = Bosses

-- A season pack's description, from its Season.lua: { key, name, expansion, order, current, raids }
-- (raids is the route, below).
function Bosses:Season(def)
    assert(type(def) == "table" and type(def.key) == "string", "a season needs a key")
    self.seasons[def.key] = def
end

-- One boss, from its boss file. encounterID, name and season are required.
function Bosses:Register(def)
    assert(type(def) == "table" and type(def.encounterID) == "number", "a boss needs an encounterID")
    assert(type(def.name) == "string" and type(def.season) == "string", "a boss needs a name and a season")
    if not self.bosses[def.encounterID] then
        self.order[#self.order + 1] = def.encounterID
    end
    self.bosses[def.encounterID] = def
end

function Bosses:Get(encounterID)
    return encounterID and self.bosses[encounterID] or nil
end

-- The seasons, sorted by their order: { def, ... }.
function Bosses:Seasons()
    local out = {}
    for _, def in pairs(self.seasons) do
        out[#out + 1] = def
    end
    table.sort(out, function(a, b)
        return (a.order or 0) < (b.order or 0)
    end)
    return out
end

function Bosses:Current()
    for _, def in pairs(self.seasons) do
        if def.current then
            return def
        end
    end
end

-- The bosses of a season (or every boss), in the order their files loaded.
function Bosses:List(seasonKey)
    local out = {}
    for _, id in ipairs(self.order) do
        local def = self.bosses[id]
        if not seasonKey or def.season == seasonKey then
            out[#out + 1] = def
        end
    end
    return out
end

-- The route ----------------------------------------------------------------------------------
-- The order bosses are listed in everywhere: the raid progression route, grouped by raid. It ships in
-- each season's Season.lua as raids = { { key, name, bosses = { encounterID, ... } }, ... }, in route
-- order. The Boss order tool on the Development page (Dev/BossOrder.lua) can lay a different order over
-- it on the dev's own computer (CRTDB.dev.bossRoute[seasonKey], the same shape); it never ships.
-- Every boss list reads Route or RouteList and keeps their order: none sorts bosses itself. A boss with
-- a file but missing from the route goes at the end of the last raid, so a new boss file is never lost;
-- a route ID with no boss file is skipped.

local routeListeners = {}
local seasonLoaded -- defined below, with LoadMode

function Bosses:OnRouteChange(fn)
    routeListeners[#routeListeners + 1] = fn
end

function Bosses:FireRoute()
    for _, fn in ipairs(routeListeners) do
        fn()
    end
end

-- The raids of a season as written, with the dev's order over the shipped one: { { key, name, bosses } }.
function Bosses:Raids(seasonKey)
    local dev = CRT.db and CRT.db.dev and CRT.db.dev.bossRoute
    if dev and type(dev[seasonKey]) == "table" then
        return dev[seasonKey], true
    end
    local def = self.seasons[seasonKey]
    return (def and def.raids) or {}, false
end

-- One season's route: { { raid = { key, name }, bosses = { def, ... } }, ... }.
local function seasonRoute(self, seasonKey)
    local out, placed = {}, {}
    for _, raid in ipairs((self:Raids(seasonKey))) do
        local group = { raid = { key = raid.key, name = raid.name }, bosses = {} }
        for _, id in ipairs(raid.bosses or {}) do
            local def = self.bosses[id]
            if def and def.season == seasonKey and not placed[id] then
                placed[id] = true
                group.bosses[#group.bosses + 1] = def
            end
        end
        out[#out + 1] = group
    end
    for _, def in ipairs(self:List(seasonKey)) do
        if not placed[def.encounterID] then
            if #out == 0 then
                local season = self.seasons[seasonKey]
                out[1] = { raid = { key = seasonKey, name = season and season.name or seasonKey }, bosses = {} }
            end
            local last = out[#out].bosses
            last[#last + 1] = def
        end
    end
    return out
end

-- The route: one season's (seasonKey), or every loaded season's in season order (nil).
function Bosses:Route(seasonKey)
    if seasonKey then
        return seasonRoute(self, seasonKey)
    end
    local out = {}
    for _, season in ipairs(self:Seasons()) do
        if seasonLoaded(season.key) then
            for _, group in ipairs(seasonRoute(self, season.key)) do
                out[#out + 1] = group
            end
        end
    end
    return out
end

-- The route as one list of boss definitions, in order.
function Bosses:RouteList(seasonKey)
    local out = {}
    for _, group in ipairs(self:Route(seasonKey)) do
        for _, def in ipairs(group.bosses) do
            out[#out + 1] = def
        end
    end
    return out
end

-- A boss's place in the route (1 first), or nil when it is not a loaded boss. For callers that order
-- their own entries by it.
function Bosses:RouteIndex(encounterID)
    for i, def in ipairs(self:RouteList()) do
        if def.encounterID == encounterID then
            return i
        end
    end
end

-- The route as dropdown options for UI.Dropdown: each raid a heading (title = true), then its bosses,
-- { key = encounterID, label = name }. Only bosses in the library are listed. The first pickable key
-- is FirstKey(options).
function Bosses:Options(seasonKey)
    local out = {}
    for _, group in ipairs(self:Route(seasonKey)) do
        if #group.bosses > 0 then
            out[#out + 1] = { key = "raid:" .. tostring(group.raid.key), label = group.raid.name, title = true }
            for _, def in ipairs(group.bosses) do
                out[#out + 1] = { key = def.encounterID, label = def.name }
            end
        end
    end
    return out
end

function Bosses.FirstKey(options)
    for _, o in ipairs(options) do
        if not o.title then
            return o.key
        end
    end
end

-- Which seasons load: "current" (the default) or "all", set in the dev window.
function Bosses:LoadMode()
    local dev = CRT.db and CRT.db.dev
    return (dev and dev.seasons and dev.seasons.load) == "all" and "all" or "current"
end

seasonLoaded = function(key)
    if Bosses:LoadMode() == "all" then
        return true
    end
    local def = Bosses.seasons[key]
    return def and def.current and true or false
end

function Bosses:Loaded(encounterID)
    local def = self.bosses[encounterID]
    return def and seasonLoaded(def.season) or false
end

-- Fills each feature's shipped table from the loaded bosses, in route order, so lists built from those
-- tables (Tattlebot's mechanics) follow the route too. Runs once, after every file loads.
function Bosses:Build()
    local timeline = CRT.TimelineDB and CRT.TimelineDB.references
    local phases = CRT.AlertPhaseDB
    local tattle = CRT.TattleDB and CRT.TattleDB.bosses
    local markers = CRT.MarkerDisplayDB and CRT.MarkerDisplayDB.displays
    local pace = CRT.PaceDB and CRT.PaceDB.bosses
    for _, def in ipairs(self:RouteList()) do
        if seasonLoaded(def.season) then
            local id = def.encounterID
            if timeline then
                for _, text in ipairs(def.references or {}) do
                    -- As written: a reference names its own boss, and may give an Encounter: line.
                    timeline[#timeline + 1] = text
                end
            end
            if phases and def.phases then
                phases[id] = def.phases
            end
            if tattle and def.mechanics then
                tattle[#tattle + 1] = { boss = def.name, encounterID = id, mechanics = def.mechanics }
            end
            if markers and def.markers then
                markers[id] = def.markers
            end
            if pace and def.pace then
                pace[id] = def.pace
            end
        end
    end
    self.built = true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        Bosses:Build()
    end
end)
