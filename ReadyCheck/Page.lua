local ADDON, CRT = ...

-- The Ready Check page. Checking the group is done in the ready check window (/crt check), where a
-- shift-click on a heading posts that column to chat. The page's tabs:
--   Window          the ready check window: when it opens and which columns it shows
--   Your bar        your own consumables bar (Consumables/Page.lua)
--   Settings        the automatic report (printed to you, or posted) and what counts
-- Like every page, its general settings are on a Settings tab, last.

local Report = CRT.RaidReport
local UI = CRT.UI

local TABS = {
    { key = "window", label = "Window" },
    { key = "bar", label = "Your bar" },
    { key = "auto", label = "Settings" },
}
local OUTPUTS = { { key = "self", label = "Only me" }, { key = "raid", label = "Raid chat" }, { key = "officer", label = "Officer chat" } }
local FOODS = { { key = "any", label = "Any food buff" }, { key = "best", label = "Best food only" } }
local WARNS = { { key = 0, label = "Off" }, { key = 5, label = "5 min" }, { key = 10, label = "10 min" } }

local ROW_H = 34

local page
local tabButtons, tabFrames, built = {}, {}, {}
local controls = {}
local refresh

local function settings()
    return CRT.db.readycheck
end

local function tooltip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
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

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "CRTFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

