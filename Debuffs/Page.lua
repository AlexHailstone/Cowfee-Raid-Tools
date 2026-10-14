local ADDON, CRT = ...

-- The Debuffs page: settings for the in-combat debuff panel. The panel is moved with
-- "Previews" in the corner of the main window.

local Debuffs = CRT.Debuffs
local UI = CRT.UI

local page, enabledCheck, sizeEdit, countEdit, dispelCheck, regularCheck
local refresh
local look = {} -- the Look section's controls, each with refresh(on)

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 26)
    b:SetText(label)
    return b
end

local function makeCheck(pf, label, yOffset, onClick, x)
    local check = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", x or 4, yOffset)
    local text = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked())
    end)
    check.label = text
    return check
end

-- Greys a box or a number out, with its label, while the setting it depends on is off.
local function usable(control, on)
    control:SetEnabled(on)
    local c = on and 1 or 0.5
    control.label:SetTextColor(c, c, c)
    if control.SetTextColor then
        control:SetTextColor(c, c, c)
    end
end

-- A dropdown for one look setting, in the Edit Mode style (UI/Controls.lua).
local function lookDropdown(pf, yOffset, text, field, choices)
    local row = UI.Dropdown(pf, text, {
        options = choices,
        labelWidth = 80,
        width = 150,
        get = function()
            return Debuffs:Get(field)
        end,
        set = function(key)
            Debuffs:Set(field, key)
        end,
        enabledIf = function()
            return Debuffs:Enabled()
        end,
    })
    row:SetPoint("TOPLEFT", 8, yOffset)
    look[#look + 1] = row
    return row
end

-- A small box for a nudge in pixels, which can be negative.
local function nudgeBox(pf, anchor, label, field)
    local text = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
    text:SetText(label)
    local edit = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontHighlight)
    edit:SetMaxLetters(3)
    edit:SetSize(36, 20)
    edit:SetPoint("LEFT", text, "RIGHT", 8, 0)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(Debuffs:Get(field)))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        Debuffs:SetNudge(field, self:GetText())
        self:SetText(tostring(Debuffs:Get(field)))
    end)
    edit.label = text
    edit.refresh = function(on)
        if not edit:HasFocus() then
            edit:SetText(tostring(Debuffs:Get(field)))
        end
        usable(edit, on and Debuffs:TimerAnchor() ~= nil)
    end
    look[#look + 1] = edit
    return edit
end

local function lookCheck(pf, label, yOffset, field, x, dependsOn)
    local check = makeCheck(pf, label, yOffset, function(checked)
        Debuffs:Set(field, checked and true or false)
    end, x)
    check.refresh = function(on)
        check:SetChecked(Debuffs:Get(field) and true or false)
        usable(check, on and (not dependsOn or Debuffs:Get(dependsOn) and true or false))
    end
    look[#look + 1] = check
    return check
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    enabledCheck:SetChecked(Debuffs:Enabled())
    dispelCheck:SetChecked(Debuffs:DispelIcon())
    regularCheck:SetChecked(Debuffs:IncludeRegular())
    local on = Debuffs:Enabled() and true or false
    sizeEdit.refresh()
    countEdit.refresh()
    usable(dispelCheck, on)
    usable(regularCheck, on)
    for _, control in ipairs(look) do
        control.refresh(on)
    end
end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Debuffs")

    UI.Help(pf, "The debuff panel", "A movable panel for the short debuffs a boss puts on you in combat. The game hides those from addons, but lets an addon choose where it draws them, so this panel is where they appear. Press Previews in the top right corner of this window to see it and drag it into place.\n\nThese are the boss mechanic debuffs the game calls private auras, which are short by design, so no time filter is needed.\n\nRegular debuffs cannot be limited to short ones, because the game hides their durations from addons in combat, which is why that row is off by default.\n\nShow diagnostics prints what the game allows on your client. Your settings are saved in your own saved variables."):SetPoint("LEFT", title, "RIGHT", 6, 0)

    enabledCheck = makeCheck(pf, "Show the panel in combat", -44, function(checked)
        Debuffs:SetEnabled(checked)
    end)

    local function panelOn()
        return Debuffs:Enabled()
    end
    sizeEdit = UI.Slider(pf, "Icon size", { min = 24, max = 96, step = 2, labelWidth = 130, width = 200, enabledIf = panelOn, get = function()
        return Debuffs:Size()
    end, set = function(value)
        Debuffs:SetSize(value)
    end })
    sizeEdit:SetPoint("TOPLEFT", 8, -70)
    countEdit = UI.Slider(pf, "How many to show", { min = 1, max = 8, labelWidth = 130, width = 200, enabledIf = panelOn, get = function()
        return Debuffs:MaxCount()
    end, set = function(value)
        Debuffs:SetMaxCount(value)
    end })
    countEdit:SetPoint("TOPLEFT", 8, -98)

    dispelCheck = makeCheck(pf, "Show the dispel type icon on each debuff", -130, function(checked)
        Debuffs:SetDispelIcon(checked)
    end)
    regularCheck = makeCheck(pf, "Also show regular debuffs in a second row (this includes long ones)", -154, function(checked)
        Debuffs:SetIncludeRegular(checked)
    end)
    local reset = makeButton(pf, "Reset position", 160)
    reset:SetPoint("TOPLEFT", 8, -192)
    reset:SetScript("OnClick", function()
        CRT.DebuffPanel:ResetPosition()
    end)

    local info = makeButton(pf, "Show diagnostics", 160)
    info:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    info:SetScript("OnClick", function()
        CRT.DebuffPanel:ShowInfo()
    end)

    -- The look of the boss debuff icons. Previews shows the changes as you make them.
    local lookTitle = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    lookTitle:SetPoint("TOPLEFT", 8, -236)
    lookTitle:SetText("Look")
    UI.Help(pf, "Look", "The game draws boss mechanic debuffs itself, and only takes these options from an addon. It writes their timer in its own shared small font, so their font and text size can't be changed without changing text all over the game. The font setting on the Addon Settings page changes everything else.\n\nTimer: the game's timer text beside or on the icon, or its countdown numbers on the swipe, never both.\n\nBorder size: the game's colored debuff border, the icon plus 5 pixels for each step.\n\nTurn on Previews to see each change as you make it."):SetPoint("LEFT", lookTitle, "RIGHT", 6, 0)

    local timer = lookDropdown(pf, -254, "Timer", "timerPosition", Debuffs.TIMER_POSITIONS)
    local nudgeX = nudgeBox(pf, timer, "Nudge X", "timerX")
    nudgeBox(pf, nudgeX, "Y", "timerY")
    lookCheck(pf, "Swipe animation as the debuff runs out", -288, "swipe")
    lookCheck(pf, "Bright edge on the swipe", -312, "swipeEdge", 28, "swipe")
    local border = UI.Slider(pf, "Border size", { min = 0, max = 6, step = 0.5, labelWidth = 80, width = 200, enabledIf = panelOn,
        format = function(v)
            return format("%g", v)
        end,
        get = function()
            return Debuffs:Get("borderScale") or 1
        end,
        set = function(v)
            Debuffs:Set("borderScale", v)
        end,
    })
    border:SetPoint("TOPLEFT", 8, -340)
    look[#look + 1] = border


    pf:SetScript("OnShow", refresh)
    Debuffs:OnChange(refresh)
end

UI:RegisterPage("debuffs", "Debuffs", build)
