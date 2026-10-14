local ADDON, CRT = ...

-- The Settings tab of the Raid Notes page (Notes/Page.lua builds it into its tab): one column for each
-- of the three note windows (timers, assignments, personal note), your alert and its text to speech,
-- and who to accept shared notes from. Unlocked windows can be dragged and resized by hand, and their
-- position and size are saved per player.

local Notes = CRT.Notes

local COLUMN_W = 226
local WINDOWS = {
    { key = "window", title = "Timers" },
    { key = "assignments", title = "Assignments" },
    { key = "personal", title = "Personal note" },
}

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

local function makeCheck(parent, x, y, label, getter, setter)
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
    end
    controls[#controls + 1] = check
end

-- valueX is where the box sits, from x.
local function makeNumber(parent, x, y, label, getter, setter, low, high, valueX)
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
    heading(pf, x, top, def.title)

    makeCheck(pf, x - 4, top - 22, "Show this window", setting(def.key, "shown"))
    makeCheck(pf, x - 4, top - 48, "Locked (clicks pass through)", setting(def.key, "locked"))
    local y = top - 76
    if def.key == "window" then
        makeCheck(pf, x - 4, y, "Hide lines once passed", setting(def.key, "hidePassed"))
        makeCheck(pf, x - 4, y - 26, "Show only me", setting(def.key, "onlyMe"))
        y = y - 52
    end
    makeNumber(pf, x, y, "Font size (8 to 32)", setting(def.key, "fontSize"), 8, 32)
    makeNumber(pf, x, y - 26, "Window alpha %", setting(def.key, "alpha"), 10, 100)
    makeNumber(pf, x, y - 52, "Background alpha %", setting(def.key, "bgAlpha"), 0, 100)

    local font = makeButton(pf, "Font", COLUMN_W - 16)
    font:SetPoint("TOPLEFT", x, y - 84)
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
        font:SetText("Font: " .. (Notes:WindowSettings(def.key).font or "Friz Quadrata"))
    end
    controls[#controls + 1] = font

    local reset = makeButton(pf, "Reset position", COLUMN_W - 16)
    reset:SetPoint("TOPLEFT", x, y - 114)
    reset:SetScript("OnClick", function()
        CRT.NoteWindow:ResetPosition(def.key)
    end)
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
    hint:SetText("Untick Locked to drag a window and resize it from its bottom-right corner, then lock it again so clicks pass through. Toggle previews shows every window with sample text. Everything here is saved for you.")

    -- The three note windows.
    for index, def in ipairs(WINDOWS) do
        buildColumn(pf, index, def, -46)
    end

    -- Your alert, on the left, and sharing, on the right.
    local top = -340
    heading(pf, 8, top, "Your alert")
    makeCheck(pf, 4, top - 22, "Show your next spell or callout", alert("enabled"))
    makeNumber(pf, 4, top - 48, "Show it this many seconds early", alert("seconds"), 1, 60, 280)
    makeCheck(pf, 4, top - 74, "Read it out (text to speech)", alert("tts"))
    makeNumber(pf, 4, top - 100, "Read it out at seconds left", alert("ttsSeconds"), 0, 30, 280)
    makeNumber(pf, 4, top - 126, "Speech volume (0 to 100)", alert("ttsVolume"), 0, 100, 280)
    local speak = makeButton(pf, "Test speech", 140)
    speak:SetPoint("TOPLEFT", 8, top - 158)
    speak:SetScript("OnClick", function()
        CRT.NoteAlert:Speak("Cowfee Raid Tools. Avenging Wrath in three.")
    end)

    heading(pf, 360, top, "Sharing")
    makeCheck(pf, 356, top - 22, "Only accept notes from leader or assistants", function()
        return Notes:TrustedOnly()
    end, function(value)
        Notes:Set(nil, "trustedOnly", value)
    end)

    pf:SetScript("OnShow", refresh)
    Notes:OnChange(refresh)
end

-- Built into the Settings tab by Notes/Page.lua.
CRT.NoteSettings = { Build = build }
