local ADDON, CRT = ...

-- Early pull: who starts the fight while a pull timer is still counting down. During the timer it
-- notes each group member's casts (who and when; the spell itself is hidden by the game for anyone
-- but you) and the order in which group members enter combat (UNIT_FLAGS and UnitAffectingCombat,
-- which the game does not hide). If someone enters combat more than EARLY_SLACK seconds before the
-- timer ends, it reports the first ones in combat and the casts just before, once per timer.
-- Settings: CRTDB.readycheck.earlyPull (on or off) and earlyPullOutput ("self", "raid", "officer").

local EarlyPull = {}
CRT.EarlyPull = EarlyPull

local EARLY_SLACK = 0.5 -- seconds before the end that still count as on time
local CAST_WINDOW = 2 -- seconds before the first combat that a cast is listed for
local GATHER = 0.4 -- seconds to wait after the first combat, so the order of the next few is known

local pullAt -- GetTime() when the running pull timer ends, nil when none is running
local casts = {} -- { { name, t, spell } } during the timer
local order = {} -- names in the order they entered combat, with their times
local seen = {}
local reported = false

local function settings()
    return CRT.db.readycheck
end

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- The group unit tokens: you, your party or your raid.
local function groupUnit(unit)
    return readable(unit) and type(unit) == "string" and (unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$")) and true or false
end

local function unitName(unit)
    local name = UnitName(unit)
    if readable(name) then
        return name
    end
end

local function reset()
    pullAt = nil
    wipe(casts)
    wipe(order)
    wipe(seen)
    reported = false
end

local function format1(seconds)
    return string.format("%.1f s", seconds)
end

local function report()
    local first = order[1]
    if not first or reported then
        return
    end
    reported = true
    local early = first.left
    local names = {}
    for i = 1, math.min(3, #order) do
        names[#names + 1] = order[i].name
    end
    local parts = { string.format("Early pull, %s before the pull timer ended. First in combat: %s", format1(early), table.concat(names, ", ")) }
    local recent = {}
    for i = #casts, 1, -1 do
        local c = casts[i]
        if c.t <= first.t + 0.05 and first.t - c.t <= CAST_WINDOW then
            recent[#recent + 1] = c.name .. (c.spell and (" (" .. c.spell .. ")") or "") .. " " .. format1(first.t - c.t) .. " before"
            if #recent == 3 then
                break
            end
        end
    end
    if #recent > 0 then
        parts[#parts + 1] = "Last casts: " .. table.concat(recent, ", ")
    end
    local line = table.concat(parts, ". ") .. "."
    EarlyPull.last = line
    CRT.RaidReport:Output({ line }, settings().earlyPullOutput or "self")
end

-- Someone entered combat while the timer runs.
local function inCombat(unit)
    if not pullAt or reported then
        return
    end
    local now = GetTime()
    if now >= pullAt - EARLY_SLACK then
        return
    end
    local name = unitName(unit)
    if not name or seen[name] then
        return
    end
    local ok, combat = pcall(UnitAffectingCombat, unit)
    if not ok or not readable(combat) or not combat then
        return
    end
    seen[name] = true
    order[#order + 1] = { name = name, t = now, left = pullAt - now }
    if #order == 1 then
        C_Timer.After(GATHER, report)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("START_PLAYER_COUNTDOWN")
events:RegisterEvent("CANCEL_PLAYER_COUNTDOWN")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_FLAGS")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not CRT.db then
        return
    end
    if event == "START_PLAYER_COUNTDOWN" then
        reset()
        local remaining = a2
        -- The game may hide the timer's length in a raid; then there is no way to tell early from on time.
        if settings().earlyPull and IsInGroup() and readable(remaining) and type(remaining) == "number" and remaining > 0 then
            pullAt = GetTime() + remaining
            C_Timer.After(remaining + 1, function()
                if pullAt and GetTime() >= pullAt then
                    pullAt = nil
                end
            end)
        end
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        reset()
    elseif not pullAt then
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if groupUnit(a1) then
            local name = unitName(a1)
            if name then
                local spell
                if readable(a3) and type(a3) == "number" and C_Spell and C_Spell.GetSpellName then
                    local ok, spellName = pcall(C_Spell.GetSpellName, a3)
                    spell = ok and readable(spellName) and spellName or nil
                end
                casts[#casts + 1] = { name = name, t = GetTime(), spell = spell }
                if #casts > 200 then
                    table.remove(casts, 1)
                end
            end
        end
    elseif event == "UNIT_FLAGS" then
        if groupUnit(a1) then
            inCombat(a1)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat("player")
    end
end)
