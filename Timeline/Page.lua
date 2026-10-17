local ADDON, CRT = ...

-- The Timeline page, with three tabs: Review (Timeline/ReviewTab.lua: pick a boss and one of its
-- references or saved pulls, see it drawn by the timeline view), References (Timeline/ReferencePage.lua: paste, edit
-- and delete reference timelines) and Settings (Timeline/SettingsTab.lua: the view, which rows to
-- show, the deaths, and recording). Every control writes through Timeline:Set or the Journal's
-- setters, and the page redraws when either tells it something changed. The boss list is the boss
-- library's bosses in the raid route (CRT.Bosses:Options), headed by raid, so a boss can be opened
-- before its first pull; a boss outside the library is not listed. With a reference shown, the
-- Recent pulls list beside it lays one of the boss's pulls over it; that choice is not saved. The
-- Difficulty dropdown picks Normal/Heroic or Mythic, and every list shows only that group. The
-- difficulty, boss and reference or pull shown are saved in timeline.lastView, so the page opens on
-- them again, after a reload too.

local Timeline = CRT.Timeline
local View = CRT.TimelineView
local Reference = CRT.TimelineReference
local ReferencePage = CRT.TimelineReferencePage
local ReviewTab = CRT.TimelineReviewTab
local SettingsTab = CRT.TimelineSettingsTab
local UI = CRT.UI

local RECENT_W = ReviewTab.RECENT_W
local DOT = " \194\183 "
local EMPTY_BOSS = "No pulls recorded for this boss yet"
local EMPTY_ALL = "No boss pulls recorded yet"

local TEXT = {
    shareNote = "Share note",
    shareHelp = "Sends this boss's raid note to everyone in the group with the addon, as Share to raid on Raid Notes does, with every line added or moved here. It becomes everyone's active note, and yours, so Raid Notes shows it.\n\nWhen the boss has no raid note yet, one is made first, with its EncounterID, Difficulty and Name header, and it appears on Raid Notes.\n\nOnly the raid leader or an assistant can send it to the group; anyone else (or solo) just makes it their own active note. Notes can't be sent during a boss fight.",
    noNote = "This boss has no encounter ID yet, so no raid note can be made for it.",
    made = "Made a raid note for %s. It is on Raid Notes.",
    phaseCopy = "Moved the phase line in a reference of your own (shipped references never change). It is listed as yours.",
}

local GRAY = { 0.35, 0.35, 0.35 }
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local GROUPS = Timeline.GROUP_NAMES

local TABS = {
    { key = "review", label = "Review" },
    { key = "references", label = "References" },
    { key = "settings", label = "Settings" },
}

local page, view, emptyLabel, unnamedHelp
local reviewFrame, holder, recent, refTab, settingsTab
local shareButton, shareHelp
local tabButtons, tabFrames = {}, {}
local controls = {} -- the Review tab's controls, which refresh() redraws
local currentTab = "review"
local selectedBoss, selectedPull
local selectedGroup = "nh" -- "nh" or "mythic": which difficulty the page shows
local shownBoss, shownPull, shownBase, shownOverlay, shownGroup
local overlayID -- the pull laid over the shown reference, by id; not saved
local bossList -- { { key, name, label } } for the dropdown and name lookups, rebuilt on each refresh
local refsByBoss = {} -- boss key -> its references, { { key, ref, own, text } }, rebuilt with bossList
local refresh

local function settings()
    return Timeline:Settings()
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

-- The bosses ------------------------------------------------------------------------------------

