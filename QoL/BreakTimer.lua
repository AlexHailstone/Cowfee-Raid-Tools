local ADDON, CRT = ...

-- The break timer: /crt break <minutes> starts a break, /crt break 0 cancels it. A small movable window
-- counts it down with a bar; at the end a sound plays and it says the break is over.
-- From the raid leader or an assistant it reaches the whole group: everyone with the addon gets the
-- same timer (addon message CRTBreak1: "S:<seconds>" to start, "C" to cancel), and a raid warning (in a
-- party, a party message) tells everyone else. From anyone else it is a timer for you only.
-- The break's end is saved (CRTDB.qol.breakTimer.endsAt, a time() value), so it survives a /reload.

local Break = {}
CRT.BreakTimer = Break

local UI = CRT.UI

local PREFIX = "CRTBreak1"
local MAX_MINUTES = 60
local BAR_W, BAR_H = 300, 30
local OVER_SHOWN = 6 -- seconds "Break's over" stays up
local LAST_MINUTE = 60 -- seconds left when the bar turns red
local COLOR_BAR = { 0.78, 0.56, 0.36, 1 }
local COLOR_LAST = { 0.85, 0.27, 0.2, 1 }

local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local frame, handle, bar, label, timeText, endsText
local previewOn = false

local function db()
    return CRT.db.qol.breakTimer
end

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

local function clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The window ---------------------------------------------------------------------------------------

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    db().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function applyPosition()
    local p = db().position
    frame:ClearAllPoints()
    if p then
        frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

function Break:ResetPosition()
    db().position = nil
    if frame then
        applyPosition()
    end
end

local onUpdate

local function build()
    if frame then
        return
    end
    -- A big bar with "Break" and the time left inside it, and "Break ends at: 23:00" under it.
    frame = CreateFrame("Frame", "CowfeeRaidToolsBreak", UIParent)
    frame:SetSize(BAR_W, BAR_H + 26)
    UI:RegisterLayer("alert", frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    -- Right-click hides it for you; the break keeps running and the end still plays.
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not previewOn then
            frame:Hide()
        end
    end)

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("TOP")
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(unpack(COLOR_BAR))
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.75)

    label = bar:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    label:SetPoint("LEFT", 6, 0)
    label:SetTextColor(1, 1, 1)
    label:SetShadowOffset(1, -1)
    timeText = bar:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    timeText:SetPoint("RIGHT", -6, 0)
    timeText:SetTextColor(1, 1, 1)
    timeText:SetShadowOffset(1, -1)
    endsText = frame:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    endsText:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    endsText:SetTextColor(1, 1, 1)
    endsText:SetShadowOffset(1, -1)

    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    UI:RegisterThemed(handle, { bg = { 0.3, 0.25, 0.05, 0.9 }, border = { 0.78, 0.63, 0.31 } })
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", 6, 0)
    text:SetText("Break timer: drag to move")
    handle:SetScript("OnDragStart", function()
        frame:StartMoving(true)
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    UI.ResetButton(handle, function()
        Break:ResetPosition()
    end):SetPoint("RIGHT", -2, 0)
    handle:Hide()

    applyPosition()
    frame:Hide()
end

local overAt -- GetTime() when "Break's over" was shown

local elapsed = 0
onUpdate = function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.2 then
        return
    end
    elapsed = 0
    local s = db()
    if overAt then
        if GetTime() - overAt >= OVER_SHOWN then
            overAt = nil
            frame:SetScript("OnUpdate", nil)
            if not previewOn then
                frame:Hide()
            end
        end
        return
    end
    if not s.endsAt then
        frame:SetScript("OnUpdate", nil)
        return
    end
    local left = s.endsAt - time()
    if left <= 0 then
        s.endsAt, s.total, s.from = nil, nil, nil
        overAt = GetTime()
        label:SetText("Break's over")
        timeText:SetText("0:00")
        endsText:SetText("")
        bar:SetValue(0)
        CRT:PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
        CRT:Print("The break is over.")
        return
    end
    bar:SetMinMaxValues(0, math.max(1, s.total or left))
    bar:SetValue(left)
    -- The last minute turns the bar red, so raiders know to get back.
    if left <= LAST_MINUTE then
        bar:SetStatusBarColor(unpack(COLOR_LAST))
    else
        bar:SetStatusBarColor(unpack(COLOR_BAR))
    end
    timeText:SetText(clock(left))
end

local function show()
    build()
    local s = db()
    overAt = nil
    label:SetText("Break" .. (s.from and (" - " .. Ambiguate(s.from, "short")) or ""))
    -- The clock time it ends, for raiders who missed the raid warning.
    endsText:SetText(s.endsAt and ("Break ends at: " .. date("%H:%M", s.endsAt)) or "")
    elapsed = 1
    frame:SetScript("OnUpdate", onUpdate)
    frame:Show()
end

-- Starting and stopping -------------------------------------------------------------------------

-- Starts a break of `seconds`. from: who started it (nil for you).
local function begin(seconds, from)
    local s = db()
    s.endsAt = time() + seconds
    s.total = seconds
    s.from = from
    show()
end

local function stop(quiet)
    local s = db()
    local had = s.endsAt ~= nil
    s.endsAt, s.total, s.from = nil, nil, nil
    overAt = nil
    if frame and not previewOn then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    if had and not quiet then
        CRT:Print("Break cancelled.")
    end
end

local function broadcast(message)
    local ch = channel()
    if ch and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, ch)
    end
