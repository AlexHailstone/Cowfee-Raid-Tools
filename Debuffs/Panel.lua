local ADDON, CRT = ...

-- The in-combat debuff panel: a movable panel that shows your debuffs, shortest first, while you
-- are in combat. The game hides debuff data from addons in combat, so the icons, timers and stack
-- counts are drawn by Blizzard's own AuraContainer and AuraButton frames, added in patch 12.1.0,
-- which fill themselves in even when the data is secret.
--
-- The wiki documents only the method names of these frames, not the option formats, so every call
-- is guarded and the result is recorded. `/crt debuffs info` prints what worked and what didn't.
--
-- The panel is faded out with alpha, not hidden, when you are out of combat, because showing
-- and hiding frames can be blocked in combat.

local Debuffs = CRT.Debuffs
local Panel = {}
CRT.DebuffPanel = Panel

local GROUP = "shortDebuffs"
local GAP = 4
local REFRESH_SECONDS = 0.5

local frame, container, handle
local dragging
local previewOn = false
local elapsed = 0
local report = { created = false, error = nil, notes = {} }

local function note(text)
    if #report.notes < 40 then
        report.notes[#report.notes + 1] = text
    end
end

-- Calls a method, recording a note if it fails or does not exist. Returns ok, results...
local function try(label, object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then
        note(label .. ": method " .. method .. " is missing")
        return false
    end
    local ok, a, b = pcall(fn, object, ...)
    if not ok then
        note(label .. ": " .. method .. " failed: " .. tostring(a))
        return false
    end
    return true, a, b
end

-- The container's sort enums, whichever way this client exposes them.
local function sortEnums()
    local method = _G.AuraContainerSortMethod or (Enum and Enum.AuraContainerSortMethod)
    local direction = _G.AuraContainerSortDirection or (Enum and Enum.AuraContainerSortDirection)
    return method, direction
end

local function pick(enum, names)
    if type(enum) ~= "table" then
        return nil
    end
    for _, name in ipairs(names) do
        if enum[name] ~= nil then
            return enum[name], name
        end
    end
    return nil
end

-- Chosen sort: shortest time left first where the client allows it, else the default order.
local chosen = {}

local function sortOptions()
    local methods, directions = sortEnums()
    local method, methodName = pick(methods, { "Expiration", "ExpirationOnly", "TimeLeft", "Duration" })
    local direction, directionName
    if Debuffs:Reverse() then
        direction, directionName = pick(directions, { "Reverse", "Descending" })
    else
        direction, directionName = pick(directions, { "Normal", "Ascending" })
    end
    chosen.method, chosen.methodName = method, methodName or "Default (no expiration sort found)"
    chosen.direction, chosen.directionName = direction, directionName or "Default"
    return method, direction
end

-- Lays the icons out in a row. Done by hand because the container's own layout options are not
-- documented. Out of combat only, since the frames may be restricted in combat.
local function layout()
    if not container or InCombatLockdown() then
        return
    end
    local size = Debuffs:Size()
    local count = Debuffs:MaxCount()
    local total = 0
    local ok, n = pcall(container.GetAuraGroupFrameCount, container, GROUP)
    if ok and type(n) == "number" then
        total = n
    end
    for index = 1, total do
        local ok2, button = pcall(container.GetAuraGroupFrame, container, GROUP, index)
        if ok2 and button then
            pcall(button.SetSize, button, size, size)
            pcall(button.ClearAllPoints, button)
            pcall(button.SetPoint, button, "TOPLEFT", frame, "TOPLEFT", (index - 1) * (size + GAP), 0)
        end
    end
    frame:SetSize(count * size + (count - 1) * GAP, size)
    container:SetSize(frame:GetWidth(), frame:GetHeight())
end

-- Sets up one aura button: an icon, a cooldown spiral with the time, and the stack count.
-- Blizzard fills these in from the aura, including when the aura's data is hidden from addons.
local function initializeButton(a, b)
    local button = (type(a) == "table" and a.SetIcon and a) or (type(b) == "table" and b.SetIcon and b)
    if not button then
        note("initializeFrame was called without an aura button")
        return
    end
    local size = Debuffs:Size()
    pcall(button.SetSize, button, size, size)

    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.7)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    try("button", button, "SetIcon", icon)

    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints(icon)
        try("button", button, "SetDurationCooldown", cooldown)
    else
        note("button: could not create a Cooldown frame")
    end

    local count = button:CreateFontString(nil, "OVERLAY", "CRTFontHighlight")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    try("button", button, "SetApplicationCount", count)
end

local function createContainer()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    if not ok or not c then
        report.error = "CreateFrame(\"AuraContainer\") failed: " .. tostring(c)
        return false
    end
    container = c
    container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    container:SetSize(frame:GetWidth(), frame:GetHeight())

    try("container", container, "SetUnit", "player")
    local method, direction = sortOptions()
    local options = {
        maxFrameCount = Debuffs:MaxCount(),
        initializeFrame = initializeButton,
        sortMethod = method,
        sortDirection = direction,
    }
    local okGroup = try("container", container, "AddAuraGroup", GROUP, "HARMFUL", options)
    try("container", container, "SetEnabled", true)
    try("container", container, "UpdateAllAuras")
    report.created = okGroup
    return okGroup
end

local function applyPosition()
    local saved = Debuffs:Position()
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
end

-- Shows the panel during combat, or always while previewing. Alpha, not Show, because showing and
-- hiding may be blocked in combat.
local function updateVisibility()
    if not frame then
        return
    end
    local visible = Debuffs:Enabled() and (InCombatLockdown() or previewOn)
    if previewOn then
        visible = true
    end
    frame:SetAlpha(visible and 1 or 0)
    if handle then
        handle:SetShown(previewOn)
    end
end

function Panel:Apply()
    if not frame or InCombatLockdown() then
        return
    end
    if not dragging then
        applyPosition()
    end
    if container then
        try("container", container, "SetAuraGroupMaxFrameCount", GROUP, Debuffs:MaxCount())
        local method, direction = sortOptions()
        if method ~= nil then
            try("container", container, "SetAuraGroupSortMethod", GROUP, method, direction)
        end
        try("container", container, "UpdateAllAuras")
    end
    layout()
    updateVisibility()
end

function Panel:SetPreview(on)
    previewOn = on and true or false
    if container then
        try("container", container, "SetEditModePreviewEnabled", previewOn)
        try("container", container, "UpdateAllAuras")
    end
    layout()
    updateVisibility()
end

function Panel:ResetPosition()
    Debuffs:ResetPosition()
    if frame and not InCombatLockdown() then
        applyPosition()
    end
end

local function build()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "CowfeeRaidToolsDebuffPanel", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    local size, count = Debuffs:Size(), Debuffs:MaxCount()
    frame:SetSize(count * size + (count - 1) * GAP, size)
    applyPosition()
    frame:SetAlpha(0)

    -- A drag handle above the panel, shown during a preview.
    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    handle:SetBackdropColor(0.35, 0.1, 0.1, 0.9)
    handle:SetBackdropBorderColor(0.9, 0.3, 0.3, 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("CENTER")
    text:SetText("Debuffs: drag to move")
    handle:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            return
        end
        dragging = true
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        dragging = false
        local point, _, relativePoint, x, y = frame:GetPoint()
        Debuffs:SavePosition(point, relativePoint, x, y)
    end)
    handle:Hide()

    createContainer()
    layout()

    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < REFRESH_SECONDS then
            return
        end
        elapsed = 0
        layout()
    end)
    updateVisibility()
