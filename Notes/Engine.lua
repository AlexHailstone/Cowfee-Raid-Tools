local ADDON, CRT = ...

-- Runs a note's timers on the alerts engine (Alerts/Engine.lua). On ENCOUNTER_START the engine asks this
-- file for the note that matches the boss, and every timer counts down from the start of its phase.
-- There is no phase-change event an addon can use in Midnight, so phases after the first start when
-- someone presses Next phase (or /crt note next). /crt note test starts the active note at once, to try
-- it out of an encounter. The note is the engine's "note" block: one item per timer.

local Notes = CRT.Notes
local Alerts = CRT.Alerts
local Rules = CRT.AlertRules
local Engine = { running = false, runId = 0 }
CRT.NoteEngine = Engine

local note       -- the parsed note being run
local noteRunId  -- the engine run the note belongs to; any other run drops it
local claiming   -- true while Engine:Start starts the engine run for its note

-- Melee damage specializations, used for the "melee" and "ranged" tags. Tanks and healers match
-- "tank" and "healer" instead. A spec not listed counts as ranged.
local MELEE_SPECS = {
    [70] = true, -- Retribution Paladin
    [71] = true, [72] = true, -- Arms, Fury Warrior
    [251] = true, [252] = true, -- Frost, Unholy Death Knight
    [259] = true, [260] = true, [261] = true, -- Rogue
    [269] = true, -- Windwalker Monk
    [577] = true, -- Havoc Demon Hunter
    [103] = true, -- Feral Druid
    [255] = true, -- Survival Hunter
    [263] = true, -- Enhancement Shaman
}

local function specIdAndRole()
    local info = C_SpecializationInfo
    local getSpec = (info and info.GetSpecialization) or GetSpecialization
    local getInfo = (info and info.GetSpecializationInfo) or GetSpecializationInfo
    if not (getSpec and getInfo) then
        return nil, nil
    end
    local ok, index = pcall(getSpec)
    if not ok or not index then
        return nil, nil
    end
    local ok2, id, _, _, _, role = pcall(getInfo, index)
    if ok2 then
        return id, role
    end
    return nil, nil
end

-- The words that match you: your name, your role, and melee or ranged.
local myTokens, tokensAt
local function tokens()
    if myTokens and tokensAt and GetTime() - tokensAt < 5 then
        return myTokens
    end
    local t = { all = true, everyone = true, raid = true }
    local name = UnitName("player")
    if name then
        t[name:lower()] = true
    end
    local specId, specRole = specIdAndRole()
    local role = UnitGroupRolesAssigned("player")
    if not role or role == "NONE" then
        role = specRole
    end
    if role == "TANK" then
        t.tank, t.tanks = true, true
    elseif role == "HEALER" then
        t.healer, t.healers, t.heal = true, true, true
    else
        t.dps, t.damager = true, true
        if specId and MELEE_SPECS[specId] then
            t.melee, t.melees = true, true
        else
            t.ranged, t.range = true, true
        end
    end
    myTokens, tokensAt = t, GetTime()
    return t
end

local function readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

-- Your class as tag words: the class file name and the class's own name, lower-cased with every space
-- removed, so "DEATHKNIGHT" (what the editor writes), "deathknight" and "death knight" all match (and
-- "chevalier de la mort" in French).
-- Only IsMine reads these: a class word is common in ordinary sentences, so it never marks free text as yours.
local myClasses, classesAt
local function classTokens()
    if myClasses and classesAt and GetTime() - classesAt < 5 then
        return myClasses
    end
    local t = {}
    if UnitClass then
        local ok, localized, file = pcall(UnitClass, "player")
        if ok then
            for _, v in ipairs({ { localized }, { file } }) do
                v = v[1]
                if readable(v) and type(v) == "string" then
                    local joined = v:gsub("%s+", "")
                    for _, lower in ipairs({ string.lower, strlower or string.lower }) do
                        local word = lower(joined)
                        if word ~= "" then
                            t[word] = true
                        end
                    end
                end
            end
        end
    end
    myClasses, classesAt = t, GetTime()
    return t
end

