local ADDON, CRT = ...

-- Timeline: the canvas that draws one saved pull. Each lane is a row: the deaths first (one row,
-- or one per player), then the boss's ability rows with their casts, then "Boss casts (unnamed)"
-- for casts whose spell could not be read or has no row. A fixed column on the left holds the
-- lane names; the track to its right scrolls sideways under a time axis and up and down with the
-- lane names. The mouse wheel over the track zooms around the cursor (with Shift it scrolls the
-- lanes), dragging the track or its bar scrolls it, and hovering shows the time under the cursor.
-- Icons come from a pool and are reused on every refresh, since frames cannot be deleted. With the
-- overlay on, deaths from the pulls before the shown one are drawn faded by how old they are.
-- A reference timeline is drawn the same way, plus its phase lines and labels, a bar behind each
-- cast that lasts a while, a thin line before each cast that has a lead time, and the row names in
-- their own colors. A pull laid over a reference adds its deaths, a row of small ticks for its
-- casts and a line where it ended. Bars, lines and ticks come from pools like the icons.
-- The page builds one with View.Create(parent) and hands it a pull or { reference = ref }, and an
-- optional pull to lay over it, with view:SetData.
-- Two left clicks on the track (not on an icon or a marker) drop a new alert there: the editor opens
-- with the row's spell and the clicked time as phase + seconds. Every saved note line and reminder of
-- the boss is drawn as a small flag on its spell's row, or on a "Notes" row added at the bottom for
-- the ones with no row; a double-click on a flag opens it in the editor.
-- Along the bottom, a strip holds a chip for each template (CRT.AlertSaved) and a "+" chip that makes
-- one. Dragging a chip onto the track opens the editor on a new alert from it at that time (taking the
-- spell of a cast icon it is dropped on); right-clicking a chip edits, renames or deletes it. Under it a
-- Cooldowns row lists healer cooldowns and raid defensives (CRT.AlertCooldowns, filtered by its
-- dropdown): dragged the same way, one opens a new alert of your own with its spell; right-clicked, it
-- can be saved as a template. A right click on the track that doesn't move opens a menu there: New
-- alert here, or Place a template or a cooldown.

local View = {}
CRT.TimelineView = View

local LABEL_W = 150 -- the lane name column
local ROW_H = 30
local AXIS_H = 20
local PHASE_ROW_H = 12 -- each row of phase labels above the time labels
local PHASE_ROWS = 2 -- phase labels stagger over at most this many rows
local BAR_H = 10 -- the sideways scroll bar
local UNKNOWN_H = 16 -- the "Time unknown" line under the lanes
local SCROLLBAR_W = 24 -- room for the lanes' up and down scroll bar
local MIN_SPAN, MAX_SPAN = 60, 600
local ZOOM = 1.25
local TICK_GAP = 40 -- the fewest pixels between two axis labels
local DEATH_RED = { 0.89, 0.29, 0.29 } -- also the phase lines
local LEAD_GREEN = { 0.72, 0.88, 0.72 }
local DUR_H = 18 -- the height of a duration bar
local BAR_ALPHA = 0.45
local TINT_ALPHA = 0.08 -- a reference row's background, in its type's color
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a white circle, colored per type
local DOT_SIZE = 8
local MAX_DOTS = 3
local TICK_W, TICK_H = 3, 10 -- one cast of an overlaid pull
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local UNNAMED_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local NOTES_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local PERSONAL_ICON = "Interface\\Icons\\INV_Misc_Note_02"
local FLAG_W, FLAG_HEAD = 12, 14 -- a marker's flag, drawn on a pole as tall as the row less 6 px
local FLAG_BTN_W = 20 -- the clickable marker: a square at the row top, the flag centred in it
local DOUBLE_TIME, DOUBLE_DIST = 0.3, 6 -- two clicks on the track this close make a double-click
local MOVE_DIST = 4 -- a flag held and moved less than this many pixels is a click, not a drag
local STRIP_ROW = 26 -- one row of the strip under the scroll bar: the templates, then the cooldowns
local STRIP_H = STRIP_ROW * 2
local CHIP_H, CHIP_ICON, CHIP_EDGE, CHIP_GAP = 20, 16, 3, 4
local CHIP_NAME_MAX = 160 -- a longer name is cut short on its chip
local PLUS_W = 22
local CHIP_WHEEL = 40 -- pixels the chips scroll per mouse wheel notch
local MENU_DIST, MENU_TIME = 6, 0.3 -- a right click that moves less and lets go sooner opens the menu
local DASH, DASH_GAP = 6, 4 -- the dashed line where a dragged chip would land
local RENAME_POPUP = "COWFEE_RAID_TOOLS_SAVED_ALERT_RENAME"
local CD_DROP_W = 120 -- the Cooldowns row's filter dropdown

local TEXT = {
    notes = "Notes",
    personal = "Personal notes",
    personalHelp = "Your personal reminders (Save as: Only me). These are only yours: they stay on your PC and are "
        .. "never shared with the raid.\n\nDouble-click this row, or drop a template on it, to make one. Drag one "
        .. "to change its time; Alt+drag adds a time.",
    view = "View",
    everyone = "Everyone",
    noOne = "No one (timers window only)",
    onlyMe = "Only me",
    raidNote = "Raid note",
    raidNoteOf = "Raid note (%s)",
    yourReminder = "Your reminder",
    reminder = "Reminder",
    spell = "Spell %d",
    needPull = "Reminders need the boss pulled once, or its reference to have an Encounter line.",
    moveTo = "Move to %s",
    addTime = "Alt \194\183 add a time %s",
    moveRefused = "That alert changed since you grabbed it; nothing was moved.",
    savedAlerts = "Templates",
    savedHelp = "Your templates: an alert's setup without its time. Drag one onto the timeline to make an "
        .. "alert there (dropped on a boss spell's icon it takes that spell). Right-click one to edit, rename or "
        .. "delete it; + makes a new one. \"Save As Template\" in the alert editor makes one too.\n\n"
        .. "Right-click the timeline (without dragging) for New alert here, or Place a template at that time.",
    newSaved = "New template",
    savedHint = "Drag onto the timeline to place it. Right-click to edit, rename or delete.",
    shows = "Shows: %s",
    showsNothing = "Shows nothing",
    readOut = "read out",
    outputs = { alert = "Alert", text = "Text", icon = "Icon", bar = "Bar", circle = "Circle" },
    raidNoteFor = "Raid note for %s",
    placeAt = "Place at %s",
    edit = "Edit",
    rename = "Rename",
    delete = DELETE or "Delete",
    cancel = CANCEL or "Cancel",
    accept = ACCEPT or "Accept",
    renamePrompt = "Rename this template:",
    deleteConfirm = "Delete the template \"%s\"?",
    newHere = "New alert here",
    place = "Place",
    noSaved = "No templates yet",
    unnamed = "Template",
    noMenu = "This game version has no right-click menus for this.",
    deleteRefused = "That alert changed since you opened its menu; nothing was deleted.",
    deleteNote = "Delete this raid note line?\n\n%s",
    deleteTime = "Delete this time of \"%s\"? Its other times stay.",
    deleteReminder = "Delete your reminder \"%s\"?",
    cooldowns = "Cooldowns",
    cooldownsHelp = "Healer cooldowns and raid defensives. Drag one onto the timeline to make an alert with its "
        .. "spell there (your own, Only me). Right-click one to save it as a template.\n\n"
        .. "The dropdown picks which ones are listed: your class (healer cooldowns when your class has none), "
        .. "all of them, the healer cooldowns, the raid defensives, or one class.",
    cooldownHint = "Drag onto the timeline to make an alert",
    saveTemplate = "Save as template",
    noCooldowns = "No cooldowns",
}

local function settings()
    return CRT.Timeline:Settings()
end

local function mocha(key, alpha)
    local c = CRT.MOCHA[key]
    return c[1], c[2], c[3], alpha or 1
end

local function clampSpan(seconds)
    seconds = tonumber(seconds) or 300
    return math.max(MIN_SPAN, math.min(MAX_SPAN, math.floor(seconds + 0.5)))
end

-- Pure helpers -------------------------------------------------------------------------------------

-- The seconds to label on an axis: multiples of grid from 0 to span, with the step doubled until
-- neighbors are at least TICK_GAP pixels apart at this width.
function View.Ticks(span, grid, width)
    local list = {}
    if not span or span <= 0 or not width or width <= 0 then
        return list
    end
    local step = (grid and grid > 0) and grid or 30
    local perSecond = width / span
    while step * perSecond < TICK_GAP do
        step = step * 2
    end
    local s = 0
    while s <= span do
        list[#list + 1] = s
        s = s + step
    end
    return list
end

function View.TimeToX(t, span, width)
    -- t * width / span rather than t / span * width, so whole seconds land on whole pixels
    return t * width / span
end

-- The reverse of TimeToX: the time at x pixels.
function View.XToTime(x, span, width)
    return x * span / width
end

-- t to the nearest tenth of a second.
local function tenth(t)
    return math.floor(t * 10 + 0.5) / 10
end

function View.Format(t)
    t = math.max(0, math.floor(t or 0))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

-- The lanes come from Timeline/Lanes.lua; the old name stays so the callers and tests keep working.
View.Lanes = CRT.TimelineLanes.Build

-- Tooltips -----------------------------------------------------------------------------------------

local function hideTip()
    GameTooltip:Hide()
end

local function spellName(spellID)
    if type(spellID) == "number" and spellID > 0 then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" then
            return name
        end
    end
end

-- Shows a spell's tooltip; when the game refuses (or the spell is unknown) the name stands in as a
-- gold title, so the lines added after it still have a title above them.
local function spellTip(spellID, fallback)
    local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, spellID)
    if not ok then
        GameTooltip:SetText(fallback or "Unknown", 1, 0.82, 0)
    end
end

-- The type lines of a reference ability ("Soak", "Mythic only"), each in its type's color.
local function addTypes(lane)
    local Reference = CRT.TimelineReference
    for _, key in ipairs(lane.types or {}) do
        local t = Reference and Reference.TYPES[key]
        if t then
            GameTooltip:AddLine(t.label, t.color[1], t.color[2], t.color[3])
        end
    end
end

local function iconEnter(b)
    local mark, lane = b.mark, b.lane
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if mark.death then
        local d = mark.death
        GameTooltip:SetText(d.name or "Unknown", CRT.Groups.ClassColor(d.name, d.class))
        GameTooltip:AddLine(type(d.t) == "number" and ("Died at " .. View.Format(d.t)) or "time unknown", 1, 1, 1)
        local killer = spellName(d.spellID)
        GameTooltip:AddLine(killer and ("Killed by " .. killer) or "Killing blow unknown", 0.85, 0.85, 0.85)
        -- a pull laid over a reference always says which it is; the age overlay only when it is on
        if (mark.overlay or settings().overlayOn) and mark.pull and mark.pull.id then
            GameTooltip:AddLine("Pull " .. mark.pull.id, 0.85, 0.85, 0.85)
        end
    elseif lane.kind == "reference" then
        if lane.spellID and lane.spellID ~= 0 then
            spellTip(lane.spellID, lane.label)
        else
            GameTooltip:SetText(lane.label or "Unknown", 1, 0.82, 0)
        end
        GameTooltip:AddLine("Planned at " .. View.Format(mark.t), 1, 1, 1)
        if type(mark.dur) == "number" and mark.dur > 0 then
            GameTooltip:AddLine(string.format("Lasts %ds", mark.dur), 0.85, 0.85, 0.85)
        end
        if type(lane.lead) == "number" and lane.lead > 0 then
            GameTooltip:AddLine(string.format("Cast starts %ds before", lane.lead), 0.85, 0.85, 0.85)
        end
        addTypes(lane)
    elseif lane.kind == "unnamed" then
        GameTooltip:SetText("Boss cast (unnamed)", 1, 1, 1)
        GameTooltip:AddLine("Cast at " .. View.Format(mark.t), 0.85, 0.85, 0.85)
        if type(mark.dur) == "number" and mark.dur > 0 then
            GameTooltip:AddLine(string.format("Duration %.1fs", mark.dur), 0.85, 0.85, 0.85)
        end
    else
        spellTip(mark.spellID, spellName(mark.spellID))
        GameTooltip:AddLine("Cast at " .. View.Format(mark.t), 1, 1, 1)
    end
    GameTooltip:Show()
end

-- The game's class names by tag word: the class file name ("DEATHKNIGHT", as the editor writes it)
-- and the name with its spaces taken out, lower-cased. Made once the game lists the classes.
local classNames
local function className(word)
    local names = classNames
    if not names then
        names = {}
        for i = 1, GetNumClasses and GetNumClasses() or 0 do
            local name, file = GetClassInfo(i)
            if CRT.Timeline.readable(name) and type(name) == "string" and name ~= "" then
                names[(name:gsub("%s+", "")):lower()] = name
                if CRT.Timeline.readable(file) and type(file) == "string" then
                    names[file:lower()] = name
                end
            end
        end
        if next(names) then
            classNames = names
        end
    end
    return names[word:lower()] or word
end

