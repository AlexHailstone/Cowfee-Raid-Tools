local ADDON, CRT = ...

-- The Tattlebot page, with three tabs: Tonight (tonight's pulls and totals, with Post and End night),
-- History (past nights with totals, Post and the Discord export) and Settings (tracking, avoidable
-- damage and where posts go).

local Tattle = CRT.Tattle
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
local OUTPUTS = { { key = "self", label = "Only me" }, { key = "raid", label = "Raid chat" }, { key = "officer", label = "Officer chat" } }
local ENDED = { button = "End night was pressed", gap = "no pull came for 6 hours" }

local page, tonightText, tonightChild, detailText, detailChild, listChild
local endButton, postPullButton, postNightButton, deleteButton, postSelectedButton
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
    b:SetNormalFontObject(CRTFontStandard)
    b:SetHighlightFontObject(CRTFontStandardHighlight)
    b:SetDisabledFontObject(CRTFontStandardDisable)
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

local function label(pf, text, font)
    local fs = pf:CreateFontString(nil, "OVERLAY", font or "CRTFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Text -------------------------------------------------------------------

local function clock(t)
    return date("%H:%M", t)
end

local function day(t)
    return date("%a %d %b", t)
end

local function duration(seconds)
    if not seconds then
        return nil
    end
    return format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function name(key, class)
    local r, g, b = Groups.ClassColor(key, class)
    return format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), Groups.Display(key))
end

local function difficulty(id)
    if not id or not GetDifficultyInfo then
        return nil
    end
    local ok, n = pcall(GetDifficultyInfo, id)
    return ok and n or nil
end

local function trackingWarning()
    if Tattle.ListSize() == 0 and not Tattle:Settings().avoidable then
        return "|cffff6060The spell list is empty and avoidable damage is off, so nothing is tracked yet.|r"
    end
end

