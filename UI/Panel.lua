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
    b:SetHeight(30)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * 32)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * 32)

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
    f:SetFrameStrata("HIGH")
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
    tinsert(UISpecialFrames, "CowfeeRaidToolsFrame")

    -- Closing the panel also turns the previews off, so nothing is left floating on screen.
    f:SetScript("OnHide", function()
        UI:SetPreviews(false)
    end)

    -- "Previews", in the title bar beside the close button. It uses the game's small fonts, not the
    -- addon's scaled ones, and is 18 high and 1 pixel lower than centre, so it fits inside the title bar.
    local pb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    pb:SetNormalFontObject(GameFontNormalSmall)
    pb:SetHighlightFontObject(GameFontHighlightSmall)
    pb:SetDisabledFontObject(GameFontDisableSmall)
    pb:SetSize(96, 18)
    -- Beside the close button, centred on it, so it sits inside the title bar.
    if f.CloseButton then
        pb:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, -1)
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
    f.menu = menu

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", menu, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    f.content = content

    for i, key in ipairs(self.order) do
        local page = self.pages[key]
        page.button = createMenuButton(menu, page, i)
    end

    self.frame = f
    f:Hide()
    return f
end

function UI:BuildPage(page)
    local pf = CreateFrame("Frame", nil, self.frame.content)
    pf:SetAllPoints()
    pf:Hide()
    page.frame = pf
    page.builder(pf)
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
            p.button.sel:SetShown(selected)
            if selected then
                p.button.text:SetTextColor(1, 0.82, 0)
            else
                p.button.text:SetTextColor(0.85, 0.85, 0.85)
            end
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