-- A marker: the alert's text, who it is for, its phase and time, and where it is saved.
local function flagEnter(f)
    local m = f.mark
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    GameTooltip:SetText(m.text, 1, 0.82, 0)
    local who = TEXT.onlyMe
    if not m.mine then
        local words = {}
        for i, tag in ipairs(m.tags or {}) do
            words[i] = tag:lower() == "everyone" and TEXT.everyone or className(tag)
        end
        who = #words > 0 and table.concat(words, " ") or TEXT.noOne
    end
    GameTooltip:AddLine(who, 1, 1, 1)
    GameTooltip:AddLine(CRT.AlertReminders.FormatTimes({ { ph = m.ph, t = m.time } }), 0.85, 0.85, 0.85)
    local source = TEXT.yourReminder
    if not m.mine then
        source = m.difficulty and string.format(TEXT.raidNoteOf, m.difficulty) or TEXT.raidNote
    end
    GameTooltip:AddLine(source, 0.85, 0.85, 0.85)
    GameTooltip:Show()
end

local function labelEnter(l)
    local lane = l.lane
    if lane and lane.kind == "spell" then
        GameTooltip:SetOwner(l, "ANCHOR_RIGHT")
        spellTip(lane.spellID, lane.label)
        GameTooltip:Show()
    elseif lane and lane.kind == "reference" and lane.types and #lane.types > 0 then
        GameTooltip:SetOwner(l, "ANCHOR_RIGHT")
        GameTooltip:SetText(lane.label or "", 1, 0.82, 0)
        addTypes(lane)
        GameTooltip:Show()
    end
end

-- The view ------------------------------------------------------------------------------------------

local Methods = {}
Methods.__index = Methods
local count = 0

-- Takes item n of a pool, making it with make() the first time, and shows it.
local function pooled(list, n, make)
    local item = list[n]
    if not item then
        item = make()
        list[n] = item
    end
    item:Show()
    return item
end

local function hideFrom(list, n)
    for i = n, #list do
        list[i]:Hide()
    end
end

-- The cursor's x in pixels from the left edge of frame.
local function cursorX(frame)
    local x = GetCursorPosition()
    return x / frame:GetEffectiveScale() - (frame:GetLeft() or 0)
end

function View.Create(parent)
    count = count + 1
    local view = setmetatable({
        icons = {}, labels = {}, lines = {}, ticks = {}, texts = {}, lanes = {}, unknown = {}, trackW = 1,
        bars = {}, leads = {}, phaseLines = {}, phaseTexts = {}, pullTicks = {}, extra = { phases = {}, length = 0 },
        flags = {}, marks = {}, chips = {}, dashes = {}, cdChips = {},
    }, Methods)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    view.frame = f

    -- the time under the cursor, in the empty corner above the lane names
    view.hover = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    view.hover:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    view.hover:SetTextColor(mocha("latte"))

    -- the axis: a scroll frame that follows the track's sideways scroll
    local axisScroll = CreateFrame("ScrollFrame", nil, f)
    axisScroll:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, 0)
    axisScroll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SCROLLBAR_W, 0)
    axisScroll:SetHeight(AXIS_H)
    local axis = CreateFrame("Frame", nil, axisScroll)
    axis:SetSize(1, AXIS_H)
    axisScroll:SetScrollChild(axis)
    view.axisScroll, view.axis = axisScroll, axis
    local base = f:CreateTexture(nil, "ARTWORK")
    base:SetPoint("BOTTOMLEFT", axisScroll, "BOTTOMLEFT")
    base:SetPoint("BOTTOMRIGHT", axisScroll, "BOTTOMRIGHT")
    base:SetHeight(1)
    base:SetColorTexture(mocha("caramel"))

    view.unknownText = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    view.unknownText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, STRIP_H + 2)
    view.unknownText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, STRIP_H + 2)
    view.unknownText:SetJustifyH("LEFT")

    view:BuildStrip()

    -- the sideways scroll bar under the track
    local bar = CreateFrame("Slider", nil, f)
    bar:SetOrientation("HORIZONTAL")
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LABEL_W, STRIP_H + UNKNOWN_H + 2)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLLBAR_W, STRIP_H + UNKNOWN_H + 2)
    bar:SetHeight(BAR_H)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(mocha("roast"))
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = bar:GetThumbTexture()
    if thumb then
        thumb:SetVertexColor(mocha("caramel"))
        thumb:SetSize(40, BAR_H)
    end
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(_, value)
        if not view.syncing then
            view:ScrollTo(value)
        end
    end)
    view.bar = bar

    -- the lanes: an up and down scroll frame holding the name column and the sideways track
    local vscroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTimelineView" .. count, f, "UIPanelScrollFrameTemplate")
    vscroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -AXIS_H)
    vscroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLLBAR_W, STRIP_H + UNKNOWN_H + BAR_H + 4)
    local body = CreateFrame("Frame", nil, vscroll)
    body:SetSize(1, 1)
    vscroll:SetScrollChild(body)
    view.vscroll, view.body = vscroll, body

    local hscroll = CreateFrame("ScrollFrame", nil, body)
    hscroll:SetPoint("TOPLEFT", body, "TOPLEFT", LABEL_W, 0)
    hscroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT")
    local track = CreateFrame("Frame", nil, hscroll)
    track:SetSize(1, 1)
    hscroll:SetScrollChild(track)
    view.hscroll, view.track = hscroll, track
    view.cursorLine = track:CreateTexture(nil, "OVERLAY")
    view.cursorLine:SetWidth(1)
    view.cursorLine:SetColorTexture(mocha("cream", 0.5))
    view.cursorLine:Hide()

    hscroll:EnableMouse(true)
    hscroll:EnableMouseWheel(true)
    hscroll:SetScript("OnMouseWheel", function(_, delta)
        if IsShiftKeyDown() then
            view:ScrollLanes(delta)
        else
            view:Zoom(delta)
        end
    end)
    hscroll:SetScript("OnMouseDown", function(_, button)
        if view:PhaseMouseDown(button) then
            return -- Shift + drag moves a phase line; a right press on a moved one may reset it
        end
        view:StartDrag(button)
        view:RightDown(button)
    end)
    hscroll:SetScript("OnMouseUp", function(_, button)
        if view:PhaseMouseUp(button) then
            return
        end
        view:RightUp(button) -- before StopDrag: a menu click puts back the few pixels it scrolled
        view:StopDrag()
        view:TrackClick(button)
    end)
    f:SetScript("OnUpdate", function()
        view:OnUpdate()
    end)
    f:SetScript("OnSizeChanged", function()
        view:Refresh()
    end)
    f:SetScript("OnHide", function()
        view:StopDrag()
        view:CancelMove()
        view:CancelChipMove()
        view.rightAt = nil
    end)
    -- the markers follow the notes and the reminders; only a shown view redraws
    -- a failing redraw must never break the note or reminder save that fired it
    local function changed()
        if f:IsVisible() then
            local ok, err = pcall(view.Refresh, view)
            if not ok and geterrorhandler then
                geterrorhandler()(err)
            end
        end
    end
    if CRT.Notes and CRT.Notes.OnChange then
        CRT.Notes:OnChange(changed)
    end
    if CRT.Alerts and CRT.Alerts.OnChange then
        CRT.Alerts:OnChange(changed)
    end
    -- the strip follows the saved alerts
    if CRT.AlertSaved and CRT.AlertSaved.OnChange then
        CRT.AlertSaved:OnChange(function()
            if f:IsVisible() then
                view:DrawStrip()
            end
        end)
    end
    return view
end

-- base is a recorded pull or { reference = ref }; overlay is a pull laid over a reference.
function Methods:SetData(base, encounterID, overlay, bossName, group)
    self.pull, self.encounterID, self.overlay, self.bossName, self.group = base, encounterID, overlay, bossName, group
    self.highlight = nil -- a lit row belongs to what was shown
    self:Refresh()
    self:ScrollTo(0)
end

-- Lights the row of a spell (by its ID, else by the row's name) in a foamy off-white and scrolls it
-- into the middle of the view, for "Show on the Timeline". Returns true when such a row is shown.
-- The light stays until other data is shown or ClearHighlight (the page calls it when the pop-out
-- closes); a second Highlight moves it to the new row.
local HIGHLIGHT = { 0.96, 0.94, 0.86 }
function Methods:Highlight(spellID, name)
    self.highlight = { spellID = spellID, name = type(name) == "string" and name:lower() or nil }
    self:Refresh()
    local row = self.highlightRow
    if not row then
        return false
    end
    local v = self.vscroll
    if v.UpdateScrollChildRect then
        v:UpdateScrollChildRect()
    end
    local range = v:GetVerticalScrollRange() or 0
    local top = (row - 1) * ROW_H - ((v:GetHeight() or 0) - ROW_H) / 2
    v:SetVerticalScroll(math.max(0, math.min(range, top)))
    return true
end

function Methods:ClearHighlight()
    if self.highlight then
        self.highlight = nil
        self:Refresh()
    end
end

-- The lit row's band over the labels and the track, or nothing.
function Methods:DrawHighlight(lanes)
    local want = self.highlight
    self.highlightRow = nil
    if want then
        for i, lane in ipairs(lanes) do
            local id = lane.spellID
            if (want.spellID and want.spellID ~= 0 and id == want.spellID)
                or (want.name and type(lane.label) == "string" and lane.label:lower() == want.name) then
                self.highlightRow = i
                break
            end
        end
    end
    if not self.highlightRow then
        if self.highlightTex then
            self.highlightTex:Hide()
        end
        return
    end
    if not self.highlightTex then
        self.highlightTex = self.body:CreateTexture(nil, "ARTWORK")
    end
    local tex, y = self.highlightTex, -(self.highlightRow - 1) * ROW_H
    tex:SetColorTexture(HIGHLIGHT[1], HIGHLIGHT[2], HIGHLIGHT[3], 0.22)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, y)
    tex:SetPoint("BOTTOMRIGHT", self.body, "TOPRIGHT", 0, y - ROW_H)
    tex:Show()
end

-- The chosen order of the shown reference's parts (a list of part names), or nil for the order the
-- reference was written in. Takes effect on the next Refresh or SetData.
function Methods:SetOrder(order)
    self.order = order
end

-- The phases, length and end line of what is shown, from the last refresh.
function Methods:Extra()
    return self.extra
end

function Methods:SetSpan(seconds)
    settings().span = clampSpan(seconds)
    self:Refresh()
end

function Methods:CastCount()
    local n = 0
    for _, cast in ipairs((self.pull and self.pull.casts) or {}) do
        if type(cast.t) == "number" then -- the lanes skip casts without a time, so the count does too
            n = n + 1
        end
    end
    return n
end

-- The width of the track's window, in pixels.
function Methods:VisibleWidth()
    return math.max(1, self.axisScroll:GetWidth() or 1)
end

function Methods:ScrollTo(x)
    local most = math.max(0, self.trackW - self:VisibleWidth())
    x = math.max(0, math.min(most, x or 0))
    self.hscroll:SetHorizontalScroll(x)
    self.axisScroll:SetHorizontalScroll(x)
    self.syncing = true
    self.bar:SetMinMaxValues(0, most)
    self.bar:SetValue(x)
    self.syncing = false
end

-- Zooms in (delta above 0) or out by ZOOM, keeping the time under the cursor where it is.
function Methods:Zoom(delta)
    local width = self:VisibleWidth()
    local span = clampSpan(settings().span)
    local cx = cursorX(self.hscroll)
    local t = (self.hscroll:GetHorizontalScroll() + cx) * span / width
    self:SetSpan(delta > 0 and span / ZOOM or span * ZOOM)
    self:ScrollTo(t * width / clampSpan(settings().span) - cx)
end

function Methods:ScrollLanes(delta)
    local v = self.vscroll
    local top = math.max(0, math.min(v:GetVerticalScrollRange() or 0, (v:GetVerticalScroll() or 0) - delta * ROW_H))
    if v.ScrollBar then
        v.ScrollBar:SetValue(top)
    else
        v:SetVerticalScroll(top)
    end
end

-- Holding the right mouse button and moving scrolls the timeline sideways. The left button is
-- left free for clicking on the timeline.
function Methods:StartDrag(button)
    if button ~= "RightButton" then
        return
    end
    self.dragX = GetCursorPosition() / self.hscroll:GetEffectiveScale()
    self.dragFrom = self.hscroll:GetHorizontalScroll()
end

function Methods:StopDrag()
    self.dragX = nil
end

function Methods:OnUpdate()
    if self.move then
        self:UpdateMove()
    end
    if self.chipMove then
        self:UpdateChipMove()
    end
    if self.dragX then
        if IsMouseButtonDown("RightButton") then
            local x = GetCursorPosition() / self.hscroll:GetEffectiveScale()
            self:ScrollTo(self.dragFrom - (x - self.dragX))
        else
            self.dragX = nil
        end
    end
    if self.pull and self.hscroll:IsMouseOver() then
        local cx = cursorX(self.hscroll)
        local x = self.hscroll:GetHorizontalScroll() + cx
        self.hover:SetText(View.Format(x * clampSpan(settings().span) / self:VisibleWidth()))
        self.cursorLine:ClearAllPoints()
        self.cursorLine:SetPoint("TOPLEFT", self.track, "TOPLEFT", x, 0)
        self.cursorLine:SetPoint("BOTTOMLEFT", self.track, "BOTTOMLEFT", x, 0)
        self.cursorLine:Show()
    elseif self.cursorLine:IsShown() then
        self.hover:SetText("")
        self.cursorLine:Hide()
    end
    if self.phaseDrag then
        self:UpdatePhaseDrag() -- after the hover time, so its own label wins while a line drags
    end
