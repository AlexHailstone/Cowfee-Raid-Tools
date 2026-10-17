local ADDON, CRT = ...

-- Cooldowns: the healer cooldowns and raid defensives the Timeline's Cooldowns row lists, under the
-- templates. The list itself is season data in Alerts/CooldownData.lua (CRT.AlertCooldownData), checked
-- on every patch pass. Each one dragged onto the timeline opens the alert editor on a new alert with its
-- spell. An entry the game doesn't know (no readable name) is left out at runtime, so an ID deleted
-- outright drops off the row; a removed or reworked talent may still have a name and keep showing, which
-- only the patch-pass check catches. CRT.db.alerts.cooldownFilter keeps the row's choice: "mine" (your
-- class, else the healer cooldowns), "all", "healer", "raid" or a class token in the list; anything else
-- reads as "mine".

local Cooldowns = {}
CRT.AlertCooldowns = Cooldowns

local TEXT = {
    mine = "Your class",
    all = "All",
    healer = "Healer cooldowns",
    raid = "Raid defensives",
}

-- { class, spellID, kind } entries, from Alerts/CooldownData.lua; kind is "healer" or "raid".
local LIST = CRT.AlertCooldownData or {}
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

local KINDS = { mine = true, all = true, healer = true, raid = true }

-- The stored filter: "mine" when none is kept, or when it is no longer one of the choices (a class the
-- list has no entries for, or anything else).
function Cooldowns:Filter()
    local db = CRT.db and CRT.db.alerts
    local f = db and db.cooldownFilter
    if type(f) == "string" and (KINDS[f] or hasClass(f)) then
        return f
    end
    return "mine"
end

function Cooldowns:SetFilter(filter)
    local db = CRT.db and CRT.db.alerts
    if db and type(filter) == "string" and filter ~= "" then
        db.cooldownFilter = filter
    end
end
