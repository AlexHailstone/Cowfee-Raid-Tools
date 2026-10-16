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

-- A season pack's description, from its Season.lua: { key, name, expansion, order, current }.
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

-- Which seasons load: "current" (the default) or "all", set in the dev window.
function Bosses:LoadMode()
    local dev = CRT.db and CRT.db.dev
    return (dev and dev.seasons and dev.seasons.load) == "all" and "all" or "current"
end

local function seasonLoaded(key)
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

-- Fills each feature's shipped table from the loaded bosses. Runs once, after every file loads.
function Bosses:Build()
    local timeline = CRT.TimelineDB and CRT.TimelineDB.references
    local phases = CRT.AlertPhaseDB
    local tattle = CRT.TattleDB and CRT.TattleDB.bosses
    local markers = CRT.MarkerDisplayDB and CRT.MarkerDisplayDB.displays
    local pace = CRT.PaceDB and CRT.PaceDB.bosses
    for _, def in ipairs(self:List()) do
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
