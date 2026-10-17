local ADDON, CRT = ...

local Groups = { listeners = {} }
CRT.Groups = Groups

local NUM_SLOTS = 40
Groups.NUM_SLOTS = NUM_SLOTS

local function gdb()
    return CRT.db.groups
end

-- Names ------------------------------------------------------------------

-- Every stored name is "Name-Realm" so same-name players on different realms stay distinct.
function Groups.Normalize(name)
    if type(name) ~= "string" then
        return ""
    end
    name = strtrim(name)
    if name == "" then
        return ""
    end
    if not name:find("-", 1, true) then
        local realm = GetNormalizedRealmName()
        if realm and realm ~= "" then
            name = name .. "-" .. realm
        end
    end
    return name
end

function Groups.Display(key)
    if not key or key == "" then
        return ""
    end
    return Ambiguate(key, "none")
end

-- A name for reports, chat posts and Discord exports (the Late Tracker and Tattlebot): without its
-- realm when "Leave realm names out" is ticked on General Settings, else as Display shows it.
function Groups.ReportName(key)
    if not key or key == "" then
        return ""
    end
    if CRT.db.ui.hideRealms then
        return Ambiguate(key, "short")
    end
    return Ambiguate(key, "none")
end

-- classOverride is the live class of a matched group member, if any.
function Groups.ClassColor(key, classOverride)
    local class = classOverride or (key and CRT.db.classCache[key:lower()])
    local color = class and RAID_CLASS_COLORS[class]
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

-- Last role seen for this name, so players who aren't in the group right now keep their icon.
function Groups.CachedRole(key)
    return key and CRT.db.roleCache[key:lower()]
end

local function cacheClass(key, class)
    if class then
        CRT.db.classCache[key:lower()] = class
    end
end

local function cacheRole(key, role)
    if role then
        CRT.db.roleCache[key:lower()] = role
    end
end

-- Rosters ----------------------------------------------------------------

local function playerSpecRole()
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

-- TANK, HEALER or DAMAGER, or nil when unknown. Your own role falls back to your spec.
local function unitRole(unit)
    local role = UnitGroupRolesAssigned(unit)
    if (not role or role == "NONE") and UnitIsUnit(unit, "player") then
        role = playerSpecRole() or role
    end
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return nil
end

