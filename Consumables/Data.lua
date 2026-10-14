local ADDON, CRT = ...

-- Consumables: which buffs and bag items count as a flask, food, potion, weapon oil or
-- augment rune, and the current status of each for the ready check row.
-- The lists are saved in CRTDB.consumables and edited on the Consumables page, not in code.

local Consumables = { listeners = {} }
CRT.Consumables = Consumables

Consumables.QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Order here is the order of the icons, left to right.
-- kind "buff": a buff with a timer, falling back to a bag count when it is missing.
-- kind "count": only a bag count. kind "weapon": a temporary weapon enchant.
-- clickable: clicking the icon on the row uses the first assigned item that is in your bags.
-- Set clickable on potion or rune to make those icons clickable too.
Consumables.CATEGORIES = {
    { key = "food", label = "Food", kind = "buff", clickable = true },
    { key = "flask", label = "Flask", kind = "buff", clickable = true },
    { key = "potion", label = "Potion", kind = "count" },
    { key = "weapon", label = "Weapon oil or stone", kind = "weapon", clickable = true },
    { key = "rune", label = "Augment rune", kind = "buff" },
}

local function cdb()
    return CRT.db.consumables
end

local function category(key)
    local c = cdb().categories[key]
    if type(c) ~= "table" then
        c = { buffs = {}, items = {} }
        cdb().categories[key] = c
    end
    c.buffs = c.buffs or {}
    c.items = c.items or {}
    return c
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

-- Assigned buffs and items -------------------------------------------------

function Consumables:AddBuff(key, spellId, name, icon)
    category(key).buffs[spellId] = { name = name or ("Spell " .. spellId), icon = icon }
    self:Fire()
end

function Consumables:RemoveBuff(key, spellId)
    category(key).buffs[spellId] = nil
    self:Fire()
end

function Consumables:AddItem(key, itemId, name, icon)
    category(key).items[itemId] = { name = name or ("Item " .. itemId), icon = icon }
    self:Fire()
end

function Consumables:RemoveItem(key, itemId)
    category(key).items[itemId] = nil
    self:Fire()
end

-- Entries as a list sorted by name, for the page: { id, name, icon }.
function Consumables:List(key, which)
    local out = {}
    for id, entry in pairs(category(key)[which]) do
        out[#out + 1] = { id = id, name = entry.name or tostring(id), icon = entry.icon }
    end
    table.sort(out, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return out
end

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

-- Scanning what you have right now -----------------------------------------

-- Helpful buffs on you: { id = spellId, name, icon }. Used by "Add from my buffs".
function Consumables:ScanBuffs()
    local out, seen = {}, {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return out
    end
    for index = 1, 80 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok or not aura then
            break
        end
        local spellId, name, icon = aura.spellId, aura.name, aura.icon
        if not (isSecret(spellId) or isSecret(name) or isSecret(icon)) and spellId and not seen[spellId] then
            seen[spellId] = true
            out[#out + 1] = { id = spellId, name = name, icon = icon }
        end
    end
    table.sort(out, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Items in your bags, totalled by item: { id = itemId, name, icon, count }.
function Consumables:ScanBags()
    local byItem, out = {}, {}
    if not (C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerNumSlots) then
        return out
    end
    -- 0 is the backpack, 1 to 4 are bags, 5 is the reagent bag.
    for bag = 0, 5 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local entry = byItem[info.itemID]
                if not entry then
                    entry = { id = info.itemID, name = info.itemName or ("Item " .. info.itemID), icon = info.iconFileID, count = 0 }
                    byItem[info.itemID] = entry
                    out[#out + 1] = entry
                end
                entry.count = entry.count + (info.stackCount or 1)
            end
        end
    end
    table.sort(out, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Status ------------------------------------------------------------------

local function itemCount(c)
    local total = 0
    for itemId in pairs(c.items) do
        local ok, count = pcall(C_Item.GetItemCount, itemId)
        if ok and type(count) == "number" then
            total = total + count
        end
    end
    return total
end

-- The item a click on this slot should use: the first assigned item (by name) that is in
-- your bags. Returns { id, name, icon, count } or nil.
function Consumables:NextItem(key)
    for _, entry in ipairs(self:List(key, "items")) do
        local ok, count = pcall(C_Item.GetItemCount, entry.id)
        if ok and type(count) == "number" and count > 0 then
            return { id = entry.id, name = entry.name, icon = entry.icon, count = count }
        end
    end
    return nil
end

local function defaultIcon(c)
    for _, entry in pairs(c.items) do
        if entry.icon then
            return entry.icon
        end
    end
    for _, entry in pairs(c.buffs) do
        if entry.icon then
            return entry.icon
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

-- The longest-lasting matching buff on you. Returns best, unknown.
local function bestBuff(c)
    local best, unknown
    for spellId in pairs(c.buffs) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
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
-- { key, label, icon, left (seconds or nil), count (number or nil),
--   state = "active" | "low" | "missing" | "unknown" | "unset", tag ("MH"/"OH" or nil) }
function Consumables:Status(key)
    local c = category(key)
    local kind
    for _, def in ipairs(self.CATEGORIES) do
        if def.key == key then
            kind = def.kind
            break
        end
    end

    local status = { key = key, icon = defaultIcon(c), state = "missing" }
    -- A weapon slot needs no list, since any temporary enchant counts. The items only
    -- supply the icon and the bag count.
    local assigned = kind == "weapon" or next(c.buffs) ~= nil or next(c.items) ~= nil
    if not assigned then
        status.state = "unset"
        return status
    end

    local lowSeconds = (cdb().lowMinutes or 10) * 60

    if kind == "count" then
        status.count = itemCount(c)
        status.state = status.count > 0 and "active" or "missing"
        return status
    end

    if kind == "weapon" then
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
            status.count = itemCount(c)
        end
        return status
    end

    -- Buff categories.
    if aurasRestricted() then
        status.state = "unknown"
        return status
    end
    local best, unknown = bestBuff(c)
    if best then
        status.icon = best.icon or status.icon
        status.left = best.left
        status.state = (best.left and best.left < lowSeconds) and "low" or "active"
    elseif unknown then
        status.state = "unknown"
    else
        status.count = itemCount(c)
    end
    return status
end
