local ADDON, CRT = ...

-- Sharing notes with the group through addon messages. A message holds at most 255 characters and the
-- game allows a burst of about 10 per prefix, then about 1 a second, so a note is sent in numbered chunks
-- at that pace. Addon messages are blocked during a boss encounter, so share before the pull.
--
-- Message: "<id>|<part>|<total>|<text>". Only a raid leader or assistant can share, and by default notes
-- are only accepted from them.

local Notes = CRT.Notes
local Comm = {}
CRT.NoteComm = Comm

local PREFIX = "CRTNote"
local CHUNK = 220
local BURST = 8

local RESULT = Enum and Enum.SendAddonMessageResult or {}
local SUCCESS = RESULT.Success or 0
local THROTTLED = RESULT.AddonMessageThrottle or 3
local LOCKDOWN = RESULT.AddOnMessageLockdown or 11

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local outgoing -- { id, chunks, index, name }
local incoming = {} -- sender .. id -> { total, parts, count }

local function channel()
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function isLeaderOrAssist(unit)
    return (UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)) and true or false
end

function Comm:CanShare()
    if not channel() then
        return false, "You need to be in a group to share a note."
    end
    if not isLeaderOrAssist("player") then
        return false, "Only the raid leader or an assistant can share notes."
    end
    if outgoing then
        return false, "A note is already being shared."
    end
    return true
end

function Comm:Sharing()
    return outgoing and outgoing.index - 1 or nil, outgoing and #outgoing.chunks or nil
end

local function sendNext()
    if not outgoing then
        return
    end
    local i = outgoing.index
    local chunk = outgoing.chunks[i]
    local message = outgoing.id .. "|" .. i .. "|" .. #outgoing.chunks .. "|" .. chunk
    local ch = channel()
    if not ch then
        CRT:Print("Sharing stopped: you left the group.")
        outgoing = nil
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, ch)
    if not ok then
        CRT:Print("Sharing failed: " .. tostring(result))
        outgoing = nil
        return
    end
    if result == true or result == nil or result == SUCCESS then
        outgoing.index = i + 1
        Notes:Fire()
        if outgoing.index > #outgoing.chunks then
            CRT:Print("Shared " .. outgoing.name .. " with the group.")
            outgoing = nil
            Notes:Fire()
            return
        end
    elseif result == THROTTLED then
        -- Try the same part again after a pause.
        C_Timer.After(1.5, sendNext)
        return
    elseif result == LOCKDOWN then
        CRT:Print("Notes can't be shared during an encounter. Share again after the pull ends.")
        outgoing = nil
        Notes:Fire()
        return
    else
        CRT:Print("Sharing failed with result " .. tostring(result) .. ".")
        outgoing = nil
        Notes:Fire()
        return
    end
    C_Timer.After(outgoing.index <= BURST and 0.2 or 1.1, sendNext)
end

function Comm:Share(id)
    local ok, why = self:CanShare()
    if not ok then
        CRT:Print(why)
        return
    end
    local record = Notes:Get(id)
    if not record then
        CRT:Print("Pick a note to share first.")
        return
    end
    local chunks = {}
    local text = record.raw or ""
    for pos = 1, #text, CHUNK do
        chunks[#chunks + 1] = text:sub(pos, pos + CHUNK - 1)
    end
    if #chunks == 0 then
        CRT:Print("That note is empty.")
        return
    end
    outgoing = {
        id = format("%04x", math.random(0, 65535)),
        chunks = chunks,
        index = 1,
        name = record.name or "note",
    }
    CRT:Print(format("Sharing %s in %d parts. This takes about %d seconds.", outgoing.name, #chunks, math.max(1, #chunks - BURST)))
    sendNext()
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or type(sender) ~= "string" then
        return
    end
    local short = Ambiguate(sender, "none")
    if short == UnitName("player") then
        return
    end
    if Notes:TrustedOnly() and not isLeaderOrAssist(short) then
        return
    end
    local id, part, total, chunk = message:match("^(%x+)|(%d+)|(%d+)|(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not (id and part and total) or total < 1 or total > 200 or part < 1 or part > total then
        return
    end
    local key = sender .. ":" .. id
    local buffer = incoming[key]
    if not buffer then
        buffer = { total = total, parts = {}, count = 0 }
        incoming[key] = buffer
    end
    if not buffer.parts[part] then
        buffer.parts[part] = chunk
        buffer.count = buffer.count + 1
    end
    if buffer.count >= buffer.total then
        incoming[key] = nil
        local text = table.concat(buffer.parts, "", 1, buffer.total)
        local newId, result = Notes:Import(text, short)
        if newId then
            Notes:SetActive(newId)
            CRT:Print("Received a note from " .. short .. ". " .. result)
        else
            CRT:Print("Received a note from " .. short .. " that could not be read: " .. tostring(result))
        end
    end
end)
