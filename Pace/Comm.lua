local ADDON, CRT = ...

-- Sharing pace plans with the group through addon messages, like raid notes. Only the raid leader or
-- an assistant can share, and plans are only accepted from them. A received plan is saved as the
-- raid's plan for that boss (CRTDB.pace.shared[encounterID]), apart from your own plan, and becomes
-- the plan in use: a new share always switches you back to the raid's plan, and your own is never
-- changed. Addon messages are blocked during a boss encounter, so share before the pull.
--
-- Message under the prefix CRTPace1: "<encounterID>|<hash>|<part>|<total>|<text>", where text is a part
-- of the plan as Pace:Export writes it (plain text, its lines joined by ";"), and hash is its
-- fingerprint, so a plan that arrives damaged is dropped.

local Pace = CRT.Pace
local Comm = {}
CRT.PaceComm = Comm

local PREFIX = "CRTPace1"
local CHUNK = 200
local RESULT = Enum and Enum.SendAddonMessageResult or {}
local SUCCESS = RESULT.Success or 0
local THROTTLED = RESULT.AddonMessageThrottle or 3
local LOCKDOWN = RESULT.AddOnMessageLockdown or 11

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local queue = {} -- messages waiting to go, in order
local incoming = {} -- sender .. id .. hash -> { total, parts, count }

local function channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

local function isLeaderOrAssist(unit)
    return (UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)) and true or false
end

-- Two small running sums (a djb2 kept under 2^24 and an Adler-style sum), plus the length, so a
-- damaged plan practically never matches, with every number small enough for any Lua.
local function fingerprint(text)
    local h, a = 5381, 1
    for i = 1, #text do
        local b = text:byte(i)
        h = (h * 33 + b) % 16777216
        a = (a * 7 + b) % 65521
    end
    return string.format("%06x%04x%x", h, a, #text)
end

function Comm:CanShare()
    if not channel() then
        return false, "You need to be in a group to share pace plans."
    end
    if not isLeaderOrAssist("player") then
        return false, "Only the raid leader or an assistant can share pace plans."
    end
    return true
end

local function sendQueue()
    local ch = channel()
    if not ch then
        wipe(queue)
        CRT:Print("Sharing stopped: you left the group.")
        return
    end
    while #queue > 0 do
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, queue[1], ch)
        if not ok then
            wipe(queue)
            CRT:Print("Sharing the pace plan failed: " .. tostring(result))
            return
        end
        if result == THROTTLED then
            C_Timer.After(1, sendQueue)
            return
        elseif result == LOCKDOWN then
            wipe(queue)
            CRT:Print("Pace plans can't be shared during an encounter. Share again after the pull ends.")
            return
        elseif not (result == true or result == nil or result == SUCCESS) then
            wipe(queue)
            CRT:Print("Sharing the pace plan failed with result " .. tostring(result) .. ".")
            return
        end
        table.remove(queue, 1)
    end
end

-- Queues one boss's plan in use. Returns true when there was one.
local function queuePlan(encounterID)
    -- Line breaks travel as ";" (plan text has none of its own).
    local text = (Pace:Export(encounterID):gsub("\n", ";"))
    if text == "" then
        return false
    end
    local hash = fingerprint(text)
    local parts = {}
    for pos = 1, #text, CHUNK do
        parts[#parts + 1] = text:sub(pos, pos + CHUNK - 1)
    end
    for i, part in ipairs(parts) do
        queue[#queue + 1] = encounterID .. "|" .. hash .. "|" .. i .. "|" .. #parts .. "|" .. part
    end
    return true
end

-- Shares one boss's plan in use, or with ids a list of bosses. Returns how many were shared.
function Comm:Share(ids)
    local ok, why = self:CanShare()
    if not ok then
        CRT:Print(why)
        return 0
    end
    local n = 0
    for _, id in ipairs(ids) do
        if queuePlan(id) then
            n = n + 1
        end
    end
    if n == 0 then
        CRT:Print("There is no pace plan to share.")
        return 0
    end
    sendQueue()
    CRT:Print(string.format("Shared %d pace plan%s with the group.", n, n == 1 and "" or "s"))
    return n
end

-- Every boss with a plan in use, for Share all.
function Comm:AllPlanned()
    local seen, out = {}, {}
    local function add(id)
        if not seen[id] and Pace:Plan(id) then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for id in pairs(CRT.db.pace.own) do
        add(id)
    end
    for id in pairs(CRT.db.pace.shared) do
        add(id)
    end
    for id in pairs(CRT.PaceDB.bosses) do
        add(id)
    end
    table.sort(out)
    return out
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or type(sender) ~= "string" then
        return
    end
    if (issecretvalue and (issecretvalue(message) or issecretvalue(sender))) then
        return
    end
    local short = Ambiguate(sender, "none")
    if short == UnitName("player") or not isLeaderOrAssist(short) then
        return
    end
    local id, hash, part, total, data = message:match("^(%d+)|(%x+)|(%d+)|(%d+)|(.*)$")
    id, part, total = tonumber(id), tonumber(part), tonumber(total)
    if not (id and hash and part and total) or part < 1 or part > total or total > 50 then
        return
    end
    local key = sender .. ":" .. id .. ":" .. hash
    local buffer = incoming[key]
    if not buffer then
        buffer = { total = total, parts = {}, count = 0 }
        incoming[key] = buffer
    end
    if not buffer.parts[part] then
        buffer.parts[part] = data
        buffer.count = buffer.count + 1
    end
    if buffer.count < buffer.total then
        return
    end
    incoming[key] = nil
    local text = table.concat(buffer.parts, "", 1, buffer.total)
    if fingerprint(text) ~= hash then
        CRT:Print("A pace plan from " .. short .. " arrived damaged. Ask them to share it again.")
        return
    end
    local n, err = Pace:ReceiveShared(id, (text:gsub(";", "\n")), short)
    if n then
        CRT:Print(string.format("%s shared the pace plan for %s (%d checkpoint%s). It's now your plan in use; your own plan is kept.", short, Pace:BossName(id), n, n == 1 and "" or "s"))
    else
        CRT:Print("A pace plan from " .. short .. " could not be read: " .. tostring(err))
    end
end)