-- Your raid group number. In a party or solo you count as group 1.
local function mySubgroup()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if UnitIsUnit("raid" .. i, "player") then
                local _, _, subgroup = GetRaidRosterInfo(i)
                return subgroup
            end
        end
    end
    return 1
end

-- The group number a tag names: "G1", "Grp1" or "Group1" in one word, or "G", "Grp" or "Group"
-- followed by a number as the next word, so "Group 1" works too. Returns the number and how many
-- words it used, or nil.
local GROUP_WORDS = { g = true, grp = true, group = true }
local function groupTag(word, nextWord)
    local prefix, number = word:match("^(%a+)(%d)$")
    if prefix and GROUP_WORDS[prefix] then
        return tonumber(number), 1
    end
    if GROUP_WORDS[word] and nextWord and nextWord:match("^%d$") then
        return tonumber(nextWord), 2
    end
    return nil
end

-- Whether a timer is for you: your name, your role, your class, everyone, or your raid group. A name in
-- a tag may carry a realm, which is ignored. A class name of several words may be split over them.
function Engine:IsMine(item)
    local mine = tokens()
    local classes = classTokens()
    local tags = item.tags
    local subgroup
    local i = 1
    while i <= #tags do
        local word = tags[i]:lower():gsub("%-.*$", "")
        if mine[word] or classes[word] then
            return true
        end
        local joined = word
        for j = i + 1, #tags do
            joined = joined .. tags[j]:lower()
            if classes[joined] then
                return true
            end
        end
        local number, used = groupTag(word, tags[i + 1])
        if number then
            subgroup = subgroup or mySubgroup()
            if number == subgroup then
                return true
            end
            i = i + used
        else
            i = i + 1
        end
    end
    return false
end

-- Whether a timer stays when "Show only me" is on: it is yours, or it has no tag, which means everyone.
function Engine:IsForMe(item)
    return #item.tags == 0 or self:IsMine(item)
end

-- Words that also appear in ordinary sentences, so they never mark a line of free text as yours.
local NOT_IN_TEXT = { all = true, everyone = true, raid = true, range = true, heal = true, damager = true }

-- Whether a word of a note's free text is your name or your role, such as "Tanks" or "Melee".
function Engine:WordIsMe(word)
    local w = word:lower():gsub("%-.*$", "")
    if NOT_IN_TEXT[w] then
        return false
    end
    return tokens()[w] and true or false
end

function Engine:Note()
    return note
end

