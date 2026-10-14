local ADDON, CRT = ...

-- The Late Tracker page: the raid schedule, the expected roster, Start raid now and End raid, tonight's
-- live list of who is missing with a running clock, and the history of past nights with totals.

local Late = CRT.Late
local Groups = CRT.Groups
local UI = CRT.UI

local ROW_H = 22
local LIST_W = 250
local TOTALS = "totals"

local GRAY = { 0.35, 0.35, 0.35 }
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}
-- Monday first on the page. The numbers are date()'s weekdays, where 1 is Sunday.
local DAYS = {
    { wday = 2, label = "Mon" }, { wday = 3, label = "Tue" }, { wday = 4, label = "Wed" },
    { wday = 5, label = "Thu" }, { wday = 6, label = "Fri" }, { wday = 7, label = "Sat" },
    { wday = 1, label = "Sun" },
}
local HOW = { schedule = "from the schedule", button = "by Start raid now" }
local ENDED = {
    disband = "the group disbanded",
    button = "End raid was pressed",
    timeout = "it ran 8 hours",
    offline = "you logged in after the group had gone",
}

local page, tonightText, tonightChild, detailText, detailChild, listChild, statusText
local startButton, endButton, layoutButton, deleteButton
local rows, controls = {}, {}
local selected = TOTALS
local refresh

local function skin(frame, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, alpha or 0.5)
    frame:SetBackdropBorderColor(GRAY[1], GRAY[2], GRAY[3], 1)
end

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 24)
    b:SetText(label)
    return b
end

local function tooltip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Text -------------------------------------------------------------------

local function clock(t)
    return date("%H:%M", t)
end

local function day(t)
    return date("%a %d %b", t)
end

local function minutes(seconds)
    local m = math.floor(seconds / 60 + 0.5)
    if m >= 60 then
        return format("%d h %02d min", math.floor(m / 60), m % 60)
    end
    return m .. " min"
end

local function running(seconds)
    seconds = math.floor(seconds)
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then
        return format("%d:%02d:%02d", h, m, s)
    end
    return format("%d:%02d", m, s)
end

local function name(key)
    local r, g, b = Groups.ClassColor(key)
    return format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), Groups.Display(key))
end

