local ADDON, CRT = ...

-- The Alerts tab of the Raid Notes page (Notes/Page.lua builds it into its tab).
--   Left   where your own note lines go: the Next spell alert, the texts, icons, bars and circles, and
--          whether they are read out. Each uses a switch kept elsewhere: the alert and speech in
--          CRTDB.notes.alert (enabled, tts), the bars in alerts.bars.noteLines, the rest in
--          alerts.noteLines. A note line with its own show: keeps its displays (see Notes/Engine.lua).
--          Under it, Previews and a test of every area.
--   Right  Configuration, from half the page: a dropdown of the four alert areas and the chosen one's
--          settings, drawn by Alerts/Areas.lua's panel from each area's def.settings. The choice is kept
--          for the session.
-- The ⚙ on each area's drag box opens this tab on that area (CRT.NoteAlertsTab.Select).
-- The areas load after this file, so they are only looked up once the tab is built.

local Notes = CRT.Notes
local UI = CRT.UI

-- Every word on this tab, in one place so the wording is easy to change. Keep the keys, change the
-- text in quotes, save, and /reload.
local TEXT = {
    routeTitle = "Your note lines go to",
    routeHelp = "Where your own lines from the raid note show, and whether they are read out. Tick as many as you like.\n\n"
        .. "This is for your note lines without their own displays. A line that names its own displays keeps them, though each display's own switch can still turn it off.\n\n"
        .. "Your note lines are read when the pull starts, so a change takes effect on the next pull.",
    nextSpell = "Next spell alert",
    text = "Text",
    icon = "Icon",
    bar = "Bar",
    circle = "Circle",
    speech = "Read them out (text to speech)",
    speechHelp = "Reads your note lines out wherever they show, with or without the Next spell alert, and plays their sounds.\n\n"
        .. "It is also the switch for all speech: turning it off silences your reminders' speech too.",

    tryIt = "Try it",
    tryHelp = "Previews shows every alert with samples, so you can drag them into place; the cog on each opens its settings here. Test all areas counts three test alerts down in each.",
    previews = "Previews",
    testAll = "Test all areas",
    testLine = "Test alert %d",

    config = "Configuration",
    configHelp = "How each kind of alert looks. Pick one from the list to see its settings; a change shows at once.",
    icons = "Icons",
    texts = "Texts",
    bars = "Bars",
    circles = "Circles",
}

-- The areas in the dropdown, in this order.
local KINDS = {
    { key = "icons", label = TEXT.icons },
    { key = "texts", label = TEXT.texts },
    { key = "bars", label = TEXT.bars },
    { key = "circles", label = TEXT.circles },
}
local DEFAULT_KIND = "icons"
-- Two columns, each half of the page (UI.PAGE_W): where your note lines go on the left, Configuration
-- on the right. The tab is UI.PAGE_H - 66 high under the tabs; the tallest area's rows end well above it.
local COLUMN_GAP = 16
local RIGHT_X = math.floor(UI.PAGE_W / 2) + COLUMN_GAP / 2
local TEST_ICONS = { 136243, 135808, 136116 }
local TEST_TIMES = { 8, 12, 16 } -- seconds until each test alert reaches 0
local TEST_HOLD = 1

local WHITE = { 1, 1, 1 }
local GREY = { 0.5, 0.5, 0.5 }

local tab, panel, kindDrop
local selected = DEFAULT_KIND
local controls = {}

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 24)
    b:SetText(label)
    return b
end