end

-- Moving phase lines --------------------------------------------------------------------------------
-- With a reference shown, Shift + left-drag on a red phase line moves it, and a right-click on a moved
-- line puts it back where it was planned. While it drags, the shown reference's phase time changes and
-- the timeline redraws (casts follow their phase, and an earlier phase's casts past the line hide); on
-- release view.onPhaseMoved(index, seconds) saves it into the reference (Timeline/Page.lua).

local PHASE_GRAB = 4 -- pixels either side of a phase line that pick it up
local PHASE_GAP = 5 -- seconds a phase line keeps from its neighbours and from the pull

-- The time under the cursor on the track, in seconds.
function Methods:CursorSeconds()
    local x = self.hscroll:GetHorizontalScroll() + cursorX(self.hscroll)
    return x * clampSpan(settings().span) / self:VisibleWidth()
end

-- The index (into the shown reference's phases) of the phase line under the cursor, or nil.
function Methods:PhaseNear()
    local ref = self.pull and self.pull.reference
    if not (ref and ref.phases and self.trackW and self.trackW > 0) then
        return nil
    end
    local length = math.max(1, self.extra and self.extra.length or 0)
    local x = self.hscroll:GetHorizontalScroll() + cursorX(self.hscroll)
    for i, phase in ipairs(ref.phases) do
        if type(phase.t) == "number" and phase.t > 0
            and math.abs(View.TimeToX(phase.t, length, self.trackW) - x) <= PHASE_GRAB then
            return i
        end
    end
    return nil
end

-- A press on the track. True when it belongs to a phase line (and the track does nothing else with it).
function Methods:PhaseMouseDown(button)
    local i = self:PhaseNear()
    if not i then
        return false
    end
    local phase = self.pull.reference.phases[i]
    if button == "LeftButton" and IsShiftKeyDown() then
        self.phaseDrag = { index = i, from = phase.t }
        return true
    end
    if button == "RightButton" and phase.planned and phase.planned ~= phase.t then
        local x, y = GetCursorPosition()
        self.phaseReset = { index = i, x = x, y = y, at = GetTime() }
        return true
    end
    return false
end

-- A release on the track. True when it ended a phase drag or a reset click.
function Methods:PhaseMouseUp(button)
    if self.phaseDrag and button == "LeftButton" then
        self:FinishPhaseDrag()
        return true
    end
    local r = self.phaseReset
    if r and button == "RightButton" then
        self.phaseReset = nil
        local scale = self.hscroll:GetEffectiveScale()
        local x, y = GetCursorPosition()
        local phase = self.pull and self.pull.reference and self.pull.reference.phases[r.index]
        if phase and math.abs(x - r.x) / scale < MENU_DIST and math.abs(y - r.y) / scale < MENU_DIST
            and GetTime() - r.at <= MENU_TIME then
            if self.onPhaseMoved then
                self.onPhaseMoved(r.index, phase.planned)
            end
        end
        return true
    end
    return false
end

-- Moves the dragged line to the cursor, kept PHASE_GAP seconds from its neighbours and the pull.
function Methods:UpdatePhaseDrag()
    local drag = self.phaseDrag
    local ref = self.pull and self.pull.reference
    local phase = ref and ref.phases and ref.phases[drag.index]
    if not phase then
        self.phaseDrag = nil
        return
    end
    if not IsMouseButtonDown("LeftButton") then
        self:FinishPhaseDrag()
        return
    end
    local prev = ref.phases[drag.index - 1]
    local nextPhase = ref.phases[drag.index + 1]
    local low = (prev and prev.t or 0) + PHASE_GAP
    local high = nextPhase and (nextPhase.t - PHASE_GAP) or math.max(low, (self.extra and self.extra.length or 0) - PHASE_GAP)
    local t = math.floor(self:CursorSeconds() + 0.5)
    t = math.max(low, math.min(high, t))
    if t ~= phase.t then
        phase.t = t
        self:Refresh()
    end
    local masked = self.extra and self.extra.masked or 0
    self.hover:SetText(string.format("%s%s (planned %s)%s", phase.label and (phase.label .. ": ") or "", View.Format(t),
        View.Format(phase.planned or t), masked > 0 and string.format(", %d hidden", masked) or ""))
end

-- Lets go of the dragged line and saves where it ended.
function Methods:FinishPhaseDrag()
    local drag = self.phaseDrag
    self.phaseDrag = nil
    local ref = self.pull and self.pull.reference
    local phase = ref and ref.phases and ref.phases[drag.index]
    if phase and phase.t ~= drag.from and self.onPhaseMoved then
        self.onPhaseMoved(drag.index, phase.t)
    else
        self:Refresh()
    end
end

-- One icon button from the pool, set up for a mark on a lane.
function Methods:Icon(n)
    return pooled(self.icons, n, function()
        local b = CreateFrame("Button", nil, self.track)
        b:EnableMouse(true)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 1, -1)
        b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        b:SetScript("OnEnter", iconEnter)
        b:SetScript("OnLeave", hideTip)
        b:SetScript("OnMouseDown", function(_, button)
            self.clickAt = nil -- a click here is the icon's, so it never pairs with one on the track
            self:StartDrag(button)
            self:RightDown(button)
        end)
        b:SetScript("OnMouseUp", function(_, button)
            self:RightUp(button)
            self:StopDrag()
        end)
        b:SetScript("OnDoubleClick", function()
            self:IconDoubleClick(b)
        end)
        return b
    end)
end

-- The boss's encounter ID as a number: a boss shown under a reference's name uses the reference's
-- Encounter line, or the boss the Journal finds by that name. Nil when neither is known.
function Methods:EncounterNumber()
    local encounterID = self.encounterID
    if type(encounterID) ~= "number" and CRT.TimelineJournal and CRT.TimelineJournal.ResolveID then
        encounterID = CRT.TimelineJournal:ResolveID(encounterID, self.pull and self.pull.reference)
    end
    return type(encounterID) == "number" and encounterID or nil
end

-- Opens the editor on a new alert t seconds from the pull, as phase + seconds through the shown
-- reference's phase lines (on a recorded pull, phase 1 from the pull), saved as your own by default.
-- Reminders are keyed by encounter ID, so a boss with none asks to be pulled once first.
-- The raid's chosen order on this boss (Timeline:OrderShift): shift moves a part's line to where its
-- part now is, unshift is the reverse (once the Timeline offers it). Both nil when nothing moves.
function Methods:OrderShifts()
    local encounterID = self:EncounterNumber()
    local Timeline = CRT.Timeline
    if not (encounterID and Timeline and Timeline.OrderShift) then
        return nil
    end
    local ok, shift, unshift = pcall(Timeline.OrderShift, Timeline, encounterID, self.group)
    if not ok then
        return nil
    end
    return type(shift) == "function" and shift or nil, type(unshift) == "function" and unshift or nil
end

-- A time on screen as the note or reminder stores it: the chosen order moves a part's lines, so a time
-- picked on a moved cast is put back where the written order has it.
function Methods:WrittenTime(spellID, text, t)
    local _, unshift = self:OrderShifts()
    if not unshift then
        return t
    end
    local ok, w = pcall(unshift, spellID, text, t)
    return ok and type(w) == "number" and w or t
end

function Methods:OpenAt(t, spellID, text)
    local encounterID = self:EncounterNumber()
    if not encounterID then
        CRT:Print(TEXT.needPull)
        return
    end
    t = self:WrittenTime(spellID, text, t)
    local ph, seconds = CRT.AlertReminders.PhaseAt(self.pull and self.pull.reference, tenth(t))
    CRT.AlertEditor:Open(encounterID, nil, {
        spellID = spellID,
        text = text or (spellID and CRT.AlertReminders.SpellName(spellID)) or nil,
        ph = ph,
        time = tenth(seconds),
        boss = self.bossName,
        saveAs = "mine",
    })
end

-- Whether an icon's mark is a boss cast (not a death) with a time.
local function castIcon(lane, mark)
    if not (lane and mark and type(mark.t) == "number") or mark.death then
        return false
    end
    return lane.kind == "reference" or lane.kind == "spell" or lane.kind == "unnamed"
end

-- A cast icon's spell: the lane's, else the cast's own (an unnamed lane holds casts the Journal doesn't
-- list). Nil when neither is known.
local function castSpell(lane, mark)
    local readable = CRT.Timeline.readable
    if readable(lane.spellID) and type(lane.spellID) == "number" and lane.spellID > 0 then
        return lane.spellID
    end
    if readable(mark.spellID) and type(mark.spellID) == "number" and mark.spellID > 0 then
        return mark.spellID
    end
    return nil
end

-- Double-click on a cast icon opens the editor for that boss with the spell and the time filled in.
-- Deaths and the overlaid pull's ticks do nothing.
function Methods:IconDoubleClick(b)
    -- the click's mouse-down started a drag; undo it so the view stays where it was
    if self.dragX then
        self:ScrollTo(self.dragFrom)
        self:StopDrag()
    end
    local lane, mark = b.lane, b.mark
    if not castIcon(lane, mark) then
        return
    end
    local spellID = castSpell(lane, mark)
    local text = spellID and CRT.AlertReminders.SpellName(spellID) or nil
    -- a reference row with no spell (or an unreadable name) is named after the row
    if not text and lane.kind == "reference" and type(lane.label) == "string" and lane.label ~= "" then
        text = lane.label
    end
    self:OpenAt(mark.t, spellID, text)
end

-- A left click on the track itself (icons and markers take their own clicks). The second of two
-- within DOUBLE_TIME seconds and DOUBLE_DIST pixels is a double-click; a single click does nothing.
-- A drag that scrolled the track since the first click (the mouse-up ending it comes here too) means
-- the next click starts over, so a drag and a quick click never open the editor.
function Methods:TrackClick(button)
    local scroll = self.hscroll:GetHorizontalScroll()
    if self.clickAt and scroll ~= self.clickScroll then
        self.clickAt = nil
    end
    if button ~= "LeftButton" or not self.pull then
        return
    end
    local scale = self.hscroll:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local now = GetTime()
    if self.clickAt and now - self.clickAt <= DOUBLE_TIME
        and math.abs(x - self.clickX) <= DOUBLE_DIST and math.abs(y - self.clickY) <= DOUBLE_DIST then
        self.clickAt = nil
        self:TrackDoubleClick()
    else
        self.clickAt, self.clickX, self.clickY, self.clickScroll = now, x, y, scroll
    end
end

-- Drops a new alert at the cursor: the time only, on every row. Only a double-click on a boss spell
-- icon (IconDoubleClick) fills in that spell.
function Methods:TrackDoubleClick()
    local length = math.max(1, self.extra.length or 0)
    local x = self.hscroll:GetHorizontalScroll() + cursorX(self.hscroll)
    local t = math.max(0, math.min(length, View.XToTime(x, length, self.trackW)))
    self:OpenAt(t)
end

-- Markers -------------------------------------------------------------------------------------------

local function lowerTrim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

-- The lane of an ability row for a marker: by spell, else by the row's name; nil for none.
local function rowFor(lanes, spellID, text)
    local want = type(spellID) == "number" and spellID > 0 and spellID or nil
    local name = type(text) == "string" and lowerTrim(text) or ""
    for i, lane in ipairs(lanes) do
        if (lane.kind == "reference" or lane.kind == "spell") and want and lane.spellID == want then
            return i
        end
    end
    if name ~= "" then
        for i, lane in ipairs(lanes) do
            if (lane.kind == "reference" or lane.kind == "spell") and lowerTrim(lane.label) == name then
                return i
            end
        end
    end
    return nil
end

