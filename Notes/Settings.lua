local ADDON, CRT = ...

-- The Settings tab of the Raid Notes page (Notes/Page.lua builds it into its tab): one column for each
-- of the three note windows (timers, assignments, personal note), your alerts and text to speech,
-- and who to accept shared notes from. Unlocked windows can be dragged and resized by hand, and their
-- position and size are saved per player.

local Notes = CRT.Notes
local UI = CRT.UI

-- Every word on this tab, in one place so the wording is easy to change. Keep the keys, change the
-- text in quotes, save, and /reload.
local TEXT = {
    hint = "Untick Locked to drag a window and resize it from its bottom-right corner, then lock it again so clicks pass through. Previews shows every window with sample text. Everything here is saved for you.",

    -- The three window columns.
    timers = "Timers",
    assignments = "Assignments",
    personal = "Personal note",
    show = "Show this window",
    locked = "Locked (clicks pass through)",
    hidePassed = "Hide lines once passed",
    onlyMe = "Show only me",
    fontSize = "Font size",
    windowAlpha = "Window alpha",
    backgroundAlpha = "Background",
    font = "Font",

    -- Alerts.
    alerts = "Alerts",
    alertShow = "Show your next spell or callout",
    alertSeconds = "Show it early by",
    tts = "Text to Speech",
    ttsSeconds = "Count down seconds",
    ttsVolume = "Speech volume",
    alertIcon = "Spell icon",
    testSpeech = "Test speech",
    testPhrase = "Cowfee Raid Tools. Avenging Wrath in three.",

    -- Sharing.
    sharing = "Sharing",
    trustedOnly = "Only accept notes from leader or assistants",

    -- Alert bars.
    bars = "Alert bars",
    barsHelp = "Bars list what is coming up, soonest first: your note lines and your reminders. Show bars from is how many seconds ahead a line gets a bar. Your note lines are read when the pull starts, so changing that box takes effect on the next pull.",
    barsShow = "Show alert bars",
    barsNoteLines = "Show your note lines as bars",
    barsCap = "Bars at once",
    barsAhead = "Show bars from",
    barsWidth = "Bar width",
    barsHeight = "Bar height",
    testBars = "Test bars",
}

local COLUMN_W = 226
local ICON_POSITIONS = {
    { key = "left", label = "Left" },
    { key = "right", label = "Right" },
    { key = "above", label = "Above" },
    { key = "below", label = "Below" },
}
local WINDOWS = {
    { key = "window", title = TEXT.timers },
    { key = "assignments", title = TEXT.assignments },
    { key = "personal", title = TEXT.personal },
}

local WHITE = { 1, 1, 1 }
local GREY = { 0.5, 0.5, 0.5 }

local page
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

local function setting(key, field)
    return function()
        return Notes:WindowSettings(key)[field]
    end, function(value)
        Notes:Set(key, field, value)
    end
end

local function alert(field)
    return function()
        return Notes:Alert()[field]
    end, function(value)
        Notes:Set("alert", field, value)
    end
end

-- Greys a label out, for a control that can't be used right now.
local function greyOut(label, on)
    local c = on and WHITE or GREY
    label:SetTextColor(c[1], c[2], c[3])
end