local function heading(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

-- A checkbox. enabledIf, when given, greys it out while it returns false.
local function makeCheck(parent, x, y, label, enabledIf, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    check.labelText = label
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check.label = text
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    check.refresh = function()
        check:SetChecked(get() and true or false)
        if enabledIf then
            local on = enabledIf() and true or false
            check:SetEnabled(on)
            local c = on and WHITE or GREY
            text:SetTextColor(c[1], c[2], c[3])
        end
    end
    controls[#controls + 1] = check
    return check
end

local function alertSettings()
    return CRT.Alerts:Settings()
end

-- alerts.noteLines, made when an older save has none.
local function routing()
    local alerts = alertSettings()
    if type(alerts.noteLines) ~= "table" then
        alerts.noteLines = { text = false, icon = false, circle = false }
    end
    return alerts.noteLines
end

local function areaOn(key)
    return function()
        local area = CRT.AlertAreas.Find(key)
        return area and area:Settings().shown and true or false
    end
end

local function refresh()
    if not tab or not tab:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
    if panel then
        panel:Refresh()
    end
end

-- Shows the chosen area's settings on the right.
local function show(key)
    local area = CRT.AlertAreas and CRT.AlertAreas.Find(key)
    if not area then
        key = DEFAULT_KIND
        area = CRT.AlertAreas and CRT.AlertAreas.Find(key)
    end
    selected = key
    if not (panel and area) then
        return
    end
    panel:Select(area)
    if kindDrop then
        kindDrop.refresh()
    end
end

-- Three test alerts in every area, counting down without a run.
local function testAll()
    local now = GetTime()
    for _, kind in ipairs(KINDS) do
        local area = CRT.AlertAreas.Find(kind.key)
        if area then
            local lines = {}
            for i, seconds in ipairs(TEST_TIMES) do
                lines[i] = { id = "tabtest" .. i, text = format(TEXT.testLine, i), icon = TEST_ICONS[i], at = now + seconds, hold = TEST_HOLD }
            end
            area:Test(lines)
        end
    end
end

local function build(pf)
    tab = pf

    -- Left: where your note lines go.
    local routeTitle = heading(pf, 8, -14, TEXT.routeTitle)
    UI.Help(pf, TEXT.routeTitle, TEXT.routeHelp):SetPoint("LEFT", routeTitle, "RIGHT", 6, 0)
    local function alertField(field)
        return function()
            return Notes:Alert()[field]
        end, function(value)
            Notes:Set("alert", field, value)
        end
    end
    local function route(field)
        return function()
            return routing()[field]
        end, function(value)
            routing()[field] = value
            refresh()
        end
    end
    local y = -38
    local function nextRow()
        local at = y
        y = y - 26
        return at
    end
    makeCheck(pf, 4, nextRow(), TEXT.nextSpell, nil, alertField("enabled"))
    makeCheck(pf, 4, nextRow(), TEXT.text, areaOn("texts"), route("text"))
    makeCheck(pf, 4, nextRow(), TEXT.icon, areaOn("icons"), route("icon"))
    makeCheck(pf, 4, nextRow(), TEXT.bar, areaOn("bars"), function()
        return alertSettings().bars.noteLines
    end, function(value)
        alertSettings().bars.noteLines = value
        refresh()
        if CRT.AlertBars then
            CRT.AlertBars:Refresh()
        end
    end)
    makeCheck(pf, 4, nextRow(), TEXT.circle, areaOn("circles"), route("circle"))
    local speech = makeCheck(pf, 4, nextRow(), TEXT.speech, nil, alertField("tts"))
    UI.Help(pf, TEXT.speech, TEXT.speechHelp):SetPoint("LEFT", speech.label, "RIGHT", 6, 0)

    local tryTop = y - 20
    local tryTitle = heading(pf, 8, tryTop, TEXT.tryIt)
    UI.Help(pf, TEXT.tryIt, TEXT.tryHelp):SetPoint("LEFT", tryTitle, "RIGHT", 6, 0)
    local previews = makeButton(pf, TEXT.previews, 140)
    previews:SetPoint("TOPLEFT", 8, tryTop - 24)
    previews:SetScript("OnClick", function()
        UI:SetPreviews(true)
    end)
    local test = makeButton(pf, TEXT.testAll, 140)
    test:SetPoint("LEFT", previews, "RIGHT", 8, 0)
    test:SetScript("OnClick", testAll)

    -- Right: how each kind of alert looks.
    local configTitle = heading(pf, RIGHT_X, -14, TEXT.config)
    UI.Help(pf, TEXT.config, TEXT.configHelp):SetPoint("LEFT", configTitle, "RIGHT", 6, 0)
    -- No label: the heading says what the list is.
    kindDrop = UI.Dropdown(pf, "", {
        options = KINDS,
        labelWidth = 1,
        width = 180,
        get = function()
            return selected
        end,
        set = show,
    })
    kindDrop:SetPoint("TOPLEFT", RIGHT_X - 4, -32)
    panel = CRT.AlertAreas.Panel(pf, refresh)
    panel.frame:SetPoint("TOPLEFT", RIGHT_X, -72)

    pf:SetScript("OnShow", function()
        show(selected)
        refresh()
    end)
    Notes:OnChange(refresh)
    show(selected)
end

-- Built into the Alerts tab by Notes/Page.lua. Select(key) picks an area ("icons", "texts", "bars" or
-- "circles") for when the tab shows, and shows it at once if the tab is built.
CRT.NoteAlertsTab = {
    Build = build,
    Select = function(key)
        selected = key
        if panel then
            show(key)
        end
    end,
}
