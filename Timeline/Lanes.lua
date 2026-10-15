local ADDON, CRT = ...

-- Timeline: builds the lanes the canvas draws. A lane is one row: its label, icon and marks.
-- There are two kinds of timeline. A recorded pull gets the deaths first, then the boss's
-- ability rows with their casts, then "Boss casts (unnamed)" for casts whose spell could not be
-- read or has no row. A reference timeline (a written plan of when the boss does what) gets the
-- deaths lane on top and then one lane per row of the reference, in file order; when a recorded
-- pull is laid over it, that pull's deaths fill the deaths lane and its casts become a row of
-- ticks at the bottom. The Journal rows are cached, so new lane tables are made instead of
-- marking them. Lanes.Build(base, rows, settings, encounterID, overlay) returns the lanes, the
-- deaths that have no time (listed apart), and extra: the phases, the length, and the line where
-- the overlay pull ended.

local Lanes = {}
CRT.TimelineLanes = Lanes

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local UNNAMED_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function trimLower(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

-- Puts the deaths of each source on the lanes: one combined lane, or one lane per player. Deaths
-- with no time go to unknown, but only the first source's (the shown pull's, not an older one's).
local function addDeaths(lanes, unknown, sources, settings, combined)
    local Timeline = CRT.Timeline
    local deathLane
    if combined then
        deathLane = { key = "deaths", label = "Deaths", icon = SKULL, kind = "deaths", marks = {} }
        lanes[1] = deathLane
    end
    local byName = {}
    for i, source in ipairs(sources) do
        for _, death in ipairs(Timeline.FilterDeaths(source.deaths, settings)) do
            if type(death.t) ~= "number" then
                if i == 1 then
                    unknown[#unknown + 1] = death
                end
            else
                local lane = deathLane
                if not combined then
                    local name = death.name or "Unknown"
                    lane = byName[name]
                    if not lane then
                        lane = { key = "death:" .. name, label = name, class = death.class, icon = SKULL, kind = "deaths", marks = {} }
                        byName[name] = lane
                        lanes[#lanes + 1] = lane
                    end
                end
                lane.marks[#lane.marks + 1] = { t = death.t, spellID = death.spellID or 0, death = death, age = i - 1, pull = source.pull }
            end
        end
    end
end

-- The lanes of a recorded pull, top to bottom: deaths, the ability rows that are not hidden, and
-- the unnamed casts.
local function pullLanes(pull, rows, settings, encounterID)
    local lanes, unknown = {}, {}
    local Timeline = CRT.Timeline

    -- Deaths: the shown pull at age 0, then (with the overlay) the pulls before it at age 1, 2, ...
    local sources = { { pull = pull, deaths = pull.deaths or {} } }
    if settings.overlayOn and encounterID and pull.id then
        local recent = Timeline:RecentDeaths(encounterID, settings.overlay or 3, pull.id)
        if recent[1] and recent[1].pull.id == pull.id then
            sources = recent
        end
    end
    addDeaths(lanes, unknown, sources, settings, settings.deathRows ~= "player")

    -- Ability rows. A cast on a hidden row is not drawn, and does not count as unnamed either.
    local byID, shown = {}, {}
    for _, row in ipairs(rows or {}) do
        local lane = { key = "spell:" .. row.spellID, label = row.name, icon = row.icon, spellID = row.spellID, kind = "spell", marks = {} }
        byID[row.spellID] = lane
        if not CRT.TimelineJournal:IsHidden(encounterID, row.spellID) then
            shown[#shown + 1] = lane
        end
    end
    local unnamed = { key = "unnamed", label = "Boss casts (unnamed)", icon = UNNAMED_ICON, spellID = 0, kind = "unnamed", marks = {} }
    for _, cast in ipairs(pull.casts or {}) do
        if type(cast.t) == "number" then
            local id = cast.spellID or 0
            local lane = (id ~= 0 and byID[id]) or unnamed
            lane.marks[#lane.marks + 1] = { t = cast.t, spellID = id, dur = cast.dur, age = 0 }
        end
    end
    for _, lane in ipairs(shown) do
        if #lane.marks > 0 or not settings.hideEmpty then
            lanes[#lanes + 1] = lane
        end
    end
    if #unnamed.marks > 0 then
        lanes[#lanes + 1] = unnamed
    end
    return lanes, unknown, { phases = {}, length = pull.length or 0 }
end

-- The lanes of a reference timeline: deaths (from the overlay pull only), one lane per reference
-- row in file order, and with an overlay a row of ticks for that pull's casts. A row gets its
-- spell and icon from its own [spell], else from the Journal row of the same name.
local function referenceLanes(ref, rows, settings, encounterID, overlay)
    local lanes, unknown = {}, {}
    local sources = {}
    if overlay then
        sources[1] = { pull = overlay, deaths = overlay.deaths or {} }
    end
    addDeaths(lanes, unknown, sources, settings, true)

    local byName, byID = {}, {}
    for _, row in ipairs(rows or {}) do
        local key = trimLower(row.name)
        if byName[key] == nil then
            byName[key] = row
        end
        if byID[row.spellID] == nil then
            byID[row.spellID] = row
        end
    end
    local mine = settings.rows and settings.rows[encounterID]
    local hiddenNames = mine and mine.hiddenNames
    for _, row in ipairs(ref.rows or {}) do
        local key = trimLower(row.name)
        local given = row.spellID
        local match = (given and given ~= 0 and byID[given]) or byName[key]
        local spellID = (given and given ~= 0) and given or (match and match.spellID) or 0
        local hidden = (spellID ~= 0 and CRT.TimelineJournal:IsHidden(encounterID, spellID))
            or (hiddenNames and hiddenNames[key])
        if not hidden then
            local marks = {}
            for i, cast in ipairs(row.casts or {}) do
                marks[i] = { t = cast.t, dur = cast.dur }
            end
            lanes[#lanes + 1] = {
                key = "ref:" .. row.name, label = row.name, color = row.color, lead = row.lead, kind = "reference",
                spellID = spellID, icon = match and match.icon or UNNAMED_ICON, marks = marks,
            }
        end
    end

    local extra = { phases = ref.phases or {}, length = math.max(ref.length or 0, overlay and overlay.length or 0) }
    if overlay then
        local ticks = { key = "overlay", label = "Pull " .. tostring(overlay.id) .. " casts", kind = "ticks", marks = {} }
        for _, cast in ipairs(overlay.casts or {}) do
            if type(cast.t) == "number" then
                ticks.marks[#ticks.marks + 1] = { t = cast.t }
            end
        end
        lanes[#lanes + 1] = ticks
        extra.endLine = overlay.length
    end
    return lanes, unknown, extra
end

function Lanes.Build(base, rows, settings, encounterID, overlay)
    if not base then
        return {}, {}, { phases = {}, length = 0 }
    end
    if base.reference then
        return referenceLanes(base.reference, rows, settings, encounterID, overlay)
    end
    return pullLanes(base, rows, settings, encounterID)
end
