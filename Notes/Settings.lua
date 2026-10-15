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
    fontSize = "Font size (8 to 32)",
    windowAlpha = "Window alpha %",
    backgroundAlpha = "Background alpha %",
    font = "Font",

    -- Alerts.
    alerts = "Alerts",
    alertShow = "Show your next spell or callout",
    alertSeconds = "Display seconds early:",
    tts = "Text to Speech",
    ttsSeconds = "Count down seconds",
    ttsVolume = "Speech volume",
    alertIcon = "Spell icon",
    testSpeech = "Test speech",
    testPhrase = "Cowfee Raid Tools. Avenging Wrath in three.",

    -- Sharing.
    sharing = "Sharing",
    trustedOnly = "Only accept notes from leader or assistants",
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

-- opts: low and high (the allowed range), valueX (where the box sits, from x, default 160) and
-- enabledIf. getter and setter come last because setting() and alert() return both: Lua only passes
-- every return value of a call when it is the last argument, so in the middle the setter is lost.
local function makeNumber(parent, x, y, label, opts, getter, setter)
    local low, high, valueX, enabledIf = opts.low, opts.high, opts.valueX, opts.enabledIf
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("TOPLEFT", x + 4, y - 4)
    text:SetText(label)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontHighlight)
    edit:SetNumeric(true)
    edit:SetMaxLetters(3)
    edit:SetSize(44, 20)
    edit:SetPoint("TOPLEFT", x + (valueX or 160), y - 2)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(getter()))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then
            setter(math.max(low, math.min(high, math.floor(value))))
        end
        self:SetText(tostring(getter()))
    end)
    edit.refresh = function()
        if not edit:HasFocus() then
            edit:SetText(tostring(getter()))
        end
        if enabledIf then
            local on = enabledIf()
            edit:SetEnabled(on)
            edit:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
            greyOut(text, on)
        end
    end
    controls[#controls + 1] = edit
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
    makeNumber(pf, x, y - 24, TEXT.windowAlpha, { low = 10, high = 100, enabledIf = shown }, setting(def.key, "alpha"))
    makeNumber(pf, x, y - 48, TEXT.backgroundAlpha, { low = 0, high = 100, enabledIf = shown }, setting(def.key, "bgAlpha"))

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
    font:SetPoint("TOPLEFT", x, y - 70)
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
    local top = -280
    heading(pf, 8, top, TEXT.alerts)
    makeCheck(pf, 4, top - 20, TEXT.alertShow, nil, alert("enabled"))
    makeNumber(pf, 4, top - 44, TEXT.alertSeconds, { low = 1, high = 60, valueX = 200, enabledIf = alertsOn }, alert("seconds"))
    makeCheck(pf, 4, top - 68, TEXT.tts, nil, alert("tts"))
    makeNumber(pf, 4, top - 92, TEXT.ttsSeconds, { low = 0, high = 30, valueX = 200, enabledIf = speechOn }, alert("ttsSeconds"))
    local volumeGet, volumeSet = alert("ttsVolume")
    local volume = UI.Slider(pf, TEXT.ttsVolume, { min = 0, max = 100, labelWidth = 100, width = 150, get = volumeGet, set = volumeSet, enabledIf = speechOn })
    volume:SetPoint("TOPLEFT", 8, top - 116)
    controls[#controls + 1] = volume
    local iconGet, iconSet = alert("iconPosition")
    local iconRow = UI.Dropdown(pf, TEXT.alertIcon, { options = ICON_POSITIONS, labelWidth = 100, width = 150, get = iconGet, set = iconSet, enabledIf = alertsOn })
    iconRow:SetPoint("TOPLEFT", 8, top - 148)
    controls[#controls + 1] = iconRow
    local speak = makeButton(pf, TEXT.testSpeech, 140)
    speak:SetPoint("TOPLEFT", 8, top - 188)
    speak:SetScript("OnClick", function()
        CRT.NoteAlert:Speak(TEXT.testPhrase)
    end)

    heading(pf, 360, top, TEXT.sharing)
    makeCheck(pf, 356, top - 20, TEXT.trustedOnly, nil, function()
        return Notes:TrustedOnly()
    end, function(value)
        Notes:Set(nil, "trustedOnly", value)
    end)

    pf:SetScript("OnShow", refresh)
    Notes:OnChange(refresh)
end

-- Built into the Settings tab by Notes/Page.lua.
CRT.NoteSettings = { Build = build }