-- enabledIf, when given, returns whether a control can be used. When it returns false the control is
-- greyed out and can't be changed, such as the alert seconds while alerts are off.
-- enabledIf comes before getter and setter, which must be last (see makeNumber). Pass nil when the
-- box never greys out.
local function makeCheck(parent, x, y, label, enabledIf, getter, setter)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    check.refresh = function()
        check:SetChecked(getter() and true or false)
        if enabledIf then
            local on = enabledIf()
            check:SetEnabled(on)
            greyOut(text, on)
        end
    end
    controls[#controls + 1] = check
end

-- A number setting as an Edit Mode style slider. opts: low and high (the range), labelWidth and
-- width (default 92 and 78, to fit a column), format (the text beside the bar) and enabledIf.
-- getter and setter come last because setting() and alert() return both: Lua only passes every
-- return value of a call when it is the last argument, so in the middle the setter is lost.
local function makeNumber(parent, x, y, label, opts, getter, setter)
    local row = UI.Slider(parent, label, {
        min = opts.low,
        max = opts.high,
        step = 1,
        labelWidth = opts.labelWidth or 92,
        width = opts.width or 78,
        format = opts.format,
        enabledIf = opts.enabledIf,
        get = getter,
        set = setter,
    })
    row:SetPoint("TOPLEFT", x + 4, y)
    controls[#controls + 1] = row
    return row
end

local function percent(v)
    return (v or 0) .. "%"
end

local function seconds(v)
    return (v or 0) .. "s"
end

local function heading(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function buildColumn(pf, index, def, top)
    local x = 8 + (index - 1) * COLUMN_W
    local title = heading(pf, x, top, def.title)
    if index == 1 then
        UI.Help(pf, "Note windows", TEXT.hint):SetPoint("LEFT", title, "RIGHT", 6, 0)
    end

    -- Everything below Show this window greys out while the window is hidden.
    local function shown()
        return Notes:WindowSettings(def.key).shown and true or false
    end
    makeCheck(pf, x - 4, top - 20, TEXT.show, nil, setting(def.key, "shown"))
    makeCheck(pf, x - 4, top - 44, TEXT.locked, shown, setting(def.key, "locked"))
    local y = top - 68
    if def.key == "window" then
        makeCheck(pf, x - 4, y, TEXT.hidePassed, shown, setting(def.key, "hidePassed"))
        makeCheck(pf, x - 4, y - 24, TEXT.onlyMe, shown, setting(def.key, "onlyMe"))
        y = y - 48
    end
    makeNumber(pf, x, y, TEXT.fontSize, { low = 8, high = 32, enabledIf = shown }, setting(def.key, "fontSize"))
    makeNumber(pf, x, y - 28, TEXT.windowAlpha, { low = 10, high = 100, format = percent, enabledIf = shown }, setting(def.key, "alpha"))
    makeNumber(pf, x, y - 56, TEXT.backgroundAlpha, { low = 0, high = 100, format = percent, enabledIf = shown }, setting(def.key, "bgAlpha"))

    -- Read each time the menu opens, so fonts shared by other addons appear.
    local function fonts()
        local out = { { key = "default", label = "Game default" } }
        for _, f in ipairs(CRT:FontList()) do
            out[#out + 1] = { key = f.name, label = f.name }
        end
        return out
    end
    local font = UI.Dropdown(pf, TEXT.font, {
        options = fonts,
        labelWidth = 40,
        width = COLUMN_W - 64,
        get = function()
            return Notes:WindowSettings(def.key).font or "Friz Quadrata"
        end,
        set = function(name)
            Notes:Set(def.key, "font", name)
        end,
        enabledIf = shown,
    })
    font:SetPoint("TOPLEFT", x, y - 88)
    controls[#controls + 1] = font
end

local function refresh()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
end

local function build(pf)
    page = pf

    -- The three note windows.
    for index, def in ipairs(WINDOWS) do
        buildColumn(pf, index, def, -14)
    end

    -- Alerts, on the left, and sharing, on the right. The seconds row greys out while alerts are off,
    -- and the speech rows while text to speech is off.
    local function alertsOn()
        return Notes:Alert().enabled and true or false
    end
    local function speechOn()
        return Notes:Alert().tts and true or false
    end
    local top = -300
    heading(pf, 8, top, TEXT.alerts)
    makeCheck(pf, 4, top - 20, TEXT.alertShow, nil, alert("enabled"))
    makeNumber(pf, 4, top - 46, TEXT.alertSeconds, { low = 1, high = 60, labelWidth = 120, width = 150, format = seconds, enabledIf = alertsOn }, alert("seconds"))
    makeCheck(pf, 4, top - 80, TEXT.tts, nil, alert("tts"))
    makeNumber(pf, 4, top - 106, TEXT.ttsSeconds, { low = 0, high = 30, labelWidth = 120, width = 150, format = seconds, enabledIf = speechOn }, alert("ttsSeconds"))
    local volumeGet, volumeSet = alert("ttsVolume")
    local volume = UI.Slider(pf, TEXT.ttsVolume, { min = 0, max = 100, labelWidth = 120, width = 150, format = percent, get = volumeGet, set = volumeSet, enabledIf = speechOn })
    volume:SetPoint("TOPLEFT", 8, top - 138)
    controls[#controls + 1] = volume
    local iconGet, iconSet = alert("iconPosition")
    local iconRow = UI.Dropdown(pf, TEXT.alertIcon, { options = ICON_POSITIONS, labelWidth = 120, width = 150, get = iconGet, set = iconSet, enabledIf = alertsOn })
    iconRow:SetPoint("TOPLEFT", 8, top - 170)
    controls[#controls + 1] = iconRow
    local speak = makeButton(pf, TEXT.testSpeech, 140)
    speak:SetPoint("TOPLEFT", 8, top - 210)
    speak:SetScript("OnClick", function()
        CRT.NoteAlert:Speak(TEXT.testPhrase)
    end)

    heading(pf, 360, top, TEXT.sharing)
    makeCheck(pf, 356, top - 20, TEXT.trustedOnly, nil, function()
        return Notes:TrustedOnly()
    end, function(value)
        Notes:Set(nil, "trustedOnly", value)
    end)

    -- Alert bars, under sharing. They read these settings every refresh, so a change shows at once.
    local function bars()
        return CRT.Alerts:Settings().bars
    end
    local function barSetting(field)
        return function()
            return bars()[field]
        end, function(value)
            bars()[field] = value
            refresh()
            CRT.AlertBars:Refresh()
        end
    end
    local function barsOn()
        return bars().shown and true or false
    end
    local barsTop = top - 60
    local barsTitle = heading(pf, 360, barsTop, TEXT.bars)
    UI.Help(pf, TEXT.bars, TEXT.barsHelp):SetPoint("LEFT", barsTitle, "RIGHT", 6, 0)
    makeCheck(pf, 356, barsTop - 20, TEXT.barsShow, nil, barSetting("shown"))
    makeCheck(pf, 356, barsTop - 44, TEXT.barsNoteLines, barsOn, barSetting("noteLines"))
    local sliders = {
        { TEXT.barsCap, "cap", 1, 10, 1 },
        { TEXT.barsAhead, "ahead", 5, 60, 1 },
        { TEXT.barsWidth, "width", 120, 400, 10 },
        { TEXT.barsHeight, "height", 12, 40, 1 },
    }
    for i, def in ipairs(sliders) do
        local get, set = barSetting(def[2])
        local row = UI.Slider(pf, def[1], { min = def[3], max = def[4], step = def[5], labelWidth = 110, width = 130, get = get, set = set, enabledIf = barsOn })
        row:SetPoint("TOPLEFT", 364, barsTop - 48 - i * 28)
        controls[#controls + 1] = row
    end
    local testBars = makeButton(pf, TEXT.testBars, 140)
    testBars:SetPoint("TOPLEFT", 364, barsTop - 48 - (#sliders + 1) * 28 - 4)
    testBars:SetScript("OnClick", function()
        CRT.AlertBars:Test()
    end)

    pf:SetScript("OnShow", refresh)
    Notes:OnChange(refresh)
end

-- Built into the Settings tab by Notes/Page.lua.
CRT.NoteSettings = { Build = build }
