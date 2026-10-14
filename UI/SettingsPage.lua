local ADDON, CRT = ...

-- The Addon Settings page: settings for the whole addon, in CRTDB.ui (and CRTDB.window.scale for the
-- window scale). Only settings, so it has no tabs.
--   Window  the main window's scale, its style (the game's window art, or minimal black) and the
--           background's opacity (UI:ApplyStyle in UI/Panel.lua)
--   Text    the font, outline and text size of every text the addon draws with its shared fonts
--           (CRT:ApplyFonts in Core.lua). Each note window keeps its own font setting, and the game
--           draws boss debuff timers in its own font.
--   Layers  which frame strata each kind of window is drawn in, so one can sit above or below
--           another (UI:SetLayer in UI/Panel.lua)

local UI = CRT.UI

local LABEL_W = 170
local CONTROL_W = 200

local page
local controls = {}

local STYLES = {
    { key = "game", label = "Game window" },
    { key = "minimal", label = "Minimal black" },
}
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

local function heading(pf, y, text, help)
    local fs = pf:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    fs:SetPoint("TOPLEFT", 8, y)
    fs:SetText(text)
    if help then
        UI.Help(pf, text, help):SetPoint("LEFT", fs, "RIGHT", 6, 0)
    end
    return fs
end

local function add(row, y)
    row:SetPoint("TOPLEFT", 10, y)
    controls[#controls + 1] = row
    return row
end

local function refresh()
    if not page or not page:IsShown() then
        return
    end
    for _, control in ipairs(controls) do
        control.refresh()
    end
end

local function fontChoices()
    local out = { { key = "default", label = "Game default" } }
    for _, font in ipairs(CRT.FONTS) do
        out[#out + 1] = { key = font.name, label = font.name }
    end
    return out
end

local function build(pf)
    page = pf

    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Addon Settings")
    UI.Help(pf, "Addon Settings", "Settings for the whole addon: the main window, the text everywhere, and which windows are drawn above which. Every change applies straight away."):SetPoint("LEFT", title, "RIGHT", 6, 0)

    -- Window.
    heading(pf, -44, "Window", "Window Scale applies when you let go of the slider. Ctrl + mouse wheel over the window also changes it.\n\nMinimal black swaps the game's stone and marble window art for a flat black background. Background opacity fades the window's background and frame art, never the text or buttons.")
    local scale = add(UI.Slider(pf, "Window Scale: (50% to 200%)", {
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
    }), -62)
    local resetScale = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
    resetScale:SetNormalFontObject(GameFontNormalSmall)
    resetScale:SetHighlightFontObject(GameFontHighlightSmall)
    resetScale:SetSize(110, 20)
    resetScale:SetText("Reset to 100%")
    resetScale:SetPoint("LEFT", scale, "RIGHT", 12, 0)
    resetScale:SetScript("OnClick", function()
        UI:SetScale(100)
    end)
    add(UI.Dropdown(pf, "Style", {
        options = STYLES,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return ui().style
        end,
        set = function(key)
            ui().style = key
            UI:ApplyStyle()
            refresh()
        end,
    }), -94)
    add(UI.Slider(pf, "Background opacity", {
        min = 0,
        max = 100,
        step = 5,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        format = percent,
        get = function()
            return ui().bgAlpha
        end,
        set = function(v)
            ui().bgAlpha = v
            UI:ApplyStyle()
        end,
    }), -126)

    -- Text.
    heading(pf, -170, "Text", "The font, outline and size of the text in this window and in the addon's own on-screen displays, such as your next spell alert and the ready check bar and window.\n\nEach note window keeps its own font, set on Raid Notes. Boss debuff timers are drawn by the game in its own font, which no addon can change.\n\nGame default keeps the game's font, which also suits clients in other languages.")
    add(UI.Dropdown(pf, "Font", {
        options = fontChoices,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        get = function()
            return ui().font
        end,
        set = function(key)
            ui().font = key
            CRT:ApplyFonts()
            refresh()
        end,
    }), -188)
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
    }), -220)
    add(UI.Slider(pf, "Text size", {
        min = 80,
        max = 150,
        step = 5,
        labelWidth = LABEL_W,
        width = CONTROL_W,
        format = percent,
        onRelease = true,
        get = function()
            return ui().textSize
        end,
        set = function(v)
            ui().textSize = v
            CRT:ApplyFonts()
        end,
    }), -252)

    -- Layers.
    heading(pf, -296, "Layers", "Which layer each window is drawn in, from Background (under everything) to Tooltip (over everything). A window in a higher layer always covers one in a lower layer, including the game's own windows in those layers.\n\nThe game's windows are mostly Medium and High, and dialogs are Dialog. The consumables bar can't change layer during combat, so a change to it waits until combat ends.")
    for i, layer in ipairs(UI.LAYERS) do
        add(UI.Dropdown(pf, layer.label, {
            options = UI.STRATA,
            labelWidth = LABEL_W,
            width = CONTROL_W,
            get = function()
                return UI:Layer(layer.key)
            end,
            set = function(key)
                UI:SetLayer(layer.key, key)
                refresh()
            end,
        }), -314 - (i - 1) * 30)
    end
    local resetLayers = CreateFrame("Button", nil, pf, "UIPanelButtonTemplate")
    resetLayers:SetNormalFontObject(GameFontNormalSmall)
    resetLayers:SetHighlightFontObject(GameFontHighlightSmall)
    resetLayers:SetSize(130, 20)
    resetLayers:SetText("Default layers")
    resetLayers:SetPoint("TOPLEFT", 10, -314 - #UI.LAYERS * 30 - 6)
    resetLayers:SetScript("OnClick", function()
        for _, layer in ipairs(UI.LAYERS) do
            UI:SetLayer(layer.key, layer.default)
        end
        refresh()
    end)

    pf:SetScript("OnShow", refresh)
    -- Ctrl + mouse wheel changes the scale too, so the slider follows it.
    UI.onScale = refresh
end

UI:RegisterPage("settings", "Addon Settings", build)
