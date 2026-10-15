local ADDON, CRT = ...

-- The conflict rules for alerts: which entries show, which merge into one line, and what is due now.
-- Pure functions with no game calls, so the engine, speech queue and bars all share one set of rules.
-- An entry is { block, id, at, spellID, text, icon, color, priority, hold, warn,
--               outputs = { alert, bar, speech }, speech = { { at, text } } }, with `at` the GetTime() it is due.
-- A line is an entry plus `members`, the original entries it stands for. Blocks never compete with
-- each other: duplicates and grouping only apply inside one block listed in `groupBlocks`.

local Rules = {}
CRT.AlertRules = Rules

Rules.DUPLICATE = 2        -- same spell (or text) within this many seconds shows once
Rules.GROUP = 1.5          -- entries this close to the first of a run share one line
Rules.SPEECH_BEHIND = 1.5  -- a queued line this late makes the queue drop its lowest priority
Rules.SPEECH_TIMEOUT = 4   -- seconds a line may play before the next starts without a finished event

local LATE = 1  -- a speech item whose entry passed more than this many seconds ago is skipped, not spoken

local LEVEL = { high = 3, normal = 2, low = 1 }

-- rank: 3 your reminder, 2 your note line, 1 raid-wide. level: "high", "normal" or "low".
function Rules.Priority(rank, level)
    return rank * 10 + (LEVEL[level] or 2)
end

-- Earlier first, then higher priority first. Ties keep input order (index passed in as `seq`).
local function before(a, b)
    if a.at ~= b.at then return a.at < b.at end
    if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
    return a.seq < b.seq
end

local function sorted(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = { entry = e, at = e.at, priority = e.priority, seq = i } end
    table.sort(out, before)
    for i, w in ipairs(out) do out[i] = w.entry end
    return out
end

-- Same spell, or the same text when an entry has no spell.
local function dupKey(e)
    if type(e.spellID) == "number" and e.spellID > 0 then return "s" .. e.spellID end
    return "t" .. tostring(e.text)
end

-- A line standing for one entry, copied so the input is never changed.
local function newLine(e)
    local line = {}
    for k, v in pairs(e) do line[k] = v end
    line.outputs = { alert = e.outputs and e.outputs.alert, bar = e.outputs and e.outputs.bar,
        speech = e.outputs and e.outputs.speech }
    line.speech = {}
    for i, s in ipairs(e.speech or {}) do line.speech[i] = s end
    line.members = { e }
    return line
end

local function join(line, e)
    line.text = tostring(line.text) .. " + " .. tostring(e.text)
    line.priority = math.max(line.priority or 0, e.priority or 0)
    line.warn = math.max(line.warn or 0, e.warn or 0)
    line.hold = math.max(line.hold or 0, e.hold or 0)
    if e.outputs then
        for _, k in ipairs({ "alert", "bar", "speech" }) do
            if e.outputs[k] then line.outputs[k] = true end
        end
    end
    for _, s in ipairs(e.speech or {}) do line.speech[#line.speech + 1] = s end
    line.members[#line.members + 1] = e
end

-- Entries into lines. groupBlocks[block] true means that block drops duplicates and merges close entries.
function Rules.Lines(entries, groupBlocks)
    local lines, kept, runs = {}, {}, {}
    for _, e in ipairs(sorted(entries)) do
        local block = e.block
        if not (groupBlocks and groupBlocks[block]) then
            lines[#lines + 1] = newLine(e)
        else
            local list = kept[block]
            if not list then list = {}; kept[block] = list end
            local key, dup = dupKey(e), false
            for _, k in ipairs(list) do
                if k.key == key and e.at - k.at <= Rules.DUPLICATE then dup = true; break end
            end
            if not dup then
                list[#list + 1] = { key = key, at = e.at }
                local run = runs[block]
                if run and e.at - run.at <= Rules.GROUP then
                    join(run.line, e)
                else
                    local line = newLine(e)
                    lines[#lines + 1] = line
                    runs[block] = { at = e.at, line = line }
                end
            end
        end
    end
    return sorted(lines)
end

-- The line the on-screen alert shows: inside its warn and hold window, soonest first.
function Rules.Alert(lines, now)
    local best, bestGap
    for _, line in ipairs(lines) do
        if line.outputs and line.outputs.alert and now >= line.at - (line.warn or 0)
            and now < line.at + (line.hold or 0) then
            local gap = line.at - now
            if not bestGap or gap < bestGap then best, bestGap = line, gap end
        end
    end
    return best
end

-- Bar lines due within `ahead` seconds, soonest first, at most `cap`. Second value: how many were left out.
function Rules.Bars(lines, now, ahead, cap)
    local list = {}
    for _, line in ipairs(lines) do
        if line.outputs and line.outputs.bar and line.at - now <= ahead and now < line.at + (line.hold or 0) then
            list[#list + 1] = line
        end
    end
    list = sorted(list)
    local out = {}
    for i = 1, math.min(cap, #list) do out[i] = list[i] end
    return out, #list - #out
end

-- Speech items that have come due and were not spoken yet, oldest first. `spoken` is the caller's table
-- of keys, "<member id>#<index in that member's speech>", so a merged line changing members keeps its keys.
-- Only members with their own speech output on contribute. Every item returned or skipped as too late is
-- marked, so it is considered once. An item is skipped when its entry passed more than a second ago.
function Rules.SpeechDue(lines, now, spoken)
    local items = {}
    for _, line in ipairs(lines) do
        for _, member in ipairs(line.members or { line }) do
            if member.outputs and member.outputs.speech then
                for i, s in ipairs(member.speech or {}) do
                    local key = tostring(member.id) .. "#" .. i
                    if s.at <= now and not spoken[key] then
                        spoken[key] = true
                        -- Late is measured against the entry, as the note always did: a line whose speech
                        -- time passed before the pull is still read out while the line itself is ahead.
                        if now - (member.at or s.at) <= LATE then
                            items[#items + 1] = { key = key, at = s.at, text = s.text,
                                priority = member.priority or line.priority, seq = #items + 1 }
                        end
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.seq < b.seq
    end)
    for _, it in ipairs(items) do it.seq = nil end
    return items
end

-- Drops the lowest-priority item (earliest of equals) while the head of the queue is too far behind.
function Rules.Behind(queue, now)
    while #queue > 1 and now - queue[1].at > Rules.SPEECH_BEHIND do
        local worst = 1
        for i = 2, #queue do
            if (queue[i].priority or 0) < (queue[worst].priority or 0) then worst = i end
        end
        table.remove(queue, worst)
    end
    return queue
end
