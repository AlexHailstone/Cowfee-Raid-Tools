local ADDON, CRT = ...

-- The minimap button, and the addon's entry in the game's addon menu beside the minimap (the
-- AddonCompartmentFunc line in the .toc). Left-click opens or closes the main window, right-click
-- opens General Settings. Drag the button around the minimap's edge; its place is saved as an angle in
-- CRTDB.minimap.angle, and General Settings can hide it (CRTDB.minimap.hide).

local UI = CRT.UI
local Minimap_ = {}
CRT.MinimapButton = Minimap_

-- The addon's own coffee cup, a round 128 x 128 TGA in the Media folder.
local ICON = "Interface\\AddOns\\CowfeeRaidTools\\Media\\Icon"

local button

local function settings()
    return CRT.db.minimap
end

local function place()
    local angle = math.rad(settings().angle or 225)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onClick(mouseButton)
    if mouseButton == "RightButton" then
        UI:Show("settings")
    else
        UI:Toggle()
    end
end

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Cowfee Raid Tools", 1, 0.82, 0)
    GameTooltip:AddLine("v" .. tostring(CRT.version), 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Left-click: open or close", 1, 1, 1)
    GameTooltip:AddLine("Right-click: General Settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 1, 1, 1)
    GameTooltip:Show()
end

local function create()
    button = CreateFrame("Button", "CowfeeRaidToolsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 6, -5)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouseButton)
        onClick(mouseButton)
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    -- Dragging follows the cursor around the minimap's centre.
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            settings().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            place()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
end

function Minimap_:Refresh()
    if not button then
        if settings().hide then
            return
        end
        create()
    end
    place()
    button:SetShown(not settings().hide)
end

function Minimap_:SetHidden(hide)
    settings().hide = hide and true or false
    self:Refresh()
end

-- The game's addon menu beside the minimap calls this global, named in the .toc.
function CowfeeRaidTools_OnAddonCompartmentClick(_, mouseButton)
    onClick(mouseButton)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    Minimap_:Refresh()
end)
