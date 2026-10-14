local ADDON, CRT = ...

-- The ready check window: one row per player and one column per check (food, flask, runes, the raid
-- buffs, durability), with each player's ready answer. It opens on a ready check for raid leaders and
-- assistants (a setting), stays for 30 seconds (a setting), and closes early on a right-click. It
-- refreshes every second while open, so it follows people eating and buffing.
--
-- Durability is not something the game shows about other players, so every player running this
-- addon sends their own over an addon message when a ready check starts: "D:<percent>" under the
-- prefix CRTReady. Players without the addon show a blank.

local Report = CRT.RaidReport
local Window = {}
CRT.ReadyCheckWindow = Window

local PREFIX = "CRTReady"
local NAME_W = 130
local READY_W = 26
local COL_W = 46
local ROW_H = 20
local TOP_H = 50 -- title and column headings
local ICON = 16

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

local frame, rows, headers = nil, {}, {}
local shownUntil, previewOn = 0, false
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

local function sendDurability()
    local channel = groupChannel()
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, "D:" .. myDurability(), channel)
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

-- Moves a column one place left (delta -1) or right (delta 1).
function Window:MoveColumn(key, delta)
    local keys = {}
    for i, col in ipairs(self:OrderedColumns()) do
        keys[i] = col.key
    end
    for i, k in ipairs(keys) do
        if k == key then
            local j = i + delta
            if j >= 1 and j <= #keys then
                keys[i], keys[j] = keys[j], keys[i]
            end
            break
        end
    end
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

local function sampleMembers()
    return {
        { name = "Solex", class = "PALADIN", ready = "ready", dur = 90, cells = { food = "ok", flask = "low", rune = "ok", intellect = "ok", stamina = "ok", versatility = "ok" } },
        { name = "Rixxy", class = "MAGE", ready = "waiting", dur = 100, cells = { food = "ok", flask = "ok", intellect = "ok", stamina = "missing", versatility = "ok" } },
        { name = "Gadios", class = "ROGUE", ready = "notready", dur = 42, cells = { food = "missing", flask = "ok", rune = "missing", intellect = "ok", stamina = "ok", versatility = "missing" } },
        { name = "Abu", class = "DRUID", ready = "ready", cells = {} },
    }
end

-- Drawing -----------------------------------------------------------------------------------

local function classColor(class)
    local c = class and RAID_CLASS_COLORS[class]
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