-- enabledIf, when given, returns whether the box can be used. When it returns false the box is
-- greyed out and can't be clicked, because the setting it depends on is off.
local function makeCheck(parent, x, y, text, field, sub, enabledIf)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    local fs = label(parent, text, "CRTFontSmall")
    fs:SetPoint("LEFT", check, "RIGHT", 2, 0)
    -- sub is a key of CRTDB.readycheck, or a function returning the table that holds field.
    local function holder()
        if type(sub) == "function" then
            return sub()
        end
        return sub and settings()[sub] or settings()
    end
    check:SetScript("OnClick", function(self)
        holder()[field] = self:GetChecked() and true or false
        CRT.ReadyCheckWindow:Apply()
        refresh()
    end)
    check.refresh = function()
        check:SetChecked(holder()[field] and true or false)
        if enabledIf then
            local on = enabledIf() and true or false
            check:SetEnabled(on)
            local c = on and 1 or 0.5
            fs:SetTextColor(c, c, c)
        end
    end
    controls[#controls + 1] = check
    return check
end

-- A button that steps through a list of choices for one setting.
-- holder optionally returns the table that holds field, by default CRTDB.readycheck.
local function makeCycle(parent, x, y, width, prefix, field, choices, holder)
    holder = holder or settings
    local b = makeButton(parent, prefix, width)
    b:SetPoint("TOPLEFT", x, y)
    b:SetScript("OnClick", function()
        local current = holder()[field]
        local index = 1
        for i, c in ipairs(choices) do
            if c.key == current then
                index = i % #choices + 1
            end
        end
        holder()[field] = choices[index].key
        CRT.ReadyCheckWindow:Apply()
        refresh()
    end)
    b.refresh = function()
        local text = choices[1].label
        for _, c in ipairs(choices) do
            if c.key == holder()[field] then
                text = c.label
            end
        end
        b:SetText(prefix .. ": " .. text)
    end
    controls[#controls + 1] = b
    return b
end

-- Settings tab (the automatic report) ------------------------------------------------------------

local function buildAuto(f)
    makeCheck(f, 4, -8, "Report automatically on a ready check", "auto")
    -- These three only matter for the automatic report.
    local function autoOn()
        return settings().auto
    end
    makeCheck(f, 28, -32, "Also on a pull timer", "onPull", nil, autoOn)
    makeCheck(f, 28, -56, "Only in raids", "raidsOnly", nil, autoOn)
    makeCheck(f, 28, -80, "Not in Raid Finder", "notLFR", nil, autoOn)
    local postTo = makeCycle(f, 32, -108, 240, "Post to", "output", OUTPUTS)
    UI.Help(f, "Who posts the report", "The automatic report goes to chat only from whoever started the ready check or pull timer, so it is posted once. Everyone else sees it only in their own chat.\n\nShift-clicked headings in the ready check window also post to this channel, or to raid chat when it is Only me."):SetPoint("LEFT", postTo, "RIGHT", 6, 0)

    local include = label(f, "Include in the report")
    include:SetPoint("TOPLEFT", 8, -144)
    for i, check in ipairs(Report.CHECKS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        makeCheck(f, 4 + col * 200, -166 - row * 24, check.label, check.key, "include")
    end

    local counts = label(f, "What counts")
    counts:SetPoint("TOPLEFT", 8, -224)
    UI.Help(f, "What counts", "Best food only and lower quality flasks need those marked in the built-in consumables list. Until they are, all food counts and no flask is flagged.\n\nNot available: potions and healthstones used in the last fight (the combat log is closed to addons during boss fights in Midnight), and other players' weapon oils and armor kits (they aren't buffs, so the game doesn't show them to addons)."):SetPoint("LEFT", counts, "RIGHT", 6, 0)
    makeCycle(f, 8, -246, 240, "Food", "food", FOODS)
    makeCycle(f, 8, -274, 240, "Flask expiring warning", "flaskWarn", WARNS)
    makeCheck(f, 4, -302, "Count a lower quality flask as a problem", "lowFlask")
end

-- Window tab -------------------------------------------------------------------------------------

local function windowSettings()
    return settings().window
end

local function makeNumber(parent, x, y, text, field, low, high)
    local fs = label(parent, text, "CRTFontSmall")
    fs:SetPoint("TOPLEFT", x, y - 4)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontHighlight)
    edit:SetNumeric(true)
    edit:SetMaxLetters(3)
    edit:SetSize(44, 20)
    edit:SetPoint("TOPLEFT", x + 190, y - 2)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value then
            windowSettings()[field] = math.max(low, math.min(high, math.floor(value)))
            CRT.ReadyCheckWindow:Apply()
        end
        self:SetText(tostring(windowSettings()[field]))
    end)
    edit.refresh = function()
        if not edit:HasFocus() then
            edit:SetText(tostring(windowSettings()[field]))
        end
    end
    controls[#controls + 1] = edit
end

local function buildWindow(f)
    makeCheck(f, 4, -16, "Open the window on a ready check", "enabled", windowSettings)
    -- Only the automatic opening checks who you are, so this depends on the box above.
    makeCheck(f, 28, -40, "Only when I'm the raid leader or an assistant", "leadOnly", windowSettings, function()
        return windowSettings().enabled
    end)
    makeCheck(f, 28, -64, "Only raid buff columns my group can give", "groupBuffsOnly", windowSettings)
    makeCycle(f, 400, -16, 260, "Sort players by", "sort", CRT.ReadyCheckWindow.SORTS, windowSettings)
    makeCheck(f, 396, -44, "Class color bar behind each row", "classBars", windowSettings)
    makeNumber(f, 32, -90, "Seconds open (5 to 120)", "seconds", 5, 120)
    makeNumber(f, 32, -114, "Size % (50 to 150)", "scale", 50, 150)

    local Window = CRT.ReadyCheckWindow
    local cols = label(f, "Columns: drag a heading to move it, click it to show or hide it.")
    cols:SetPoint("TOPLEFT", 8, -148)
    cols:SetWordWrap(false)
    UI.Help(f, "The ready check window", "A table of every player's ready answer, consumables and raid buffs. It opens on a ready check, or any time with /crt check, and closes after the time set here or on a right-click. Shift-click a heading in it to post who is missing that to raid chat. Drag it to move it, or use Previews to place it.\n\nIn the table: an icon means they have it, a gold number is minutes left on an expiring flask, x is missing, and ? means the game hid their buffs. Durability only shows for players who run Cowfee Raid Tools, since each one sends their own."):SetPoint("LEFT", cols, "RIGHT", 6, 0)

    -- The same table the window draws, with sample players, in edit mode.
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    Window.Dress(box)
    local editor
    -- Draws the copy, then scales it down if it is wider than the tab, so it never runs past the
    -- panel. Anchor offsets are in the box's own scale, so they are divided by it.
    local function drawCopy()
        Window:DrawEditor(editor)
        local available = (f:GetWidth() or 0) > 0 and f:GetWidth() - 16 or 670
        local scale = math.min(1, available / box:GetWidth())
        box:SetScale(scale)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", f, "TOPLEFT", 8 / scale, -170 / scale)
    end
    editor = Window.NewTable(box, true, drawCopy)
    box.refresh = drawCopy
    controls[#controls + 1] = box

    local y = -172 - 150
    local resetOrder = makeButton(f, "Default order", 150)
    resetOrder:SetPoint("TOPLEFT", 8, y)
    resetOrder:SetScript("OnClick", function()
        windowSettings().order = {}
        Window:Apply()
        refresh()
    end)
    local test = makeButton(f, "Show it now", 150)
    test:SetPoint("LEFT", resetOrder, "RIGHT", 8, 0)
    test:SetScript("OnClick", function()
        Window:Show(nil, true)
    end)
    tooltip(test, "Show it now", "Opens the window with these sample players, exactly as arranged here. Right-click it to close it.")
    local live = makeButton(f, "Show with my group", 180)
    live:SetPoint("LEFT", test, "RIGHT", 8, 0)
    live:SetScript("OnClick", function()
        Window:Show()
    end)
    tooltip(live, "Show with my group", "Opens the window with your current group, as a ready check would. Raid buff columns follow Only raid buff columns my group can give.")
    local reset = makeButton(f, "Reset position", 150)
    reset:SetPoint("LEFT", live, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        Window:ResetPosition()
    end)
end

-- Tabs ----------------------------------------------------------------------------------------

local function selectTab(key)
    if not tabFrames[key] then
        key = "window"
    end
    settings().tab = key
    if not built[key] then
        built[key] = true
        if key == "auto" then
            buildAuto(tabFrames[key])
        elseif key == "window" then
            buildWindow(tabFrames[key])
        else
            CRT.ConsumablesPage.Build(tabFrames[key])
        end
    end
    for _, tab in ipairs(TABS) do
        local on = tab.key == key
        tabFrames[tab.key]:SetShown(on)
        tabButtons[tab.key].sel:SetShown(on)
        tabButtons[tab.key].text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
    end
    refresh()
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
end

local function build(pf)
    page = pf
    local title = label(pf, "Ready Check", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)

    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, pf, "BackdropTemplate")
        b:SetSize(160, 26)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 164, -36)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(0, 0, 0, 0.4)
        b:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        b.sel = b:CreateTexture(nil, "ARTWORK")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        b.text = b:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(tab.label)
        b:SetScript("OnClick", function()
            selectTab(tab.key)
        end)
        tabButtons[tab.key] = b

        local f = CreateFrame("Frame", nil, pf)
        f:SetPoint("TOPLEFT", 0, -66)
        f:SetPoint("BOTTOMRIGHT", 0, 0)
        f:Hide()
        tabFrames[tab.key] = f
    end

    local line = pf:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.35, 0.35, 0.35, 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -62)
    line:SetPoint("TOPRIGHT", -8, -62)

    pf:SetScript("OnShow", function()
        selectTab(settings().tab)
    end)
    Report.onChange = refresh
end

UI:RegisterPage("readycheck", "Ready Check", build)

-- Opens the page on a tab: "auto", "window" or "bar".
CRT.ReadyCheckPage = {
    Open = function(tab)
        settings().tab = tab
        UI:Show("readycheck")
        if page and page:IsShown() then
            selectTab(tab)
        end
    end,
}
