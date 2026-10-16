local ADDON, CRT = ...

-- The alert areas: movable places on screen where the alerts engine's lines show as texts, icons,
-- circles or bars. Every area is made by Areas.New from a def, so they all move, preview, layer, pool,
-- grow, glow and show their settings the same way; each kind only says how one alert looks.
--
--   Areas.New(def) -> area, with def = {
--     key              names the area: its frame is CowfeeRaidToolsAlert<Key>, its preview "alert<key>"
--     output           the entry output it shows: "text", "icon", "circle" or "bar" (see Rules.Area)
--     layer            its UI.LAYERS key
--     title            its name, on the drag box
--     settingsKey      its settings are CRT.db.alerts.areas[settingsKey]: shown, cap, grow, position, and
--                      whatever its own rows add
--     defaultPosition  { point, relativePoint, x, y } until it is moved
--     make(parent)     -> a new widget, a Frame on parent. Made once per pool slot, never per refresh.
--                      Widgets never take the mouse, so the alerts let clicks through.
--     draw(widget, line, now, s, shownAt)  shows one line on a widget and sets its size. s is the area's
--                      settings; shownAt is the GetTime() the line's id first showed in this area (nil
--                      without an id), kept by id so it survives the line moving to another widget.
--     sample(now)      -> lines for Previews, each with `at` set
--     settings(panel, s)  adds the area's own rows to its settings on Raid Notes > Alerts with
--                      panel:Dropdown(label, opts), panel:Slider(label, opts), panel:Check(label, get, set) and
--                      panel:Color(label, get, set, enabledIf) (a swatch for the game's color picker; get() -> { r, g, b, a },
--                      set(new table); opts as for UI.Dropdown and UI.Slider). It is called every time the area
--                      shows there; the rows are made the first time and reused after. A change refreshes the
--                      area at once.
--   Optional, for an area whose settings or lines live elsewhere (the bars):
--     store()          -> the settings table, instead of CRT.db.alerts.areas[settingsKey]
--     lines(now, s, cap)  -> lines, more: the lines to show and how many were left out, instead of
--                      Rules.Area(Alerts:Lines(now), now, output, cap)
--     after(area, n, more)  called after each layout with the widgets shown and the count left out
--                      (lines beyond the cap included), such as for a "+N more" line
--     align(s)         -> "LEFT", "CENTER" or "RIGHT": with grow up or down, the widgets line up on that
--                      edge of a box HANDLE_MIN_WIDTH wide around the saved center
--   }
--
-- An area shows its lines soonest first, at most `cap` (1-10), the rest after the first in the `grow`
-- direction, 4 px apart. The first is centered on the saved position; with def.align and grow up or
-- down, it sits on that edge of a box HANDLE_MIN_WIDTH wide centered there instead. A line glows while
-- line.glow and now >= at. The drag box (title, settings button, reset) shows only with Previews, above
-- the area, or below it when it grows up. Every area refreshes from one ticker every 0.1 s, and only
-- while a run, a preview or a test is going; otherwise it hides once and does nothing.
--   area:Refresh()        draws it now
--   area:ResetPosition()  back to defaultPosition
--   area:Test(lines)      shows the given lines (with `at` set) until they have all passed
--   area:Visible()        -> { widget } on screen, for the tests; area.more is the count left out
--   area:Open()           opens Raid Notes > Alerts on this area (the ⚙ button)
--   area:Settings()       -> its settings table
--   Areas.Panel(parent, onChange)  the settings panel the Alerts tab shows an area's rows in (below)
--   Areas.Find(key)       the area with that def.key
--   Areas.Glow(widget, on)  a pulsing border on a widget's own frame
--   Areas.LineText(line), Areas.LineIcon(line), Areas.LineColor(line), Areas.SetFont(fontString, name,
--     size, outline): what a line shows, with values the game hides left out, and the area's font.

