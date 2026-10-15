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
    lowHealthSound = "Also play the game's low-health pulse sound  |cff999999(WIP)|r",
    lowHealthSoundWIP = "Work in progress: the low-health sound doesn't work yet, so it is switched off. The game hides its low-health decision from addons, and its Combat Audio Alerts errored alongside other addons when turned on. Any game setting it changed has been put back. We'll come back to it.",
    lowHealthSoundNote = "Turns on the game's own low-health pulse (Combat Audio Alerts, in the game's Accessibility options): a sound that loops while your health is under your threshold, faster as it drops. The game compares your health itself, so it works in combat, where an addon can't.\n\nThe pulse works in 10% steps, so your threshold is rounded to the nearest one (35% becomes 40%).\n\nIf you weren't using Combat Audio Alerts, its spoken alerts are switched off so only the pulse plays. Unticking this puts every game setting it changed back.",
    lowHealthVolume = "Volume",
    lowHealthChoice = "Sound",
    lowHealthChoiceNote = "The game's pulse loops and speeds up as your health drops. Any other sound repeats, faster at each lower 10%.\n\nShared sounds come from other addons through LibSharedMedia, when one of them is installed.\n\nYour own sounds: put an .ogg or .mp3 file in Interface\\AddOns\\CowfeeRaidTools\\Sounds, /reload, then type its name below and press Add. Updating the addon by replacing its folder removes them, so keep a copy.\n\nVolume only changes the game's sounds. Shared and your own sounds play at the volume of their output channel.",
    lowHealthOnce = "Play once each time my health drops under",
    lowHealthOnceNote = "On: the sound plays one time, in full, each time your health drops under the threshold. Dropping lower during the same dip doesn't play it again; healing and dropping again does.\n\nOff: it repeats until you heal, faster as your health drops, each repeat cutting off the one before.\n\nThe game's pulse is a loop and keeps looping either way.",
    lowHealthCustom = "Your sound file",
    lowHealthAdd = "Add",
    lowHealthRemove = "Remove",
    lowHealthOutput = "Output",
    lowHealthOutputNote = "Game default plays the sound on the game's voice output, like its own pulse. Pick a channel to follow that channel's volume and mute in the game's Sound settings instead.\n\nAny sound other than the game's pulse, or any channel, is played by the addon: the game's pulse runs silently and the addon plays yours whenever it starts or stops, so it still works in combat.",
    lowHealthTest = "Test sound",
    lowHealthStop = "Stop sound",
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
    UI.Help(pf, TEXT.lowHealthSound, function()
        return Sound.WIP and TEXT.lowHealthSoundWIP or TEXT.lowHealthSoundNote
    end):SetPoint("LEFT", soundText, "RIGHT", 6, 0)
    sound:SetScript("OnClick", function(self)
        settings().sound = self:GetChecked() and true or false
        Sound:Apply()
        refresh()
    end)
    sound.refresh = function()
        local on = alertOn() and Sound:Available() and not Sound.WIP
        sound:SetChecked((settings().sound and not Sound.WIP) and true or false)
        sound:SetEnabled(on)
        local c = on and 1 or 0.5
        soundText:SetTextColor(c, c, c)
    end
    controls[#controls + 1] = sound

    local function soundOn()
        return alertOn() and settings().sound and not Sound.WIP
    end
    -- A Play button inside each item of the Sound and Output menus: the Sound menu plays each sound on
    -- your output, the Output menu plays your sound on each output. Click again to stop; it stops by
    -- itself after 3 seconds.
    local function playButton(choiceOf, outputOf)
        return function(button, option)
            local choiceKey, outputKey = choiceOf(option), outputOf(option)
            local hit = button:AttachFrame("Button")
            hit:SetSize(40, 18)
            hit:SetPoint("RIGHT", -4, 0)
            hit:EnableMouse(true)
            local label = button:AttachFontString()
            label:SetFontObject(CRTFontButtonSmall)
            label:SetPoint("CENTER", hit, "CENTER")
            local token = {}
            hit.crtToken = token
            local function show()
                if Sound:IsPreviewing(choiceKey, outputKey) then
                    label:SetText("|cffff6060Stop|r")
                else
                    label:SetText("|cff80c0ffPlay|r")
                end
            end
            show()
            hit:SetScript("OnClick", function()
                Sound:Preview(choiceKey, outputKey, function()
                    -- The menu reuses its pieces, so only update this label if it is still this item's.
                    if hit.crtToken == token then
                        show()
                    end
                end)
                show()
            end)
            if button.fontString then
                button.fontString:SetPoint("RIGHT", hit, "LEFT", -6, 0)
            end
            local textWidth = button.fontString and button.fontString:GetUnboundedStringWidth() or 120
            return textWidth + 80, 20
        end
    end

    local choice = UI.Dropdown(pf, TEXT.lowHealthChoice, {
        options = Sound.Choices,
        decorate = playButton(function(option)
            return option.key
        end, function()
            return settings().soundChannel or "game"
        end),
        labelWidth = SLIDER_LABEL_W,
        width = 200,
        get = function()
            return settings().soundChoice or "pulse"
        end,
        set = function(key)
            settings().soundChoice = key
            Sound:Apply()
            refresh()
        end,
        enabledIf = soundOn,
    })
    choice:SetPoint("TOPLEFT", 10, top - 100)
    controls[#controls + 1] = choice
    UI.Help(pf, TEXT.lowHealthChoice, TEXT.lowHealthChoiceNote):SetPoint("LEFT", choice, "RIGHT", 6, 0)

    local output = UI.Dropdown(pf, TEXT.lowHealthOutput, {
        options = Sound.Outputs,
        decorate = playButton(function()
            return settings().soundChoice or "pulse"
        end, function(option)
            return option.key
        end),
        labelWidth = SLIDER_LABEL_W,
        width = 200,
        get = function()
            return settings().soundChannel or "game"
        end,
        set = function(key)
            settings().soundChannel = key
            Sound:Apply()
            refresh()
        end,
        enabledIf = soundOn,
    })
    output:SetPoint("TOPLEFT", 10, top - 130)
    controls[#controls + 1] = output
    UI.Help(pf, TEXT.lowHealthOutput, TEXT.lowHealthOutputNote):SetPoint("LEFT", output, "RIGHT", 6, 0)

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
        enabledIf = soundOn,
    })
    volume:SetPoint("TOPLEFT", 10, top - 160)
    controls[#controls + 1] = volume

    -- Play once: the sound plays one time per dip under the threshold (not the game's looping pulse).
    local once = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    once:SetSize(24, 24)
    once:SetPoint("TOPLEFT", 6, top - 192)
    local onceText = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    onceText:SetPoint("LEFT", once, "RIGHT", 1, 0)
    onceText:SetText(TEXT.lowHealthOnce)
    UI.Help(pf, TEXT.lowHealthOnce, TEXT.lowHealthOnceNote):SetPoint("LEFT", onceText, "RIGHT", 6, 0)
    once:SetScript("OnClick", function(self)
        settings().soundOnce = self:GetChecked() and true or false
        Sound:StopOurs()
        refresh()
    end)
    once.refresh = function()
        local on = soundOn() and (settings().soundChoice or "pulse") ~= "pulse"
        once:SetChecked(settings().soundOnce ~= false)
        once:SetEnabled(on and true or false)
        local c = on and 1 or 0.5
        onceText:SetTextColor(c, c, c)
    end
    controls[#controls + 1] = once

    -- Your own sound files, added by name since the game can't list a folder.
    local customLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    customLabel:SetPoint("TOPLEFT", 10, top - 228)
    customLabel:SetWidth(SLIDER_LABEL_W)
    customLabel:SetJustifyH("LEFT")
    customLabel:SetText(TEXT.lowHealthCustom)
    local customEdit = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    customEdit:SetAutoFocus(false)
    customEdit:SetFontObject(CRTFontHighlight)
    customEdit:SetMaxLetters(80)
    customEdit:SetSize(190, 22)
    customEdit:SetPoint("LEFT", customLabel, "RIGHT", 12, 0)
    customEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    customEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    local add = smallButton(pf, TEXT.lowHealthAdd)
    add:SetWidth(60)
    add:SetPoint("LEFT", customEdit, "RIGHT", 8, 0)
    add:SetScript("OnClick", function()
        local ok, message = Sound:AddCustom(customEdit:GetText())
        CRT:Print(message)
        if ok then
            local name = customEdit:GetText():gsub("^%s+", ""):gsub("%s+$", "")
            customEdit:SetText("")
            settings().soundChoice = "file:" .. name
            Sound:Apply()
        end
        refresh()
    end)
    local remove = smallButton(pf, TEXT.lowHealthRemove)
    remove:SetWidth(70)
    remove:SetPoint("LEFT", add, "RIGHT", 6, 0)
    remove:SetScript("OnClick", function()
        local file = (settings().soundChoice or ""):match("^file:(.+)$")
        if file and Sound:RemoveCustom(file) then
            CRT:Print("Removed " .. file .. " from the list. The file itself stays in the Sounds folder.")
            Sound:Apply()
        end
        refresh()
    end)
    controls[#controls + 1] = {
        refresh = function()
            local on = soundOn() and true or false
            customEdit:SetEnabled(on)
            add:SetEnabled(on)
            remove:SetEnabled(on and (settings().soundChoice or ""):find("^file:") ~= nil)
            local c = on and 1 or 0.5
            customLabel:SetTextColor(c, c, c)
        end,
    }

    local test = smallButton(pf, TEXT.lowHealthTest)
    test:SetPoint("LEFT", volume, "RIGHT", 12, 0)
    -- Test sound plays your choice for 3 seconds; while it plays the button stops it.
    test:SetScript("OnClick", function()
        local started = Sound:Test(function()
            test:SetText(TEXT.lowHealthTest)
        end)
        test:SetText(started and TEXT.lowHealthStop or TEXT.lowHealthTest)
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
    -- Leaving the page stops any sound being tried out.
    pf:SetScript("OnHide", function()
        CRT.LowHealthSound:StopPreview()
    end)
end

UI:RegisterPage("qol", TEXT.title, build)
