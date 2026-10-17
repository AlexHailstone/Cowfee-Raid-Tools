local ADDON, CRT = ...

-- The Ready Check page. Checking the group is done in the ready check window (/crt check), where a
-- shift-click on a heading posts that column to chat. The page's tabs:
--   Window          the ready check window: when it opens and which columns it shows
--   Your bar        your own consumables bar (Consumables/Page.lua)
--   Settings        the automatic report (printed to you, or posted), what counts, and whether
--                   your bar shows
-- Like every page, its general settings are on a Settings tab, last.

local Report = CRT.RaidReport
local UI = CRT.UI

local TABS = {
    { key = "window", label = "Window" },
    { key = "bar", label = "Your bar" },
    { key = "auto", label = "Settings" },
}
local OUTPUTS = { { key = "self", label = "Only me" }, { key = "raid", label = "Raid chat" }, { key = "officer", label = "Officer chat" } }
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

-- A dropdown for one setting, in the Edit Mode style (UI/Controls.lua).
-- holder optionally returns the table that holds field, by default CRTDB.readycheck.
local function makeDropdown(parent, x, y, text, field, choices, holder, labelWidth, width, enabledIf)
    holder = holder or settings
    local row = UI.Dropdown(parent, text, {
        options = choices,
        labelWidth = labelWidth,
        width = width,
        enabledIf = enabledIf,
        get = function()
            return holder()[field]
        end,
        set = function(key)
            holder()[field] = key
            CRT.ReadyCheckWindow:Apply()
            refresh()
        end,
    })
    row:SetPoint("TOPLEFT", x, y)
    controls[#controls + 1] = row
    return row
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
    local postTo = makeDropdown(f, 32, -100, "Post to", "output", OUTPUTS, nil, 70, 170)
    UI.Help(f, "Who posts the report", "The automatic report goes to chat only from whoever started the ready check or pull timer, so it is posted once. Everyone else sees it only in their own chat.\n\nShift-clicked headings in the ready check window also post to this channel, or to raid chat when it is Only me."):SetPoint("LEFT", postTo, "RIGHT", 6, 0)

    local include = label(f, "Include in the report")
    include:SetPoint("TOPLEFT", 8, -144)
    for i, check in ipairs(Report.CHECKS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        makeCheck(f, 4 + col * 200, -166 - row * 24, check.label, check.key, "include")
    end

    local counts = label(f, "What counts")
    counts:SetPoint("TOPLEFT", 8, -224)
    UI.Help(f, "What counts", "Food: any food buff counts, whatever was eaten.\n\nLower quality flasks need those marked in the built-in consumables list. Until they are, no flask is flagged.\n\nNot available: potions and healthstones used in the last fight (the combat log is closed to addons during boss fights in Midnight), and other players' weapon oils and armor kits (they aren't buffs, so the game doesn't show them to addons)."):SetPoint("LEFT", counts, "RIGHT", 6, 0)
    makeDropdown(f, 8, -240, "Flask and oil expiring warning", "flaskWarn", WARNS, nil, 200, 170)
    makeCheck(f, 4, -274, "Count a lower quality flask as a problem", "lowFlask")
    local lock = makeCheck(f, 4, -304, "Lock my Ready button until everyone has my raid buff", "buffLock")
    local fade = makeCheck(f, 4, -334, "Fade out my bar and the ready check window on a pull timer", "fadeOnPull")
    UI.Help(f, "Fade on a pull timer", "When anyone starts a pull timer, your bar and the ready check window fade out over 2 seconds, so they're gone before the pull. They come back on the next ready check, and Previews keeps them up."):SetPoint("LEFT", fade, "RIGHT", 330, 0)
    -- Early Pull Checker, its own section in the right column under Your bar (below the include
    -- checkboxes, which run under both columns).
    local earlyTitle = label(f, "Early Pull Checker")
    earlyTitle:SetPoint("TOPLEFT", 404, -230)
    UI.Help(f, "Early Pull Checker", "While a pull timer counts down, the addon watches which group members enter combat and who cast just before. If the fight starts more than half a second before the timer ends, it reports the first players in combat and the last casts before it.\n\nThe game hides which spell other players cast, so only their names and times are listed; your own casts show their spell.\n\nIf the game hides the timer's length in your raid, early and on time can't be told apart and nothing is reported."):SetPoint("LEFT", earlyTitle, "RIGHT", 6, 0)
    makeCheck(f, 400, -250, "Report who starts the fight before the pull timer ends", "earlyPull")
    makeDropdown(f, 428, -276, "Post to", "earlyPullOutput", OUTPUTS, nil, 70, 170, function()
        return settings().earlyPull
    end)
    UI.Help(f, "Ready button lock", "When a ready check starts and someone in the group is missing your class's raid buff (Arcane Intellect, Fortitude, Battle Shout, Mark of the Wild, Skyfury or Blessing of the Bronze), your Ready button is greyed out until they have it. Hover it to see who.\n\nHold Shift and click Ready to ready anyway, and it unlocks by itself after 10 seconds, in case you can't buff.\n\nOnly players the game lets the addon read count. Anyone offline, out of sight, or whose buffs the game hides never locks you."):SetPoint("LEFT", lock, "RIGHT", 330, 0)

    -- Your bar, top right. The bar itself is arranged on the Your bar tab.
    local Consumables = CRT.Consumables
    local function bar()
        return CRT.db.consumables
    end
    local barTitle = label(f, "Your bar")
    barTitle:SetPoint("TOPLEFT", 404, -12)
    UI.Help(f, "Your bar", "Your own row of consumable icons on a ready check. Arrange it on the Your bar tab.\n\nNot when I start it: a raid leader who starts the check usually has no need to see it."):SetPoint("LEFT", barTitle, "RIGHT", 6, 0)
    makeCheck(f, 400, -32, "Show my bar on a ready check", "enabled", bar)
    makeCheck(f, 424, -56, "Not when I start the ready check", "notStarter", bar, function()
        return bar().enabled
    end)

    local warn = label(f, "Warn under", "CRTFontSmall")
    warn:SetPoint("TOPLEFT", 404, -88)
    local lowEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    lowEdit:SetAutoFocus(false)
    lowEdit:SetFontObject(CRTFontHighlight)
    lowEdit:SetNumeric(true)
    lowEdit:SetMaxLetters(3)
    lowEdit:SetSize(40, 20)
    lowEdit:SetPoint("LEFT", warn, "RIGHT", 10, 0)
    lowEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    lowEdit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(Consumables:LowMinutes()))
        self:ClearFocus()
    end)
    lowEdit:SetScript("OnEditFocusLost", function(self)
        Consumables:SetLowMinutes(self:GetText())
        self:SetText(tostring(Consumables:LowMinutes()))
    end)
    lowEdit.refresh = function()
        if not lowEdit:HasFocus() then
            lowEdit:SetText(tostring(Consumables:LowMinutes()))
        end
    end
    controls[#controls + 1] = lowEdit
    local minutes = label(f, "minutes left", "CRTFontSmall")
    minutes:SetPoint("LEFT", lowEdit, "RIGHT", 6, 0)
    UI.Help(f, "Warn under", "An icon gets gold marching ants when its buff or weapon oil has less time left than this, 1 to 240 minutes."):SetPoint("LEFT", minutes, "RIGHT", 6, 0)

    -- Work in progress: shown but greyed out until the cauldron flasks' and an unlimited rune's
    -- item IDs are in the built-in list (Consumables/Database.lua).
    local function wip()
        return false
    end
    local cauldron = makeCheck(f, 400, -112, "Flasks from a cauldron only (WIP)", "cauldronOnly", bar, wip)
    UI.Help(f, "Coming soon", "Flasks from a cauldron only: clicking the flask icon would use only the Fleeting flasks a raid cauldron hands out, so your own flasks are saved.\n\nUnlimited rune only: clicking the rune icon would use only an augment rune that is not used up.\n\nBoth wait for the item IDs to be added to the built-in list."):SetPoint("LEFT", cauldron, "RIGHT", 210, 0)
    makeCheck(f, 400, -136, "Unlimited augment rune only (WIP)", "unlimitedRune", bar, wip)
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
    makeDropdown(f, 400, -8, "Sort players by", "sort", CRT.ReadyCheckWindow.SORTS, windowSettings, 100, 150)
    makeCheck(f, 396, -44, "Class color bar behind each row", "classBars", windowSettings)
    makeNumber(f, 32, -90, "Seconds open (5 to 120)", "seconds", 5, 120)
    makeNumber(f, 32, -114, "Size % (50 to 150)", "scale", 50, 150)

    local Window = CRT.ReadyCheckWindow
    local cols = label(f, "Columns: drag a heading to move it, click it to show or hide it.")
    cols:SetPoint("TOPLEFT", 8, -148)
    cols:SetWordWrap(false)
    UI.Help(f, "The ready check window", "A table of every player's ready answer, consumables and raid buffs. It opens on a ready check, or any time with /crt check, and closes after the time set here or on a right-click. Shift-click a heading in it to post who is missing that to raid chat. Drag it to move it, or use Previews to place it.\n\nIn the table: an icon means they have it, a gold number is minutes left on an expiring flask, x is missing, and ? means the game hid their buffs. Durability and weapon oils only show for players who run Cowfee Raid Tools, since each one sends their own. The game never shows addons another player's weapon oil."):SetPoint("LEFT", cols, "RIGHT", 6, 0)

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
        UI:SetTabSelected(tabButtons[tab.key], on)
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
        UI:RegisterTab(b)

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