local Alerts = CRT.Alerts
local Rules = CRT.AlertRules
local UI = CRT.UI
local Areas = { list = {} }
CRT.AlertAreas = Areas

local TEXT = {
    drag = "%s: drag to move",
    settings = "Settings",
    show = "Show these alerts",
    cap = "At once",
    grow = "Grow",
    down = "Down",
    up = "Up",
    left = "Left",
    right = "Right",
}

local REFRESH_SECONDS = 0.1
local GAP = 4
local MAX_CAP = 10
local DEFAULT_CAP = 3
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local OUTLINES = { [""] = true, OUTLINE = true, THICKOUTLINE = true }
local HANDLE_HEIGHT = 20
local WINDOW_MARGIN = 20      -- the main window moved aside sits this far from the screen edge
local HANDLE_MIN_WIDTH = 220
local GEAR_TEXTURE = "Interface\\WorldMap\\Gear_64Grey" -- the settings button
local GEAR_SIZE = 16
local HANDLE_TITLE_LEFT = 6   -- the title's left edge on the drag box
local HANDLE_GEAR_RIGHT = 50  -- the settings button's right edge, from the drag box's right
local HANDLE_TITLE_GAP = 4    -- between the title and the settings button
local GLOW_SIZE = 2      -- the border's thickness
local GLOW_OUTSET = 3    -- how far it sits outside the widget
local GLOW_COLOR = { 1, 0.82, 0 }
local GLOW_PULSE = 0.4   -- seconds from bright to faint
local GLOW_FAINT = 0.25
local ROW_HEIGHT = 32
-- The settings panel's rows: label and control, unless a row asks for others, to fit half the tab.
local PANEL_LABEL_WIDTH, PANEL_CONTROL_WIDTH = 120, 180
local COLOR_GAP, COLOR_SWATCH = 5, 40 -- a color row's swatch, after a label as wide as the others'
local SLIDER_VALUE_WIDTH = 44 -- a slider's value beside its bar (UI/Controls.lua VALUE_W)

-- Each direction: the point a widget anchors by, the point of the one before it, and the gap's offset.
local GROW = {
    down = { "TOP", "BOTTOM", 0, -GAP },
    up = { "BOTTOM", "TOP", 0, GAP },
    left = { "RIGHT", "LEFT", -GAP, 0 },
    right = { "LEFT", "RIGHT", GAP, 0 },
}
-- With an alignment, the vertical directions anchor by that edge instead of the middle.
local ALIGNED = {
    down = { LEFT = { "TOPLEFT", "BOTTOMLEFT" }, CENTER = { "TOP", "BOTTOM" }, RIGHT = { "TOPRIGHT", "BOTTOMRIGHT" } },
    up = { LEFT = { "BOTTOMLEFT", "TOPLEFT" }, CENTER = { "BOTTOM", "TOP" }, RIGHT = { "BOTTOMRIGHT", "TOPRIGHT" } },
}
local GROW_OPTIONS = {
    { key = "down", label = TEXT.down },
    { key = "up", label = TEXT.up },
    { key = "left", label = TEXT.left },
    { key = "right", label = TEXT.right },
}

local EMPTY = {}

local function readable(v)
    return CRT.Timeline.readable(v)
end

local function number(v, default)
    return type(v) == "number" and v or default
end

local function capOf(s)
    return math.max(1, math.min(MAX_CAP, math.floor(number(s.cap, DEFAULT_CAP))))
end

local function report(err)
    if geterrorhandler then
        geterrorhandler()(err)
    end
end

-- What a line shows -----------------------------------------------------------------------

-- The line's text, else its spell's name, else "". Values the game hides never reach a string call.
function Areas.LineText(line)
    local t = line.text
    if readable(t) and type(t) == "string" and t ~= "" then
        return t
    end
    local id = line.spellID
    if readable(id) and type(id) == "number" and CRT.Notes then
        local info = CRT.Notes:SpellInfo(id)
        if info and readable(info.name) and type(info.name) == "string" then
            return info.name
        end
    end
    return ""
