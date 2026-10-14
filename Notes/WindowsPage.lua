local ADDON, CRT = ...

-- The Note Windows page: one column of settings for each of the three note windows (timers,
-- assignments, personal note). Unlocked windows can be dragged and resized by hand, and their position
-- and size are saved per player.

local Notes = CRT.Notes
local UI = CRT.UI

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

local function makeNumber(parent, x, y, label, getter, setter, low, high)
    local text = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("TOPLEFT", x + 4, y - 4)
    text:SetText(label)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontHighlight)
    edit:SetNumeric(true)
    edit:SetMaxLetters(3)
    edit:SetSize(44, 20)
    edit:SetPoint("TOPLEFT", x + 160, y - 2)
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

local function buildColumn(pf, index, def)
    local x = 8 + (index - 1) * COLUMN_W
    local top = -96
    local label = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    label:SetPoint("TOPLEFT", x, top)
    label:SetText(def.title)

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

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Note Windows")

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -32)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")
    hint:SetText("Three windows: the timers, the assignments (a note's text that is not a timer), and your personal note. Untick Locked to drag a window and resize it from its bottom-right corner, then lock it again so clicks pass through. Toggle previews shows all three with sample text. Size and position are saved for you.")

    for index, def in ipairs(WINDOWS) do
        buildColumn(pf, index, def)
    end

    local back = makeButton(pf, "Back to Raid Notes", 200)
    back:SetPoint("TOPLEFT", 8, -400)
    back:SetScript("OnClick", function()
        UI:Show("notes")
    end)

    pf:SetScript("OnShow", refresh)
    Notes:OnChange(refresh)
end

UI:RegisterPage("notewindows", "Note Windows", build)
