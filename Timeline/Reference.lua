local ADDON, CRT = ...

-- Timeline: reference timelines. A reference is a boss's known cast schedule written as plain text,
-- either shipped with the addon (CRT.TimelineDB.references, a list of text blocks) or pasted in
-- game and saved in CRTDB.timeline.references as { id, text }. This file reads that text (Parse),
-- keeps the player's own references (Add, Update, Delete) and answers which references exist and
-- which belong to a boss (List, Find, ForBoss, BossKey). The text is one line per thing:
--   Boss: Name            (required)   Difficulty: Mythic   Length: 9:48   Encounter: 3001
--   Phase: [label] time   a phase line, the time is the last word
--   Name [spell N] (type raid soak, lead N, color rrggbb): time, time+bar, ...   an ability row
-- A time is m:ss or plain seconds. Blank lines and lines starting with # are skipped. Every line
-- that cannot be read is reported as "Line N: reason", and nothing is saved until the text is clean.

local Reference = {}
CRT.TimelineReference = Reference

-- What an ability is, written (type raid) or (type mythic soak). The first type colors the row; the
-- others show as dots on its label, and the tooltip lists them all. No type means a plain mechanic.
Reference.TYPE_ORDER = { "dispel", "raid", "falloff", "mythic", "heroic", "generic", "soak", "spread", "dodge", "heavydot" }
Reference.TYPES = {
    dispel = { label = "Dispellable debuff", color = { 0.29, 0.64, 1 } },
    raid = { label = "Raid-wide damage, unavoidable", color = { 1, 0.31, 0.31 } },
    falloff = { label = "Fall-off damage", color = { 0.49, 0.86, 0.42 } },
    mythic = { label = "Mythic only", color = { 1, 0.6, 0.24 } },
    heroic = { label = "Heroic and higher", color = { 0.77, 0.36, 0.88 } },
    generic = { label = "Mechanic", color = { 0.95, 0.9, 0.84 } },
    soak = { label = "Soak", color = { 1, 0.5, 0.82 } },
    spread = { label = "Spread out or get away", color = { 1, 0.85, 0.29 } },
    dodge = { label = "Dodge", color = { 0.2, 0.82, 0.78 } },
    heavydot = { label = "Heavy damage over time", color = { 0.75, 0.92, 0.25 } },
}