end

-- The line's icon, else its spell's icon, else nil.
function Areas.LineIcon(line)
    local icon = line.icon
    if readable(icon) and (type(icon) == "number" or type(icon) == "string") then
        return icon
    end
    local id = line.spellID
    if readable(id) and type(id) == "number" and CRT.Notes then
        local info = CRT.Notes:SpellInfo(id)
        if info and readable(info.icon) and (type(info.icon) == "number" or type(info.icon) == "string") then
            return info.icon
        end
    end
    return nil
end

-- The line's { r, g, b }, or nil.
function Areas.LineColor(line)
    local c = line.color
    if readable(c) and type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return nil
end

-- Sets a font string to a font from CRT:FontList (Friz Quadrata when the name is gone), only when it
-- changed, so a refresh does not look the font up again.
function Areas.SetFont(fontString, name, size, outline)
    outline = OUTLINES[outline] and outline or ""
    local key = tostring(name) .. "|" .. size .. "|" .. outline
    if fontString.crtFontKey == key then
        return
    end
    local path = CRT:FontPath(name) or DEFAULT_FONT
    fontString:SetFont(path, size, outline)
    -- A file that fails to load leaves the font unset, which GetFont shows.
    if not fontString:GetFont() then
        fontString:SetFont(DEFAULT_FONT, size, outline)
    end
    fontString.crtFontKey = key
end

-- Glow --------------------------------------------------------------------------------------

-- A pulsing border just outside the widget, from four textures on a frame of its own made the first
-- time, shown while `on`. Only the addon's own widgets glow.
function Areas.Glow(widget, on)
    local border = widget.glowBorder
    if not on then
        if border and border:IsShown() then
            border.pulse:Stop()
            border:Hide()
        end
        return
    end
    if not border then
        border = CreateFrame("Frame", nil, widget)
        border:SetPoint("TOPLEFT", -GLOW_OUTSET, GLOW_OUTSET)
        border:SetPoint("BOTTOMRIGHT", GLOW_OUTSET, -GLOW_OUTSET)
        border:SetFrameLevel((widget:GetFrameLevel() or 1) + 5)
        local function edge(from, to, width, height)
            local t = border:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], 1)
            t:SetPoint(from)
            t:SetPoint(to)
            if width then
                t:SetWidth(width)
            else
                t:SetHeight(height)
            end
        end
        edge("TOPLEFT", "TOPRIGHT", nil, GLOW_SIZE)
        edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, GLOW_SIZE)
        edge("TOPLEFT", "BOTTOMLEFT", GLOW_SIZE)
        edge("TOPRIGHT", "BOTTOMRIGHT", GLOW_SIZE)
        local pulse = border:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(GLOW_FAINT)
        fade:SetDuration(GLOW_PULSE)
        border.pulse = pulse
        border:Hide()
        widget.glowBorder = border
    end
    if not border:IsShown() then
        border:Show()
        border.pulse:Play()
    end
end

-- The settings panel -------------------------------------------------------------------------
-- The Alerts tab of Raid Notes (Notes/AlertsTab.lua) shows one area's settings at a time in a panel.
-- The common rows (Show these alerts, At once, Grow) are made once; an area's own rows are made the
-- first time it shows and kept, hidden while another area shows.

local Panel = {}
Panel.__index = Panel

