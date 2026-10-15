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
local DUR_H = 12 -- the height of a duration bar
local TICK_W, TICK_H = 3, 10 -- one cast of an overlaid pull
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local UNNAMED_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

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

local function iconEnter(b)
    local mark, lane = b.mark, b.lane
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if mark.death then
        local d = mark.death
        GameTooltip:SetText(d.name or "Unknown", CRT.Groups.ClassColor(d.name, d.class))
        GameTooltip:AddLine(type(d.t) == "number" and ("Died at " .. View.Format(d.t)) or "time unknown", 1, 1, 1)
        local killer = spellName(d.spellID)
        GameTooltip:AddLine(killer and ("Killed by " .. killer) or "Killing blow unknown", 0.85, 0.85, 0.85)
        if settings().overlayOn and mark.pull and mark.pull.id then
            GameTooltip:AddLine("Pull " .. mark.pull.id, 0.85, 0.85, 0.85)
        end
    elseif lane.kind == "reference" then
        if lane.spellID and lane.spellID ~= 0 then
            GameTooltip:SetSpellByID(lane.spellID)
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
    elseif lane.kind == "unnamed" then
        GameTooltip:SetText("Boss cast (unnamed)", 1, 1, 1)
        GameTooltip:AddLine("Cast at " .. View.Format(mark.t), 0.85, 0.85, 0.85)
        if type(mark.dur) == "number" and mark.dur > 0 then
            GameTooltip:AddLine(string.format("Duration %.1fs", mark.dur), 0.85, 0.85, 0.85)
        end
    else
        GameTooltip:SetSpellByID(mark.spellID)
        GameTooltip:AddLine("Cast at " .. View.Format(mark.t), 1, 1, 1)
    end
    GameTooltip:Show()
end

local function labelEnter(l)
    if l.lane and l.lane.kind == "spell" then
        GameTooltip:SetOwner(l, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(l.lane.spellID)
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
    hscroll:SetScript("OnMouseDown", function()
        view:StartDrag()
    end)
    hscroll:SetScript("OnMouseUp", function()
        view:StopDrag()
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
    return view
end

-- base is a recorded pull or { reference = ref }; overlay is a pull laid over a reference.
function Methods:SetData(base, encounterID, overlay)
    self.pull, self.encounterID, self.overlay = base, encounterID, overlay
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

function Methods:StartDrag()
    self.dragX = GetCursorPosition() / self.hscroll:GetEffectiveScale()
    self.dragFrom = self.hscroll:GetHorizontalScroll()
end

function Methods:StopDrag()
    self.dragX = nil
end

function Methods:OnUpdate()
    if self.dragX then
        if IsMouseButtonDown("LeftButton") then
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
        b:SetScript("OnMouseDown", function()
            self:StartDrag()
        end)
        b:SetScript("OnMouseUp", function()
            self:StopDrag()
        end)
        return b
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
                bar:SetColorTexture(c[1], c[2], c[3], 0.35)
            else
                bar:SetColorTexture(mocha("caramel", 0.35))
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
    self.trackW = pull and math.max(1, length * width / clampSpan(s.span)) or 1
    local height = math.max(1, #lanes * ROW_H)
    self.body:SetSize(math.max(1, self.vscroll:GetWidth() or 1), height)
    self.track:SetSize(self.trackW, height)
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
        l.stripe:SetShown(i % 2 == 0)
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
    self:ScrollTo(self.hscroll:GetHorizontalScroll())
end