end

-- Diagnostics: what was built, what failed, and what the game offers. --------------------

function Panel:InfoText()
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end

    add("Debuff panel diagnostics")
    add("Game build: " .. tostring(select(4, GetBuildInfo())))
    add("AuraContainer created: " .. tostring(report.created))
    if report.error then
        add("Error: " .. report.error)
    end
    add("In combat: " .. tostring(InCombatLockdown()) .. ", preview on: " .. tostring(previewOn) .. ", enabled: " .. tostring(Debuffs:Enabled()))
    add(format("Settings: size %d, max %d, reverse %s", Debuffs:Size(), Debuffs:MaxCount(), tostring(Debuffs:Reverse())))
    add("Sort chosen: method " .. tostring(chosen.methodName) .. ", direction " .. tostring(chosen.directionName))

    local methods, directions = sortEnums()
    local function dumpEnum(title, enum)
        if type(enum) ~= "table" then
            add(title .. ": not found")
            return
        end
        local parts = {}
        for key, value in pairs(enum) do
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
        end
        table.sort(parts)
        add(title .. ": " .. table.concat(parts, ", "))
    end
    dumpEnum("AuraContainerSortMethod", methods)
    dumpEnum("AuraContainerSortDirection", directions)

    -- Anything else that looks related, so undocumented options can be found.
    local found = {}
    for key in pairs(Enum or {}) do
        if type(key) == "string" and (key:find("AuraContainer") or key:find("CandidateFilter")) then
            found[#found + 1] = "Enum." .. key
        end
    end
    for key in pairs(_G) do
        if type(key) == "string" and (key:find("AuraContainer") or key:find("AuraCandidate")) and not key:find("^CRT") then
            found[#found + 1] = key
        end
    end
    table.sort(found)
    add("Related names: " .. (#found > 0 and table.concat(found, ", ") or "none found"))

    if container then
        local count = 0
        local ok, n = pcall(container.GetAuraGroupFrameCount, container, GROUP)
        if ok and type(n) == "number" then
            count = n
        end
        add("Aura frames in the group: " .. count)
        for index = 1, count do
            local ok2, button = pcall(container.GetAuraGroupFrame, container, GROUP, index)
            if ok2 and button then
                local shown = button.IsShown and button:IsShown()
                local point, _, _, x, y = button:GetPoint()
                add(format("  frame %d: shown %s, size %dx%d, at %s %s,%s", index, tostring(shown), button:GetWidth(), button:GetHeight(), tostring(point), tostring(x), tostring(y)))
            end
        end
    end

    add("")
    add("Notes from setup:")
    if #report.notes == 0 then
        add("  none")
    end
    for _, text in ipairs(report.notes) do
        add("  " .. text)
    end
    return table.concat(lines, "\n")
end

function Panel:ShowInfo()
    local tools = CRT.ConsumablesTools
    if tools then
        tools:ShowText("Debuff panel diagnostics (Ctrl+C to copy)", self:InfoText())
    else
        print(self:InfoText())
    end
end

Debuffs:OnChange(function()
    Panel:Apply()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not InCombatLockdown() then
            build()
        end
    elseif frame then
        updateVisibility()
        if event == "PLAYER_REGEN_ENABLED" then
            Panel:Apply()
        end
    end
end)

CRT.UI:RegisterPreview("debuffs", function(on)
    if not frame and not InCombatLockdown() then
        build()
    end
    Panel:SetPreview(on)
end)
