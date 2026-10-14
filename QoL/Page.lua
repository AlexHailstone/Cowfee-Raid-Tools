local ADDON, CRT = ...

-- The Quality of Life page: a home for small conveniences and their settings, in CRTDB.qol with
-- defaults in Core.lua. The panel's size (CRTDB.window.scale, applied by UI/Panel.lua), and the
-- experimental low-health alert (QoL/LowHealth.lua).

local UI = CRT.UI
local LowHealth = CRT.LowHealth

-- Every word on this page, in one place so the wording is easy to change.
local TEXT = {
    title = "Quality of Life",
    hint = "Small conveniences for raid nights.",

    panelSize = "Panel size",
    panelSizeLabel = "Size of this window, text included (50% to 200%):",
    panelSizeNote = "The new size applies when you let go of the slider. Ctrl + mouse wheel over the window also changes it.",
    panelSizeReset = "Reset to 100%",

    lowHealth = "Low-health alert",
    lowHealthTag = "(experimental)",
    lowHealthEnable = "Show a LOW HEALTH banner when my health is low",
    lowHealthThreshold = "Show it at or under this much health:",
    lowHealthNote = "Experimental: in combat the game hides your health from addons, so the banner lets the game compare it to your setting. If it misbehaves, untick it here or type /crt lowhp off. Use Previews to place the banner.",
    resetPosition = "Reset position",
}

local GREY, WHITE, GOLD = { 0.5, 0.5, 0.5 }, { 1, 1, 1 }, { 1, 0.82, 0 }

local page
local controls = {}

local function settings()
    return CRT.db.qol.lowHealth
end

local function color(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 24)
    b:SetText(label)
    return b
end

local function refresh()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
end

-- A horizontal slider with its value beside it, built from the plain Slider widget and color
-- textures. Returns the slider and the value text. The caller sets its scripts.
local function makeSlider(pf, x, y, low, high, width, step)
    local slider = CreateFrame("Slider", nil, pf, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 14)
    slider:SetPoint("TOPLEFT", x, y)
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    slider:SetBackdropColor(0, 0, 0, 0.6)
    slider:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 0.82, 0, 1)
    thumb:SetSize(10, 18)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    local value = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    return slider, value
end

-- A small button in the game's small font, the size of the Previews button's text.
-- Rounds a slider value to its step of 5, however the value arrived.
local function toFive(v)
    return math.floor(v / 5 + 0.5) * 5
end

local function smallButton(pf, text)
    local b = makeButton(pf, text, 110, 20)
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
    return b
end

-- Panel size ----------------------------------------------------------------------------------

local function buildPanelSize(pf, top)
    local heading = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    heading:SetPoint("TOPLEFT", 8, top)
    heading:SetText(TEXT.panelSize)
    UI.Help(pf, TEXT.panelSize, TEXT.panelSizeNote):SetPoint("LEFT", heading, "RIGHT", 6, 0)
    local sliderLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    sliderLabel:SetPoint("TOPLEFT", 10, top - 16)
    sliderLabel:SetText(TEXT.panelSizeLabel)

    local slider, value = makeSlider(pf, 10, top - 32, UI.MIN_SCALE, UI.MAX_SCALE, 100, 5)
    -- The slider sits inside the window it resizes, so the size is applied when the mouse lets go,
    -- not on every step, or the slider would move under the mouse while dragging.
    local updating = false
    slider:SetScript("OnValueChanged", function(_, v)
        value:SetText(toFive(v) .. "%")
    end)
    slider:SetScript("OnMouseUp", function(self)
        if not updating then
            UI:SetScale(toFive(self:GetValue()))
        end
    end)
    slider.refresh = function()
        updating = true
        slider:SetValue(UI:Scale())
        updating = false
        value:SetText(UI:Scale() .. "%")
    end
    controls[#controls + 1] = slider

    local reset = smallButton(pf, TEXT.panelSizeReset)
    reset:SetPoint("LEFT", value, "RIGHT", 16, 0)
    reset:SetScript("OnClick", function()
        UI:SetScale(100)
    end)

end

-- Low-health alert ----------------------------------------------------------------------------

local function buildLowHealth(pf, top)
    local heading = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    heading:SetPoint("TOPLEFT", 8, top)
    heading:SetText(TEXT.lowHealth .. "  |cff999999" .. TEXT.lowHealthTag .. "|r")
    UI.Help(pf, TEXT.lowHealth, TEXT.lowHealthNote):SetPoint("LEFT", heading, "RIGHT", 6, 0)

    local check = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 6, top - 18)
    local checkText = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    checkText:SetPoint("LEFT", check, "RIGHT", 1, 0)
    checkText:SetText(TEXT.lowHealthEnable)
    check:SetScript("OnClick", function(self)
        LowHealth:SetEnabled(self:GetChecked())
        refresh()
    end)
    check.refresh = function()
        check:SetChecked(settings().enabled and true or false)
    end
    controls[#controls + 1] = check

    -- The slider, with the percent beside it. Built from the plain Slider widget and color textures.
    local sliderLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    sliderLabel:SetPoint("TOPLEFT", 10, top - 42)
    sliderLabel:SetText(TEXT.lowHealthThreshold)
    local slider, value = makeSlider(pf, 10, top - 58, 5, 90, 100, 5)

    local updating = false
    slider:SetScript("OnValueChanged", function(_, v)
        v = toFive(v)
        value:SetText(v .. "%")
        if not updating then
            settings().threshold = v
            LowHealth:Apply()
        end
    end)
    slider.refresh = function()
        local on = settings().enabled and true or false
        updating = true
        slider:SetValue(settings().threshold or 35)
        updating = false
        value:SetText((settings().threshold or 35) .. "%")
        slider:SetEnabled(on)
        slider:SetAlpha(on and 1 or 0.5)
        color(sliderLabel, on and WHITE or GREY)
        color(value, on and GOLD or GREY)
    end
    controls[#controls + 1] = slider

    local reset = smallButton(pf, TEXT.resetPosition)
    reset:SetPoint("LEFT", value, "RIGHT", 16, 0)
    reset:SetScript("OnClick", function()
        LowHealth:ResetPosition()
    end)

end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(TEXT.title)

    UI.Help(pf, TEXT.title, TEXT.hint):SetPoint("LEFT", title, "RIGHT", 6, 0)

    buildPanelSize(pf, -42)
    buildLowHealth(pf, -98)

    pf:SetScript("OnShow", refresh)
    -- Ctrl + mouse wheel changes the size too, so the slider follows it.
    UI.onScale = refresh
end

UI:RegisterPage("qol", TEXT.title, build)
