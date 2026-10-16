local ADDON, CRT = ...

-- Consumables: the status of each ready check slot. The list comes from two places:
--   * the list that ships with the addon, Consumables/Database.lua, and
--   * the player's own additions, saved in CRTDB.consumables.extra, added by dragging an item
--     from the bags onto the bar on the Consumables tab. They are optional.
-- The player also chooses the order, and the buff of an item is learned the first time it is used.
-- Saved in CRTDB.consumables:
--   categoryOrder = { "flask", "food", ... }       order of the icons
--   itemOrder[category] = { itemId, itemId, ... }  which item is used first
--   extra[category] = { { item, name }, ... }      the player's own additions
--   learned[itemId] = spellId                      buffs worked out from use

local Consumables = { listeners = {} }
CRT.Consumables = Consumables

Consumables.QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Default icon order, left to right.
-- kind "buff": a buff with a timer, falling back to a bag count when it is missing.
-- kind "count": only a bag count. kind "weapon": a temporary weapon enchant.
-- clickable: clicking the icon on the row uses the first listed item that is in your bags. Every
-- category is, except potions: the potion icon only shows how many you have, so none is used before
-- the pull by mistake.
Consumables.CATEGORIES = {
    { key = "food", label = "Food", kind = "buff", clickable = true },
    { key = "flask", label = "Flask", kind = "buff", clickable = true },
    { key = "potion", label = "Potion", kind = "count" },
    { key = "weapon", label = "Weapon oil/stone", kind = "weapon", clickable = true },
    { key = "rune", label = "Augment rune", kind = "buff", clickable = true },
}

local byKey = {}
for _, def in ipairs(Consumables.CATEGORIES) do
    byKey[def.key] = def
end

-- A buff has to last at least this long to be learned as an item's buff, which skips short procs.
local LEARN_MIN_SECONDS = 300
local LEARN_GIVE_UP_SECONDS = 90

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

-- Each category's list, built once and kept until something that changes it calls Fire. The bar and
-- the ready check read the lists twice a second, so rebuilding them every time made a lot of garbage.
local entriesCache = {}

function Consumables:Fire()
    wipe(entriesCache)
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

function Consumables:Def(key)
    return byKey[key]
end

-- Food ---------------------------------------------------------------------------------
-- Food is one hardcoded check: a buff from foodBuffs in Database.lua, or, on an English client, any
-- buff with "Well Fed" in its name (a feast gives "Hearty Well Fed"). The food list is only for
-- clicking: which food your bar eats.

function Consumables:FoodBuffIds()
    local out = {}
    for _, entry in ipairs(CRT.ConsumablesDB.foodBuffs or {}) do
        out[entry.buff] = entry
    end
    return out
end

function Consumables.IsFoodName(name)
    return type(name) == "string" and name:find("Well Fed", 1, true) ~= nil
end

-- Options ---------------------------------------------------------------------

function Consumables:Enabled()
    return cdb().enabled
end

function Consumables:SetEnabled(value)
    cdb().enabled = value and true or false
    self:Fire()
end

-- True when your bar should stay hidden on a ready check you started yourself.
function Consumables:NotStarter()
    return cdb().notStarter and true or false
end

function Consumables:SetNotStarter(value)
    cdb().notStarter = value and true or false
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

-- Where the ready check bar sits. Without a saved position it goes above the ready check dialog.
function Consumables:Position()
    return cdb().position
end

function Consumables:SavePosition(point, relativePoint, x, y)
    cdb().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

function Consumables:ResetPosition()
    cdb().position = nil
    self:Fire()
end

-- The shipped list ------------------------------------------------------------

function Consumables:Database()
    return CRT.ConsumablesDB
end