-- The type colors as tooltip text, one line per type in its own color: "Soak (soak)".
function Reference.Legend()
    local lines = {}
    for _, key in ipairs(Reference.TYPE_ORDER) do
        local t = Reference.TYPES[key]
        local r, g, b = math.floor(t.color[1] * 255 + 0.5), math.floor(t.color[2] * 255 + 0.5), math.floor(t.color[3] * 255 + 0.5)
        lines[#lines + 1] = string.format("|cff%02x%02x%02x%s (%s)|r", r, g, b, t.label, key)
    end
    return table.concat(lines, "\n")
end

local function settings()
    return CRT.Timeline:Settings()
end

-- Lowercase, trimmed, curly apostrophes folded to a plain one (pasted text brings them).
local function fold(s)
    return (s:gsub("\226\128\153", "'"):gsub("\226\128\152", "'"))
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "1:05" or "65" in seconds, nil for anything else.
function Reference.ParseTime(s)
    if type(s) ~= "string" then
        return nil
    end
    s = trim(s)
    local m, sec = s:match("^(%d+):(%d%d)$")
    if m then
        if tonumber(sec) >= 60 then
            return nil
        end
        return tonumber(m) * 60 + tonumber(sec)
    end
    if s:match("^%d+$") then
        return tonumber(s)
    end
    return nil
end

-- The options in round brackets: "lead 7, color 7ddc6a". Sets them on the row; returns an error or nil.
local function readOptions(row, text)
    for opt in (text .. ","):gmatch("([^,]*),") do
        opt = trim(opt)
        if opt ~= "" then
            local key, arg = opt:match("^(%a+)%s+(.+)$")
            key = key and key:lower()
            if key == "lead" then
                local n = Reference.ParseTime(arg)
                if not n then
                    return "bad lead time '" .. arg .. "'"
                end
                row.lead = n
            elseif key == "color" then
                local hex = trim(arg):gsub("^#", "")
                if not hex:match("^%x%x%x%x%x%x$") then
                    return "bad color '" .. arg .. "' (use rrggbb)"
                end
                row.color = {
                    tonumber(hex:sub(1, 2), 16) / 255,
                    tonumber(hex:sub(3, 4), 16) / 255,
                    tonumber(hex:sub(5, 6), 16) / 255,
                }
            elseif key == "type" then
                row.types = row.types or {}
                for word in arg:gmatch("%S+") do
                    word = word:lower()
                    if not Reference.TYPES[word] then
                        return "unknown type '" .. word .. "' (use " .. table.concat(Reference.TYPE_ORDER, ", ") .. ")"
                    end
                    row.types[#row.types + 1] = word
                end
            else
                return "unknown option '" .. opt .. "'"
            end
        end
    end
end

-- The cast times of an ability line: "0:02+45, 1:17, 70". Fills row.casts; returns an error or nil.
local function readTimes(row, text)
    for tok in (text .. ","):gmatch("([^,]*),") do
        tok = trim(tok)
        if tok ~= "" then
            local at, bar = tok:match("^(.-)%s*%+%s*(.+)$")
            local t = Reference.ParseTime(at or tok)
            if not t then
                return "bad time '" .. tok .. "'"
            end
            local cast = { t = t }
            if bar then
                cast.dur = Reference.ParseTime(bar)
                if not cast.dur then
                    return "bad bar length '" .. bar .. "'"
                end
            end
            row.casts[#row.casts + 1] = cast
        end
    end
    if #row.casts == 0 then
        return "needs at least one time"
    end
end

-- One ability line, "Name [spell N] (options): times". Returns the row, or nil and a reason.
local function readAbility(line)
    local name, rest = line:match("^([^:%[%(]+)(.*)$")
    name = name and trim(name)
    if not name or name == "" then
        return nil, "missing the ability name"
    end
    local row = { name = name, casts = {} }
    rest = trim(rest)
    while true do
        local first = rest:sub(1, 1)
        if first == "[" then
            local id, after = rest:match("^%[%s*[Ss][Pp][Ee][Ll][Ll]%s+(%d+)%s*%]%s*(.*)$")
            if not id then
                return nil, "expected [spell N]"
            end
            row.spellID = tonumber(id)
            rest = after
        elseif first == "(" then
            local opts, after = rest:match("^%((.-)%)%s*(.*)$")
            if not opts then
                return nil, "missing a closing bracket"
            end
            local err = readOptions(row, opts)
            if err then
                return nil, err
            end
            rest = after
        elseif first == ":" then
            local err = readTimes(row, rest:sub(2))
            if err then
                return nil, err
            end
            -- the first type colors the row, unless a color was given
            if not row.color and row.types and row.types[1] then
                local c = Reference.TYPES[row.types[1]].color
                row.color = { c[1], c[2], c[3] }
            end
            return row
        else
            return nil, "expected ':' and the times after the name"
        end
    end
end

-- Reads reference text. Returns the reference, or nil and a list of "Line N: reason" errors.
function Reference.Parse(text)
    if type(text) ~= "string" then
        return nil, { "No text to read" }
    end
    -- pasted text: a non-breaking space is a space, a zero-width space is nothing
    text = text:gsub("\194\160", " "):gsub("\226\128\139", "")
    local ref = { phases = {}, rows = {} }
    local errors = {}
    local explicitLength
    local n = 0
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local line = trim((raw:gsub("\r", "")))
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local err
            local key, val = line:match("^(%a+)%s*:%s*(.*)$")
            key = key and key:lower()
            if key == "boss" then
                if val == "" then
                    err = "Boss needs a name"
                else
                    ref.boss = val
                end
            elseif key == "difficulty" then
                ref.difficulty = val ~= "" and val or nil
            elseif key == "length" then
                explicitLength = Reference.ParseTime(val)
                if not explicitLength then
                    err = "bad length '" .. val .. "'"
                end
            elseif key == "encounter" then
                ref.encounterID = val:match("^%d+$") and tonumber(val) or nil
                if not ref.encounterID then
                    err = "bad encounter ID '" .. val .. "'"
                end
            elseif key == "phase" then
                -- a moved phase line keeps the time it was transcribed with: "P2 2:53 (planned 3:03)"
                local plannedText
                local rest, p = val:match("^(.-)%s*%(%s*[Pp][Ll][Aa][Nn][Nn][Ee][Dd]%s+(%S+)%s*%)$")
                if rest then
                    val, plannedText = rest, p
                end
                local label, last = val:match("^(.-)%s*(%S+)$")
                local t = last and Reference.ParseTime(last)
                local planned = plannedText and Reference.ParseTime(plannedText)
                if not t then
                    err = "Phase needs a time at the end"
                elseif plannedText and not planned then
                    err = "bad planned time '" .. plannedText .. "'"
                else
                    ref.phases[#ref.phases + 1] = { t = t, planned = planned or t, label = label ~= "" and label or nil }
                end
            else
                local row, reason = readAbility(line)
                if row then
                    ref.rows[#ref.rows + 1] = row
                else
                    err = reason
                end
            end
            if err then
                errors[#errors + 1] = "Line " .. n .. ": " .. err
            end
        end
    end
    if not ref.boss then
        errors[#errors + 1] = "Missing a Boss line"
    end
    if #ref.rows == 0 and #errors == 0 then
        errors[#errors + 1] = "Needs at least one ability line with a time"
    end
    if #errors > 0 then
        return nil, errors
    end
    table.sort(ref.phases, function(a, b)
        return a.t < b.t
    end)
    local last = 0
    for _, row in ipairs(ref.rows) do
        table.sort(row.casts, function(a, b)
            return a.t < b.t
        end)
        for _, c in ipairs(row.casts) do
            last = math.max(last, c.t + (c.dur or 0))
        end
    end
    ref.length = math.max(explicitLength or 0, last)
    return ref
end

-- "Reference · Mythic · 9:48"
function Reference.Label(ref)
    local len = ref.length or 0
    local time = string.format("%d:%02d", math.floor(len / 60), len % 60)
    if ref.difficulty and ref.difficulty ~= "" then
        return "Reference \194\183 " .. ref.difficulty .. " \194\183 " .. time
    end
    return "Reference \194\183 " .. time
end

-- The saved list of your own references, made when first needed.
local function saved()
    local db = settings()
    db.references = db.references or {}
    db.nextRef = db.nextRef or 1
    return db.references
end

local function findOwn(key)
    local id = type(key) == "string" and key:match("^own:(%d+)$")
    if not id then
        return nil
    end
    id = tonumber(id)
    for i, r in ipairs(saved()) do
        if r.id == id then
            return r, i
        end
    end
end

-- Your references first (in the order you saved them), then the shipped ones. A shipped text that
-- does not read is skipped without a word.
function Reference:List()
    local list = {}
    for _, r in ipairs(saved()) do
        local ref = Reference.Parse(r.text)
        if ref then
            list[#list + 1] = { key = "own:" .. r.id, ref = ref, own = true, text = r.text }
        end
    end
    local shipped = CRT.TimelineDB and CRT.TimelineDB.references
    if shipped then
        for i, text in ipairs(shipped) do
            local ref = Reference.Parse(text)
            if ref then
                list[#list + 1] = { key = "ship:" .. i, ref = ref, own = false, text = text }
            end
        end
    end
    return list
end

function Reference:Find(key)
    for _, entry in ipairs(self:List()) do
        if entry.key == key then
            return entry
        end
    end
end

local function norm(name)
    return type(name) == "string" and fold(trim(name)):lower() or nil
end

local HEADERS = { boss = true, difficulty = true, length = true, encounter = true, phase = true }

-- The Boss and Encounter lines of reference text, read loosely so a box that does not parse yet
-- still says which boss it is for. Returns the boss name and encounter ID, either may be nil.
function Reference.Header(text)
    if type(text) ~= "string" then
        return nil, nil
    end
    local boss, encounterID
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local key, val = trim((raw:gsub("\r", ""))):match("^(%a+)%s*:%s*(.*)$")
        key = key and key:lower()
        if key == "boss" and val ~= "" then
            boss = trim((val:gsub("\194\160", " ")))
        elseif key == "encounter" and val:match("^%d+$") then
            encounterID = tonumber(val)
        end
    end
    return boss, encounterID
end

-- Adds [spell N] to each ability line that has none and whose name matches one of rows (the boss's
-- Journal abilities, { spellID, name }), by name in any case. Every other line is kept as it is.
-- Returns the new text and how many lines got a spell ID.
function Reference.FillSpellIDs(text, rows)
    if type(text) ~= "string" then
        return text, 0
    end
    local byName = {}
    for _, row in ipairs(rows or {}) do
        local key = norm(row.name)
        if key and key ~= "" and type(row.spellID) == "number" and row.spellID > 0 and not byName[key] then
            byName[key] = row.spellID
        end
    end
    local out, filled = {}, 0
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local cr = raw:sub(-1) == "\r" and "\r" or ""
        local line = cr == "" and raw or raw:sub(1, -2)
        local indent, name, rest = line:match("^(%s*)([^:%[%(]+)(.*)$")
        local key = name and line:match("^%s*(%a+)%s*:")
        local id = name and byName[norm((name:gsub("\194\160", " ")))]
        if id and not HEADERS[key and key:lower() or ""] and not rest:lower():find("%[%s*spell")
            and line:sub(#indent + 1, #indent + 1) ~= "#" then
            rest = trim(rest)
            line = indent .. trim(name) .. " [spell " .. id .. "]" .. (rest:sub(1, 1) == ":" and "" or " ") .. rest
            filled = filled + 1
        end
        out[#out + 1] = line .. cr
    end
    return table.concat(out, "\n"), filled
end

-- The references of a boss: by encounter ID when the reference has one, otherwise by boss name.
function Reference:ForBoss(encounterID, name)
    local want = norm(name)
    local found = {}
    for _, entry in ipairs(self:List()) do
        local ref = entry.ref
        if ref.encounterID then
            if ref.encounterID == encounterID then
                found[#found + 1] = entry
            end
        elseif want and norm(ref.boss) == want then
            found[#found + 1] = entry
        end
    end
    return found
end

-- The boss dropdown key of a reference: the listed boss it belongs to, else its own "ref:name" key.
-- listed is the bosses already in the dropdown, { { key, name } }. The same rule as ForBoss: by
-- encounter ID when the reference has one (never by name then), otherwise by name.
function Reference:BossKey(entry, listed)
    local ref = entry.ref
    local want = norm(ref.boss)
    for _, l in ipairs(listed or {}) do
        local match
        if ref.encounterID then
            match = l.key == ref.encounterID
        else
            match = norm(l.name) == want
        end
        if match then
            return l.key
        end
    end
    return "ref:" .. want
end

-- Saves new text as your reference. Returns its key, or nil and the errors (nothing is saved then).
function Reference:Add(text)
    local ref, errors = Reference.Parse(text)
    if not ref then
        return nil, errors
    end
    local list = saved()
    local db = settings()
    local id = db.nextRef
    db.nextRef = id + 1
    list[#list + 1] = { id = id, text = text }
    CRT.Timeline:Fire()
    return "own:" .. id
end

-- Replaces the text of one of your references. Shipped ones cannot be changed.
function Reference:Update(key, text)
    local r = findOwn(key)
    if not r then
        return false, { "No such reference" }
    end
    local ref, errors = Reference.Parse(text)
    if not ref then
        return false, errors
    end
    r.text = text
    CRT.Timeline:Fire()
    return true
end

-- Deletes one of your references. Shipped ones cannot be deleted.
function Reference:Delete(key)
    local r, i = findOwn(key)
    if not r then
        return
    end
    table.remove(saved(), i)
    CRT.Timeline:Fire()
end

-- Moving phases -------------------------------------------------------------------------------------
-- A phase line can be moved on the timeline. The move is written into the Phase line as its new time
-- with the transcribed one kept: "Phase: P2 2:53 (planned 3:03)". The cast times stay as transcribed:
-- each cast belongs to the phase it was planned in (by the planned times), moves with that phase, and
-- is hidden while it would land at or after the next phase's start. Moving the line back shows it again.

-- The start of every phase, phase 1 (the pull) first: { 0, start of the first Phase line, ... }.
function Reference.PhaseStarts(ref)
    local starts = { 0 }
    for i, phase in ipairs(ref and ref.phases or {}) do
        starts[i + 1] = phase.t
    end
    return starts
end

local function clock(seconds)
    seconds = math.floor(seconds + 0.5)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The text with its index-th phase (in time order, as Parse sorts them) moved to t. At the planned
-- time the "(planned ...)" goes away. Returns nil when there is no such phase line.
function Reference.MovePhaseText(text, index, t)
    if type(text) ~= "string" or type(index) ~= "number" or type(t) ~= "number" then
        return nil
    end
    local lines, found = {}, {}
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = raw
        local cr = raw:sub(-1) == "\r" and "\r" or ""
        local line = cr == "" and raw or raw:sub(1, -2)
        local indent, key, val = line:match("^(%s*)(%a+)%s*:%s*(.*)$")
        if key and key:lower() == "phase" then
            local one = Reference.Parse("Boss: x\nPhase: " .. val .. "\nx: 1")
            local phase = one and one.phases[1]
            if phase then
                found[#found + 1] = { n = #lines, phase = phase, indent = indent, cr = cr }
            end
        end
    end
    table.sort(found, function(a, b)
        return a.phase.t < b.phase.t
    end)
    local hit = found[index]
    if not hit then
        return nil
    end
    local phase = hit.phase
    local line = hit.indent .. "Phase: " .. (phase.label and (phase.label .. " ") or "") .. clock(t)
    if math.floor(t + 0.5) ~= phase.planned then
        line = line .. " (planned " .. clock(phase.planned) .. ")"
    end
    lines[hit.n] = line .. hit.cr
    return table.concat(lines, "\n")
end

-- Moves a reference's index-th phase to t and saves it. Your own reference is changed in place; a
-- shipped one is saved as a new reference of your own with the move, since shipped text never changes.
-- Returns the key of the reference that now holds the move (and true when it is a new copy), or nil.
function Reference:MovePhase(key, index, t)
    local entry = self:Find(key)
    local text = entry and Reference.MovePhaseText(entry.text, index, t)
    if not text then
        return nil
    end
    if entry.own then
        local ok = self:Update(key, text)
        return ok and key or nil, false
    end
    local newKey = self:Add(text)
    return newKey, newKey ~= nil
end

-- Difficulty ----------------------------------------------------------------------------------------
-- A reference belongs to one of two groups: "nh" (Normal and Heroic share a schedule) or "mythic".
-- The group comes from its Difficulty line; anything but Mythic, or no line, is "nh".

function Reference.Group(ref)
    local d = ref and type(ref.difficulty) == "string" and trim(ref.difficulty):lower()
    return d == "mythic" and "mythic" or "nh"
end

-- True for a row marked (type ... mythic ...).
function Reference.MythicOnly(row)
    for _, t in ipairs(row and row.types or {}) do
        if t == "mythic" then
            return true
        end
    end
    return false
end

-- The entries (as List returns them) that belong to the group.
function Reference:ForGroup(entries, group)
    local out = {}
    for _, entry in ipairs(entries or {}) do
        if Reference.Group(entry.ref) == group then
            out[#out + 1] = entry
        end
    end
    return out
end

-- The text with its Difficulty line set for the group: Mythic for "mythic"; for "nh" a Normal or Heroic
-- line stays, anything else becomes Heroic. A text with no Difficulty line gets one right after the Boss
-- line (at the top when there is none). Every other line, and each line's own \r, is kept.
function Reference.StampDifficulty(text, group)
    if type(text) ~= "string" then
        return text
    end
    local lines, bossAt, stamped = {}, nil, false
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local cr = raw:sub(-1) == "\r" and "\r" or ""
        local line = cr == "" and raw or raw:sub(1, -2)
        local indent, key, val = line:match("^(%s*)(%a+)%s*:%s*(.*)$")
        key = key and key:lower()
        if key == "difficulty" then
            stamped = true
            local d = trim(val):lower()
            if group == "mythic" then
                line = indent .. "Difficulty: Mythic"
            elseif d ~= "normal" and d ~= "heroic" then
                line = indent .. "Difficulty: Heroic"
            end
        elseif key == "boss" and not bossAt then
            bossAt = #lines + 1
        end
        lines[#lines + 1] = line .. cr
    end
    if not stamped then
        local at = bossAt and bossAt + 1 or 1
        local cr = (lines[bossAt or 1] or ""):sub(-1) == "\r" and "\r" or ""
        table.insert(lines, at, "Difficulty: " .. (group == "mythic" and "Mythic" or "Heroic") .. cr)
    end
    return table.concat(lines, "\n")
end

-- The text copied to a difficulty group: stamped for it, and for "nh" without the Mythic-only ability
-- lines. Header, Phase and # lines stay as they are. Returns the text and how many lines were left out.
function Reference.CopyTo(text, group)
    text = Reference.StampDifficulty(text, group)
    if type(text) ~= "string" or group == "mythic" then
        return text, 0
    end
    local out, removed = {}, 0
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = trim((raw:gsub("\r", "")))
        local key = line:match("^(%a+)%s*:")
        local drop = false
        if line ~= "" and line:sub(1, 1) ~= "#" and not HEADERS[key and key:lower() or ""] then
            local one = Reference.Parse("Boss: x\n" .. line)
            drop = one and Reference.MythicOnly(one.rows[1]) or false
        end
        if drop then
            removed = removed + 1
        else
            out[#out + 1] = raw
        end
    end
    return table.concat(out, "\n"), removed
end
