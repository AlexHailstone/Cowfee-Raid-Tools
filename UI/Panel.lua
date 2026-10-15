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
    { key = "readycheck", label = "Ready check window", default = "HIGH" },
    { key = "bar", label = "Your consumables bar", default = "HIGH" },
    { key = "debuffs", label = "Debuff panel", default = "HIGH" },
    { key = "lowhealth", label = "Low-health banner", default = "DIALOG" },
}

local layerDefaults, layerFrames = {}, {}
for _, layer in ipairs(UI.LAYERS) do
    layerDefaults[layer.key] = layer.default
    layerFrames[layer.key] = {}
end
local layersWaiting = false -- a change blocked by combat, applied when combat ends

function UI:Layer(key)
    local saved = CRT.db and CRT.db.ui and CRT.db.ui.layers[key]
    return saved or layerDefaults[key] or "MEDIUM"
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
end

function UI:SetLayer(key, strata)
    CRT.db.ui.layers[key] = (strata ~= layerDefaults[key]) and strata or nil
    applyLayer(key)
    if layersWaiting then
        CRT:Print("That window can't change layer during combat. It will change when combat ends.")
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
    { "notes", "debuffs", "timeline" },
    { "late", "tattle" },
}

function UI:IsModern()
    return CRT.db and CRT.db.ui and CRT.db.ui.modern and true or false
end

function UI:ApplyStyle()
    local f = self.frame
    if not f then
        return
    end
    local s = CRT.db.ui
    local modern = self:IsModern()
    local flat = modern or s.style == "minimal"
    local alpha = (s.bgAlpha or 100) / 100
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

function UI.SetFrameTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    elseif frame.TitleText then
        frame.TitleText:SetText(text)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
    end
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
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        local w = CRT.db.window
        w.point, w.x, w.y = point, x, y
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

    local w = CRT.db.window
    f:SetScale(UI:Scale() / 100)
    f:ClearAllPoints()
    f:SetPoint(w.point, UIParent, w.point, w.x, w.y)

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
    local page = self.pages[key] or self.pages[self.order[1]]
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

function UI:Show(key)
    local f = self:Create()
    self:SelectPage(key or CRT.db.lastPage)
    f:Show()
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Show()
    end
end
