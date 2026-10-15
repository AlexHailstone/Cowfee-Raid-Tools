local ADDON, CRT = ...

-- Timeline: the ability rows of a boss. The rows come from the Encounter Journal (every ability
-- that has a spell, in Journal order, each spell once), followed by spells you added yourself.
-- The game only gives the Journal's boss list for the instance you are in, so the boss is found
-- through the map you stand on first, then by looking through the current tier's raids; the
-- Journal's own selected instance is put back afterwards so its window is not disturbed. Nothing
-- is looked up during combat or while the Journal window is open, and what is found is kept for
-- the rest of the session. Hiding a row only sets a flag: the page decides what to draw.

local Journal = {}
CRT.TimelineJournal = Journal

local cache = {}
-- bosses the Journal could not be asked about in this zone; only your own rows are listed for them
local missed = {}

local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:SetScript("OnEvent", function()
    missed = {}
end)

local function settings()
    return CRT.Timeline:Settings()
end

-- The saved row settings of a boss, made when first needed.
local function bossRows(encounterID)
    local rows = settings().rows
    if not rows then
        rows = {}
        settings().rows = rows
    end
    local r = rows[encounterID]
    if not r then
        r = {}
        rows[encounterID] = r
    end
    r.hidden = r.hidden or {}
    r.custom = r.custom or {}
    return r
end

local function changed(encounterID)
    cache[encounterID] = nil
    CRT.Timeline:Fire()
end

-- The Journal root section of the boss in the instance that is selected right now, or nil.
local function rootInSelected(encounterID)
    local j = 1
    while j < 100 do
        local ok, _, _, journalID = pcall(EJ_GetEncounterInfoByIndex, j)
        if not ok or not journalID then
            return nil
        end
        local ok2, _, _, _, rootSectionID, _, _, dungeonEncounterID = pcall(EJ_GetEncounterInfo, journalID)
        if ok2 and dungeonEncounterID == encounterID then
            return rootSectionID
        end
        j = j + 1
    end
end

-- The Journal root section of a boss (by dungeon encounter id), or nil when it cannot be found.
local function findRoot(encounterID)
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex and EJ_GetEncounterInfo) then
        return nil
    end
    -- the instance the Journal has selected now, to put back afterwards
    local previous
    if EJ_GetCurrentInstance then
        local ok, id = pcall(EJ_GetCurrentInstance)
        previous = ok and id or nil
    elseif EncounterJournal then
        previous = EncounterJournal.instanceID
    end
    local root
    -- the instance of the map we stand on
    if EJ_GetInstanceForMap and C_Map and C_Map.GetBestMapForUnit then
        local okMap, map = pcall(C_Map.GetBestMapForUnit, "player")
        if okMap and map then
            local okInst, instanceID = pcall(EJ_GetInstanceForMap, map)
            if okInst and instanceID and instanceID ~= 0 then
                pcall(EJ_SelectInstance, instanceID)
                root = rootInSelected(encounterID)
            end
        end
    end
    -- otherwise every raid of the current tier
    if not root and EJ_GetInstanceByIndex then
        local i = 1
        while i < 100 do
            local ok, instanceID = pcall(EJ_GetInstanceByIndex, i, true)
            if not ok or not instanceID then
                break
            end
            pcall(EJ_SelectInstance, instanceID)
            root = rootInSelected(encounterID)
            if root then
                break
            end
            i = i + 1
        end
    end
    if previous and previous ~= 0 then
        local now
        if EJ_GetCurrentInstance then
            local ok, id = pcall(EJ_GetCurrentInstance)
            now = ok and id or nil
        end
        if now ~= previous then
            pcall(EJ_SelectInstance, previous)
        end
    end
    return root
end

-- Every ability section under root, depth first in Journal order: children, then siblings.
local function collect(root, rows, seen)
    local visited = {}
    local function walk(id)
        while id and id ~= 0 and not visited[id] do
            visited[id] = true
            local ok, info = pcall(C_EncounterJournal.GetSectionInfo, id)
            if not ok or type(info) ~= "table" then
                return
            end
            local spellID = info.spellID
            if type(spellID) == "number" and spellID > 0 and not seen[spellID] then
                seen[spellID] = true
                local okName, name = pcall(C_Spell.GetSpellName, spellID)
                local okIcon, icon = pcall(C_Spell.GetSpellTexture, spellID)
                rows[#rows + 1] = {
                    spellID = spellID,
                    name = (okName and name) or info.title or "",
                    icon = (okIcon and icon) or info.abilityIcon,
                    own = false,
                }
            end
            walk(info.firstChildSectionID)
            id = info.siblingSectionID
        end
    end
    walk(root)
end

-- The rows of a boss: Journal abilities, then your own. Empty in combat or while the Journal is
-- open (nothing cached then). When the Journal does not know the boss only your own spells are
-- listed, and that miss is remembered until the zone changes so the Journal is not walked again.
function Journal:Rows(encounterID)
    -- a reference timeline has no encounter id to look up (its key is text), so never walk for it
    if type(encounterID) ~= "number" then
        return {}
    end
    if cache[encounterID] then
        return cache[encounterID]
    end
    if InCombatLockdown() or (EncounterJournal and EncounterJournal:IsShown()) then
        return {}
    end
    local rows, seen = {}, {}
    local root
    if not missed[encounterID] then
        root = findRoot(encounterID)
        if not root then
            missed[encounterID] = true
        end
    end
    if root then
        collect(root, rows, seen)
    end
    local mine = settings().rows and settings().rows[encounterID]
    if mine and mine.custom then
        for _, spellID in ipairs(mine.custom) do
            if not seen[spellID] then
                seen[spellID] = true
                local okName, name = pcall(C_Spell.GetSpellName, spellID)
                local okIcon, icon = pcall(C_Spell.GetSpellTexture, spellID)
                rows[#rows + 1] = { spellID = spellID, name = (okName and name) or tostring(spellID), icon = okIcon and icon or nil, own = true }
            end
        end
    end
    if root then
        cache[encounterID] = rows
    end
    return rows
end

function Journal:AddCustom(encounterID, spellID)
    local r = bossRows(encounterID)
    for _, id in ipairs(r.custom) do
        if id == spellID then
            return
        end
    end
    r.custom[#r.custom + 1] = spellID
    changed(encounterID)
end

function Journal:RemoveCustom(encounterID, spellID)
    local r = bossRows(encounterID)
    for i, id in ipairs(r.custom) do
        if id == spellID then
            table.remove(r.custom, i)
            break
        end
    end
    changed(encounterID)
end

function Journal:SetHidden(encounterID, spellID, hidden)
    bossRows(encounterID).hidden[spellID] = hidden and true or nil
    changed(encounterID)
end

function Journal:IsHidden(encounterID, spellID)
    local r = settings().rows and settings().rows[encounterID]
    return (r and r.hidden and r.hidden[spellID]) and true or false
end
