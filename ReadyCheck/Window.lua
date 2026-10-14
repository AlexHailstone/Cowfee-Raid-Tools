local ADDON, CRT = ...

-- The ready check window: one row per player and one column per check (food, flask, runes, the raid
-- buffs, durability), with each player's ready answer. It opens on a ready check for raid leaders and
-- assistants (a setting), stays for 30 seconds (a setting), and closes early on a right-click. It
-- refreshes every second while open, so it follows people eating and buffing.
--
-- Durability is not something the game shows about other players, so every player running this
-- addon sends their own over an addon message when a ready check starts: "D:<percent>" under the
-- prefix CRTReady. Opening the window by hand sends "Q", which asks everyone to send theirs. Your own
-- is read live. Players without the addon show a blank.

local Report = CRT.RaidReport
local Window = {}
CRT.ReadyCheckWindow = Window

local PREFIX = "CRTReady"
local NAME_W = 130
local READY_W = 26
local ROLE_W = 20 -- the role icon, between the ready icon and the name
local LEAD_W = READY_W + ROLE_W

-- The same role art as the Raid Groups page.
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local COL_W = 46
local ROW_H = 20
local TOP_H = 50 -- title and column headings
local ICON = 16
local DURABILITY_LOW = 30 -- a shift-clicked Dur heading posts players under this percent

local READY_ICONS = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

