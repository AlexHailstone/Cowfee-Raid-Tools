local ADDON, CRT = ...

-- Consumables: the status of each ready check slot, computed from the shipped list in
-- Consumables/Database.lua. Players only choose the order, saved in CRTDB.consumables:
--   categoryOrder = { "flask", "food", ... }       order of the icons
--   itemOrder[category] = { itemId, itemId, ... }  which item is used first

local Consumables = { listeners = {} }
CRT.Consumables = Consumables

Consumables.QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Default icon order, left to right.
-- kind "buff": a buff with a timer, falling back to a bag count when it is missing.
-- kind "count": only a bag count. kind "weapon": a temporary weapon enchant.
-- clickable: clicking the icon on the row uses the first listed item that is in your bags.
Consumables.CATEGORIES = {
    { key = "food", label = "Food", kind = "buff", clickable = true },
    { key = "flask", label = "Flask", kind = "buff", clickable = true },
    { key = "potion", label = "Potion", kind = "count" },
    { key = "weapon", label = "Weapon oil or stone", kind = "weapon", clickable = true },
    { key = "rune", label = "Augment rune", kind = "buff" },
}

local byKey = {}
for _, def in ipairs(Consumables.CATEGORIES) do
    byKey[def.key] = def
end

local function cdb()
    return CRT.db.consumables
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Change notifications ----------------------------------------------------

function Consumables:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Consumables:Fire()
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

function Consumables:Def(key)
    return byKey[key]
end

-- Options ---------------------------------------------------------------------

function Consumables:Enabled()
    return cdb().enabled
end

function Consumables:SetEnabled(value)
    cdb().enabled = value and true or false
    self:Fire()
end

function Consumables:LowMinutes()
    return cdb().lowMinutes
end

function Consumables:SetLowMinutes(minutes)
    minutes = tonumber(minutes)
    if minutes then
        cdb().lowMinutes = math.max(1, math.min(240, math.floor(minutes)))
    end
    self:Fire()
end

-- The shipped list ------------------------------------------------------------

function Consumables:Database()
    return CRT.ConsumablesDB
end

-- Moves one id by delta positions within a list of ids, returning the new list.
local function moved(list, id, delta)
    local out = {}
    for i, v in ipairs(list) do
        out[i] = v
    end
    for i, v in ipairs(out) do
        if v == id then
            local j = i + delta
            if j >= 1 and j <= #out then
                out[i], out[j] = out[j], out[i]
            end
            break
        end
    end
    return out
end

