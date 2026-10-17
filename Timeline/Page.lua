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

local TEXT = {
    shareNote = "Share note",
    shareHelp = "Sends this boss's raid note to everyone in the group with the addon, as Share to raid on Raid Notes does, with every line added or moved here. It becomes everyone's active note, and yours, so Raid Notes shows it.\n\nWhen the boss has no raid note yet, one is made first, with its EncounterID, Difficulty and Name header, and it appears on Raid Notes.\n\nOnly the raid leader or an assistant can send it to the group; anyone else (or solo) just makes it their own active note. Notes can't be sent during a boss fight.",
    noNote = "This boss has no encounter ID yet, so no raid note can be made for it.",
    made = "Made a raid note for %s. It is on Raid Notes.",
}

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
local shareButton, shareHelp
local tabButtons, tabFrames = {}, {}
local controls, rowPool = {}, {}
local currentTab = "review"
local selectedBoss, selectedPull
local selectedBossName -- the selected boss's name, to find it again if its key changes
local shownBoss, shownPull, shownBase, shownOverlay
local overlayID -- the pull laid over the shown reference, by id; not saved
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
    for _, boss in ipairs(Journal:RaidBosses()) do
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
-- asks the Journal under the same id the lanes use (Journal:ResolveID).
local function journalKey(entry)
    if type(selectedBoss) ~= "number" and entry then
        return Journal:ResolveID(selectedBoss, entry.ref) or selectedBoss
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

-- The pop-out window -----------------------------------------------------------------------------
-- Pop out moves the whole Review tab (the boss and pull choices, the zoom and the view) into a
-- window of its own that can be dragged to any size, for a wider view than the main panel allows.
-- The Review tab then shows a note and a button to bring it back, and closing the window (its X,
-- Escape or Dock) puts it back. Its size and position are saved in timeline.popout.

local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber"
local MIN_W, MIN_H = 760, 360
local popWin, popButton, dockedNote
local popped = false

local function popSettings()
    local s = settings()
    s.popout = s.popout or { width = 1200, height = 600 }
    return s.popout
end

local function placePopout()
    local p = popSettings()
    popWin:ClearAllPoints()
    if p.point then
        popWin:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
    else
        popWin:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    popWin:SetSize(math.max(MIN_W, p.width or 1200), math.max(MIN_H, p.height or 600))
end

-- The window's colours follow the Modern or Classic look.
local function stylePopout()
    if UI:IsModern() then
        local c, e = CRT.MOCHA.espresso, CRT.MOCHA.edge
        popWin:SetBackdropColor(c[1], c[2], c[3], 0.96)
        popWin:SetBackdropBorderColor(e[1], e[2], e[3], 1)
    else
        popWin:SetBackdropColor(0, 0, 0, 0.9)
        popWin:SetBackdropBorderColor(GRAY[1], GRAY[2], GRAY[3], 1)
    end
end

local dock