-- The boss's saved alerts that have a time on what is shown: every timed line of its raid notes (each
-- difficulty's note) and every time of your reminders, except those at or after a later phase's line
-- (Reminders.PhaseCut, the phase mask). On a recorded pull only phase 1 can be placed.
-- Each gets the lane it goes on: a note line its spell's row, else a Notes lane added at the bottom of
-- lanes; your reminders only the Personal notes lane, added last whenever a boss is shown (with or
-- without reminders). Returns { { t, ph, time, row, text, tags, kind, encounterID, ... } }: a
-- reminder's mark (kind "mine") also holds id and index (which of its times), a note line's (kind
-- "note") noteID, line, difficulty and expected (the raw line as drawn).
function Methods:Marks(lanes, length)
    local out = self:NoteAndReminderMarks(lanes, length)
    if self.pull then
        lanes[#lanes + 1] = { key = "personal", label = TEXT.personal, icon = PERSONAL_ICON, kind = "personal", marks = {} }
        for _, m in ipairs(out) do
            if m.kind == "mine" then
                m.row = #lanes
            end
        end
    end
    return out
end

function Methods:NoteAndReminderMarks(lanes, length)
    local out = {}
    local Reminders = CRT.AlertReminders
    local encounterID = self.pull and Reminders and self:EncounterNumber()
    if not encounterID then
        return out
    end
    local ref = self.pull.reference
    local shift = self:OrderShifts()
    local function add(m, spellID, text, iconID)
        m.spellID, m.iconID = spellID, iconID
        m.t = Reminders.AbsoluteTime(ref, m.ph, m.time)
        -- the raid's chosen order: a phase 1 line for one part's spell sits where that part now is
        -- (shiftDelta, so a drag puts it back in the written order); past its new window it is hidden
        if shift and m.ph == 1 and m.t then
            local ok, t2 = pcall(shift, spellID, text, m.t)
            if ok and t2 == false then
                return
            elseif ok and type(t2) == "number" then
                m.shiftDelta = t2 - m.t
                m.t = t2
            end
        end
        if not (m.t and m.t >= 0 and m.t <= length) then
            return
        end
        -- the phase mask: hidden once a later phase line comes first (kept in the note or reminder)
        local cut = Reminders.PhaseCut(ref, m.ph)
        if cut and m.t >= cut then
            return
        end
        m.text = (type(text) == "string" and text ~= "" and text) or Reminders.SpellName(spellID)
            or (type(spellID) == "number" and string.format(TEXT.spell, spellID)) or TEXT.reminder
        -- a reminder's row is the Personal notes lane, set once it is added
        m.row = m.kind == "note" and rowFor(lanes, spellID, text) or nil
        out[#out + 1] = m
    end
    local Notes = CRT.Notes
    if Notes and Notes.List then
        for _, n in ipairs(Notes:List()) do
            if n.record.encounterID == encounterID then
                local note = Notes:Parsed(n.id)
                local rawLines = Notes:RawLines(n.id) -- the lines as drawn, so a move can tell one has changed
                for _, timer in ipairs(note and note.timers or {}) do
                    local raw = rawLines[timer.line]
                    add({ ph = timer.ph, time = timer.time, tags = timer.tags, noteID = n.id, line = timer.line,
                        difficulty = n.record.difficulty, kind = "note", expected = raw, encounterID = encounterID },
                        timer.spellId, timer.text, timer.iconID)
                end
            end
        end
    end
    for _, e in ipairs(Reminders:List(encounterID)) do
        for index, at in ipairs((Reminders:Times(encounterID, e.r))) do
            add({ ph = at.ph, time = at.t, mine = true, encounterID = encounterID, id = e.id, index = index,
                kind = "mine" }, e.r.spellID, e.r.text, e.r.iconID)
        end
    end
    local notesRow
    for _, m in ipairs(out) do
        if m.kind == "note" and not m.row then
            if not notesRow then
                lanes[#lanes + 1] = { key = "notes", label = TEXT.notes, icon = NOTES_ICON, kind = "notes", marks = {} }
                notesRow = #lanes
            end
            m.row = notesRow
        end
    end
    return out
end

-- One marker from the pool: a pole with a flag at its top. Only a square around the flag is the
-- button; the pole below it is a plain texture, so the lower part of the row still reaches an icon.
function Methods:Flag(n)
    return pooled(self.flags, n, function()
        local f = CreateFrame("Button", nil, self.track)
        f:SetSize(FLAG_BTN_W, FLAG_BTN_W)
        f:EnableMouse(true)
        local inset = (FLAG_BTN_W - FLAG_W) / 2
        f.pole = f:CreateTexture(nil, "ARTWORK")
        f.pole:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -3)
        f.pole:SetSize(2, ROW_H - 6)
        f.head = f:CreateTexture(nil, "ARTWORK")
        f.head:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -3)
        f.head:SetSize(FLAG_W, FLAG_HEAD)
        -- An alert with a spell (or an icon) shows that icon in place of the flag, in an edge of the
        -- flag's color (raid note or your reminder). The pole stays below it, marking the time.
        f.edge = f:CreateTexture(nil, "ARTWORK", nil, 1)
        f.edge:SetAllPoints(f)
        f.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        f.icon:SetSize(FLAG_BTN_W - 2, FLAG_BTN_W - 2)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.edge:Hide()
        f.icon:Hide()
        f:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
        f:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.15)
        f:SetScript("OnEnter", function(btn)
            self:FlagHighlight(btn)
            flagEnter(btn)
        end)
        f:SetScript("OnLeave", hideTip)
        f:SetScript("OnMouseDown", function(_, button)
            self.clickAt = nil
            if button == "LeftButton" then
                self:StartMove(f)
            else
                self:StartDrag(button)
                self:RightDown(button)
            end
        end)
        f:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                self:FinishMove()
            else
                self:RightUp(button, f)
                self:StopDrag()
            end
        end)
        f:SetScript("OnDoubleClick", function()
            self:FlagDoubleClick(f)
        end)
        return f
    end)
end

-- Opens a marker's note line or reminder in the editor.
function Methods:FlagDoubleClick(f)
    self:CancelMove()
    if self.dragX then
        self:ScrollTo(self.dragFrom)
        self:StopDrag()
    end
    self:EditMark(f.mark)
end

function Methods:EditMark(m)
    if not m then
        return
    end
    if m.noteID then
        CRT.AlertEditor:OpenNote(m.noteID, m.line)
    else
        CRT.AlertEditor:Open(m.encounterID, m.id)
    end
end

-- Moving a flag ------------------------------------------------------------------------------------

-- Whether you may change the raid note right now (CRT.Notes:CanEditRaid: the raid leader or an
-- assistant), and the reason when not. Asked at each action, never kept, so a promotion counts at once.
local function canEditRaid()
    local Notes = CRT.Notes
    if not (Notes and Notes.CanEditRaid) then
        return false
    end
    return Notes:CanEditRaid()
end

-- Whether a marker can be moved, Alt+dragged or deleted by you: your reminders always, a raid note
-- line only when you may change the raid note.
local function canChange(m)
    return m ~= nil and (m.kind ~= "note" or (canEditRaid()))
end

-- No hover highlight on a flag you can't change (a raid note line, for anyone else); its tooltip
-- stays. Set at each draw and each hover, so a promotion counts without a redraw.
function Methods:FlagHighlight(f)
    local hl = f.GetHighlightTexture and f:GetHighlightTexture()
    if hl then
        hl:SetAlpha(canChange(f.mark) and 1 or 0)
    end
end

-- m:ss, with tenths when there are some.
local function clock(t)
    t = tenth(t)
    local m = math.floor(t / 60)
    if t == math.floor(t) then
        return string.format("%d:%02d", m, t % 60)
    end
    return string.format("%d:%04.1f", m, t - m * 60)
end

-- The cursor's screen x in the track's scale.
local function cursorScreenX(self)
    return GetCursorPosition() / self.hscroll:GetEffectiveScale()
end

-- A ghost of the flag that follows the cursor while it is dragged, with a label saying what releasing does.
function Methods:Ghost()
    local g = self.ghost
    if not g then
        g = CreateFrame("Frame", nil, self.track)
        g:SetSize(FLAG_BTN_W, FLAG_BTN_W)
        local inset = (FLAG_BTN_W - FLAG_W) / 2
        g.pole = g:CreateTexture(nil, "ARTWORK")
        g.pole:SetPoint("TOPLEFT", g, "TOPLEFT", inset, -3)
        g.pole:SetSize(2, ROW_H - 6)
        g.head = g:CreateTexture(nil, "ARTWORK")
        g.head:SetPoint("TOPLEFT", g, "TOPLEFT", inset, -3)
        g.head:SetSize(FLAG_W, FLAG_HEAD)
        g.labelBg = g:CreateTexture(nil, "BACKGROUND")
        g.labelBg:SetColorTexture(mocha("roast", 0.85))
        g.label = g:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        g.labelBg:SetPoint("TOPLEFT", g.label, "TOPLEFT", -3, 2)
        g.labelBg:SetPoint("BOTTOMRIGHT", g.label, "BOTTOMRIGHT", 3, -2)
        g:Hide()
        self.ghost = g
    end
    return g
end

-- A left button pressed on a flag: remember where, so the release can tell a click from a drag. A raid
-- note line you may not change starts nothing (no ghost, no write); its double-click still opens it.
function Methods:StartMove(f)
    if f.mark and canChange(f.mark) then
        -- a copy of the mark: a redraw during the drag can hand this flag to another alert
        local m = {}
        for k, v in pairs(f.mark) do
            m[k] = v
        end
        self.move = { f = f, m = m, x0 = cursorScreenX(self), scroll0 = self.hscroll:GetHorizontalScroll() }
    end
end

-- The time the dragged flag would land on: where it was plus how far the cursor has moved along the
-- track, to a tenth and within the view.
function Methods:MoveTarget(mv)
    local length = math.max(1, self.extra.length or 0)
    local dx = (cursorScreenX(self) + self.hscroll:GetHorizontalScroll()) - (mv.x0 + mv.scroll0)
    local t = mv.m.t + dx * length / math.max(1, self.trackW)
    return tenth(math.max(0, math.min(length, t)))
end

function Methods:CancelMove()
    self.move = nil
    if self.ghost then
        self.ghost:Hide()
    end
end

-- While a flag is held: once moved MOVE_DIST pixels the ghost and its label follow the cursor. Alt is
-- read live here, as the release reads it.
function Methods:UpdateMove()
    local mv = self.move
    if not mv then
        self:CancelMove()
        return
    end
    if not IsMouseButtonDown("LeftButton") then
        self:FinishMove() -- the release went elsewhere
        return
    end
    if not mv.moved and math.abs(cursorScreenX(self) - mv.x0) < MOVE_DIST then
        return
    end
    mv.moved = true
    local m = mv.m
    local t = self:MoveTarget(mv)
    local g = self:Ghost()
    local x = View.TimeToX(t, math.max(1, self.extra.length or 0), self.trackW) - 1 - (FLAG_BTN_W - FLAG_W) / 2
    local key = m.mine and "cream" or "caramel"
    g.head:SetColorTexture(mocha(key, 0.6))
    g.pole:SetColorTexture(mocha(key, 0.6))
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", self.track, "TOPLEFT", x, -(m.row - 1) * ROW_H)
    g:SetFrameLevel((mv.f:GetFrameLevel() or 0) + 1)
    g.label:SetText(string.format(IsAltKeyDown() and TEXT.addTime or TEXT.moveTo, clock(t)))
    -- the label stays inside the visible part of the track: above the flag (beside it on row 1,
    -- where nothing is above), slid sideways as far as it needs
    local w = g.label:GetStringWidth() or 0
    local left = self.hscroll:GetHorizontalScroll()
    local right = left + self:VisibleWidth()
    local lx, ly = x + FLAG_BTN_W / 2 - w / 2, -(m.row - 1) * ROW_H + 4
    local anchor = "BOTTOMLEFT"
    if m.row == 1 then
        lx, ly, anchor = x + FLAG_BTN_W, -FLAG_HEAD, "BOTTOMLEFT"
        if lx + w > right - 3 then
            lx = x - w - 4
        end
    end
    lx = math.max(left + 3, math.min(lx, right - w - 3))
    g.label:ClearAllPoints()
    g.label:SetPoint(anchor, self.track, "TOPLEFT", lx, ly)
    g:Show()
end

-- Moves a note line to phase ph, t seconds in, or (add) writes the same line again there, in the same
-- note. Fields the parser doesn't know stay on the line. False when the line is no longer the one drawn.
local function writeNote(m, ph, t, add)
    local Notes, Parser = CRT.Notes, CRT.NoteParser
    local timer, raw = Notes:TimerAt(m.noteID, m.line)
    if not (timer and m.expected ~= nil and raw == m.expected) then
        return false
    end
    local moved = {}
    for k, v in pairs(timer) do
        moved[k] = v
    end
    moved.ph, moved.time = ph, t
    local line = Parser.FormatLine(moved) .. Parser.UnknownFields(m.expected)
    if add then
        return Notes:AddLineTo(m.noteID, line) ~= nil
    end
    return Notes:ReplaceLine(m.noteID, m.line, line, m.expected)
end

-- Whether the cursor is over the track's window: inside the track and inside the shown part of the lanes
-- (the track runs on under the window when the lanes scroll up and down, behind the strip).
local function overTrack(self)
    local scale = self.hscroll:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local left, top = self.hscroll:GetLeft() or 0, self.hscroll:GetTop() or 0
    local vtop = self.vscroll:GetTop() or top
    return x >= left and x <= left + self.hscroll:GetWidth() and y <= top and y >= top - self.hscroll:GetHeight()
        and y <= vtop and y >= vtop - (self.vscroll:GetHeight() or 0)
end

-- Whether the cursor is over the open alert editor, which sits above the track: a drag let go there was
-- aimed at the editor, not the track.
local function overEditor()
    local E = CRT.AlertEditor
    local f = E and E.Frame and E:Frame()
    return f ~= nil and f:IsShown() and MouseIsOver ~= nil and MouseIsOver(f) and true or false
