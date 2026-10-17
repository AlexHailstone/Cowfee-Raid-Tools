local ADDON, CRT = ...

-- Stored raid notes and their settings, in CRTDB.notes (per player):
--   list[id] = { raw, name, encounterID, difficulty, updated, from, presetId }
--   active = id of the note in use, nextId
--   window = note window settings, alert = personal alert settings, trustedOnly
-- A note's invite list becomes a Raid Groups layout when it is imported (presetId links them).

local TEXT = {
    notAdmin = "Only the raid leader or assistants can change the raid note.",
}

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

-- Who may change the raid note ------------------------------------------------------------------

-- A yes/no the game reports (IsInRaid, UnitIsGroupLeader): true or false, or nil when it can't be read
-- (missing, an error, or a secret value).
local function groupFlag(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if not ok or isSecret(value) then
        return nil
    end
    return value and true or false
end

-- Whether you may change the raid note (the lines on the Timeline and in the editor): in a raid, the
-- leader or an assistant, the same check Comm:CanShare makes; in a party, the leader; on your own,
-- always. A group state that can't be read counts as no. Returns ok, and the reason when not.
function Notes:CanEditRaid()
    local raid = groupFlag(IsInRaid)
    if raid == nil then
        return false, TEXT.notAdmin
    end
    if raid then
        if groupFlag(UnitIsGroupLeader, "player") or groupFlag(UnitIsGroupAssistant, "player") then
            return true
        end
        return false, TEXT.notAdmin
    end
    local party = groupFlag(IsInGroup)
    if party == nil then
        return false, TEXT.notAdmin
    end
    if not party or groupFlag(UnitIsGroupLeader, "player") then
        return true
    end
    return false, TEXT.notAdmin
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

local DIFFICULTY_RANK = { mythic = 1, heroic = 2, normal = 3 }

-- All notes, in the raid route (CRT.Bosses:RouteIndex of the EncounterID in each note's header), the
-- same order as every boss list; a boss's notes Mythic, Heroic, Normal, then any other difficulty.
-- Notes for a boss the route doesn't list, or with no EncounterID, come last, by name: { id, record }.
function Notes:List()
    local out = {}
    local Bosses = CRT.Bosses
    for id, record in pairs(ndb().list) do
        local route = record.encounterID and Bosses and Bosses:RouteIndex(record.encounterID)
        out[#out + 1] = {
            id = id,
            record = record,
            route = route or math.huge,
            rank = DIFFICULTY_RANK[(record.difficulty or ""):lower()] or 4,
            name = (record.name or ""):lower(),
        }
    end
    table.sort(out, function(a, b)
        if a.route ~= b.route then
            return a.route < b.route
        end
        -- outside the route, the name keeps one boss's notes together
        if a.route == math.huge and a.name ~= b.name then
            return a.name < b.name
        end
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.id < b.id
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

-- A name fit to sit in the header: trimmed, no line ends or semicolons; nil when nothing is left.
local function headerWord(value)
    if value == nil then
        return nil
    end
    value = tostring(value):gsub("[\r\n;]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
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

-- The first line of a new note for a boss: "EncounterID:3470;Difficulty:Mythic;Name:Nek'zali".
local function headerLine(encounterID, difficultyName, bossName)
    local header = "EncounterID:" .. tostring(encounterID)
    if difficultyName then
        header = header .. ";Difficulty:" .. difficultyName
    end
    if bossName then
        header = header .. ";Name:" .. bossName
    end
    return header
end

-- The note a pull of that difficulty reads (FindForEncounter), made when the boss has no note at
-- all: a note with only the header line, which the Raid Notes page then shows like any other.
-- Returns the note id and true when it was just made.
function Notes:NoteFor(encounterID, difficultyName, bossName)
    if type(encounterID) ~= "number" then
        return nil
    end
    difficultyName, bossName = headerWord(difficultyName), headerWord(bossName)
    local id = self:FindForEncounter(encounterID, difficultyName)
    if id then
        return id, false
    end
    local newId = self:Import(headerLine(encounterID, difficultyName, bossName) .. "\n")
    return newId, newId ~= nil
end

-- Adds a line where a pull of that difficulty reads it: the note FindForEncounter gives (that
-- difficulty's note, else the boss's other note). A new note is made only when the boss has none at
-- all. Returns the note id and the line's number.
function Notes:AddLine(encounterID, difficultyName, bossName, line)
    if not singleLine(line) then
        return nil
    end
    difficultyName, bossName = headerWord(difficultyName), headerWord(bossName)
    local id = self:FindForEncounter(encounterID, difficultyName)
    if not id then
        local newId = self:Import(headerLine(encounterID, difficultyName, bossName) .. "\n" .. line)
        return newId, newId and 2 or nil
    end
    return id, self:AddLineTo(id, line)
end

-- Adds a line to the end of that very note. Returns the line's number, nil when the note or line isn't fit.
function Notes:AddLineTo(id, line)
    local record = self:Get(id)
    if not (record and singleLine(line)) then
        return nil
    end
    local pieces = splitLines(record.raw or "")
    local last = pieces[#pieces]
    if last.text ~= "" then
        -- no newline after the last line yet: add one, in the note's own style
        last.eol = (pieces[1].eol == "\r\n") and "\r\n" or "\n"
        pieces[#pieces + 1] = { text = line, eol = "" }
    else
        pieces[#pieces] = { text = line, eol = "" }
    end
    self:UpdateRaw(id, joinLines(pieces))
    return #pieces
end

-- The raw lines of a note, from one split (line n is what a timer with line = n was parsed from).
function Notes:RawLines(id)
    local record = self:Get(id)
    local out = {}
    if record and record.raw then
        for i, piece in ipairs(splitLines(record.raw)) do
            out[i] = piece.text
        end
    end
    return out
end

-- Replaces one line. `expected` is the raw line the editor loaded; if the line has changed since,
-- nothing is written and false comes back.
function Notes:ReplaceLine(id, lineNumber, line, expected)
    local pieces, piece = pieceAt(id, lineNumber, expected)
    if not (piece and singleLine(line) and self:TimerAt(id, lineNumber)) then
        return false
    end
    piece.text = line
    self:UpdateRaw(id, joinLines(pieces))
    return true
end

-- Removes one line and its line end (a last line with no end leaves the line before it as it was).
function Notes:RemoveLine(id, lineNumber, expected)
    local pieces = pieceAt(id, lineNumber, expected)
    if not (pieces and self:TimerAt(id, lineNumber)) then
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
