local ADDON, CRT = ...

-- The Timeline page, with three tabs: Review (pick a boss and one of its references or saved
-- pulls, see it drawn by the timeline view), References (Timeline/ReferencePage.lua: paste, edit
-- and delete reference timelines) and Settings (the view, which rows to show, the deaths, and
-- recording). Every control writes through Timeline:Set or the Journal's setters, and the page
-- redraws when either tells it something changed. The boss list is the bosses with saved pulls,
-- the bosses of the raid you are standing in, and the bosses that only have a reference, so a
-- boss can be opened before its first pull. With a reference shown, the Recent pulls list beside
-- it lays one of the boss's pulls over it; that choice is not saved.

local Timeline = CRT.Timeline
local Journal = CRT.TimelineJournal
local View = CRT.TimelineView
local Lanes = CRT.TimelineLanes
local Reference = CRT.TimelineReference
local ReferencePage = CRT.TimelineReferencePage
local UI = CRT.UI

local ROW_H = 22
local RIGHT_X = 360
local RECENT_W = 150
local DOT = " \194\183 "
local EMPTY_BOSS = "No pulls recorded for this boss yet"
local EMPTY_ALL = "No boss pulls recorded yet"

local GRAY = { 0.35, 0.35, 0.35 }
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local TABS = {
    { key = "review", label = "Review" },
    { key = "references", label = "References" },
    { key = "settings", label = "Settings" },
}

local page, view, emptyLabel, unnamedHelp, bossLabel, deleteButton, rowsChild, addEdit, addButton
local reviewFrame, holder, recent, refTab
local tabButtons, tabFrames = {}, {}
local controls, rowPool = {}, {}
local currentTab = "review"
local selectedBoss, selectedPull
local selectedBossName -- the selected boss's name, to find it again if its key changes
local shownBoss, shownPull, shownBase, shownOverlay
local overlayID -- the pull laid over the shown reference, by id; not saved
local raidCache = {}
local bossList -- { { key, name, label } } for the dropdown and name lookups, rebuilt on each refresh
local refsByBoss = {} -- boss key -> its references, { { key, ref, own, text } }, rebuilt with bossList
local refresh

local function settings()
    return Timeline:Settings()
end

-- A name as the lanes compare it: trimmed, curly apostrophes made plain, lowercase. The same rule
-- as trimLower in Lanes.lua.
local function nameKey(name)
    local s = tostring(name or ""):gsub("\226\128\153", "'"):gsub("\226\128\152", "'")
    return (s:gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

local function skin(frame, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, alpha or 0.5)
    frame:SetBackdropBorderColor(GRAY[1], GRAY[2], GRAY[3], 1)
end

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "CRTFontNormal")
    fs:SetText(text)
    return fs
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

