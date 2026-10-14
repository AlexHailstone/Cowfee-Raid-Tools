local ADDON, CRT = ...

-- The raid report: checks every group member's food, flask, augment rune, Vantus rune and raid buffs,
-- shows the result to you or posts it to chat, and can run on its own on a ready check or a pull timer.
-- Other players' buffs are read with C_UnitAuras. They are secret in combat, encounters, Mythic+ and
-- PvP, and may be secret inside raid instances too (the 12.0.5 SecretOnRestrictedMaps rule), so a
-- player whose buffs cannot be read is listed as "couldn't check", never as missing.
-- Settings are in CRTDB.readycheck.

local Report = { last = {} }
CRT.RaidReport = Report

local Consumables = CRT.Consumables

local CHAT_MAX = 250 -- a chat line can hold 255 characters

-- Raid buffs, each given by one class. A buff is found by its spell ID or by that spell's name, since
-- Blessing of the Bronze gives a differently numbered buff to each class. IDs are the retail spell IDs
-- linked from each Warcraft Wiki page, read 2026-10-14.
-- short is the ready check window's column heading.
Report.BUFFS = {
    { key = "intellect", spell = 1459, class = "MAGE", label = "Arcane Intellect", short = "Int" },
    { key = "stamina", spell = 21562, class = "PRIEST", label = "Power Word: Fortitude", short = "Stam" },
    { key = "attack", spell = 6673, class = "WARRIOR", label = "Battle Shout", short = "AP" },
    { key = "versatility", spell = 1126, class = "DRUID", label = "Mark of the Wild", short = "Vers" },
    { key = "mastery", spell = 462854, class = "SHAMAN", label = "Skyfury", short = "Mast" },
    { key = "movement", spell = 364342, class = "EVOKER", label = "Blessing of the Bronze", short = "Move" },
}

-- The checks, in the order they show and post.
Report.CHECKS = {
    { key = "food", label = "Food" },
    { key = "flask", label = "Flask" },
    { key = "rune", label = "Augment rune" },
    { key = "vantus", label = "Vantus rune" },
    { key = "buffs", label = "Raid buffs" },
}

-- Until the consumables list in Consumables/Database.lua is filled in, buffs are also found by their
-- English names. This only works on an English game client. Food is matched by "Well Fed" anywhere in
-- the name, since a feast gives "Hearty Well Fed".
local FALLBACK = {
    food = function(name)
        return CRT.Consumables.IsFoodName(name)
    end,
    flask = function(name)
        return name:find("^Flask") ~= nil or name:find("^Phial") ~= nil
    end,
    rune = function(name)
        return name:find("Augment") ~= nil
    end,
    vantus = function(name)
        return name:find("^Vantus Rune") ~= nil
    end,
}

local function settings()
    return CRT.db.readycheck
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Group members ---------------------------------------------------------------

