local ADDON, CRT = ...

-- Sharing notes with the group through addon messages. The game allows each prefix a burst of 10
-- messages, then 1 a second, and 255 characters a message. So a note is compressed first with the
-- game's own C_EncodingUtil.CompressString (Deflate), which makes a typical note a quarter of its
-- size, and the parts are sent straight away, waiting only when the game reports the throttle. A note
-- of up to 10 parts after compression arrives at once. Addon messages are blocked during a boss
-- encounter, so share before the pull.
--
-- Message under the prefix CRTNote2: "<hash>|<part>|<total>|<data>". hash is a fingerprint of the
-- note text, so a raider who already has that exact note skips the download and makes their stored
-- copy the active note. Sharing a note always makes it the active note for everyone, the sender too
-- (the sender's even when it can't be sent), so notes can be shared ahead of time and shared again to
-- switch the raid to one. data is the compressed note,
-- with byte 0 (not allowed in addon messages) and the escape byte 1 written as two bytes each.
-- Version 0.12 and earlier sent plain text under CRTNote, "<id>|<part>|<total>|<text>", which is
-- still received so older senders keep working. Only a raid leader or assistant can share, and by
-- default notes are only accepted from them.

local Notes = CRT.Notes
local Comm = {}
CRT.NoteComm = Comm

local PREFIX = "CRTNote2"
local OLD_PREFIX = "CRTNote"
local OLD_CHUNK = 220 -- the plain-text part size, used only when compression is missing
-- Data bytes a part may carry after escaping. The header is at most 22 characters (a 13-digit
-- fingerprint and two 3-digit part numbers with their separators), so a message stays under 255.
local MAX_DATA = 230
local MAX_PARTS = 200

local RESULT = Enum and Enum.SendAddonMessageResult or {}
local SUCCESS = RESULT.Success or 0
local THROTTLED = RESULT.AddonMessageThrottle or 3
local LOCKDOWN = RESULT.AddOnMessageLockdown or 11

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(OLD_PREFIX)
end

local Encoding = C_EncodingUtil
local DEFLATE = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
local canCompress = Encoding and Encoding.CompressString and Encoding.DecompressString and true or false

local outgoing -- { prefix, hash, parts, index, name, started }
local incoming = {} -- sender .. hash -> { total, parts, count, skip }

local function channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function isLeaderOrAssist(unit)
    return (UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)) and true or false
end

-- Fingerprint --------------------------------------------------------------------------------