-- A checkbox with its text on the right. get() is the setting, set(on) saves it.
local function checkbox(parent, x, y, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 4, y)
    cb.Label = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.Label:SetJustifyH("LEFT")
    cb.Label:SetText(text)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    cb.refresh = function()
        cb:SetChecked(get() and true or false)
    end
    controls[#controls + 1] = cb
    return cb
end

local function place(row, parent, x, y)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    controls[#controls + 1] = row
    return row
end

-- Asks in the game's own confirmation box, then runs accept.
local function confirm(text, arg, acceptText, accept)
    StaticPopup_ShowCustomGenericConfirmation({
        text = text,
        text_arg1 = arg,
        acceptText = acceptText,
        cancelText = CANCEL,
        showAlert = true,
        callback = accept,
    })
end

-- The bosses ------------------------------------------------------------------------------------

-- The bosses of the raid you are standing in, from the Encounter Journal: { { encounterID, name } }.
-- Asked out of combat only, only inside a raid, kept per instance, and empty when anything is
-- missing or fails.
local function raidBosses()
    local out = {}
    local okType, _, kind = pcall(GetInstanceInfo)
    if not okType or kind ~= "raid" then
        return out
    end
    if InCombatLockdown() or not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex and EJ_GetEncounterInfo and C_Map and C_Map.GetBestMapForUnit) then
        return out
    end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or not mapID then
        return out
    end
    local okInst, instanceID = pcall(EJ_GetInstanceForMap, mapID)
    if not okInst or not instanceID or instanceID == 0 then
        return out
    end
    if raidCache[instanceID] then
        return raidCache[instanceID]
    end
    for i = 1, 30 do
        local r = { pcall(EJ_GetEncounterInfoByIndex, i, instanceID) }
        local name, journalID = r[2], r[4]
        if not r[1] or not name or not journalID then
            break
        end
        local d = { pcall(EJ_GetEncounterInfo, journalID) }
        local encounterID = d[1] and d[8] or nil
        if type(encounterID) == "number" then
            out[#out + 1] = { encounterID = encounterID, name = name }
        end
    end
    if #out > 0 then
        raidCache[instanceID] = out
    end
    return out
end

-- Bosses with saved pulls first, then this raid's bosses that have none, then the bosses that only
-- have a reference: { { key, name, label } }, the label being the name with the pull count for a
-- boss that has pulls. Each reference goes to the boss Reference:BossKey gives it, so the boss list
-- and each boss's references use one rule. A boss added for a reference has a text key, so a later
-- reference finds it only by the same name, which is the key BossKey would give it anyway.
local function buildBossList()
    local list, seen = {}, {}
    refsByBoss = {}
    for _, boss in ipairs(Timeline:Bosses()) do
        seen[boss.encounterID] = true
        local name = boss.name ~= "" and boss.name or tostring(boss.encounterID)
        list[#list + 1] = { key = boss.encounterID, name = name, label = name .. " (" .. boss.count .. ")" }
    end
    for _, boss in ipairs(raidBosses()) do
        if not seen[boss.encounterID] then
            seen[boss.encounterID] = true
            list[#list + 1] = { key = boss.encounterID, name = boss.name, label = boss.name }
        end
    end
    for _, entry in ipairs(Reference:List()) do
        local key = Reference:BossKey(entry, list)
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { key = key, name = entry.ref.boss, label = entry.ref.boss }
        end
        refsByBoss[key] = refsByBoss[key] or {}
        table.insert(refsByBoss[key], entry)
    end
    return list
end

local function bossOptions()
    bossList = bossList or buildBossList()
    return bossList
end

-- The references of the selected boss, yours first.
local function bossRefs()
    bossOptions()
    return selectedBoss and refsByBoss[selectedBoss] or {}
end

local function findRef(key)
    for _, entry in ipairs(bossRefs()) do
        if entry.key == key then
            return entry
        end
    end
end

-- A reference is selected by its text key ("own:1", "ship:1"), a pull by its number.
local function showingReference()
    return type(selectedPull) == "string"
end

local function pullLabel(pull)
    return "Pull " .. pull.id .. DOT .. View.Format(pull.length or 0) .. DOT .. (pull.kill and "kill" or "wipe")
end

-- The boss's references first, then its recorded pulls, newest first.
local function pullOptions()
    local list = {}
    for _, entry in ipairs(bossRefs()) do
        list[#list + 1] = { key = entry.key, label = Reference.Label(entry.ref) .. (entry.own and (DOT .. "yours") or "") }
    end
    if selectedBoss then
        for _, pull in ipairs(Timeline:Pulls(selectedBoss)) do
            list[#list + 1] = { key = pull.id, label = pullLabel(pull) }
        end
    end
    return list
end

-- The name of the selected boss, from the saved pulls or this raid's list.
local function bossName()
    if not selectedBoss then
        return nil
    end
    for _, option in ipairs(bossOptions()) do
        if option.key == selectedBoss then
            return option.name
        end
    end
end

-- Keeps the selection valid: a boss that is still listed, and a reference or pull that still exists
-- (else the boss's first reference, else its newest pull). The overlay goes with a reference only.
local function fixSelection()
    local options = bossOptions()
    local found = false
    for _, option in ipairs(options) do
        if option.key == selectedBoss then
            found = true
        end
    end
    -- a boss that was listed only for its reference ("ref:name") gets a numeric key once it is
    -- pulled or you enter its raid: the same name stays selected, with its reference
    if not found and type(selectedBoss) == "string" and selectedBossName then
        for _, option in ipairs(options) do
            if type(option.key) == "number" and nameKey(option.name) == selectedBossName then
                selectedBoss, found = option.key, true
                break
            end
        end
    end
    if not found then
        selectedBoss = options[1] and options[1].key or nil
        selectedPull = nil
    end
    selectedBossName = nil
    for _, option in ipairs(options) do
        if option.key == selectedBoss then
            selectedBossName = nameKey(option.name)
        end
    end
    local valid
    if showingReference() then
        valid = findRef(selectedPull) ~= nil
    else
        valid = selectedBoss and selectedPull and Timeline:Pull(selectedBoss, selectedPull) ~= nil
    end
    if not valid then
        local refs = bossRefs()
        local pulls = selectedBoss and Timeline:Pulls(selectedBoss) or {}
        selectedPull = (refs[1] and refs[1].key) or (pulls[1] and pulls[1].id) or nil
    end
    if not showingReference() or not (overlayID and Timeline:Pull(selectedBoss, overlayID)) then
        overlayID = nil
    end
end

-- The Review tab -------------------------------------------------------------------------------

local function updateView()
    local base, sig
    if showingReference() then
        local entry = findRef(selectedPull)
        base = entry and { reference = entry.ref }
        sig = entry and entry.text -- each refresh parses afresh, so the text tells if it changed
    else
        base = selectedBoss and selectedPull and Timeline:Pull(selectedBoss, selectedPull) or nil
        sig = base
    end
    local overlay = showingReference() and overlayID and Timeline:Pull(selectedBoss, overlayID) or nil
    if sig ~= shownBase or selectedPull ~= shownPull or selectedBoss ~= shownBoss or overlay ~= shownOverlay then
        shownBase, shownPull, shownBoss, shownOverlay = sig, selectedPull, selectedBoss, overlay
        view:SetData(base, selectedBoss, overlay, bossName())
    else
        view:Refresh()
    end
    emptyLabel:SetText(selectedBoss and EMPTY_BOSS or EMPTY_ALL)
    emptyLabel:SetShown(base == nil)
    -- the Recent pulls list takes the right edge while a reference is shown
    holder:SetPoint("BOTTOMRIGHT", reviewFrame, "BOTTOMRIGHT", showingReference() and -(RECENT_W + 16) or -8, 8)
    recent:Update(showingReference() and Timeline:Pulls(selectedBoss) or {}, overlayID, showingReference())
end

local function buildReview(f)
    reviewFrame = f
    local boss = UI.Dropdown(f, "Boss", {
        options = bossOptions,
        labelWidth = 40,
        width = 230,
        get = function()
            return selectedBoss
        end,
        set = function(key)
            selectedBoss, selectedPull, overlayID = key, nil, nil
            fixSelection()
            refresh()
        end,
    })
    place(boss, f, 8, -4)
    local pulls = UI.Dropdown(f, "Pull", {
        options = pullOptions,
        labelWidth = 36,
        width = 250,
        get = function()
            return selectedPull
        end,
        set = function(key)
            selectedPull, overlayID = key, nil
            refresh()
        end,
        enabledIf = function()
            return selectedPull ~= nil
        end,
    })
    place(pulls, f, 330, -4)

    checkbox(f, 8, -38, "Record every pull", function()
        return settings().record
    end, function(on)
        Timeline:Set("record", on)
    end)
    local overlay = checkbox(f, 220, -38, "Deaths from recent pulls", function()
        return settings().overlayOn
    end, function(on)
        Timeline:Set("overlayOn", on)
    end)
    overlay.Label:SetWidth(170)
    UI.Help(f, "Deaths from recent pulls", "Draws the deaths of the pulls before this one over it, faded by how old they are, so deaths that repeat stand out. How many pulls it covers is on the Settings tab."):SetPoint("TOPLEFT", f, "TOPLEFT", 440, -40)

    unnamedHelp = UI.Help(f, "Unnamed casts", function()
        local text = "Some boss casts come from the game without a readable spell, so they are drawn in the \"Boss casts (unnamed)\" row with only their time. That is the game hiding the name, not a missing record."
        -- a reference has no casts of its own, so the hint is for recorded pulls only
        if view and view:CastCount() == 0 and selectedPull and not showingReference() then
            text = text .. "\n\nThis pull has no casts at all. The game's Boss Timeline option may be off, so no boss events arrived. Check it in the game's options."
        end
        return text
    end)
    unnamedHelp:SetPoint("TOPLEFT", f, "TOPLEFT", 470, -40)

    -- Zoom: the mouse wheel writes span without telling the page, so refresh re-reads it here.
    place(UI.Slider(f, "Time visible", {
        min = 60, max = 600, step = 30, format = View.Format,
        labelWidth = 80, width = 160,
        get = function()
            return settings().span
        end,
        set = function(value)
            Timeline:Set("span", value)
            view:SetSpan(value)
        end,
    }), f, 8, -64)

    recent = ReferencePage.Recent(f, RECENT_W, pullLabel, function(pullID)
        overlayID = overlayID ~= pullID and pullID or nil
        refresh()
    end)

    holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -96)
    holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    view = View.Create(holder)
    emptyLabel = holder:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    emptyLabel:SetPoint("CENTER", holder, "CENTER")
    emptyLabel:SetText(EMPTY_ALL)
end

-- The Settings tab -----------------------------------------------------------------------------

local GRIDS = {
    { key = 10, label = "10 seconds" },
    { key = 15, label = "15 seconds" },
    { key = 30, label = "30 seconds" },
    { key = 60, label = "1 minute" },
}
local DEATH_ROWS = {
    { key = "combined", label = "One row for everyone" },
    { key = "player", label = "A row per player" },
}

local function slider(parent, x, y, text, opts)
    opts.labelWidth, opts.width = 120, 150
    return place(UI.Slider(parent, text, opts), parent, x, y)
end

local function settingSlider(parent, x, y, text, field, low, high, step, format)
    return slider(parent, x, y, text, {
        min = low, max = high, step = step, format = format,
        get = function()
            return settings()[field]
        end,
        set = function(value)
            Timeline:Set(field, value)
        end,
    })
end

-- A reference row is hidden by its name (as the lanes read it), or by the spell the lanes give it
-- (its [spell] or its Journal match by name) when that spell is hidden. A boss with a text key
-- uses the reference's own encounter ID for the Journal, like the lanes do.
local function journalKey(entry)
    if type(selectedBoss) ~= "number" and entry and type(entry.ref.encounterID) == "number" then
        return entry.ref.encounterID
    end
    return selectedBoss
end

local function refRowHidden(row, entry)
    local mine = settings().rows and settings().rows[selectedBoss]
    local eid = journalKey(entry)
    local spellID = Lanes.RowSpell(row, eid)
    return (mine and mine.hiddenNames and mine.hiddenNames[nameKey(row.name)])
        or (spellID ~= 0 and Journal:IsHidden(eid, spellID)) or false
end

local function setRefRowHidden(row, hidden, entry)
    local all = settings().rows or {}
    settings().rows = all
    all[selectedBoss] = all[selectedBoss] or {}
    local mine = all[selectedBoss]
    mine.hiddenNames = mine.hiddenNames or {}
    mine.hiddenNames[nameKey(row.name)] = hidden or nil
    local eid = journalKey(entry)
    local spellID = Lanes.RowSpell(row, eid)
    if not hidden and spellID ~= 0 and Journal:IsHidden(eid, spellID) then
        Journal:SetHidden(eid, spellID, false)
    end
    Timeline:Fire()
end

-- The rows of the selected boss, one line each: show or hide, the name, and Remove on your own.
-- With a reference shown, they are the reference's rows instead.
local function updateRows()
    local entry = showingReference() and findRef(selectedPull)
    local rows = entry and entry.ref.rows or (selectedBoss and Journal:Rows(selectedBoss)) or {}
    -- spells of your own are added to recorded pulls only
    addEdit:SetEnabled(not entry)
    addButton:SetEnabled(not entry)
    bossLabel:SetText(selectedBoss and ("Rows for " .. (bossName() or selectedBoss)) or "Pick a boss on the Review tab")
    for i, row in ipairs(rows) do
        local line = rowPool[i]
        if not line then
            line = CreateFrame("Frame", nil, rowsChild)
            line:SetSize(300, ROW_H)
            line:SetPoint("TOPLEFT", rowsChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
            line.check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
            line.check:SetSize(22, 22)
            line.check:SetPoint("LEFT", 0, 0)
            line.text = line:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
            line.text:SetPoint("LEFT", line.check, "RIGHT", 2, 0)
            line.text:SetWidth(200)
            line.text:SetJustifyH("LEFT")
            line.text:SetWordWrap(false)
            line.remove = button(line, "Remove", 56)
            line.remove:SetPoint("RIGHT", 0, 0)
            line.check.line = line
            line.check:SetScript("OnClick", function(self)
                local l = self.line
                if l.refRow then
                    setRefRowHidden(l.refRow, not self:GetChecked(), l.refEntry)
                else
                    Journal:SetHidden(selectedBoss, l.spellID, not self:GetChecked())
                end
            end)
            line.remove:SetScript("OnClick", function()
                Journal:RemoveCustom(selectedBoss, line.spellID)
            end)
            rowPool[i] = line
            UI:SkinTree(rowsChild) -- so the Modern look skins the new Remove button
        end
        line.spellID, line.refRow, line.refEntry = row.spellID, entry and row or nil, entry or nil
        line.text:SetText(row.name or tostring(row.spellID))
        if entry then
            line.check:SetChecked(not refRowHidden(row, entry))
        else
            line.check:SetChecked(not Journal:IsHidden(selectedBoss, row.spellID))
        end
        line.remove:SetShown(not entry and row.own and true or false)
        line:Show()
    end
    for i = #rows + 1, #rowPool do
        rowPool[i]:Hide()
    end
    rowsChild:SetHeight(math.max(1, #rows * ROW_H))
end

-- Adds a spell of your own to the selected boss's rows, after checking the game knows the ID.
local function addSpell()
    local text = addEdit:GetText()
    local spellID = tonumber(text)
    if not spellID or spellID <= 0 or spellID ~= math.floor(spellID) then
        CRT:Print("Type a spell ID, a number.")
        return
    end
    if not selectedBoss then
        CRT:Print("Pick a boss on the Review tab first.")
        return
    end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if not ok or not name then
        CRT:Print("No spell with that ID.")
        return
    end
    Journal:AddCustom(selectedBoss, spellID)
    addEdit:SetText("")
    addEdit:ClearFocus()
end

local function buildSettings(f)
    -- View
    label(f, "View"):SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    UI.Help(f, "View", "How much time is visible at once (the mouse wheel over the timeline zooms too), how often the time axis is labelled, and how big the cast icons are."):SetPoint("TOPLEFT", f, "TOPLEFT", 60, -9)
    settingSlider(f, 8, -26, "Seconds visible", "span", 60, 600, 30, View.Format)
    place(UI.Dropdown(f, "Axis labels every", {
        options = GRIDS,
        labelWidth = 120,
        width = 150,
        get = function()
            return settings().grid
        end,
        set = function(key)
            Timeline:Set("grid", key)
        end,
    }), f, 8, -58)
    settingSlider(f, 8, -90, "Icon size", "iconSize", 16, 32, 1)

    -- Rows
    label(f, "Rows"):SetPoint("TOPLEFT", f, "TOPLEFT", 8, -132)
    UI.Help(f, "Rows", "The rows come from the boss's Encounter Journal abilities, then your own. Untick a row to hide it. Add a spell by its ID (the number in its Wowhead address) to track a cast the Journal does not list. The Journal is read out of combat with the Journal window closed.\n\nWith a reference shown, its own rows are listed instead, and unticking one hides it by name. Adding a spell works for recorded pulls only.\n\nA reference row gets its icon, and its match to a Journal ability, from the Encounter Journal, which is not read in combat; they can be blank until you are out of combat."):SetPoint("TOPLEFT", f, "TOPLEFT", 54, -133)
    bossLabel = label(f, "", "CRTFontSmall")
    bossLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -154)
    checkbox(f, 8, -172, "Hide rows with no casts in this pull", function()
        return settings().hideEmpty
    end, function(on)
        Timeline:Set("hideEmpty", on)
    end)
    addEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    addEdit:SetAutoFocus(false)
    addEdit:SetFontObject(CRTFontHighlight)
    addEdit:SetNumeric(true)
    addEdit:SetMaxLetters(8)
    addEdit:SetSize(90, 20)
    addEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -204)
    addEdit:SetScript("OnEnterPressed", addSpell)
    addEdit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    addButton = button(f, "Add", 50)
    addButton:SetPoint("LEFT", addEdit, "RIGHT", 8, 0)
    addButton:SetScript("OnClick", addSpell)
    label(f, "spell ID", "CRTFontSmall"):SetPoint("LEFT", addButton, "RIGHT", 8, 0)

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTimelineRowsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -232)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 330, 8)
    rowsChild = CreateFrame("Frame", nil, scroll)
    rowsChild:SetSize(300, 1)
    scroll:SetScrollChild(rowsChild)

    -- Deaths
    label(f, "Deaths"):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -8)
    UI.Help(f, "Deaths", "Whether the deaths share one row or each player gets a row, which roles to show, and whether to show only the first few deaths (0 shows all). With \"Deaths from recent pulls\" on, the overlay covers this many pulls, the shown one included."):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X + 60, -9)
    place(UI.Dropdown(f, "Death rows", {
        options = DEATH_ROWS,
        labelWidth = 120,
        width = 150,
        get = function()
            return settings().deathRows
        end,
        set = function(key)
            Timeline:Set("deathRows", key)
        end,
    }), f, RIGHT_X, -26)
    local roleX = RIGHT_X
    for _, role in ipairs({ { "TANK", "Tanks" }, { "HEALER", "Healers" }, { "DAMAGER", "Damage" } }) do
        checkbox(f, roleX, -62, role[2], function()
            return settings().roles[role[1]]
        end, function(on)
            local roles = settings().roles
            roles[role[1]] = on
            Timeline:Set("roles", roles)
        end)
        roleX = roleX + 100
    end
    settingSlider(f, RIGHT_X, -86, "First deaths only", "firstDeaths", 0, 20, 1, function(v)
        return v == 0 and "All" or tostring(v)
    end)
    settingSlider(f, RIGHT_X, -118, "Overlay pulls", "overlay", 2, 5, 1)

    -- Recording
    label(f, "Recording"):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -166)
    UI.Help(f, "Recording", "Pulls are saved on their own during raid boss fights, ten per boss, the oldest dropped first. Pulls shorter than the shortest pull are not kept."):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X + 82, -167)
    checkbox(f, RIGHT_X, -186, "Record every pull", function()
        return settings().record
    end, function(on)
        Timeline:Set("record", on)
    end)
    settingSlider(f, RIGHT_X, -212, "Shortest pull (s)", "minPull", 5, 60, 1)
    deleteButton = button(f, "Delete this boss's pulls", 180)
    deleteButton:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -254)
    deleteButton:SetScript("OnClick", function()
        local boss = selectedBoss
        if not boss then
            return
        end
        confirm("Delete every saved pull of %s?", bossName() or tostring(boss), "Delete", function()
            Timeline:DeleteBoss(boss)
        end)
    end)
    f:SetScript("OnShow", function()
        refresh()
    end)
