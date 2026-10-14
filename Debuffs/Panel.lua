local ADDON, CRT = ...

-- The in-combat debuff panel: a movable panel for the short debuffs a boss puts on you. Those are
-- "private auras". The game hides them from every addon, but it lets an addon choose WHERE Blizzard
-- draws them, with C_UnitAuras.AddPrivateAuraAnchor, the same call Blizzard's own debuff frame uses.
-- So the panel is a row of slots, and each slot is an anchor for one private aura: the game draws the
-- icon, the countdown number and the swipe inside it.
--
-- Regular debuffs, which can be long, are optional in a second row, drawn by Blizzard's AuraContainer
-- (added in patch 12.1.0). They cannot be limited to short ones, so that row is off by default.
--
-- The panel is faded with alpha, not hidden, when you are out of combat, because showing and hiding
-- frames can be blocked in combat. Positions and settings are saved per player in CRTDB.debuffs.

local Debuffs = CRT.Debuffs
local Panel = {}
CRT.DebuffPanel = Panel

local GROUP = "regularDebuffs"
local GAP = 4
local MAX_SLOTS = 8
local REGULAR_ROW_OFFSET = 24 -- gap below the private slots, which leaves room for their countdown text
local REFRESH_SECONDS = 0.5

local frame, container, handle
local slots = {} -- one frame per private aura slot
local anchorIds = {} -- the private aura anchors added for those slots
local tiles = {} -- preview tiles
local dragging
local previewOn = false
local inCombat = false
local elapsed = 0
local report = { created = false, error = nil, notes = {} }
local appliedAnchors, appliedContainer -- the settings each part was last built for

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

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

local function panelWidth()
    local size, count = Debuffs:Size(), Debuffs:MaxCount()
    return count * size + (count - 1) * GAP, size
end

-- Private aura slots ---------------------------------------------------------------

local function removeAnchors()
    for index, id in pairs(anchorIds) do
        pcall(C_UnitAuras.RemovePrivateAuraAnchor, id)
        anchorIds[index] = nil
    end
end

-- Adds one private aura anchor per slot, the way Blizzard's debuff frame does. Out of combat only.
local function addAnchors()
    if not frame or InCombatLockdown() then
        return
    end
    local size, count = Debuffs:Size(), Debuffs:MaxCount()
    local signature = size .. ":" .. count .. ":" .. tostring(Debuffs:DispelIcon())
    if signature == appliedAnchors then
        return
    end
    appliedAnchors = signature

    if not (C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor) then
        report.error = "C_UnitAuras.AddPrivateAuraAnchor is not available on this client"
        return
    end
    removeAnchors()

    for index = 1, MAX_SLOTS do
        local slot = slots[index]
        if not slot then
            slot = CreateFrame("Frame", nil, frame)
            slots[index] = slot
        end
        if index <= count then
            slot:SetSize(size, size)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", (index - 1) * (size + GAP), 0)
            slot:Show()
            local args = {
                unitToken = "player",
                auraIndex = index,
                parent = slot,
                showCooldownFrame = true,
                showCooldownEdge = true,
                showCountdownNumbers = true,
                showDispelIcon = Debuffs:DispelIcon(),
                isContainer = false,
                iconInfo = {
                    iconAnchor = { point = "CENTER", relativeTo = slot, relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
                    iconWidth = size,
                    iconHeight = size,
                },
                durationAnchor = { point = "TOP", relativeTo = slot, relativePoint = "BOTTOM", offsetX = 0, offsetY = -2 },
            }
            local ok, id = pcall(C_UnitAuras.AddPrivateAuraAnchor, args)
            if ok and id then
                anchorIds[index] = id
            else
                note("private aura anchor " .. index .. " failed: " .. tostring(id))
            end
        else
            slot:Hide()
        end
    end
end

-- Preview tiles ----------------------------------------------------------------------
-- Sample debuffs drawn by this addon, in the size and spacing of the real panel, so it can be placed
-- and sized. Private auras only exist during a boss mechanic, so there is nothing real to show.

local SAMPLES = {
    { spell = 589, time = "12s" },
    { spell = 116, time = "8s" },
    { spell = 172, time = "21s", stacks = 3 },
    { spell = 703, time = "27s" },
    { spell = 348, time = "5s" },
    { spell = 686, time = "17s", stacks = 2 },
    { spell = 980, time = "24s" },
    { spell = 1022, time = "9s" },
}

local function sampleIcon(spellId)
    local ok, icon = pcall(C_Spell.GetSpellTexture, spellId)
    if ok and icon then
        return icon
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function makeTile()
    local tile = CreateFrame("Frame", nil, frame)
    tile.back = tile:CreateTexture(nil, "BACKGROUND")
    tile.back:SetAllPoints()
    tile.back:SetColorTexture(0, 0, 0, 0.7)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 1, -1)
    tile.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tile.time = tile:CreateFontString(nil, "OVERLAY", "CRTFontHighlight")
    tile.time:SetPoint("TOP", tile, "BOTTOM", 0, -2)
    tile.count = tile:CreateFontString(nil, "OVERLAY", "CRTFontHighlight")
    tile.count:SetPoint("BOTTOMRIGHT", -2, 2)
    tile:Hide()
    return tile
