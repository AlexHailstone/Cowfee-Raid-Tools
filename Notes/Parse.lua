local ADDON, CRT = ...

-- Reads a raid note's text. The format is lines of "key:value;" pairs:
--   EncounterID:3470;Difficulty:Mythic;Name:Nek'zali              the boss this note is for
--   time:34;ph:1;tag:Cheoeqar;spellid:64843;                     a spell for a player, 34s into phase 1
--   time:48;ph:1;tag:Abu Sixz;text:Group 1 go in;dur:8;colors:0 1 1 1;DisplayType:Text;
--                                                                a text callout shown for 8 seconds
--   invitelist:Name-Realm,Name-Realm,,Name-Realm;                the roster, in group order
-- Any other line is free text shown under the timers. A tag is one or more player names, role words
-- (tank, healer, dps, melee, ranged, all) or class names, separated by spaces.
-- A timed line may also say how it shows. Without show: it shows as it always has.
--   show:icon,text;   only these displays: alert, text, icon, bar, circle
--   tts:1; count:1;   read the line out; count down 3, 2, 1
--   sound:RAID_WARNING; glow:1; warn:6; linger:3; icon:135940;
-- DisplayType: is ignored.

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

local SHOW_WORDS = { "alert", "text", "icon", "bar", "circle" }
local IS_SHOW_WORD = {}
for _, w in ipairs(SHOW_WORDS) do
    IS_SHOW_WORD[w] = true
end

-- "icon, Text" into { icon = true, text = true }. Unknown words are left out.
local function showSet(s)
    local set = {}
    for word in s:gmatch("[^,]+") do
        word = trim(word):lower()
        if IS_SHOW_WORD[word] then
            set[word] = true
        end
    end
    return set
end

local YES = { ["1"] = true, ["true"] = true, yes = true }
local function flag(s)
    if s and YES[s:lower()] then
        return true
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
-- Each timer is { time, ph, tags, kind = "spell" or "text", spellId, text, dur, color, line } with `line`
-- its line number in the text, and, when the line has them: show (a set), tts, count, glow (true),
-- sound (the text as written; Speech plays it only if it names one of Speech.SOUNDS), warn, linger
-- (seconds) and iconID.
function Parser.Parse(text)
    local note = { timers = {}, phases = {}, lines = {}, invite = nil }
    local phaseSeen = {}
    local lineNo = 0

    for raw in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        lineNo = lineNo + 1
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
                    line = lineNo,
                    show = f.show and showSet(f.show) or nil,
                    tts = flag(f.tts),
                    count = flag(f.count),
                    glow = flag(f.glow),
                    sound = (f.sound and f.sound ~= "") and f.sound or nil,
                    warn = tonumber(f.warn),
                    linger = tonumber(f.linger),
                    iconID = tonumber(f.icon),
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

-- A number as short as it can be written: 34, 1.5, -5.
local function num(n)
    return (("%.10g"):format(n))
end

-- One timer back into a note line, the reverse of Parse: Parse(FormatLine(t)) gives back the same timer.
-- Only the fields the timer has are written.
function Parser.FormatLine(t)
    local out = {}
    local function add(key, value)
        out[#out + 1] = key .. ":" .. value .. ";"
    end
    add("time", num(t.time or 0))
    if t.ph then
        add("ph", num(t.ph))
    end
    if t.tags and #t.tags > 0 then
        add("tag", table.concat(t.tags, " "))
    end
    if t.kind == "spell" and t.spellId then
        add("spellid", num(t.spellId))
    end
    if t.text then
        add("text", t.text)
    end
    if t.dur then
        add("dur", num(t.dur))
    end
    if t.color then
        local c = t.color
        add("colors", num(c[1] or 1) .. " " .. num(c[2] or 1) .. " " .. num(c[3] or 1) .. " " .. num(c[4] or 1))
    end
    if t.show then
        local list = {}
        for _, w in ipairs(SHOW_WORDS) do
            if t.show[w] then
                list[#list + 1] = w
            end
        end
        add("show", table.concat(list, ","))
    end
    if t.tts then
        add("tts", "1")
    end
    if t.count then
        add("count", "1")
    end
    if t.sound then
        add("sound", t.sound)
    end
    if t.glow then
        add("glow", "1")
    end
    if t.warn then
        add("warn", num(t.warn))
    end
    if t.linger then
        add("linger", num(t.linger))
    end
    if t.iconID then
        add("icon", num(t.iconID))
    end
    return table.concat(out)
end