end

local function announce(text)
    local ch = channel()
    if not ch or not send then
        return
    end
    -- A raid warning reaches everyone on screen; in a party there's no warning, so party chat.
    if ch == "RAID" and isLeaderOrAssist("player") then
        ch = "RAID_WARNING"
    end
    pcall(send, text, ch)
end

-- /crt break <minutes>: 0 cancels. Returns nothing; prints what it did.
function Break:Command(arg)
    local minutes = tonumber(arg)
    if not minutes or minutes < 0 then
        CRT:Print("Type /crt break and the minutes, such as /crt break 10. /crt break 0 cancels it.")
        return
    end
    minutes = math.min(MAX_MINUTES, minutes)
    local shared = IsInGroup() and isLeaderOrAssist("player")
    if minutes == 0 then
        stop()
        if shared then
            broadcast("C")
            announce("Break cancelled.")
        end
        return
    end
    local seconds = math.floor(minutes * 60 + 0.5)
    begin(seconds, nil)
    if shared then
        broadcast("S:" .. seconds)
        announce(string.format("Break: %s minute%s, back at %s.", (minutes % 1 == 0) and tostring(minutes) or string.format("%.1f", minutes), minutes == 1 and "" or "s", date("%H:%M", time() + seconds)))
    elseif IsInGroup() then
        CRT:Print("Break timer started for you only. A raid leader or assistant's break reaches the whole group.")
    end
end

function Break:Remaining()
    local s = db()
    return s.endsAt and math.max(0, s.endsAt - time()) or nil
end

-- Previews: the window with a sample break, to place it.
UI:RegisterPreview("break", function(on)
    previewOn = on and true or false
    build()
    handle:SetShown(previewOn)
    if previewOn then
        label:SetText("Break")
        timeText:SetText("7:30")
        endsText:SetText("Break ends at: 20:10")
        bar:SetStatusBarColor(unpack(COLOR_BAR))
        bar:SetMinMaxValues(0, 600)
        bar:SetValue(450)
        frame:Show()
    elseif not db().endsAt and not overAt then
        frame:Hide()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
    if event == "PLAYER_LOGIN" then
        -- A break still running after a /reload comes back.
        local s = db()
        if s.endsAt and s.endsAt > time() then
            show()
        else
            s.endsAt, s.total, s.from = nil, nil, nil
        end
        return
    end
    if prefix ~= PREFIX or type(message) ~= "string" or type(sender) ~= "string" then
        return
    end
    if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then
        return
    end
    local short = Ambiguate(sender, "none")
    if short == UnitName("player") or not isLeaderOrAssist(short) then
        return
    end
    local seconds = tonumber(message:match("^S:(%d+)$"))
    if seconds and seconds > 0 and seconds <= MAX_MINUTES * 60 then
        begin(seconds, sender)
        CRT:Print(string.format("%s started a %s break.", Ambiguate(sender, "short"), clock(seconds)))
    elseif message == "C" then
        stop(true)
        CRT:Print(Ambiguate(sender, "short") .. " cancelled the break.")
    end
end)