local function getRow(i)
    local row = rows[i]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 6, -TOP_H - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
    row.ready = row:CreateTexture(nil, "ARTWORK")
    row.ready:SetSize(ICON, ICON)
    row.ready:SetPoint("LEFT", 4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.name:SetPoint("LEFT", READY_W, 0)
    row.name:SetWidth(NAME_W - 4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cells = {}
    rows[i] = row
    return row
end

local function getCell(row, j)
    local cell = row.cells[j]
    if cell then
        return cell
    end
    cell = CreateFrame("Frame", nil, row)
    cell:SetSize(COL_W, ROW_H)
    cell:SetPoint("LEFT", READY_W + NAME_W + (j - 1) * COL_W, 0)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ICON, ICON)
    cell.icon:SetPoint("CENTER")
    cell.text = cell:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    cell.text:SetPoint("CENTER")
    row.cells[j] = cell
    return cell
end

-- state: "ok", "low", "missing", "unknown" or nil (column empty for this player).
local function drawCell(cell, state, icon, left)
    cell.icon:Hide()
    cell.text:SetText("")
    if state == "ok" or state == "low" then
        cell.icon:SetTexture(icon or CRT.Consumables.QUESTION_MARK)
        cell.icon:Show()
        if state == "low" then
            cell.icon:SetVertexColor(1, 0.6, 0.6)
            cell.text:SetText(left and ("|cffffd100" .. math.max(1, math.floor(left / 60 + 0.5)) .. "|r") or "|cffffd100!|r")
        else
            cell.icon:SetVertexColor(1, 1, 1)
        end
    elseif state == "missing" then
        cell.text:SetText("|cffff4040x|r")
    elseif state == "unknown" then
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

local function layout(columns, count)
    for j, col in ipairs(columns) do
        local h = headers[j]
        if not h then
            h = frame:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
            headers[j] = h
        end
        h:ClearAllPoints()
        h:SetPoint("BOTTOM", frame, "TOPLEFT", 6 + READY_W + NAME_W + (j - 0.5) * COL_W, -TOP_H + 4)
        h:SetText(col.short)
        h:Show()
    end
    for j = #columns + 1, #headers do
        headers[j]:Hide()
    end
    frame:SetSize(12 + READY_W + NAME_W + math.max(#columns, 3) * COL_W, TOP_H + math.max(count, 1) * ROW_H + 8)
end

local function sampleIcon(key)
    local buff = Report.BuffByKey[key]
    if buff then
        return C_Spell.GetSpellTexture(buff.spell)
    end
    return CRT.Consumables.QUESTION_MARK
end

function Window:Refresh()
    if not frame or not frame:IsShown() then
        return
    end
    local members, classes
    if previewOn then
        members = sampleMembers()
    else
        members = Report:ReadGroup()
        classes = Report.Classes(members)
    end
    local columns = visibleColumns(classes)
    layout(columns, #members)

    local readyCount = 0
    for i, m in ipairs(members) do
        local row = getRow(i)
        row:Show()
        local r, g, b = classColor(m.class)
        row.name:SetText(m.name)
        row.name:SetTextColor(r, g, b)

        local ready = m.ready
        if not previewOn then
            -- Answers come from READY_CHECK and READY_CHECK_CONFIRM. GetReadyCheckStatus has no Warcraft
            -- Wiki page, so it is only used if the game has it.
            if GetReadyCheckStatus then
                local ok, status = pcall(GetReadyCheckStatus, m.unit)
                if ok and status and not isSecret(status) then
                    readyState[m.name] = status
                end
            end
            ready = readyState[m.name] or "waiting"
        end
        if ready == "ready" then
            readyCount = readyCount + 1
        end
        row.ready:SetTexture(ready and READY_ICONS[ready] or nil)

        for j, col in ipairs(columns) do
            local cell = getCell(row, j)
            cell:Show()
            if col.key == "durability" then
                drawDurability(cell, previewOn and m.dur or durability[m.name])
            elseif previewOn then
                drawCell(cell, m.cells[col.key] or "missing", sampleIcon(col.key), 240)
            else
                local c = Report.Cell(m, col.key)
                drawCell(cell, c.state, c.icon, c.left)
            end
        end
        for j = #columns + 1, #row.cells do
            row.cells[j]:Hide()
        end
    end
    for i = #members + 1, #rows do
        rows[i]:Hide()
    end

    local left = math.max(0, math.ceil(shownUntil - GetTime()))
    frame.title:SetText(format("Ready check  %d/%d ready", readyCount, #members))
    frame.timer:SetText(previewOn and "preview" or (left .. "s, right-click to close"))
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
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
    frame:SetBackdropBorderColor(0.78, 0.63, 0.31, 1)
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

    frame.title = frame:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    frame.title:SetPoint("TOPLEFT", 8, -6)
    frame.timer = frame:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    frame.timer:SetPoint("TOPRIGHT", -8, -8)

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

function Window:Show(seconds)
    if not frame then
        build()
    end
    applyPosition()
    shownUntil = GetTime() + (seconds or settings().seconds or 30)
    frame:Show()
    self:Refresh()
end

function Window:Hide()
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
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
    if not CRT.db then
        return
    end
    if event == "READY_CHECK" then
        local initiator = ...
        readyState, durability = {}, {}
        if initiator and not isSecret(initiator) then
            readyState[Ambiguate(initiator, "short")] = "ready"
        end
        durability[UnitName("player")] = myDurability()
        sendDurability()
        if mayShow() then
            Window:Show()
        end
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
            if percent then
                durability[Ambiguate(sender, "short")] = math.min(100, percent)
                Window:Refresh()
            end
        end
    end
end)