end

local function updateTiles()
    if not frame then
        return
    end
    local size, count = Debuffs:Size(), Debuffs:MaxCount()
    for index = 1, MAX_SLOTS do
        local tile = tiles[index]
        if not tile then
            tile = makeTile()
            tiles[index] = tile
        end
        if previewOn and index <= count then
            local sample = SAMPLES[index]
            tile:SetSize(size, size)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", frame, "TOPLEFT", (index - 1) * (size + GAP), 0)
            tile.icon:SetTexture(sampleIcon(sample.spell))
            tile.time:SetText(sample.time)
            tile.count:SetText(sample.stacks or "")
            tile:Show()
        else
            tile:Hide()
        end
    end
end

-- Regular debuffs (optional second row) -------------------------------------------------

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

local chosen = {}

local function sortOptions()
    local methods, directions = sortEnums()
    local method, methodName = pick(methods, { "Expiration", "ExpirationOnly" })
    local direction, directionName
    if Debuffs:Reverse() then
        direction, directionName = pick(directions, { "Reverse" })
    else
        direction, directionName = pick(directions, { "Normal" })
    end
    chosen.methodName = methodName or "Default"
    chosen.directionName = directionName or "Default"
    return method, direction
end

-- Sets up one aura button: an icon, a cooldown spiral with the time, and the stack count.
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

-- The container's own flow layout, with the values the game lists in CustomAuraContainerLayoutDefaults.
local function applyContainerLayout()
    if not container or InCombatLockdown() then
        return
    end
    local width, size = panelWidth()
    local signature = width .. ":" .. size
    if signature == appliedContainer then
        return
    end
    appliedContainer = signature
    container:SetSize(width, size)
    try("container", container, "SetFlowLayoutAnchorPoint", "TOPLEFT")
    try("container", container, "SetFlowLayoutAxis", 0)
    try("container", container, "SetFlowLayoutGrowthDirection", 1, -1)
    try("container", container, "SetFlowLayoutPadding", 0, 0, 0, 0)
    try("container", container, "SetFlowLayoutMaximumLineSize", width)
    try("container", container, "SetAuraGroupLayout", GROUP, { elementSpacing = GAP })
end

local function createContainer()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    if not ok or not c then
        note("CreateFrame(\"AuraContainer\") failed: " .. tostring(c))
        return false
    end
    container = c
    container:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -REGULAR_ROW_OFFSET)

    try("container", container, "SetUnit", "player")
    local method, direction = sortOptions()
    local options = {
        maxFrameCount = Debuffs:MaxCount(),
        initializeFrame = initializeButton,
        sortMethod = method,
        sortDirection = direction,
        layout = { elementSpacing = GAP },
    }
    report.created = try("container", container, "AddAuraGroup", GROUP, "HARMFUL", options)
    try("container", container, "SetEnabled", true)
    appliedContainer = nil
    applyContainerLayout()
    try("container", container, "UpdateAllAuras")
    return report.created
end

-- Sizes the panel, and the regular row's aura frames. Out of combat only.
local function layout()
    if not frame or InCombatLockdown() then
        return
    end
    local width, size = panelWidth()
    frame:SetSize(width, size)
    addAnchors()
    applyContainerLayout()
    if container then
        local ok, n = pcall(container.GetAuraGroupFrameCount, container, GROUP)
        if ok and type(n) == "number" and not isSecret(n) then
            for index = 1, n do
                local ok2, button = pcall(container.GetAuraGroupFrame, container, GROUP, index)
                if ok2 and button then
                    pcall(button.SetSize, button, size, size)
                end
            end
        end
    end
end

-- Position and visibility -----------------------------------------------------------

local function applyPosition()
    local saved = Debuffs:Position()
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
end

-- Whether you are in combat. InCombatLockdown() is false inside the PLAYER_REGEN_DISABLED handler,
-- because the lockdown only starts after that event fires, so the events set a flag directly and
-- UnitAffectingCombat backs it up.
local function playerInCombat()
    return inCombat or (UnitAffectingCombat("player") and true or false)
