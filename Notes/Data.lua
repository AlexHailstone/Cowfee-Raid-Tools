local ADDON, CRT = ...

-- Stored raid notes and their settings, in CRTDB.notes (per player):
--   list[id] = { raw, name, encounterID, difficulty, updated, from, presetId }
--   active = id of the note in use, nextId
--   window = note window settings, alert = personal alert settings, trustedOnly
-- A note's invite list becomes a Raid Groups layout when it is imported (presetId links them).

local Parser = CRT.NoteParser
local Notes = { listeners = {} }
CRT.Notes = Notes

local parsed = {} -- id -> { raw, note }, so a note is only parsed again when its text changes
local spells = {} -- spellId -> { name, icon }

local function ndb()
    return CRT.db.notes
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

function Notes:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Notes:Fire()
    for _, fn in ipairs(self.listeners) do
        fn()
    end
end

-- Settings ------------------------------------------------------------------------------

function Notes:Window()
    return ndb().window
end

-- Settings for one of the three windows: "window" (timers), "assignments" or "personal".
function Notes:WindowSettings(key)
    return ndb()[key]
end

function Notes:Personal()
    return ndb().personalText or ""
end

function Notes:SetPersonal(text)
    ndb().personalText = text or ""
    self:Fire()
end

function Notes:Alert()
    return ndb().alert
end

function Notes:TrustedOnly()
    return ndb().trustedOnly
end

function Notes:Set(section, key, value)
    local target = section and ndb()[section] or ndb()
    target[key] = value
    self:Fire()
end

-- Spells: name and icon, cached out of combat so the note never reads them during a fight. -------

function Notes:SpellInfo(spellId)
    if not spellId then
        return nil
    end
    local cached = spells[spellId]
    if cached then
        return cached
    end
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
        if ok and type(info) == "table" then
            name, icon = info.name, info.iconID
        end
    end
    if isSecret(name) or isSecret(icon) then
        return nil
    end
    if name then
        spells[spellId] = { name = name, icon = icon }
        return spells[spellId]
    end
    return nil
end

local function cacheSpells(note)
    for _, item in ipairs(note.timers) do
        if item.spellId then
            Notes:SpellInfo(item.spellId)
        end
    end
end

-- Notes -----------------------------------------------------------------------------------

function Notes:Get(id)
    return id and ndb().list[id]
end

function Notes:Parsed(id)
    local record = self:Get(id)
    if not record then
        return nil
    end
    local entry = parsed[id]
    if not entry or entry.raw ~= record.raw then
        entry = { raw = record.raw, note = Parser.Parse(record.raw) }
        parsed[id] = entry
        if not InCombatLockdown() then
            cacheSpells(entry.note)
        end
    end
    return entry.note
end

