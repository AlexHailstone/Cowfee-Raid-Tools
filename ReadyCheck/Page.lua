local ADDON, CRT = ...

-- The Ready Check page, with three tabs:
--   Raid report     check the group's food, flask, rune, Vantus rune and raid buffs, and post them
--   On ready check  the automatic report and what counts
--   Window          the ready check window: when it opens and which columns it shows
--   Your bar        your own consumables bar (Consumables/Page.lua)

local Report = CRT.RaidReport
local UI = CRT.UI

local TABS = {
    { key = "report", label = "Raid report" },
    { key = "auto", label = "On ready check" },
    { key = "window", label = "Window" },
    { key = "bar", label = "Your bar" },
}
local OUTPUTS = { { key = "self", label = "Only me" }, { key = "raid", label = "Raid chat" }, { key = "officer", label = "Officer chat" } }
local FOODS = { { key = "any", label = "Any food buff" }, { key = "best", label = "Best food only" } }
local WARNS = { { key = 0, label = "Off" }, { key = 5, label = "5 min" }, { key = 10, label = "10 min" } }

local ROW_H = 46

local page
local tabButtons, tabFrames, built = {}, {}, {}
local resultTexts, controls = {}, {}
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

local function makeCheck(parent, x, y, text, field, sub)
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
    end)
    check.refresh = function()
        check:SetChecked(holder()[field] and true or false)
    end
    controls[#controls + 1] = check
    return check
end

-- A button that steps through a list of choices for one setting.
local function makeCycle(parent, x, y, width, prefix, field, choices)
    local b = makeButton(parent, prefix, width)
    b:SetPoint("TOPLEFT", x, y)
    b:SetScript("OnClick", function()
        local current = settings()[field]
        local index = 1
        for i, c in ipairs(choices) do
            if c.key == current then
                index = i % #choices + 1
            end
        end
        settings()[field] = choices[index].key
        refresh()
    end)
    b.refresh = function()
        local text = choices[1].label
        for _, c in ipairs(choices) do
            if c.key == settings()[field] then
                text = c.label
            end
        end
        b:SetText(prefix .. ": " .. text)
    end
    controls[#controls + 1] = b
    return b
end

-- Raid report tab -----------------------------------------------------------------------

local function buildReport(f)
    local hint = label(f, "Check shows the result only to you. Post to chat sends it to the channel chosen on the On ready check tab, or raid chat if that is Only me. Players whose buffs can't be read are listed as couldn't check, not as missing.", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -8)
    hint:SetWidth(670)

    for i, check in ipairs(Report.CHECKS) do
        local y = -60 - (i - 1) * ROW_H
        local name = label(f, check.label)
        name:SetPoint("TOPLEFT", 8, y - 4)
        name:SetWidth(130)

        local checkButton = makeButton(f, "Check", 80)
        checkButton:SetPoint("TOPLEFT", 140, y)
        checkButton:SetScript("OnClick", function()
            Report:Check({ check.key }, false)
        end)

        local post = makeButton(f, "Post to chat", 120)
        post:SetPoint("LEFT", checkButton, "RIGHT", 6, 0)
        post:SetScript("OnClick", function()
            Report:Check({ check.key }, true)
        end)

        local result = label(f, "Not checked yet.", "CRTFontSmall")
        result:SetPoint("TOPLEFT", post, "TOPRIGHT", 10, -2)
        result:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        result:SetJustifyV("TOP")
        result:SetHeight(ROW_H - 6)
        result:SetWordWrap(true)
        resultTexts[check.key] = result
    end

    local y = -60 - #Report.CHECKS * ROW_H - 8
    local all = makeButton(f, "Check everything", 200)
    all:SetPoint("TOPLEFT", 140, y)
    all:SetScript("OnClick", function()
        local keys = {}
        for _, check in ipairs(Report.CHECKS) do
            keys[#keys + 1] = check.key
        end
        Report:Check(keys, false)
    end)
    local postAll = makeButton(f, "Post the report to chat", 220)
    postAll:SetPoint("LEFT", all, "RIGHT", 6, 0)
    postAll:SetScript("OnClick", function()
        Report:Check(Report:Included(), true)
    end)
    local postHint = label(f, "Posts the checks ticked under Include in the report.", "CRTFontDisableSmall")
    postHint:SetPoint("TOPLEFT", all, "BOTTOMLEFT", 0, -6)

    local listNote = label(f, "", "CRTFontDisableSmall")
    listNote:SetPoint("TOPLEFT", 8, y - 70)
    listNote:SetWidth(670)
    listNote.refresh = function()
        local empty = {}
        for _, key in ipairs({ "food", "flask", "rune" }) do
            if not next(CRT.Consumables:BuffIds(key)) then
                empty[#empty + 1] = key
            end
        end
        if #empty > 0 then
            listNote:SetText("The built-in list has no buffs yet for: " .. table.concat(empty, ", ") .. ". Until it does, those checks look for the English buff names (Well Fed, Flask, Phial, Augment), so they only work on an English game client. Vantus runes always go by name.")
        else
            listNote:SetText("Vantus runes are found by their English buff name.")
        end
    end
    controls[#controls + 1] = listNote

    local commands = label(f, "/crt check food, flask, rune, vantus, buffs or all. Add chat to post it, such as /crt check food chat", "CRTFontDisableSmall")
    commands:SetPoint("BOTTOMLEFT", 8, 8)
end

-- On ready check tab ------------------------------------------------------------------------

local function buildAuto(f)
    makeCheck(f, 4, -8, "Report automatically on a ready check", "auto")
    makeCheck(f, 28, -36, "Also on a pull timer", "onPull")
    makeCheck(f, 28, -64, "Only in raids", "raidsOnly")
    makeCheck(f, 28, -92, "Not in Raid Finder", "notLFR")
    makeCycle(f, 32, -122, 240, "Post to", "output", OUTPUTS)
    local who = label(f, "The automatic report goes to chat only from whoever started the ready check or pull timer, so it is posted once. Everyone else sees it only in their own chat.", "CRTFontDisableSmall")
    who:SetPoint("TOPLEFT", 32, -152)
    who:SetWidth(640)

    local include = label(f, "Include in the report")
    include:SetPoint("TOPLEFT", 8, -196)
    for i, check in ipairs(Report.CHECKS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        makeCheck(f, 4 + col * 200, -218 - row * 28, check.label, check.key, "include")
    end

    local counts = label(f, "What counts")
    counts:SetPoint("TOPLEFT", 8, -290)
    makeCycle(f, 8, -312, 240, "Food", "food", FOODS)
    makeCycle(f, 8, -342, 240, "Flask expiring warning", "flaskWarn", WARNS)
    makeCheck(f, 4, -372, "Count a lower quality flask as a problem", "lowFlask")
    local note = label(f, "Best food only and lower quality flasks need those marked in the built-in consumables list. Until they are, all food counts and no flask is flagged.", "CRTFontDisableSmall")
    note:SetPoint("TOPLEFT", 8, -402)
    note:SetWidth(640)

    local notHere = label(f, "Not available: potions and healthstones used in the last fight (the combat log is closed to addons during boss fights in Midnight), and other players' weapon oils and armor kits (they aren't buffs, so the game doesn't show them to addons).", "CRTFontDisableSmall")
    notHere:SetPoint("TOPLEFT", 8, -450)
    notHere:SetWidth(640)
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
    local hint = label(f, "A table of every player's ready answer, consumables and raid buffs that opens on a ready check and closes after the time below or on a right-click. Drag it to move it, or use Toggle previews to place it with sample players.", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -8)
    hint:SetWidth(670)

    makeCheck(f, 4, -52, "Open the window on a ready check", "enabled", windowSettings)
    makeCheck(f, 28, -80, "Only when I'm the raid leader or an assistant", "leadOnly", windowSettings)
    makeCheck(f, 28, -108, "Only raid buff columns my group can give", "groupBuffsOnly", windowSettings)
    makeNumber(f, 32, -138, "Seconds open (5 to 120)", "seconds", 5, 120)
    makeNumber(f, 32, -166, "Size % (50 to 150)", "scale", 50, 150)

    local Window = CRT.ReadyCheckWindow
    local cols = label(f, "Columns: drag a heading left or right to move it, click it to show or hide it. Faded columns are hidden.")
    cols:SetPoint("TOPLEFT", 8, -200)
    cols:SetWidth(670)

    -- The same table the window draws, with sample players, in edit mode.
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 8, -226)
    Window.Dress(box)
    local editor
    editor = Window.NewTable(box, true, function()
        Window:DrawEditor(editor)
    end)
    box.refresh = function()
        Window:DrawEditor(editor)
    end
    controls[#controls + 1] = box

    local y = -226 - 150
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

    local key = label(f, "In the table: an icon means they have it, a gold number is minutes left on an expiring flask, x is missing, ? means the game hid their buffs. Durability only shows for players who run Cowfee Raid Tools, since each one sends their own.", "CRTFontDisableSmall")
    key:SetPoint("TOPLEFT", 8, y - 36)
    key:SetWidth(670)
end

-- Tabs ----------------------------------------------------------------------------------------

local function selectTab(key)
    if not tabFrames[key] then
        key = "report"
    end
    settings().tab = key
    if not built[key] then
        built[key] = true
        if key == "report" then
            buildReport(tabFrames[key])
        elseif key == "auto" then
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

local function ago(t)
    local seconds = time() - t
    if seconds < 60 then
        return "just now"
    end
    return math.floor(seconds / 60) .. " min ago"
end

refresh = function()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
    for key, fs in pairs(resultTexts) do
        local last = Report.last[key]
        if last then
            fs:SetText("|cff999999" .. ago(last.at) .. ":|r " .. table.concat(last.lines, "  "))
        end
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

-- Opens the page on a tab: "report", "auto" or "bar".
CRT.ReadyCheckPage = {
    Open = function(tab)
        settings().tab = tab
        UI:Show("readycheck")
        if page and page:IsShown() then
            selectTab(tab)
        end
    end,
}