-- Current group. Raid members keep their subgroup; party and solo are treated as group 1,
-- so you always appear in your own roster. Returns { {key, subgroup, class, role}, ... }.
function Groups:ReadRoster()
    local out = {}
    local function add(key, subgroup, classFile, role)
        cacheClass(key, classFile)
        cacheRole(key, role)
        out[#out + 1] = { key = key, subgroup = subgroup, class = classFile, role = role }
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup, _, _, classFile = GetRaidRosterInfo(i)
            if name then
                add(self.Normalize(name), subgroup, classFile, unitRole("raid" .. i))
            end
        end
    else
        local units = { "player" }
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
        for _, unit in ipairs(units) do
            local name, realm = UnitFullName(unit)
            if name then
                if realm and realm ~= "" then
                    name = name .. "-" .. realm
                end
                local _, classFile = UnitClass(unit)
                add(self.Normalize(name), 1, classFile, unitRole(unit))
            end
        end
    end
    return out
end

-- Returns a function key -> roster entry (or nil). A name stored without a realm
-- also matches a same-named member when that match is unambiguous (cross-realm players).
function Groups.MakeLookup(roster)
    local byKey, byBase = {}, {}
    for _, entry in ipairs(roster) do
        local lower = entry.key:lower()
        byKey[lower] = entry
        local base = lower:match("^[^-]+") or lower
        byBase[base] = (byBase[base] == nil) and entry or false
    end
    local ownRealm = (GetNormalizedRealmName() or ""):lower()
    return function(key)
        local lower = key:lower()
        if byKey[lower] then
            return byKey[lower]
        end
        if lower:match("%-(.+)$") == ownRealm then
            return byBase[lower:match("^[^-]+") or lower] or nil
        end
    end
end

function Groups:ReadGuild()
    local out = {}
    if not IsInGuild() then
        return out
    end
    for i = 1, GetNumGuildMembers() do
        local fullName, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if fullName then
            local key = self.Normalize(fullName)
            cacheClass(key, classFile)
            out[#out + 1] = { key = key, class = classFile }
        end
    end
    return out
end

-- Working grid -----------------------------------------------------------

local function copySlots(src)
    local out = {}
    for i = 1, NUM_SLOTS do
        local v = src and src[i]
        out[i] = (type(v) == "string") and v or ""
    end
    return out
end

-- The grid being edited: 40 slots, slot = (group - 1) * 5 + position, "" when empty.
function Groups:Working()
    local g = gdb()
    if type(g.working) ~= "table" then
        g.working = {}
    end
    for i = 1, NUM_SLOTS do
        if type(g.working[i]) ~= "string" then
            g.working[i] = ""
        end
    end
    return g.working
end

-- The names in the active layout (Active: the roster the raid runs with, set by "Use This Group"), in
-- slot order, each once: { key, ... }. Never the working grid, which is a draft. Empty when no layout is
-- active.
function Groups:ActiveNames()
    local id = self:Active()
    local preset = id and self:Find(id)
    local slots = preset and preset.slots
    local out, seen = {}, {}
    if type(slots) ~= "table" then
        return out
    end
    for i = 1, NUM_SLOTS do
        local key = slots[i]
        if type(key) == "string" and key ~= "" and not seen[key:lower()] then
            seen[key:lower()] = true
            out[#out + 1] = key
        end
    end
    return out
end

function Groups:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Groups:Fire()
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

-- Called after every edit. Auto-saves to the selected preset when "Keep changes" is on.
function Groups:Touch()
    local g = gdb()
    self.dirty = true
    if g.keepChanges and g.selected then
        self:CommitSelected()
    end
    self:Fire()
end

function Groups:SetSlot(index, key)
    local w = self:Working()
    key = self.Normalize(key)
    if key ~= "" then
        local lower = key:lower()
        for j = 1, NUM_SLOTS do
            if j ~= index and w[j] ~= "" and w[j]:lower() == lower then
                w[j] = ""
            end
        end
    end
    w[index] = key
    self:Touch()
end

function Groups:Swap(a, b)
    local w = self:Working()
    w[a], w[b] = w[b], w[a]
    self:Touch()
end

function Groups:ReplaceWorking(slots)
    local g = gdb()
    g.working = copySlots(slots)
    self:Touch()
end

-- Presets ----------------------------------------------------------------

function Groups:Presets()
    return gdb().presets
end

function Groups:Find(id)
    for i, p in ipairs(gdb().presets) do
        if p.id == id then
            return p, i
        end
    end
end

local function nameTaken(name)
    local lower = name:lower()
    for _, p in ipairs(gdb().presets) do
        if p.name:lower() == lower then
            return true
        end
    end
    return false
end

local function uniqueName(name)
    name = strtrim(name or "")
    if name == "" then
        name = "Layout"
    end
    name = name:sub(1, 40)
    if not nameTaken(name) then
        return name
    end
    local n = 2
    while nameTaken(name .. " (" .. n .. ")") do
        n = n + 1
    end
    return name .. " (" .. n .. ")"
end

function Groups:CreatePreset(name, slots)
    local g = gdb()
    local preset = { id = g.nextId, name = uniqueName(name), slots = copySlots(slots) }
    g.nextId = g.nextId + 1
    g.presets[#g.presets + 1] = preset
    table.sort(g.presets, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    self:Fire()
    return preset.id
end

-- Renames a saved layout. Returns the name actually used, which gains " (2)" etc. if it
-- clashes with another layout. A blank name or an unchanged name does nothing.
function Groups:Rename(id, name)
    local preset = self:Find(id)
    if not preset then
        return
    end
    name = strtrim(name or ""):sub(1, 40)
    if name == "" or name == preset.name then
        return preset.name
    end
    preset.name = ""
    preset.name = uniqueName(name)
    table.sort(gdb().presets, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    self:Fire()
    return preset.name
end

function Groups:Select(id)
    local preset = self:Find(id)
    if not preset then
        return
    end
    local g = gdb()
    g.selected = id
    g.working = copySlots(preset.slots)
    self.dirty = false
    self:Fire()
end

function Groups:CommitSelected()
    local g = gdb()
    local preset = g.selected and self:Find(g.selected)
    if preset then
        preset.slots = copySlots(self:Working())
        self.dirty = false
    end
end

function Groups:Delete(id)
    local g = gdb()
    local _, index = self:Find(id)
    if index then
        table.remove(g.presets, index)
    end
    if g.selected == id then
        g.selected = nil
        self.dirty = false
    end
    if g.active == id then
        g.active = nil
    end
    self:Fire()
end

-- The active layout: the roster the raid is running with, marked "active" in Quick Load. The Late
-- Tracker expects the people in it, in their groups. Its id, or nil when none is set or it was deleted.
-- Before 0.19.0 the Late Tracker kept its own pick (CRTDB.late.layoutId); that becomes the active
-- layout the first time this is asked.
function Groups:Active()
    local g = gdb()
    if g.active == nil and CRT.db.late and CRT.db.late.layoutId then
        g.active = CRT.db.late.layoutId
    end
    if g.active and self:Find(g.active) then
        return g.active
    end
    return nil
end

function Groups:SetActive(id)
    gdb().active = id
    self:Fire()
end

-- Export / import ----------------------------------------------------------
-- Format: CRT1;<name>;<slot1>,<slot2>,...,<slot40>
-- ';' ',' and '%' inside values are %XX escaped. No '|' is used so the text is safe in edit boxes.

local function esc(s)
    return (s:gsub("[%%;,]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function clean(s, maxLen)
    s = s:gsub("[%c|]", "")
    return strtrim(s):sub(1, maxLen)
end

function Groups:Export(name, slots)
    local parts = {}
    for i = 1, NUM_SLOTS do
        parts[i] = esc(slots[i] or "")
    end
    return "CRT1;" .. esc(name or "") .. ";" .. table.concat(parts, ",")
end

-- Plain list pasted from a spreadsheet: one name per row, row N fills slot N.
-- With several columns (tab separated) the first non-empty cell of each row is the name.
-- Blank rows leave their slot empty.
function Groups:ImportList(str)
    local rows = {}
    for line in (str .. "\n"):gmatch("(.-)\r?\n") do
        local name = ""
        for field in (line .. "\t"):gmatch("(.-)\t") do
            field = clean(field, 64)
            if field ~= "" then
                name = field
                break
            end
        end
        rows[#rows + 1] = name
    end
    while #rows > 0 and rows[#rows] == "" do
        rows[#rows] = nil
    end
    if #rows == 0 then
        return nil, "Nothing to import. Paste one name per line."
    end
    if #rows > NUM_SLOTS then
        return nil, "The list has " .. #rows .. " rows, but a raid only has " .. NUM_SLOTS .. " slots."
    end

    local slots, seen = {}, {}
    for i = 1, NUM_SLOTS do
        local key = self.Normalize(rows[i] or "")
        if key ~= "" and seen[key:lower()] then
            key = ""
        end
        if key ~= "" then
            seen[key:lower()] = true
        end
        slots[i] = key
    end
    return "Pasted roster", slots
end

-- Returns name, slots on success, or nil, errorMessage.
-- Accepts either a CRT1 export string or a plain pasted list of names.
function Groups:Import(str)
    str = strtrim(str or "")
    if not str:find("^CRT1;") then
        return self:ImportList(str)
    end
    local name, body = str:match("^CRT1;([^;]*);([^;]*)$")
    if not name then
        return nil, "That Cowfee Raid Tools export looks damaged."
    end

    local slots, seen, n, pos = {}, {}, 0, 1
    while true do
        local comma = body:find(",", pos, true)
        local item = body:sub(pos, (comma or 0) - 1)
        n = n + 1
        if n > NUM_SLOTS then
            return nil, "Import has more than " .. NUM_SLOTS .. " slots."
        end
        local key = self.Normalize(clean(unesc(item), 64))
        if key ~= "" and seen[key:lower()] then
            key = ""
        end
        if key ~= "" then
            seen[key:lower()] = true
        end
        slots[n] = key
        if not comma then
            break
        end
        pos = comma + 1
    end
    for i = n + 1, NUM_SLOTS do
        slots[i] = ""
    end

    local presetName = clean(unesc(name), 40)
    if presetName == "" then
        presetName = "Imported"
    end
    return presetName, slots
end
