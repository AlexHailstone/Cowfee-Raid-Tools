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
local tonightPane, detailPane -- the text boxes' views, for showView
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
    return format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), Groups.ReportName(key))
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
        return "|cffff6060No spells are tracked yet and avoidable damage is off, so nothing is recorded. Add spells on the Mechanics tab.|r"
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
        local damage = Tattle.PullDamage(p, pull)
        if damage > 0 then
            players[#players + 1] = { key = key, class = p.class, damage = damage }
        end
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

-- Tonight: the intro, the night's mechanics added up over every pull, and the pulls under them.
local function tonightView(night)
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
    lines[#lines + 1] = format("Started %s %s, %d %s so far. |cffffd100Tonight's totals|r, all pulls added up:", day(night.startedAt), clock(night.startedAt), #night.pulls, #night.pulls == 1 and "pull" or "pulls")
    local below = { "|cffffd100Pulls, newest first|r" }
    for i = #night.pulls, 1, -1 do
        pullLines(night.pulls[i], i, below)
    end
    return table.concat(lines, "\n"), Tattle.MechanicBlocks({ night }), table.concat(below, "\n")
end

-- History filters --------------------------------------------------------------------------
-- The Season dropdown picks which nights the list and totals use: every saved night (All seasons,
-- the default) or the current night: tonight's while one is running, otherwise the last one saved.
-- The Mechanic dropdown narrows the totals, the nights and the export to one mechanic, which makes
-- Totals that mechanic's record.

local ALL = "all"
local NIGHT = "night"
local seasonFilter = ALL -- ALL or NIGHT
local mechFilter = ALL -- ALL or a mechanic key

local function filterMech()
    return mechFilter ~= ALL and mechFilter or nil
end

-- Tonight's running night, or else the last saved one, or nil.
local function currentNight()
    local history = Tattle:History()
    return Tattle:Current() or history[#history]
end

local function filteredNights()
    if seasonFilter == NIGHT then
        local night = currentNight()
        return night and { night } or {}
    end
    return Tattle:History()
end

local function seasonText()
    if seasonFilter ~= NIGHT then
        return "all seasons"
    end
    local night = currentNight()
    if night and night == Tattle:Current() then
        return "tonight"
    elseif night then
        return "the last night, " .. day(night.startedAt)
    end
    return "the current night"
end

local function mechText()
    local key = filterMech()
    return key and Tattle.MechanicLabel(Tattle.MechanicByKey(key)) or nil
end

local function nightView(night)
    local mechKey = filterMech()
    local intro = format("%s, %s to %s, %d %s. Ended when %s.", day(night.startedAt), clock(night.startedAt), clock(night.endedAt), #night.pulls, #night.pulls == 1 and "pull" or "pulls", ENDED[night.endReason] or "it ended")
    if mechKey then
        intro = intro .. " |cffffd100" .. mechText() .. "|r only."
    end
    local below
    if not mechKey then
        local lines = { "|cffffd100Pulls|r" }
        for i, pull in ipairs(night.pulls) do
            pullLines(pull, i, lines)
        end
        below = table.concat(lines, "\n")
    end
    return intro, Tattle.MechanicBlocks({ night }, mechKey), below
end

local function totalsView()
    local nights = filteredNights()
    if #nights == 0 then
        if seasonFilter == NIGHT then
            return "No night yet. A night starts with the first boss pull Tattlebot reads."
        end
        return "No finished nights yet. Each night is added here when it ends."
    end
    local mechKey = filterMech()
    local intro
    if mechKey then
        intro = format("|cffffd100%s|r, %s, %d %s.", mechText(), seasonText(), #nights, #nights == 1 and "night" or "nights")
    else
        intro = format("All mechanics, %s, %d %s.", seasonText(), #nights, #nights == 1 and "night" or "nights")
    end
    return intro, Tattle.MechanicBlocks(nights, mechKey)
end

-- Mechanic tables ----------------------------------------------------------------------------
-- A text box shows a view: a line of text, a table with a Mechanic, Player, Pulls hit and Damage
-- column (the mechanic's name only on its first row, a gap between mechanics), and more text below.
-- Damage is added up over every pull, and Pulls hit is how many pulls it hit that player in: the game's meter
-- has no count of single hits.

local TABLE_ROW_H = 18
local TABLE_GAP = 6

local function tableRow(view, i)
    local row = view.rows[i]
    if row then
        return row
    end
    row = {}
    for _, key in ipairs({ "mech", "player", "pulls", "damage" }) do
        local fs = view.child:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        fs:SetWordWrap(false)
        row[key] = fs
    end
    view.rows[i] = row
    return row
end

local function cell(fs, x, y, width, justify, text)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    fs:SetText(text)
    fs:Show()
end

local function showView(view, intro, blocks, below)
    for _, row in pairs(view.rows) do
        for _, fs in pairs(row) do
            fs:Hide()
        end
    end
    view.text:SetText(intro or "")
    local y = -(view.text:GetStringHeight() + 10)
    local w = view.child:GetWidth()
    if not w or w < 300 then
        w = 360
    end
    -- Mechanic, Player, then Pulls hit and Damage right-aligned at the right edge.
    local xMech, wMech = 2, math.floor(w * 0.36)
    local xPlayer, wPlayer = xMech + wMech + 6, math.floor(w * 0.32)
    local wNum = math.floor((w - (xPlayer + wPlayer) - 12) / 2)
    local xPulls = xPlayer + wPlayer + 4
    local xDamage = xPulls + wNum + 4
    local n = 0
    if blocks and #blocks > 0 then
        n = n + 1
        local head = tableRow(view, n)
        cell(head.mech, xMech, y, wMech, "LEFT", "|cff999999Mechanic|r")
        cell(head.player, xPlayer, y, wPlayer, "LEFT", "|cff999999Player|r")
        cell(head.pulls, xPulls, y, wNum, "RIGHT", "|cff999999Pulls hit|r")
        cell(head.damage, xDamage, y, wNum, "RIGHT", "|cff999999Damage|r")
        y = y - TABLE_ROW_H
        for b, block in ipairs(blocks) do
            if b > 1 then
                y = y - TABLE_GAP
            end
            for r, data in ipairs(block.rows) do
                n = n + 1
                local row = tableRow(view, n)
                cell(row.mech, xMech, y, wMech, "LEFT", r == 1 and ("|cffffd100" .. block.name .. "|r") or "")
                cell(row.player, xPlayer, y, wPlayer, "LEFT", name(data.key, data.class))
                cell(row.pulls, xPulls, y, wNum, "RIGHT", tostring(data.hits))
                cell(row.damage, xDamage, y, wNum, "RIGHT", "|cffff8060" .. Tattle.Short(data.damage) .. "|r")
                y = y - TABLE_ROW_H
            end
        end
        y = y - 10
    elseif blocks then
        view.text:SetText((intro or "") .. "\n\nNobody took damage from a tracked mechanic.")
        y = -(view.text:GetStringHeight() + 10)
    end
    view.below:ClearAllPoints()
    view.below:SetPoint("TOPLEFT", 2, y)
    view.below:SetText(below or "")
    view.child:SetHeight(-y + (below and view.below:GetStringHeight() or 0) + 8)
end

-- Discord export ----------------------------------------------------------------------------
-- A bold title and a code block so the columns line up in Discord's fixed-width font. No color
-- codes and no pipe characters, which the game's text box treats as escape codes. It follows the
-- History filters.

local function pad(s, width)
    s = tostring(s)
    if #s >= width then
        return s:sub(1, width - 1) .. " "
    end
    return s .. string.rep(" ", width - #s)
end

local function lpad(s, width)
    s = tostring(s)
    if #s >= width then
        return s
    end
    return string.rep(" ", width - #s) .. s
end

-- The export: Mechanic, Player, Pulls hit and Damage, the mechanic's name only on its first row and
-- a blank line between mechanics, most total damage first. With a mechanic picked, that one only.
local function summaryExport(title, nights)
    local mechKey = filterMech()
    local blocks = Tattle.MechanicBlocks(nights, mechKey)
    if #blocks == 0 then
        return title .. "\n" .. (mechKey and "Nobody took damage from this mechanic." or "Nobody took damage from a tracked mechanic.")
    end
    -- Columns as wide as the longest name in them, within limits.
    local wMech, wPlayer = #"Mechanic", #"Player"
    for _, block in ipairs(blocks) do
        wMech = math.max(wMech, #block.name)
        for _, row in ipairs(block.rows) do
            wPlayer = math.max(wPlayer, #Groups.ReportName(row.key))
        end
    end
    wMech, wPlayer = math.min(wMech, 28) + 2, math.min(wPlayer, 24) + 2
    local lines = { title, "```", pad("Mechanic", wMech) .. pad("Player", wPlayer) .. pad("Pulls hit", 11) .. lpad("Damage", 8) }
    for i, block in ipairs(blocks) do
        if i > 1 then
            lines[#lines + 1] = ""
        end
        for r, row in ipairs(block.rows) do
            lines[#lines + 1] = pad(r == 1 and block.name or "", wMech) .. pad(Groups.ReportName(row.key), wPlayer) .. pad(tostring(row.hits), 11) .. lpad(Tattle.Short(row.damage), 8)
        end
    end
    lines[#lines + 1] = "```"
    return table.concat(lines, "\n")
end

local function totalsExport()
    local nights = filteredNights()
    if #nights == 0 then
        return "No nights yet."
    end
    local first, last = nights[1].startedAt, nights[1].startedAt
    for _, night in ipairs(nights) do
        first, last = math.min(first, night.startedAt), math.max(last, night.startedAt)
    end
    local what = mechText() or "Tattlebot totals"
    if seasonFilter == NIGHT then
        local pulls = #nights[1].pulls
        return summaryExport(format("**%s**, %s: %d %s", what, day(first), pulls, pulls == 1 and "pull" or "pulls"), nights)
    end
    return summaryExport(format("**%s**, all seasons: %d %s, %s to %s", what, #nights, #nights == 1 and "night" or "nights", day(first), day(last)), nights)
end

local function nightExport(night)
    local what = mechText()
    local title = format("**Tattlebot, %s**: %d %s", day(night.startedAt), #night.pulls, #night.pulls == 1 and "pull" or "pulls")
    if what then
        title = title .. ", " .. what
    end
    return summaryExport(title, { night })
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
    -- Text under a mechanic table, placed by showView.
    local below = child:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    below:SetJustifyH("LEFT")
    below:SetJustifyV("TOP")
    scroll:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w)
        text:SetWidth(w - 6)
        below:SetWidth(w - 6)
        if box.onResize then
            box.onResize()
        end
    end)
    box.view = { child = child, text = text, below = below, rows = {} }
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
    -- Current night shows only its totals: the running night is not in the saved list yet.
    local history = seasonFilter == NIGHT and {} or filteredNights()
    local inList = false
    for _, night in ipairs(history) do
        inList = inList or night.id == selected
    end
    if selected ~= TOTALS and not inList then
        selected = TOTALS
    end
    local entries = { { value = TOTALS, text = "|cffffd100Totals (" .. (seasonFilter == NIGHT and "current night" or "all seasons") .. ")|r" } }
    for i = #history, 1, -1 do
        local night = history[i]
        entries[#entries + 1] = { value = night.id, text = format("%s %s  (%d %s)", day(night.startedAt), clock(night.startedAt), #night.pulls, #night.pulls == 1 and "pull" or "pulls") }
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

-- Mechanics list ---------------------------------------------------------
-- The dropdown picks Last fight, a boss from the shipped list, or the player's own spells. Last fight
-- lists every spell that damaged the group in the meter's current session, with a check box each,
-- and Add checked adds them to the player's own spells, for that fight's boss. A boss shows its
-- mechanics with their spell IDs. Own spells can be removed one by one and typed in below the list.

local OWN = "own"
local SCAN = "scan"
local MECH_ROW_H = 22
local shownBoss -- SCAN, "boss:<index>" or OWN, nil until the tab is first shown
local mechChild, addRow, scanBar
local mechRows = {}
local scanResult, scanError -- the last scan, and why the last try failed
local checked = {} -- [spellID] = true for the ticked spells in the Last fight view

-- Reads the meter again. A failed read (in combat) keeps the last good scan and says why.
local function doScan()
    local result, why = Tattle:Scan()
    if result then
        scanResult, scanError = result, nil
        checked = {}
    else
        scanError = why
    end
end

local function bossOptions()
    local out = { { key = SCAN, label = "Last fight: pick spells to track" } }
    for i, boss in ipairs(Tattle.Bosses()) do
        out[#out + 1] = { key = "boss:" .. i, label = boss.boss or ("Boss " .. i) }
    end
    out[#out + 1] = { key = OWN, label = "Your own spells" }
    return out
end

local function currentBoss()
    if shownBoss == OWN or shownBoss == SCAN then
        return shownBoss
    end
    local i = shownBoss and tonumber(shownBoss:match("^boss:(%d+)$"))
    if i and Tattle.Bosses()[i] then
        return shownBoss
    end
    return #Tattle.Bosses() > 0 and "boss:1" or OWN
end

local function idList(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        local spellName = Tattle.SpellName(id)
        parts[#parts + 1] = spellName == ("Spell " .. id) and tostring(id) or (id .. " " .. spellName)
    end
    return table.concat(parts, ", ")
end

-- Where Add checked puts the spells: the scanned fight's boss, or any boss.
local function scanTarget()
    local boss = scanResult and scanResult.boss
    return boss and boss.name or nil
end

-- The Last fight rows: a heading, then { text, check = spellID } for each spell not yet tracked.
local function scanEntries()
    local out = {}
    if not scanResult then
        out[1] = { text = "|cffff6060" .. (scanError or "No fight read yet. Press Rescan after a fight.") .. "|r" }
        return out
    end
    local where = scanTarget()
    out[1] = { text = format("|cffffd100Last fight|r: %s%s", where or "not a boss", scanResult.duration and (", " .. duration(scanResult.duration)) or "") }
    -- Whether spells added now also count on the fight that was scanned.
    local when
    local on = where and ("on " .. where) or "on every boss pull"
    if scanResult.pull then
        when = "Ticked spells are tracked " .. on .. " from this pull on: this pull is filled in too."
    else
        when = "This fight isn't saved as a pull yet. Add checked saves it as one with the ticked spells, and they are tracked " .. on .. " from then on."
    end
    out[2] = { text = "|cffbbbbbb" .. when .. "|r" }
    if scanError then
        out[#out + 1] = { text = "|cffff6060" .. scanError .. " Showing the last fight read.|r" }
    end
    local tracked = Tattle.List()
    for _, sp in ipairs(scanResult.spells) do
        local tags = {}
        if sp.avoidable then
            tags[#tags + 1] = "|cffff9933avoidable|r"
        end
        local mech = tracked[sp.id]
        if mech then
            tags[#tags + 1] = "|cff80ff80tracked as " .. mech.name .. "|r"
        end
        local text = format("%s  |cff999999%d|r   |cffff8060%s|r on %d %s%s", sp.name, sp.id, Tattle.Short(sp.damage),
            sp.players, sp.players == 1 and "player" or "players", #tags > 0 and ("   " .. table.concat(tags, ", ")) or "")
        out[#out + 1] = { text = text, check = sp.id, tracked = mech ~= nil }
    end
    if #scanResult.spells == 0 then
        out[#out + 1] = { text = "|cff999999Nobody in the group took damage in the last fight.|r" }
    end
    return out
end

-- Lines for the list: { text, id } where id is set for an own spell, which gets a Remove button.
local function mechanicEntries()
    local key = currentBoss()
    local out = {}
    if key == SCAN then
        return scanEntries()
    end
    if key == OWN then
        local list = {}
        local index = Tattle.List()
        for id, v in pairs(Tattle:Settings().custom) do
            local name, boss = v, nil
            if type(v) == "table" then
                name, boss = v.name, v.boss
            end
            local label = (type(name) == "string" and name ~= "") and name or Tattle.SpellName(id)
            list[#list + 1] = { id = id, label = label, boss = boss or "", index = index[id] }
        end
        table.sort(list, function(a, b)
            if a.boss:lower() ~= b.boss:lower() then
                return a.boss:lower() < b.boss:lower()
            end
            if a.label:lower() ~= b.label:lower() then
                return a.label:lower() < b.label:lower()
            end
            return a.id < b.id
        end)
        for _, e in ipairs(list) do
            local where = e.boss ~= "" and ("|cffbbbbbb" .. e.boss .. ":|r ") or "|cffbbbbbbAny boss:|r "
            local text = format("%s|cffffd100%s|r   %s", where, e.label, idList({ e.id }))
            -- A spell in the shipped list counts under that list's mechanic instead.
            local tracked = Tattle.List()[e.id]
            if tracked and not tracked.own then
                text = text .. "  |cff999999(already in the shipped list as " .. tracked.name .. ")|r"
            end
            out[#out + 1] = { text = text, id = e.id }
        end
        if #out == 0 then
            out[1] = { text = "|cff999999None yet. Pick Last fight in the dropdown to add spells from a fight, or type a spell ID below.|r" }
        end
        return out
    end
    local boss = Tattle.Bosses()[tonumber(key:match("%d+"))]
    for _, mech in ipairs(boss.mechanics or {}) do
        out[#out + 1] = { text = format("|cffffd100%s|r   %s", mech.name or "?", idList(mech.spells or {})) }
    end
    if #out == 0 then
        out[1] = { text = "|cff999999No mechanics listed for this boss yet.|r" }
    end
    return out
end

local function getMechRow(i)
    local row = mechRows[i]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, mechChild)
    row:SetHeight(MECH_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * MECH_ROW_H)
    row:SetPoint("RIGHT", mechChild, "RIGHT", 0, 0)
    row.remove = makeButton(row, "Remove", 70, 18)
    row.remove:SetPoint("RIGHT", -2, 0)
    row.remove:SetScript("OnClick", function(self)
        if self.id then
            Tattle:RemoveCustom(self.id)
        end
    end)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
        if self.id then
            checked[self.id] = self:GetChecked() and true or nil
            refresh()
        end
    end)
    row.text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.text:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    mechRows[i] = row
    return row
end

local function refreshMechanics()
    if not mechChild then
        return
    end
    local entries = mechanicEntries()
    for i, entry in ipairs(entries) do
        local row = getMechRow(i)
        row.text:SetText(entry.text)
        row.remove.id = entry.id
        row.remove:SetShown(entry.id ~= nil)
        -- Spells already tracked get no check box: they would add nothing.
        local canCheck = entry.check ~= nil and not entry.tracked
        row.check.id = canCheck and entry.check or nil
        row.check:SetShown(canCheck)
        row.check:SetChecked(canCheck and checked[entry.check] or false)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", entry.check and 26 or 4, 0)
        row.text:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
        row:Show()
    end
    for i = #entries + 1, #mechRows do
        mechRows[i]:Hide()
    end
    mechChild:SetHeight(#entries * MECH_ROW_H)
    addRow:SetShown(currentBoss() == OWN)
    scanBar:SetShown(currentBoss() == SCAN)
    if currentBoss() == SCAN then
        local n = 0
        for _ in pairs(checked) do
            n = n + 1
        end
        scanBar.add:SetEnabled(n > 0)
        scanBar.add:SetText(n > 0 and format("Add %d checked", n) or "Add checked")
    end
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
    showView(tonightPane, tonightView(night))
    local hasPulls = night and #night.pulls > 0
    endButton:SetEnabled(night ~= nil)
    postPullButton:SetEnabled(hasPulls and true or false)
    postNightButton:SetEnabled(hasPulls and true or false)
    refreshList()
    refreshMechanics()
    if selected == TOTALS then
        showView(detailPane, totalsView())
        deleteButton:Hide()
        postSelectedButton:Hide()
    else
        showView(detailPane, nightView(Tattle:Find(selected)))
        deleteButton:Show()
        postSelectedButton:Show()
    end
end

-- Build ------------------------------------------------------------------

local TABS = {
    { key = "tonight", label = "Tonight" },
    { key = "history", label = "History" },
    { key = "mechanics", label = "Mechanics" },
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
        UI:SetTabSelected(tabButtons[tab.key], on)
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
    tonightPane = tonightBox.view
    tonightBox.onResize = function()
        refresh()
    end
    tonightBox:SetPoint("TOPLEFT", 8, -40)
    tonightBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
end

local SEASON_OPTIONS = { { key = ALL, label = "All seasons" }, { key = NIGHT, label = "Current night" } }

local function mechOptions()
    local out = { { key = ALL, label = "All mechanics" } }
    for _, o in ipairs(Tattle.MechanicOptions(Tattle:History())) do
        out[#out + 1] = o
    end
    return out
end

local function buildHistory(f)
    local seasonDropdown = UI.Dropdown(f, "Season", {
        options = SEASON_OPTIONS,
        labelWidth = 60,
        width = 190,
        get = function()
            return seasonFilter
        end,
        set = function(key)
            seasonFilter = key
            refresh()
        end,
    })
    seasonDropdown:SetPoint("TOPLEFT", 8, -4)
    controls[#controls + 1] = seasonDropdown
    local mechDropdown = UI.Dropdown(f, "Mechanic", {
        options = mechOptions,
        labelWidth = 76,
        width = 250,
        get = function()
            return mechFilter
        end,
        set = function(key)
            mechFilter = key
            refresh()
        end,
    })
    mechDropdown:SetPoint("LEFT", seasonDropdown, "RIGHT", 16, 0)
    controls[#controls + 1] = mechDropdown
    UI.Help(f, "History filters", "Season picks what is added up: All seasons is every saved night, and Current night is tonight's night while one is running, or the last saved night when none is.\n\nMechanic narrows Totals, each night and the Discord export to one mechanic. Totals then becomes that mechanic's record: each player's damage from it, how many of the pulls on its boss it hit them in, and the average damage in a pull it hit them."):SetPoint("LEFT", mechDropdown, "RIGHT", 6, 0)

    local listBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", 8, -40)
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
    detailPane = detailBox.view
    detailBox.onResize = function()
        refresh()
    end
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

local function editBox(parent, width, letters, numeric)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontEdit)
    edit:SetNumeric(numeric and true or false)
    edit:SetMaxLetters(letters)
    edit:SetSize(width, 20)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return edit
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

    -- The season new nights are filed under. Typing a new name starts a new season.
    local seasonLabel = label(f, "Season", "CRTFontSmall")
    seasonLabel:SetPoint("TOPLEFT", 8, -150)
    seasonLabel:SetWidth(120)
    local season = editBox(f, 200, 40, false)
    season:SetPoint("LEFT", seasonLabel, "RIGHT", 10, 0)
    local function save(self)
        local text = strtrim(self:GetText() or "")
        if text ~= "" and text ~= Tattle:Settings().season then
            Tattle:Set("season", text)
            CRT:Print("Tattlebot: new nights now go under the season \"" .. text .. "\".")
        end
        self:SetText(Tattle:Settings().season)
    end
    season:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    season:SetScript("OnEditFocusLost", save)
    season.refresh = function()
        if not season:HasFocus() then
            season:SetText(Tattle:Settings().season)
        end
    end
    controls[#controls + 1] = season
    UI.Help(f, "Season", "New nights are stored with this season name. Type a new name and press Enter to start a new season, for example at the start of a new raid tier. Earlier seasons stay in the history. A night already running keeps its season."):SetPoint("LEFT", season, "RIGHT", 6, 0)
end

local function buildMechanics(f)
    local bossDropdown = UI.Dropdown(f, "Boss", {
        options = bossOptions,
        labelWidth = 50,
        width = 260,
        get = currentBoss,
        set = function(key)
            shownBoss = key
            if key == SCAN then
                doScan()
            end
            refresh()
        end,
    })
    bossDropdown:SetPoint("TOPLEFT", 8, -8)
    controls[#controls + 1] = bossDropdown
    UI.Help(f, "Tracked mechanics", "Last fight lists every spell that damaged the group in the last fight. Tick the ones to track and press Add checked. They go to Your own spells, for that fight's boss.\n\nA boss shows the mechanics that ship with the addon, in Tattlebot/Database.lua, with their spell IDs.\n\nYour own spells lists the spells you added, and can add one by its spell ID.\n\nAll the spell IDs of one mechanic are added together in the reports, so each mechanic is one line however many IDs it has. /crt tattle scan opens Last fight."):SetPoint("LEFT", bossDropdown, "RIGHT", 6, 0)

    local count = label(f, "", "CRTFontSmall")
    count:SetPoint("TOPRIGHT", -12, -16)
    controls[#controls + 1] = {
        refresh = function()
            local n = Tattle.ListSize()
            count:SetText(format("%d %s tracked in all", n, n == 1 and "spell ID" or "spell IDs"))
        end,
    }

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    skin(box, 0.4)
    box:SetPoint("TOPLEFT", 8, -44)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 44)
    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTattleMechScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    mechChild = CreateFrame("Frame", nil, scroll)
    mechChild:SetSize(1, 1)
    scroll:SetScrollChild(mechChild)
    scroll:SetScript("OnSizeChanged", function(_, w)
        mechChild:SetWidth(w)
    end)

    -- Last fight: an optional mechanic name for the ticked spells, Add checked, Rescan, and the plain
    -- text for the shipped list.
    scanBar = CreateFrame("Frame", nil, f)
    scanBar:SetPoint("BOTTOMLEFT", 8, 8)
    scanBar:SetPoint("BOTTOMRIGHT", -8, 8)
    scanBar:SetHeight(28)
    local mechLabel = label(scanBar, "Mechanic", "CRTFontSmall")
    mechLabel:SetPoint("LEFT", 0, 0)
    local mechEdit = editBox(scanBar, 170, 40, false)
    mechEdit:SetPoint("LEFT", mechLabel, "RIGHT", 10, 0)
    mechEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    scanBar.add = makeButton(scanBar, "Add checked", 130)
    scanBar.add:SetPoint("LEFT", mechEdit, "RIGHT", 8, 0)
    UI.Help(scanBar, "Add checked", "Adds the ticked spells to Your own spells, tied to the boss of the fight, so History counts them against that boss's pulls. Their damage from this fight counts at once: it is filled in on the pull Tattlebot saved for it, or, when it has none (not a boss, or a training dummy), the fight is saved as a pull of its own. They count on every boss pull after. A fight that was not a boss adds them for every boss.\n\nLeave Mechanic empty to use each spell's own name, so spells that share a name become one mechanic. Type a name to put every ticked spell under it."):SetPoint("LEFT", scanBar.add, "RIGHT", 6, 0)
    scanBar.add:SetScript("OnClick", function()
        if not scanResult then
            return
        end
        local ids, names = {}, {}
        local typed = strtrim(mechEdit:GetText() or "")
        for _, sp in ipairs(scanResult.spells) do
            if checked[sp.id] then
                ids[#ids + 1] = sp.id
                names[sp.id] = typed ~= "" and typed or sp.name
            end
        end
        if #ids == 0 then
            return
        end
        local boss = scanResult.boss
        checked = {}
        mechEdit:SetText("")
        mechEdit:ClearFocus()
        Tattle:AddCustomMany(ids, names, boss and boss.name, boss and boss.encounterID)
        local filled
        if scanResult.pull then
            local n = Tattle:Backfill(scanResult.pull, scanResult.players, ids)
            filled = format(", and filled them in on this pull for %d %s", n, n == 1 and "player" or "players")
        else
            -- No saved pull for this fight: save it as one, so the spells show up now. Later adds from
            -- the same scan fill in this pull.
            local pull, n = Tattle:AddScannedPull(scanResult, ids)
            scanResult.pull = pull
            filled = format(", and saved this fight as a pull with %d %s hit", n, n == 1 and "player" or "players")
        end
        CRT:Print(format("Tattlebot now tracks %d more %s%s%s.", #ids, #ids == 1 and "spell" or "spells", boss and boss.name and (" on " .. boss.name) or "", filled))
    end)
    local copy = makeButton(scanBar, "Copy as text", 110)
    copy:SetPoint("RIGHT", 0, 0)
    copy:SetScript("OnClick", function()
        CRT.TattlePage.ScanText()
    end)
    tooltip(copy, "Copy as text", "Opens the last fight's spells as lines for the shipped list in Tattlebot/Database.lua.")
    local rescan = makeButton(scanBar, "Rescan", 80)
    rescan:SetPoint("RIGHT", copy, "LEFT", -4, 0)
    rescan:SetScript("OnClick", function()
        doScan()
        refresh()
    end)
    tooltip(rescan, "Rescan", "Reads the damage meter again, for the fight that just ended. It can't be read during combat.")

    -- Adding an own spell: its ID and, optionally, the mechanic to count it under.
    addRow = CreateFrame("Frame", nil, f)
    addRow:SetPoint("BOTTOMLEFT", 8, 8)
    addRow:SetPoint("BOTTOMRIGHT", -8, 8)
    addRow:SetHeight(28)
    local idLabel = label(addRow, "Spell ID", "CRTFontSmall")
    idLabel:SetPoint("LEFT", 0, 0)
    local idEdit = editBox(addRow, 90, 9, true)
    idEdit:SetPoint("LEFT", idLabel, "RIGHT", 10, 0)
    local nameLabel = label(addRow, "Mechanic", "CRTFontSmall")
    nameLabel:SetPoint("LEFT", idEdit, "RIGHT", 14, 0)
    local nameEdit = editBox(addRow, 200, 40, false)
    nameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
    local addButton = makeButton(addRow, "Add", 70)
    addButton:SetPoint("LEFT", nameEdit, "RIGHT", 8, 0)
    UI.Help(addRow, "Add a spell", "Type the spell ID, and optionally the mechanic it belongs to. Spells with the same mechanic name are added together in the reports. Left empty, the game's spell name is used.\n\nA spell already in the shipped list counts under that list's mechanic."):SetPoint("LEFT", addButton, "RIGHT", 6, 0)
    local function add()
        local id = tonumber(idEdit:GetText())
        if not id or id <= 0 then
            CRT:Print("Type a spell ID first.")
            return
        end
        id = math.floor(id)
        local name = strtrim(nameEdit:GetText() or "")
        Tattle:AddCustom(id, name)
        if Tattle.SpellName(id) == ("Spell " .. id) then
            CRT:Print(format("Added spell %d. The game doesn't know a spell with that ID, so check it.", id))
        end
        idEdit:SetText("")
        nameEdit:SetText("")
        idEdit:ClearFocus()
        nameEdit:ClearFocus()
    end
    addButton:SetScript("OnClick", add)
    idEdit:SetScript("OnEnterPressed", add)
    nameEdit:SetScript("OnEnterPressed", add)
    idEdit:SetScript("OnTabPressed", function()
        nameEdit:SetFocus()
    end)
end

local function build(pf)
    page = pf

    local title = label(pf, "Tattlebot", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    UI.Help(pf, "Tattlebot", "After each boss pull, once you are out of combat, Tattlebot reads the game's own damage meter and keeps the damage each player took from the boss mechanics in its list.\n\nThe meter gives damage, not hits, so each player gets the damage per mechanic and the number of pulls it hit them in.\n\nTonight shows tonight's pulls. History keeps every night, with totals and an export for Discord.\n\nNothing can be read during a fight: the game keeps the meter secret until combat ends."):SetPoint("LEFT", title, "RIGHT", 6, 0)

    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, pf, "BackdropTemplate")
        b:SetSize(150, 26)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 154, -36)
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
        UI:RegisterTab(b)

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
    buildMechanics(tabFrames.mechanics)
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
    -- Opens the Mechanics tab on Last fight, read fresh.
    Scan = function()
        shownBoss = SCAN
        currentTab = "mechanics"
        doScan()
        if page and page:IsShown() then
            selectTab("mechanics")
            refresh()
        else
            UI:Show("tattle")
        end
    end,
    ScanText = function()
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