-- All notes, sorted by boss name: { id, record }.
function Notes:List()
    local out = {}
    for id, record in pairs(ndb().list) do
        out[#out + 1] = { id = id, record = record }
    end
    table.sort(out, function(a, b)
        return (a.record.name or ""):lower() < (b.record.name or ""):lower()
    end)
    return out
end

function Notes:Active()
    local id = ndb().active
    if id and ndb().list[id] then
        return id, ndb().list[id], self:Parsed(id)
    end
    return nil
end

function Notes:SetActive(id)
    ndb().active = id
    self:Fire()
end

-- The note for a boss, by encounter ID, preferring the same difficulty.
function Notes:FindForEncounter(encounterID, difficultyName)
    local fallback
    for id, record in pairs(ndb().list) do
        if record.encounterID == encounterID then
            if difficultyName and record.difficulty and record.difficulty:lower() == difficultyName:lower() then
                return id
            end
            fallback = fallback or id
        end
    end
    return fallback
end

-- Builds a Raid Groups layout from the invite list, in order, keeping empty slots.
local function rosterFromInvite(note, title)
    local Groups = CRT.Groups
    if not (Groups and note.invite) then
        return nil
    end
    local slots, any = {}, false
    for i = 1, Groups.NUM_SLOTS do
        local name = note.invite[i] or ""
        slots[i] = Groups.Normalize(name)
        if slots[i] ~= "" then
            any = true
        end
    end
    if not any then
        return nil
    end
    return Groups:CreatePreset(title, slots)
end

-- Imports note text. A note for the same boss and difficulty is replaced. Returns id, message.
function Notes:Import(text, from)
    local note = Parser.Parse(text)
    if not note.name and not note.encounterID and #note.timers == 0 then
        return nil, "That doesn't look like a raid note. It needs an EncounterID line or time: lines."
    end
    local db = ndb()
    local id
    for existingId, record in pairs(db.list) do
        local sameBoss = note.encounterID and record.encounterID == note.encounterID
        local sameDifficulty = (record.difficulty or "") == (note.difficulty or "")
        if sameBoss and sameDifficulty then
            id = existingId
            break
        end
    end
    if not id then
        id = db.nextId
        db.nextId = db.nextId + 1
    end
    local record = db.list[id] or {}
    record.raw = text
    record.name = note.name or ("Note " .. id)
    record.encounterID = note.encounterID
    record.difficulty = note.difficulty
    record.updated = date("%Y-%m-%d %H:%M")
    record.from = from
    db.list[id] = record

    -- The invite list becomes a Raid Groups layout the first time, which can then be adjusted there.
    local message = "Imported " .. record.name .. (record.difficulty and (" (" .. record.difficulty .. ")") or "") .. "."
    if note.invite and not (record.presetId and CRT.Groups and CRT.Groups:Find(record.presetId)) then
        local presetId = rosterFromInvite(note, record.name .. " " .. (record.difficulty or "") .. " roster")
        if presetId then
            record.presetId = presetId
            message = message .. " Its invite list is now a layout in Raid Groups."
        end
    end
    parsed[id] = nil
    self:Parsed(id)
    self:Fire()
    return id, message
end

function Notes:UpdateRaw(id, text)
    local record = self:Get(id)
    if not record then
        return
    end
    local note = Parser.Parse(text)
    record.raw = text
    record.name = note.name or record.name
    record.encounterID = note.encounterID or record.encounterID
    record.difficulty = note.difficulty or record.difficulty
    record.updated = date("%Y-%m-%d %H:%M")
    parsed[id] = nil
    self:Parsed(id)
    self:Fire()
end

-- Single lines ------------------------------------------------------------------------------
-- The editor reads and writes one note line at a time. Line numbers are the parser's (timer.line):
-- 1-based, counting every line, with CRLF or LF ends. Every other line is kept byte for byte.

-- The raw text as { text, eol } pieces; concatenating them gives the raw text back exactly.
local function splitLines(raw)
    local pieces, pos = {}, 1
    while true do
        local nl = raw:find("\n", pos, true)
        if not nl then
            pieces[#pieces + 1] = { text = raw:sub(pos), eol = "" }
            return pieces
        end
        local text, eol = raw:sub(pos, nl - 1), "\n"
        if text:sub(-1) == "\r" then
            text, eol = text:sub(1, -2), "\r\n"
        end
        pieces[#pieces + 1] = { text = text, eol = eol }
        pos = nl + 1
    end
end

local function joinLines(pieces)
    local out = {}
    for i, piece in ipairs(pieces) do
        out[i] = piece.text .. piece.eol
    end
    return table.concat(out)
end

local function singleLine(line)
    return type(line) == "string" and not line:find("[\r\n]")
end

-- The pieces of a note and the piece at lineNumber, or nil when the note or line isn't there or
-- `expected` (the raw line the editor loaded) no longer matches it.
local function pieceAt(id, lineNumber, expected)
    local record = Notes:Get(id)
    if not (record and record.raw and type(lineNumber) == "number") then
        return nil
    end
    local pieces = splitLines(record.raw)
    local piece = pieces[lineNumber]
    if not piece or (expected ~= nil and piece.text ~= expected) then
        return nil
    end
    return pieces, piece
end

-- The timer parsed from a line, and the raw line itself (pass it back as `expected`). Nil when that
-- line isn't a timed line.
function Notes:TimerAt(id, lineNumber)
    local note = self:Parsed(id)
    local _, piece = pieceAt(id, lineNumber)
    if not (note and piece) then
        return nil
    end
    for _, timer in ipairs(note.timers) do
        if timer.line == lineNumber then
            return timer, piece.text
        end
    end
    return nil
end

-- Adds a line to the note for a boss (making the note when there is none). Returns the note id and
-- the line's number.
function Notes:AddLine(encounterID, difficultyName, bossName, line)
    if not singleLine(line) then
        return nil
    end
    local id = self:FindForEncounter(encounterID, difficultyName)
    if not id then
        local header = "EncounterID:" .. tostring(encounterID)
        if difficultyName then
            header = header .. ";Difficulty:" .. difficultyName
        end
        if bossName then
            header = header .. ";Name:" .. bossName
        end
        local newId = self:Import(header .. "\n" .. line)
        return newId, newId and 2 or nil
    end
    local raw = self:Get(id).raw or ""
    local pieces = splitLines(raw)
    local last = pieces[#pieces]
    if last.text ~= "" then
        -- no newline after the last line yet: add one, in the note's own style
        last.eol = (pieces[1].eol == "\r\n") and "\r\n" or "\n"
        pieces[#pieces + 1] = { text = line, eol = "" }
    else
        pieces[#pieces] = { text = line, eol = "" }
    end
    self:UpdateRaw(id, joinLines(pieces))
    return id, #pieces
end

-- Replaces one line. `expected` is the raw line the editor loaded; if the line has changed since,
-- nothing is written and false comes back.
function Notes:ReplaceLine(id, lineNumber, line, expected)
    local pieces, piece = pieceAt(id, lineNumber, expected)
    if not (piece and singleLine(line)) then
        return false
    end
    piece.text = line
    self:UpdateRaw(id, joinLines(pieces))
    return true
end

-- Removes one line and its line end (a last line with no end leaves the line before it as it was).
function Notes:RemoveLine(id, lineNumber, expected)
    local pieces = pieceAt(id, lineNumber, expected)
    if not pieces then
        return false
    end
    table.remove(pieces, lineNumber)
    self:UpdateRaw(id, joinLines(pieces))
    return true
end

function Notes:Delete(id)
    local db = ndb()
    db.list[id] = nil
    parsed[id] = nil
    if db.active == id then
        db.active = nil
    end
    self:Fire()
end
