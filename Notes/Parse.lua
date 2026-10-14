local ADDON, CRT = ...

-- Reads a raid note's text. The format is lines of "key:value;" pairs:
--   EncounterID:3470;Difficulty:Mythic;Name:Nek'zali              the boss this note is for
--   time:34;ph:1;tag:Cheoeqar;spellid:64843;                     a spell for a player, 34s into phase 1
--   time:48;ph:1;tag:Abu Sixz;text:Group 1 go in;dur:8;colors:0 1 1 1;DisplayType:Text;
--                                                                a text callout shown for 8 seconds
--   invitelist:Name-Realm,Name-Realm,,Name-Realm;                the roster, in group order
-- Any other line is free text shown under the timers. A tag is one or more player names or role words
-- (tank, healer, dps, melee, ranged, all), separated by spaces.

local Parser = {}
CRT.NoteParser = Parser

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "key:value;key:value;" into a table with lowercase keys.
local function fields(line)
    local out = {}
    for part in line:gmatch("[^;]+") do
        local key, value = part:match("^%s*([^:]+):(.*)$")
        if key then
            out[trim(key):lower()] = trim(value)
        end
    end
    return out
end

local function words(s)
    local out = {}
    for word in (s or ""):gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

local function color(s)
    local r, g, b, a = (s or ""):match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*([%d%.]*)")
    if r then
        return { tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1 }
    end
    return nil
end

-- Comma separated, keeping empty entries so a blank leaves an empty group slot.
local function nameList(s)
    local names, pos = {}, 1
    while true do
        local comma = s:find(",", pos, true)
        names[#names + 1] = trim(s:sub(pos, (comma or 0) - 1))
        if not comma then
            break
        end
        pos = comma + 1
    end
    return names
end

-- Returns { encounterID, difficulty, name, timers = {...}, phases = {...}, lines = {...}, invite = {...} }.
-- Each timer is { time, ph, tags, kind = "spell" or "text", spellId, text, dur, color }.
function Parser.Parse(text)
    local note = { timers = {}, phases = {}, lines = {}, invite = nil }
    local phaseSeen = {}

    for raw in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        local line = trim(raw)
        local lower = line:lower()
        if line == "" then
            note.lines[#note.lines + 1] = ""
        elseif lower:find("^encounterid:") then
            local f = fields(line)
            note.encounterID = tonumber(f.encounterid)
            note.difficulty = f.difficulty
            note.name = f.name
        elseif lower:find("^time:") then
            local f = fields(line)
            local t = tonumber(f.time)
            if t then
                local item = {
                    time = t,
                    ph = tonumber(f.ph) or 1,
                    tags = words(f.tag),
                    spellId = tonumber(f.spellid),
                    text = f.text,
                    dur = tonumber(f.dur),
                    color = color(f.colors),
                }
                item.kind = item.spellId and "spell" or "text"
                note.timers[#note.timers + 1] = item
                if not phaseSeen[item.ph] then
                    phaseSeen[item.ph] = true
                    note.phases[#note.phases + 1] = item.ph
                end
            end
        elseif lower:find("^invitelist:") then
            local list = line:match("^[^:]+:(.*)$") or ""
            note.invite = nameList((list:gsub(";%s*$", "")))
        else
            note.lines[#note.lines + 1] = line
        end
    end

    table.sort(note.phases)
    table.sort(note.timers, function(a, b)
        if a.ph ~= b.ph then
            return a.ph < b.ph
        end
        return a.time < b.time
    end)

    -- Free text: no blank lines at the start or end, and never two in a row.
    local cleaned = {}
    for _, line in ipairs(note.lines) do
        if line ~= "" or (#cleaned > 0 and cleaned[#cleaned] ~= "") then
            cleaned[#cleaned + 1] = line
        end
    end
    while #cleaned > 0 and cleaned[#cleaned] == "" do
        cleaned[#cleaned] = nil
    end
    note.lines = cleaned
    return note
end