local function buildPopout()
    if popWin then
        return
    end
    popWin = CreateFrame("Frame", "CowfeeRaidToolsTimelineWindow", UIParent, "BackdropTemplate")
    popWin:SetBackdrop(BACKDROP)
    popWin:SetClampedToScreen(true)
    popWin:SetMovable(true)
    popWin:SetResizable(true)
    if popWin.SetResizeBounds then
        popWin:SetResizeBounds(MIN_W, MIN_H)
    end
    popWin:EnableMouse(true)
    UI:RegisterLayer("timeline", popWin)
    tinsert(UISpecialFrames, "CowfeeRaidToolsTimelineWindow")

    -- The header: drag it to move the window.
    local header = CreateFrame("Frame", nil, popWin)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(24)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(1, 1, 1, 0.05)
    local title = label(header, "Timeline", "CRTFontNormal")
    title:SetPoint("LEFT", 8, 0)
    local function save()
        local point, _, relativePoint, x, y = popWin:GetPoint()
        local p = popSettings()
        p.point, p.relativePoint, p.x, p.y = point, relativePoint, x, y
        p.width = math.floor(popWin:GetWidth() + 0.5)
        p.height = math.floor(popWin:GetHeight() + 0.5)
    end
    header:SetScript("OnDragStart", function()
        popWin:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        popWin:StopMovingOrSizing()
        save()
    end)

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -1, 0)
    UI:SkinCloseButton(close)
    close:SetScript("OnClick", function()
        popWin:Hide()
    end)
    local reset = UI.ResetButton(header, function()
        local p = popSettings()
        p.point, p.relativePoint, p.x, p.y = nil, nil, nil, nil
        p.width, p.height = 1200, 600
        placePopout()
    end)
    reset:SetPoint("RIGHT", close, "LEFT", -4, 0)

    popWin.content = CreateFrame("Frame", nil, popWin)
    popWin.content:SetPoint("TOPLEFT", 4, -30)
    popWin.content:SetPoint("BOTTOMRIGHT", -4, 18)

    local grip = CreateFrame("Button", nil, popWin)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture(GRIP .. "-Up")
    grip:SetHighlightTexture(GRIP .. "-Highlight")
    grip:SetPushedTexture(GRIP .. "-Down")
    grip:SetScript("OnMouseDown", function()
        popWin:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        popWin:StopMovingOrSizing()
        save()
    end)

    -- Closing the window, however it closes, puts the Review tab back.
    popWin:SetScript("OnHide", function()
        if popped then
            dock()
        end
    end)
    popWin:Hide()
end

-- Puts the Review tab back on the page.
dock = function()
    popped = false
    reviewFrame:SetParent(tabFrames.review)
    reviewFrame:ClearAllPoints()
    reviewFrame:SetAllPoints(tabFrames.review)
    reviewFrame:Show()
    dockedNote:Hide()
    popButton:SetText("Pop out")
    if popWin and popWin:IsShown() then
        popWin:Hide()
    end
    refresh()
end

-- Moves the Review tab into the pop-out window.
local function popOut()
    buildPopout()
    popped = true
    placePopout()
    stylePopout()
    popWin:SetScale(UI:Scale() / 100)
    reviewFrame:SetParent(popWin.content)
    reviewFrame:ClearAllPoints()
    reviewFrame:SetAllPoints(popWin.content)
    reviewFrame:Show()
    dockedNote:Show()
    popButton:SetText("Dock")
    popWin:Show()
    UI:SkinTree(popWin)
    refresh()
end

local function togglePopout()
    if popped then
        dock()
    else
        popOut()
    end
end

