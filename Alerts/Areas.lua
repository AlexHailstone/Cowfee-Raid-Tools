local ADDON, CRT = ...

-- The alert areas: movable places on screen where the alerts engine's lines show as texts, icons,
-- circles or bars. Every area is made by Areas.New from a def, so they all move, preview, layer, pool,
-- grow, glow and open their settings the same way; each kind only says how one alert looks.
--
--   Areas.New(def) -> area, with def = {
--     key              names the area: its frame is CowfeeRaidToolsAlert<Key>, its preview "alert<key>"
--     output           the entry output it shows: "text", "icon", "circle" or "bar" (see Rules.Area)
--     layer            its UI.LAYERS key
--     title            its name, on the drag box and the settings window
--     settingsKey      its settings are CRT.db.alerts.areas[settingsKey]: shown, cap, grow, position, and
--                      whatever its own rows add
--     defaultPosition  { point, relativePoint, x, y } until it is moved
--     make(parent)     -> a new widget, a Frame on parent. Made once per pool slot, never per refresh.
--                      Widgets never take the mouse, so the alerts let clicks through.
--     draw(widget, line, now, s)  shows one line on a widget and sets its size. s is the area's settings.
--     sample(now)      -> lines for Previews, each with `at` set
--     settings(dialog, s)  adds the area's own rows to the settings window with dialog:Dropdown(label,
--                      opts), dialog:Slider(label, opts) and dialog:Check(label, get, set) (opts as for
--                      UI.Dropdown and UI.Slider). It is called on every open; the rows are made on the
--                      first and reused after. A change refreshes the area at once.
--   Optional, for an area whose settings or lines live elsewhere (the bars):
--     store()          -> the settings table, instead of CRT.db.alerts.areas[settingsKey]
--     lines(now, s, cap)  -> the lines to show, instead of Rules.Area(Alerts:Lines(now), now, output, cap)
--   }
--
-- An area shows its lines soonest first, at most `cap` (1-10), the first centered on its saved position
-- and the rest after it in the `grow` direction, 4 px apart. A line glows while line.glow and now >= at.
-- The drag box (title, settings button, reset) shows only with Previews. Every area refreshes from one
-- ticker every 0.1 s, and only while a run, a preview or a test is going; otherwise it hides once and
-- does nothing.
--   area:Refresh()        draws it now
--   area:ResetPosition()  back to defaultPosition
--   area:Test(lines)      shows the given lines (with `at` set) until they have all passed
--   area:Visible()        -> { widget } on screen, for the tests
--   area:Open()           opens the settings window on this area (the ⚙ button)
--   area:Settings()       -> its settings table
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
    show = "Show this area",
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
local HANDLE_MIN_WIDTH = 220
local GEAR_TEXTURE = "Interface\\WorldMap\\Gear_64Grey" -- the settings button
local GEAR_SIZE = 16
local GLOW_SIZE = 2      -- the border's thickness
local GLOW_OUTSET = 3    -- how far it sits outside the widget
local GLOW_COLOR = { 1, 0.82, 0 }
local GLOW_PULSE = 0.4   -- seconds from bright to faint
local GLOW_FAINT = 0.25
local DIALOG_NAME = "CowfeeRaidToolsAlertArea"
local DIALOG_WIDTH = 440
local DIALOG_TOP = 32    -- below the title bar
local DIALOG_LEFT = 16
local ROW_HEIGHT = 32