local function makeCheck(parent, label, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.labelText = label
    local text = check:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    check.refresh = function()
        check:SetChecked(get() and true or false)
    end
    return check
end

local function copyColor(c)
    return { c[1], c[2], c[3], c[4] }
end

-- A row with a label and a swatch that opens the game's color picker (with opacity). get() returns
-- { r, g, b, a }; set(color) is given a new table. The picker writes through the set it opened with, so
-- one left open never writes into another area's settings, and Cancel puts the old color back.
local function makeColor(parent, label, slot, changed)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(PANEL_LABEL_WIDTH + COLOR_GAP + COLOR_SWATCH, ROW_HEIGHT)
    row.colorLabel = label
    local text = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", row, "LEFT", 0, 0)
    text:SetWidth(PANEL_LABEL_WIDTH)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(label)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(COLOR_SWATCH, 20)
    swatch:SetPoint("LEFT", row, "LEFT", PANEL_LABEL_WIDTH + COLOR_GAP, 0)
    swatch.edge = swatch:CreateTexture(nil, "BACKGROUND")
    swatch.edge:SetAllPoints()
    swatch.edge:SetColorTexture(0.5, 0.5, 0.5, 1)
    swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
    swatch.tex:SetPoint("TOPLEFT", 1, -1)
    swatch.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    row.swatch = swatch
    row.refresh = function()
        local c = slot.opts.get()
        swatch.tex:SetColorTexture(c[1], c[2], c[3], 1)
        if slot.opts.enabledIf then
            local on = slot.opts.enabledIf() and true or false
            swatch:SetEnabled(on)
            swatch:SetAlpha(on and 1 or 0.4)
            text:SetAlpha(on and 1 or 0.5)
        end
    end
    swatch:SetScript("OnClick", function()
        if not ColorPickerFrame then
            return
        end
        local set = slot.opts.set -- this showing's settings, kept until the picker closes
        local before = copyColor(slot.opts.get())
        local function apply()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or before[4]
            set({ r, g, b, a })
            changed()
        end
        local function cancel()
            set(copyColor(before))
            changed()
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = before[1], g = before[2], b = before[3], opacity = before[4], hasOpacity = true,
                swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
            })
        else
            ColorPickerFrame.hasOpacity = true
            ColorPickerFrame.opacity = 1 - before[4] -- the older picker counts transparency
            ColorPickerFrame.previousValues = { before[1], before[2], before[3], before[4] }
            ColorPickerFrame.func = apply
            ColorPickerFrame.opacityFunc = apply
            ColorPickerFrame.cancelFunc = cancel
            ColorPickerFrame:SetColorRGB(before[1], before[2], before[3])
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    return row
end

-- Reads every row of the area shown again.
function Panel:Refresh()
    if not (self.area and self.common) then
        return
    end
    for _, row in ipairs(self.common) do
        row.refresh()
    end
    local rows = self.rows[self.area]
    for i = 1, self.cursor do
        rows[i].row.refresh()
    end
end

-- After any change: the area redraws at once, the rows show the new values, and the tab hears of it.
function Panel:Changed()
    if self.area then
        self.area:Refresh()
    end
    self:Refresh()
    if self.onChange then
        self.onChange()
    end
end

-- The next of the shown area's own rows: the one made the first time it showed, or a new one from
-- make(slot). slot.opts is replaced on every showing, before any control is made (a control reads its
-- value as it is made), so the rows always read fresh settings.
function Panel:NextSlot(opts, make)
    local rows = self.rows[self.area]
    self.cursor = self.cursor + 1
    local slot = rows[self.cursor]
    if slot then
        slot.opts = opts
    else
        slot = { opts = opts }
        slot.row = make(slot)
        rows[self.cursor] = slot
    end
    return slot
end

function Panel:Dropdown(label, opts)
    local slot = self:NextSlot(opts, function(slot)
        return UI.Dropdown(self.frame, label, {
            options = function()
                local o = slot.opts.options
                return type(o) == "function" and o() or o
            end,
            get = function()
                return slot.opts.get()
            end,
            set = function(key)
                slot.opts.set(key)
                self:Changed()
            end,
            width = opts.width or PANEL_CONTROL_WIDTH,
            labelWidth = opts.labelWidth or PANEL_LABEL_WIDTH,
            enabledIf = function()
                return not slot.opts.enabledIf or slot.opts.enabledIf()
            end,
            decorate = opts.decorate and function(button, option)
                return slot.opts.decorate and slot.opts.decorate(button, option)
            end,
        })
    end)
    return slot.row