-- The per-player totals for a set of nights, as text lines.
local function summaryLines(nights, lines)
    local rowsOut, pulls = Tattle.Summary(nights)
    if #rowsOut == 0 then
        lines[#lines + 1] = "  Nobody took damage from a tracked mechanic."
        return
    end
    for _, row in ipairs(rowsOut) do
        lines[#lines + 1] = format("  %s  |cffff8060%s|r, hit in %d of %d pulls", name(row.key, row.class), Tattle.Short(row.damage), row.hits, pulls)
        for _, spell in ipairs(Tattle.SortedSpells(row.spells)) do
            lines[#lines + 1] = format("      |cffbbbbbb%s  %s  (%d %s)|r", Tattle.SpellName(spell.id), Tattle.Short(spell.damage), spell.hits, spell.hits == 1 and "pull" or "pulls")
        end
    end
end

-- One pull as one heading line and one line of who took the most.
local function pullLines(pull, index, lines)
    local bits = { clock(pull.at) .. "  " .. Tattle.PullTitle(pull, index) }
    local extra = {}
    local diff = difficulty(pull.difficulty)
    if diff then
        extra[#extra + 1] = diff
    end
    if pull.duration then
        extra[#extra + 1] = duration(pull.duration)
    end
    if #extra > 0 then
        bits[1] = bits[1] .. " (" .. table.concat(extra, ", ") .. ")"
    end
    lines[#lines + 1] = "  |cffffd100" .. bits[1] .. "|r"
    local players = {}
    for key, p in pairs(pull.players) do
        players[#players + 1] = { key = key, class = p.class, damage = Tattle.PullDamage(p) }
    end
    table.sort(players, function(a, b)
        if a.damage ~= b.damage then
            return a.damage > b.damage
        end
        return a.key:lower() < b.key:lower()
    end)
    if #players == 0 then
        lines[#lines + 1] = "      Nobody was hit."
        return
    end
    local parts = {}
    for _, e in ipairs(players) do
        parts[#parts + 1] = name(e.key, e.class) .. " " .. Tattle.Short(e.damage)
    end
    lines[#lines + 1] = "      " .. table.concat(parts, ", ")
end

local function tonightLines(night)
    local lines = {}
    local warn = trackingWarning()
    if warn then
        lines[#lines + 1] = warn
        lines[#lines + 1] = ""
    end
    if not night then
        lines[#lines + 1] = "No boss pull recorded tonight. After each boss pull, once you are out of combat, Tattlebot reads the game's damage meter."
        local why = Tattle.Unavailable()
        if why then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cffff6060" .. why .. "|r"
        end
        return table.concat(lines, "\n")
    end
    lines[#lines + 1] = format("Started %s %s, %d %s so far.", day(night.startedAt), clock(night.startedAt), #night.pulls, #night.pulls == 1 and "pull" or "pulls")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd100Tonight's totals|r"
    summaryLines({ night }, lines)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd100Pulls, newest first|r"
    for i = #night.pulls, 1, -1 do
        pullLines(night.pulls[i], i, lines)
    end
    return table.concat(lines, "\n")
end

local function nightLines(night)
    local lines = {
        format("%s, %s to %s, %d pulls. Ended when %s.", day(night.startedAt), clock(night.startedAt), clock(night.endedAt), #night.pulls, ENDED[night.endReason] or "it ended"),
        "",
        "|cffffd100Totals|r",
    }
    summaryLines({ night }, lines)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd100Pulls|r"
    for i, pull in ipairs(night.pulls) do
        pullLines(pull, i, lines)
    end
    return table.concat(lines, "\n")
end

local function totalsLines()
    local history = Tattle:History()
    if #history == 0 then
        return "No finished nights yet. Each night is added here when it ends."
    end
    local lines = { format("All %d saved nights, most damage first.", #history), "" }
    summaryLines(history, lines)
    return table.concat(lines, "\n")
end

local function setText(fs, child, s)
    fs:SetText(s)
    child:SetHeight(fs:GetStringHeight() + 8)
end

-- Discord export ----------------------------------------------------------------------------
-- A bold title and a code block so the columns line up in Discord's fixed-width font. No color
-- codes and no pipe characters, which the game's text box treats as escape codes.

local function pad(s, width)
    s = tostring(s)
    if #s >= width then
        return s:sub(1, width - 1) .. " "
    end
    return s .. string.rep(" ", width - #s)
end

local function summaryExport(title, nights)
    local rowsOut, pulls = Tattle.Summary(nights)
    local lines = { title }
    if #rowsOut == 0 then
        lines[#lines + 1] = "Nobody took damage from a tracked mechanic."
        return table.concat(lines, "\n")
    end
    lines[#lines + 1] = "```"
    lines[#lines + 1] = pad("Player", 24) .. pad("Damage", 10) .. "Pulls hit"
    for _, row in ipairs(rowsOut) do
        lines[#lines + 1] = pad(Groups.Display(row.key), 24) .. pad(Tattle.Short(row.damage), 10) .. row.hits .. " of " .. pulls
        for _, spell in ipairs(Tattle.SortedSpells(row.spells)) do
            lines[#lines + 1] = pad("  " .. Tattle.SpellName(spell.id), 24) .. pad(Tattle.Short(spell.damage), 10) .. spell.hits
        end
    end
    lines[#lines + 1] = "```"
    return table.concat(lines, "\n")
end

local function totalsExport()
    local history = Tattle:History()
    if #history == 0 then
        return "No finished nights yet."
    end
    local first, last = history[1].startedAt, history[1].startedAt
    for _, night in ipairs(history) do
        first, last = math.min(first, night.startedAt), math.max(last, night.startedAt)
    end
    return summaryExport(format("**Tattlebot totals**: %d nights, %s to %s", #history, day(first), day(last)), history)
end

local function nightExport(night)
    return summaryExport(format("**Tattlebot, %s**: %d pulls", day(night.startedAt), #night.pulls), { night })
end

local function export()
    local text, title
    if selected == TOTALS then
        text, title = totalsExport(), "Tattlebot totals for Discord (Ctrl+C to copy)"
    else
        local night = Tattle:Find(selected)
        if not night then
            return
        end
        text, title = nightExport(night), "Tattlebot night for Discord (Ctrl+C to copy)"
    end
    CRT.ConsumablesTools:ShowText(title, text)
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
    local history = Tattle:History()
    if selected ~= TOTALS and not Tattle:Find(selected) then
        selected = TOTALS
    end
    local entries = { { value = TOTALS, text = "|cffffd100Totals (all nights)|r" } }
    for i = #history, 1, -1 do
        local night = history[i]
        entries[#entries + 1] = { value = night.id, text = format("%s %s  (%d pulls)", day(night.startedAt), clock(night.startedAt), #night.pulls) }
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

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
    local night = Tattle:Current()
    setText(tonightText, tonightChild, tonightLines(night))
    local hasPulls = night and #night.pulls > 0
    endButton:SetEnabled(night ~= nil)
    postPullButton:SetEnabled(hasPulls and true or false)
    postNightButton:SetEnabled(hasPulls and true or false)
    refreshList()
    if selected == TOTALS then
        setText(detailText, detailChild, totalsLines())
        deleteButton:Hide()
        postSelectedButton:Hide()
    else
        setText(detailText, detailChild, nightLines(Tattle:Find(selected)))
        deleteButton:Show()
        postSelectedButton:Show()
    end
end

-- Build ------------------------------------------------------------------

local TABS = {
    { key = "tonight", label = "Tonight" },
    { key = "history", label = "History" },
    { key = "settings", label = "Settings" },
}
local tabButtons, tabFrames = {}, {}
local currentTab = "tonight"

local function selectTab(key)
    if not tabFrames[key] then
        key = "tonight"
    end
    currentTab = key
    for _, tab in ipairs(TABS) do
        local on = tab.key == key
        tabFrames[tab.key]:SetShown(on)
        tabButtons[tab.key].sel:SetShown(on)
        tabButtons[tab.key].text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
    end
end

local function buildTonight(f)
    postPullButton = makeButton(f, "Post last pull", 140)
    postPullButton:SetPoint("TOPLEFT", 8, -8)
    postPullButton:SetScript("OnClick", function()
        Tattle:PostLastPull()
    end)
    tooltip(postPullButton, "Post last pull", "Posts who took damage from the tracked mechanics in the last pull, to the channel picked on the Settings tab.")

    postNightButton = makeButton(f, "Post tonight", 120)
    postNightButton:SetPoint("LEFT", postPullButton, "RIGHT", 4, 0)
    postNightButton:SetScript("OnClick", function()
        Tattle:PostNight()
    end)
    tooltip(postNightButton, "Post tonight", "Posts tonight's totals so far: each player's damage from the tracked mechanics and how many pulls they were hit in, to the channel picked on the Settings tab.")

    endButton = makeButton(f, "End night", 100)
    endButton:SetPoint("LEFT", postNightButton, "RIGHT", 4, 0)
    endButton:SetScript("OnClick", function()
        Tattle:EndNight("button")
    end)
    tooltip(endButton, "End night", "Ends tonight and saves it to the history. A night also ends on its own when no boss pull comes for 6 hours.")

    local tonightBox
    tonightBox, tonightText, tonightChild = textBox(f, "CowfeeRaidToolsTattleTonightScroll")
    tonightBox:SetPoint("TOPLEFT", 8, -40)
    tonightBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
end

local function buildHistory(f)
    local listBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", 8, -8)
    listBox:SetPoint("BOTTOMLEFT", 8, 8)
    listBox:SetWidth(LIST_W)
    skin(listBox, 0.4)
    local listScroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTattleListScroll", listBox, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", -26, 4)
    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(LIST_W - 32, 1)
    listScroll:SetScrollChild(listChild)

    local detailBox
    detailBox, detailText, detailChild = textBox(f, "CowfeeRaidToolsTattleDetailScroll")
    detailBox:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 8, 0)
    detailBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 38)

    local exportButton = makeButton(f, "Export for Discord", 160)
    exportButton:SetPoint("BOTTOMLEFT", detailBox, "BOTTOMLEFT", 0, -30)
    exportButton:SetScript("OnClick", export)
    tooltip(exportButton, "Export for Discord", "Opens a window with the selected totals or night as text, already selected. Press Ctrl+C, then paste it into Discord. The columns line up in Discord's code block.")

    postSelectedButton = makeButton(f, "Post this night", 140)
    postSelectedButton:SetPoint("LEFT", exportButton, "RIGHT", 4, 0)
    postSelectedButton:SetScript("OnClick", function()
        local night = Tattle:Find(selected)
        if night then
            Tattle:PostNight(night)
        end
    end)
    tooltip(postSelectedButton, "Post this night", "Posts this night's totals to the channel picked on the Settings tab.")

    deleteButton = makeButton(f, "Delete this night", 160)
    deleteButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
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
        Tattle:Delete(selected)
    end)
end

-- A check box for one field of CRTDB.tattle. enabledIf greys it out while the setting it depends on
-- is off.
local function makeCheck(f, x, y, text, field, enabledIf)
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    local fs = label(f, text, "CRTFontSmall")
    fs:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check:SetScript("OnClick", function(self)
        Tattle:Set(field, self:GetChecked() and true or false)
    end)
    check.refresh = function()
        check:SetChecked(Tattle:Settings()[field] and true or false)
        if enabledIf then
            local on = enabledIf() and true or false
            check:SetEnabled(on)
            local c = on and 1 or 0.5
            fs:SetTextColor(c, c, c)
        end
    end
    check.label = fs
    controls[#controls + 1] = check
    return check
end

local function buildSettings(f)
    local function trackingOn()
        return Tattle:Settings().enabled
    end

    makeCheck(f, 4, -8, "Read the damage meter after each boss pull", "enabled")
    makeCheck(f, 28, -32, "Only in raids", "raidsOnly", trackingOn)
    local avoidable = makeCheck(f, 28, -56, "Also count damage the game marks avoidable", "avoidable", trackingOn)
    UI.Help(f, "Avoidable damage", "Besides the spells in Tattlebot's list, also count every spell the game's own damage meter puts under Avoidable Damage Taken.\n\nThe game decides what is avoidable, and it does not track it in every kind of content."):SetPoint("LEFT", avoidable.label, "RIGHT", 6, 0)
    local autoPost = makeCheck(f, 28, -80, "Post after each pull", "autoPost", trackingOn)
    UI.Help(f, "Post after each pull", "Posts the pull's report right after it is read. It goes to the channel below only if you are the raid leader, so a raid full of this addon posts once. Everyone else sees it only in their own chat."):SetPoint("LEFT", autoPost.label, "RIGHT", 6, 0)

    local postTo = UI.Dropdown(f, "Post to", {
        options = OUTPUTS,
        labelWidth = 120,
        width = 170,
        get = function()
            return Tattle:Settings().output
        end,
        set = function(key)
            Tattle:Set("output", key)
        end,
    })
    postTo:SetPoint("TOPLEFT", 8, -112)
    controls[#controls + 1] = postTo

    local maxPlayers = UI.Slider(f, "Players in a post", {
        min = 3,
        max = 40,
        labelWidth = 120,
        width = 170,
        get = function()
            return Tattle:Settings().maxPlayers
        end,
        set = function(v)
            Tattle:Set("maxPlayers", v)
        end,
    })
    maxPlayers:SetPoint("TOPLEFT", 8, -144)
    controls[#controls + 1] = maxPlayers
    UI.Help(f, "Players in a post", "Chat posts list the players who took the most damage first, up to this many, so a post does not flood the chat. The Discord export always lists everyone."):SetPoint("LEFT", maxPlayers, "RIGHT", 6, 0)

    local list = label(f, "")
    list:SetPoint("TOPLEFT", 8, -188)
    controls[#controls + 1] = {
        refresh = function()
            local n = Tattle.ListSize()
            list:SetText(format("Tracked mechanics: %d %s", n, n == 1 and "spell" or "spells"))
        end,
    }
    UI.Help(f, "The tracked mechanics", "The spells Tattlebot reports on ship with the addon, in Tattlebot/Database.lua.\n\nTo find a spell's ID, do a pull, leave combat and type /crt tattle scan. It lists every spell that damaged the group in the last fight, as lines to paste into that file."):SetPoint("LEFT", list, "RIGHT", 6, 0)
end

local function build(pf)
    page = pf

    local title = label(pf, "Tattlebot", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    UI.Help(pf, "Tattlebot", "After each boss pull, once you are out of combat, Tattlebot reads the game's own damage meter and keeps the damage each player took from the boss mechanics in its list.\n\nThe meter gives damage, not hits, so each player gets the damage per mechanic and the number of pulls it hit them in.\n\nTonight shows tonight's pulls. History keeps every night, with totals and an export for Discord.\n\nNothing can be read during a fight: the game keeps the meter secret until combat ends."):SetPoint("LEFT", title, "RIGHT", 6, 0)

    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, pf, "BackdropTemplate")
        b:SetSize(160, 26)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 164, -36)
        skin(b, 0.4)
        b.sel = b:CreateTexture(nil, "ARTWORK")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        b.text = b:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(tab.label)
        b:SetScript("OnClick", function()
            selectTab(tab.key)
        end)
        tabButtons[tab.key] = b

        local f = CreateFrame("Frame", nil, pf)
        f:SetPoint("TOPLEFT", 0, -66)
        f:SetPoint("BOTTOMRIGHT", 0, 0)
        f:Hide()
        tabFrames[tab.key] = f
    end
    local line = pf:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.35, 0.35, 0.35, 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -62)
    line:SetPoint("TOPRIGHT", -8, -62)

    buildTonight(tabFrames.tonight)
    buildHistory(tabFrames.history)
    buildSettings(tabFrames.settings)

    pf:SetScript("OnShow", function()
        selectTab(currentTab)
        refresh()
    end)
    Tattle:OnChange(refresh)
end

UI:RegisterPage("tattle", "Tattlebot", build)

-- For /crt tattle scan and export.
CRT.TattlePage = {
    Scan = function()
        local text, why = Tattle:ScanText()
        if not text then
            CRT:Print(why)
            return
        end
        CRT.ConsumablesTools:ShowText("Spells that damaged the group in the last fight (Ctrl+C to copy)", text)
    end,
    ExportTotals = function()
        CRT.ConsumablesTools:ShowText("Tattlebot totals for Discord (Ctrl+C to copy)", totalsExport())
    end,
}
