local ADDON, CRT = ...

-- The row of consumable icons shown above the ready check. A missing or expiring consumable
-- gets marching ants around its icon. Food, flask, weapon and rune icons are clickable and use the
-- first listed item in your bags. The potion icon only shows a count and is never used from the row. The icons are drawn by Consumables/Bar.lua, shared with the
-- bar on the Consumables tab.
--
-- Every icon is a secure button, so the icon order can change without making new frames. That
-- makes the buttons and their parent frame protected: in combat the row cannot be shown,
-- hidden or moved and a click action cannot change, so those wait for PLAYER_REGEN_ENABLED.
-- The row is built at login, out of combat, because secure buttons should be created there.

local Consumables = CRT.Consumables
local Ants = CRT.Ants
local Bar = CRT.ConsumablesBar
local Display = {}
CRT.ConsumablesDisplay = Display

local REFRESH_SECONDS = 0.5
local PREVIEW_SECONDS = 20

local frame, handle, closeBar
local slots = {}
local dragging -- true while the row is being dragged, so it is not re-anchored under the cursor
local shownUntil -- time at which a ready check or preview row hides by itself, nil for no limit
local sawReadyCheckFrame -- true once Blizzard's ready check dialog has been seen on screen
local elapsed = 0
local pendingHide -- a hide that was blocked by combat

local function showTooltip(self)
    local def = Consumables:Def(self.key)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if self.useItem then
        GameTooltip:SetText(self.useItem.name, 1, 1, 1)
        GameTooltip:AddLine("Click to use (" .. self.useItem.count .. " in your bags)", 0.6, 0.9, 0.6)
        if self.key == "weapon" then
            GameTooltip:AddLine("Shift-click for the off hand", 0.7, 0.7, 0.7)
        end
    else
        GameTooltip:SetText(def and def.label or "", 1, 1, 1)
        if def and def.clickable then
            GameTooltip:AddLine("None of the listed items are in your bags.", 0.9, 0.4, 0.4)
        elseif def and def.key == "potion" then
            GameTooltip:AddLine("Shows how many you have. Not used from here.", 0.7, 0.7, 0.7)
        end
    end
    Bar.AddStatusLines(self.status)
    GameTooltip:Show()
end

local function build()
    if frame then
        return frame
    end
    local count = #Consumables.CATEGORIES
    frame = CreateFrame("Frame", "CowfeeRaidToolsReadyCheckRow", UIParent, "BackdropTemplate")
    frame:SetSize(Bar.Size(count))
    CRT.UI:RegisterLayer("bar", frame)
    frame:SetBackdrop(Bar.BACKDROP)
    CRT.UI:RegisterThemed(frame, { bg = { 0, 0, 0, 0.45 }, border = { 0.2, 0.8, 0.9 } })
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- A drag handle above the row, shown during a preview so the row can be moved.
    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    handle:SetBackdrop(Bar.BACKDROP)
    CRT.UI:RegisterThemed(handle, { bg = { 0.1, 0.3, 0.35, 0.9 }, border = { 0.2, 0.8, 0.9 } })
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local handleText = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    handleText:SetPoint("CENTER")
    handleText:SetText("Consumables: drag to move")
    CRT.UI.ResetButton(handle, function()
        Display:ResetPosition()
    end):SetPoint("RIGHT", -2, 0)
    handle:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            return
        end
        dragging = true
        frame:StartMoving(true)
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        dragging = false
        local point, _, relativePoint, x, y = frame:GetPoint()
        Consumables:SavePosition(point, relativePoint, x, y)
    end)
    handle:Hide()

    -- A Close bar under the row, the row's width, for when you're done looking before the check ends.
    -- Hidden during previews, which have their own drag bar and Reset.
    closeBar = CreateFrame("Button", nil, frame, "BackdropTemplate")
    closeBar:SetHeight(20)
    closeBar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
    closeBar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
    closeBar:SetBackdrop(Bar.BACKDROP)
    CRT.UI:RegisterThemed(closeBar, { bg = { 0, 0, 0, 0.6 }, border = { 0.2, 0.8, 0.9 } })
    local closeText = closeBar:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("Close")
    closeBar:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local closeHighlight = closeBar:GetHighlightTexture()
    if closeHighlight then
        closeHighlight:SetVertexColor(1, 1, 1, 0.12)
    end
    closeBar:SetScript("OnClick", function()
        Display:Hide()
    end)

    for index = 1, count do
        local slot = Bar.CreateSlot(frame, index, true)
        slot:SetScript("OnEnter", showTooltip)
        slot:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        slots[index] = slot
    end

    frame:SetScript("OnUpdate", function(_, dt)
        -- The ants move every frame, and the statuses refresh twice a second.
        for _, slot in ipairs(slots) do
            Ants:Update(slot, dt)
        end
        elapsed = elapsed + dt
        if elapsed < REFRESH_SECONDS then
            return
        end
        elapsed = 0
        Display:Refresh()
    end)
    return frame
end

local function place()
    if InCombatLockdown() or dragging then
        return
    end
    local rc = _G.ReadyCheckFrame
    local saved = Consumables:Position()
    frame:ClearAllPoints()
    if saved then
        -- Where the player put it.
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
    elseif rc and rc.IsShown and rc:IsShown() then
        frame:SetPoint("BOTTOM", rc, "TOP", 0, 18)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end
end

