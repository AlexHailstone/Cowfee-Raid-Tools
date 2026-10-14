local ADDON, CRT = ...

-- The Debuffs page: settings for the in-combat debuff panel. The panel is moved with
-- "Toggle previews" in the corner of the main window.

local Debuffs = CRT.Debuffs
local UI = CRT.UI

local page, enabledCheck, sizeEdit, countEdit, reverseCheck
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

local function numberBox(pf, label, anchorTo, yOffset, getter, setter, maxLetters)
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
    return edit
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    enabledCheck:SetChecked(Debuffs:Enabled())
    reverseCheck:SetChecked(Debuffs:Reverse())
    if not sizeEdit:HasFocus() then
        sizeEdit:SetText(tostring(Debuffs:Size()))
    end
    if not countEdit:HasFocus() then
        countEdit:SetText(tostring(Debuffs:MaxCount()))
    end
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
    hint:SetText("A movable panel that shows your debuffs while you are in combat, shortest time left first. Press Toggle previews in the top right corner of this window to see it and drag it into place.")

    enabledCheck = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    enabledCheck:SetSize(26, 26)
    enabledCheck:SetPoint("TOPLEFT", 4, -82)
    local enabledLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    enabledLabel:SetPoint("LEFT", enabledCheck, "RIGHT", 2, 0)
    enabledLabel:SetText("Show the panel in combat")
    enabledCheck:SetScript("OnClick", function(self)
        Debuffs:SetEnabled(self:GetChecked())
    end)

    sizeEdit = numberBox(pf, "Icon size (24 to 96)", nil, -124, function()
        return Debuffs:Size()
    end, function(value)
        Debuffs:SetSize(value)
    end)
    countEdit = numberBox(pf, "How many to show (1 to 8)", nil, -158, function()
        return Debuffs:MaxCount()
    end, function(value)
        Debuffs:SetMaxCount(value)
    end, 1)

    reverseCheck = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    reverseCheck:SetSize(26, 26)
    reverseCheck:SetPoint("TOPLEFT", 4, -190)
    local reverseLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    reverseLabel:SetPoint("LEFT", reverseCheck, "RIGHT", 2, 0)
    reverseLabel:SetText("Reverse the order (try this if the longest debuffs show first)")
    reverseCheck:SetScript("OnClick", function(self)
        Debuffs:SetReverse(self:GetChecked())
    end)

    local reset = makeButton(pf, "Reset position", 160)
    reset:SetPoint("TOPLEFT", 8, -236)
    reset:SetScript("OnClick", function()
        CRT.DebuffPanel:ResetPosition()
    end)

    local info = makeButton(pf, "Show diagnostics", 160)
    info:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    info:SetScript("OnClick", function()
        CRT.DebuffPanel:ShowInfo()
    end)

    local note = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    note:SetPoint("TOPLEFT", 8, -290)
    note:SetWidth(660)
    note:SetJustifyH("LEFT")
    note:SetText("The game hides debuff durations from addons in combat, so the panel cannot filter to debuffs under 30 seconds itself. It shows the shortest-lasting ones first, up to the number you choose. Show diagnostics prints what the game allows on your client. Your settings are saved in your own saved variables.")

    pf:SetScript("OnShow", refresh)
    Debuffs:OnChange(refresh)
end

UI:RegisterPage("debuffs", "Debuffs", build)