end

-- The left button let go of a flag. Under MOVE_DIST pixels it was a click. Otherwise Alt at this moment
-- decides: held adds a time, else the alert moves. A release off the track, or over the open alert
-- editor, cancels the drag. A refused write (the alert is no longer what was grabbed) says so and leaves
-- the flag be.
function Methods:FinishMove()
    local mv = self.move
    self:CancelMove()
    if not mv or math.abs(cursorScreenX(self) - mv.x0) < MOVE_DIST or not overTrack(self) or overEditor() then
        return
    end
    local m = mv.m
    local t = self:MoveTarget(mv)
    local add = IsAltKeyDown() and true or false
    if t == m.t then
        return
    end
    t = t - (m.shiftDelta or 0) -- back to the written order
    local Reminders = CRT.AlertReminders
    local ph, seconds = Reminders.PhaseAt(self.pull and self.pull.reference, t)
    seconds = tenth(seconds)
    local ok
    if m.kind == "mine" then
        -- still the time that was grabbed?
        local r = Reminders:Get(m.encounterID, m.id)
        local cur = r and Reminders:Times(m.encounterID, r)[m.index]
        if not (cur and cur.ph == m.ph and cur.t == m.time) then
            CRT:Print(TEXT.moveRefused)
            return
        end
        if add then
            ok = Reminders:AddTime(m.encounterID, m.id, ph, seconds)
        else
            ok = Reminders:SetTime(m.encounterID, m.id, m.index, ph, seconds)
        end
    elseif m.kind == "note" then
        -- asked again at the release: you may have lost the right since the grab
        local allowed, why = canEditRaid()
        if not allowed then
            CRT:Print(why or TEXT.moveRefused)
            return
        end
        ok = writeNote(m, ph, seconds, add)
    end
    if not ok then
        CRT:Print(TEXT.moveRefused)
    end
end

-- Saved alerts: the strip, dropping a chip, and the right-click menus -------------------------------

local function readable(v)
    return CRT.Timeline.readable(v)
end

-- The cursor on the track: x from the track's left end (scroll included) and y down from its top.
local function cursorOnTrack(self)
    local scale = self.hscroll:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    return self.hscroll:GetHorizontalScroll() + x - (self.hscroll:GetLeft() or 0), (self.hscroll:GetTop() or 0) - y
end

-- The time at x on the track, within the view and to a tenth.
function Methods:TimeAtX(x)
    local length = math.max(1, self.extra.length or 0)
    return tenth(math.max(0, math.min(length, View.XToTime(x, length, self.trackW))))
end

-- The spell of the boss cast icon at x, y on the track (as cursorOnTrack gives them), else nil. Deaths and
-- icons without a spell give none.
function Methods:IconSpellAt(x, y)
    local length = math.max(1, self.extra.length or 0)
    for _, b in ipairs(self.icons) do
        if b:IsShown() and castIcon(b.lane, b.mark) then
            local row
            for i, lane in ipairs(self.lanes) do
                if lane == b.lane then
                    row = i
                    break
                end
            end
            local half = (b:GetWidth() or 0) / 2
            if row and math.abs(x - View.TimeToX(b.mark.t, length, self.trackW)) <= half
                and math.abs(y - ((row - 1) * ROW_H + ROW_H / 2)) <= half then
                local spellID = castSpell(b.lane, b.mark)
                if spellID then
                    return spellID
                end
            end
        end
    end
    return nil
end

-- The lane at y down from the track's top (as cursorOnTrack gives it), else nil (the empty space below).
function Methods:LaneAtY(y)
    local row = y and y >= 0 and math.floor(y / ROW_H) + 1 or nil
    return row and self.lanes[row] or nil
end

-- Opens the editor on a new alert from saved alert id at t seconds from the pull (phase + seconds as
-- OpenAt gives them), with spellID (a cast icon's) in place of its own when given. Placed on the
-- Personal notes lane (lane), or as a Raid note by someone who may not change the raid note (asked
-- now), it is saved as your own.
function Methods:PlaceSaved(id, t, spellID, lane)
    local Saved = CRT.AlertSaved
    local encounterID = self:EncounterNumber()
    if not encounterID then
        CRT:Print(TEXT.needPull)
        return
    end
    if not Saved then
        return
    end
    local saved = Saved.Get and Saved:Get(id)
    t = self:WrittenTime(spellID or (saved and saved.spellID), saved and saved.text, t)
    local ph, seconds = CRT.AlertReminders.PhaseAt(self.pull and self.pull.reference, tenth(t))
    local prefill = Saved:Prefill(id, encounterID, ph, tenth(seconds), spellID, self.bossName)
    if prefill then
        if (lane and lane.kind == "personal") or (prefill.saveAs == "note" and not canEditRaid()) then
            prefill.saveAs = "mine"
        end
        CRT.AlertEditor:Open(encounterID, nil, prefill)
    end
end

-- Opens the editor on a new alert from cooldown e (as CRT.AlertCooldowns:List gives it) at t seconds from
-- the pull: OpenAt with its spell and its name as the text, so it is your own (Only me) wherever it is
-- dropped, the Personal notes lane included.
function Methods:PlaceCooldown(e, t)
    if not (e and e.spellID) then
        return
    end
    self:OpenAt(t, e.spellID, e.name)
end

-- A context menu at the cursor, built by build(root) with the game's menu; without one, a chat line.
local function contextMenu(owner, build)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            build(root)
        end)
    else
        CRT:Print(TEXT.noMenu)
    end
end

-- The Rename popup: an edit box with the saved alert's name. data = { id, name }. The popup helpers
-- (lifting it over the alert editor, finding it, its edit box) are CRT.UI's.
local function acceptRename(edit, data)
    if edit and data and CRT.AlertSaved then
        CRT.AlertSaved:Rename(data.id, edit:GetText())
    end
end

local function ensureRenamePopup()
    if not StaticPopupDialogs then
        return false
    end
    if not StaticPopupDialogs[RENAME_POPUP] then
        StaticPopupDialogs[RENAME_POPUP] = {
            text = TEXT.renamePrompt,
            button1 = TEXT.accept,
            button2 = TEXT.cancel,
            hasEditBox = true,
            maxLetters = 64,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnShow = function(dialog, data)
                local edit = CRT.UI.PopupEditBox(dialog)
                if edit then
                    edit:SetText(data and data.name or "")
                    edit:HighlightText()
                end
            end,
            OnAccept = function(dialog, data)
                acceptRename(CRT.UI.PopupEditBox(dialog), data)
            end,
            -- the game passes the dialog's data; the box's parent is only a fallback (layouts change)
            EditBoxOnEnterPressed = function(edit, data)
                local parent = edit:GetParent()
                acceptRename(edit, data or (parent and parent.data))
                StaticPopup_Hide(RENAME_POPUP)
            end,
            EditBoxOnEscapePressed = function()
                StaticPopup_Hide(RENAME_POPUP)
            end,
        }
    end
    return true
end

local function askRename(id)
    local s = CRT.AlertSaved and CRT.AlertSaved:Get(id)
    if s and ensureRenamePopup() then
        local UI = CRT.UI
        UI.LiftOver(UI.ShownPopup(StaticPopup_Show(RENAME_POPUP, nil, nil, { id = id, name = s.name }), RENAME_POPUP))
    end
end

local function askDelete(id)
    local s = CRT.AlertSaved and CRT.AlertSaved:Get(id)
    if not (s and StaticPopup_ShowCustomGenericConfirmation) then
        return
    end
    local UI = CRT.UI
    UI.LiftOver(UI.ShownPopup(StaticPopup_ShowCustomGenericConfirmation({
        text = string.format(TEXT.deleteConfirm, tostring(s.name or "")),
        acceptText = TEXT.delete,
        cancelText = TEXT.cancel,
        showAlert = true,
        callback = function()
            CRT.AlertSaved:Delete(id)
        end,
    }), "GENERIC_CONFIRMATION"))
end

-- Delete on a marker's menu, after a confirm. A reminder with several times loses only this time; one
-- with a single time is deleted whole; a raid note line is removed if it is still the line drawn. A
-- change since the menu opened is refused, with a chat line.
local function deleteMark(self, m)
    local ok
    if m.noteID then
        local allowed, why = canEditRaid()
        if not allowed then
            CRT:Print(why or TEXT.deleteRefused)
            return
        end
        ok = CRT.Notes:RemoveLine(m.noteID, m.line, m.expected)
    else
        local Reminders = CRT.AlertReminders
        local r = Reminders:Get(m.encounterID, m.id)
        local times = r and Reminders:Times(m.encounterID, r)
        local cur = times and times[m.index]
        if cur and cur.ph == m.ph and cur.t == m.time then
            if #times > 1 then
                ok = Reminders:RemoveTime(m.encounterID, m.id, m.index)
            else
                Reminders:Delete(m.encounterID, m.id)
                ok = true
            end
        end
    end
    if not ok then
        CRT:Print(TEXT.deleteRefused)
        self:Refresh()
    end
end

