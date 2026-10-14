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
    lowHealthNote = "Experimental: in combat the game hides your health from addons, so the banner lets the game compare it to your setting. If it misbehaves, untick it here or type /crt lowhp off. Use Toggle previews to place the banner.",
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
local function makeSlider(pf, x, y, low, high, width)
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
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local value = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    return slider, value
end

-- Panel size ----------------------------------------------------------------------------------

local function buildPanelSize(pf, top)
    local heading = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    heading:SetPoint("TOPLEFT", 8, top)
    heading:SetText(TEXT.panelSize)
    local sliderLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    sliderLabel:SetPoint("TOPLEFT", 12, top - 22)
    sliderLabel:SetText(TEXT.panelSizeLabel)

    local slider, value = makeSlider(pf, 16, top - 44, UI.MIN_SCALE, UI.MAX_SCALE, 240)
    -- The slider sits inside the window it resizes, so the size is applied when the mouse lets go,
    -- not on every step, or the slider would move under the mouse while dragging.
    local updating = false
    slider:SetScript("OnValueChanged", function(_, v)
        value:SetText(math.floor(v + 0.5) .. "%")
    end)
    slider:SetScript("OnMouseUp", function(self)
        if not updating then
            UI:SetScale(self:GetValue())
        end
    end)
    slider.refresh = function()
        updating = true
        slider:SetValue(UI:Scale())
        updating = false
        value:SetText(UI:Scale() .. "%")
    end
    controls[#controls + 1] = slider

    local reset = makeButton(pf, TEXT.panelSizeReset, 140, 22)
    reset:SetPoint("LEFT", value, "RIGHT", 16, 0)
    reset:SetScript("OnClick", function()
        UI:SetScale(100)
    end)

    local note = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    note:SetPoint("TOPLEFT", 16, top - 66)
    note:SetWidth(650)
    note:SetJustifyH("LEFT")
    note:SetText(TEXT.panelSizeNote)
end

-- Low-health alert ----------------------------------------------------------------------------

local function buildLowHealth(pf, top)
    local heading = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    heading:SetPoint("TOPLEFT", 8, top)
    heading:SetText(TEXT.lowHealth .. "  |cff999999" .. TEXT.lowHealthTag .. "|r")

    local check = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 4, top - 20)
    local checkText = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    checkText:SetPoint("LEFT", check, "RIGHT", 2, 0)
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
    sliderLabel:SetPoint("TOPLEFT", 32, top - 46)
    sliderLabel:SetText(TEXT.lowHealthThreshold)
    local slider, value = makeSlider(pf, 36, top - 66, 5, 90, 240)

    local updating = false
    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
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

    local reset = makeButton(pf, TEXT.resetPosition, 160)
    reset:SetPoint("TOPLEFT", 36, top - 90)
    reset:SetScript("OnClick", function()
        LowHealth:ResetPosition()
    end)

    local note = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    note:SetPoint("TOPLEFT", 36, top - 120)
    note:SetWidth(630)
    note:SetJustifyH("LEFT")
    note:SetText(TEXT.lowHealthNote)
end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(TEXT.title)

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -34)
    hint:SetWidth(670)
    hint:SetJustifyH("LEFT")
    hint:SetText(TEXT.hint)

    buildPanelSize(pf, -62)
    buildLowHealth(pf, -168)

    pf:SetScript("OnShow", refresh)
    -- Ctrl + mouse wheel changes the size too, so the slider follows it.
    UI.onScale = refresh
end

UI:RegisterPage("qol", TEXT.title, build)