end

function Panel:Slider(label, opts)
    local slot = self:NextSlot(opts, function(slot)
        return UI.Slider(self.frame, label, {
            min = opts.min,
            max = opts.max,
            step = opts.step,
            format = opts.format,
            onRelease = opts.onRelease,
            width = opts.width or PANEL_CONTROL_WIDTH,
            labelWidth = opts.labelWidth or PANEL_LABEL_WIDTH,
            get = function()
                return slot.opts.get()
            end,
            set = function(value)
                slot.opts.set(value)
                self:Changed()
            end,
            enabledIf = function()
                return not slot.opts.enabledIf or slot.opts.enabledIf()
            end,
        })
    end)
    return slot.row
end

function Panel:Check(label, get, set)
    local slot = self:NextSlot({ get = get, set = set }, function(slot)
        return makeCheck(self.frame, label, function()
            return slot.opts.get()
        end, function(on)
            slot.opts.set(on)
            self:Changed()
        end)
    end)
    return slot.row
end

function Panel:Color(label, get, set, enabledIf)
    local slot = self:NextSlot({ get = get, set = set, enabledIf = enabledIf }, function(slot)
        return makeColor(self.frame, label, slot, function()
            self:Changed()
        end)
    end)
    return slot.row
end

function Panel:Place(row, y)
    row:ClearAllPoints()
    if row.labelText then
        -- A checkbox is smaller than its row, so it sits in the middle of it.
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", -4, y - (ROW_HEIGHT - 24) / 2)
    else
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, y)
    end
    row:Show()
end

-- The common rows read the shown area's settings as they are made, so they wait for the first area.
local function buildCommon(panel)
    local frame = panel.frame
    local function s()
        return panel.area:Settings()
    end
    panel.common = {
        makeCheck(frame, TEXT.show, function()
            return s().shown
        end, function(on)
            s().shown = on
            panel:Changed()
        end),
        UI.Slider(frame, TEXT.cap, {
            min = 1,
            max = MAX_CAP,
            labelWidth = PANEL_LABEL_WIDTH,
            width = PANEL_CONTROL_WIDTH,
            get = function()
                return capOf(s())
            end,
            set = function(value)
                s().cap = value
                panel:Changed()
            end,
        }),
        UI.Dropdown(frame, TEXT.grow, {
            options = GROW_OPTIONS,
            labelWidth = PANEL_LABEL_WIDTH,
            width = PANEL_CONTROL_WIDTH,
            get = function()
                return GROW[s().grow] and s().grow or "down"
            end,
            set = function(key)
                s().grow = key
                panel:Changed()
            end,
        }),
    }
    for _, row in ipairs(panel.common) do
        row:Hide()
    end
end

-- Shows one area's rows, top to bottom, and hides every other area's. The panel's height follows.
function Panel:Select(area)
    self.area = area
    if not self.common then
        buildCommon(self)
    end
    for other, rows in pairs(self.rows) do
        if other ~= area then
            for _, slot in ipairs(rows) do
                slot.row:Hide()
            end
        end
    end
    self.rows[area] = self.rows[area] or {}
    self.cursor = 0
    if area.def.settings then
        area.def.settings(self, area:Settings())
    end
    -- A row that an earlier showing made but this one did not ask for stays hidden.
    local rows = self.rows[area]
    for i = self.cursor + 1, #rows do
        rows[i].row:Hide()
    end
    local y = 0
    for _, row in ipairs(self.common) do
        self:Place(row, y)
        y = y - ROW_HEIGHT
    end
    for i = 1, self.cursor do
        self:Place(rows[i].row, y)
        y = y - ROW_HEIGHT
    end
    self.frame:SetHeight(-y)
    self:Refresh()
end

