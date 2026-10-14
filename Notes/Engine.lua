local ADDON, CRT = ...

-- Runs a note's timers. ENCOUNTER_START starts the clock for the note that matches the boss, and every
-- timer counts down from the start of its phase. There is no phase-change event an addon can use in
-- Midnight, so phases after the first start when someone presses Next phase (or /crt note next).
-- /crt note test starts the active note at once, to try it out of an encounter.

local Notes = CRT.Notes
local Engine = { running = false }
CRT.NoteEngine = Engine

local starts = {} -- phase -> GetTime() when it began
local note -- the parsed note being run

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

-- Whether a timer is for you: your name, your role, everyone, or your raid group. A name in a tag
-- may carry a realm, which is ignored.
function Engine:IsMine(item)
    local mine = tokens()
    local tags = item.tags
    local subgroup
    local i = 1
    while i <= #tags do
        local word = tags[i]:lower():gsub("%-.*$", "")
        if mine[word] then
            return true
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

function Engine:Start(parsedNote, reason)
    if not parsedNote then
        return
    end
    note = parsedNote
    wipe(starts)
    starts[note.phases[1] or 1] = GetTime()
    self.running = true
    self.reason = reason
    self.runId = (self.runId or 0) + 1
    myTokens = nil
    Notes:Fire()
end

function Engine:Stop()
    self.running = false
    note = nil
    wipe(starts)
    Notes:Fire()
end

-- Starts the next phase now. Returns the phase that started, or nil.
function Engine:NextPhase()
    if not self.running or not note then
        return nil
    end
    for _, ph in ipairs(note.phases) do
        if not starts[ph] then
            starts[ph] = GetTime()
            Notes:Fire()
            return ph
        end
    end
    return nil
end

function Engine:PhaseStarted(ph)
    return starts[ph] ~= nil
end

function Engine:CurrentPhase()
    local current
    for _, ph in ipairs(note and note.phases or {}) do
        if starts[ph] then
            current = ph
        end
    end
    return current
end

-- Seconds since the pull.
function Engine:Elapsed()
    if not self.running or not note then
        return nil
    end
    return GetTime() - (starts[note.phases[1] or 1] or GetTime())
end

-- Seconds until a timer, or nil if its phase has not started. Negative once it has passed.
function Engine:Remaining(item)
    local start = starts[item.ph]
    if not start then
        return nil
    end
    return start + item.time - GetTime()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ENCOUNTER_START")
events:RegisterEvent("ENCOUNTER_END")
events:SetScript("OnEvent", function(_, event, encounterID, _, difficultyID)
    if event == "ENCOUNTER_START" then
        local difficultyName = difficultyID and GetDifficultyInfo and GetDifficultyInfo(difficultyID)
        local id = Notes:FindForEncounter(encounterID, difficultyName)
        if id then
            Notes:SetActive(id)
            Engine:Start(Notes:Parsed(id), "encounter")
        end
    elseif Engine.reason == "encounter" then
        Engine:Stop()
    end
end)
