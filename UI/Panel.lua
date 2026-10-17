local ADDON, CRT = ...

local UI = { pages = {}, order = {} }
CRT.UI = UI

local FRAME_W, FRAME_H = 860, 762
local MENU_W = 150

-- Pages register themselves; the panel builds each one lazily the first time it is shown.
function UI:RegisterPage(key, title, builder)
    self.pages[key] = { key = key, title = title, builder = builder }
    self.order[#self.order + 1] = key
end

-- A hidden page has no menu button and can't be opened, such as the Development page until /crt dev.
-- closeHides hides it again whenever the main window closes.
function UI:SetPageHidden(key, hidden, closeHides)
    local page = self.pages[key]
    if not page then
        return
    end
    page.hidden = hidden and true or false
    if closeHides ~= nil then
        page.closeHides = closeHides and true or false
    end
    if self.frame then
        self:LayoutMenu()
    end
end

-- Previews: the panels that appear on their own, such as the ready check bar and the debuff panel,
-- register here. "Previews" in the corner of the main panel shows them all so they can be
-- dragged into place, and hides them again. setFn(on) shows or hides one panel's preview.
UI.previews = {}
UI.previewing = false

function UI:RegisterPreview(key, setFn)
    self.previews[key] = setFn
end

function UI:SetPreviews(on)
    on = on and true or false
    if on and InCombatLockdown() then
        CRT:Print("Previews can't be turned on during combat.")
        return
    end
    self.previewing = on
    for key, setFn in pairs(self.previews) do
        local ok, err = pcall(setFn, on)
        if not ok then
            CRT:Print("Preview '" .. key .. "' failed: " .. tostring(err))
        end
    end
    if self.previewButton then
        self.previewButton:SetText(on and "Previews: ON" or "Previews")
    end
end

function UI:TogglePreviews()
    self:SetPreviews(not self.previewing)
end

-- The panel's size as a percent, 50 to 200. SetScale scales everything in it, text included.
UI.MIN_SCALE, UI.MAX_SCALE = 50, 200

function UI:Scale()
    return math.max(self.MIN_SCALE, math.min(self.MAX_SCALE, math.floor((CRT.db.window.scale or 100) + 0.5)))
end

-- Sets the panel's size. onScale, when set, is told so a page can show the new value.
function UI:SetScale(percent)
    CRT.db.window.scale = math.max(self.MIN_SCALE, math.min(self.MAX_SCALE, math.floor(percent + 0.5)))
    if self.frame then
        self.frame:SetScale(self:Scale() / 100)
    end
    if self.onScale then
        self.onScale()
    end
end

-- Layers -----------------------------------------------------------------------------------------
-- Each kind of window registers its frames with RegisterLayer, which draws them in the frame strata
-- chosen on the General Settings page, or in the window's default. The choice is saved per kind in
-- CRTDB.ui.layers, and only while it differs from the default.

UI.STRATA = {
    { key = "BACKGROUND", label = "Background" },
    { key = "LOW", label = "Low" },
    { key = "MEDIUM", label = "Medium" },
    { key = "HIGH", label = "High" },
    { key = "DIALOG", label = "Dialog" },
    { key = "FULLSCREEN", label = "Fullscreen" },
    { key = "FULLSCREEN_DIALOG", label = "Fullscreen dialog" },
    { key = "TOOLTIP", label = "Tooltip" },
}

UI.LAYERS = {
    { key = "panel", label = "Main window", default = "HIGH" },
    { key = "notes", label = "Note windows", default = "MEDIUM" },
    { key = "alert", label = "Your next spell", default = "HIGH" },
    { key = "alertbars", label = "Alert bars", default = "HIGH" },
    { key = "alerticons", label = "Alert icons", default = "HIGH" },
    { key = "alerttexts", label = "Alert texts", default = "HIGH" },
    { key = "alertcircles", label = "Alert circles", default = "HIGH" },
    { key = "readycheck", label = "Ready check window", default = "HIGH" },
    { key = "bar", label = "Your consumables bar", default = "HIGH" },
    { key = "debuffs", label = "Debuff panel", default = "HIGH" },
    { key = "lowhealth", label = "Low-health banner", default = "DIALOG" },
    -- At most Fullscreen: the alert editor and the game's dropdown lists sit above it, on Fullscreen
    -- dialog and Tooltip, so editing from the Timeline window always shows on top.
    { key = "timeline", label = "Timeline window", default = "HIGH", max = "FULLSCREEN" },
    -- The windows that open over the others: the dev tools, the text, import and roster windows.
    { key = "popups", label = "Pop-up windows", default = "FULLSCREEN_DIALOG" },
}

local layerDefaults, layerFrames = {}, {}
for _, layer in ipairs(UI.LAYERS) do
    layerDefaults[layer.key] = layer.default
    layerFrames[layer.key] = {}
end
local layersWaiting = false -- a change blocked by combat, applied when combat ends

local strataRank, layerMax = {}, {}
for i, s in ipairs(UI.STRATA) do
    strataRank[s.key] = i
end
for _, layer in ipairs(UI.LAYERS) do
    layerMax[layer.key] = layer.max
end

function UI:Layer(key)
    local saved = CRT.db and CRT.db.ui and CRT.db.ui.layers[key]
    local strata = saved or layerDefaults[key] or "MEDIUM"
    -- a layer with a highest allowed strata never goes above it, a choice saved before included
    local max = layerMax[key]
    if max and (strataRank[strata] or 0) > (strataRank[max] or 0) then
        strata = max
    end
    return strata
end

-- The strata a layer can be set to: every one, or up to its highest allowed.
function UI:LayerChoices(key)
    local max = layerMax[key]
    if not max then
        return self.STRATA
    end
    local out = {}
    for _, s in ipairs(self.STRATA) do
        if strataRank[s.key] <= strataRank[max] then
            out[#out + 1] = s
        end
    end
    return out
end

-- A protected frame (one holding secure buttons) can't change strata in combat, so that waits.
local function applyLayer(key)
    for _, frame in ipairs(layerFrames[key]) do
        if InCombatLockdown() and frame:IsProtected() then
            layersWaiting = true
        else
            frame:SetFrameStrata(UI:Layer(key))
        end
    end
end

function UI:RegisterLayer(key, frame)
    local list = layerFrames[key]
    list[#list + 1] = frame
    frame:SetFrameStrata(self:Layer(key))
    -- a pop-up comes in front of the other pop-ups when clicked
    if key == "popups" then
        frame:SetToplevel(true)
    end
end

function UI:SetLayer(key, strata)
    CRT.db.ui.layers[key] = (strata ~= layerDefaults[key]) and strata or nil
    applyLayer(key)
    if layersWaiting then
        CRT:Print("That window can't change layer during combat. It will change when combat ends.")
    end
end

-- The groups General Settings shows, each setting the layer of several windows at once. The
-- Development page (/crt dev) still lists every window on its own.
UI.LAYER_GROUPS = {
    { key = "panel", label = "Main window", layers = { "panel" } },
    { key = "notes", label = "Note windows", layers = { "notes" } },
    { key = "timeline", label = "Timeline window", layers = { "timeline" } },
    { key = "alerts", label = "Alerts", layers = { "alert", "alertbars", "alerticons", "alerttexts", "alertcircles", "lowhealth" } },
    { key = "raid", label = "Raid windows", layers = { "readycheck", "bar", "debuffs" } },
    { key = "popups", label = "Pop-up windows", layers = { "popups" } },
}

-- The layer every window of a group is in, or "mixed" when they differ.
function UI:GroupLayer(group)
    local common
    for _, key in ipairs(group.layers) do
        local strata = self:Layer(key)
        if common and strata ~= common then
            return "mixed"
        end
        common = strata
    end
    return common
end

-- The layers a group can be set to: up to the lowest highest-allowed layer of its windows.
function UI:GroupLayerChoices(group)
    local choices
    for _, key in ipairs(group.layers) do
        local list = self:LayerChoices(key)
        if not choices or #list < #choices then
            choices = list
        end
    end
    return choices or self.STRATA
end

function UI:SetGroupLayer(group, strata)
    for _, key in ipairs(group.layers) do
        self:SetLayer(key, strata)
    end
end

local layerEvents = CreateFrame("Frame")
layerEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
layerEvents:SetScript("OnEvent", function()
    if layersWaiting then
        layersWaiting = false
        for _, layer in ipairs(UI.LAYERS) do
            applyLayer(layer.key)
        end
    end
end)

-- Window style ------------------------------------------------------------------------------------
-- Two looks, picked with the "Modern look" checkbox on General Settings (CRTDB.ui.modern):
--   Classic  the menu as one list, and the style dropdown: "game" shows the window template's own
--            art, "minimal" hides it for a flat black background with a thin border
--   Modern   coffee colors (CRT.MOCHA in Core.lua): an espresso window with caramel lines under the
--            title and beside the menu, the menu in grouped blocks (UI.MENU_GROUPS) with the
--            selected page in mocha, mocha page tabs, flat dropdowns and buttons, and Arial Narrow
--            text unless another font is picked (CRT:ApplyFonts)
-- bgAlpha fades whichever background is showing, never the text or buttons.

local function mocha(key, alpha)
    local c = CRT.MOCHA[key]
    return c[1], c[2], c[3], alpha or 1
end

-- The Modern menu's blocks, top to bottom. A page not listed joins the last block.
UI.MENU_GROUPS = {
    { "settings", "qol" },
    { "groups", "readycheck" },
    { "notes", "timeline", "pace" },
    { "late", "tattle" },
}

function UI:IsModern()
    return CRT.db and CRT.db.ui and CRT.db.ui.modern and true or false
end

-- Backdrop frames outside the main window that follow the look: your bar, its drag and Close bars,
-- and the ready check window. Each keeps its Classic colours; in Modern its background turns espresso
-- (keeping its own opacity) and its outline caramel.
UI.themed = {}

function UI:ApplyThemed(f)
    local c = f.crtClassic
    if self:IsModern() then
        local bg, edge = CRT.MOCHA.espresso, CRT.MOCHA.caramel
        f:SetBackdropColor(bg[1], bg[2], bg[3], c.bg[4])
        f:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    else
        f:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], c.bg[4])
        f:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], 1)
    end