local function units()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            out[#out + 1] = "raid" .. i
        end
    else
        out[1] = "player"
        for i = 1, GetNumSubgroupMembers() do
            out[#out + 1] = "party" .. i
        end
    end
    return out
end

-- Helpful auras on a unit: { { id, name, left }, ... }, or nil and why they couldn't be read.
local function unitAuras(unit)
    if not UnitIsConnected(unit) then
        return nil, "offline"
    end
    if not UnitIsUnit(unit, "player") and not UnitIsVisible(unit) then
        return nil, "too far away"
    end
    local out = {}
    for index = 1, 80 do
        local ok, id, name, expires, icon = pcall(function()
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
            if not aura then
                return nil
            end
            return aura.spellId, aura.name, aura.expirationTime, aura.icon
        end)
        if not ok then
            return nil, "unreadable"
        end
        if id == nil then
            break
        end
        if isSecret(id) or isSecret(name) or isSecret(expires) then
            return nil, "hidden by the game"
        end
        local left = (type(expires) == "number" and expires > 0) and (expires - GetTime()) or nil
        out[#out + 1] = { id = id, name = name or "", left = left, icon = (not isSecret(icon)) and icon or nil }
    end
    return out
end

-- A unit's raid group: from the raid roster in a raid, 1 in a party or solo.
local function subgroupOf(unit)
    local index = unit:match("^raid(%d+)$")
    if index then
        local _, _, subgroup = GetRaidRosterInfo(tonumber(index))
        if subgroup and not isSecret(subgroup) then
            return subgroup
        end
    end
    return 1
end

-- Your role from your current specialization, for when the group has not assigned one.
local function specRole()
    local info = C_SpecializationInfo
    local getSpec = (info and info.GetSpecialization) or GetSpecialization
    local getRole = (info and info.GetSpecializationRole) or GetSpecializationRole
    if not getSpec or not getRole then
        return nil
    end
    local ok, role = pcall(function()
        local spec = getSpec()
        return spec and getRole(spec)
    end)
    return ok and role or nil
end

local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

-- TANK, HEALER or DAMAGER, or nil. The role the group assigned, else your spec's role for you, else
-- the last role the Raid Groups page saw for that player.
local function roleOf(unit, name)
    local role = UnitGroupRolesAssigned(unit)
    if isSecret(role) or not ROLES[role] then
        role = nil
    end
    if not role and UnitIsUnit(unit, "player") then
        role = specRole()
    end
    if not role and CRT.Groups then
        role = CRT.Groups.CachedRole(CRT.Groups.Normalize(name))
    end
    return ROLES[role] and role or nil
end

-- Everyone in the group with their class, raid group, role and buffs, in raid order (order).
-- Players whose buffs can't be read have auras = nil.
local function readGroup()
    local members = {}
    for _, unit in ipairs(units()) do
        local name = GetUnitName(unit, true)
        if name and not isSecret(name) then
            local _, class = UnitClass(unit)
            local auras, why = unitAuras(unit)
            members[#members + 1] = {
                unit = unit,
                name = Ambiguate(name, "short"),
                class = (not isSecret(class)) and class or nil,
                subgroup = subgroupOf(unit),
                role = roleOf(unit, name),
                order = #members + 1,
                auras = auras,
                why = why,
            }
        end
    end
    return members
end

-- Checks ------------------------------------------------------------------------

-- The longest-lasting aura on a member matching the IDs or the fallback name. Returns aura, entry.
local function findAura(auras, ids, fallback)
    local best, bestEntry
    for _, aura in ipairs(auras) do
        local entry = ids[aura.id]
        if entry or (fallback and fallback(aura.name)) then
            if not best or (aura.left or math.huge) > (best.left or math.huge) then
                best, bestEntry = aura, entry
            end
        end
    end
    return best, bestEntry
end

local function minutesLeft(seconds)
    return math.max(1, math.floor(seconds / 60 + 0.5)) .. " min"
end

-- Food is one hardcoded check, whatever was eaten: the food buffs in Consumables/Database.lua, or a
-- buff with "Well Fed" in its name.
local function foodIds()
    return Consumables:FoodBuffIds(), FALLBACK.food
end

-- One consumable check. Returns { missing = {}, notes = {}, unknown = {}, total }.
local function checkConsumable(key, members)
    local result = { missing = {}, notes = {}, unknown = {}, total = #members }
    local ids, fallback
    if key == "food" then
        ids, fallback = foodIds()
    elseif key == "vantus" then
        ids, fallback = {}, FALLBACK.vantus
    else
        ids, fallback = Consumables:BuffIds(key), FALLBACK[key]
    end
    local s = settings()
    for _, m in ipairs(members) do
        if not m.auras then
            result.unknown[#result.unknown + 1] = m.name .. " (" .. m.why .. ")"
        else
            local aura, entry = findAura(m.auras, ids, fallback)
            if not aura then
                result.missing[#result.missing + 1] = m.name
            elseif key == "flask" and s.lowFlask and entry and entry.low then
                result.notes[#result.notes + 1] = m.name .. " (lower quality)"
            elseif key == "flask" and (s.flaskWarn or 0) > 0 and aura.left and aura.left < s.flaskWarn * 60 then
                result.notes[#result.notes + 1] = m.name .. " (" .. minutesLeft(aura.left) .. ")"
            end
        end
    end
    return result
end

-- Raid buffs your group can give, and who is missing each. Returns { buffs = { {label, missing} },
-- notInGroup = { labels }, unknown = {} }.
local function checkBuffs(members)
    local classes = {}
    for _, m in ipairs(members) do
        if m.class then
            classes[m.class] = true
        end
    end
    local result = { buffs = {}, notInGroup = {}, unknown = {}, total = #members }
    for _, m in ipairs(members) do
        if not m.auras then
            result.unknown[#result.unknown + 1] = m.name .. " (" .. m.why .. ")"
        end
    end
    for _, buff in ipairs(Report.BUFFS) do
        if classes[buff.class] then
            local spellName = C_Spell.GetSpellName(buff.spell)
            local missing = {}
            for _, m in ipairs(members) do
                if m.auras then
                    local found = false
                    for _, aura in ipairs(m.auras) do
                        if aura.id == buff.spell or (spellName and aura.name == spellName) then
                            found = true
                            break
                        end
                    end
                    if not found then
                        missing[#missing + 1] = m.name
                    end
                end
            end
            result.buffs[#result.buffs + 1] = { label = spellName or buff.label, missing = missing }
        else
            result.notInGroup[#result.notInGroup + 1] = C_Spell.GetSpellName(buff.spell) or buff.label
        end
    end
    return result
end

-- The ready check window -----------------------------------------------------------------

function Report:ReadGroup()
    return readGroup()
end

-- The classes in a group read by ReadGroup, as a set.
function Report.Classes(members)
    local classes = {}
    for _, m in ipairs(members) do
        if m.class then
            classes[m.class] = true
        end
    end
    return classes
end

local buffByKey = {}
for _, buff in ipairs(Report.BUFFS) do
    buffByKey[buff.key] = buff
end
Report.BuffByKey = buffByKey

-- One cell of the ready check window, for a consumable key or a raid buff key:
-- { state = "ok" | "low" | "missing" | "unknown", icon, left }. "low" is an expiring or lower quality flask.
function Report.Cell(member, key)
    if not member.auras then
        return { state = "unknown", why = member.why }
    end
    local aura, entry
    local buff = buffByKey[key]
    if buff then
        local spellName = C_Spell.GetSpellName(buff.spell)
        for _, a in ipairs(member.auras) do
            if a.id == buff.spell or (spellName and a.name == spellName) then
                aura = a
                break
            end
        end
    else
        local ids, fallback
        if key == "food" then
            ids, fallback = foodIds()
        elseif key == "vantus" then
            ids, fallback = {}, FALLBACK.vantus
        else
            ids, fallback = Consumables:BuffIds(key), FALLBACK[key]
        end
        aura, entry = findAura(member.auras, ids, fallback)
    end
    if not aura then
        return { state = "missing" }
    end
    local s = settings()
    local state = "ok"
    if key == "flask" and ((s.lowFlask and entry and entry.low) or ((s.flaskWarn or 0) > 0 and aura.left and aura.left < s.flaskWarn * 60)) then
        state = "low"
    end
    return { state = state, icon = aura.icon, left = aura.left, name = aura.name }
end

-- Text --------------------------------------------------------------------------------

local function labelOf(key)
    for _, check in ipairs(Report.CHECKS) do
        if check.key == key then
            return check.label
        end
    end
    return key
end

local function unknownText(unknown)
    if #unknown == 0 then
        return nil
    end
    return "couldn't check " .. table.concat(unknown, ", ")
end

-- Chat lines for one check. A line for every buff that someone is missing.
local function linesFor(key, members)
    local lines = {}
    if key == "buffs" then
        local r = checkBuffs(members)
        for _, b in ipairs(r.buffs) do
            if #b.missing > 0 then
                lines[#lines + 1] = b.label .. " missing: " .. table.concat(b.missing, ", ")
            end
        end
        if #lines == 0 then
            lines[1] = #r.buffs > 0 and "Raid buffs: everyone has them" or "Raid buffs: nobody in the group gives one"
        end
        local u = unknownText(r.unknown)
        if u then
            lines[#lines + 1] = "Raid buffs: " .. u
        end
        return lines, r
    end
    local r = checkConsumable(key, members)
    local parts = {}
    if #r.missing > 0 then
        parts[#parts + 1] = "missing " .. table.concat(r.missing, ", ")
    end
    if #r.notes > 0 then
        parts[#parts + 1] = (key == "flask" and "check " or "") .. table.concat(r.notes, ", ")
    end
    local u = unknownText(r.unknown)
    if u then
        parts[#parts + 1] = u
    end
    if #parts == 0 then
        parts[1] = "everyone has it"
    end
    lines[1] = labelOf(key) .. ": " .. table.concat(parts, "; ")
    return lines, r
end

-- Runs one check, or every key in the list, and remembers the result for the page.
function Report:Run(keys)
    local members = readGroup()
    local all = {}
    for _, key in ipairs(keys) do
        local lines = linesFor(key, members)
        self.last[key] = { lines = lines, at = time() }
        for _, line in ipairs(lines) do
            all[#all + 1] = line
        end
    end
    return all
end

-- Output --------------------------------------------------------------------------------

-- Splits a line longer than one chat message at the commas.
local function chunks(line)
    if #line <= CHAT_MAX then
        return { line }
    end
    local out, current = {}, ""
    for piece in line:gmatch("[^,]+,?") do
        if #current + #piece > CHAT_MAX and current ~= "" then
            out[#out + 1] = current
            current = "  " .. strtrim(piece)
        else
            current = current .. piece
        end
    end
    if current ~= "" then
        out[#out + 1] = current
    end
    return out
end

local function groupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

-- output is "self", "raid" or "officer". Anything that can't go to chat is printed to you instead.
function Report:Output(lines, output)
    local channel
    if output == "raid" then
        channel = groupChannel()
    elseif output == "officer" then
        channel = "OFFICER"
    end
    for _, line in ipairs(lines) do
        local sent = false
        if channel and send then
            sent = true
            for _, part in ipairs(chunks(line)) do
                local ok = pcall(send, "[CRT] " .. part, channel)
                sent = sent and ok
            end
        end
        if not sent then
            CRT:Print(line)
        end
    end
end

-- Checks the keys given and shows or posts them. toChat posts to the chosen channel, otherwise only you see it.
function Report:Check(keys, toChat)
    if InCombatLockdown() then
        CRT:Print("Buffs can't be checked in combat.")
        return
    end
    local lines = self:Run(keys)
    self:Output(lines, toChat and (settings().output ~= "self" and settings().output or "raid") or "self")
    if self.onChange then
        self.onChange()
    end
end

-- The checks ticked under "Include in the report".
function Report:Included()
    local keys = {}
    for _, check in ipairs(Report.CHECKS) do
        if settings().include[check.key] then
            keys[#keys + 1] = check.key
        end
    end
    return keys
end

-- Automatic report ------------------------------------------------------------------------

local function inLFR()
    local _, _, difficultyId = GetInstanceInfo()
    return difficultyId == 7 or difficultyId == 17
end

-- startedByMe: you started the ready check or pull timer. Only then does the report go to chat, so a
-- raid full of this addon posts it once.
local function autoReport(startedByMe)
    local s = settings()
    if not s.auto or InCombatLockdown() then
        return
    end
    if s.raidsOnly and not IsInRaid() then
        return
    end
    if s.notLFR and inLFR() then
        return
    end
    local keys = Report:Included()
    if #keys == 0 then
        return
    end
    local lines = Report:Run(keys)
    Report:Output(lines, startedByMe and s.output or "self")
    if Report.onChange then
        Report.onChange()
    end
end

local function isMe(name, guid)
    if guid and not isSecret(guid) and guid == UnitGUID("player") then
        return true
    end
    if name and not isSecret(name) then
        return Ambiguate(name, "short") == UnitName("player")
    end
    return false
end

local events = CreateFrame("Frame")
events:RegisterEvent("READY_CHECK")
events:RegisterEvent("START_PLAYER_COUNTDOWN")
events:SetScript("OnEvent", function(_, event, ...)
    if not CRT.db then
        return
    end
    if event == "READY_CHECK" then
        local initiator = ...
        autoReport(isMe(initiator))
    elseif event == "START_PLAYER_COUNTDOWN" and settings().onPull then
        local initiatedBy, _, _, _, initiatedByName = ...
        autoReport(isMe(initiatedByName, initiatedBy))
    end
end)