end

-- The page -------------------------------------------------------------------------------------

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    bossList = buildBossList()
    fixSelection()
    for _, control in ipairs(controls) do
        control.refresh()
    end
    updateView()
    updateRows()
    refTab:Refresh()
    deleteButton:SetEnabled(selectedBoss ~= nil and #Timeline:Pulls(selectedBoss) > 0)
end

local function selectTab(key)
    if not tabFrames[key] then
        key = "review"
    end
    currentTab = key
    for _, tab in ipairs(TABS) do
        local on = tab.key == key
        tabFrames[tab.key]:SetShown(on)
        UI:SetTabSelected(tabButtons[tab.key], on)
    end
    if key == "review" then
        refresh() -- the hidden view did not redraw while the Settings tab was open
    end
end

local function build(pf)
    page = pf

    local title = label(pf, "Timeline", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    UI.Help(pf, "The Timeline", "Every raid boss pull is saved automatically: when the boss cast its spells and when players died. Pick a boss and a pull on the Review tab to see it as a timeline, hover for the time, scroll the mouse wheel to zoom.\n\nA reference is a boss's planned timeline. It is listed first in the pull list, and a recent pull can be laid over it. The References tab is where you paste your own.\n\nThe Settings tab has the view, which rows are shown, the deaths filters and recording."):SetPoint("LEFT", title, "RIGHT", 6, 0)

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

    buildReview(tabFrames.review)
    refTab = ReferencePage.Build(tabFrames.references, {
        selectedBoss = function()
            return selectedBoss
        end,
        bossName = bossName,
        references = bossRefs,
        refresh = function()
            refresh()
        end,
    })
    buildSettings(tabFrames.settings)

    pf:SetScript("OnShow", function()
        selectTab(currentTab)
        refresh()
    end)
    Timeline:OnChange(refresh)
end

UI:RegisterPage("timeline", "Timeline", build)
