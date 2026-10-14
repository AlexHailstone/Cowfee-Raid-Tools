local ADDON, CRT = ...

-- The Debuffs page: settings for the in-combat debuff panel. The panel is moved with
-- "Toggle previews" in the corner of the main window.

local Debuffs = CRT.Debuffs
local UI = CRT.UI

local page, enabledCheck, sizeEdit, countEdit, dispelCheck, regularCheck
local refresh

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 26)
    b:SetText(label)
    return b
end

local function makeCheck(pf, label, yOffset, onClick)
    local check = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 4, yOffset)
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

local function numberBox(pf, label, yOffset, getter, setter, maxLetters)
    local text = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("TOPLEFT", 8, yOffset)
    text:SetText(label)

    local edit = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontHighlight)
    edit:SetNumeric(true)
    edit:SetMaxLetters(maxLetters or 3)
    edit:SetSize(50, 22)
    edit:SetPoint("LEFT", text, "LEFT", 220, 0)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(getter()))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        setter(self:GetText())
        self:SetText(tostring(getter()))
    end)
    edit.label = text
    return edit
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    enabledCheck:SetChecked(Debuffs:Enabled())
    dispelCheck:SetChecked(Debuffs:DispelIcon())
    regularCheck:SetChecked(Debuffs:IncludeRegular())
    if not sizeEdit:HasFocus() then
        sizeEdit:SetText(tostring(Debuffs:Size()))
    end
    if not countEdit:HasFocus() then
        countEdit:SetText(tostring(Debuffs:MaxCount()))
    end
    local on = Debuffs:Enabled() and true or false
    usable(sizeEdit, on)
    usable(countEdit, on)
    usable(dispelCheck, on)
    usable(regularCheck, on)
end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Debuffs")

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -34)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")
    hint:SetText("A movable panel for the short debuffs a boss puts on you in combat. The game hides those from addons, but lets an addon choose where it draws them, so this panel is where they appear. Press Toggle previews in the top right corner of this window to see it and drag it into place.")

    enabledCheck = makeCheck(pf, "Show the panel in combat", -86, function(checked)
        Debuffs:SetEnabled(checked)
    end)

    sizeEdit = numberBox(pf, "Icon size (24 to 96)", -128, function()
        return Debuffs:Size()
    end, function(value)
        Debuffs:SetSize(value)
    end)
    countEdit = numberBox(pf, "How many to show (1 to 8)", -160, function()
        return Debuffs:MaxCount()
    end, function(value)
        Debuffs:SetMaxCount(value)
    end, 1)

    dispelCheck = makeCheck(pf, "Show the dispel type icon on each debuff", -192, function(checked)
        Debuffs:SetDispelIcon(checked)
    end)
    regularCheck = makeCheck(pf, "Also show regular debuffs in a second row (this includes long ones)", -222, function(checked)
        Debuffs:SetIncludeRegular(checked)
    end)
    local reset = makeButton(pf, "Reset position", 160)
    reset:SetPoint("TOPLEFT", 8, -268)
    reset:SetScript("OnClick", function()
        CRT.DebuffPanel:ResetPosition()
    end)

    local info = makeButton(pf, "Show diagnostics", 160)
    info:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    info:SetScript("OnClick", function()
        CRT.DebuffPanel:ShowInfo()
    end)

    -- The longer explanation, as a tooltip on a small link instead of a paragraph on the page.
    local about = CreateFrame("Button", nil, pf)
    about:SetPoint("LEFT", info, "RIGHT", 16, 0)
    about:SetSize(150, 22)
    local aboutText = about:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    aboutText:SetPoint("LEFT")
    aboutText:SetText("|cff80c0ff(?) How this works|r")
    about:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("How the debuff panel works", 1, 1, 1)
        GameTooltip:AddLine("These are the boss mechanic debuffs the game calls private auras, which are short by design, so no time filter is needed.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Regular debuffs cannot be limited to short ones, because the game hides their durations from addons in combat, which is why that row is off by default.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Show diagnostics prints what the game allows on your client. Your settings are saved in your own saved variables.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    about:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    pf:SetScript("OnShow", refresh)
    Debuffs:OnChange(refresh)
end

UI:RegisterPage("debuffs", "Debuffs", build)
