local ADDON, CRT = ...

-- The Pace page: pick a boss, set where its health should be by phase (or by time from the pull),
-- and turn its pace window on or off. Rows are added one at a time or pasted with Import, and Export
-- gives them back as text. A boss's shipped plan (Pace/Database.lua) is used until you change it; Reset
-- goes back to it. The window itself is Pace/Display.lua.

local Pace = CRT.Pace
local UI = CRT.UI

local TEXT = {
    title = "Pace",
    help = "Where a boss's health should be as the fight goes, so you can see in the pull whether the raid is ahead of or behind the plan.\n\nBy phase (the default), a row's seconds count from when its phase starts, from the pull, a phase event or Next phase on Raid Notes. By time, they count from the pull and the phase is ignored. Between two rows the expected health runs in a straight line.\n\nIn the pull, the pace window shows each boss's health with a tick where it should be, and AHEAD or BEHIND. The game hides boss health from addons in combat, so the game itself does the comparing; that also means the addon can't post or say when you fall behind.\n\nMove the window with Previews.",
    boss = "Boss",
    mode = "Times",
    showBoss = "Show the pace window for this boss",
    showAll = "Show the pace window",
    phase = "Phase",
    seconds = "Seconds",
    unit = "Boss unit",
    expected = "Expected %",
    add = "Add",
    delete = "Delete",
    import = "Import",
    export = "Export",
    reset = "Reset to shipped",
    noBoss = "No bosses yet: pull one, stand in its raid, or add its reference on the Timeline.",
    noRows = "Add your next checkpoint above, or Import a list.",
    start = "start, automatic",
    shipped = "In use: the plan shipped with the addon",
    yours = "In use: your own plan",
    raid = "In use: the raid's plan, shared by %s",
    use = "Plan in use",
    useRaid = "The raid's plan (from %s)",
    useOwn = "Your own plan",
    share = "Share to raid",
    shareAll = "Share all",
    shareHelp = "Share to raid sends this boss's plan in use to everyone in the group with the addon; Share all sends every boss that has one. Only the raid leader or an assistant can share, and only their plans are accepted.\n\nA shared plan is saved as the raid's plan, apart from each raider's own, and becomes the plan in use. Sharing again always puts everyone back on the raid's plan. Anyone can switch a boss to their own plan under Plan in use, and editing a boss's rows switches you to your own plan.\n\nAddon messages are blocked during a boss fight, so share before the pull.",
}

local MODES = { { key = "phase", label = "By phase (seconds into each phase)" }, { key = "time", label = "By time from the pull" } }
local PHASES = {}
for i = 1, 6 do
    PHASES[i] = { key = i, label = "Phase " .. i }
