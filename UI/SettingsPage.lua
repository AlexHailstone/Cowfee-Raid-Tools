local ADDON, CRT = ...

-- The General Settings page: settings for the whole addon, in two columns. Only settings, so it has no
-- tabs.
--   Left    Window (the main window's scale, style and background opacity, UI:ApplyStyle in
--           UI/Panel.lua), Text (the font, outline and size of every text the addon draws with its
--           shared fonts, CRT:ApplyFonts in Core.lua), Sound, Reports and the Minimap button
--   Right   Layers (which frame strata each kind of window is drawn in, UI:SetLayer in UI/Panel.lua)
--           and Profiles (Profiles.lua)
-- Named Addon Settings before 0.16.0. Its key is still "settings".

local UI = CRT.UI
local Profiles = CRT.Profiles

local LEFT_X, RIGHT_X = 10, 352
local LABEL_W = 120
local CONTROL_W = 160

local page
local controls = {}

local STYLES = {
    { key = "game", label = "Game window" },
    { key = "minimal", label = "Minimal black" },
}
-- Text size in points, for the body text: 8 to 22 pt.
local TEXT_SIZES = {}
for pt = 8, 22 do
    TEXT_SIZES[#TEXT_SIZES + 1] = { key = pt, label = pt .. " pt" }
end

local OUTLINES = {
    { key = "", label = "None" },
    { key = "OUTLINE", label = "Outline" },
    { key = "THICKOUTLINE", label = "Thick outline" },
}

local function ui()
    return CRT.db.ui
end

local function percent(v)
    return v .. "%"
end

local function heading(pf, x, y, text, help)
    local fs = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    fs:SetPoint("TOPLEFT", x - 2, y)
    fs:SetText(text)
    if help then
        UI.Help(pf, text, help):SetPoint("LEFT", fs, "RIGHT", 6, 0)
    end
    return fs
end

local function add(row, x, y)
    row:SetPoint("TOPLEFT", x, y)
    controls[#controls + 1] = row
    return row
end

local function button(pf, text, width)
    local b = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

local function checkbox(pf, x, y, text, get, set)
    local cb = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x - 4, y)
    local label = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetWidth(300)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    cb.refresh = function()
        cb:SetChecked(get() and true or false)
    end
    controls[#controls + 1] = cb
    return cb
end

local function refresh()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
end

-- Read each time the menu opens, so fonts other addons share through LibSharedMedia appear.
local function fontChoices()
    local out = { { key = "default", label = "Default" } }
    for _, font in ipairs(CRT:FontList()) do
        out[#out + 1] = { key = font.name, label = font.name }
    end
    return out
end

local function fontLabel(key)
    return key == "default" and "Default" or key
end

-- Asks in the game's own confirmation box, then runs accept.
local function confirm(text, arg, acceptText, accept)
    StaticPopup_ShowCustomGenericConfirmation({
        text = text,
        text_arg1 = arg,
        acceptText = acceptText,
        cancelText = CANCEL,
        showAlert = true,
        callback = accept,
    })
end

-- The font changes every text in the addon, so it asks first.
local function confirmFont(key)
    if key == ui().font then
        return
    end
    confirm("Changing this changes all other fonts in this addon, the note windows included.\n\nUse %s for everything?", fontLabel(key), "Change all fonts", function()
        CRT:SetAddonFont(key)
        refresh()
    end)
end

-- Profile export and import: one window with a text box, and a name box when importing. ----------

local textDialog

local function getTextDialog()
    if textDialog then
        return textDialog
    end
    local d = CreateFrame("Frame", "CowfeeRaidToolsProfileText", UIParent, "BasicFrameTemplateWithInset")
    d:SetSize(520, 340)
    d:SetPoint("CENTER")
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CowfeeRaidToolsProfileText")

    d.nameLabel = d:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    d.nameLabel:SetPoint("TOPLEFT", 16, -36)
    d.nameLabel:SetText("New profile name")
    d.name = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
    d.name:SetSize(200, 20)
    d.name:SetPoint("LEFT", d.nameLabel, "RIGHT", 12, 0)
    d.name:SetAutoFocus(false)
    d.name:SetFontObject(CRTFontEdit)

    d.scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsProfileTextScroll", d, "UIPanelScrollFrameTemplate")
    d.scroll:SetPoint("BOTTOMRIGHT", -34, 46)
    d.edit = CreateFrame("EditBox", nil, d.scroll)
    d.edit:SetMultiLine(true)
    d.edit:SetAutoFocus(false)
    d.edit:SetFontObject(CRTFontEdit)
    d.edit:SetWidth(460)
    d.edit:SetScript("OnEscapePressed", function()
        d:Hide()
    end)
    d.scroll:SetScrollChild(d.edit)

    d.ok = button(d, "Import", 110)
    d.ok:SetHeight(24)
    d.ok:SetPoint("BOTTOM", -60, 12)
    d.ok:SetScript("OnClick", function()
        local ok, message = Profiles:Import(d.edit:GetText(), d.name:GetText())
        if ok then
            CRT:Print("Imported the profile " .. strtrim(d.name:GetText()) .. ". Pick it under Use profile to switch to it.")
            d:Hide()
            refresh()
        else
            CRT:Print(message)
        end
    end)
    d.close = button(d, CLOSE, 110)
    d.close:SetHeight(24)
    d.close:SetScript("OnClick", function()
        d:Hide()
    end)
    d:Hide()
    textDialog = d
    return d
end

local function showExport()
    local text, err = Profiles:Export()
    if not text then
        CRT:Print(err)
        return
    end
    local d = getTextDialog()
    UI.SetFrameTitle(d, "Export profile: " .. Profiles:Current() .. " (copy the text below)")
    d.nameLabel:Hide()
    d.name:Hide()
    d.ok:Hide()
    d.close:SetPoint("BOTTOM", 0, 12)
    d.scroll:SetPoint("TOPLEFT", 14, -34)
    d.edit:SetText(text)
    d:Show()
    d.edit:SetFocus()
    d.edit:HighlightText()
end

local function showImport()
    local d = getTextDialog()
    UI.SetFrameTitle(d, "Import a profile (paste it below)")
    d.nameLabel:Show()
    d.name:Show()
    d.name:SetText("")
    d.ok:Show()
    d.close:SetPoint("BOTTOM", 60, 12)
    d.scroll:SetPoint("TOPLEFT", 14, -64)
    d.edit:SetText("")
    d:Show()
    d.name:SetFocus()
end

-- The columns. -----------------------------------------------------------------------------------

local function buildLeft(pf)
    local x = LEFT_X

    heading(pf, x, -44, "Window", "Modern look gives the whole addon coffee colors, flat dropdowns and buttons, the menu in grouped blocks, and Arial Narrow text when the font below is Default. Unticked, it uses the Classic look, with the Style choice below.\n\nWindow Scale applies when you let go of the slider. Ctrl + mouse wheel over the window also changes it.\n\nIn the Classic look, Minimal black swaps the game's stone and marble window art for a flat black background. Opacity fades the whole window, text and buttons included, down to 30%.")
    checkbox(pf, x, -62, "Modern look (unticked: Classic)", function()
        return ui().modern
    end, function(on)
        ui().modern = on
        CRT:ApplyFonts()
        UI:ApplyStyle()
        refresh()
    end)
    add(UI.Slider(pf, "Window scale", {
        min = UI.MIN_SCALE,
        max = UI.MAX_SCALE,
        step = 5,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        format = percent,
        onRelease = true,
        get = function()
            return UI:Scale()
        end,
        set = function(v)
            UI:SetScale(v)
        end,
    }), x, -90)
    local resetScale = button(pf, "Reset scale to 100%", 140)
    resetScale:SetPoint("TOPLEFT", x + LABEL_W + 5, -124)
    resetScale:SetScript("OnClick", function()
        UI:SetScale(100)
    end)
    add(UI.Dropdown(pf, "Style", {
        options = STYLES,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        enabledIf = function()
            return not ui().modern
        end,
        get = function()
            return ui().style
        end,
        set = function(key)
            ui().style = key
            UI:ApplyStyle()
            refresh()
        end,
    }), x, -148)
    add(UI.Slider(pf, "Opacity", {
        min = 30,
        max = 100,
        step = 5,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        format = percent,
        get = function()
            return math.max(30, ui().bgAlpha or 100)
        end,
        set = function(v)
            ui().bgAlpha = v
            UI:ApplyStyle()
        end,
    }), x, -180)

    heading(pf, x, -224, "Text", "The font, outline and size of every text the addon draws: this window, the note windows and their titles, your next spell alert, and the ready check bar and window.\n\nThe font list has the game's fonts, plus any font other addons share through LibSharedMedia, when one of them is installed. Default is the game's own font in the Classic look and Arial Narrow in the Modern look. The game's font also suits clients in other languages.\n\nChanging the font sets every note window to it too. You can still give a note window its own font on Raid Notes afterwards. Text size is the body text size in points, 8 to 22 pt (14 pt is the default); headings and small text grow or shrink with it. It doesn't change the note windows, which have their own size.\n\nBoss debuff timers are drawn by the game in its own font, which no addon can change, so the debuff preview keeps that font too.")
    add(UI.Dropdown(pf, "Font", {
        options = fontChoices,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return ui().font
        end,
        set = confirmFont,
    }), x, -242)
    local warning = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    warning:SetPoint("TOPLEFT", x + LABEL_W + 5, -272)
    warning:SetWidth(CONTROL_W + 40)
    warning:SetJustifyH("LEFT")
    warning:SetTextColor(1, 0.55, 0.1)
    warning:SetWordWrap(false)
    warning:SetText("Changes all addon fonts.")
    add(UI.Dropdown(pf, "Outline", {
        options = OUTLINES,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return ui().outline
        end,
        set = function(key)
            ui().outline = key
            CRT:ApplyFonts()
            refresh()
        end,
    }), x, -286)
    add(UI.Dropdown(pf, "Text size", {
        options = TEXT_SIZES,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return ui().fontSize
        end,
        set = function(pt)
            ui().fontSize = pt
            CRT:ApplyFonts()
            refresh()
        end,
    }), x, -318)

    heading(pf, x, -362, "Sound", "Every sound the addon plays goes through this game sound channel, so it follows that channel's volume and mute in the game's Sound settings.\n\nTwo sounds are played by the game instead and keep its own outputs: the low-health pulse (Combat Audio Alerts, with its own volume on Quality of Life) and text to speech for your next spell (its volume is on Raid Notes).")
    add(UI.Dropdown(pf, "Sound channel", {
        options = CRT.SOUND_CHANNELS,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return ui().soundChannel or "Master"
        end,
        set = function(key)
            ui().soundChannel = key
            refresh()
        end,
    }), x, -380)

    heading(pf, x, -424, "Reports", "Ticked, player names in the Late Tracker and Tattlebot show without their realm: on their pages, in chat posts and in Discord exports. Unticked, a realm only shows for players from another realm, as the game shows it.\n\nThe Raid Groups grid always keeps realms, since it needs them to tell players apart.")
    checkbox(pf, x, -442, "Leave realm names out of reports and Discord exports", function()
        return ui().hideRealms
    end, function(on)
        ui().hideRealms = on
    end)

    heading(pf, x, -484, "Minimap", "Left-click the minimap button to open or close this window, and right-click it for General Settings. Drag it to move it around the minimap.\n\nThe addon is also listed in the game's addon menu beside the minimap, which works with the button hidden.")
    checkbox(pf, x, -502, "Show the minimap button", function()
        return not CRT.db.minimap.hide
    end, function(on)
        CRT.MinimapButton:SetHidden(not on)
    end)
end

local function buildRight(pf)
    local x = RIGHT_X

    heading(pf, x, -44, "Layers", "Which layer each window is drawn in, from Background (under everything) to Tooltip (over everything). A window in a higher layer always covers one in a lower layer, including the game's own windows in those layers.\n\nThe game's windows are mostly Medium and High, and dialogs are Dialog. The consumables bar can't change layer during combat, so a change to it waits until combat ends.")
    for i, layer in ipairs(UI.LAYERS) do
        add(UI.Dropdown(pf, layer.label, {
            options = UI.STRATA,
            labelWidth = LABEL_W + 30,
            width = CONTROL_W - 10,
            get = function()
                return UI:Layer(layer.key)
            end,
            set = function(key)
                UI:SetLayer(layer.key, key)
                refresh()
            end,
        }), x, -62 - (i - 1) * 30)
    end
    local lastLayer = -62 - #UI.LAYERS * 30
    local resetLayers = button(pf, "Default layers", 130)
    resetLayers:SetPoint("TOPLEFT", x, lastLayer - 4)
    resetLayers:SetScript("OnClick", function()
        for _, layer in ipairs(UI.LAYERS) do
            UI:SetLayer(layer.key, layer.default)
        end
        refresh()
    end)

    local top = lastLayer - 44
    heading(pf, x, top, "Profiles", "A profile holds everything the addon saves: every setting and window position, plus your raid layouts, notes, consumables lists, and the Late Tracker and Tattlebot history.\n\nEach character remembers its own profile. New characters start on the profile picked under New characters.\n\nSwitching, copying or resetting a profile reloads your interface, like /reload.\n\nExport gives the profile as text to share or keep. Import saves pasted text as a new profile.")

    local current = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    current:SetPoint("TOPLEFT", x, top - 22)
    current.refresh = function()
        current:SetText("Current profile: |cffffd100" .. Profiles:Current() .. "|r")
    end
    controls[#controls + 1] = current

    add(UI.Dropdown(pf, "Use profile", {
        options = function()
            return Profiles:All()
        end,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return Profiles:Current()
        end,
        set = function(name)
            if name == Profiles:Current() then
                return
            end
            confirm("Switch this character to the profile %s?\n\nYour interface reloads.", name, "Switch and reload", function()
                Profiles:Switch(name)
            end)
        end,
    }), x, top - 36)

    local newLabel = pf:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    newLabel:SetPoint("TOPLEFT", x, top - 78)
    newLabel:SetWidth(LABEL_W)
    newLabel:SetJustifyH("LEFT")
    newLabel:SetText("New profile")
    local newName = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    newName:SetSize(CONTROL_W - 64, 20)
    newName:SetPoint("LEFT", newLabel, "RIGHT", 10, 0)
    newName:SetAutoFocus(false)
    newName:SetFontObject(CRTFontEdit)
    newName:SetMaxLetters(32)
    local create = button(pf, "Create", 60)
    create:SetPoint("LEFT", newName, "RIGHT", 4, 0)
    local function createProfile()
        local name = strtrim(newName:GetText() or "")
        if name == "" then
            CRT:Print("Type a name for the new profile first.")
            return
        end
        if Profiles:Exists(name) then
            CRT:Print("A profile named " .. name .. " already exists.")
            return
        end
        newName:ClearFocus()
        confirm("Create the profile %s, starting from the defaults, and switch this character to it?\n\nYour interface reloads.", name, "Create and reload", function()
            Profiles:Switch(name)
        end)
    end
    create:SetScript("OnClick", createProfile)
    newName:SetScript("OnEnterPressed", createProfile)
    newName:SetScript("OnEscapePressed", newName.ClearFocus)

    local hasOthers = function()
        return #Profiles:Others() > 0
    end
    add(UI.Dropdown(pf, "Copy from", {
        options = function()
            return Profiles:Others()
        end,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        enabledIf = hasOthers,
        get = function()
            return nil
        end,
        set = function(name)
            confirm("Replace everything in this profile with a copy of %s?\n\nYour interface reloads.", name, "Copy and reload", function()
                Profiles:CopyFrom(name)
            end)
        end,
    }), x, top - 100).Dropdown:SetDefaultText("Pick a profile")
    add(UI.Dropdown(pf, "Delete profile", {
        options = function()
            return Profiles:Others()
        end,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        enabledIf = hasOthers,
        get = function()
            return nil
        end,
        set = function(name)
            confirm("Delete the profile %s? This can't be undone.", name, DELETE, function()
                Profiles:Delete(name)
                refresh()
            end)
        end,
    }), x, top - 132).Dropdown:SetDefaultText("Pick a profile")
    add(UI.Dropdown(pf, "New characters", {
        options = function()
            return Profiles:All()
        end,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return Profiles:Default()
        end,
        set = function(name)
            Profiles:SetDefault(name)
            refresh()
        end,
    }), x, top - 164)

    local reset = button(pf, "Reset profile", 100)
    reset:SetPoint("TOPLEFT", x, top - 204)
    reset:SetScript("OnClick", function()
        confirm("Put everything in the profile %s back to the defaults, its layouts, notes and history included? This can't be undone.\n\nYour interface reloads.", Profiles:Current(), "Reset and reload", function()
            Profiles:Reset()
        end)
    end)
    local export = button(pf, "Export", 100)
    export:SetPoint("LEFT", reset, "RIGHT", 6, 0)
    export:SetScript("OnClick", showExport)
    local import = button(pf, "Import", 100)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    import:SetScript("OnClick", showImport)
end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("General Settings")
    UI.Help(pf, "General Settings", "Settings for the whole addon: the main window, the text everywhere, sound, the minimap button, which windows are drawn above which, and profiles. Every change applies straight away, except profile changes, which reload your interface."):SetPoint("LEFT", title, "RIGHT", 6, 0)

    buildLeft(pf)
    buildRight(pf)

    pf:SetScript("OnShow", refresh)
    -- Ctrl + mouse wheel changes the scale too, so the slider follows it.
    UI.onScale = refresh
end

UI:RegisterPage("settings", "General Settings", build)