-- A 32-bit fingerprint of the text (djb2) as 8 hex digits, plus its length, so two different notes
-- practically never match.
local function fingerprint(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return format("%08x%x", h, #text)
end
Comm.Fingerprint = fingerprint

local known = {} -- raw text -> fingerprint, so stored notes are not hashed again and again

-- The stored note with exactly this text, or nil.
local function haveNote(hash)
    for id, record in pairs(CRT.db.notes.list) do
        local raw = record.raw or ""
        known[raw] = known[raw] or fingerprint(raw)
        if known[raw] == hash then
            return id
        end
    end
    return nil
end

-- Escaping ---------------------------------------------------------------------------------------

-- Byte 0 is not allowed in an addon message, so cut() writes 0 as 1 2 and 1 as 1 1, and this
-- reverses it.
local function unescape(data)
    return (data:gsub("\1(.)", function(c)
        return c == "\1" and "\1" or "\0"
    end))
end

-- Cuts the compressed note into parts of at most MAX_DATA bytes after escaping, never splitting an
-- escaped pair.
local function cut(data)
    local parts, current, size = {}, {}, 0
    for i = 1, #data do
        local c = data:sub(i, i)
        local e = (c == "\0" and "\1\2") or (c == "\1" and "\1\1") or c
        if size + #e > MAX_DATA then
            parts[#parts + 1] = table.concat(current)
            current, size = {}, 0
        end
        current[#current + 1] = e
        size = size + #e
    end
    if size > 0 then
        parts[#parts + 1] = table.concat(current)
    end
    return parts
end

-- Sending -----------------------------------------------------------------------------------------

-- The Empty note: what Share sends when there is no note to share. A name and one line of text, so every
-- version of the addon takes it as a note; no encounter ID, so no boss uses it.
local EMPTY_TEXT = "EncounterID:;Name:Empty\nEmpty"

local function emptyNote()
    for id, record in pairs(CRT.db.notes.list) do
        if record.raw == EMPTY_TEXT then
            return id
        end
    end
    return (Notes:Import(EMPTY_TEXT))
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
    return outgoing and outgoing.index - 1 or nil, outgoing and #outgoing.parts or nil
end

local function finish(message)
    if message then
        CRT:Print(message)
    end
    outgoing = nil
    Notes:Fire()
end

-- Sends every part the game will take right now, then waits a second if it reports the throttle.
local function sendParts()
    if not outgoing then
        return
    end
    local ch = channel()
    if not ch then
        finish("Sharing stopped: you left the group.")
        return
    end
    while outgoing.index <= #outgoing.parts do
        local i = outgoing.index
        local message = outgoing.hash .. "|" .. i .. "|" .. #outgoing.parts .. "|" .. outgoing.parts[i]
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, outgoing.prefix, message, ch)
        if not ok then
            finish("Sharing failed: " .. tostring(result))
            return
        end
        if result == THROTTLED then
            C_Timer.After(1, sendParts)
            return
        elseif result == LOCKDOWN then
            finish("Notes can't be shared during an encounter. Share again after the pull ends.")
            return
        elseif not (result == true or result == nil or result == SUCCESS) then
            finish("Sharing failed with result " .. tostring(result) .. ".")
            return
        end
        outgoing.index = i + 1
    end
    local seconds = GetTime() - outgoing.started
    finish(format("Shared %s with the group in %d part%s, %.1f seconds.", outgoing.name, #outgoing.parts, #outgoing.parts == 1 and "" or "s", seconds))
end

-- Shares a note with the group. It always becomes your own active note first, so the Raid Notes
-- page and the alerts show what you meant to share even when it can't be sent (no group, not the
-- leader or an assistant, or a share still running); the chat then says why it wasn't sent.
function Comm:Share(id)
    local record = Notes:Get(id)
    -- No note, or one with no text: share the Empty note, which replaces everyone's note with "Empty"
    -- (and still shows the stamp). The one you have is reused, so it is never made twice.
    if not record or (record.raw or "") == "" then
        id = emptyNote()
        record = Notes:Get(id)
        if not record then
            CRT:Print("Couldn't make the Empty note.")
            return
        end
    end
    if Notes:Active() ~= id then
        Notes:SetActive(id)
    end
    -- Every press of Share note shows the "note updated" stamp here, whether or not it can go out (the
    -- chat says why when it can't); everyone who receives it gets the stamp too.
    if CRT.NoteWindow then
        CRT.NoteWindow:Flash()
    end
    local ok, why = self:CanShare()
    if not ok then
        CRT:Print(format("%s is now your active note, but it wasn't sent to the group: %s", record.name or "The note", why))
        return
    end
    local text = record.raw or ""
    if text == "" then
        CRT:Print("That note is empty.")
        return
    end

    local prefix, parts = PREFIX, nil
    if canCompress then
        local okCompress, data = pcall(Encoding.CompressString, text, DEFLATE)
        if okCompress and type(data) == "string" and data ~= "" then
            parts = cut(data)
        end
    end
    if not parts then
        -- No compression in this client: plain text in the old format.
        prefix, parts = OLD_PREFIX, {}
        for pos = 1, #text, OLD_CHUNK do
            parts[#parts + 1] = text:sub(pos, pos + OLD_CHUNK - 1)
        end
    end
    if #parts > MAX_PARTS then
        CRT:Print("That note is too long to share.")
        return
    end

    -- It is already the active note here (above); everyone who receives it makes it theirs too.
    outgoing = {
        prefix = prefix,
        hash = prefix == PREFIX and fingerprint(text) or format("%04x", math.random(0, 65535)),
        parts = parts,
        index = 1,
        name = record.name or "note",
        started = GetTime(),
    }
    if #parts > 10 then
        CRT:Print(format("Sharing %s in %d parts. The game allows 10 at once and then 1 a second, so this takes about %d seconds.", outgoing.name, #parts, #parts - 10))
    end
    Notes:Fire()
    sendParts()
end

-- Receiving ---------------------------------------------------------------------------------------

local function received(text, short)
    local newId, result = Notes:Import(text, short)
    if newId then
        Notes:SetActive(newId)
        -- the note windows show a "note updated" stamp
        if CRT.NoteWindow then
            CRT.NoteWindow:Flash()
        end
        CRT:Print("Received a note from " .. short .. ". " .. result)
    else
        CRT:Print("Received a note from " .. short .. " that could not be read: " .. tostring(result))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
    if (prefix ~= PREFIX and prefix ~= OLD_PREFIX) or type(message) ~= "string" or type(sender) ~= "string" then
        return
    end
    local short = Ambiguate(sender, "none")
    if short == UnitName("player") then
        return
    end
    if Notes:TrustedOnly() and not isLeaderOrAssist(short) then
        return
    end
    local hash, part, total, data = message:match("^(%x+)|(%d+)|(%d+)|(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not (hash and part and total) or total < 1 or total > MAX_PARTS or part < 1 or part > total then
        return
    end

    local key = prefix .. sender .. ":" .. hash
    local buffer = incoming[key]
    if not buffer then
        -- Already have this exact note: skip its parts (no download, no import), then make the stored
        -- copy active once the share has finished arriving.
        buffer = { total = total, parts = {}, count = 0, skip = prefix == PREFIX and haveNote(hash) or nil }
        incoming[key] = buffer
    end
    if not buffer.parts[part] then
        buffer.parts[part] = buffer.skip and true or data
        buffer.count = buffer.count + 1
    end
    if buffer.count < buffer.total then
        return
    end
    incoming[key] = nil
    if buffer.skip then
        local id = buffer.skip
        if CRT.db.notes.list[id] and Notes:Active() ~= id then
            Notes:SetActive(id)
            CRT:Print(short .. " shared " .. (CRT.db.notes.list[id].name or "a note") .. ", which you already have. It is now your active note.")
        end
        -- a note you already have still shows the "note updated" stamp: the leader pushed it
        if CRT.NoteWindow then
            CRT.NoteWindow:Flash()
        end
        return
    end

    if prefix == OLD_PREFIX then
        received(table.concat(buffer.parts, "", 1, buffer.total), short)
        return
    end
    if not canCompress then
        CRT:Print("Received a note from " .. short .. ", but this game client cannot unpack it.")
        return
    end
    local packed = {}
    for i = 1, buffer.total do
        packed[i] = unescape(buffer.parts[i])
    end
    local ok, text = pcall(Encoding.DecompressString, table.concat(packed), DEFLATE)
    if not ok or type(text) ~= "string" then
        CRT:Print("Received a note from " .. short .. " that could not be unpacked.")
        return
    end
    if fingerprint(text) ~= hash then
        CRT:Print("Received a note from " .. short .. " that arrived damaged. Ask them to share it again.")
        return
    end
    received(text, short)
end)