-- The boss library's bosses in the raid route (CRT.Bosses:Options: a heading per raid, then its
-- bosses, never re-sorted here): { { key, name, label } }, the label being the name with the pull
-- count on the shown difficulty, and a heading { key = "raid:...", label, title = true }. A boss that
-- is not in the library is not listed, even with saved pulls (they stay saved). Each reference goes
-- to the boss Reference:BossKey gives it; one for a boss that is not listed is left out too.
local function buildBossList()
    local list, bosses = {}, {}
    refsByBoss = {}
    local counts = {}
    for _, boss in ipairs(Timeline:Bosses(selectedGroup)) do
        counts[boss.encounterID] = boss.count
    end
    for _, option in ipairs(CRT.Bosses:Options()) do
        if option.title then
            list[#list + 1] = option
        else
            local count = counts[option.key] or 0
            local entry = { key = option.key, name = option.label, label = count > 0 and (option.label .. " (" .. count .. ")") or option.label }
            list[#list + 1] = entry
            bosses[#bosses + 1] = entry
        end
    end
    for _, entry in ipairs(Reference:ForGroup(Reference:List(), selectedGroup)) do
        local key = Reference:BossKey(entry, bosses)
        if type(key) == "number" then
            refsByBoss[key] = refsByBoss[key] or {}
            table.insert(refsByBoss[key], entry)
        end
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

-- The game's name for a difficultyID ("Mythic", "Heroic"), or nil when the game gives none.
local function gameDifficultyName(difficultyID)
    if type(difficultyID) == "number" and GetDifficultyInfo then
        local ok, name = pcall(GetDifficultyInfo, difficultyID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

-- The game's name for a pull's difficulty, else the name of its group.
local function difficultyName(pull)
    return gameDifficultyName(pull.difficultyID) or GROUPS[Timeline.DifficultyGroup(pull.difficultyID)]
end

local function pullLabel(pull)
    return "Pull " .. pull.id .. DOT .. View.Format(pull.length or 0) .. DOT .. (pull.kill and "kill" or "wipe") .. DOT .. difficultyName(pull)
end

-- A pull belongs to the shown difficulty group.
local function inGroup(pull)
    return Timeline.DifficultyGroup(pull.difficultyID) == selectedGroup
end

-- The boss's references first, then its recorded pulls, newest first.
local function pullOptions()
    local list = {}
    for _, entry in ipairs(bossRefs()) do
        list[#list + 1] = { key = entry.key, label = Reference.Label(entry.ref) .. (entry.own and (DOT .. "yours") or "") }
    end
    if selectedBoss then
        for _, pull in ipairs(Timeline:Pulls(selectedBoss, selectedGroup)) do
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
        if not option.title and option.key == selectedBoss then
            found = true
        end
    end
    if not found then
        selectedBoss = CRT.Bosses.FirstKey(options)
        selectedPull = nil
    end
    local valid
    if showingReference() then
        valid = findRef(selectedPull) ~= nil
    else
        local pull = selectedBoss and selectedPull and Timeline:Pull(selectedBoss, selectedPull)
        valid = pull ~= nil and inGroup(pull)
    end
    if not valid then
        local refs = bossRefs()
        local pulls = selectedBoss and Timeline:Pulls(selectedBoss, selectedGroup) or {}
        selectedPull = (refs[1] and refs[1].key) or (pulls[1] and pulls[1].id) or nil
    end
    if not showingReference() or not (overlayID and Timeline:Pull(selectedBoss, overlayID)) then
        overlayID = nil
    end
end

-- The Review tab -------------------------------------------------------------------------------

-- The shown reference, when it has an Order line, and the boss its chosen order is saved under.
local function orderedRef()
    local entry = showingReference() and findRef(selectedPull)
    if entry and entry.ref.order then
        return entry.ref, entry.ref.encounterID or selectedBoss
    end
end

-- The chosen order of the shown reference's parts (a list), or nil with no Order line.
local function chosenOrder()
    local ref, boss = orderedRef()
    return ref and Reference.ResolveOrder(ref, Timeline:Order(boss, selectedGroup))
end

local function orderOptions()
    local list = {}
    local ref = orderedRef()
    for i, parts in ipairs(ref and Reference.Orders(ref) or {}) do
        local key = Reference.OrderKey(parts)
        list[#list + 1] = { key = key, label = key .. (i == 1 and " (as written)" or "") }
    end
    return list
end

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
    view:SetOrder(chosenOrder())
    if sig ~= shownBase or selectedPull ~= shownPull or selectedBoss ~= shownBoss or overlay ~= shownOverlay or selectedGroup ~= shownGroup then
        shownBase, shownPull, shownBoss, shownOverlay, shownGroup = sig, selectedPull, selectedBoss, overlay, selectedGroup
        view:SetData(base, selectedBoss, overlay, bossName(), selectedGroup)
    else
        view:Refresh()
    end
    emptyLabel:SetText(selectedBoss and EMPTY_BOSS or EMPTY_ALL)
    emptyLabel:SetShown(base == nil)
    -- the Recent pulls list takes the right edge while a reference is shown
    holder:SetPoint("BOTTOMRIGHT", reviewFrame, "BOTTOMRIGHT", showingReference() and -(RECENT_W + 16) or -8, 8)
    recent:Update(showingReference() and Timeline:Pulls(selectedBoss, selectedGroup) or {}, overlayID, showingReference())
end

local function buildReview(f)
    reviewFrame = f
    local tab = ReviewTab.Build(f, {
        groups = GROUPS,
        group = function()
            return selectedGroup
        end,
        boss = function()
            return selectedBoss
        end,
        pull = function()
            return selectedPull
        end,
        -- Switching difficulty drops the overlay and repairs the selection.
        selectGroup = function(key)
            selectedGroup, overlayID, bossList = key, nil, nil
            fixSelection()
            refresh()
        end,
        selectBoss = function(key)
            selectedBoss, selectedPull, overlayID = key, nil, nil
            fixSelection()
            refresh()
        end,
        selectPull = function(key)
            selectedPull, overlayID = key, nil
            refresh()
        end,
        toggleOverlay = function(pullID)
            overlayID = overlayID ~= pullID and pullID or nil
            refresh()
        end,
        -- A phase line moved (or put back) on the timeline is written into the shown reference. A
        -- shipped reference is never changed: the move makes a reference of your own, which is then
        -- shown.
        movePhase = function(index, seconds)
            if type(selectedPull) ~= "string" then
                return
            end
            local key, copied = Reference:MovePhase(selectedPull, index, seconds)
            if key then
                selectedPull = key
                if copied then
                    CRT:Print(TEXT.phaseCopy)
                end
            end
            refresh()
        end,
        -- the raid's order of the shown reference's parts, kept per boss and difficulty
        order = function()
            local parts = chosenOrder()
            return parts and Reference.OrderKey(parts)
        end,
        hasOrder = function()
            return orderedRef() ~= nil
        end,
        selectOrder = function(key)
            local ref, boss = orderedRef()
            if ref then
                -- the written order is kept as no choice, so a changed reference starts from it again
                Timeline:SetOrder(boss, selectedGroup, key ~= Reference.OrderKey(ref.order.parts) and key or nil)
            end
        end,
        orderOptions = orderOptions,
        bossOptions = bossOptions,
        pullOptions = pullOptions,
        pullLabel = pullLabel,
        showingReference = showingReference,
    })
    view, holder, recent, emptyLabel, unnamedHelp, controls = tab.view, tab.holder, tab.recent, tab.emptyLabel, tab.unnamedHelp, tab.controls
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
local returnPage -- the page Show on the Timeline came from, shown again when the pop-out is closed

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
        popWin:StartMoving(true)
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

    -- Closing the window, however it closes, puts the Review tab back, and ends a Show on the
    -- Timeline's light. Opened by Show on the Timeline, the main window goes back to the page it
    -- came from (Raid Notes on its Mech Alerts tab); the Dock button stays on the Timeline.
    popWin:SetScript("OnHide", function()
        if view then
            view:ClearHighlight()
        end
        local back = returnPage
        returnPage = nil
        if popped then
            dock()
        end
        if back then
            UI:SelectPage(back)
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
    returnPage = nil
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
    return gameDifficultyName(base.difficultyID)
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
        -- no boss: Share sends the Empty note (Notes/Comm.lua)
        CRT.NoteComm:Share(nil)
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

-- "Show on the Timeline": opens the pop-out on a boss (by encounter ID) with its reference, or else
-- its newest pull, and lights the row of a spell there: spell is a spellID or an ability's name, and
-- name (optional) is tried when no row has that spellID. The boss is
-- looked for on the shown difficulty first, then on the other one. Returns true when the row is
-- shown, false when the boss or the row is not.
local function bossKeyFor(encounterID)
    for _, option in ipairs(bossOptions()) do
        local refs = refsByBoss[option.key] or {}
        local match = option.key == encounterID
        for _, entry in ipairs(refs) do
            match = match or entry.ref.encounterID == encounterID
        end
        -- listed with something to show on this difficulty: a reference or a pull
        if match and (refs[1] or (type(option.key) == "number" and Timeline:Pulls(option.key, selectedGroup)[1])) then
            return option.key
        end
    end
end

function Timeline:ShowRow(encounterID, spell, name)
    if not (popped and popWin:IsShown()) and CRT.db.lastPage ~= "timeline" then
        returnPage = CRT.db.lastPage
    end
    CRT.TimelinePopout()
    local key, before = nil, selectedGroup
    for _, group in ipairs({ before, before == "nh" and "mythic" or "nh" }) do
        selectedGroup, bossList = group, nil
        key = bossKeyFor(encounterID)
        if key then
            break
        end
    end
    if not key then
        selectedGroup, bossList = before, nil
        refresh()
        return false
    end
    if key ~= selectedBoss or selectedGroup ~= before then
        selectedBoss, selectedPull, overlayID = key, nil, nil
    end
    refresh()
    if not view then
        return false
    end
    local spellID = type(spell) == "number" and spell or nil
    return view:Highlight(spellID, type(spell) == "string" and spell or name)
end

-- The page -------------------------------------------------------------------------------------

refresh = function()
    if not page or not (page:IsShown() or (popped and popWin:IsShown())) then
        return
    end
    bossList = buildBossList()
    fixSelection()
    -- what is shown is kept, so the page (and a reload) opens on it again
    settings().lastView = { group = selectedGroup, boss = selectedBoss, pull = selectedPull }
    for _, control in ipairs(controls) do
        control.refresh()
    end
    updateView()
    updateShare()
    settingsTab:Refresh()
    refTab:Refresh()
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
    UI.Help(pf, "The Timeline", "Every raid boss pull is saved automatically: when the boss cast its spells and when players died. Pick a boss and a pull on the Review tab to see it as a timeline, hover for the time, scroll the mouse wheel to zoom, hold the right mouse button and drag to move left and right, and use Shift with the mouse wheel to scroll the rows.\n\nA reference is a boss's planned timeline. It is listed first in the pull list, and a recent pull can be laid over it. The References tab is where you paste your own.\n\nThe red lines are phase changes. Hold Shift and drag one to move it: that phase's casts and note lines move with it, and the phase before it hides whatever would now come after the line (they come back when you move it back). Right-click a moved line to put it back. A move is saved in the reference; a shipped reference becomes one of your own.\n\nThe Settings tab has the view, which rows are shown, the deaths filters and recording.\n\nA reference row's color says what the ability is (a dot on the row's name for each extra type):\n" .. CRT.TimelineReference.Legend()):SetPoint("LEFT", title, "RIGHT", 6, 0)

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
        difficulty = function()
            return selectedGroup
        end,
        references = bossRefs,
        refresh = function()
            refresh()
        end,
    })
    settingsTab = SettingsTab.Build(tabFrames.settings, {
        selectedBoss = function()
            return selectedBoss
        end,
        bossName = bossName,
        showingReference = showingReference,
        shownReference = function()
            return showingReference() and findRef(selectedPull) or nil
        end,
        refresh = function()
            refresh()
        end,
    })

    -- open on the difficulty, boss and reference or pull last shown; fixSelection falls back when
    -- the boss or pull is gone (the boss's reference, else its newest pull)
    local last = settings().lastView
    if type(last) == "table" then
        selectedGroup = (last.group == "mythic") and "mythic" or "nh"
        selectedBoss, selectedPull = last.boss, last.pull
    end

    pf:SetScript("OnShow", function()
        selectTab(currentTab)
        refresh()
    end)
    Timeline:OnChange(refresh)
    CRT.Bosses:OnRouteChange(refresh) -- the raid route, the boss list's order
    if CRT.Notes and CRT.Notes.OnChange then
        CRT.Notes:OnChange(refresh) -- a note shared, edited or deleted
    end
end

UI:RegisterPage("timeline", "Timeline", build)