-- The difficulty name of what is shown: a reference's Difficulty line, or a recorded pull's
-- difficulty as the game names it ("Mythic", "Heroic"). Nil when neither says.
local function shownDifficulty()
    local base = view and view.pull
    if not base then
        return nil
    end
    if base.reference then
        return base.reference.difficulty
    end
    if type(base.difficultyID) == "number" and GetDifficultyInfo then
        local ok, name = pcall(GetDifficultyInfo, base.difficultyID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

-- The shown boss's encounter ID, or nil when no boss with a known ID is shown.
local function shownEncounter()
    return view and view.EncounterNumber and view:EncounterNumber() or nil
end

-- Shown whenever a boss with a known encounter ID is on the timeline: Share note makes or finds its
-- raid note, so it works before the boss has a note, and solo (the note then only becomes yours).
local function updateShare()
    if shareButton then
        local on = shownEncounter() ~= nil and CRT.Notes ~= nil and CRT.NoteComm ~= nil
        shareButton:SetShown(on)
        shareHelp:SetShown(on)
    end
end

-- Share note: the note a pull of the shown boss and difficulty reads (Notes:NoteFor, the same note
-- the timeline's lines are written to), made with its header when the boss has no note at all, then
-- shared as Share to raid does. Sharing makes it the active note, so Raid Notes shows it.
local function shareNote()
    local encounterID = shownEncounter()
    if not encounterID then
        return
    end
    local id, made = CRT.Notes:NoteFor(encounterID, shownDifficulty(), bossName())
    if not id then
        CRT:Print(TEXT.noNote)
        return
    end
    if made then
        local record = CRT.Notes:Get(id)
        CRT:Print(string.format(TEXT.made, (record and record.name) or "the boss"))
    end
    CRT.NoteComm:Share(id)
end

-- The Pop out button on the Review tab, and the note left on the tab while it is popped out.
local function buildPopControls()
    popButton = button(reviewFrame, "Pop out", 90)
    popButton:SetPoint("TOPRIGHT", reviewFrame, "TOPRIGHT", -8, -38)
    popButton:SetScript("OnClick", togglePopout)
    UI.Help(reviewFrame, "Pop out", "Moves the timeline into a window of its own that you can drag to any size, for a wider view. Drag its title to move it and its corner to resize it.\n\nDock, the window's X or Escape puts it back here."):SetPoint("RIGHT", popButton, "LEFT", -2, 0)

    -- Share note: see shareNote above.
    shareButton = button(reviewFrame, TEXT.shareNote, 90)
    shareButton:SetPoint("TOPRIGHT", reviewFrame, "TOPRIGHT", -8, -66)
    shareButton:SetScript("OnClick", shareNote)
    shareHelp = UI.Help(reviewFrame, TEXT.shareNote, TEXT.shareHelp)
    shareHelp:SetPoint("RIGHT", shareButton, "LEFT", -2, 0)
    shareButton:Hide()
    shareHelp:Hide()

    dockedNote = CreateFrame("Frame", nil, tabFrames.review)
    dockedNote:SetAllPoints(tabFrames.review)
    local text = label(dockedNote, "The timeline is in its own window.", "CRTFontNormal")
    text:SetPoint("CENTER", 0, 20)
    local back = button(dockedNote, "Bring it back", 130)
    back:SetPoint("TOP", text, "BOTTOM", 0, -12)
    back:SetScript("OnClick", dock)
    dockedNote:Hide()
end

-- /crt timeline pop: opens the Timeline page and pops the Review tab out.
function CRT.TimelinePopout()
    UI:Show("timeline")
    if not popped then
        popOut()
    end
end

-- The page -------------------------------------------------------------------------------------

refresh = function()
    if not page or not (page:IsShown() or (popped and popWin:IsShown())) then
        return
    end
    bossList = buildBossList()
    fixSelection()
    for _, control in ipairs(controls) do
        control.refresh()
    end
    updateView()
    updateShare()
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
    UI.Help(pf, "The Timeline", "Every raid boss pull is saved automatically: when the boss cast its spells and when players died. Pick a boss and a pull on the Review tab to see it as a timeline, hover for the time, scroll the mouse wheel to zoom, hold the right mouse button and drag to move left and right, and use Shift with the mouse wheel to scroll the rows.\n\nA reference is a boss's planned timeline. It is listed first in the pull list, and a recent pull can be laid over it. The References tab is where you paste your own.\n\nThe Settings tab has the view, which rows are shown, the deaths filters and recording.\n\nA reference row's color says what the ability is (a dot on the row's name for each extra type):\n" .. CRT.TimelineReference.Legend()):SetPoint("LEFT", title, "RIGHT", 6, 0)

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

    -- The Review tab's content sits in a frame of its own, so Pop out can move it to its window.
    local review = CreateFrame("Frame", nil, tabFrames.review)
    review:SetAllPoints(tabFrames.review)
    buildReview(review)
    buildPopControls()
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
    if CRT.Notes and CRT.Notes.OnChange then
        CRT.Notes:OnChange(refresh) -- a note shared, edited or deleted
    end
end

UI:RegisterPage("timeline", "Timeline", build)