local function askDeleteMark(self, m)
    if not StaticPopup_ShowCustomGenericConfirmation then
        return
    end
    local question
    if m.noteID then
        question = string.format(TEXT.deleteNote, tostring(m.text or ""))
    else
        local r = CRT.AlertReminders:Get(m.encounterID, m.id)
        local times = r and CRT.AlertReminders:Times(m.encounterID, r)
        question = string.format(times and #times > 1 and TEXT.deleteTime or TEXT.deleteReminder, tostring(m.text or ""))
    end
    local UI = CRT.UI
    UI.LiftOver(UI.ShownPopup(StaticPopup_ShowCustomGenericConfirmation({
        text = question,
        acceptText = TEXT.delete,
        cancelText = TEXT.cancel,
        showAlert = true,
        callback = function()
            deleteMark(self, m)
        end,
    }), "GENERIC_CONFIRMATION"))
end

-- A chip's icon: its icon ID, else its spell's icon; nil when there is none or it can't be read.
local function chipIcon(s)
    local id = s.iconID
    if readable(id) and type(id) == "number" and id > 0 then
        return id
    end
    id = s.spellID
    if readable(id) and type(id) == "number" and id > 0 and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex ~= nil and readable(tex) then
            return tex
        end
    end
    return nil
end

-- A chip's edge color: the template's color, else caramel.
local function chipColor(s)
    local c = s.color
    if type(c) == "table" and readable(c[1]) and type(c[1]) == "number" and type(c[2]) == "number"
        and type(c[3]) == "number" then
        return c[1], c[2], c[3], 1
    end
    return mocha("caramel")
end

-- A font string's width as its text would draw: a width set earlier caps GetStringWidth.
local function textWidth(fs)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
    if type(w) ~= "number" then
        w = fs:GetStringWidth()
    end
    return type(w) == "number" and w or 0
end

-- A template's hover: its name and text, how it shows, who it is for.
local function chipEnter(c)
    local s = CRT.AlertSaved and CRT.AlertSaved:Get(c.savedID)
    if not s then
        return
    end
    GameTooltip:SetOwner(c, "ANCHOR_TOP")
    GameTooltip:SetText(s.name or TEXT.unnamed, 1, 0.82, 0)
    if type(s.text) == "string" and s.text ~= "" and s.text ~= s.name then
        GameTooltip:AddLine(s.text, 1, 1, 1)
    end
    local shows = {}
    for _, k in ipairs({ "alert", "text", "icon", "bar", "circle" }) do
        if s.outputs and s.outputs[k] then
            shows[#shows + 1] = TEXT.outputs[k]
        end
    end
    if s.outputs and s.outputs.speech then
        shows[#shows + 1] = TEXT.readOut
    end
    GameTooltip:AddLine(#shows > 0 and string.format(TEXT.shows, table.concat(shows, ", ")) or TEXT.showsNothing,
        0.85, 0.85, 0.85)
    if s.saveAs == "note" then
        local words = {}
        for i, tag in ipairs(s.tags or {}) do
            words[i] = tag:lower() == "everyone" and TEXT.everyone or className(tag)
        end
        GameTooltip:AddLine(string.format(TEXT.raidNoteFor, #words > 0 and table.concat(words, " ") or TEXT.noOne),
            0.85, 0.85, 0.85)
    else
        GameTooltip:AddLine(TEXT.onlyMe, 0.85, 0.85, 0.85)
    end
    GameTooltip:AddLine(TEXT.savedHint, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- A cooldown's hover: the game's name for its spell, its class, and what dragging it does.
local function cooldownEnter(c)
    local e = c.cooldown
    if not e then
        return
    end
    local Cooldowns = CRT.AlertCooldowns
    GameTooltip:SetOwner(c, "ANCHOR_TOP")
    GameTooltip:SetText(e.name, 1, 0.82, 0)
    GameTooltip:AddLine(Cooldowns and Cooldowns.ClassName(e.class) or e.class, 1, 1, 1)
    GameTooltip:AddLine(TEXT.cooldownHint, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- A faint light over a button while the mouse is on it (the HIGHLIGHT layer shows only then).
local function hoverLight(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
end

-- The chip parts: a background, the colored left edge, the icon and the name.
local function chipParts(c)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(mocha("roast", 0.9))
    c.edge = c:CreateTexture(nil, "ARTWORK")
    c.edge:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.edge:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    c.edge:SetWidth(CHIP_EDGE)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(CHIP_ICON, CHIP_ICON)
    c.icon:SetPoint("LEFT", c, "LEFT", CHIP_EDGE + 4, 0)
    c.name = c:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.name:SetTextColor(mocha("cream"))
end

-- Paints a chip (or the ghost): its name, the icon tex untinted, or with none the Personal notes icon
-- tinted by tint ({ r, g, b }); the edge in edge ({ r, g, b, a }). Returns its width.
local function paintChip(c, name, tex, tint, edge)
    if tex then
        c.icon:SetTexture(tex)
        c.icon:SetVertexColor(1, 1, 1)
    else
        c.icon:SetTexture(PERSONAL_ICON)
        c.icon:SetVertexColor(tint[1], tint[2], tint[3])
    end
    c.icon:Show()
    local x = CHIP_EDGE + 4 + CHIP_ICON + 4
    c.edge:SetColorTexture(edge[1], edge[2], edge[3], edge[4] or 1)
    c.name:SetText(name)
    local w = math.ceil(math.min(CHIP_NAME_MAX, textWidth(c.name)))
    c.name:SetWidth(w)
    c.name:ClearAllPoints()
    c.name:SetPoint("LEFT", c, "LEFT", x, 0)
    local width = x + w + 6
    c:SetSize(width, CHIP_H)
    return width
end

-- Fills a chip (or the ghost) for template s; returns its width. Without an icon it shows the note icon
-- in the template's color.
local function fillChip(c, s)
    local color = { chipColor(s) }
    return paintChip(c, s.name or TEXT.unnamed, chipIcon(s), color, color)
end

-- Fills a chip (or the ghost) for cooldown e (as CRT.AlertCooldowns:List gives it); returns its width.
local function fillCooldownChip(c, e)
    local tex = e.icon
    if not (tex ~= nil and readable(tex) and (type(tex) == "number" or type(tex) == "string")) then
        tex = nil
    end
    return paintChip(c, e.name, tex, { mocha("caramel") }, { mocha("latte", 0.6) })
end

-- The strip along the bottom: two rows. The templates: their label (with help) and the chips in a
-- sideways scroll frame. Under them the cooldowns: a label (with help), the filter dropdown and their
-- chips, scrolling the same way.
function Methods:BuildStrip()
    local f = self.frame
    local strip = CreateFrame("Frame", nil, f)
    strip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
    strip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLLBAR_W, 2)
    strip:SetHeight(STRIP_H)
    local line = strip:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(mocha("caramel", 0.4))
    strip.label = strip:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    strip.label:SetPoint("LEFT", strip, "TOPLEFT", 4, -STRIP_ROW / 2)
    strip.label:SetTextColor(mocha("latte"))
    strip.label:SetText(TEXT.savedAlerts)
    if CRT.UI and CRT.UI.Help then
        CRT.UI.Help(strip, TEXT.savedAlerts, TEXT.savedHelp):SetPoint("LEFT", strip.label, "RIGHT", 2, 0)
    end
    strip:Hide()
    self.strip = strip

    local function chipScroll()
        local scroll = CreateFrame("ScrollFrame", nil, strip)
        local row = CreateFrame("Frame", nil, scroll)
        row:SetSize(1, CHIP_H)
        scroll:SetScrollChild(row)
        scroll:EnableMouseWheel(true)
        return scroll, row
    end
    local scroll, row = chipScroll()
    scroll:SetPoint("TOPLEFT", strip, "TOPLEFT", LABEL_W, -3)
    scroll:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, -STRIP_ROW + 3)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        self:ScrollChips(-delta * CHIP_WHEEL)
    end)
    self.chipScroll, self.chipRow = scroll, row

    -- the Cooldowns row: label, (?), the filter dropdown, then the chips
    local cdLabel = strip:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    cdLabel:SetPoint("LEFT", strip, "TOPLEFT", 4, -STRIP_ROW - STRIP_ROW / 2)
    cdLabel:SetTextColor(mocha("latte"))
    cdLabel:SetText(TEXT.cooldowns)
    self.cdLabel = cdLabel
    local after = cdLabel
    if CRT.UI and CRT.UI.Help then
        after = CRT.UI.Help(strip, TEXT.cooldowns, TEXT.cooldownsHelp)
        after:SetPoint("LEFT", cdLabel, "RIGHT", 2, 0)
    end
    local Cooldowns = CRT.AlertCooldowns
    if Cooldowns and CRT.UI and CRT.UI.Dropdown then
        local drop = CRT.UI.Dropdown(strip, "", {
            labelWidth = 1,
            width = CD_DROP_W,
            maxHeight = 300,
            options = function()
                return Cooldowns:Filters()
            end,
            get = function()
                return Cooldowns:Filter()
            end,
            set = function(key)
                Cooldowns:SetFilter(key)
                self.cdScroll:SetHorizontalScroll(0) -- a new list starts at its first chip
                self:DrawCooldowns()
            end,
        })
        drop:SetHeight(STRIP_ROW)
        drop:SetPoint("LEFT", after, "RIGHT", 0, 0)
        self.cdFilter = drop
        after = drop.Dropdown or drop
    end
    -- the chips start just after the dropdown (else the (?), else the label), whatever their widths, and
    -- run to the strip's right end, centred on the second row
    local cdScroll, cdRow = chipScroll()
    cdScroll:SetPoint("LEFT", after, "RIGHT", 6, 0)
    cdScroll:SetPoint("RIGHT", strip, "TOPRIGHT", 0, -STRIP_ROW - STRIP_ROW / 2)
    cdScroll:SetHeight(CHIP_H)
    cdScroll:SetScript("OnMouseWheel", function(_, delta)
        self:ScrollCooldowns(-delta * CHIP_WHEEL)
    end)
    self.cdScroll, self.cdRow = cdScroll, cdRow
    self.cdEmpty = cdRow:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    self.cdEmpty:SetPoint("LEFT", cdRow, "LEFT", 4, 0)
    self.cdEmpty:SetTextColor(mocha("latte", 0.7))
    self.cdEmpty:SetText(TEXT.noCooldowns)
    self.cdEmpty:Hide()

    local plus = CreateFrame("Button", nil, row)
    plus:SetSize(PLUS_W, CHIP_H)
    plus.bg = plus:CreateTexture(nil, "BACKGROUND")
    plus.bg:SetAllPoints()
    plus.bg:SetColorTexture(mocha("roast", 0.9))
    plus.text = plus:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    plus.text:SetPoint("CENTER", plus, "CENTER", 0, 0)
    plus.text:SetText("+")
    plus.text:SetTextColor(mocha("caramel"))
    hoverLight(plus)
    plus:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText(TEXT.newSaved, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", hideTip)
    plus:SetScript("OnClick", function()
        if CRT.AlertEditor then
            CRT.AlertEditor:EditSaved(nil)
        end
    end)
    self.plus = plus
end

-- Scrolls a row of chips sideways by dx pixels, within its width.
local function scrollRow(scroll, rowW, dx)
    local most = math.max(0, (rowW or 0) - (scroll:GetWidth() or 0))
    scroll:SetHorizontalScroll(math.max(0, math.min(most, (scroll:GetHorizontalScroll() or 0) + dx)))
end

function Methods:ScrollChips(dx)
    scrollRow(self.chipScroll, self.chipRowW, dx)
end

function Methods:ScrollCooldowns(dx)
    scrollRow(self.cdScroll, self.cdRowW, dx)
end

-- A chip from pool list on row: left-drag places it, a right click opens its menu. kind is "saved" (a
-- template) or "cooldown"; enter is its hover.
function Methods:MakeChip(list, n, row, kind, enter)
    return pooled(list, n, function()
        local c = CreateFrame("Button", nil, row)
        c.chipKind = kind
        c:EnableMouse(true)
        chipParts(c)
        hoverLight(c)
        c:SetScript("OnEnter", enter)
        c:SetScript("OnLeave", hideTip)
        c:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                self:StartChipMove(c)
            end
        end)
        c:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                self:FinishChipMove()
            elseif button == "RightButton" then
                self:ChipMenu(c)
            end
        end)
        return c
    end)
end

-- One template chip from the pool.
function Methods:Chip(n)
    return self:MakeChip(self.chips, n, self.chipRow, "saved", chipEnter)
end

-- One cooldown chip from the pool.
function Methods:CooldownChip(n)
    return self:MakeChip(self.cdChips, n, self.cdRow, "cooldown", cooldownEnter)
end

-- Draws a chip for each template, by name, then the + chip, and the Cooldowns row. Hidden while no boss
-- is shown.
function Methods:DrawStrip()
    local shown = self.pull ~= nil and self.encounterID ~= nil
    self.strip:SetShown(shown)
    if not shown then
        self:CancelChipMove()
        return
    end
    local list = CRT.AlertSaved and CRT.AlertSaved:List() or {}
    local x = 0
    for n, e in ipairs(list) do
        local c = self:Chip(n)
        c.savedID = e.id
        local w = fillChip(c, e.s)
        c:ClearAllPoints()
        c:SetPoint("LEFT", self.chipRow, "LEFT", x, 0)
        x = x + w + CHIP_GAP
    end
    hideFrom(self.chips, #list + 1)
    self.plus:ClearAllPoints()
    self.plus:SetPoint("LEFT", self.chipRow, "LEFT", x, 0)
    self.chipRowW = x + PLUS_W
    self.chipRow:SetSize(self.chipRowW, CHIP_H)
    self:ScrollChips(0)
    self:DrawCooldowns()
end

-- The cooldowns the row lists now (its filter), in list order.
function Methods:CooldownList()
    local Cooldowns = CRT.AlertCooldowns
    return Cooldowns and Cooldowns:List(Cooldowns:Filter()) or {}
end

-- Draws the Cooldowns row: a chip for each cooldown of the chosen filter.
function Methods:DrawCooldowns()
    if self.cdFilter and self.cdFilter.refresh then
        self.cdFilter.refresh()
    end
    local list = self:CooldownList()
    local x = 0
    for n, e in ipairs(list) do
        local c = self:CooldownChip(n)
        c.cooldown = e
        local w = fillCooldownChip(c, e)
        c:ClearAllPoints()
        c:SetPoint("LEFT", self.cdRow, "LEFT", x, 0)
        x = x + w + CHIP_GAP
    end
    hideFrom(self.cdChips, #list + 1)
    self.cdEmpty:SetShown(#list == 0)
    self.cdRowW = math.max(1, x - CHIP_GAP)
    self.cdRow:SetSize(self.cdRowW, CHIP_H)
    self:ScrollCooldowns(0)
end

-- The ghost chip that follows the cursor while a chip is dragged; above everything, taking no clicks.
function Methods:ChipGhost()
    local g = self.chipGhost
    if not g then
        g = CreateFrame("Frame", nil, UIParent)
        g:SetFrameStrata("TOOLTIP")
        chipParts(g)
        g:SetAlpha(0.85)
        g:Hide()
        self.chipGhost = g
    end
    return g
end

-- The dashed line on the track where a dragged chip would land, with its time beside it.
function Methods:DropLine()
    local d = self.dropLine
    if not d then
        d = CreateFrame("Frame", nil, self.track)
        d:SetWidth(2)
        d.labelBg = d:CreateTexture(nil, "BACKGROUND")
        d.labelBg:SetColorTexture(mocha("roast", 0.85))
        d.label = d:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        d.labelBg:SetPoint("TOPLEFT", d.label, "TOPLEFT", -3, 2)
        d.labelBg:SetPoint("BOTTOMRIGHT", d.label, "BOTTOMRIGHT", 3, -2)
        d:Hide()
        self.dropLine = d
    end
    return d
end

-- Shows the dashed line at time t, its label at the cursor's height (y down from the track's top), kept
-- inside the visible part of the track.
function Methods:DrawDropLine(t, y)
    local d = self:DropLine()
    local length = math.max(1, self.extra.length or 0)
    local x = View.TimeToX(t, length, self.trackW)
    local height = math.max(1, self.track:GetHeight() or 1)
    d:ClearAllPoints()
    d:SetPoint("TOP", self.track, "TOPLEFT", x, 0)
    d:SetHeight(height)
    d:SetFrameLevel((self.track:GetFrameLevel() or 0) + 10)
    local n = math.ceil(height / (DASH + DASH_GAP))
    for i = 1, n do
        local dash = pooled(self.dashes, i, function()
            local tex = d:CreateTexture(nil, "OVERLAY")
            tex:SetColorTexture(mocha("cream", 0.85))
            tex:SetSize(2, DASH)
            return tex
        end)
        dash:ClearAllPoints()
        dash:SetPoint("TOP", d, "TOP", 0, -(i - 1) * (DASH + DASH_GAP))
    end
    hideFrom(self.dashes, n + 1)
    d.label:SetText(string.format(TEXT.placeAt, clock(t)))
    local w = d.label:GetStringWidth() or 0
    local left = self.hscroll:GetHorizontalScroll()
    local right = left + self:VisibleWidth()
    local lx = x + 4
    if lx + w > right - 3 then
        lx = x - w - 4
    end
    lx = math.max(left + 3, math.min(lx, right - w - 3))
    d.label:ClearAllPoints()
    d.label:SetPoint("BOTTOMLEFT", self.track, "TOPLEFT", lx, math.min(-FLAG_HEAD, -y + 6))
    d:Show()
end

-- A left button pressed on a chip: remember where, so the release can tell a click from a drag. A
-- template chip carries kind "saved" and its id; a cooldown chip kind "cooldown" and its cooldown.
function Methods:StartChipMove(c)
    local x, y = GetCursorPosition()
    if c.chipKind == "saved" and c.savedID then
        self.chipMove = { kind = "saved", id = c.savedID, chip = c, x0 = x, y0 = y }
    elseif c.chipKind == "cooldown" and c.cooldown then
        self.chipMove = { kind = "cooldown", cooldown = c.cooldown, chip = c, x0 = x, y0 = y }
    end
end

function Methods:CancelChipMove()
    self.chipMove = nil
    if self.chipGhost then
        self.chipGhost:Hide()
    end
    if self.dropLine then
        self.dropLine:Hide()
    end
end

local function chipMoved(cm)
    local x, y = GetCursorPosition()
    return cm.moved or math.abs(x - cm.x0) >= MOVE_DIST or math.abs(y - cm.y0) >= MOVE_DIST
end

-- Fills the ghost for the chip held in cm, by its kind.
local function fillGhost(g, cm)
    if cm.kind == "cooldown" then
        fillCooldownChip(g, cm.cooldown)
    else
        local s = CRT.AlertSaved and CRT.AlertSaved:Get(cm.id)
        if s then
            fillChip(g, s)
        end
    end
end

-- While a chip is held: once moved MOVE_DIST pixels a ghost of it follows the cursor, and over the track
-- the dashed line shows where it would land.
function Methods:UpdateChipMove()
    local cm = self.chipMove
    if not IsMouseButtonDown("LeftButton") then
        self:FinishChipMove() -- the release went elsewhere
        return
    end
    if not chipMoved(cm) then
        return
    end
    local g = self:ChipGhost()
    if not cm.moved then
        -- filled once, as the drag starts; after that it only follows the cursor
        cm.moved = true
        fillGhost(g, cm)
    end
    local scale = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    g:ClearAllPoints()
    g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    g:Show()
    if self.pull and overTrack(self) and not overEditor() then
        local tx, ty = cursorOnTrack(self)
        self:DrawDropLine(self:TimeAtX(tx), ty)
    elseif self.dropLine then
        self.dropLine:Hide()
    end
end

-- The left button let go of a chip. Not moved, it was a click and does nothing; released over the track,
-- the template or cooldown is placed there; anywhere else (or over the open alert editor), nothing.
function Methods:FinishChipMove()
    local cm = self.chipMove
    self:CancelChipMove()
    if not (cm and chipMoved(cm) and self.pull and overTrack(self)) or overEditor() then
        return
    end
    local x, y = cursorOnTrack(self)
    if cm.kind == "cooldown" then
        self:PlaceCooldown(cm.cooldown, self:TimeAtX(x))
    else
        self:PlaceSaved(cm.id, self:TimeAtX(x), self:IconSpellAt(x, y), self:LaneAtY(y))
    end
end

-- Makes a template from cooldown e: its name, spell and text, in caramel, with what a new alert in the
-- editor starts with (CRT.AlertEditor.NewDefaults, the one source of those).
function Methods:SaveCooldown(e)
    local Saved = CRT.AlertSaved
    if not (Saved and e) then
        return nil
    end
    local Editor = CRT.AlertEditor
    local fields = Editor and Editor.NewDefaults and Editor.NewDefaults() or {}
    local r, g, b = mocha("caramel")
    fields.name, fields.spellID, fields.text, fields.color = e.name, e.spellID, e.name, { r, g, b, 1 }
    return Saved:Save(nil, fields)
end

-- A chip's menu. A template: Edit, Rename, Delete. A cooldown: Save as template.
function Methods:ChipMenu(c)
    if c.chipKind == "cooldown" then
        local e = c.cooldown
        contextMenu(c, function(root)
            root:CreateTitle(e.name)
            root:CreateButton(TEXT.saveTemplate, function()
                self:SaveCooldown(e)
            end)
        end)
        return
    end
    local id = c.savedID
    local s = id and CRT.AlertSaved and CRT.AlertSaved:Get(id)
    if not s then
        return
    end
    contextMenu(c, function(root)
        root:CreateTitle(s.name or TEXT.unnamed)
        root:CreateButton(TEXT.edit, function()
            CRT.AlertEditor:EditSaved(id)
        end)
        root:CreateButton(TEXT.rename, function()
            askRename(id)
        end)
        root:CreateButton(TEXT.delete, function()
            askDelete(id)
        end)
    end)
end

-- The right button pressed on the track (or an icon or a flag on it): remember where and when, so its
-- release can tell a click (the menu) from a drag (which scrolls).
function Methods:RightDown(button)
    if button ~= "RightButton" then
        return
    end
    local x, y = GetCursorPosition()
    local tx, ty = cursorOnTrack(self)
    self.rightAt = { x = x, y = y, at = GetTime(), scroll = self.hscroll:GetHorizontalScroll(), tx = tx, ty = ty }
end

-- The right button let go: moved under MENU_DIST pixels and within MENU_TIME seconds, the press was a
-- click and opens the menu where it went down, putting back what it scrolled.
function Methods:RightUp(button, flag)
    if button ~= "RightButton" then
        return
    end
    local r = self.rightAt
    self.rightAt = nil
    if not (r and self.pull) then
        return
    end
    local scale = self.hscroll:GetEffectiveScale()
    local x, y = GetCursorPosition()
    if math.abs(x - r.x) / scale >= MENU_DIST or math.abs(y - r.y) / scale >= MENU_DIST or GetTime() - r.at > MENU_TIME then
        return
    end
    self:ScrollTo(r.scroll)
    if flag and flag.mark then
        self:FlagMenu(flag.mark, flag)
    else
        self:TrackMenu(r.tx, r.ty)
    end
end

-- A marker's menu: its text and time as the title, Edit (the double-click) and Delete. Alt+drag is the
-- way to add a time, so there is no Copy. A raid note line you may not change has View in place of
-- Edit (the editor opens it read-only) and no Delete.
function Methods:FlagMenu(m, owner)
    local title = tostring(m.text or "")
    title = title .. " \194\183 " .. CRT.AlertReminders.FormatTimes({ { ph = m.ph, t = m.time } })
    local changeable = canChange(m)
    contextMenu(owner, function(root)
        root:CreateTitle(title)
        root:CreateButton(changeable and TEXT.edit or TEXT.view, function()
            self:EditMark(m)
        end)
        if changeable then
            root:CreateButton(TEXT.delete, function()
                askDeleteMark(self, m)
            end)
        end
    end)
end

-- The track's menu at x, y on the track: its time and row as the title, New alert here (the double-click;
-- on a cast icon with that icon's spell), and Place, each template at that time (with the spell of a
-- cast icon there), then a Cooldowns submenu with the Cooldowns row's cooldowns.
function Methods:TrackMenu(x, y)
    local t = self:TimeAtX(x)
    local lane = self:LaneAtY(y)
    local title = clock(t)
    if lane and readable(lane.label) and type(lane.label) == "string" and lane.label ~= "" then
        title = title .. " \194\183 " .. lane.label
    end
    local spellID = self:IconSpellAt(x, y)
    contextMenu(self.hscroll, function(root)
        root:CreateTitle(title)
        root:CreateButton(TEXT.newHere, function()
            self:OpenAt(t, spellID)
        end)
        local place = root:CreateButton(TEXT.place)
        local list = CRT.AlertSaved and CRT.AlertSaved:List() or {}
        if #list == 0 then
            place:CreateTitle(TEXT.noSaved)
        end
        for _, e in ipairs(list) do
            place:CreateButton(e.s.name or TEXT.unnamed, function()
                self:PlaceSaved(e.id, t, spellID, lane)
            end)
        end
        -- the cooldowns the Cooldowns row lists now, placed as a drop there would be
        local cooldowns = place:CreateButton(TEXT.cooldowns)
        local cds = self:CooldownList()
        if #cds == 0 then
            cooldowns:CreateTitle(TEXT.noCooldowns)
        end
        for _, e in ipairs(cds) do
            cooldowns:CreateButton(e.name, function()
                self:PlaceCooldown(e, t)
            end)
        end
    end)
end

-- Draws the markers above the icons: raid note lines in caramel, your reminders in cream. A button
-- sits a level above every cast icon, so a flag over an icon is the one clicked.
function Methods:DrawMarks(length)
    local level = (self.track:GetFrameLevel() or 0) + 8
    for n, m in ipairs(self.marks) do
        local f = self:Flag(n)
        f.mark = m
        self:FlagHighlight(f)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", self.track, "TOPLEFT", View.TimeToX(m.t, length, self.trackW) - 1 - (FLAG_BTN_W - FLAG_W) / 2, -(m.row - 1) * ROW_H)
        f:SetFrameLevel(level)
        local key = m.mine and "cream" or "caramel"
        f.pole:SetColorTexture(mocha(key))
        f.head:SetColorTexture(mocha(key))
        local icon = chipIcon(m)
        f.icon:SetTexture(icon)
        f.edge:SetColorTexture(mocha(key))
        f.icon:SetShown(icon ~= nil)
        f.edge:SetShown(icon ~= nil)
        f.head:SetShown(icon == nil)
    end
    hideFrom(self.flags, #self.marks + 1)
end

function Methods:Label(n)
    return pooled(self.labels, n, function()
        local l = CreateFrame("Button", nil, self.body)
        l:SetSize(LABEL_W - 4, ROW_H)
        l.stripe = self.body:CreateTexture(nil, "BACKGROUND")
        l.stripe:SetColorTexture(mocha("cream", 0.04))
        l.icon = l:CreateTexture(nil, "ARTWORK")
        l.icon:SetSize(18, 18)
        l.icon:SetPoint("LEFT", l, "LEFT", 4, 0)
        l.text = l:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        l.text:SetPoint("LEFT", l, "LEFT", 26, 0)
        l.text:SetPoint("RIGHT", l, "RIGHT", -2, 0)
        l.text:SetJustifyH("LEFT")
        l.text:SetWordWrap(false)
        -- one dot per extra ability type, at the right end of the label
        l.dots = {}
        for d = 1, MAX_DOTS do
            local dot = l:CreateTexture(nil, "OVERLAY")
            dot:SetTexture(DOT)
            dot:SetSize(DOT_SIZE, DOT_SIZE)
            dot:SetPoint("RIGHT", l, "RIGHT", -4 - (d - 1) * (DOT_SIZE + 3), 0)
            dot:Hide()
            l.dots[d] = dot
        end
        l:SetScript("OnEnter", labelEnter)
        l:SetScript("OnLeave", hideTip)
        return l
    end)
end

-- The (?) on the Personal notes lane's label, just after its name: these are only yours and stay on
-- your PC. Hidden when no boss is shown.
function Methods:DrawPersonalHelp(lanes)
    local row
    for i, lane in ipairs(lanes) do
        if lane.kind == "personal" then
            row = i
        end
    end
    local h = self.personalHelp
    if not h then
        if not (row and CRT.UI and CRT.UI.Help) then
            return
        end
        h = CRT.UI.Help(self.body, TEXT.personal, TEXT.personalHelp)
        self.personalHelp = h
    end
    local l = row and self.labels[row]
    if not l then
        h:Hide()
        return
    end
    -- its name's own width (a width set by the label's anchors caps GetStringWidth)
    local w = textWidth(l.text)
    h:ClearAllPoints()
    -- the name starts 26 px in (after the icon); the (?) stays inside the label
    h:SetPoint("LEFT", l, "LEFT", math.min(26 + w, LABEL_W - 4 - 24), 0)
    h:SetFrameLevel((l:GetFrameLevel() or 0) + 2)
    h:Show()
end

-- Draws the axis labels and grid lines across the whole track.
function Methods:DrawAxis(length, height)
    local n = 0
    for _, sec in ipairs(View.Ticks(length, settings().grid, self.trackW)) do
        n = n + 1
        local x = View.TimeToX(sec, length, self.trackW)
        local line = pooled(self.lines, n, function()
            local tex = self.track:CreateTexture(nil, "BACKGROUND")
            tex:SetWidth(1)
            tex:SetColorTexture(mocha("caramel", 0.25))
            return tex
        end)
        line:SetPoint("TOPLEFT", self.track, "TOPLEFT", x, 0)
        line:SetHeight(height)
        local tick = pooled(self.ticks, n, function()
            local tex = self.axis:CreateTexture(nil, "ARTWORK")
            tex:SetSize(1, 5)
            tex:SetColorTexture(mocha("caramel"))
            return tex
        end)
        tick:SetPoint("BOTTOMLEFT", self.axis, "BOTTOMLEFT", x, 0)
        local text = pooled(self.texts, n, function()
            local fs = self.axis:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
            fs:SetTextColor(mocha("latte"))
            return fs
        end)
        text:SetPoint("BOTTOMLEFT", self.axis, "BOTTOMLEFT", x + 3, 4)
        text:SetText(View.Format(sec))
    end
    hideFrom(self.lines, n + 1)
    hideFrom(self.ticks, n + 1)
    hideFrom(self.texts, n + 1)
end

-- A texture on the track from one of the pools, made in this layer and color the first time.
function Methods:Tex(list, n, layer, r, g, b, a)
    return pooled(list, n, function()
        local tex = self.track:CreateTexture(nil, layer)
        tex:SetColorTexture(r, g, b, a)
        return tex
    end)
end

-- Draws a 2 px red line over all the lanes for each phase, with its label on the axis just right
-- of it, above the time labels. The implied first phase at 0:00 gets no line. Returns how many rows
-- of labels it used (0 to PHASE_ROWS), which the axis makes room for.
function Methods:DrawPhases(phases, length, height)
    local n, rows, rowEnds = 0, 0, {}
    for i, phase in ipairs(phases or {}) do
        if type(phase.t) == "number" and phase.t > 0 and phase.t <= length then
            n = n + 1
            local x = View.TimeToX(phase.t, length, self.trackW)
            local line = self:Tex(self.phaseLines, n, "ARTWORK", DEATH_RED[1], DEATH_RED[2], DEATH_RED[3], 1)
            -- the line being dragged is gold, the others red (set every draw, since lines are pooled)
            local dragging = self.phaseDrag and (self.pull and self.pull.reference and self.pull.reference.phases[self.phaseDrag.index]) == phase
            if dragging then
                line:SetColorTexture(1, 0.82, 0, 1)
            else
                line:SetColorTexture(DEATH_RED[1], DEATH_RED[2], DEATH_RED[3], 1)
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", self.track, "TOPLEFT", x - 1, 0)
            line:SetSize(2, height)
            local text = pooled(self.phaseTexts, n, function()
                local fs = self.axis:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
                fs:SetTextColor(mocha("latte"))
                return fs
            end)
            -- the part a chosen order put in this phase is added to the drawn label only: the alerts
            -- read a phase's number from phase.label, which stays as written
            local part = self.extra and self.extra.parts and self.extra.parts[i]
            local label = phase.label
            if part then
                label = label and (label .. " \194\183 " .. part) or part
            end
            text:SetText(label or "")
            -- labels go in the first row they fit in without touching the one before, so close phase
            -- lines stagger; a third that fits nowhere goes back to the first row
            local row = 0
            if label then
                local w = text.GetStringWidth and text:GetStringWidth() or #label * 6
                while row < PHASE_ROWS and (rowEnds[row] or -math.huge) > x do
                    row = row + 1
                end
                if row == PHASE_ROWS then
                    row = 0
                end
                rowEnds[row] = x + 3 + w + 6
                rows = math.max(rows, row + 1)
            end
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", self.axis, "TOPLEFT", x + 3, -1 - row * PHASE_ROW_H)
        end
    end
    hideFrom(self.phaseLines, n + 1)
    hideFrom(self.phaseTexts, n + 1)
    return rows
end

-- Draws the 2 px line where the overlaid pull ended, or hides it when there is none.
function Methods:DrawEndLine(t, length, height)
    if type(t) ~= "number" then
        if self.endLine then
            self.endLine:Hide()
        end
        return
    end
    if not self.endLine then
        self.endLine = self.track:CreateTexture(nil, "ARTWORK")
        self.endLine:SetColorTexture(mocha("caramel"))
    end
    self.endLine:ClearAllPoints()
    self.endLine:SetPoint("TOPLEFT", self.track, "TOPLEFT", View.TimeToX(math.min(t, length), length, self.trackW) - 1, 0)
    self.endLine:SetSize(2, height)
    self.endLine:Show()
end

-- A reference lane's bars (as long as each cast lasts) and lead lines (from the cast's start to
-- its icon), drawn behind the icons. Returns the new counts of bars and lead lines used.
function Methods:DrawPlan(lane, mid, length, bars, leads)
    local c = lane.color
    for _, mark in ipairs(lane.marks) do
        local x = View.TimeToX(mark.t, length, self.trackW)
        if type(mark.dur) == "number" and mark.dur > 0 and mark.t < length then
            bars = bars + 1
            local bar = self:Tex(self.bars, bars, "BORDER", 1, 1, 1, 1)
            if c then
                bar:SetColorTexture(c[1], c[2], c[3], BAR_ALPHA)
            else
                bar:SetColorTexture(mocha("caramel", BAR_ALPHA))
            end
            bar:ClearAllPoints()
            bar:SetSize(math.max(1, View.TimeToX(math.min(mark.t + mark.dur, length), length, self.trackW) - x), DUR_H)
            bar:SetPoint("LEFT", self.track, "TOPLEFT", x, mid)
        end
        if type(lane.lead) == "number" and lane.lead > 0 and mark.t > 0 then
            leads = leads + 1
            local line = self:Tex(self.leads, leads, "BORDER", LEAD_GREEN[1], LEAD_GREEN[2], LEAD_GREEN[3], 1)
            local from = View.TimeToX(math.max(0, mark.t - lane.lead), length, self.trackW)
            line:ClearAllPoints()
            line:SetSize(math.max(1, x - from), 1)
            line:SetPoint("LEFT", self.track, "TOPLEFT", from, mid)
        end
    end
    return bars, leads
end

-- An overlaid pull's casts: small caramel bars with no tooltip, since their spells are unknown.
-- Returns the new count of ticks used.
function Methods:DrawTicks(lane, mid, length, ticks)
    for _, mark in ipairs(lane.marks) do
        ticks = ticks + 1
        local tick = self:Tex(self.pullTicks, ticks, "ARTWORK", mocha("caramel"))
        tick:ClearAllPoints()
        tick:SetSize(TICK_W, TICK_H)
        tick:SetPoint("CENTER", self.track, "TOPLEFT", View.TimeToX(mark.t, length, self.trackW), mid)
    end
    return ticks
end

function Methods:Refresh()
    local s = settings()
    local pull = self.pull
    local extra
    if pull then
        local rows = CRT.TimelineJournal:Rows(self.encounterID)
        self.lanes, self.unknown, extra = View.Lanes(pull, rows, s, self.encounterID, self.overlay, self.group, self.order)
    else
        self.lanes, self.unknown = {}, {}
    end
    self.extra = extra or { phases = {}, length = 0 }
    local lanes = self.lanes
    local width = self:VisibleWidth()
    local length = pull and math.max(1, self.extra.length or 0) or 1
    -- the saved notes' markers, collected before the lanes are drawn since they may add the Notes lane
    self.marks = self:Marks(lanes, length)
    self.trackW = pull and math.max(1, length * width / clampSpan(s.span)) or 1
    local height = math.max(1, #lanes * ROW_H)
    -- the track reaches at least the bottom of the window, so the empty space under the lanes takes
    -- a double-click too; when the lanes fit there is still nothing to scroll up and down
    local area = math.max(height, self.vscroll:GetHeight() or 0)
    self.body:SetSize(math.max(1, self.vscroll:GetWidth() or 1), area)
    self.track:SetSize(self.trackW, area)
    self.axis:SetSize(self.trackW, self.axisH or AXIS_H)
    if self.hscroll.UpdateScrollChildRect then
        self.hscroll:UpdateScrollChildRect() -- so a zoom scroll right after is not cut to the old range
    end
    if pull then
        self:DrawAxis(length, height)
    else
        hideFrom(self.lines, 1)
        hideFrom(self.ticks, 1)
        hideFrom(self.texts, 1)
    end
    local phaseRows = self:DrawPhases(pull and self.extra.phases, length, height)
    -- the axis grows by a row for each row of phase labels, so they never cover the time labels
    local axisH = AXIS_H + phaseRows * PHASE_ROW_H
    if axisH ~= (self.axisH or AXIS_H) then
        self.axisH = axisH
        self.axisScroll:SetHeight(axisH)
        self.axis:SetSize(self.trackW, axisH)
        self.vscroll:SetPoint("TOPLEFT", self.vscroll:GetParent(), "TOPLEFT", 0, -axisH)
    end
    self:DrawEndLine(pull and self.extra.endLine, length, height)

    local size = s.iconSize or 22
    local used, bars, leads, ticks = 0, 0, 0, 0
    for i, lane in ipairs(lanes) do
        local y = -(i - 1) * ROW_H
        local l = self:Label(i)
        l.lane = lane
        l:SetPoint("TOPLEFT", self.body, "TOPLEFT", 2, y)
        l.stripe:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, y)
        l.stripe:SetPoint("BOTTOMRIGHT", self.body, "TOPRIGHT", 0, y - ROW_H)
        -- a reference row is tinted faintly in its type's color; other rows keep the alternate stripe
        local tint = lane.kind == "reference" and lane.color
        if tint then
            l.stripe:SetColorTexture(tint[1], tint[2], tint[3], TINT_ALPHA)
        else
            l.stripe:SetColorTexture(mocha("cream", 0.04))
        end
        l.stripe:SetShown(tint and true or i % 2 == 0)
        -- the extra types (after the first, which colors the row) as dots: types 2 up to MAX_DOTS + 1 in reading order, the leftmost dot being type 2
        local extras = lane.kind == "reference" and lane.types or {}
        local dotCount = math.min(MAX_DOTS, math.max(0, #extras - 1))
        local Reference = CRT.TimelineReference
        for d = 1, MAX_DOTS do
            local key = extras[dotCount - d + 2]
            local t = d <= dotCount and key and Reference and Reference.TYPES[key]
            if t then
                l.dots[d]:SetVertexColor(t.color[1], t.color[2], t.color[3])
                l.dots[d]:Show()
            else
                l.dots[d]:Hide()
            end
        end
        l.text:SetPoint("RIGHT", l, "RIGHT", -2 - dotCount * (DOT_SIZE + 3), 0)
        l.icon:SetTexture(lane.icon)
        l.text:SetText(lane.label or "")
        if lane.class then
            l.text:SetTextColor(CRT.Groups.ClassColor(lane.label, lane.class))
        elseif lane.color then
            l.text:SetTextColor(lane.color[1], lane.color[2], lane.color[3])
        elseif lane.kind == "ticks" then
            l.text:SetTextColor(mocha("latte"))
        else
            l.text:SetTextColor(mocha("cream"))
        end
        local mid = y - ROW_H / 2
        if lane.kind == "reference" then
            bars, leads = self:DrawPlan(lane, mid, length, bars, leads)
        end
        if lane.kind == "ticks" then
            ticks = self:DrawTicks(lane, mid, length, ticks)
        end
        -- older marks first, so the shown pull's deaths are drawn on top; ticks have no icons
        for m = #lane.marks, lane.kind == "ticks" and #lane.marks + 1 or 1, -1 do
            local mark = lane.marks[m]
            used = used + 1
            local b = self:Icon(used)
            b.mark, b.lane = mark, lane
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("CENTER", self.track, "TOPLEFT", View.TimeToX(mark.t, length, self.trackW), y - ROW_H / 2)
            b:SetFrameLevel((self.track:GetFrameLevel() or 0) + 5 - math.min(mark.age or 0, 4))
            if mark.death then
                b.tex:SetTexture(SKULL)
                if lane.class then
                    b.bg:SetColorTexture(DEATH_RED[1], DEATH_RED[2], DEATH_RED[3])
                else
                    local r, g, bl = CRT.Groups.ClassColor(mark.death.name, mark.death.class)
                    b.bg:SetColorTexture(r, g, bl)
                end
            else
                local icon = lane.icon
                if lane.kind == "spell" and not icon then
                    local ok, tex = pcall(C_Spell.GetSpellTexture, mark.spellID)
                    icon = ok and tex or UNNAMED_ICON
                end
                b.tex:SetTexture(icon)
                b.bg:SetColorTexture(0, 0, 0)
            end
            -- earlier pulls fade by age; the floor keeps a fifth pull back visible
            b:SetAlpha(math.max(0.1, 1 - 0.25 * (mark.age or 0)))
        end
    end
    hideFrom(self.labels, #lanes + 1)
    for i = #lanes + 1, #self.labels do
        self.labels[i].stripe:Hide()
    end
    self:DrawPersonalHelp(lanes)
    hideFrom(self.icons, used + 1)
    hideFrom(self.bars, bars + 1)
    hideFrom(self.leads, leads + 1)
    hideFrom(self.pullTicks, ticks + 1)

    local names = {}
    for _, death in ipairs(self.unknown) do
        names[#names + 1] = death.name or "Unknown"
    end
    self.unknownText:SetText(#names > 0 and ("Time unknown: " .. table.concat(names, ", ")) or "")
    self:DrawHighlight(lanes)
    self:DrawMarks(length)
    self:DrawStrip()
    self:ScrollTo(self.hscroll:GetHorizontalScroll())
end