-- Every column the window can show, in order. The raid buff columns come from Report.BUFFS.
Window.COLUMNS = {
    { key = "food", short = "Food", label = "Food" },
    { key = "flask", short = "Flask", label = "Flask" },
    { key = "rune", short = "Rune", label = "Augment rune" },
    { key = "vantus", short = "Vantus", label = "Vantus rune" },
}
for _, buff in ipairs(Report.BUFFS) do
    Window.COLUMNS[#Window.COLUMNS + 1] = { key = buff.key, short = buff.short, label = buff.label, buff = buff }
end
Window.COLUMNS[#Window.COLUMNS + 1] = { key = "durability", short = "Dur", label = "Durability" }

local frame
local shownUntil, previewOn = 0, false
local stayOpen = false -- opened by /crt check: no timer, closes on a right-click
local checkActive = false -- a ready check is running, between READY_CHECK and READY_CHECK_FINISHED
local sampleOn = false -- opened by Show it now: sample players, closes like the real one
local readyState = {} -- short name -> "ready" | "notready" | "waiting"
local durability = {} -- short name -> percent

local function settings()
    return CRT.db.readycheck.window
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Durability --------------------------------------------------------------------------

-- Your average durability across equipped items, as a whole percent.
local function myDurability()
    local current, maximum = 0, 0
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            current, maximum = current + cur, maximum + max
        end
    end
    if maximum == 0 then
        return 100
    end
    return math.floor(current / maximum * 100 + 0.5)
end

local function groupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function send(text)
    local channel = groupChannel()
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
    end
end

local lastSent = 0
local function sendDurability()
    lastSent = GetTime()
    send("D:" .. myDurability())
end

-- Answers a request for durability, at most once every 5 seconds so a burst of requests is one reply.
local function answerRequest()
    if GetTime() - lastSent >= 5 then
        sendDurability()
    end
end

-- Columns and data ------------------------------------------------------------------------

-- The columns to draw: ticked in settings, and for raid buffs only those your group can give when
-- "Only buffs my group can give" is on.
local byKey = {}
for _, col in ipairs(Window.COLUMNS) do
    byKey[col.key] = col
end

-- Every column in the player's order (CRTDB.readycheck.window.order). Columns added in a later
-- version, and so missing from a saved order, go at the end.
function Window:OrderedColumns()
    local out, seen = {}, {}
    for _, key in ipairs(settings().order or {}) do
        if byKey[key] and not seen[key] then
            out[#out + 1] = byKey[key]
            seen[key] = true
        end
    end
    for _, col in ipairs(Window.COLUMNS) do
        if not seen[col.key] then
            out[#out + 1] = col
        end
    end
    return out
end

-- Moves a column to a place in the order, 1 being leftmost.
function Window:MoveColumnTo(key, index)
    local keys = {}
    for _, col in ipairs(self:OrderedColumns()) do
        if col.key ~= key then
            keys[#keys + 1] = col.key
        end
    end
    table.insert(keys, math.max(1, math.min(#keys + 1, index)), key)
    settings().order = keys
    self:Apply()
end

local function visibleColumns(classes)
    local s = settings()
    local out = {}
    for _, col in ipairs(Window:OrderedColumns()) do
        if s.columns[col.key] and not (col.buff and s.groupBuffsOnly and classes and not classes[col.buff.class]) then
            out[#out + 1] = col
        end
    end
    return out
end

-- Drawing -----------------------------------------------------------------------------------
-- A table is the column headings and one row per player, drawn inside a frame dressed by
-- Window.Dress. The ready check window draws one. The Window tab of the Ready Check page draws
-- another with sample players in edit mode, where a heading is dragged to move its column and
-- clicked to show or hide it, so what you arrange there is exactly what the window shows.

local function classColor(class)
    local c = class and RAID_CLASS_COLORS[class]
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

local function sampleIcon(key)
    local buff = Report.BuffByKey[key]
    if buff then
        return C_Spell.GetSpellTexture(buff.spell)
    end
    return CRT.Consumables.QUESTION_MARK
end

-- Sample players for the previews: { name, class, ready, dur, cells[key] = { state, icon, left } }.
function Window.SampleMembers()
    local list = {
        { name = "Solex", class = "PALADIN", role = "HEALER", subgroup = 2, ready = "ready", dur = 90, states = { food = "ok", flask = "low", rune = "ok", vantus = "ok", intellect = "ok", stamina = "ok", attack = "ok", versatility = "ok", mastery = "ok", movement = "ok" } },
        { name = "Rixxy", class = "MAGE", role = "DAMAGER", subgroup = 1, ready = "waiting", dur = 100, states = { food = "ok", flask = "ok", intellect = "ok", stamina = "missing", attack = "ok", versatility = "ok", mastery = "ok", movement = "missing" } },
        { name = "Gadios", class = "ROGUE", role = "DAMAGER", subgroup = 2, ready = "notready", dur = 42, states = { food = "missing", flask = "ok", rune = "missing", intellect = "ok", stamina = "ok", attack = "ok", versatility = "missing", mastery = "ok", movement = "ok" } },
        { name = "Abu", class = "DRUID", role = "TANK", subgroup = 1, ready = "ready", states = { food = "unknown", flask = "unknown", rune = "unknown", vantus = "unknown", intellect = "unknown", stamina = "unknown", attack = "unknown", versatility = "unknown", mastery = "unknown", movement = "unknown" } },
    }
    for i, m in ipairs(list) do
        m.order = i
        m.cells = {}
        for _, col in ipairs(Window.COLUMNS) do
            m.cells[col.key] = { state = m.states[col.key] or "missing", icon = sampleIcon(col.key), left = 240 }
        end
    end
    return list
end

-- Gives a frame the window's look: backdrop, title and the time line in the corner. The frame must
-- be made with BackdropTemplate.
function Window.Dress(f)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
    f:SetBackdropBorderColor(0.78, 0.63, 0.31, 1)
    f.title = f:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    f.title:SetPoint("TOPLEFT", 8, -6)
    f.timer = f:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    f.timer:SetPoint("TOPRIGHT", -8, -8)
end

-- Sorting -------------------------------------------------------------------------------------

Window.SORTS = {
    { key = "group", label = "Group" },
    { key = "role", label = "Role" },
    { key = "name", label = "Name" },
}

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

-- Sorts players in place by the window's "sort" setting: group (raid group, then raid order), role
-- (tanks, healers, damage, then no role, each by name) or name. Ties fall back to raid order.
function Window.Sort(members)
    local mode = settings().sort or "group"
    table.sort(members, function(a, b)
        if mode == "group" and (a.subgroup or 9) ~= (b.subgroup or 9) then
            return (a.subgroup or 9) < (b.subgroup or 9)
        end
        if mode == "role" then
            local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
            if ra ~= rb then
                return ra < rb
            end
        end
        if (mode == "role" or mode == "name") and a.name ~= b.name then
            return a.name:lower() < b.name:lower()
        end
        return (a.order or 0) < (b.order or 0)
    end)
    return members
end

local Table = {}
Table.__index = Table

-- parent is a frame dressed by Window.Dress. edit turns on dragging and clicking the headings, and
-- onEdit is called after a column is moved, shown or hidden. Without edit, onShiftClick(key) is called
-- when a heading is shift-clicked, and a right-click on a heading closes the window like anywhere else.
function Window.NewTable(parent, edit, onEdit, onShiftClick)
    local t = setmetatable({ parent = parent, edit = edit, onEdit = onEdit, onShiftClick = onShiftClick, rows = {}, headers = {}, count = 0, rowCount = 0 }, Table)
    if edit then
        t.marker = parent:CreateTexture(nil, "OVERLAY")
        t.marker:SetColorTexture(1, 0.82, 0, 1)
        t.marker:SetWidth(2)
        t.marker:Hide()
    end
    return t
end

local function columnX(j)
    return 6 + LEAD_W + NAME_W + (j - 1) * COL_W
end

-- The column index under the cursor, 1 to count.
function Table:IndexAtCursor()
    local scale = self.parent:GetEffectiveScale()
    local x = GetCursorPosition() / scale - self.parent:GetLeft()
    return math.max(1, math.min(self.count, math.floor((x - columnX(1)) / COL_W) + 1))
end

local function headerClick(self)
    local columns = settings().columns
    columns[self.key] = not columns[self.key]
    Window:Apply()
    self.owner.onEdit()
end

local function headerDragStart(self)
    self.owner.dragKey = self.key
    self.text:SetTextColor(1, 0.82, 0)
end

local function headerDragStop(self)
    local t = self.owner
    t.dragKey = nil
    t.marker:Hide()
    Window:MoveColumnTo(self.key, t:IndexAtCursor())
    t.onEdit()
end

-- While a heading is dragged, a gold line marks where the column will land.
local function headerUpdate(self)
    local t = self.owner
    if t.dragKey ~= self.key then
        return
    end
    local index = t:IndexAtCursor()
    local x = columnX(index) + (index > self.index and COL_W or 0)
    t.marker:ClearAllPoints()
    t.marker:SetPoint("TOP", t.parent, "TOPLEFT", x, -TOP_H + 22)
    t.marker:SetHeight(t.rowCount * ROW_H + 24)
    t.marker:Show()
end

local function headerEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.label, 1, 1, 1)
    GameTooltip:AddLine("Click to show or hide this column. Drag it left or right to move it.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

function Table:Header(j)
    local h = self.headers[j]
    if h then
        return h
    end
    h = CreateFrame("Button", nil, self.parent)
    h:SetSize(COL_W, 20)
    h.owner = self
    h.text = h:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    h.text:SetPoint("CENTER")
    if self.edit then
        local hl = h:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        h:RegisterForClicks("LeftButtonUp")
        h:RegisterForDrag("LeftButton")
        h:SetScript("OnClick", headerClick)
        h:SetScript("OnDragStart", headerDragStart)
        h:SetScript("OnDragStop", headerDragStop)
        h:SetScript("OnUpdate", headerUpdate)
        h:SetScript("OnEnter", headerEnter)
        h:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    else
        h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        h:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                Window:Hide()
            elseif IsShiftKeyDown() and self.owner.onShiftClick then
                self.owner.onShiftClick(self.key)
            end
        end)
        h:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.label, 1, 1, 1)
            if self.key == "durability" then
                GameTooltip:AddLine("Shift-click to post who is under " .. DURABILITY_LOW .. "% durability to raid chat.", 0.8, 0.8, 0.8, true)
            else
                GameTooltip:AddLine("Shift-click to post who is missing this to raid chat.", 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    self.headers[j] = h
    return h
end

function Table:Row(i)
    local row = self.rows[i]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, self.parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 6, -TOP_H - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", self.parent, "RIGHT", -6, 0)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
    row.ready = row:CreateTexture(nil, "ARTWORK")
    row.ready:SetSize(ICON, ICON)
    row.ready:SetPoint("LEFT", 4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.role = row:CreateTexture(nil, "ARTWORK")
    row.role:SetSize(ICON, ICON)
    row.role:SetPoint("LEFT", READY_W, 0)
    row.role:SetTexture(ROLE_TEXTURE)
    row.name:SetPoint("LEFT", LEAD_W, 0)
    row.name:SetWidth(NAME_W - 4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cells = {}
    self.rows[i] = row
    return row
end

local function getCell(row, j)
    local cell = row.cells[j]
    if cell then
        return cell
    end
    cell = CreateFrame("Frame", nil, row)
    cell:SetSize(COL_W, ROW_H)
    cell:SetPoint("LEFT", LEAD_W + NAME_W + (j - 1) * COL_W, 0)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ICON, ICON)
    cell.icon:SetPoint("CENTER")
    cell.text = cell:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    cell.text:SetPoint("CENTER")
    row.cells[j] = cell
    return cell
end

-- c.state: "ok", "low", "missing" or "unknown".
local function drawCell(cell, c)
    cell.icon:Hide()
    cell.text:SetText("")
    if c.state == "ok" or c.state == "low" then
        cell.icon:SetTexture(c.icon or CRT.Consumables.QUESTION_MARK)
        cell.icon:Show()
        if c.state == "low" then
            cell.icon:SetVertexColor(1, 0.6, 0.6)
            cell.text:SetText(c.left and ("|cffffd100" .. math.max(1, math.floor(c.left / 60 + 0.5)) .. "|r") or "|cffffd100!|r")
        else
            cell.icon:SetVertexColor(1, 1, 1)
        end
    elseif c.state == "missing" then
        cell.text:SetText("|cffff4040x|r")
    elseif c.state == "unknown" then
        cell.text:SetText("|cff888888?|r")
    end
end

local function drawDurability(cell, percent)
    cell.icon:Hide()
    if not percent then
        cell.text:SetText("")
        return
    end
    local color = percent < 50 and "ff4040" or (percent < 80 and "ffd100" or "ffffff")
    cell.text:SetText("|cff" .. color .. percent .. "%|r")
end

-- members: { name, class, ready, dur, cells[key] }. columns: the columns in order. dim[key] fades a
-- column (hidden columns on the Window tab). Sizes the parent and returns how many are ready.
function Table:Draw(members, columns, dim)
    dim = dim or {}
    self.count, self.rowCount = #columns, #members
    self.members, self.columns = members, columns
    for j, col in ipairs(columns) do
        local h = self:Header(j)
        h.key, h.label, h.index = col.key, col.label, j
        h:ClearAllPoints()
        h:SetPoint("BOTTOMLEFT", self.parent, "TOPLEFT", columnX(j), -TOP_H)
        h.text:SetText(col.short)
        if self.dragKey ~= col.key then
            if dim[col.key] then
                h.text:SetTextColor(0.45, 0.45, 0.45)
            else
                h.text:SetTextColor(0.85, 0.85, 0.85)
            end
        end
        h:Show()
    end
    for j = #columns + 1, #self.headers do
        self.headers[j]:Hide()
    end
    self.parent:SetSize(12 + LEAD_W + NAME_W + math.max(#columns, 3) * COL_W, TOP_H + math.max(#members, 1) * ROW_H + 8)

    local readyCount = 0
    for i, m in ipairs(members) do
        local row = self:Row(i)
        row:Show()
        row.name:SetText(m.name)
        local r, g, b = classColor(m.class)
        row.name:SetTextColor(r, g, b)
        -- A bar in the class color behind the row, or plain stripes when that is off.
        if settings().classBars then
            row.bg:SetColorTexture(r, g, b, 0.22)
        else
            row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
        end
        if m.ready == "ready" then
            readyCount = readyCount + 1
        end
        row.ready:SetTexture(m.ready and READY_ICONS[m.ready] or nil)
        local coords = m.role and ROLE_COORDS[m.role]
        if coords then
            row.role:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            row.role:Show()
        else
            row.role:Hide()
        end
        for j, col in ipairs(columns) do
            local cell = getCell(row, j)
            cell:Show()
            cell:SetAlpha(dim[col.key] and 0.25 or 1)
            if col.key == "durability" then
                drawDurability(cell, m.dur)
            else
                drawCell(cell, m.cells[col.key] or { state = "missing" })
            end
        end
        for j = #columns + 1, #row.cells do
            row.cells[j]:Hide()
        end
    end
    for i = #members + 1, #self.rows do
        self.rows[i]:Hide()
    end
    return readyCount
end

-- The group as the window shows it, with ready answers, cells and durability filled in.
local function liveMembers(members, columns)
    for _, m in ipairs(members) do
        -- Answers come from READY_CHECK and READY_CHECK_CONFIRM. GetReadyCheckStatus has no Warcraft
        -- Wiki page, so it is only used if the game has it.
        if GetReadyCheckStatus then
            local ok, status = pcall(GetReadyCheckStatus, m.unit)
            if ok and status and not isSecret(status) then
                readyState[m.name] = status
            end
        end
        -- Outside a ready check, a window opened with /crt check has no answers to show.
        if checkActive then
            m.ready = readyState[m.name] or "waiting"
        elseif stayOpen then
            m.ready = nil
        else
            m.ready = readyState[m.name] or "waiting"
        end
        if UnitIsUnit(m.unit, "player") then
            m.dur = myDurability()
        else
            m.dur = durability[m.name]
        end
        m.cells = {}
        for _, col in ipairs(columns) do
            if col.key ~= "durability" then
                m.cells[col.key] = Report.Cell(m, col.key)
            end
        end
    end
    return members
end

local windowTable

-- Shift-click posting ------------------------------------------------------------------------------

-- One chat line for a column, from what the window shows: who is missing it, whose flask is running
-- out, and whose buffs the game hid.
function Window.ColumnLine(col, members)
    if col.key == "durability" then
        local low = {}
        for _, m in ipairs(members) do
            if m.dur and m.dur < DURABILITY_LOW then
                low[#low + 1] = m.name .. " " .. m.dur .. "%"
            end
        end
        if #low == 0 then
            return "Durability: everyone with the addon is at " .. DURABILITY_LOW .. "% or more"
        end
        return "Durability under " .. DURABILITY_LOW .. "%: " .. table.concat(low, ", ")
    end
    local missing, low, unknown = {}, {}, {}
    for _, m in ipairs(members) do
        local c = m.cells and m.cells[col.key]
        if c then
            if c.state == "missing" then
                missing[#missing + 1] = m.name
            elseif c.state == "low" then
                low[#low + 1] = m.name .. (c.left and (" (" .. math.max(1, math.floor(c.left / 60 + 0.5)) .. " min)") or "")
            elseif c.state == "unknown" then
                unknown[#unknown + 1] = m.name
            end
        end
    end
    local line
    if #missing == 0 and #low == 0 then
        line = col.label .. ": everyone has it"
    elseif #missing > 0 then
        line = col.label .. " missing: " .. table.concat(missing, ", ")
        if #low > 0 then
            line = line .. "; running out: " .. table.concat(low, ", ")
        end
    else
        line = col.label .. " running out: " .. table.concat(low, ", ")
    end
    if #unknown > 0 then
        line = line .. "; couldn't check: " .. table.concat(unknown, ", ")
    end
    return line
end

-- Posts a column to the "Post to" channel on the Settings tab, or raid chat if that is Only me.
-- Sample players (Show it now, Previews) are only printed to you, never posted.
function Window:PostColumn(key)
    local t = windowTable
    if not (t and t.members and t.columns) then
        return
    end
    local col
    for _, c in ipairs(t.columns) do
        if c.key == key then
            col = c
        end
    end
    if not col then
        return
    end
    local line = Window.ColumnLine(col, t.members)
    if previewOn or sampleOn then
        CRT:Print("(sample players, not posted) " .. line)
        return
    end
    local output = CRT.db.readycheck.output
    Report:Output({ line }, (output and output ~= "self") and output or "raid")
end

function Window:Refresh()
    if not frame or not frame:IsShown() then
        return
    end
    local members, columns
    if previewOn or sampleOn then
        members = Window.SampleMembers()
        columns = visibleColumns(nil)
    else
        members = Report:ReadGroup()
        columns = visibleColumns(Report.Classes(members))
        liveMembers(members, columns)
    end
    Window.Sort(members)
    local readyCount = windowTable:Draw(members, columns)
    local left = math.max(0, math.ceil(shownUntil - GetTime()))
    if stayOpen and not checkActive and not previewOn then
        frame.title:SetText(format("Group check  %d %s", #members, #members == 1 and "player" or "players"))
    else
        frame.title:SetText(format("Ready check  %d/%d ready", readyCount, #members))
    end
    if previewOn then
        frame.timer:SetText("preview")
    elseif stayOpen then
        frame.timer:SetText("right-click to close")
    else
        frame.timer:SetText(left .. "s, right-click to close")
    end
end

-- What the Window tab draws: every column in order, the hidden ones faded, with sample players.
function Window:DrawEditor(t)
    local columns = self:OrderedColumns()
    local dim = {}
    for _, col in ipairs(columns) do
        dim[col.key] = not settings().columns[col.key]
    end
    local members = Window.Sort(Window.SampleMembers())
    local readyCount = t:Draw(members, columns, dim)
    t.parent.title:SetText(format("Ready check  %d/%d ready", readyCount, #members))
    t.parent.timer:SetText((settings().seconds or 30) .. "s, right-click to close")
end

-- The frame ---------------------------------------------------------------------------------

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    settings().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function applyPosition()
    local s = settings()
    frame:ClearAllPoints()
    local p = s.position
    if p then
        frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    frame:SetScale((s.scale or 100) / 100)
end

local function build()
    frame = CreateFrame("Frame", "CowfeeRaidToolsReadyCheckWindow", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    Window.Dress(frame)
    windowTable = Window.NewTable(frame, false, nil, function(key)
        Window:PostColumn(key)
    end)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not previewOn then
            Window:Hide()
        end
    end)


    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then
            return
        end
        elapsed = 0
        if not previewOn and GetTime() >= shownUntil then
            Window:Hide()
        else
            Window:Refresh()
        end
    end)
    applyPosition()
    frame:Hide()
end

-- sample shows the sample players from the Window tab instead of your group. stay keeps it open with
-- no timer until it is right-clicked, for /crt check.
function Window:Show(seconds, sample, stay)
    if not frame then
        build()
    end
    sampleOn = sample and true or false
    applyPosition()
    if not sample then
        send("Q") -- ask the group for their durability
    end
    if stay then
        stayOpen = true
        shownUntil = math.huge
    elseif not stayOpen then
        shownUntil = GetTime() + (seconds or settings().seconds or 30)
    end
    frame:Show()
    self:Refresh()
end

function Window:Hide()
    stayOpen = false
    if frame and not previewOn then
        frame:Hide()
    end
end

function Window:ResetPosition()
    settings().position = nil
    if frame then
        applyPosition()
    end
end

-- Applies changed settings to an open window.
function Window:Apply()
    if frame and frame:IsShown() then
        applyPosition()
        self:Refresh()
    end
end

CRT.UI:RegisterPreview("readycheckwindow", function(on)
    if not frame then
        build()
    end
    previewOn = on
    if on then
        applyPosition()
        frame:Show()
        Window:Refresh()
    else
        frame:Hide()
    end
end)

-- Events -------------------------------------------------------------------------------------

local function mayShow()
    local s = settings()
    if not s.enabled then
        return false
    end
    if s.leadOnly and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return false
    end
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("READY_CHECK")
events:RegisterEvent("READY_CHECK_CONFIRM")
events:RegisterEvent("READY_CHECK_FINISHED")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
    if not CRT.db then
        return
    end
    if event == "READY_CHECK" then
        local initiator = ...
        readyState, durability = {}, {}
        checkActive = true
        if initiator and not isSecret(initiator) then
            readyState[Ambiguate(initiator, "short")] = "ready"
        end
        durability[UnitName("player")] = myDurability()
        sendDurability()
        if mayShow() then
            Window:Show()
        end
    elseif event == "READY_CHECK_FINISHED" then
        checkActive = false
        Window:Refresh()
    elseif event == "READY_CHECK_CONFIRM" then
        local unit, isReady = ...
        local name = unit and GetUnitName(unit, true)
        if name and not isSecret(name) and not isSecret(isReady) then
            readyState[Ambiguate(name, "short")] = isReady and "ready" or "notready"
        end
        Window:Refresh()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, _, sender = ...
        if prefix == PREFIX and type(text) == "string" and sender and not isSecret(sender) then
            local percent = tonumber(text:match("^D:(%d+)$"))
            if text == "Q" then
                answerRequest()
            elseif percent then
                durability[Ambiguate(sender, "short")] = math.min(100, percent)
                Window:Refresh()
            end
        end
    end
end)
