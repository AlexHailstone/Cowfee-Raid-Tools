local ADDON, CRT = ...

-- Cooldowns: a built-in list of healer cooldowns and raid defensives, for the Timeline's Cooldowns row
-- under the templates.
-- Last checked: 12.1.5 (spell IDs written from memory, not yet confirmed in game)
-- The list is checked on every patch pass. Spells the game doesn't know are skipped at runtime, so a
-- stale ID silently disappears from the row instead of erroring. Each one dragged onto the timeline opens the alert editor on a new alert with its
-- spell. The names beside the IDs are for the reader only: what shows is the game's own name, and an
-- entry the game doesn't know (no readable name) is left out. CRT.db.alerts.cooldownFilter keeps the
-- row's choice: "mine" (your class, else the healer cooldowns), "all", "healer", "raid" or a class token.

local Cooldowns = {}
CRT.AlertCooldowns = Cooldowns

local TEXT = {
    mine = "Your class",
    all = "All",
    healer = "Healer cooldowns",
    raid = "Raid defensives",
}

-- { class, spellID, kind }: kind is "healer" (a healer's cooldown) or "raid" (a raid defensive).
local LIST = {
    { class = "DRUID", spellID = 740, kind = "healer" }, -- Tranquility
    { class = "DRUID", spellID = 33891, kind = "healer" }, -- Incarnation: Tree of Life
    { class = "DRUID", spellID = 391528, kind = "healer" }, -- Convoke the Spirits
    { class = "DRUID", spellID = 197721, kind = "healer" }, -- Flourish
    { class = "EVOKER", spellID = 363534, kind = "healer" }, -- Rewind
    { class = "EVOKER", spellID = 359816, kind = "healer" }, -- Dream Flight
    { class = "EVOKER", spellID = 370960, kind = "healer" }, -- Emerald Communion
    { class = "EVOKER", spellID = 370537, kind = "healer" }, -- Stasis
    { class = "EVOKER", spellID = 374227, kind = "raid" }, -- Zephyr
    { class = "MONK", spellID = 115310, kind = "healer" }, -- Revival
    { class = "MONK", spellID = 388615, kind = "healer" }, -- Restoral
    { class = "MONK", spellID = 322118, kind = "healer" }, -- Invoke Yu'lon, the Jade Serpent
    { class = "MONK", spellID = 325197, kind = "healer" }, -- Invoke Chi-Ji, the Red Crane
    { class = "MONK", spellID = 116849, kind = "healer" }, -- Life Cocoon
    { class = "PALADIN", spellID = 31821, kind = "healer" }, -- Aura Mastery
    { class = "PALADIN", spellID = 31884, kind = "healer" }, -- Avenging Wrath
    { class = "PALADIN", spellID = 375576, kind = "healer" }, -- Divine Toll
    { class = "PALADIN", spellID = 6940, kind = "healer" }, -- Blessing of Sacrifice
    { class = "PRIEST", spellID = 64843, kind = "healer" }, -- Divine Hymn
    { class = "PRIEST", spellID = 265202, kind = "healer" }, -- Holy Word: Salvation
    { class = "PRIEST", spellID = 200183, kind = "healer" }, -- Apotheosis
    { class = "PRIEST", spellID = 62618, kind = "healer" }, -- Power Word: Barrier
    { class = "PRIEST", spellID = 47536, kind = "healer" }, -- Rapture
    { class = "PRIEST", spellID = 246287, kind = "healer" }, -- Evangelism
    { class = "PRIEST", spellID = 33206, kind = "healer" }, -- Pain Suppression
    { class = "PRIEST", spellID = 47788, kind = "healer" }, -- Guardian Spirit
    { class = "SHAMAN", spellID = 108280, kind = "healer" }, -- Healing Tide Totem
    { class = "SHAMAN", spellID = 98008, kind = "healer" }, -- Spirit Link Totem
    { class = "SHAMAN", spellID = 114052, kind = "healer" }, -- Ascendance
    { class = "WARRIOR", spellID = 97462, kind = "raid" }, -- Rallying Cry
    { class = "DEMONHUNTER", spellID = 196718, kind = "raid" }, -- Darkness
    { class = "DEATHKNIGHT", spellID = 51052, kind = "raid" }, -- Anti-Magic Zone
    { class = "DRUID", spellID = 106898, kind = "raid" }, -- Stampeding Roar
}
Cooldowns.LIST = LIST

local function readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

local function hasClass(token)
    for _, e in ipairs(LIST) do
        if e.class == token then
            return true
        end
    end
    return false
end

-- The player's class token, when the game gives a readable one.
local function playerClass()
    if not UnitClass then
        return nil
    end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and token ~= nil and readable(token) and type(token) == "string" and token ~= "" then
        return token
    end
    return nil
end

-- The game's name for spellID, else nil (unknown, secret or empty).
local function spellName(id)
    if not (C_Spell and C_Spell.GetSpellName) then
        return nil
    end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and name ~= nil and readable(name) and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function spellIcon(id)
    if not (C_Spell and C_Spell.GetSpellTexture) then
        return nil
    end
    local ok, tex = pcall(C_Spell.GetSpellTexture, id)
    if ok and tex ~= nil and readable(tex) and (type(tex) == "number" or type(tex) == "string") then
        return tex
    end
    return nil
end

-- The filter "mine" stands for: your class when it has entries, else "healer".
function Cooldowns.Resolve(filter)
    filter = filter or "mine"
    if filter == "mine" then
        local token = playerClass()
        return token and hasClass(token) and token or "healer"
    end
    return filter
end

local function matches(e, filter)
    if filter == "all" then
        return true
    elseif filter == "healer" or filter == "raid" then
        return e.kind == filter
    end
    return e.class == filter
end

-- { { spellID, name, icon, class, kind } } in list order, for filter ("mine" when nil). Only spells the
-- game knows by a readable name are listed; icon is nil when the game gives none that can be read.
function Cooldowns:List(filter)
    filter = Cooldowns.Resolve(filter)
    local out = {}
    for _, e in ipairs(LIST) do
        if matches(e, filter) then
            local name = spellName(e.spellID)
            if name then
                out[#out + 1] = { spellID = e.spellID, name = name, icon = spellIcon(e.spellID), class = e.class, kind = e.kind }
            end
        end
    end
    return out
end

-- A class token's name as the game shows it, else the token.
function Cooldowns.ClassName(token)
    local names = LOCALIZED_CLASS_NAMES_MALE
    local name = type(names) == "table" and names[token] or nil
    if name ~= nil and readable(name) and type(name) == "string" and name ~= "" then
        return name
    end
    return token
end

-- The row's dropdown options, in order: { { key, label } }. Your class, All, Healer cooldowns, Raid
-- defensives, then each class with entries by its name.
function Cooldowns:Filters()
    local out = {
        { key = "mine", label = TEXT.mine },
        { key = "all", label = TEXT.all },
        { key = "healer", label = TEXT.healer },
        { key = "raid", label = TEXT.raid },
    }
    local seen, classes = {}, {}
    for _, e in ipairs(LIST) do
        if not seen[e.class] then
            seen[e.class] = true
            classes[#classes + 1] = { key = e.class, label = Cooldowns.ClassName(e.class) }
        end
    end
    table.sort(classes, function(a, b)
        return a.label < b.label
    end)
    for _, c in ipairs(classes) do
        out[#out + 1] = c
    end
    return out
end

-- The stored filter, "mine" when none is kept.
function Cooldowns:Filter()
    local db = CRT.db and CRT.db.alerts
    local f = db and db.cooldownFilter
    return type(f) == "string" and f ~= "" and f or "mine"
end

function Cooldowns:SetFilter(filter)
    local db = CRT.db and CRT.db.alerts
    if db and type(filter) == "string" and filter ~= "" then
        db.cooldownFilter = filter
    end
end