-- Areas.Panel(parent, onChange) -> panel, with panel.frame a Frame of its own on parent:
--   panel:Select(area)   shows that area's rows: Show these alerts, At once, Grow, then its own
--   panel.area           the area it shows
--   panel:Refresh()      reads every row again
--   panel:Dropdown/Slider/Check/Color  what def.settings(panel, s) adds its rows with
-- onChange() is called after any change made on it.
function Areas.Panel(parent, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(PANEL_LABEL_WIDTH + COLOR_GAP + PANEL_CONTROL_WIDTH + SLIDER_VALUE_WIDTH, ROW_HEIGHT)
    local panel = setmetatable({ frame = frame, rows = {}, cursor = 0, onChange = onChange }, Panel)
    return panel
end

-- The area with this key ("icons", "texts", "bars" or "circles"), or nil.
function Areas.Find(key)
    for _, area in ipairs(Areas.list) do
        if area.def.key == key then
            return area
        end
    end
    return nil
end

-- The area -----------------------------------------------------------------------------------

local Area = {}
Area.__index = Area

function Area:Settings()
    if self.def.store then
        return self.def.store()
    end
    local alerts = CRT.db.alerts
    alerts.areas = alerts.areas or {}
    local s = alerts.areas[self.def.settingsKey]
    if not s then
        s = {}
        alerts.areas[self.def.settingsKey] = s
    end
    return s
end

function Area:ApplyPosition()
    local p = self:Settings().position or self.def.defaultPosition or DEFAULT_POSITION
    self.frame:ClearAllPoints()
    self.frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or p.point or "CENTER", p.x or 0, p.y or 0)
end

function Area:ResetPosition()
    self:Settings().position = nil
    if self.frame then
        self:ApplyPosition()
    end
end

-- The drag box is wide enough for the whole title left of the settings button and Reset, never narrower
-- than before. Measured again whenever Previews turn on, so a font change applies.
function Area:MeasureHandle()
    local title = self.handleTitle
    if not (title and self.handle) then
        return
    end
    local titleWidth = title.GetUnboundedStringWidth and title:GetUnboundedStringWidth() or title:GetStringWidth()
    self.handleMin = math.max(HANDLE_MIN_WIDTH, math.ceil(HANDLE_TITLE_LEFT + titleWidth + HANDLE_TITLE_GAP + HANDLE_GEAR_RIGHT + GEAR_SIZE))
    self.handle:SetWidth(self.handleMin)
end

function Area:Build()
    if self.frame then
        return
    end
    local key = self.def.key
    local frame = CreateFrame("Frame", "CowfeeRaidToolsAlert" .. key:sub(1, 1):upper() .. key:sub(2), UIParent)
    self.frame = frame
    frame:SetSize(HANDLE_MIN_WIDTH, HANDLE_HEIGHT)
    UI:RegisterLayer(self.def.layer, frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)

    local handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    self.handle = handle
    handle:SetSize(HANDLE_MIN_WIDTH, HANDLE_HEIGHT)
    handle:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    self.handleBelow = false
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    handle:SetBackdropColor(0.3, 0.25, 0.05, 0.9)
    handle:SetBackdropBorderColor(1, 0.82, 0, 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local title = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    title:SetPoint("LEFT", 6, 0)
    title:SetText(format(TEXT.drag, self.title))
    CRT.UI.ResetButton(handle, function()
        self:ResetPosition()
    end):SetPoint("RIGHT", -2, 0)
    self.handleTitle = title
    self:MeasureHandle()

    local gear = CreateFrame("Button", nil, handle)
    handle.gear = gear
    gear:SetSize(GEAR_SIZE, GEAR_SIZE)
    gear:SetPoint("RIGHT", -HANDLE_GEAR_RIGHT, 0)
    gear:SetFrameLevel((handle:GetFrameLevel() or 1) + 5)
    gear:SetNormalTexture(GEAR_TEXTURE)
    gear:SetHighlightTexture(GEAR_TEXTURE)
    gear:SetScript("OnClick", function()
        self:Open()
    end)
    gear:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText(TEXT.settings, 1, 1, 1)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    handle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    -- Saved by its center, which is the first alert's center.
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        self:Settings().position = { point = "CENTER", relativePoint = "CENTER", x = x - ux, y = y - uy }
        self:ApplyPosition()
    end)
    handle:Hide()

    self:ApplyPosition()
    frame:Hide()
