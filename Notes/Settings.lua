local ADDON, CRT = ...

-- The Settings tab of the Raid Notes page (Notes/Page.lua builds it into its tab): one column for each
-- of the three note windows (timers, assignments, personal note), your alerts and text to speech,
-- and who to accept shared notes from. Unlocked windows can be dragged and resized by hand, and their
-- position and size are saved per player.

local Notes = CRT.Notes

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
    font = "Font: ",
    resetPosition = "Reset position",

    -- Alerts.
    alerts = "Alerts",
    alertShow = "Show your next spell or callout",
    alertSeconds = "Display seconds early:",
    tts = "Text to Speech",
    ttsSeconds = "Count down seconds",
    ttsVolume = "Speech volume",
    testSpeech = "Test speech",
    testPhrase = "Cowfee Raid Tools. Avenging Wrath in three.",

    -- Sharing.
    sharing = "Sharing",
    trustedOnly = "Only accept notes from leader or assistants",
}

local COLUMN_W = 226
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

-- A horizontal slider from low to high, with its value shown to the right. Built from the plain
-- Slider widget and color textures, so it needs no Blizzard template or art file. opts: low, high,
-- width and enabledIf, with getter and setter last for the same reason as makeNumber.
local function makeSlider(parent, x, y, label, opts, getter, setter)
    local low, high, width, enabledIf = opts.low, opts.high, opts.width, opts.enabledIf
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("TOPLEFT", x + 4, y - 4)
    text:SetText(label)

    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 14)
    slider:SetPoint("TOPLEFT", x + 4, y - 24)
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    slider:SetBackdropColor(0, 0, 0, 0.6)
    slider:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 0.82, 0, 1)
    thumb:SetSize(10, 18)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local value = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    value:SetPoint("LEFT", slider, "RIGHT", 10, 0)

    local updating = false
    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        value:SetText(v)
        if not updating then
            setter(v)
        end
    end)
    slider.refresh = function()
        updating = true
        slider:SetValue(getter() or low)
        value:SetText(math.floor((getter() or low) + 0.5))
        updating = false
        if enabledIf then
            local on = enabledIf()
            slider:SetEnabled(on)
            slider:SetAlpha(on and 1 or 0.5)
            greyOut(text, on)
            greyOut(value, on)
        end
    end
    controls[#controls + 1] = slider
end

local function heading(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function buildColumn(pf, index, def, top)
    local x = 8 + (index - 1) * COLUMN_W
    heading(pf, x, top, def.title)

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

    local font = makeButton(pf, TEXT.font, COLUMN_W - 16)
    font:SetPoint("TOPLEFT", x, y - 76)
    font:SetScript("OnClick", function()
        local fonts = CRT.NoteWindow.FONTS
        local current = Notes:WindowSettings(def.key).font
        local nextIndex = 1
        for i, f in ipairs(fonts) do
            if f.name == current then
                nextIndex = i % #fonts + 1
            end
        end
        Notes:Set(def.key, "font", fonts[nextIndex].name)
    end)
    font.refresh = function()
        font:SetText(TEXT.font .. (Notes:WindowSettings(def.key).font or "Friz Quadrata"))
        font:SetEnabled(shown())
    end
    controls[#controls + 1] = font

    local reset = makeButton(pf, TEXT.resetPosition, COLUMN_W - 16)
    reset:SetPoint("TOPLEFT", x, y - 104)
    reset:SetScript("OnClick", function()
        CRT.NoteWindow:ResetPosition(def.key)
    end)
    reset.refresh = function()
        reset:SetEnabled(shown())
    end
    controls[#controls + 1] = reset
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

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -6)
    hint:SetWidth(670)
    hint:SetJustifyH("LEFT")
    hint:SetText(TEXT.hint)

    -- The three note windows.
    for index, def in ipairs(WINDOWS) do
        buildColumn(pf, index, def, -46)
    end

    -- Alerts, on the left, and sharing, on the right. The seconds row greys out while alerts are off,
    -- and the speech rows while text to speech is off.
    local function alertsOn()
        return Notes:Alert().enabled and true or false
    end
    local function speechOn()
        return Notes:Alert().tts and true or false
    end
    local top = -312
    heading(pf, 8, top, TEXT.alerts)
    makeCheck(pf, 4, top - 20, TEXT.alertShow, nil, alert("enabled"))
    makeNumber(pf, 4, top - 44, TEXT.alertSeconds, { low = 1, high = 60, valueX = 200, enabledIf = alertsOn }, alert("seconds"))
    makeCheck(pf, 4, top - 68, TEXT.tts, nil, alert("tts"))
    makeNumber(pf, 4, top - 92, TEXT.ttsSeconds, { low = 0, high = 30, valueX = 200, enabledIf = speechOn }, alert("ttsSeconds"))
    makeSlider(pf, 4, top - 116, TEXT.ttsVolume, { low = 0, high = 100, width = 196, enabledIf = speechOn }, alert("ttsVolume"))
    local speak = makeButton(pf, TEXT.testSpeech, 140)
    speak:SetPoint("TOPLEFT", 8, top - 164)
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