-- Each direction: the point a widget anchors by, the point of the one before it, and the gap's offset.
local GROW = {
    down = { "TOP", "BOTTOM", 0, -GAP },
    up = { "BOTTOM", "TOP", 0, GAP },
    left = { "RIGHT", "LEFT", -GAP, 0 },
    right = { "LEFT", "RIGHT", GAP, 0 },
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
    if not fontString:SetFont(path, size, outline) then
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

-- The settings window ------------------------------------------------------------------------
-- One window for every area. The common rows are made once; an area's own rows are made the first
-- time it opens and kept on the area, hidden while another area is open.

local dialog
local current -- the area the window shows

local function refreshRows()
    if not (dialog and current) then
        return
    end
    for _, row in ipairs(dialog.common) do
        row.refresh()
    end
    for i = 1, current.cursor do
        current.rows[i].row.refresh()
    end
end

-- After any change: the area redraws at once and the rows show the new values.
local function changed()
    if current then
        current:Refresh()
    end
    refreshRows()
end

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

-- The next of the open area's own rows: the one made on an earlier open, or a new one from make(slot).
-- slot.opts (or slot.get and slot.set) are replaced on every open, so the rows read fresh settings.
local function nextSlot(make)
    current.cursor = current.cursor + 1
    local slot = current.rows[current.cursor]
    if not slot then
        slot = {}
        slot.row = make(slot)
        current.rows[current.cursor] = slot
    end
    return slot
end

local methods = {}

function methods:Dropdown(label, opts)
    local slot = nextSlot(function(slot)
        return UI.Dropdown(dialog, label, {
            options = function()
                local o = slot.opts.options
                return type(o) == "function" and o() or o
            end,
            get = function()
                return slot.opts.get()
            end,
            set = function(key)
                slot.opts.set(key)
                changed()
            end,
            width = opts.width,
            labelWidth = opts.labelWidth,
            enabledIf = function()
                return not slot.opts.enabledIf or slot.opts.enabledIf()
            end,
            decorate = opts.decorate and function(button, option)
                return slot.opts.decorate and slot.opts.decorate(button, option)
            end,
        })
    end)
    slot.opts = opts
    return slot.row
end

function methods:Slider(label, opts)
    local slot = nextSlot(function(slot)
        return UI.Slider(dialog, label, {
            min = opts.min,
            max = opts.max,
            step = opts.step,
            format = opts.format,
            onRelease = opts.onRelease,
            width = opts.width,
            labelWidth = opts.labelWidth,
            get = function()
                return slot.opts.get()
            end,
            set = function(value)
                slot.opts.set(value)
                changed()
            end,
            enabledIf = function()
                return not slot.opts.enabledIf or slot.opts.enabledIf()
            end,
        })
    end)
    slot.opts = opts
    return slot.row
end

function methods:Check(label, get, set)
    local slot = nextSlot(function(slot)
        return makeCheck(dialog, label, function()
            return slot.get()
        end, function(on)
            slot.set(on)
            changed()
        end)
    end)
    slot.get, slot.set = get, set
    return slot.row
end

local function buildDialog()
    if dialog then
        return
    end
    local d = CreateFrame("Frame", DIALOG_NAME, UIParent, "BasicFrameTemplateWithInset")
    dialog = d
    d:SetSize(DIALOG_WIDTH, 200)
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI:RegisterLayer("panel", d)
    tinsert(UISpecialFrames, DIALOG_NAME)
    for name, fn in pairs(methods) do
        d[name] = fn
    end

    local function s()
        return current:Settings()
    end
    d.common = {
        makeCheck(d, TEXT.show, function()
            return s().shown
        end, function(on)
            s().shown = on
            changed()
        end),
        UI.Slider(d, TEXT.cap, {
            min = 1,
            max = MAX_CAP,
            get = function()
                return capOf(s())
            end,
            set = function(value)
                s().cap = value
                changed()
            end,
        }),
        UI.Dropdown(d, TEXT.grow, {
            options = GROW_OPTIONS,
            get = function()
                return GROW[s().grow] and s().grow or "down"
            end,
            set = function(key)
                s().grow = key
                changed()
            end,
        }),
    }
    d:Hide()
end

local function place(row, y)
    row:ClearAllPoints()
    if row.labelText then
        -- A checkbox is smaller than its row, so it sits in the middle of it.
        row:SetPoint("TOPLEFT", dialog, "TOPLEFT", DIALOG_LEFT, y - (ROW_HEIGHT - 24) / 2)
    else
        row:SetPoint("TOPLEFT", dialog, "TOPLEFT", DIALOG_LEFT, y)
    end
    row:Show()
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

    local gear = CreateFrame("Button", nil, handle)
    handle.gear = gear
    gear:SetSize(GEAR_SIZE, GEAR_SIZE)
    gear:SetPoint("RIGHT", -50, 0)
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

-- Lays out up to `cap` lines on pooled widgets and hides the rest.
function Area:Draw(lines, now, s)
    local def, frame, pool = self.def, self.frame, self.pool
    local n = math.min(#lines, capOf(s))
    local g = GROW[s.grow] or GROW.down
    for i = 1, n do
        local line, w = lines[i], pool[i]
        if not w then
            w = def.make(frame)
            pool[i] = w
        end
        def.draw(w, line, now, s)
        w:ClearAllPoints()
        if i == 1 then
            w:SetPoint(g[1], frame, g[1], 0, 0)
        else
            w:SetPoint(g[1], pool[i - 1], g[2], g[3], g[4])
        end
        w:Show()
        Areas.Glow(w, line.glow == true and now >= line.at)
    end
    for i = n + 1, #pool do
        local w = pool[i]
        if w:IsShown() then
            w:Hide()
        end
        Areas.Glow(w, false)
    end
    self.count = n
    if n > 0 then
        -- The area is the first widget's size, so that widget sits on the saved center.
        local width, height = pool[1]:GetWidth(), pool[1]:GetHeight()
        frame:SetSize(width, height)
        self.handle:SetWidth(math.max(HANDLE_MIN_WIDTH, width))
    end
    frame:SetShown(n > 0 or self.preview)
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
    local lines
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
                lines = self.def.lines(now, s, cap) or EMPTY
            else
                lines = Rules.Area(Alerts:Lines(now), now, self.def.output, cap)
            end
        else
            lines = EMPTY
        end
    end
    self:Draw(lines, now, s)
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

function Area:Open()
    buildDialog()
    for _, area in ipairs(Areas.list) do
        for _, slot in ipairs(area.rows) do
            slot.row:Hide()
        end
    end
    current = self
    UI.SetFrameTitle(dialog, self.title)
    self.cursor = 0
    if self.def.settings then
        self.def.settings(dialog, self:Settings())
    end
    local y = -DIALOG_TOP
    for _, row in ipairs(dialog.common) do
        place(row, y)
        y = y - ROW_HEIGHT
    end
    for i = 1, self.cursor do
        place(self.rows[i].row, y)
        y = y - ROW_HEIGHT
    end
    dialog:SetHeight(-y + DIALOG_LEFT)
    refreshRows()
    dialog:Show()
    dialog:Raise()
end

function Areas.New(def)
    local area = setmetatable({ def = def, title = def.title, pool = {}, count = 0, rows = {}, cursor = 0, preview = false }, Area)
    Areas.list[#Areas.list + 1] = area
    UI:RegisterPreview("alert" .. def.key, function(on)
        area:Build()
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
        local ok, err = pcall(area.Tick, area)
        if not ok then
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