-- Moves one id to a place in a list of ids (1 is first), returning the new list.
local function movedTo(list, id, index)
    local out = {}
    for _, v in ipairs(list) do
        if v ~= id then
            out[#out + 1] = v
        end
    end
    table.insert(out, math.max(1, math.min(#out + 1, index)), id)
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

-- Puts a category at a place in the icon order, 1 being leftmost.
function Consumables:MoveCategoryTo(key, index)
    cdb().categoryOrder = movedTo(self:Order(), key, index)
    self:Fire()
end

-- Entries for a category: the shipped ones, then the player's own, rearranged by the player's
-- saved order. Each is { item, buff, name, best, low, user, category }. The list is shared until the
-- next change, so callers must not change it.
function Consumables:Entries(key)
    local cached = entriesCache[key]
    if cached then
        return cached
    end
    local byItem, base = {}, {}
    local function add(entry, user)
        if entry.item and not byItem[entry.item] then
            local e = { item = entry.item, buff = entry.buff, name = entry.name, best = entry.best, low = entry.low, user = user, category = key }
            byItem[entry.item] = e
            base[#base + 1] = e
        end
    end
    for _, entry in ipairs((self:Database().categories or {})[key] or {}) do
        add(entry, false)
    end
    for _, entry in ipairs(cdb().extra[key] or {}) do
        add(entry, true)
    end

    local out, seen = {}, {}
    for _, id in ipairs(cdb().itemOrder[key] or {}) do
        local e = byItem[id]
        if e and not seen[id] then
            out[#out + 1] = e
            seen[id] = true
        end
    end
    for _, e in ipairs(base) do
        if not seen[e.item] then
            out[#out + 1] = e
            seen[e.item] = true
        end
    end
    return out
end

-- Puts an item at a place in its category's list, 1 being used first.
function Consumables:MoveItemTo(key, itemId, index)
    local ids = {}
    for _, entry in ipairs(self:Entries(key)) do
        ids[#ids + 1] = entry.item
    end
    cdb().itemOrder[key] = movedTo(ids, itemId, index)
    self:Fire()
end

-- Item and bag helpers ----------------------------------------------------------
-- Your bags are read again only after the game reports a change (BAG_UPDATE_DELAYED), and item counts
-- are kept until then too. Reading every bag slot twice a second made thousands of tables a minute.

local bagNames = {} -- names of items in your bags, keyed by item ID; the game's own name is what /use needs
-- Item IDs in your bags by name. Crafted consumables come in quality ranks with an item ID each but
-- the same name, so a listed item also counts its other ranks found in your bags this way.
local bagByName = {}
local countCache = {} -- item ID -> count in your bags, until the bags change
local bagsDirty = true

local function itemInfo(itemId)
    local ok, id, _, _, _, icon, classId = pcall(C_Item.GetItemInfoInstant, itemId)
    if ok and id then
        return icon, classId
    end
    return nil
end

local function itemIcon(itemId)
    return (itemInfo(itemId))
end

local function itemCount(itemId)
    local cached = countCache[itemId]
    if cached then
        return cached
    end
    local ok, count = pcall(C_Item.GetItemCount, itemId)
    if ok and type(count) == "number" then
        countCache[itemId] = count
        return count
    end
    return 0
end

-- The buff spell ID for an entry: the one listed, else the one learned from use, else (for
-- flasks and runes) the item's use spell. Food has no such fallback, because the use spell of
-- food is the eating buff and not the long Well Fed buff.
local function buffId(entry)
    if entry.buff then
        return entry.buff
    end
    local learned = cdb().learned[entry.item]
    if learned then
        return learned
    end
    if entry.category ~= "food" then
        local ok, _, spellId = pcall(C_Item.GetItemSpell, entry.item)
        if ok and type(spellId) == "number" then
            return spellId
        end
    end
    return nil
end

-- The buff spell IDs listed or learned for a category, for checking other players: { [spellId] = entry }.
function Consumables:BuffIds(key)
    local out = {}
    for _, entry in ipairs(self:Entries(key)) do
        local id = buffId(entry)
        if id then
            out[id] = entry
        end
    end
    return out
end

-- Reads your bags if they changed since the last read, or always with force.
function Consumables:RefreshBags(force)
    if not bagsDirty and not force then
        return
    end
    bagsDirty = false
    wipe(bagNames)
    wipe(bagByName)
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
                local ids = bagByName[info.itemName]
                if not ids then
                    ids = {}
                    bagByName[info.itemName] = ids
                end
                ids[#ids + 1] = info.itemID
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

-- A readable name for an entry: from your bags, else the game cache, else the saved label.
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

-- An item's crafted quality rank (1, 2, ...), or 0 when it has none or the game doesn't say.
local function qualityRank(id)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo
    if not api then
        return 0
    end
    local ok, quality = pcall(api, id)
    return (ok and type(quality) == "number") and quality or 0
end

-- The fleeting version of an item, from a cauldron: the same name with "Fleeting " in front.
local FLEETING = "Fleeting "

-- The item IDs in your bags for an entry: its own ID, its other quality ranks (items of the same
-- name) and its fleeting versions, in the order a click should use them: fleeting first, then the
-- highest rank. Each is { id, fleeting }. Read from the last bag read.
local function bagIds(entry)
    local name = Consumables:ItemName(entry)
    local out, seen = {}, {}
    local function add(id, fleeting)
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = { id = id, fleeting = fleeting, rank = qualityRank(id) }
        end
    end
    for _, id in ipairs(bagByName[FLEETING .. name] or {}) do
        add(id, true)
    end
    if bagNames[entry.item] then
        add(entry.item, false)
    end
    for _, id in ipairs(bagByName[name] or {}) do
        add(id, false)
    end
    table.sort(out, function(a, b)
        if a.fleeting ~= b.fleeting then
            return a.fleeting
        end
        if a.rank ~= b.rank then
            return a.rank > b.rank
        end
        return a.id < b.id
    end)
    return out
end
Consumables.BagIds = bagIds

-- The entry a click on this slot should use. Fleeting items (which expire) come first, in your
-- item order, then the first listed item in your bags at its highest quality rank. Returns
-- { id, name, icon, count } or nil. The name is the one the game gave your bags.
function Consumables:NextItem(key)
    local entries = self:Entries(key)
    for _, fleetingPass in ipairs({ true, false }) do
        for _, entry in ipairs(entries) do
            for _, found in ipairs(bagIds(entry)) do
                local count = itemCount(found.id)
                if found.fleeting == fleetingPass and count > 0 and bagNames[found.id] then
                    return { id = found.id, name = bagNames[found.id], icon = itemIcon(found.id), count = count }
                end
            end
        end
    end
    return nil
end

-- The player's own additions ---------------------------------------------------------

-- Adds an item to a category's own list. Returns ok, message.
function Consumables:AddExtra(key, itemId)
    local def = byKey[key]
    if not def then
        return false, "Unknown category."
    end
    local icon, classId = itemInfo(itemId)
    if not icon then
        return false, "The game doesn't know that item."
    end
    if classId ~= 0 then
        return false, "That isn't a consumable."
    end
    for _, entry in ipairs(self:Entries(key)) do
        if entry.item == itemId then
            return false, "That item is already in the " .. def.label:lower() .. " list."
        end
    end

    self:RefreshBags(true)
    local name = bagNames[itemId]
    if not name then
        local ok, cached = pcall(C_Item.GetItemNameByID, itemId)
        name = ok and cached or nil
    end
    local list = cdb().extra[key]
    if not list then
        list = {}
        cdb().extra[key] = list
    end
    list[#list + 1] = { item = itemId, name = name }
    self:Fire()

    local note = ""
    if def.kind == "buff" and not buffId({ item = itemId, category = key }) then
        note = " Use one and I'll learn its buff."
    end
    return true, "Added " .. (name or ("item " .. itemId)) .. " to " .. def.label:lower() .. "." .. note
end

-- Adds the item you are dragging from your bags. Returns ok, message.
function Consumables:AddFromCursor(key)
    local kind, itemId = GetCursorInfo()
    if kind ~= "item" or type(itemId) ~= "number" then
        return false, "Drag an item from your bags onto an icon."
    end
    ClearCursor() -- the item stays in your bags
    return self:AddExtra(key, itemId)
end

function Consumables:RemoveExtra(key, itemId)
    local list = cdb().extra[key]
    if not list then
        return
    end
    for i, entry in ipairs(list) do
        if entry.item == itemId then
            table.remove(list, i)
            break
        end
    end
    self:Fire()
end

-- Auras on you --------------------------------------------------------------------

-- Readable helpful buffs on you: { { id, name, left (seconds or nil) }, ... }.
local function helpfulAuras()
    local out = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return out
    end
    for index = 1, 80 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok or not aura then
            break
        end
        local id, name, expires, icon = aura.spellId, aura.name, aura.expirationTime, aura.icon
        if not (isSecret(id) or isSecret(name) or isSecret(expires)) and id then
            local left = (type(expires) == "number" and expires > 0) and (expires - GetTime()) or nil
            out[#out + 1] = { id = id, name = name, left = left, icon = (not isSecret(icon)) and icon or nil }
        end
    end
    return out
end

-- Learning which buff an item gives -------------------------------------------------
-- When you use an item whose buff is not known, the buff that appears and lasts a while is
-- recorded as that item's buff. Two new buffs at once is too ambiguous, so it waits or gives up.

local learnTarget = {} -- itemId -> { baseline = { [spellId]=true }, started, newIds = {} }
local lastCounts = {} -- itemId -> bag count at the last check
local lastAuraIds = {} -- spellId -> true at the last check
local learnElapsed = 0
local learnNotice
-- The check runs only after the game reports a change to your bags or buffs, or while it is waiting
-- for a buff to appear, so it costs nothing while nothing changes.
local bagsChanged, aurasChanged = true, true

local function auraSet(list)
    local set = {}
    for _, aura in ipairs(list) do
        set[aura.id] = aura
    end
    return set
end

local function unknownBuffEntries()
    local out = {}
    for _, def in ipairs(Consumables.CATEGORIES) do
        if def.kind == "buff" and def.key ~= "food" then
            for _, entry in ipairs(Consumables:Entries(def.key)) do
                if not buffId(entry) then
                    out[#out + 1] = entry
                end
            end
        end
    end
    return out
end

local function learnPoll()
    if InCombatLockdown() then
        return
    end
    if not bagsChanged and not aurasChanged and not next(learnTarget) then
        return
    end
    local checkBags = bagsChanged
    bagsChanged, aurasChanged = false, false
    local current = auraSet(helpfulAuras())

    -- Notice a used item: its bag count went down since the last check.
    if checkBags then
        for _, entry in ipairs(unknownBuffEntries()) do
            local count = itemCount(entry.item)
            local before = lastCounts[entry.item]
            if before and count < before and not learnTarget[entry.item] then
                learnTarget[entry.item] = { baseline = lastAuraIds, started = GetTime() }
            end
            lastCounts[entry.item] = count
        end
    end

    -- Look for the buff that appeared.
    local now = GetTime()
    for itemId, target in pairs(learnTarget) do
        local fresh = {}
        for id, aura in pairs(current) do
            local long = aura.left and aura.left >= LEARN_MIN_SECONDS
            if long and not target.baseline[id] then
                fresh[#fresh + 1] = aura
            end
        end
        local age = now - target.started
        if #fresh == 1 then
            cdb().learned[itemId] = fresh[1].id
            learnTarget[itemId] = nil
            learnNotice = nil
            CRT:Print(format("Learned the buff for %s: %s.", Consumables:ItemName({ item = itemId }), tostring(fresh[1].name)))
            Consumables:Fire()
        elseif #fresh > 1 and age > 30 then
            learnTarget[itemId] = nil
            CRT:Print(format("Couldn't tell which buff %s gives, because several appeared at once. Use one again when nothing else is buffing you.", Consumables:ItemName({ item = itemId })))
        elseif age > LEARN_GIVE_UP_SECONDS then
            learnTarget[itemId] = nil
        end
    end

    -- Remember what you have now, as the baseline for the next use.
    local snapshot = {}
    for id in pairs(current) do
        snapshot[id] = true
    end
    lastAuraIds = snapshot
end

-- A short line for the page when something is being learned.
function Consumables:LearningText()
    local waiting = {}
    for itemId in pairs(learnTarget) do
        waiting[#waiting + 1] = Consumables:ItemName({ item = itemId })
    end
    if #waiting > 0 then
        return "Learning the buff for " .. table.concat(waiting, ", ") .. "..."
    end
    local pending = unknownBuffEntries()
    if #pending > 0 then
        return #pending .. " item(s) will learn their buff the first time you use them."
    end
    return ""
end

local learnFrame = CreateFrame("Frame")
learnFrame:RegisterEvent("BAG_UPDATE_DELAYED")
learnFrame:RegisterUnitEvent("UNIT_AURA", "player")
learnFrame:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        bagsChanged = true
        bagsDirty = true
        wipe(countCache)
    else
        aurasChanged = true
    end
end)
learnFrame:SetScript("OnUpdate", function(_, dt)
    learnElapsed = learnElapsed + dt
    if learnElapsed < 1 then
        return
    end
    learnElapsed = 0
    if CRT.db then
        learnPoll()
    end
end)

-- Status ------------------------------------------------------------------

-- Everything in your bags for a category, every quality rank included. A rank in your bags under
-- two entries (one listed by ID, the other by its name) is counted once.
local function totalCount(entries)
    local total, counted = 0, {}
    for _, entry in ipairs(entries) do
        if not counted[entry.item] then
            counted[entry.item] = true
            total = total + itemCount(entry.item)
        end
        for _, found in ipairs(bagIds(entry)) do
            if not counted[found.id] then
                counted[found.id] = true
                total = total + itemCount(found.id)
            end
        end
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
                local expires, icon, name = aura.expirationTime, aura.icon, aura.name
                if isSecret(expires) or isSecret(icon) then
                    unknown = true
                else
                    local left = (type(expires) == "number" and expires > 0) and (expires - GetTime()) or nil
                    if not best or (left or math.huge) > (best.left or math.huge) then
                        best = { left = left, icon = icon, name = (not isSecret(name)) and name or nil }
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
-- "unset" means nothing is listed for this category yet.
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
            status.name = enchant.label == "OH" and "Off hand" or "Main hand"
            status.charges = enchant.charges and enchant.charges > 0 and enchant.charges or nil
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
    local best, unknown
    if key == "food" then
        -- The longest food buff on you, by the hardcoded food check.
        local ids = self:FoodBuffIds()
        for _, aura in ipairs(helpfulAuras()) do
            if ids[aura.id] or Consumables.IsFoodName(aura.name) then
                if not best or (aura.left or math.huge) > (best.left or math.huge) then
                    best = aura
                end
            end
        end
    else
        best, unknown = bestBuff(entries)
    end
    if best then
        status.icon = best.icon or status.icon
        status.left = best.left
        status.name = best.name
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
    for _, aura in ipairs(helpfulAuras()) do
        if not seen[aura.id] then
            seen[aura.id] = true
            lines[#lines + 1] = format("buff = %d, -- %s (icon %s)", aura.id, tostring(aura.name), tostring(aura.icon))
        end
    end
    if #lines == 1 then
        lines[#lines + 1] = "-- (none readable)"
    end

    -- Weapon oils and stones are enchants, not buffs, so they are listed apart.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "-- Weapon enchants (oils and stones) on you right now."
    local anyEnchant = false
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        for _, slot in ipairs({ { INVSLOT_MAINHAND or 16, "Main hand" }, { INVSLOT_OFFHAND or 17, "Off hand" } }) do
            local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, slot[1])
            if ok and type(info) == "table" then
                anyEnchant = true
                local parts = {}
                for k, v in pairs(info) do
                    if not isSecret(v) then
                        parts[#parts + 1] = k .. " = " .. tostring(v)
                    end
                end
                table.sort(parts)
                lines[#lines + 1] = format("-- %s: %s", slot[2], table.concat(parts, ", "))
            end
        end
    end
    if not anyEnchant then
        lines[#lines + 1] = "-- (none)"
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

-- Checks every entry, shipped and your own, against the game, so a wrong ID is caught.
function Consumables:CheckText()
    local db = self:Database()
    local lines = { format("Consumables list: %s, updated %s", tostring(db.expansion), tostring(db.updated)) }
    local problems, total = 0, 0
    for _, def in ipairs(self.CATEGORIES) do
        local entries = self:Entries(def.key)
        lines[#lines + 1] = ""
        lines[#lines + 1] = format("%s (%d listed)", def.label, #entries)
        for _, entry in ipairs(entries) do
            total = total + 1
            local label = (entry.name or ("item " .. tostring(entry.item))) .. (entry.user and " (yours)" or "")
            local notes, info = {}, nil
            if not itemIcon(entry.item) then
                notes[#notes + 1] = "ITEM ID NOT FOUND"
            end
            if def.key == "food" then
                info = "checked by the food buff, whatever was eaten"
            elseif def.kind == "buff" then
                local bid = buffId(entry)
                if not bid then
                    info = "buff is learned the first time you use it"
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
                lines[#lines + 1] = format("  ok       %s%s", label, info and (" (" .. info .. ")") or "")
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Food buffs (any of these counts as fed)"
    for _, entry in ipairs(db.foodBuffs or {}) do
        total = total + 1
        local ok, icon = pcall(C_Spell.GetSpellTexture, entry.buff)
        if ok and icon then
            lines[#lines + 1] = format("  ok       %s (%d)", tostring(entry.name), entry.buff)
        else
            problems = problems + 1
            lines[#lines + 1] = format("  PROBLEM  %s: BUFF ID %d NOT FOUND", tostring(entry.name), entry.buff)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = format("%d entries checked, %d with problems.", total, problems)
    return table.concat(lines, "\n")
end