-- Starts a run of the note. Inside a pull (the engine's onPull hook) the run is already starting and
-- collects the note's items right after, so the engine is only started here for a test run.
function Engine:Start(parsedNote, reason)
    if not parsedNote then
        return
    end
    note = parsedNote
    self.reason = reason
    myTokens, myClasses = nil, nil
    if Alerts.starting then
        noteRunId = Alerts.runId
    else
        claiming = true
        Alerts:Start(parsedNote.encounterID, nil, reason)
        claiming = false
    end
end

function Engine:Stop()
    Alerts:Stop()
end

-- Starts the next phase of the alerts run now, with or without a note (a pull may run only
-- reminders). Returns the phase that started, or nil.
function Engine:NextPhase()
    if not Alerts.running then
        return nil
    end
    return Alerts:NextPhase()
end

-- The phase Next phase would start, or nil. Starts nothing.
function Engine:PeekNextPhase()
    return Alerts:PeekNextPhase()
end

function Engine:PhaseStarted(ph)
    return Alerts:PhaseStart(ph) ~= nil
end

function Engine:CurrentPhase()
    return Alerts:CurrentPhase()
end

-- Seconds since the pull.
function Engine:Elapsed()
    if not self.running or not note then
        return nil
    end
    return Alerts:Elapsed()
end

-- Seconds until a timer, or nil if its phase has not started. Negative once it has passed.
function Engine:Remaining(item)
    local start = Alerts:PhaseStart(item.ph)
    if not start then
        return nil
    end
    return start + item.time - GetTime()
end

-- The note block -----------------------------------------------------------------------------

-- The note a run uses: the one running for the current run, or (for any other run, such as the
-- Phases tab asking which phases a boss has) the note saved for that boss.
local function noteFor(run)
    if run == nil or run == Alerts.run then
        return note
    end
    if run.encounterID then
        local id = Notes:FindForEncounter(run.encounterID, run.difficultyName)
        if id then
            return Notes:Parsed(id)
        end
    end
    return nil
end

-- The alert item of one timer, `index` its place in the note and `mine` whether it is for you. Your
-- timers alert, show as bars and are read out, or, when the line has show:, use exactly the displays it
-- names; anyone else's only show in the timers window, so they carry no outputs. Used by the block and by
-- the alert editor's Test of a note line.
function Engine.ItemFor(t, index, mine)
    local s = Notes:Alert() or {}
    local info = t.kind == "spell" and Notes:SpellInfo(t.spellId) or nil
    local item = {
        id = "note:" .. index,
        ph = t.ph,
        time = t.time,
        spellID = t.spellId,
        icon = info and info.icon,
        text = t.kind == "spell" and (info and info.name or ("Spell " .. tostring(t.spellId))) or (t.text or ""),
        color = t.color,
    }
    -- A line with show: is labelled by its text: when it has one, as a reminder is; the spell gives the
    -- icon. A line without show: keeps the spell's name. ownLabel tells the Next spell alert to show the
    -- item's own text, icon and colour, as the areas do.
    if t.show then
        item.ownLabel = true
    end
    if t.show and type(t.text) == "string" and t.text ~= "" then
        item.text = t.text
    end
    if t.show and type(t.iconID) == "number" and t.iconID > 0 then
        item.icon = t.iconID
    end
    if not mine then
        return item
    end
    item.priority = Rules.Priority(2, "normal")
    if t.show then
        local show = t.show
        local speaks = (t.tts or t.count) and true or false
        item.outputs = {
            alert = show.alert and true or false,
            text = show.text and true or false,
            icon = show.icon and true or false,
            bar = show.bar and true or false,
            circle = show.circle and true or false,
            speech = speaks,
        }
        item.warn = t.warn or s.seconds or 10
        item.hold = math.max(0.5, t.linger or t.dur or 0)
        item.sound = t.sound
        item.glow = t.glow and true or nil
        item.speech = Rules.SpeechItems(item.text, item.warn, t.tts and true or false, t.count and true or false)
        return item
    end
    local bars = (Alerts:Settings() or {}).bars or {}
    item.outputs = {
        alert = s.enabled and true or false,
        bar = (bars.shown and bars.noteLines) and true or false,
        speech = (s.enabled and s.tts) and true or false,
    }
    item.warn = s.seconds or 10
    -- A spell shows for half a second after its time, a text line for its dur:.
    item.hold = t.kind == "text" and (t.dur or 0) or 0.5
    item.speech = { { offset = s.ttsSeconds or 3, text = info and info.name or t.text or "" } }
    return item
end

-- One item per timer.
local function entries(run)
    local n = noteFor(run)
    if not n then
        return {}
    end
    local out = {}
    for index, t in ipairs(n.timers) do
        out[#out + 1] = Engine.ItemFor(t, index, Engine:IsMine(t))
    end
    return out
end

Alerts:RegisterBlock("note", { label = "Raid note", group = false, Entries = entries })

-- On a pull, the note for the boss (preferring the same difficulty) becomes the note in use and runs.
Alerts.onPull[#Alerts.onPull + 1] = function(run)
    note = nil
    local id = Notes:FindForEncounter(run.encounterID, run.difficultyName)
    if id then
        Notes:SetActive(id)
        Engine:Start(Notes:Parsed(id), "encounter")
    end
end

-- running and runId follow the engine; running is only true while the engine runs a note, so a pull
-- of a boss with no note shows as not running, as before. When the engine stops (Stop, or the end of
-- the encounter) or another run replaces the note's (such as the reminder editor's Test), the note is
-- dropped. Every change tells the note windows and pages.
Alerts:OnChange(function()
    if claiming and Alerts.running then
        noteRunId = Alerts.runId
    end
    if not Alerts.running or Alerts.runId ~= noteRunId then
        note = nil
    end
    Engine.running = Alerts.running and note ~= nil
    Engine.runId = Alerts.runId
    Notes:Fire()
end)