end
local UNIT_OPTIONS = {}
for _, u in ipairs(Pace.UNITS) do
    UNIT_OPTIONS[#UNIT_OPTIONS + 1] = { key = u, label = u }
end

-- Two columns: the boss, its plan and the new-checkpoint row on the left; the checkpoints on the right,
-- from LIST_TOP down to the buttons at the bottom of the page (UI.PAGE_W x UI.PAGE_H).
local ROW_H = 22
local LIST_X = 390
local LIST_W = UI.PAGE_W - LIST_X - 8 - 16 -- the scroll bar takes the rest
local LIST_TOP = -82
local MAX_ROWS = math.floor((UI.PAGE_H + LIST_TOP - 44) / ROW_H)

local page, selected, rows, offset = nil, nil, {}, 0
local controls = {}
local newRow = { ph = 1, unit = "boss1" }
local statusText, emptyText, secondsEdit, hpEdit, textDialog, slider, startRow
local refresh

local function bosses()
    local list = CRT.NoteReminders and CRT.NoteReminders.BossList and CRT.NoteReminders.BossList() or {}
    local out, seen = {}, {}
    for _, b in ipairs(list) do
        out[#out + 1] = { key = b.key, label = b.label }
        seen[b.key] = true
    end
    for id in pairs(CRT.PaceDB.bosses) do
        if not seen[id] then
            out[#out + 1] = { key = id, label = "Encounter " .. id }
        end
    end
    for id in pairs(CRT.db.pace.own) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = { key = id, label = "Encounter " .. id }
        end
    end
    return out
end

local function boss()
    local list = bosses()
    if selected then
        for _, b in ipairs(list) do
            if b.key == selected then
                return selected
            end
        end
    end
    selected = list[1] and list[1].key or nil
    return selected
end

local function clock(t)
    return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function checkbox(parent, x, y, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    cb.refresh = function()
        cb:SetChecked(get() and true or false)
    end
    controls[#controls + 1] = cb
    return cb
end

local function numberBox(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject(CRTFontEdit)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- Import and Export share one text window; Import also has its OK.
local function getTextDialog()
    if textDialog then
        return textDialog
    end
    local d = CreateFrame("Frame", "CowfeeRaidToolsPaceText", UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(d)
    d:SetSize(440, 360)
    d:SetPoint("CENTER")
    UI:RegisterLayer("popups", d)
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CowfeeRaidToolsPaceText")
    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsPaceTextScroll", d, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -34)
    scroll:SetPoint("BOTTOMRIGHT", -34, 46)
    d.edit = CreateFrame("EditBox", nil, scroll)
    d.edit:SetMultiLine(true)
    d.edit:SetAutoFocus(false)
    d.edit:SetFontObject(CRTFontEdit)
    d.edit:SetWidth(380)
    d.edit:SetScript("OnEscapePressed", function()
        d:Hide()
    end)
    scroll:SetScrollChild(d.edit)
    d.ok = button(d, TEXT.import, 110)
    d.ok:SetPoint("BOTTOM", -60, 12)
    d.ok:SetScript("OnClick", function()
        local n, err = Pace:Import(boss(), d.edit:GetText())
        if n then
            CRT:Print("Imported " .. n .. " pace rows.")
            d:Hide()
        else
            CRT:Print(err)
        end
    end)
    d.close = button(d, CLOSE, 110)
    d.close:SetScript("OnClick", function()
        d:Hide()
    end)
    UI:SkinTree(d)
    d:Hide()
    textDialog = d
    return d
end

local function makeRow(f, i)
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(LIST_W, ROW_H)
    r:SetPoint("TOPLEFT", LIST_X, LIST_TOP - (i - 1) * ROW_H)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
    local function cell(x, w)
        local fs = r:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        return fs
    end
    r.ph, r.t, r.unit, r.hp = cell(8, 70), cell(82, 90), cell(176, 80), cell(260, 70)
    r.delete = button(r, TEXT.delete, 70)
    r.delete:SetHeight(18)
    r.delete:SetPoint("RIGHT", -4, 0)
    r.delete:SetScript("OnClick", function(self)
        Pace:RemoveRow(boss(), self:GetParent().index)
    end)
    return r
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    for _, c in ipairs(controls) do
        c.refresh()
    end
    local id = boss()
    local plan = id and Pace:Plan(id)
    local list = plan and plan.rows or {}
    local time = plan and plan.mode == "time"
    offset = math.max(0, math.min(offset, #list - MAX_ROWS))
    for i, r in ipairs(rows) do
        local row = list[offset + i]
        if row then
            r.index = offset + i
            r.ph:SetText(time and "-" or ("Phase " .. row.ph))
            r.t:SetText(clock(row.t) .. "  (" .. tostring(row.t) .. "s)")
            r.unit:SetText(row.unit)
            r.hp:SetText(string.format("%s%%", tostring(row.hp)))
            r:Show()
        else
            r:Hide()
        end
    end
    if slider then
        slider:SetMinMaxValues(0, math.max(0, #list - MAX_ROWS))
        slider:SetValue(offset)
        slider:SetShown(#list > MAX_ROWS)
    end
    if not id then
        statusText:SetText(TEXT.noBoss)
    else
        local source = Pace:Source(id)
        local shared = Pace:Shared(id)
        statusText:SetText((source == "raid" and string.format(TEXT.raid, shared.from or "?")) or (source == "own" and TEXT.yours) or (source == "shipped" and TEXT.shipped) or "")
    end
    emptyText:SetShown(id ~= nil and #list == 0)
    startRow:SetShown(id ~= nil)
    startRow.ph:SetText(time and "-" or "Phase 1")
    startRow.t:SetText("0:00  (0s)")
    startRow.unit:SetText("every boss")
    startRow.hp:SetText("100%")
end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(TEXT.title)
    UI.Help(pf, TEXT.title, TEXT.help):SetPoint("LEFT", title, "RIGHT", 6, 0)

    local bossRow = UI.Dropdown(pf, TEXT.boss, { options = bosses, labelWidth = 40, width = 260,
        get = function()
            return boss()
        end,
        set = function(id)
            selected, offset = id, 0
            refresh()
        end })
    bossRow:SetPoint("TOPLEFT", 8, -40)
    controls[#controls + 1] = bossRow
    local modeRow = UI.Dropdown(pf, TEXT.mode, { options = MODES, labelWidth = 44, width = 230,
        enabledIf = function()
            return boss() ~= nil
        end,
        get = function()
            local plan = boss() and Pace:Plan(boss())
            return plan and plan.mode or "phase"
        end,
        set = function(mode)
            Pace:SetMode(boss(), mode)
        end })
    modeRow:SetPoint("TOPLEFT", 8, -72)
    controls[#controls + 1] = modeRow

    checkbox(pf, 4, -104, TEXT.showBoss, function()
        return boss() and Pace:Enabled(boss())
    end, function(on)
        if boss() then
            Pace:SetEnabled(boss(), on)
        end
    end)
    checkbox(pf, 4, -128, TEXT.showAll, function()
        return CRT.db.pace.shown ~= false
    end, function(on)
        CRT.db.pace.shown = on
        if not on then
            Pace:Stop()
        end
    end)

    -- Add a row.
    local phaseRow = UI.Dropdown(pf, TEXT.phase, { options = PHASES, labelWidth = 40, width = 100,
        get = function()
            return newRow.ph
        end,
        set = function(v)
            newRow.ph = v
        end,
        enabledIf = function()
            local plan = boss() and Pace:Plan(boss())
            return not (plan and plan.mode == "time")
        end })
    phaseRow:SetPoint("TOPLEFT", 8, -214)
    controls[#controls + 1] = phaseRow
    local secLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    secLabel:SetPoint("TOPLEFT", 170, -222)
    secLabel:SetText(TEXT.seconds)
    secondsEdit = numberBox(pf, 50)
    secondsEdit:SetPoint("LEFT", secLabel, "RIGHT", 8, 0)
    local unitRow = UI.Dropdown(pf, TEXT.unit, { options = UNIT_OPTIONS, labelWidth = 60, width = 90,
        get = function()
            return newRow.unit
        end,
        set = function(v)
            newRow.unit = v
        end })
    unitRow:SetPoint("TOPLEFT", 8, -248)
    controls[#controls + 1] = unitRow
    local hpLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    hpLabel:SetPoint("TOPLEFT", 170, -256)
    hpLabel:SetText(TEXT.expected)
    hpEdit = numberBox(pf, 50)
    hpEdit:SetPoint("LEFT", hpLabel, "RIGHT", 8, 0)
    local add = button(pf, TEXT.add, 60)
    add:SetPoint("LEFT", hpEdit, "RIGHT", 8, 0)
    add:SetScript("OnClick", function()
        local t, hp = tonumber(secondsEdit:GetText()), tonumber(hpEdit:GetText())
        if not boss() then
            CRT:Print(TEXT.noBoss)
        elseif not t or not hp then
            CRT:Print("Type the seconds and the expected health first, such as 30 and 72.1.")
        else
            Pace:AddRow(boss(), newRow.ph, t, newRow.unit, hp)
            secondsEdit:SetText("")
            hpEdit:SetText("")
        end
    end)

    -- The list.
    local head = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    head:SetPoint("TOPLEFT", LIST_X + 8, -40)
    head:SetText("Phase         Time                  Unit              Expected")
    statusText = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    statusText:SetPoint("TOPLEFT", 8, -158)
    local useRow = UI.Dropdown(pf, TEXT.use, { labelWidth = 80, width = 200,
        options = function()
            local shared = boss() and Pace:Shared(boss())
            local out = {}
            if shared then
                out[#out + 1] = { key = "raid", label = string.format(TEXT.useRaid, shared.from or "?") }
            end
            out[#out + 1] = { key = "own", label = TEXT.useOwn }
            return out
        end,
        get = function()
            return Pace:Source(boss()) == "raid" and "raid" or "own"
        end,
        set = function(key)
            Pace:SetUse(boss(), key)
        end })
    useRow:SetPoint("TOPLEFT", 8, -176)
    local useRefresh = useRow.refresh
    useRow.refresh = function()
        useRefresh()
        useRow:SetShown(boss() ~= nil and Pace:Shared(boss()) ~= nil)
    end
    controls[#controls + 1] = useRow
    emptyText = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", LIST_X + 8, LIST_TOP - 4)
    emptyText:SetText(TEXT.noRows)
    -- Every boss starts at 100% at the pull, so that point is always there; checkpoints follow it.
    startRow = makeRow(pf, 1)
    startRow:ClearAllPoints()
    startRow:SetPoint("TOPLEFT", LIST_X, LIST_TOP + ROW_H)
    startRow.delete:Hide()
    startRow.note = startRow:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    startRow.note:SetPoint("RIGHT", -10, 0)
    startRow.note:SetText(TEXT.start)
    for _, fs in ipairs({ startRow.ph, startRow.t, startRow.unit, startRow.hp }) do
        fs:SetTextColor(0.6, 0.6, 0.6)
    end
    for i = 1, MAX_ROWS do
        rows[i] = makeRow(pf, i)
    end
    slider = CreateFrame("Slider", nil, pf)
    slider:SetOrientation("VERTICAL")
    slider:SetSize(10, MAX_ROWS * ROW_H)
    slider:SetPoint("TOPLEFT", LIST_X + LIST_W + 6, LIST_TOP)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.2, 0.2, 0.2, 0.6)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor((v or 0) + 0.5)
        if v ~= offset then
            offset = v
            refresh()
        end
    end)
    slider:Hide()
    pf:EnableMouseWheel(true)
    pf:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        refresh()
    end)

    -- Import, Export and Reset.
    local import = button(pf, TEXT.import, 110)
    import:SetPoint("BOTTOMLEFT", 8, 10)
    import:SetScript("OnClick", function()
        local d = getTextDialog()
        UI.SetFrameTitle(d, "Import pace rows: phase seconds unit health, one per line")
        d.ok:Show()
        d.close:SetPoint("BOTTOM", 60, 12)
        d.edit:SetText("")
        d:Show()
        d.edit:SetFocus()
    end)
    local export = button(pf, TEXT.export, 110)
    export:SetPoint("LEFT", import, "RIGHT", 6, 0)
    export:SetScript("OnClick", function()
        local d = getTextDialog()
        UI.SetFrameTitle(d, "Export pace rows (Ctrl+C to copy)")
        d.ok:Hide()
        d.close:SetPoint("BOTTOM", 0, 12)
        d.edit:SetText(boss() and Pace:Export(boss()) or "")
        d:Show()
        d.edit:SetFocus()
        d.edit:HighlightText()
    end)
    -- Sharing, for the raid leader and assistants.
    local share = button(pf, TEXT.share, 120)
    share:SetPoint("BOTTOMRIGHT", -8, 10)
    share:SetScript("OnClick", function()
        if boss() then
            CRT.PaceComm:Share({ boss() })
        end
    end)
    local shareAll = button(pf, TEXT.shareAll, 90)
    shareAll:SetPoint("RIGHT", share, "LEFT", -6, 0)
    shareAll:SetScript("OnClick", function()
        CRT.PaceComm:Share(CRT.PaceComm:AllPlanned())
    end)
    UI.Help(pf, TEXT.share, TEXT.shareHelp):SetPoint("RIGHT", shareAll, "LEFT", -4, 0)
    controls[#controls + 1] = {
        refresh = function()
            local can = CRT.PaceComm:CanShare()
            share:SetEnabled(can and boss() ~= nil and Pace:Plan(boss()) ~= nil)
            shareAll:SetEnabled(can and true or false)
        end,
    }

    local reset = button(pf, TEXT.reset, 140)
    reset:SetPoint("LEFT", export, "RIGHT", 6, 0)
    reset:SetScript("OnClick", function()
        if boss() then
            Pace:Reset(boss())
        end
    end)

    pf:SetScript("OnShow", refresh)
    Pace:OnChange(refresh)
end

UI:RegisterPage("pace", TEXT.title, build)