end

-- Lays out up to `cap` lines on pooled widgets and hides the rest. `more` is how many the source left
-- out; lines past the cap are added to it.
function Area:Draw(lines, now, s, more)
    local def, frame, pool = self.def, self.frame, self.pool
    local n = math.min(#lines, capOf(s))
    local grow = GROW[s.grow] and s.grow or "down"
    local g = GROW[grow]
    local align = def.align and ALIGNED[grow] and ALIGNED[grow][def.align(s)]
    local point, relative = g[1], g[2]
    if align then
        point, relative = align[1], align[2]
    end

    -- When each line id first showed, kept by id so it survives the line moving to another widget.
    local shownAt, seen = self.shownAt, self.seen
    for i = 1, n do
        local line, w = lines[i], pool[i]
        if not w then
            w = def.make(frame)
            pool[i] = w
        end
        local id, at = line.id, nil
        if id ~= nil then
            seen[id] = true
            at = shownAt[id]
            if not at then
                at = now
                shownAt[id] = at
            end
        end
        def.draw(w, line, now, s, at)
        w:ClearAllPoints()
        if i == 1 then
            w:SetPoint(point, frame, point, 0, 0)
        else
            w:SetPoint(point, pool[i - 1], relative, g[3], g[4])
        end
        w:Show()
        Areas.Glow(w, line.glow == true and now >= line.at)
    end
    for id in pairs(shownAt) do
        if not seen[id] then
            shownAt[id] = nil
        end
    end
    for id in pairs(seen) do
        seen[id] = nil
    end
    for i = n + 1, #pool do
        local w = pool[i]
        if w:IsShown() then
            w:Hide()
        end
        Areas.Glow(w, false)
    end

    self.count = n
    self.more = (more or 0) + (#lines - n)
    if n > 0 then
        -- The area is the first widget's size, so that widget sits on the saved center. With an
        -- alignment it is as wide as the drag box, so the aligned edge stays put as the texts change.
        local width, height = pool[1]:GetWidth(), pool[1]:GetHeight()
        if align then
            width = HANDLE_MIN_WIDTH
        end
        frame:SetSize(width, height)
        self.handle:SetWidth(math.max(self.handleMin or HANDLE_MIN_WIDTH, width))
    end
    -- The drag box sits on the side the widgets don't grow into.
    local below = grow == "up"
    if self.handleBelow ~= below then
        self.handleBelow = below
        self.handle:ClearAllPoints()
        if below then
            self.handle:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        else
            self.handle:SetPoint("BOTTOM", frame, "TOP", 0, 2)
        end
    end
    frame:SetShown(n > 0 or self.preview)
    if def.after then
        def.after(self, n, self.more)
    end
end

-- The test lines still to show, soonest first, or nil once every one has passed.
local function testLines(self, now)
    local out, left = {}, false
    for _, line in ipairs(self.testList) do
        if now < line.at + math.max(0, number(line.hold, 0)) then
            left = true
            if not line.warn or now >= line.at - line.warn then
                out[#out + 1] = line
            end
        end
    end
    if not left then
        self.testList = nil
        return nil
    end
    table.sort(out, function(a, b)
        return a.at < b.at
    end)
    return out
end

function Area:Refresh()
    if not self.frame then
        return
    end
    local s = self:Settings()
    local now = GetTime()
    self.handle:SetShown(self.preview)
    local lines, more
    if self.preview then
        lines = self.def.sample(now) or EMPTY
    elseif self.testList then
        lines = testLines(self, now)
    end
    if not lines then
        -- Nothing shows while the area is off, whichever block the lines come from.
        if s.shown and Alerts.running then
            local cap = capOf(s)
            if self.def.lines then
                lines, more = self.def.lines(now, s, cap)
                lines = lines or EMPTY
            else
                lines, more = Rules.Area(Alerts:Lines(now), now, self.def.output, cap)
            end
        else
            lines = EMPTY
        end
    end
    self:Draw(lines, now, s, more)
end

-- From the ticker: nothing to do unless a run, a preview or a test is going.
function Area:Tick()
    if not self.frame then
        return
    end
    if not (Alerts.running or self.preview or self.testList) then
        if not self.idle then
            self.idle = true
            self:Draw(EMPTY, 0, self:Settings())
        end
        return
    end
    self.idle = false
    self:Refresh()
end

function Area:Test(lines)
    self:Build()
    self.testList = type(lines) == "table" and lines or nil
    self.idle = false
    self:Refresh()
end

function Area:Visible()
    local out = {}
    for i = 1, self.count do
        out[i] = self.pool[i]
    end
    return out
end

-- The settings live on Raid Notes > Alerts: this opens that tab on this area.
function Area:Open()
    if CRT.NoteAlertsTab then
        CRT.NoteAlertsTab.Select(self.def.key)
    end
    if CRT.NotesPage then
        CRT.NotesPage.Open("alerts")
    end
    if UI.previewing then
        self:MoveWindowAside()
    end
end

-- While Previews are on, the main window would cover the area being tuned: for this session it moves to
-- the screen side away from the area. Its saved place is untouched (a drag still saves as usual) and it
-- goes back there when Previews turn off. A window the player has dragged since stays where they put it.
function Area:MoveWindowAside()
    local f = UI.frame
    if not f or UI.windowParked == "dragged" then
        return
    end
    local p = self:Settings().position or self.def.defaultPosition or DEFAULT_POSITION
    local left = (p.x or 0) >= 0
    local _, cy = f:GetCenter()
    local _, uy = UIParent:GetCenter()
    local scale = (f.GetEffectiveScale and f:GetEffectiveScale() or 1)
    local uscale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
    local dy = ((cy or 0) * scale - (uy or 0) * uscale) / scale
    local point = left and "LEFT" or "RIGHT"
    f:ClearAllPoints()
    f:SetPoint(point, UIParent, point, left and WINDOW_MARGIN or -WINDOW_MARGIN, dy)
    UI.windowParked = true
end

-- Previews off: the main window goes back to its saved place, unless the player moved it meanwhile.
UI:RegisterPreview("alertwindow", function(on)
    if not on and UI.windowParked then
        if UI.windowParked == true then
            UI:ApplyWindowPosition()
        end
        UI.windowParked = nil
    end
end)

function Areas.New(def)
    local area = setmetatable({ def = def, title = def.title, pool = {}, count = 0, more = 0,
        preview = false, shownAt = {}, seen = {} }, Area)
    Areas.list[#Areas.list + 1] = area
    UI:RegisterPreview("alert" .. def.key, function(on)
        area:Build()
        if on then
            area:MeasureHandle()
        end
        area.preview = on and true or false
        area.idle = false
        area:Refresh()
    end)
    return area
end

-- Every area, back where it starts (Dev:ResetAllPositions).
function Areas:ResetAllPositions()
    for _, area in ipairs(self.list) do
        area:ResetPosition()
    end
end

-- One ticker for every area. It builds them at login, once the saved settings are in.
local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < REFRESH_SECONDS then
        return
    end
    elapsed = 0
    for _, area in ipairs(Areas.list) do
        -- One area failing must not stop the others.
        -- A failure is reported once, until the area works again.
        local ok, err = pcall(area.Tick, area)
        if ok then
            area.failed = nil
        elseif not area.failed then
            area.failed = true
            report(err)
        end
    end
end)
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function()
    for _, area in ipairs(Areas.list) do
        area:Build()
    end
end)