local function sortedPlayers(night, now)
    local list = {}
    for _, p in ipairs(night.players) do
        list[#list + 1] = p
    end
    table.sort(list, function(a, b)
        local sa, sb = Late.Seconds(night, a, now), Late.Seconds(night, b, now)
        if sa ~= sb then
            return sa > sb
        end
        return a.key:lower() < b.key:lower()
    end)
    return list
end

local function onTimeLine(names)
    if #names == 0 then
        return nil
    end
    return "|cff80ff80On time (" .. #names .. "):|r " .. table.concat(names, ", ")
end

local function tonightLines(night, now)
    local lines = {
        format("Started %s %s, expected roster \"%s\". Running %s.", clock(night.startedAt), HOW[night.how] or "", night.layout or "?", running(now - night.startedAt)),
    }
    if (night.grace or 0) > 0 then
        lines[#lines + 1] = "Grace: " .. night.grace .. " min."
    end
    local missing, late, onTime = {}, {}, {}
    for _, p in ipairs(sortedPlayers(night, now)) do
        if not p.joinedAt then
            missing[#missing + 1] = format("  %s  |cffff6060%s|r", name(p.key), running(Late.Seconds(night, p, now)))
        elseif Late.IsLate(night, p) then
            late[#late + 1] = format("  %s  joined %s, %s late", name(p.key), clock(p.joinedAt), minutes(Late.Seconds(night, p)))
        else
            onTime[#onTime + 1] = name(p.key)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffff6060Not here yet (" .. #missing .. "):|r"
    for _, l in ipairs(missing) do
        lines[#lines + 1] = l
    end
    if #late > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffffd100Arrived late (" .. #late .. "):|r"
        for _, l in ipairs(late) do
            lines[#lines + 1] = l
        end
    end
    local ok = onTimeLine(onTime)
    if ok then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ok
    end
    return table.concat(lines, "\n")
end

local function nightLines(night)
    local lines = {
        format("%s, started %s %s.", day(night.startedAt), clock(night.startedAt), HOW[night.how] or ""),
        format("Expected roster \"%s\". Ended %s, when %s.", night.layout or "?", clock(night.endedAt), ENDED[night.endReason] or "it ended"),
    }
    if (night.grace or 0) > 0 then
        lines[#lines + 1] = "Grace: " .. night.grace .. " min."
    end
    local late, onTime = {}, {}
    for _, p in ipairs(sortedPlayers(night)) do
        if Late.IsLate(night, p) then
            if p.never then
                late[#late + 1] = format("  %s  |cffff6060no-show|r, %s until the end", name(p.key), minutes(Late.Seconds(night, p)))
            else
                late[#late + 1] = format("  %s  joined %s, %s late", name(p.key), clock(p.joinedAt), minutes(Late.Seconds(night, p)))
            end
        else
            onTime[#onTime + 1] = name(p.key)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd100Late (" .. #late .. "):|r"
    for _, l in ipairs(late) do
        lines[#lines + 1] = l
    end
    if #late == 0 then
        lines[#lines + 1] = "  Nobody. Everyone was on time."
    end
    local ok = onTimeLine(onTime)
    if ok then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ok
    end
    return table.concat(lines, "\n")
end

local function setText(fs, child, s)
    fs:SetText(s)
    child:SetHeight(fs:GetStringHeight() + 8)
end

-- Discord export ----------------------------------------------------------------------------
-- Plain text for pasting into Discord: a bold title, then a code block so the columns line up in
-- Discord's fixed-width font. No color codes and no pipe characters, which the game's text box treats
-- as escape codes. Discord's message limit is 2000 characters, so a full 40-player list may need two
-- pastes.

local function pad(s, width)
    s = tostring(s)
    if #s >= width then
        return s:sub(1, width - 1) .. " "
    end
    return s .. string.rep(" ", width - #s)
end

local function plain(key)
    return Groups.Display(key)
end

local function totalsExport()
    local history = Late:History()
    if #history == 0 then
        return "No finished raid nights yet."
    end
    local first, last = history[1].startedAt, history[1].startedAt
    for _, night in ipairs(history) do
        first, last = math.min(first, night.startedAt), math.max(last, night.startedAt)
    end
    local lines = {
        format("**Late tracker totals**: %d nights, %s to %s", #history, day(first), day(last)),
        "```",
        pad("Player", 26) .. pad("Late", 9) .. pad("Time late", 13) .. "No-Show",
    }
    for _, t in ipairs(Late:Totals()) do
        lines[#lines + 1] = pad(plain(t.key), 26) .. pad(t.late .. " of " .. t.nights, 9) .. pad(t.late > 0 and minutes(t.seconds) or "-", 13) .. (t.never > 0 and t.never or "-")
    end
    lines[#lines + 1] = "```"
    return table.concat(lines, "\n")
end

local function nightExport(night)
    local lines = {
        format("**Raid night %s**, start %s, roster \"%s\", ended %s when %s", day(night.startedAt), clock(night.startedAt), night.layout or "?", clock(night.endedAt), ENDED[night.endReason] or "it ended"),
    }
    local late, onTime = {}, {}
    for _, p in ipairs(sortedPlayers(night)) do
        if Late.IsLate(night, p) then
            late[#late + 1] = p
        else
            onTime[#onTime + 1] = plain(p.key)
        end
    end
    if #late > 0 then
        lines[#lines + 1] = "```"
        lines[#lines + 1] = pad("Player", 26) .. pad("Joined", 10) .. "Late"
        for _, p in ipairs(late) do
            lines[#lines + 1] = pad(plain(p.key), 26) .. pad(p.never and "no-show" or clock(p.joinedAt), 10) .. minutes(Late.Seconds(night, p))
        end
        lines[#lines + 1] = "```"
    else
        lines[#lines + 1] = "Nobody was late."
    end
    if #onTime > 0 then
        lines[#lines + 1] = "On time: " .. table.concat(onTime, ", ")
    end
    return table.concat(lines, "\n")
end

-- Opens the copy window with what is selected in History: the totals or one night.
local function export()
    local text, title
    if selected == TOTALS then
        text, title = totalsExport(), "Late tracker totals for Discord (Ctrl+C to copy)"
    else
        local night = Late:Find(selected)
        if not night then
            return
        end
        text, title = nightExport(night), "Raid night for Discord (Ctrl+C to copy)"
    end
    CRT.ConsumablesTools:ShowText(title, text)
end

-- Totals table rows: four text columns per row, made as needed under the intro line.
local TOTAL_ROW_H = 18
local totalRows = {}

local function totalRow(i)
    local row = totalRows[i]
    if row then
        return row
    end
    row = {}
    for _, key in ipairs({ "name", "late", "time", "never" }) do
        local fs = detailChild:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        fs:SetWordWrap(false)
        row[key] = fs
    end
    totalRows[i] = row
    return row
end

local function hideTotals()
    for _, row in pairs(totalRows) do
        for _, fs in pairs(row) do
            fs:Hide()
        end
    end
end

local function place(fs, x, y, width, justify, text)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    fs:SetText(text)
    fs:Show()
end

-- The totals as a table: player, nights late out of nights expected, total time late, and nights
-- they never joined (no-shows), or a line saying there are no nights yet.
local function showTotals()
    hideTotals()
    local history = Late:History()
    if #history == 0 then
        setText(detailText, detailChild, "No finished raid nights yet. Each night is added here when it ends.")
        return
    end
    setText(detailText, detailChild, format("All %d saved nights, most often late first.", #history))
    local w = detailChild:GetWidth()
    if not w or w < 200 then
        w = 370
    end
    local list = Late:Totals()
    for i = 0, #list do
        local row = totalRow(i + 1)
        local y = -24 - i * TOTAL_ROW_H
        if i == 0 then
            place(row.name, 2, y, w - 214, "LEFT", "|cff999999Player|r")
            place(row.late, w - 208, y, 64, "RIGHT", "|cff999999Late|r")
            place(row.time, w - 140, y, 84, "RIGHT", "|cff999999Time late|r")
            place(row.never, w - 62, y, 60, "RIGHT", "|cff999999No-Show|r")
        else
            local t = list[i]
            place(row.name, 2, y, w - 214, "LEFT", name(t.key))
            place(row.late, w - 208, y, 64, "RIGHT", t.late .. " of " .. t.nights)
            place(row.time, w - 140, y, 84, "RIGHT", t.late > 0 and minutes(t.seconds) or "-")
            place(row.never, w - 62, y, 60, "RIGHT", t.never > 0 and ("|cffff6060" .. t.never .. "|r") or "-")
        end
    end
    detailChild:SetHeight(24 + (#list + 1) * TOTAL_ROW_H + 8)
end

-- Scrolling text boxes ---------------------------------------------------

local function textBox(pf, scrollName)
    local box = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    skin(box, 0.4)
    local scroll = CreateFrame("ScrollFrame", scrollName, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local text = child:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("TOPLEFT", 2, -2)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    scroll:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w)
        text:SetWidth(w - 6)
    end)
    return box, text, child
end

-- Settings controls ------------------------------------------------------

local function makeNumber(pf, anchor, x, letters, getter, setter, low, high)
    local edit = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontHighlight)
    edit:SetNumeric(true)
    edit:SetMaxLetters(letters)
    edit:SetSize(letters * 12 + 14, 20)
    edit:SetPoint("LEFT", anchor, "RIGHT", x, 0)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(getter()))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then
            setter(math.max(low, math.min(high, math.floor(value))))
        end
        self.refresh()
    end)
    edit.refresh = function()
        if not edit:HasFocus() then
            local value = getter()
            edit:SetText(letters == 2 and format("%02d", value) or tostring(value))
        end
    end
    controls[#controls + 1] = edit
    return edit
end

local function label(pf, text, font)
    local fs = pf:CreateFontString(nil, "OVERLAY", font or "CRTFontNormal")
    fs:SetText(text)
    return fs
end

-- Steps the expected roster through the saved layouts, forward on a left click, back on a right click.
local function stepLayout(dir)
    local presets = Groups:Presets()
    if #presets == 0 then
        CRT:Print("Save a layout on the Raid Groups page first, then pick it here.")
        return
    end
    local current = Late:Settings().layoutId
    local index = 0
    for i, p in ipairs(presets) do
        if p.id == current then
            index = i
        end
    end
    index = ((index - 1 + dir) % #presets) + 1
    Late:Set("layoutId", presets[index].id)
end

-- History list -----------------------------------------------------------

local function getRow(i)
    local row = rows[i]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, listChild)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.18)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.08)
    row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        selected = self.value
        refresh()
    end)
    rows[i] = row
    return row
end

local function refreshList()
    local history = Late:History()
    if selected ~= TOTALS and not Late:Find(selected) then
        selected = TOTALS
    end
    local entries = { { value = TOTALS, text = "|cffffd100Totals (all nights)|r" } }
    for i = #history, 1, -1 do
        local night = history[i]
        local count = 0
        for _, p in ipairs(night.players) do
            if Late.IsLate(night, p) then
                count = count + 1
            end
        end
        entries[#entries + 1] = { value = night.id, text = format("%s %s  (%d late)", day(night.startedAt), clock(night.startedAt), count) }
    end
    for i, entry in ipairs(entries) do
        local row = getRow(i)
        row.value = entry.value
        row.text:SetText(entry.text)
        row.sel:SetShown(entry.value == selected)
        row:Show()
    end
    for i = #entries + 1, #rows do
        rows[i]:Hide()
    end
    listChild:SetHeight(#entries * ROW_H)
end

-- Refresh ----------------------------------------------------------------

local function refreshTonight()
    local night = Late:Current()
    local now = time()
    if night then
        setText(tonightText, tonightChild, tonightLines(night, now))
        startButton:SetText("Restart from now")
        endButton:Enable()
    else
        local nextStart = Late:NextScheduled(now)
        local s = "No raid night is running."
        if nextStart then
            s = s .. format(" Next scheduled start: %s %s.", day(nextStart), clock(nextStart))
        else
            s = s .. " No raid days are ticked, so only Start raid now starts one."
        end
        setText(tonightText, tonightChild, s)
        startButton:SetText("Start raid now")
        endButton:Disable()
    end
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
    local preset = Late:Settings().layoutId and Groups:Find(Late:Settings().layoutId)
    layoutButton:SetText("Expected roster: " .. (preset and preset.name or "|cffff6060none picked|r"))
    refreshTonight()
    refreshList()
    if selected == TOTALS then
        showTotals()
        deleteButton:Hide()
    else
        hideTotals()
        setText(detailText, detailChild, nightLines(Late:Find(selected)))
        deleteButton:Show()
    end
end

-- Build ------------------------------------------------------------------

local function build(pf)
    page = pf

    local title = label(pf, "Late Tracker", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)

    local hint = label(pf, "Tick your raid days and start time, and pick the Raid Groups layout of who should be there. At the start time, anyone in that layout who is not in your group is late, and their clock runs until they join, or until the group disbands. Start raid now starts a night by hand when invites go out off schedule.", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -32)
    hint:SetWidth(670)
    hint:SetJustifyH("LEFT")

    -- Raid days.
    local daysLabel = label(pf, "Raid days")
    daysLabel:SetPoint("TOPLEFT", 8, -84)
    for i, d in ipairs(DAYS) do
        local check = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", 110 + (i - 1) * 64, -79)
        local text = label(pf, d.label, "CRTFontSmall")
        text:SetPoint("LEFT", check, "RIGHT", 0, 0)
        check:SetScript("OnClick", function(self)
            Late:SetDay(d.wday, self:GetChecked() and true or false)
        end)
        check.refresh = function()
            check:SetChecked(Late:Settings().days[d.wday] and true or false)
        end
        controls[#controls + 1] = check
    end

    -- Start time and grace.
    local timeLabel = label(pf, "Start time")
    timeLabel:SetPoint("TOPLEFT", 8, -110)
    local hour = makeNumber(pf, timeLabel, 18, 2, function()
        return Late:Settings().hour
    end, function(v)
        Late:Set("hour", v)
    end, 0, 23)
    local colon = label(pf, ":")
    colon:SetPoint("LEFT", hour, "RIGHT", 2, 0)
    local minute = makeNumber(pf, colon, 8, 2, function()
        return Late:Settings().minute
    end, function(v)
        Late:Set("minute", v)
    end, 0, 59)
    local clockNote = label(pf, "24-hour, this computer's clock", "CRTFontDisableSmall")
    clockNote:SetPoint("LEFT", minute, "RIGHT", 8, 0)
    -- The start time is only used by the schedule, so it greys out while no raid day is ticked.
    -- Start raid now does not need it.
    controls[#controls + 1] = {
        refresh = function()
            local on = next(Late:Settings().days) ~= nil
            local c = on and 1 or 0.5
            for _, edit in ipairs({ hour, minute }) do
                edit:SetEnabled(on)
                edit:SetTextColor(c, c, c)
            end
            if on then
                timeLabel:SetTextColor(1, 0.82, 0)
                colon:SetTextColor(1, 0.82, 0)
            else
                timeLabel:SetTextColor(0.5, 0.5, 0.5)
                colon:SetTextColor(0.5, 0.5, 0.5)
            end
        end,
    }
    local graceLabel = label(pf, "Grace minutes")
    graceLabel:SetPoint("TOPLEFT", 440, -110)
    makeNumber(pf, graceLabel, 12, 2, function()
        return Late:Settings().grace
    end, function(v)
        Late:Set("grace", v)
    end, 0, 60)

    -- Expected roster, start and end.
    layoutButton = makeButton(pf, "Expected roster", 360)
    layoutButton:SetPoint("TOPLEFT", 8, -134)
    layoutButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    layoutButton:SetScript("OnClick", function(_, button)
        stepLayout(button == "RightButton" and -1 or 1)
    end)
    tooltip(layoutButton, "Expected roster", "Click for the next saved Raid Groups layout, right-click for the previous one. Everyone in it is expected. A night already running keeps the roster it started with.")

    startButton = makeButton(pf, "Start raid now", 170)
    startButton:SetPoint("LEFT", layoutButton, "RIGHT", 8, 0)
    startButton:SetScript("OnClick", function()
        local restarting = Late:Current() ~= nil
        if Late:Start("button", time()) then
            CRT:Print(restarting and "Raid night restarted from now." or "Raid night started.")
        end
    end)
    tooltip(startButton, "Start raid now", "Starts tonight's clock now, for when invites go out. On a raid day it replaces the scheduled start. While a night is running, it restarts it from now and the running night is not saved.")

    endButton = makeButton(pf, "End raid", 130)
    endButton:SetPoint("LEFT", startButton, "RIGHT", 8, 0)
    endButton:SetScript("OnClick", function()
        Late:End("button", time())
    end)
    tooltip(endButton, "End raid", "Ends tonight and saves it to the history. Anyone who never joined is recorded with the time until now. A disbanded group ends the night on its own.")

    -- Tonight.
    local tonightLabel = label(pf, "Tonight")
    tonightLabel:SetPoint("TOPLEFT", 8, -166)
    local tonightBox
    tonightBox, tonightText, tonightChild = textBox(pf, "CowfeeRaidToolsLateTonightScroll")
    tonightBox:SetPoint("TOPLEFT", 8, -186)
    tonightBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, -186)
    tonightBox:SetHeight(220)

    -- History: the list of nights on the left, the selected night or the totals on the right.
    local historyLabel = label(pf, "History")
    historyLabel:SetPoint("TOPLEFT", 8, -414)
    local listBox = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", 8, -434)
    listBox:SetPoint("BOTTOMLEFT", 8, 8)
    listBox:SetWidth(LIST_W)
    skin(listBox, 0.4)
    local listScroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsLateListScroll", listBox, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", -26, 4)
    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(LIST_W - 32, 1)
    listScroll:SetScrollChild(listChild)

    local detailBox
    detailBox, detailText, detailChild = textBox(pf, "CowfeeRaidToolsLateDetailScroll")
    detailBox:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 8, 0)
    detailBox:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, 38)

    local exportButton = makeButton(pf, "Export for Discord", 190)
    exportButton:SetPoint("BOTTOMLEFT", detailBox, "BOTTOMLEFT", 0, -30)
    exportButton:SetScript("OnClick", export)
    tooltip(exportButton, "Export for Discord", "Opens a window with the selected totals or night as text, already selected. Press Ctrl+C, then paste it into Discord. The columns line up in Discord's code block.")

    deleteButton = makeButton(pf, "Delete this night", 190)
    deleteButton:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, 8)
    local armToken = 0
    deleteButton:SetScript("OnClick", function(self)
        if selected == TOTALS then
            return
        end
        if not self.armed then
            self.armed = true
            armToken = armToken + 1
            local token = armToken
            self:SetText("Click again to delete")
            C_Timer.After(3, function()
                if token == armToken then
                    self.armed = false
                    self:SetText("Delete this night")
                end
            end)
            return
        end
        armToken = armToken + 1
        self.armed = false
        self:SetText("Delete this night")
        Late:Delete(selected)
    end)

    -- The running clocks update once a second while the page is open.
    local elapsed = 0
    pf:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            if Late:Current() then
                refreshTonight()
            end
        end
    end)
    pf:SetScript("OnShow", refresh)
    Late:OnChange(refresh)
    Groups:OnChange(refresh)
end

UI:RegisterPage("late", "Late Tracker", build)

-- For /crt late export: the totals, ready to paste into Discord.
CRT.LatePage = {
    ExportTotals = function()
        CRT.ConsumablesTools:ShowText("Late tracker totals for Discord (Ctrl+C to copy)", totalsExport())
    end,
}