-- Category keys in the player's order. New categories added later go at the end.
function Consumables:Order()
    local out, seen = {}, {}
    for _, key in ipairs(cdb().categoryOrder) do
        if byKey[key] and not seen[key] then
            out[#out + 1] = key
            seen[key] = true
        end
    end
    for _, def in ipairs(self.CATEGORIES) do
        if not seen[def.key] then
            out[#out + 1] = def.key
        end
    end
    return out
end

function Consumables:MoveCategory(key, delta)
    cdb().categoryOrder = moved(self:Order(), key, delta)
    self:Fire()
end

-- The listed entries for a category, in the player's order, with new list entries after
-- the ones they have arranged. Each entry is { item, buff, name }.
function Consumables:Entries(key)
    local list = (self:Database().categories or {})[key] or {}
    local byItem = {}
    for _, entry in ipairs(list) do
        if entry.item then
            byItem[entry.item] = entry
        end
    end
    local out, seen = {}, {}
    for _, id in ipairs(cdb().itemOrder[key] or {}) do
        local entry = byItem[id]
        if entry and not seen[id] then
            out[#out + 1] = entry
            seen[id] = true
        end
    end
    for _, entry in ipairs(list) do
        if entry.item and not seen[entry.item] then
            out[#out + 1] = entry
            seen[entry.item] = true
        end
    end
    return out
end

function Consumables:MoveItem(key, itemId, delta)
    local ids = {}
    for _, entry in ipairs(self:Entries(key)) do
        ids[#ids + 1] = entry.item
    end
    cdb().itemOrder[key] = moved(ids, itemId, delta)
    self:Fire()
end

-- Item and bag helpers ----------------------------------------------------------

local function itemIcon(itemId)
    local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, itemId)
    if ok and icon then
        return icon
    end
    return nil
end

local function itemCount(itemId)
    local ok, count = pcall(C_Item.GetItemCount, itemId)
    if ok and type(count) == "number" then
        return count
    end
    return 0
end

-- The buff spell ID for an entry: the one listed, else the item's use spell.
local function buffId(entry)
    if entry.buff then
        return entry.buff
    end
    local ok, _, spellId = pcall(C_Item.GetItemSpell, entry.item)
    if ok and type(spellId) == "number" then
        return spellId
    end
    return nil
end

-- Names of items in your bags, keyed by item ID. The game's own name is what /use needs.
local bagNames = {}

function Consumables:RefreshBags()
    wipe(bagNames)
    if not (C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerNumSlots) then
        return
    end
    -- 0 is the backpack, 1 to 4 are bags, 5 is the reagent bag.
    for bag = 0, 5 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and info.itemName and not bagNames[info.itemID] then
                bagNames[info.itemID] = info.itemName
            end
        end
    end
end

function Consumables:ItemIcon(itemId)
    return itemIcon(itemId) or Consumables.QUESTION_MARK
end

function Consumables:ItemCount(itemId)
    return itemCount(itemId)
end

-- A readable name for an entry: from your bags, else the game cache, else the file's label.
function Consumables:ItemName(entry)
    if bagNames[entry.item] then
        return bagNames[entry.item]
    end
    local ok, name = pcall(C_Item.GetItemNameByID, entry.item)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return entry.name or ("Item " .. entry.item)
end

-- The entry a click on this slot should use: the first listed item that is in your bags.
-- Returns { id, name, icon, count } or nil. The name is the one the game gave your bags.
function Consumables:NextItem(key)
    for _, entry in ipairs(self:Entries(key)) do
        local count = itemCount(entry.item)
        if count > 0 and bagNames[entry.item] then
            return { id = entry.item, name = bagNames[entry.item], icon = itemIcon(entry.item), count = count }
        end
    end
    return nil
end

-- Total of every listed item in your bags.
local function totalCount(entries)
    local total = 0
    for _, entry in ipairs(entries) do
        total = total + itemCount(entry.item)
    end
    return total
end

local function defaultIcon(entries)
    for _, entry in ipairs(entries) do
        local icon = itemIcon(entry.item)
        if icon then
            return icon
        end
    end
    for _, entry in ipairs(entries) do
        local id = buffId(entry)
        if id then
            local ok, icon = pcall(C_Spell.GetSpellTexture, id)
            if ok and icon then
                return icon
            end
        end
    end
    return Consumables.QUESTION_MARK
end

local function aurasRestricted()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and not isSecret(restricted) and restricted then
            return true
        end
    end
    return false
end

-- The longest-lasting listed buff on you. Returns best, unknown.
local function bestBuff(entries)
    local best, unknown
    local tried = {}
    for _, entry in ipairs(entries) do
        local id = buffId(entry)
        if id and not tried[id] then
            tried[id] = true
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if not ok then
                unknown = true
            elseif aura then
                local expires, icon = aura.expirationTime, aura.icon
                if isSecret(expires) or isSecret(icon) then
                    unknown = true
                else
                    local left = (type(expires) == "number" and expires > 0) and (expires - GetTime()) or nil
                    if not best or (left or math.huge) > (best.left or math.huge) then
                        best = { left = left, icon = icon }
                    end
                end
            end
        end
    end
    return best, unknown
end

-- A temporary weapon enchant on the main or off hand: { label, left, charges } or nil.
-- C_PaperDollInfo.GetTemporaryEnchantmentInfo replaces GetWeaponEnchantInfo (deprecated in 12.1.0).
local function weaponEnchant()
    local slots = { { INVSLOT_MAINHAND or 16, "MH" }, { INVSLOT_OFFHAND or 17, "OH" } }
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        for _, slot in ipairs(slots) do
            local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, slot[1])
            if ok and type(info) == "table" then
                local ms = info.remainingTimeMs
                local left = (info.hasExpirationTime ~= false and type(ms) == "number") and ms / 1000 or nil
                return { label = slot[2], left = left, charges = info.chargesRemaining }
            end
        end
        return nil
    end
    if GetWeaponEnchantInfo then
        local hasMain, mainMs, mainCharges, _, hasOff, offMs, offCharges = GetWeaponEnchantInfo()
        if hasMain then
            return { label = "MH", left = type(mainMs) == "number" and mainMs / 1000 or nil, charges = mainCharges }
        elseif hasOff then
            return { label = "OH", left = type(offMs) == "number" and offMs / 1000 or nil, charges = offCharges }
        end
    end
    return nil
end

-- Status of one slot for the row:
-- { key, icon, left (seconds or nil), count (number or nil), tag ("MH"/"OH" or nil),
--   state = "active" | "low" | "missing" | "unknown" | "unset" }
-- "unset" means the shipped list has nothing for this category yet.
function Consumables:Status(key)
    local def = byKey[key]
    local entries = self:Entries(key)
    local status = { key = key, icon = defaultIcon(entries), state = "missing" }

    -- A weapon slot needs no list, since any temporary enchant counts.
    if def.kind ~= "weapon" and #entries == 0 then
        status.state = "unset"
        return status
    end

    local lowSeconds = (cdb().lowMinutes or 10) * 60

    if def.kind == "count" then
        status.count = totalCount(entries)
        status.state = status.count > 0 and "active" or "missing"
        return status
    end

    if def.kind == "weapon" then
        status.tag = "MH"
        local enchant = weaponEnchant()
        if enchant then
            status.tag = enchant.label
            status.left = enchant.left
            status.count = enchant.charges and enchant.charges > 0 and enchant.charges or nil
            local mainhand = GetInventoryItemTexture and GetInventoryItemTexture("player", INVSLOT_MAINHAND or 16)
            if status.icon == Consumables.QUESTION_MARK and mainhand then
                status.icon = mainhand
            end
            status.state = (enchant.left and enchant.left < lowSeconds) and "low" or "active"
        else
            status.count = totalCount(entries)
        end
        return status
    end

    -- Buff categories.
    if aurasRestricted() then
        status.state = "unknown"
        return status
    end
    local best, unknown = bestBuff(entries)
    if best then
        status.icon = best.icon or status.icon
        status.left = best.left
        status.state = (best.left and best.left < lowSeconds) and "low" or "active"
    elseif unknown then
        status.state = "unknown"
    else
        status.count = totalCount(entries)
    end
    return status
end

-- Maintainer tools: text for the scan and check commands ---------------------------

-- Your current buffs and the consumables in your bags, as lines to paste into Database.lua.
function Consumables:ScanText()
    local lines = { "-- Helpful buffs on you right now. Use the ID as buff = <ID>." }
    local seen = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, 80 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
            if not ok or not aura then
                break
            end
            local id, name = aura.spellId, aura.name
            if not (isSecret(id) or isSecret(name)) and id and not seen[id] then
                seen[id] = true
                lines[#lines + 1] = format("buff = %d, -- %s", id, tostring(name))
            end
        end
    end
    if #lines == 1 then
        lines[#lines + 1] = "-- (none readable)"
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "-- Consumable items in your bags. Use the ID as item = <ID>."
    local items, count = {}, 0
    if C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerNumSlots then
        for bag = 0, 5 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID and not items[info.itemID] then
                    local ok, _, _, subType, _, _, classId = pcall(C_Item.GetItemInfoInstant, info.itemID)
                    if ok and classId == 0 then
                        items[info.itemID] = true
                        count = count + 1
                        lines[#lines + 1] = format("item = %d, -- %s (%s)", info.itemID, tostring(info.itemName), tostring(subType))
                    end
                end
            end
        end
    end
    if count == 0 then
        lines[#lines + 1] = "-- (no consumables found)"
    end
    return table.concat(lines, "\n")
end

-- Checks every entry in the shipped list against the game, so a wrong ID is caught.
function Consumables:CheckText()
    local db = self:Database()
    local lines = { format("Consumables list: %s, updated %s", tostring(db.expansion), tostring(db.updated)) }
    local problems, total = 0, 0
    for _, def in ipairs(self.CATEGORIES) do
        local list = (db.categories or {})[def.key] or {}
        lines[#lines + 1] = ""
        lines[#lines + 1] = format("%s (%d listed)", def.label, #list)
        for _, entry in ipairs(list) do
            total = total + 1
            local label = entry.name or ("item " .. tostring(entry.item))
            local notes = {}
            if not entry.item then
                notes[#notes + 1] = "no item ID"
            else
                local ok, id = pcall(C_Item.GetItemInfoInstant, entry.item)
                if not (ok and id) then
                    notes[#notes + 1] = "ITEM ID NOT FOUND"
                end
            end
            if def.kind == "buff" then
                local bid = entry.item and buffId(entry)
                if not bid then
                    notes[#notes + 1] = "no buff ID (add buff = <ID>)"
                else
                    local ok, icon = pcall(C_Spell.GetSpellTexture, bid)
                    if not (ok and icon) then
                        notes[#notes + 1] = "BUFF ID " .. bid .. " NOT FOUND"
                    end
                end
            end
            if #notes > 0 then
                problems = problems + 1
                lines[#lines + 1] = format("  PROBLEM  %s: %s", label, table.concat(notes, ", "))
            else
                lines[#lines + 1] = format("  ok       %s", label)
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = format("%d entries checked, %d with problems.", total, problems)
    return table.concat(lines, "\n")
end