-- Points a clickable icon at the item a click should use, and clears it for the others.
-- Not allowed in combat.
local function updateClickAction(slot, clickable)
    if InCombatLockdown() then
        return
    end
    local item = clickable and Consumables:NextItem(slot.key) or nil
    slot.useItem = item
    -- Used by item ID, not by name: every quality rank of a consumable has the same name, and /use
    -- with a name could take a lower rank than the one picked.
    local use = item and ("item:" .. item.id)
    local signature = item and (slot.key .. ":" .. use) or "none"
    if slot.appliedSignature == signature then
        return
    end
    slot.appliedSignature = signature

    if not item then
        slot:SetAttribute("type", nil)
        slot:SetAttribute("macrotext", nil)
        slot:SetAttribute("shift-type1", nil)
        slot:SetAttribute("shift-macrotext1", nil)
    elseif slot.key == "weapon" then
        -- Use the oil or stone, then apply it to the main hand. Shift-click uses the off hand.
        slot:SetAttribute("type", "macro")
        slot:SetAttribute("macrotext", "/use " .. use .. "\n/use " .. (INVSLOT_MAINHAND or 16))
        slot:SetAttribute("shift-type1", "macro")
        slot:SetAttribute("shift-macrotext1", "/use " .. use .. "\n/use " .. (INVSLOT_OFFHAND or 17))
    else
        slot:SetAttribute("type", "macro")
        slot:SetAttribute("macrotext", "/use " .. use)
    end
end

-- Hiding is blocked in combat on a frame with protected children, so it waits.
local function hideFrame()
    if not frame then
        return
    end
    if InCombatLockdown() then
        pendingHide = true
        return
    end
    pendingHide = false
    frame:Hide()
end

function Display:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    -- Hide when the check has timed out, or when Blizzard's dialog was shown and has gone,
    -- which means you answered it.
    local rc = _G.ReadyCheckFrame
    if rc and rc.IsShown then
        if rc:IsShown() then
            sawReadyCheckFrame = true
        elseif sawReadyCheckFrame and not self.preview then
            return self:Hide()
        end
    end
    if shownUntil and GetTime() >= shownUntil then
        return self:Hide()
    end
    place()

    Consumables:RefreshBags()
    for index, key in ipairs(Consumables:Order()) do
        local slot = slots[index]
        local def = Consumables:Def(key)
        slot.key = key
        Bar.Apply(slot, Consumables:Status(key))
        updateClickAction(slot, def and def.clickable)
    end
end

function Display:Hide()
    -- A preview kept on from the main panel stays until it is turned off there.
    if self.persistent then
        return
    end
    shownUntil = nil
    self.preview = false
    hideFrame()
end

local function show(seconds, preview)
    if not Consumables:Enabled() and not preview then
        return
    end
    if InCombatLockdown() then
        -- The row holds protected buttons, so it cannot be shown in combat.
        if preview then
            CRT:Print("The row can't be shown while you are in combat.")
        end
        return
    end
    build()
    CRT.UI.CancelFade(frame)
    pendingHide = false
    Display.preview = preview
    sawReadyCheckFrame = false
    shownUntil = seconds and (GetTime() + seconds) or nil
    handle:SetShown(preview and true or false)
    closeBar:SetShown(not preview)
    place()
    frame:Show()
    elapsed = REFRESH_SECONDS
    Display:Refresh()
end

-- Shows the row for a few seconds without a real ready check, for testing.
function Display:Preview()
    show(PREVIEW_SECONDS, true)
    if frame and frame:IsShown() then
        CRT:Print("Showing the consumables row for " .. PREVIEW_SECONDS .. " seconds.")
    end
end

-- Keeps the row on screen, with its drag handle, until it is turned off. Used by the
-- "Previews" button in the main panel.
function Display:SetPreview(on)
    if on then
        show(nil, true)
        self.persistent = frame and frame:IsShown() or false
    else
        self.persistent = false
        if handle then
            handle:Hide()
        end
        self:Hide()
    end
end

-- Moves the row back above the ready check dialog.
function Display:ResetPosition()
    Consumables:ResetPosition()
    if frame and frame:IsShown() then
        place()
    end
end

CRT.UI:RegisterPreview("consumables", function(on)
    Display:SetPreview(on)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("READY_CHECK")
events:RegisterEvent("READY_CHECK_FINISHED")
events:RegisterEvent("START_PLAYER_COUNTDOWN")
-- True when the ready check was started by you. The name can come with a realm, or be hidden from
-- addons, in which case it does not count as yours.
local function startedByMe(initiator)
    if type(initiator) ~= "string" or (issecretvalue and issecretvalue(initiator)) then
        return false
    end
    return Ambiguate(initiator, "none") == UnitName("player")
end

events:SetScript("OnEvent", function(_, event, initiator, timeLeft)
    if event == "PLAYER_LOGIN" then
        -- Create the secure buttons now, out of combat.
        if not InCombatLockdown() then
            build()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingHide then
            hideFrame()
        elseif frame and frame:IsShown() then
            Display:Refresh()
        end
    elseif event == "START_PLAYER_COUNTDOWN" then
        -- A pull timer started: the bar fades out over 2 seconds (Ready Check settings).
        if frame and frame:IsShown() and not Display.persistent and CRT.db.readycheck.fadeOnPull then
            CRT.UI.FadeOut(frame, 2, function()
                Display:Hide()
            end)
        end
    elseif event == "READY_CHECK" then
        if Consumables:NotStarter() and startedByMe(initiator) then
            return
        end
        local seconds = type(timeLeft) == "number" and timeLeft or 30
        show(seconds + 1, false)
        -- Blizzard's dialog may not be on screen yet when this event arrives, so place it again shortly.
        C_Timer.After(0.3, function()
            if frame and frame:IsShown() then
                place()
            end
        end)
    else
        Display:Hide()
    end
end)
