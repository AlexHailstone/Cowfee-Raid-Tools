local ADDON, CRT = ...

-- DEVELOPER ONLY. The Development page (/crt dev): every developer tool in one place, so none of them
-- needs a slash command to find. It is in the menu only after /crt dev, until the main window closes,
-- and only in a developer build, since this file never ships: its .toc line is inside the
-- do-not-package block.
--   Layout editor     open it, and Move pieces (off by default, so the panel works as usual)
--   Windows           reset every movable window and the main panel
--   Diagnostics       the debuff panel's diagnostics
--   Timeline probe    arm it for the next raid boss pull, show what it found
--   Marker displays   the marker display editor
--   Reference types   set each ability's types on a reference timeline
--   Layers            every window's layer on its own (General Settings shows groups)
--   Window log        prints every move of the main window, to find what makes it jump
--   Season packs      which seasons load, and purging one

local UI = CRT.UI

local page
local controls = {}

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function heading(pf, x, y, text, help)
    local fs = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    if help then
        UI.Help(pf, text, help):SetPoint("LEFT", fs, "RIGHT", 6, 0)
    end
    return fs
end

local function action(pf, x, y, text, width, fn)
    local b = button(pf, text, width)
    b:SetPoint("TOPLEFT", x, y)
    b:SetScript("OnClick", fn)
    return b
end

local function refresh()
    if not page or not page:IsShown() then
        return
    end
    for _, c in ipairs(controls) do
        c.refresh()
    end
end

local function build(pf)
    page = pf
    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Development")
    UI.Help(pf, "Development", "Developer tools. This page is only in a developer build of the addon (from Git); release zips leave it out, along with every tool on it.\n\nThe same tools have slash commands: /crt dev (this page), /crt dev edit, /crt dev reset, /crt dev clear, /crt dev debuffs, /crt dev probe, /crt dev probe show, /crt dev markers, /crt dev types, /crt dev winlog and /crt dev seasons."):SetPoint("LEFT", title, "RIGHT", 6, 0)

    local x, right = 8, 352

    -- Layout editor.
    heading(pf, x, -44, "Layout editor", "Change where the pieces of a page sit, without changing the code: pick a piece, move it with the mouse or arrows, size it with the wheel. Changes are saved and applied after each /reload, and Export lists them so they can be written into the code.\n\nMove pieces is off by default, so with the editor open the panel still works as usual. Tick it to pick and move things.")
    local open = action(pf, x, -64, "Open the layout editor", 180, function()
        CRT.Dev:Toggle()
        refresh()
    end)
    open.refresh = function()
        open:SetText(CRT.Dev:IsOn() and "Close the layout editor" or "Open the layout editor")
    end
    controls[#controls + 1] = open
    local move = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    move:SetSize(24, 24)
    move:SetPoint("LEFT", open, "RIGHT", 10, 0)
    local moveText = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    moveText:SetPoint("LEFT", move, "RIGHT", 2, 0)
    moveText:SetText("Move pieces")
    move:SetScript("OnClick", function(self)
        CRT.Dev:SetMoving(self:GetChecked() and true or false)
    end)
    move.refresh = function()
        move:SetChecked(CRT.Dev:IsMoving())
    end
    controls[#controls + 1] = move
    action(pf, x, -92, "Clear all layout changes", 180, function()
        CRT.Dev:ClearAll()
    end)

    -- Windows.
    heading(pf, x, -132, "Windows", "Puts every movable window (your bar, the debuff panel, your next spell, the note windows, the low-health banner, the ready check window, marker displays, the pace window and the Timeline window) and the main panel back where they start.")
    action(pf, x, -152, "Reset all positions", 180, function()
        CRT.Dev:ResetAllPositions()
    end)

    -- Diagnostics.
    heading(pf, x, -192, "Diagnostics", "Prints to chat what the game allows the debuff panel to do on this client: which of its setup calls worked.")
    action(pf, x, -212, "Debuff panel diagnostics", 180, function()
        CRT.DebuffPanel:ShowInfo()
    end)

    -- Reference types.
    heading(pf, x, -252, "Reference types", "Set each ability's types on a boss's reference timeline with dropdowns: a Main type that colors the row, and any others as dots. Save as my copy shows the colors on the Timeline; Export gives the text to paste to Claude, who ships it in the boss's file.")
    action(pf, x, -272, "Open reference types", 180, function()
        CRT.ReferenceTypes:Toggle()
    end)

    -- Every window's layer on its own (General Settings shows them in groups).
    heading(pf, x, -312, "Layers, each window", "The layer of every window on its own. General Settings shows them in groups (Main window, Note windows, Timeline window, Alerts, Raid windows); a group whose windows differ shows Mixed there.")
    for i, layer in ipairs(UI.LAYERS) do
        local col = (i - 1) % 2
        local rowN = math.floor((i - 1) / 2)
        local dd = UI.Dropdown(pf, layer.label, {
            options = UI:LayerChoices(layer.key),
            labelWidth = 150,
            width = 150,
            get = function()
                return UI:Layer(layer.key)
            end,
            set = function(key)
                UI:SetLayer(layer.key, key)
                refresh()
            end,
        })
        dd:SetPoint("TOPLEFT", x + col * 344, -332 - rowN * 30)
        controls[#controls + 1] = dd
    end

    -- Window log.
    heading(pf, right, -264, "Window log", "Prints to chat every time something moves, sizes or rescales the main window: its anchor, its place on screen and the line of code that did it, and where it is one frame into a drag. For finding what makes the window jump. Click again to turn it off.")
    action(pf, right, -284, "Window log on or off", 160, function()
        CRT.WindowLog:Toggle()
    end)

    -- Timeline probe.
    heading(pf, right, -44, "Timeline probe", "For the next raid boss pull, logs whether each boss timeline, cast, damage meter, death recap and Journal value, and each phase event, was secret, readable or missing: when it fired, at the end of the encounter and after combat. Show prints what it found.")
    action(pf, right, -64, "Arm for the next pull", 160, function()
        if CRT.TimelineProbe then
            CRT.TimelineProbe:Arm()
        end
    end)
    action(pf, right, -92, "Show what it found", 160, function()
        if CRT.TimelineProbe then
            CRT.TimelineProbe:Show()
        end
    end)

    -- Marker displays.
    heading(pf, right, -132, "Marker displays", "Make a boss's marker display: slots, layout, icon size and when it clears. Save it as a draft to try in a real pull, Test it in /say, and Export it to ship in the boss's file.")
    action(pf, right, -152, "Open the marker editor", 160, function()
        CRT.MarkerEditor:Toggle()
    end)

    -- Season packs.
    heading(pf, right, -192, "Season packs", "Which season packs load (the current season only, or all), and purging one season's saved boss data: Timeline pulls, reminders, phase triggers, pace plans and switches, and marker display settings. Tattlebot's history, the Late Tracker and raid notes are always kept.")
    action(pf, right, -212, "Open season packs", 160, function()
        CRT.SeasonTools:Toggle()
    end)
    local loads = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    loads:SetPoint("TOPLEFT", right, -240)
    loads.refresh = function()
        local current = CRT.Bosses and CRT.Bosses:Current()
        loads:SetText(string.format("Loading: %s. Current season: %s.", CRT.Bosses and CRT.Bosses:LoadMode() == "all" and "all seasons" or "the current season only", current and current.name or "none"))
    end
    controls[#controls + 1] = loads

    pf:SetScript("OnShow", refresh)
end

UI:RegisterPage("dev", "Development", build)
-- Only /crt dev shows it, until the main window closes.
UI:SetPageHidden("dev", true, true)
