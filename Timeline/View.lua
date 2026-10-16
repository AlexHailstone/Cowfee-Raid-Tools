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

local View = {}
CRT.TimelineView = View

local LABEL_W = 150 -- the lane name column
local ROW_H = 30
local AXIS_H = 20
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
local FLAG_W, FLAG_HEAD = 12, 14 -- a marker's flag, drawn on a pole as tall as the row less 6 px
local FLAG_BTN_W = 20 -- the clickable marker: a square at the row top, the flag centred in it
local DOUBLE_TIME, DOUBLE_DIST = 0.3, 6 -- two clicks on the track this close make a double-click

local TEXT = {
    markerHint = "Drag to move it, Alt+drag to copy it, right-click for Edit, Copy and Delete.",
    menuEdit = "Edit",
    menuCopy = "Copy",
    menuDelete = "Delete",
    copied = "Copied the note line. Drag the copy to its time.",
    notes = "Notes",
    everyone = "Everyone",
    noOne = "No one (timers window only)",
    onlyMe = "Only me",
    raidNote = "Raid note",
    raidNoteOf = "Raid note (%s)",
    yourReminder = "Your reminder",
    reminder = "Reminder",
    spell = "Spell %d",
    needPull = "Reminders need the boss pulled once, or its reference to have an Encounter line.",
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
    if m.noteID then
        GameTooltip:AddLine(TEXT.markerHint, 0.6, 0.9, 0.6, true)
    end
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
        flags = {}, marks = {},
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
    view.unknownText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 2)
    view.unknownText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 2)
    view.unknownText:SetJustifyH("LEFT")

    -- the sideways scroll bar under the track
    local bar = CreateFrame("Slider", nil, f)
    bar:SetOrientation("HORIZONTAL")
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LABEL_W, UNKNOWN_H + 2)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLLBAR_W, UNKNOWN_H + 2)
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
    vscroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLLBAR_W, UNKNOWN_H + BAR_H + 4)
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
        view:StartDrag(button)
    end)
    hscroll:SetScript("OnMouseUp", function(_, button)
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
    return view
end

-- base is a recorded pull or { reference = ref }; overlay is a pull laid over a reference.
function Methods:SetData(base, encounterID, overlay, bossName)
    self.pull, self.encounterID, self.overlay, self.bossName = base, encounterID, overlay, bossName
    self:Refresh()
    self:ScrollTo(0)
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
    local drag = self.markDrag
    if drag then
        if not IsMouseButtonDown("LeftButton") then
            self:FinishMarkDrag()
        else
            if not drag.moved and math.abs(GetCursorPosition() - drag.x) > 4 then
                drag.moved = true
                drag.f:SetAlpha(drag.copy and 0.6 or 1)
            end
            if drag.moved then
                local t = self:CursorTime()
                local m = drag.f.mark
                drag.f:ClearAllPoints()
                drag.f:SetPoint("TOPLEFT", self.track, "TOPLEFT", View.TimeToX(t, self.markLength or 1, self.trackW) - 1 - (FLAG_BTN_W - FLAG_W) / 2, -(m.row - 1) * ROW_H)
                self.hover:SetText((drag.copy and "Copy to " or "Move to ") .. View.Format(math.floor(t + 0.5)))
            end
        end
    end
    if self.dragX then
        if IsMouseButtonDown("RightButton") then
            local x = GetCursorPosition() / self.hscroll:GetEffectiveScale()
            self:ScrollTo(self.dragFrom - (x - self.dragX))
        else
            self.dragX = nil
        end
    end
    if self.markDrag and self.markDrag.moved then
        -- a marker being dragged shows its own time in the hover text
        return
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
        end)
        b:SetScript("OnMouseUp", function()
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
function Methods:OpenAt(t, spellID, text)
    local encounterID = self:EncounterNumber()
    if not encounterID then
        CRT:Print(TEXT.needPull)
        return
    end
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

-- Double-click on a cast icon opens the editor for that boss with the spell and the time filled in.
-- Deaths and the overlaid pull's ticks do nothing.
function Methods:IconDoubleClick(b)
    -- the click's mouse-down started a drag; undo it so the view stays where it was
    if self.dragX then
        self:ScrollTo(self.dragFrom)
        self:StopDrag()
    end
    local lane, mark = b.lane, b.mark
    if not (lane and mark and type(mark.t) == "number") or mark.death then
        return
    end
    if not (lane.kind == "reference" or lane.kind == "spell" or lane.kind == "unnamed") then
        return
    end
    -- the lane's spell, else the cast's own (an unnamed lane holds casts the Journal doesn't list)
    local spellID = type(lane.spellID) == "number" and lane.spellID > 0 and lane.spellID or nil
    if not spellID and type(mark.spellID) == "number" and mark.spellID > 0 then
        spellID = mark.spellID
    end
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
-- difficulty's note) and every time of your reminders. On a recorded pull only phase 1 can be placed.
-- Each gets the lane it goes on; those with no row of their own go on a Notes lane, added at the
-- bottom of lanes. Returns { { t, ph, time, row, text, tags, mine, noteID, line, difficulty, id } }.
function Methods:Marks(lanes, length)
    local out = {}
    local Reminders = CRT.AlertReminders
    local encounterID = self.pull and Reminders and self:EncounterNumber()
    if not encounterID then
        return out
    end
    local ref = self.pull.reference
    local function add(m, spellID, text)
        m.spellID = type(spellID) == "number" and spellID > 0 and spellID or nil
        m.t = Reminders.AbsoluteTime(ref, m.ph, m.time)
        if not (m.t and m.t >= 0 and m.t <= length) then
            return
        end
        m.text = (type(text) == "string" and text ~= "" and text) or Reminders.SpellName(spellID)
            or (type(spellID) == "number" and string.format(TEXT.spell, spellID)) or TEXT.reminder
        m.row = rowFor(lanes, spellID, text)
        out[#out + 1] = m
    end
    local Notes = CRT.Notes
    if Notes and Notes.List then
        for _, n in ipairs(Notes:List()) do
            if n.record.encounterID == encounterID then
                local note = Notes:Parsed(n.id)
                for _, timer in ipairs(note and note.timers or {}) do
                    add({ ph = timer.ph, time = timer.time, tags = timer.tags, noteID = n.id, line = timer.line,
                        difficulty = n.record.difficulty }, timer.spellId, timer.text)
                end
            end
        end
    end
    for _, e in ipairs(Reminders:List(encounterID)) do
        for _, at in ipairs((Reminders:Times(encounterID, e.r))) do
            add({ ph = at.ph, time = at.t, mine = true, encounterID = encounterID, id = e.id }, e.r.spellID, e.r.text)
        end
    end
    local notesRow
    for _, m in ipairs(out) do
        if not m.row then
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
        -- A line with a spell shows the spell's icon in place of the flag; who and when are on hover.
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetPoint("CENTER", f, "CENTER", 0, -2)
        f.icon:SetSize(FLAG_BTN_W - 2, FLAG_BTN_W - 2)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.icon:Hide()
        f:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
        f:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.15)
        f:SetScript("OnEnter", flagEnter)
        f:SetScript("OnLeave", hideTip)
        f:SetScript("OnMouseDown", function(_, button)
            self.clickAt = nil
            if button == "LeftButton" and f.mark and f.mark.noteID then
                -- a note line: dragging moves it in time, with Alt held it copies it
                self.markDrag = { f = f, x = GetCursorPosition(), copy = IsAltKeyDown() }
                return
            end
            f.rightFrom = self.hscroll:GetHorizontalScroll()
            self:StartDrag(button)
        end)
        f:SetScript("OnMouseUp", function(_, button)
            if self.markDrag then
                self:FinishMarkDrag()
                return
            end
            self:StopDrag()
            -- a right-click that didn't scroll the view opens the marker's menu
            if button == "RightButton" and f.rightFrom and math.abs(self.hscroll:GetHorizontalScroll() - f.rightFrom) < 3 then
                self:MarkMenu(f)
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
    if self.dragX then
        self:ScrollTo(self.dragFrom)
        self:StopDrag()
    end
    local m = f.mark
    if not m then
        return
    end
    if m.noteID then
        CRT.AlertEditor:OpenNote(m.noteID, m.line)
    else
        CRT.AlertEditor:Open(m.encounterID, m.id)
    end
end

-- Draws the markers above the icons: raid note lines in caramel, your reminders in cream. A button
-- sits a level above every cast icon, so a flag over an icon is the one clicked.
function Methods:DrawMarks(length)
    local level = (self.track:GetFrameLevel() or 0) + 8
    for n, m in ipairs(self.marks) do
        local f = self:Flag(n)
        f.mark = m
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", self.track, "TOPLEFT", View.TimeToX(m.t, length, self.trackW) - 1 - (FLAG_BTN_W - FLAG_W) / 2, -(m.row - 1) * ROW_H)
        f:SetFrameLevel(level)
        local key = m.mine and "cream" or "caramel"
        f.pole:SetColorTexture(mocha(key))
        f.head:SetColorTexture(mocha(key))
        local icon = m.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(m.spellID)
        f.icon:SetTexture(icon)
        f.icon:SetShown(icon ~= nil)
        f.pole:SetShown(icon == nil)
        f.head:SetShown(icon == nil)
        f:SetAlpha(1)
    end
    hideFrom(self.flags, #self.marks + 1)
    self.markLength = length
end

-- The time (seconds from the start of the view) under the cursor on the track.
function Methods:CursorTime()
    local x = self.hscroll:GetHorizontalScroll() + cursorX(self.hscroll)
    return math.max(0, x * (self.markLength or 1) / math.max(1, self.trackW or 1))
end

-- A note marker let go after a drag: its line moves to the new time, or a copy goes there with Alt.
-- A press with no real movement is a click, which changes nothing (a double-click opens it).
function Methods:FinishMarkDrag()
    local drag = self.markDrag
    self.markDrag = nil
    if not drag or not drag.moved then
        return
    end
    local m = drag.f.mark
    local seconds = m.time + (self:CursorTime() - m.t)
    if not CRT.Notes:SetLineTime(m.noteID, m.line, seconds, drag.copy) then
        CRT:Print("That note line changed since the timeline was drawn. Try again.")
        self:Refresh()
    end
end

-- The right-click menu of a marker: Edit, and for a note line Copy and Delete.
function Methods:MarkMenu(f)
    local m = f.mark
    if not (m and MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    MenuUtil.CreateContextMenu(f, function(_, root)
        root:CreateTitle(m.text or "")
        root:CreateButton(TEXT.menuEdit, function()
            self:FlagDoubleClick(f)
        end)
        if m.noteID then
            root:CreateButton(TEXT.menuCopy, function()
                if CRT.Notes:SetLineTime(m.noteID, m.line, m.time, true) then
                    CRT:Print(TEXT.copied)
                end
            end)
            root:CreateButton(TEXT.menuDelete, function()
                local _, raw = CRT.Notes:TimerAt(m.noteID, m.line)
                if not (raw and CRT.Notes:RemoveLine(m.noteID, m.line, raw)) then
                    CRT:Print("That note line changed since the timeline was drawn. Try again.")
                    self:Refresh()
                end
            end)
        end
    end)
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
-- of it. The implied first phase at 0:00 gets no line.
function Methods:DrawPhases(phases, length, height)
    local n = 0
    for _, phase in ipairs(phases or {}) do
        if type(phase.t) == "number" and phase.t > 0 and phase.t <= length then
            n = n + 1
            local x = View.TimeToX(phase.t, length, self.trackW)
            local line = self:Tex(self.phaseLines, n, "ARTWORK", DEATH_RED[1], DEATH_RED[2], DEATH_RED[3], 1)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", self.track, "TOPLEFT", x - 1, 0)
            line:SetSize(2, height)
            local text = pooled(self.phaseTexts, n, function()
                local fs = self.axis:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
                fs:SetTextColor(mocha("latte"))
                return fs
            end)
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", self.axis, "TOPLEFT", x + 3, -1)
            text:SetText(phase.label or "")
        end
    end
    hideFrom(self.phaseLines, n + 1)
    hideFrom(self.phaseTexts, n + 1)
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
        self.lanes, self.unknown, extra = View.Lanes(pull, rows, s, self.encounterID, self.overlay)
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
    self.axis:SetSize(self.trackW, AXIS_H)
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
    self:DrawPhases(pull and self.extra.phases, length, height)
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
        -- the extra types (after the first, which colors the row) as dots, rightmost last
        local extras = lane.kind == "reference" and lane.types or {}
        local dotCount = math.min(MAX_DOTS, math.max(0, #extras - 1))
        local Reference = CRT.TimelineReference
        for d = 1, MAX_DOTS do
            local key = extras[#extras - d + 1]
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
    hideFrom(self.icons, used + 1)
    hideFrom(self.bars, bars + 1)
    hideFrom(self.leads, leads + 1)
    hideFrom(self.pullTicks, ticks + 1)

    local names = {}
    for _, death in ipairs(self.unknown) do
        names[#names + 1] = death.name or "Unknown"
    end
    self.unknownText:SetText(#names > 0 and ("Time unknown: " .. table.concat(names, ", ")) or "")
    self:DrawMarks(length)
    self:ScrollTo(self.hscroll:GetHorizontalScroll())
end