end

-- classic = { bg = { r, g, b, a }, border = { r, g, b } }, the frame's colours in the Classic look.
function UI:RegisterThemed(f, classic)
    f.crtClassic = classic
    self.themed[#self.themed + 1] = f
    self:ApplyThemed(f)
end

-- Floating windows: a window of its own made from BasicFrameTemplateWithInset, such as the alert
-- editor, its export box, the dev tools and the text and import dialogs. Classic shows the template's
-- own art, or with the Minimal black style a flat black background with a grey border like the main
-- window; Modern a flat espresso background with an edge border, a caramel line under the title and
-- the plain X.
-- Call StyleWindow right after CreateFrame, before adding anything, so only the template's own
-- textures count as its art. Its buttons and dropdowns are skinned now and each time it shows.
UI.windows = {}

function UI:ApplyWindow(f)
    local modern = self:IsModern()
    -- Classic with the Minimal black style is flat too, in black and grey like the main window
    local flat = modern or (CRT.db and CRT.db.ui and CRT.db.ui.style == "minimal")
    for _, texture in ipairs(f.crtArt) do
        texture:SetShown(not flat)
    end
    f.crtBg:SetShown(flat)
    f.crtTitle:SetShown(flat)
    if modern then
        f.crtBg:SetColorTexture(mocha("espresso", 0.96))
        f.crtTitle:SetColorTexture(mocha("espresso"))
    else
        f.crtBg:SetColorTexture(0, 0, 0, 0.92)
        f.crtTitle:SetColorTexture(0.12, 0.12, 0.12, 1)
    end
    for _, edge in ipairs(f.crtEdges) do
        edge:SetShown(flat)
        if modern then
            edge:SetColorTexture(mocha("edge"))
        else
            edge:SetColorTexture(0.3, 0.3, 0.3, 1)
        end
    end
    f.crtTitleLine:SetShown(modern)
    f.crtTitleLine:SetColorTexture(mocha("caramel"))
    -- the template's inset (its own frame on some clients) is part of the Classic art
    if type(f.Inset) == "table" and f.Inset.SetShown then
        f.Inset:SetShown(not flat)
    end
end

function UI:StyleWindow(f)
    if f.crtArt then
        return
    end
    f.crtArt = {}
    for _, region in ipairs({ f:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            f.crtArt[#f.crtArt + 1] = region
        end
    end
    f.crtBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.crtBg:SetAllPoints()
    -- the title strip, as on the main window
    f.crtTitle = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.crtTitle:SetPoint("TOPLEFT", 1, -1)
    f.crtTitle:SetPoint("TOPRIGHT", -1, -1)
    f.crtTitle:SetHeight(23)
    f.crtEdges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local edge = f:CreateTexture(nil, "BORDER")
        edge:SetPoint(side[1])
        edge:SetPoint(side[2])
        if side[3] then
            edge:SetHeight(1)
        else
            edge:SetWidth(1)
        end
        f.crtEdges[#f.crtEdges + 1] = edge
    end
    f.crtTitleLine = f:CreateTexture(nil, "BORDER")
    f.crtTitleLine:SetPoint("TOPLEFT", 1, -24)
    f.crtTitleLine:SetPoint("TOPRIGHT", -1, -24)
    f.crtTitleLine:SetHeight(1)
    self:SkinCloseButton(f.CloseButton)
    self.windows[#self.windows + 1] = f
    f:HookScript("OnShow", function()
        UI:SkinTree(f)
    end)
    self:ApplyWindow(f)
    self:SkinTree(f)
end

function UI:ApplyStyle()
    for _, themed in ipairs(self.themed) do
        self:ApplyThemed(themed)
    end
    for _, window in ipairs(self.windows) do
        self:ApplyWindow(window)
    end
    local f = self.frame
    if not f then
        return
    end
    local s = CRT.db.ui
    local modern = self:IsModern()
    local flat = modern or s.style == "minimal"
    -- Opacity (bgAlpha) fades the whole window, text and buttons too, never below 30%. The window's
    -- own art and colours stay solid underneath.
    f:SetAlpha(math.max(30, math.min(100, s.bgAlpha or 100)) / 100)
    local alpha = 1
    for _, texture in ipairs(f.art) do
        texture:SetShown(not flat)
        texture:SetAlpha(alpha)
    end
    for _, texture in ipairs(f.flat) do
        texture:SetShown(flat)
    end
    if modern then
        f.flatBg:SetColorTexture(mocha("espresso", 0.96 * alpha))
        f.flatTitle:SetColorTexture(mocha("espresso", alpha))
        for _, edge in ipairs(f.flatEdges) do
            edge:SetColorTexture(mocha("edge", alpha))
        end
    else
        f.flatBg:SetColorTexture(0, 0, 0, 0.92 * alpha)
        f.flatTitle:SetColorTexture(0.12, 0.12, 0.12, alpha)
        for _, edge in ipairs(f.flatEdges) do
            edge:SetColorTexture(0.3, 0.3, 0.3, alpha)
        end
    end
    f.titleLine:SetColorTexture(mocha("caramel", alpha))
    f.titleLine:SetShown(modern)
    f.menuLine:SetColorTexture(mocha("caramel", alpha))
    f.menuLine:SetShown(modern)
    self:LayoutMenu()
    self:StyleMinimizeButton()
    for _, b in ipairs(self.tabs) do
        self:StyleTab(b, b.selected)
    end
    for _, control in ipairs(self.skinned) do
        control.crtSkin(modern)
    end
end

-- Flat controls for the Modern look. Each control gets its own flat background, a 1-pixel border and
-- (for a dropdown) a small arrow, shown in Modern, while the game's art is faded out; Classic puts
-- the game's art back. UI.skinned lists every control so ApplyStyle can switch them.
UI.skinned = {}

local function flatSkin(frame, inset)
    inset = inset or 0
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetPoint("TOPLEFT", inset, -inset)
    bg:SetPoint("BOTTOMRIGHT", -inset, inset)
    local edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local e = frame:CreateTexture(nil, "BORDER", nil, -6)
        e:SetPoint(side[1], bg, side[1])
        e:SetPoint(side[2], bg, side[2])
        if side[3] then
            e:SetHeight(1)
        else
            e:SetWidth(1)
        end
        edges[#edges + 1] = e
    end
    return bg, edges
end

local function setFlat(bg, edges, shown, fill)
    bg:SetShown(shown)
    bg:SetColorTexture(mocha(fill or "roast"))
    for _, e in ipairs(edges) do
        e:SetShown(shown)
        e:SetColorTexture(mocha("edge"))
    end
end

-- A WowStyle1DropdownTemplate dropdown (UI.Dropdown makes them).
function UI:SkinDropdown(d)
    if d.crtSkin or not (d.Background and d.Arrow) then
        return
    end
    local bg, edges = flatSkin(d, 0)
    local arrow = d:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas("auctionhouse-ui-dropdown-arrow-down")
    arrow:SetSize(12, 8)
    arrow:SetPoint("RIGHT", -7, 0)
    d.crtSkin = function(modern)
        d.Background:SetAlpha(modern and 0 or 1)
        d.Arrow:SetAlpha(modern and 0 or 1)
        setFlat(bg, edges, modern)
        arrow:SetShown(modern)
        arrow:SetVertexColor(mocha("caramel"))
    end
    self.skinned[#self.skinned + 1] = d
    d.crtSkin(self:IsModern())
end

-- A UIPanelButtonTemplate button: its Left, Middle and Right art and its red highlight.
-- A close button (UIPanelCloseButton, or the window template's own): in Modern, a plain X in place
-- of the game's red and gold button art, cream and turning caramel on hover.
function UI:SkinCloseButton(b)
    if type(b) ~= "table" or b.crtSkin then
        return
    end
    local x = b:CreateFontString(nil, "OVERLAY")
    x:SetFont("Fonts\\ARIALN.TTF", 18, "")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("X")
    local hover = false
    local function color()
        x:SetTextColor(mocha(hover and "caramel" or "cream"))
    end
    b:HookScript("OnEnter", function()
        hover = true
        color()
    end)
    b:HookScript("OnLeave", function()
        hover = false
        color()
    end)
    b.crtSkin = function(modern)
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local texture = b[get] and b[get](b)
            if texture then
                texture:SetAlpha(modern and 0 or 1)
            end
        end
        x:SetShown(modern)
        color()
    end
    self.skinned[#self.skinned + 1] = b
    b.crtSkin(self:IsModern())
end

function UI:SkinButton(b)
    if b.crtSkin or not (b.Left and b.Middle and b.Right) then
        return
    end
    local bg, edges = flatSkin(b, 1)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(bg)
    hover:SetColorTexture(1, 1, 1, 0.08)
    local highlight = b:GetHighlightTexture()
    b.crtSkin = function(modern)
        for _, art in ipairs({ b.Left, b.Middle, b.Right }) do
            art:SetAlpha(modern and 0 or 1)
        end
        if highlight then
            highlight:SetAlpha(modern and 0 or 1)
        end
        hover:SetAlpha(modern and 1 or 0)
        setFlat(bg, edges, modern)
    end
    self.skinned[#self.skinned + 1] = b
    b.crtSkin(self:IsModern())
end

-- Skins every panel button under a frame. Pages call nothing themselves: the panel runs this when a
-- page is built or shown, and when a page tab changes, so buttons made later are caught too.
function UI:SkinTree(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not child.crtSkin then
            if child.Left and child.Middle and child.Right and child:GetObjectType() == "Button" then
                self:SkinButton(child)
            elseif child.Background and child.Arrow and child.SetupMenu then
                self:SkinDropdown(child)
            end
        end
        self:SkinTree(child)
    end
end

-- The menu: one list in Classic, grouped blocks in Modern, in the same order (UI.MENU_GROUPS).
local MENU_ROW, MENU_GAP = 30, 2

local function menuGroups()
    local groups, placed = {}, {}
    for _, group in ipairs(UI.MENU_GROUPS) do
        local keys = {}
        for _, key in ipairs(group) do
            if UI.pages[key] then
                keys[#keys + 1] = key
                placed[key] = true
            end
        end
        groups[#groups + 1] = keys
    end
    for _, key in ipairs(UI.order) do
        if not placed[key] then
            table.insert(groups[#groups], key)
        end
    end
    -- Hidden pages leave the menu.
    for _, keys in ipairs(groups) do
        for i = #keys, 1, -1 do
            if UI.pages[keys[i]].hidden then
                table.remove(keys, i)
            end
        end
    end
    return groups
end

function UI:LayoutMenu()
    local f = self.frame
    if not f then
        return
    end
    local menu = f.menu
    for _, bg in ipairs(menu.blocks) do
        bg:Hide()
    end
    if not self:IsModern() then
        -- Classic lists the pages in the same order as Modern's blocks, as one list.
        local order = {}
        for _, keys in ipairs(menuGroups()) do
            for _, key in ipairs(keys) do
                order[#order + 1] = key
            end
        end
        for i, key in ipairs(order) do
            local b = self.pages[key].button
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -(i - 1) * 32)
            b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -(i - 1) * 32)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", 10, 0)
        end
    else
        local y = 0
        for g, keys in ipairs(menuGroups()) do
            if #keys > 0 then
                local bg = menu.blocks[g]
                if not bg then
                    bg = menu:CreateTexture(nil, "BACKGROUND", nil, -1)
                    menu.blocks[g] = bg
                end
                bg:SetColorTexture(mocha("roast", 0.95))
                bg:ClearAllPoints()
                bg:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
                bg:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -6, y)
                bg:SetHeight(#keys * (MENU_ROW + MENU_GAP) + 2)
                bg:Show()
                y = y - 2
                for _, key in ipairs(keys) do
                    local b = self.pages[key].button
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, y)
                    b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, y)
                    b.text:ClearAllPoints()
                    b.text:SetPoint("CENTER")
                    y = y - (MENU_ROW + MENU_GAP)
                end
                y = y - 12
            end
        end
    end
    for _, page in pairs(self.pages) do
        if page.button then
            page.button:SetShown(not page.hidden)
            self:StyleMenuButton(page.button, page.button.selected)
        end
    end
end

function UI:StyleMenuButton(b, selected)
    b.selected = selected and true or false
    b.sel:SetShown(b.selected)
    if self:IsModern() then
        b.sel:SetColorTexture(mocha("mocha", 0.95))
        if b.selected then
            b.text:SetTextColor(mocha("cream"))
        else
            b.text:SetTextColor(mocha("latte"))
        end
    else
        b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        if b.selected then
            b.text:SetTextColor(1, 0.82, 0)
        else
            b.text:SetTextColor(0.85, 0.85, 0.85)
        end
    end
end

-- Page tabs. A page registers each tab button (a BackdropTemplate button with .sel and .text) when it
-- makes it, and calls SetTabSelected when its tab changes, so the tabs follow the look.
UI.tabs = {}

function UI:RegisterTab(b)
    self.tabs[#self.tabs + 1] = b
    self:StyleTab(b, false)
end

function UI:StyleTab(b, selected)
    b.selected = selected and true or false
    b.sel:SetShown(b.selected)
    local modern = self:IsModern()
    if modern then
        b.sel:SetColorTexture(mocha("mocha", 0.95))
        b.text:SetTextColor(mocha(b.selected and "cream" or "latte"))
    else
        b.sel:SetColorTexture(1, 0.82, 0, 0.18)
        if b.selected then
            b.text:SetTextColor(1, 0.82, 0)
        else
            b.text:SetTextColor(0.75, 0.75, 0.75)
        end
    end
    if b.SetBackdropBorderColor then
        if modern then
            b:SetBackdropColor(mocha("roast", 0.95))
            b:SetBackdropBorderColor(mocha("edge"))
        else
            b:SetBackdropColor(0, 0, 0, 0.4)
            b:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end
    end
end

function UI:SetTabSelected(b, selected)
    self:StyleTab(b, selected)
    -- A tab's content may be built only now, so its buttons are skinned here.
    if selected and b:GetParent() then
        self:SkinTree(b:GetParent())
    end
end

-- A small blue (?) that shows an explanation as a tooltip, used for every bit of extra context so the
-- pages stay compact. text is a string, with paragraphs split on blank lines, or a function returning
-- one, for text that changes. Anchor the returned button beside the heading or control it explains.
function UI.Help(parent, title, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 16)
    local fs = b:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    fs:SetPoint("CENTER")
    fs:SetText("|cff80c0ff(?)|r")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        local body = type(text) == "function" and text() or text or ""
        for paragraph in (body .. "\n\n"):gmatch("(.-)\n\n") do
            if paragraph ~= "" then
                GameTooltip:AddLine(paragraph, 0.85, 0.85, 0.85, true)
            end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return b
end

-- A small "Reset" button for the header bar of a window you can drag. It puts the window back where
-- it starts, and is shown with the bar (or by the window, during Previews). onClick does the reset.
function UI.ResetButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(44, 16)
    b:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 0.6)
    b:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    local text = b:CreateFontString(nil, "OVERLAY", "CRTFontButtonSmall")
    text:SetPoint("CENTER")
    text:SetText("Reset")
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local highlight = b:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(1, 1, 1, 0.15)
    end
    b:SetScript("OnClick", function()
        onClick()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset position", 1, 1, 1)
        GameTooltip:AddLine("Puts this window back where it starts.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return b
end

-- Fades a frame out over seconds, then calls done (which hides it). Showing it again should call
-- UI.CancelFade first, which stops a fade and puts the frame back to full opacity.
local fades = {}

function UI.FadeOut(frame, seconds, done)
    local driver = fades[frame]
    if not driver then
        driver = CreateFrame("Frame")
        fades[frame] = driver
    end
    local start, elapsed = frame:GetAlpha() or 1, 0
    driver:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= seconds then
            self:SetScript("OnUpdate", nil)
            frame:SetAlpha(0)
            done()
            return
        end
        frame:SetAlpha(start * (1 - elapsed / seconds))
    end)
end

function UI.CancelFade(frame)
    local driver = fades[frame]
    if driver then
        driver:SetScript("OnUpdate", nil)
    end
    frame:SetAlpha(1)
end

function UI.SetFrameTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
    end
end

-- Game popups over our windows ---------------------------------------------------------------------

-- Lifts a game dialog (its strata is below the alert editor's) over our windows, putting its strata
-- back when it hides. The hook is added once per frame; each lift saves the strata to restore.
function UI.LiftOver(dialog)
    if not (dialog and dialog.SetFrameStrata) then
        return
    end
    if not dialog.crtLifted then
        dialog.crtLifted = dialog:GetFrameStrata()
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        if not dialog.crtHooked then
            dialog.crtHooked = true
            dialog:HookScript("OnHide", function(d)
                if d.crtLifted then
                    d:SetFrameStrata(d.crtLifted)
                    d.crtLifted = nil
                end
            end)
        end
    end
    dialog:Raise()
end

-- The popup the game just showed: the frame the show call returned, else the one StaticPopup_Visible
-- names for `name` (the popup's key; "GENERIC_CONFIRMATION" for StaticPopup_ShowCustomGenericConfirmation),
-- else the first visible StaticPopup. Nil when none is shown.
function UI.ShownPopup(ret, name)
    if type(ret) == "table" then
        return ret
    end
    local frameName = name and StaticPopup_Visible and StaticPopup_Visible(name)
    local named = frameName and _G[frameName]
    if type(named) == "table" then
        return named
    end
    for i = 1, 4 do
        local p = _G["StaticPopup" .. i]
        if p and p:IsShown() then
            return p
        end
    end
    return nil
end

-- A popup's edit box, by whichever name this client gives it.
function UI.PopupEditBox(dialog)
    if not dialog then
        return nil
    end
    return dialog.GetEditBox and dialog:GetEditBox() or dialog.EditBox or dialog.editBox
end

local function createMenuButton(parent, page, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(30) -- placed by UI:LayoutMenu

    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.18)
    b.sel:Hide()

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.08)

    b.text = b:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    b.text:SetPoint("LEFT", 10, 0)
    b.text:SetText(page.title)

    b:SetScript("OnClick", function()
        UI:SelectPage(page.key)
    end)
    return b
end

function UI:Create()
    if self.frame then
        return self.frame
    end

    local f = CreateFrame("Frame", "CowfeeRaidToolsFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_W, FRAME_H)
    UI:RegisterLayer("panel", f)

    -- The template's art, for the General Settings page's style and opacity: every texture it made.
    f.art = {}
    for _, region in ipairs({ f:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            f.art[#f.art + 1] = region
        end
    end
    -- The minimal style: a flat background, a darker title strip and a thin border.
    f.flatBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.flatBg:SetAllPoints()
    f.flatTitle = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.flatTitle:SetPoint("TOPLEFT", 1, -1)
    f.flatTitle:SetPoint("TOPRIGHT", -1, -1)
    f.flatTitle:SetHeight(23)
    f.flatEdges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local edge = f:CreateTexture(nil, "BORDER")
        edge:SetPoint(side[1])
        edge:SetPoint(side[2])
        if side[3] then
            edge:SetHeight(1)
        else
            edge:SetWidth(1)
        end
        f.flatEdges[#f.flatEdges + 1] = edge
    end
    -- The Modern look's teal line under the title.
    f.titleLine = f:CreateTexture(nil, "BORDER")
    f.titleLine:SetPoint("TOPLEFT", 1, -24)
    f.titleLine:SetPoint("TOPRIGHT", -1, -24)
    f.titleLine:SetHeight(1)
    f.flat = { f.flatBg, f.flatTitle }
    for _, edge in ipairs(f.flatEdges) do
        f.flat[#f.flat + 1] = edge
    end
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- StartMoving(true) moves from where the mouse is now. Without it the game moves from a press
    -- point it remembers, which can be an old one (it went stale after using the Timeline pop-out),
    -- and the window jumped by the distance between the two. Every movable window does the same.
    f:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SaveWindowPosition()
        -- A drag while the alerts have parked the window (Alerts/Areas.lua) is the player's own choice.
        if UI.windowParked then
            UI.windowParked = "dragged"
        end
    end)
    UI.SetFrameTitle(f, "Cowfee Raid Tools")
    -- The addon's version, from the .toc, in the top left of the title bar.
    f.version = f:CreateFontString(nil, "OVERLAY", "CRTFontButtonSmall")
    f.version:SetPoint("TOPLEFT", 10, -6)
    f.version:SetTextColor(0.6, 0.6, 0.6)
    f.version:SetText("v" .. tostring(CRT.version))
    tinsert(UISpecialFrames, "CowfeeRaidToolsFrame")

    -- Closing the panel also turns the previews off, so nothing is left floating on screen.
    f:SetScript("OnHide", function()
        UI:SetPreviews(false)
        for key, page in pairs(UI.pages) do
            if page.closeHides and not page.hidden then
                UI:SetPageHidden(key, true)
            end
        end
    end)

    -- "Previews", in the title bar beside the close button. It uses the game's small size, not the
    -- addon's scaled one, and is 18 high and 1 pixel above centre, so it fits inside the title bar.
    local pb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    pb:SetNormalFontObject(CRTFontButtonSmall)
    pb:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    pb:SetDisabledFontObject(CRTFontButtonSmallDisable)
    pb:SetSize(96, 18)
    -- Beside the close button, centred on it, so it sits inside the title bar.
    if f.CloseButton then
        pb:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 1)
    else
        pb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -2)
    end
    pb:SetText("Previews")
    pb:SetScript("OnClick", function()
        UI:TogglePreviews()
    end)
    pb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Previews", 1, 1, 1)
        GameTooltip:AddLine("Shows every movable window with sample content (the ready check bar and window, the debuff panel, the note windows, your alert and the low-health banner) so you can drag them into place. Closing this window also turns the previews off.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    pb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    UI.previewButton = pb

    -- Minimize, like a desktop window: the button left of Previews, or a double-click on the title
    -- bar, shrinks the window to its title bar; the same again, /crt or opening a page restores it.
    local mb = CreateFrame("Button", nil, f, "BackdropTemplate")
    mb:SetSize(20, 18)
    mb:SetPoint("RIGHT", pb, "LEFT", -4, 0)
    mb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    -- A line for minimize, a small square for restore, drawn with plain textures.
    mb.line = mb:CreateTexture(nil, "OVERLAY")
    mb.line:SetSize(10, 2)
    mb.line:SetPoint("BOTTOM", 0, 4)
    mb.square = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local e = mb:CreateTexture(nil, "OVERLAY")
        e:SetPoint(side[1], mb, "CENTER", side[1]:find("LEFT") and -4 or 4, side[1]:find("TOP") and 4 or -4)
        e:SetPoint(side[2], mb, "CENTER", side[2]:find("LEFT") and -4 or 4, side[2]:find("TOP") and 4 or -4)
        if side[3] then
            e:SetHeight(side[1]:find("TOP") and 2 or 1)
        else
            e:SetWidth(1)
        end
        mb.square[#mb.square + 1] = e
    end
    mb:SetScript("OnClick", function()
        UI:SetMinimized(not UI.minimized)
    end)
    mb:SetScript("OnEnter", function(self)
        self.hover = true
        UI:StyleMinimizeButton()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(UI.minimized and "Restore" or "Minimize", 1, 1, 1)
        GameTooltip:AddLine("Double-clicking the title bar does the same.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    mb:SetScript("OnLeave", function(self)
        self.hover = false
        UI:StyleMinimizeButton()
        GameTooltip:Hide()
    end)
    f.minimizeButton = mb

    -- The title bar: drag it to move the window, double-click it to minimize or restore.
    local titleBar = CreateFrame("Button", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetPoint("RIGHT", mb, "LEFT", -4, 0)
    titleBar:SetHeight(24)
    titleBar:RegisterForClicks("LeftButtonUp")
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        f:GetScript("OnDragStart")(f)
    end)
    titleBar:SetScript("OnDragStop", function()
        f:GetScript("OnDragStop")(f)
    end)
    titleBar:SetScript("OnDoubleClick", function()
        UI:SetMinimized(not UI.minimized)
    end)

    f:SetScale(UI:Scale() / 100)
    UI:ApplyWindowPosition(f)

    -- Ctrl + mouse wheel over the panel changes its size in steps of 5 percent.
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then
            UI:SetScale(UI:Scale() + delta * 5)
        end
    end)

    local menu = CreateFrame("Frame", nil, f)
    menu:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -32)
    menu:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    menu:SetWidth(MENU_W)
    menu.blocks = {}
    f.menu = menu
    -- The Modern look's teal line on the menu's right edge.
    f.menuLine = menu:CreateTexture(nil, "BORDER")
    f.menuLine:SetPoint("TOPRIGHT", 0, 0)
    f.menuLine:SetPoint("BOTTOMRIGHT", 0, 0)
    f.menuLine:SetWidth(2)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", menu, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    f.content = content

    for i, key in ipairs(self.order) do
        local page = self.pages[key]
        page.button = createMenuButton(menu, page, i)
    end

    self.frame = f
    self:SkinCloseButton(f.CloseButton)
    self:SkinTree(f)
    self:ApplyStyle()
    f:Hide()
    return f
end

function UI:BuildPage(page)
    local pf = CreateFrame("Frame", nil, self.frame.content)
    pf:SetAllPoints()
    pf:Hide()
    page.frame = pf
    page.builder(pf)
    self:SkinTree(pf)
end

function UI:SelectPage(key)
    local page = self.pages[key]
    if not page or page.hidden then
        page = self.pages[self.order[1]]
    end
    if not page then
        return
    end
    if not page.frame then
        self:BuildPage(page)
    end
    for _, p in pairs(self.pages) do
        local selected = (p == page)
        if p.frame then
            p.frame:SetShown(selected)
        end
        if p.button then
            self:StyleMenuButton(p.button, selected)
        end
    end
    CRT.db.lastPage = page.key
end

-- Minimize -------------------------------------------------------------------------------------
-- Minimized, the window keeps only its title bar (the version, the title, minimize, Previews and
-- close). Its top-left corner stays where it is, so it shrinks upwards to the bar and grows back
-- down. It isn't saved: the window always opens full size after a /reload.

local TITLE_H = 26

function UI:StyleMinimizeButton()
    local mb = self.frame and self.frame.minimizeButton
    if not mb then
        return
    end
    local modern = self:IsModern()
    local r, g, b
    if modern then
        local c = CRT.MOCHA[mb.hover and "caramel" or "cream"]
        r, g, b = c[1], c[2], c[3]
        mb:SetBackdropColor(0, 0, 0, 0)
        mb:SetBackdropBorderColor(0, 0, 0, 0)
    else
        r, g, b = 1, 0.82, 0
        if not mb.hover then
            r, g, b = 0.9, 0.9, 0.9
        end
        mb:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        mb:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end
    mb.line:SetColorTexture(r, g, b, 1)
    mb.line:SetShown(not self.minimized)
    for _, e in ipairs(mb.square) do
        e:SetColorTexture(r, g, b, 1)
        e:SetShown(self.minimized and true or false)
    end
end

function UI:SetMinimized(on)
    local f = self.frame
    if not f then
        return
    end
    on = on and true or false
    if on == (self.minimized or false) then
        return
    end
    -- Pin the top-left corner first, so the window shrinks and grows from the top, and save that
    -- anchor, so anything that puts the window back (ApplyWindowPosition) puts it here.
    local left, top = f:GetLeft(), f:GetTop()
    if left and top then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        self:SaveWindowPosition()
    end
    self.minimized = on
    f:SetHeight(on and TITLE_H or FRAME_H)
    f.menu:SetShown(not on)
    f.content:SetShown(not on)
    if type(f.Inset) == "table" then
        f.Inset:SetShown(not on)
    end
    self:StyleMinimizeButton()
end

-- Saves where the main window is: its anchor point, the point of the screen it is measured from, and
-- the offsets. All four are needed: a drag or a minimize can leave the window anchored from a
-- different point of the screen than its own (TOPLEFT from the screen's BOTTOMLEFT), and putting it
-- back as if both were the same made it jump.
function UI:SaveWindowPosition()
    local f = self.frame
    if not f then
        return
    end
    local point, _, relativePoint, x, y = f:GetPoint()
    if point then
        local w = CRT.db.window
        w.point, w.relativePoint, w.x, w.y = point, relativePoint or point, x, y
    end
end

-- Puts the window (the main one, unless a frame is given) at its saved place (CRT.db.window).
function UI:ApplyWindowPosition(f)
    f = f or self.frame
    local w = CRT.db.window
    if f then
        f:ClearAllPoints()
        f:SetPoint(w.point, UIParent, w.relativePoint or w.point, w.x, w.y)
    end
end

function UI:Show(key)
    local f = self:Create()
    self:SetMinimized(false)
    self:SelectPage(key or CRT.db.lastPage)
    f:Show()
end

-- /crt: opens the window, restores it when it is minimized, and closes it when it is open.
function UI:Toggle()
    if self.frame and self.frame:IsShown() and not self.minimized then
        self.frame:Hide()
    else
        self:Show()
    end
end
