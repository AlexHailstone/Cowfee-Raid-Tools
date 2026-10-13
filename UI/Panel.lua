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

    local w = CRT.db.window
    f:ClearAllPoints()
    f:SetPoint(w.point, UIParent, w.point, w.x, w.y)

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