end

-- Shows the panel during combat, or always while previewing. Alpha, not Show, because showing and
-- hiding may be blocked in combat. It runs every frame, so a missed event cannot leave it stuck.
local function updateVisibility()
    if not frame then
        return
    end
    local visible = Debuffs:Enabled() and playerInCombat()
    if previewOn then
        visible = true
    end
    local alpha = visible and 1 or 0
    if frame:GetAlpha() ~= alpha then
        frame:SetAlpha(alpha)
    end
    if container then
        local regular = Debuffs:IncludeRegular() and 1 or 0
        if container:GetAlpha() ~= regular then
            container:SetAlpha(regular)
        end
    end
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
    updateTiles()
    updateVisibility()
end

function Panel:SetPreview(on)
    previewOn = on and true or false
    updateTiles()
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
    local width, size = panelWidth()
    frame:SetSize(width, size)
    applyPosition()
    frame:SetAlpha(0)

    -- A drag handle above the panel, shown during a preview. It is a separate frame, not a child,
    -- so it keeps its own visibility.
    handle = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    handle:SetFrameStrata("HIGH")
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
        updateVisibility()
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

-- Text for any value. A secret value is printed as "(secret)", because joining one into text is an
-- error, and the size and position of some frames are secret.
local function safe(value)
    if isSecret(value) then
        return "(secret)"
    end
    return tostring(value)
end

local function describe(value, depth)
    if isSecret(value) then
        return "(secret)"
    end
    local kind = type(value)
    if kind == "table" then
        if depth <= 0 then
            return "{...}"
        end
        local parts = {}
        for k, v in pairs(value) do
            parts[#parts + 1] = safe(k) .. "=" .. describe(v, depth - 1)
            if #parts >= 40 then
                parts[#parts + 1] = "..."
                break
            end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif kind == "function" then
        return "function"
    end
    return safe(value)
end

function Panel:InfoText()
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end

    add("Debuff panel diagnostics")
    add("Game build: " .. tostring(select(4, GetBuildInfo())))
    add("In combat: lockdown " .. tostring(InCombatLockdown()) .. ", flag " .. tostring(inCombat) .. ", UnitAffectingCombat " .. tostring(UnitAffectingCombat("player")) .. "; preview on: " .. tostring(previewOn) .. ", enabled: " .. tostring(Debuffs:Enabled()))
    add(format("Settings: size %d, max %d, dispel icon %s, regular row %s, reverse %s", Debuffs:Size(), Debuffs:MaxCount(), tostring(Debuffs:DispelIcon()), tostring(Debuffs:IncludeRegular()), tostring(Debuffs:Reverse())))
    if frame then
        local point, _, relativePoint, x, y = frame:GetPoint()
        add(format("Panel: alpha %s, shown %s, effective alpha %s, size %s x %s, at %s %s %s,%s",
            safe(frame:GetAlpha()), tostring(frame:IsShown()), safe(frame:GetEffectiveAlpha()),
            safe(frame:GetWidth()), safe(frame:GetHeight()), tostring(point), tostring(relativePoint), safe(x), safe(y)))
    else
        add("Panel: not built")
    end
    if report.error then
        add("Error: " .. report.error)
    end

    -- Private aura slots.
    add("")
    add("Private aura slots (these draw boss mechanic debuffs):")
    add("  C_UnitAuras.AddPrivateAuraAnchor available: " .. tostring(C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor ~= nil))
    local made = 0
    for _ in pairs(anchorIds) do
        made = made + 1
    end
    add("  anchors added: " .. made .. " of " .. Debuffs:MaxCount())
    for index = 1, Debuffs:MaxCount() do
        local slot = slots[index]
        if slot then
            local point, _, _, x, y = slot:GetPoint()
            add(format("  slot %d: anchor id %s, size %s x %s, at %s %s,%s", index, tostring(anchorIds[index]), safe(slot:GetWidth()), safe(slot:GetHeight()), tostring(point), safe(x), safe(y)))
        end
    end

    -- The regular row.
    add("")
    add("Regular debuff row (Blizzard AuraContainer):")
    add("  created: " .. tostring(report.created) .. ", sort: " .. tostring(chosen.methodName) .. " " .. tostring(chosen.directionName))
    if container then
        local count = 0
        local ok, n = pcall(container.GetAuraGroupFrameCount, container, GROUP)
        if ok and not isSecret(n) and type(n) == "number" then
            count = n
        end
        add("  aura frames: " .. count .. ", container alpha " .. safe(container:GetAlpha()))
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
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    if event == "PLAYER_LOGIN" then
        inCombat = UnitAffectingCombat("player") and true or false
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
