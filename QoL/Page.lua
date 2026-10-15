local ADDON, CRT = ...

-- The Quality of Life page: a home for small conveniences and their settings, in CRTDB.qol with
-- defaults in Core.lua: the experimental low-health alert (QoL/LowHealth.lua). The window scale moved
-- to the Addon Settings page (UI/SettingsPage.lua) in 0.13.1.

local UI = CRT.UI
local LowHealth = CRT.LowHealth

-- Every word on this page, in one place so the wording is easy to change.
local TEXT = {
    title = "Quality of Life",
    hint = "Small conveniences for raid nights.",

    lowHealth = "Low-health alert",
    lowHealthTag = "(experimental)",
    lowHealthEnable = "Show a LOW HEALTH banner when my health is low",
    lowHealthThreshold = "Show it at or under this much health:",
    lowHealthSound = "Also play the game's low-health pulse sound",
    lowHealthSoundNote = "Turns on the game's own low-health pulse (Combat Audio Alerts, in the game's Accessibility options): a sound that loops while your health is under your threshold, faster as it drops. The game compares your health itself, so it works in combat, where an addon can't.\n\nThe pulse works in 10% steps, so your threshold is rounded to the nearest one (35% becomes 40%).\n\nIf you weren't using Combat Audio Alerts, its spoken alerts are switched off so only the pulse plays. Unticking this puts every game setting it changed back.",
    lowHealthVolume = "Pulse volume",
    lowHealthTest = "Test sound",
    lowHealthNote = "Experimental: in combat the game hides your health from addons, so the banner lets the game compare it to your setting. If it misbehaves, untick it here or type /crt lowhp off. Use Previews to place the banner.",
    resetPosition = "Reset position",
}

local page
local controls = {}

local function settings()
    return CRT.db.qol.lowHealth
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

-- Both sliders line up: the labels share one width. The sliders are Edit Mode sliders (UI/Controls.lua).
local SLIDER_LABEL_W = 230

local function percent(v)
    return v .. "%"
end

-- A small button in the game's small font, the size of the Previews button's text.
local function smallButton(pf, text)
    local b = makeButton(pf, text, 110, 20)
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    return b
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

    local slider = UI.Slider(pf, TEXT.lowHealthThreshold, {
        min = 5,
        max = 90,
        step = 5,
        labelWidth = SLIDER_LABEL_W,
        width = 200,
        format = percent,
        get = function()
            return settings().threshold or 35
        end,
        set = function(v)
            settings().threshold = v
            LowHealth:Apply()
        end,
        enabledIf = function()
            return settings().enabled
        end,
    })
    slider:SetPoint("TOPLEFT", 10, top - 42)
    controls[#controls + 1] = slider

    local reset = smallButton(pf, TEXT.resetPosition)
    reset:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    reset:SetScript("OnClick", function()
        LowHealth:ResetPosition()
    end)

    -- The sound: the game's own low-health pulse.
    local Sound = CRT.LowHealthSound
    local function alertOn()
        return settings().enabled
    end
    local sound = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    sound:SetSize(24, 24)
    sound:SetPoint("TOPLEFT", 6, top - 76)
    local soundText = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    soundText:SetPoint("LEFT", sound, "RIGHT", 1, 0)
    soundText:SetText(TEXT.lowHealthSound)
    UI.Help(pf, TEXT.lowHealthSound, TEXT.lowHealthSoundNote):SetPoint("LEFT", soundText, "RIGHT", 6, 0)
    sound:SetScript("OnClick", function(self)
        settings().sound = self:GetChecked() and true or false
        Sound:Apply()
        refresh()
    end)
    sound.refresh = function()
        local on = alertOn() and Sound:Available()
        sound:SetChecked(settings().sound and true or false)
        sound:SetEnabled(on)
        local c = on and 1 or 0.5
        soundText:SetTextColor(c, c, c)
    end
    controls[#controls + 1] = sound

    local volume = UI.Slider(pf, TEXT.lowHealthVolume, {
        min = 0,
        max = 100,
        step = 5,
        labelWidth = SLIDER_LABEL_W,
        width = 200,
        format = percent,
        get = function()
            return settings().soundVolume or 100
        end,
        set = function(v)
            settings().soundVolume = v
            Sound:Apply()
        end,
        enabledIf = function()
            return alertOn() and settings().sound
        end,
    })
    volume:SetPoint("TOPLEFT", 10, top - 100)
    controls[#controls + 1] = volume

    local test = smallButton(pf, TEXT.lowHealthTest)
    test:SetPoint("LEFT", volume, "RIGHT", 12, 0)
    test:SetScript("OnClick", function()
        Sound:Test()
    end)

end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(TEXT.title)

    UI.Help(pf, TEXT.title, TEXT.hint):SetPoint("LEFT", title, "RIGHT", 6, 0)

    buildLowHealth(pf, -42)

    pf:SetScript("OnShow", refresh)
end

UI:RegisterPage("qol", TEXT.title, build)
