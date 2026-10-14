local ADDON, CRT = ...

-- The three note windows, built from one shared design:
--   window       the timers of the note in use. Before the pull it lists every timer by phase. During the
--                fight each line counts down and disappears once its time has passed.
--   assignments  the note's text that is not a timer, such as "Kick order" and the names under it.
--   personal     your own personal note, typed on the Raid Notes page. Only you see it.
-- Each window has its own font, size, transparency, position and size, saved per player in CRTDB.notes.
-- Unlocked, a window can be dragged to move it and resized from its bottom-right corner. Locked, it lets
-- clicks through. Names are class colored, and a line for you (your name or your role) is marked.

local Notes = CRT.Notes
local Engine = CRT.NoteEngine
local NoteWindow = { windows = {} }
CRT.NoteWindow = NoteWindow

local REFRESH_SECONDS = 0.1
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber"
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

-- The same list as the Addon Settings page's font choice, in Core.lua.
NoteWindow.FONTS = CRT.FONTS

local previewOn = false

-- The windows' text is rebuilt only when something it shows may have changed: the note, the settings,
-- the group, your role, or previews. contentVersion goes up on each of those, and a window rebuilds
-- when it has not drawn the current version. The timers window also rebuilds every refresh while a
-- note is running, for the countdown. A rebuild every few seconds anyway catches anything missed.
local contentVersion = 1
local SAFETY_SECONDS = 5
local function changed()
    contentVersion = contentVersion + 1
end

-- Text helpers --------------------------------------------------------------------------

local function fmtTime(seconds)
    if seconds < 0 then
        seconds = 0
    end
    return format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function hex(color)
    if not color then
        return "ffffff"
    end
    return format("%02x%02x%02x", math.floor((color[1] or 1) * 255), math.floor((color[2] or 1) * 255), math.floor((color[3] or 1) * 255))
end

-- Short name -> class, from the class cache, rebuilt every few seconds.
local shortClass, shortClassAt = {}, 0
local function classOf(word)
    if GetTime() - shortClassAt > 5 then
        shortClass, shortClassAt = {}, GetTime()
        for key, class in pairs(CRT.db.classCache or {}) do
            local short = key:match("^[^-]+")
            if short and not shortClass[short] then
                shortClass[short] = class
            end
        end
    end
    return shortClass[(word:lower():gsub("%-.*$", ""))]
end

local function colorName(word)
    local class = classOf(word)
    local color = class and RAID_CLASS_COLORS[class]
    if color and color.colorStr then
        return "|c" .. color.colorStr .. word .. "|r"
    end
    return word
end

local function names(item)
    local parts = {}
    for _, tag in ipairs(item.tags) do
        parts[#parts + 1] = colorName(tag)
    end
    return table.concat(parts, " ")
end

local function describe(item)
    if item.kind == "spell" then
        local info = Notes:SpellInfo(item.spellId)
        local icon = info and info.icon and ("|T" .. info.icon .. ":0|t ") or ""
        return icon .. (info and info.name or ("Spell " .. item.spellId))
    end
    return "|cff" .. hex(item.color) .. (item.text or "") .. "|r"
end

local function timerLine(item, seconds)
    local time = fmtTime(seconds)
    if Engine:IsMine(item) then
        return "|cffffd100> " .. time .. "|r  " .. describe(item) .. "  " .. names(item)
    end
    return "|cffaaaaaa" .. time .. "|r  " .. describe(item) .. "  " .. names(item)
end

-- A line of free text: names class colored, your own name in gold, and the line marked with ">" when it
-- names you or your role. A line with no colon is treated as a heading.
local function textLine(line)
    if line == "" then
        return ""
    end
    local mine = false
    local myName = (UnitName("player") or ""):lower()
    local colored = line:gsub("[%w\128-\255]+", function(word)
        if Engine:WordIsMe(word) then
            mine = true
        end
        if word:lower() == myName then
            return "|cffffd100" .. word .. "|r"
        end
        return colorName(word)
    end)
    if not line:find(":", 1, true) then
        colored = "|cffffd100" .. colored .. "|r"
    end
    if mine then
        return "|cffffd100> |r" .. colored
    end
    return colored
end

local function textBlock(lines)
    local out = {}
    for _, line in ipairs(lines) do
        out[#out + 1] = textLine(line)
    end
    return table.concat(out, "\n")
end

-- Formats lines of free text the way the assignments and personal windows show them.
NoteWindow.FormatText = textBlock

local function splitLines(text)
    local lines = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    return lines
end

-- What each window shows: returns text, heading, hasContent ------------------------------------

local function timersText()
    local _, record, note = Notes:Active()
    if not note then
        if previewOn then
            return "|cffffd100> 0:03|r  Avenging Wrath  Crazyoio\n|cffaaaaaa0:06|r  Sample spell  Cheoeqar\n|cffaaaaaa0:48|r  |cff00ffffGroup 1 go in|r  Cheoeqar Djaztech", "Raid note (sample)", true
        end
        return "No note loaded.", "Raid note", false
    end
    local lines = {}
    local heading = record.name .. (record.difficulty and (" (" .. record.difficulty .. ")") or "")
    -- "Show only me" keeps your lines, your group's and role's, and lines with no tag.
    local onlyMe = Notes:WindowSettings("window").onlyMe
    local function shown(item)
        return not onlyMe or Engine:IsForMe(item)
    end
    if onlyMe then
        heading = heading .. "   |cffffd100only me|r"
    end
    if Engine.running and Engine:Note() == note then
        heading = heading .. "   Phase " .. tostring(Engine:CurrentPhase()) .. "   " .. fmtTime(Engine:Elapsed() or 0)
        local waiting = {}
        for _, item in ipairs(note.timers) do
            local remaining = Engine:Remaining(item)
            if remaining == nil then
                waiting[item.ph] = true
            elseif shown(item) and not (Notes:WindowSettings("window").hidePassed and remaining < -(item.dur or 0)) then
                lines[#lines + 1] = timerLine(item, remaining)
            end
        end
        for _, ph in ipairs(note.phases) do
            if waiting[ph] then
                lines[#lines + 1] = "|cff777777Phase " .. ph .. " starts on Next phase|r"
            end
        end
    else
        local lastPhase
        for _, item in ipairs(note.timers) do
            if shown(item) then
                if item.ph ~= lastPhase then
                    lines[#lines + 1] = "|cffffd100Phase " .. item.ph .. "|r"
                    lastPhase = item.ph
                end
                lines[#lines + 1] = timerLine(item, item.time)
            end
        end
    end
    if onlyMe and #lines == 0 and #note.timers > 0 then
        lines[1] = "|cff777777Nothing in this note is for you. Untick Show only me to see every line.|r"
    end
    return table.concat(lines, "\n"), heading, #note.timers > 0
end

local SAMPLE_ASSIGNMENTS = {
    "Soulcoil Well Realm Groups",
    "Realm Group 1: Cheoeqar Djaztech Gadios",
    "",
    "Kick order",
    "Kicks G1: Teronhorefnd Gadios",
}

local function assignmentsText()
    local _, record, note = Notes:Active()
    if note and #note.lines > 0 then
        return textBlock(note.lines), "Assignments: " .. record.name, true
    end
    if previewOn then
        return textBlock(SAMPLE_ASSIGNMENTS), "Assignments (sample)", true
    end
    return "", "Assignments", false
end

local function personalText()
    local lines = splitLines(Notes:Personal())
    if #lines > 0 then
        return textBlock(lines), "Personal note", true
    end
    if previewOn then
        return "Your personal note shows here.\nWrite it on the Raid Notes page.", "Personal note (sample)", true
    end
    return "", "Personal note", false
end

-- One window --------------------------------------------------------------------------------

-- A note window's font: the one picked for it (from CRT:FontList), or the game's own for "default"
-- or a shared font that is no longer loaded.
local function fontPath(name)
    return CRT:FontPath(name) or (GameFontHighlight:GetFont())
end

local function createWindow(key, defaultPosition, build)
    local w = { key = key }
    local function s()
        return Notes:WindowSettings(key)
    end

    local frame = CreateFrame("Frame", "CowfeeRaidToolsNote_" .. key, UIParent, "BackdropTemplate")
    CRT.UI:RegisterLayer("notes", frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(160, 60, 1400, 1100)
    end
    if frame.SetDontSavePosition then
        pcall(frame.SetDontSavePosition, frame, true)
    end
    frame:SetBackdrop(BACKDROP)
    frame:RegisterForDrag("LeftButton")
    w.frame = frame

    local font = CreateFont("CRTNoteFont_" .. key)
    font:CopyFontObject(GameFontHighlight)

    local title = frame:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetPoint("TOPRIGHT", -8, -6)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local body = frame:CreateFontString(nil, "OVERLAY")
    body:SetFontObject(font)
    body:SetPoint("TOPLEFT", 8, -28)
    body:SetPoint("BOTTOMRIGHT", -8, 8)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetShadowOffset(1, -1)

    local hint = frame:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 8, 6)
    hint:SetText("Unlocked: drag to move, drag the corner to resize")

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture(GRIP .. "-Up")
    grip:SetHighlightTexture(GRIP .. "-Highlight")
    grip:SetPushedTexture(GRIP .. "-Down")

    local function save()
        local point, _, relativePoint, x, y = frame:GetPoint()
        local settings = s()
        settings.position = { point = point, relativePoint = relativePoint, x = x, y = y }
        settings.width = math.floor(frame:GetWidth() + 0.5)
        settings.height = math.floor(frame:GetHeight() + 0.5)
    end

    local function unlocked()
        return previewOn or not s().locked
    end

    frame:SetScript("OnDragStart", function()
        if unlocked() then
            frame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        save()
    end)
    grip:SetScript("OnMouseDown", function()
        if unlocked() then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        save()
        w.lastText = nil
    end)

    function w:ApplyPosition()
        local p = s().position or defaultPosition
        frame:ClearAllPoints()
        frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
    end

    function w:ApplyStyle()
        local settings = s()
        font:SetFont(fontPath(settings.font), settings.fontSize or 14, CRT.db.ui.outline or "")
        frame:SetSize(settings.width or 360, settings.height or 240)
        frame:SetAlpha((settings.alpha or 100) / 100)
        local bg = (settings.bgAlpha or 50) / 100
        frame:SetBackdropColor(0, 0, 0, bg)
        local open = unlocked()
        if open then
            frame:SetBackdropBorderColor(0.3, 0.9, 0.3, 1)
        else
            frame:SetBackdropBorderColor(0.3, 0.3, 0.3, bg)
        end
        -- Locked windows let clicks through to the game.
        frame:EnableMouse(open)
        grip:SetShown(open)
        hint:SetShown(open)
        self.lastText = nil
    end

    function w:Refresh()
        local live = key == "window" and Engine.running or false
        if not live and not self.wasLive and self.drawnVersion == contentVersion and GetTime() - (self.drawnAt or 0) < SAFETY_SECONDS then
            return
        end
        self.wasLive = live
        self.drawnVersion = contentVersion
        self.drawnAt = GetTime()
        local text, heading, hasContent = build()
        local visible = previewOn or (s().shown and hasContent)
        frame:SetShown(visible and true or false)
        if not visible then
            return
        end
        title:SetText(heading)
        if text ~= self.lastText then
            body:SetText(text)
            self.lastText = text
        end
    end

    function w:ResetPosition()
        s().position = nil
        self:ApplyPosition()
    end

    w:ApplyPosition()
    w:ApplyStyle()
    frame:Hide()
    return w
end

-- Public -------------------------------------------------------------------------------------

function NoteWindow:Get(key)
    return self.windows[key]
end

function NoteWindow:ResetPosition(key)
    local w = self.windows[key]
    if w then
        w:ResetPosition()
    end
end

function NoteWindow:RefreshAll()
    for _, w in pairs(self.windows) do
        w:Refresh()
    end
end

local function styleAll()
    for _, w in pairs(NoteWindow.windows) do
        w:ApplyStyle()
        w:Refresh()
    end
end

local built = false
local function build()
    if built then
        return
    end
    built = true
    NoteWindow.windows.window = createWindow("window", { point = "LEFT", relativePoint = "LEFT", x = 40, y = 120 }, timersText)
    NoteWindow.windows.assignments = createWindow("assignments", { point = "LEFT", relativePoint = "LEFT", x = 40, y = -170 }, assignmentsText)
    NoteWindow.windows.personal = createWindow("personal", { point = "RIGHT", relativePoint = "RIGHT", x = -60, y = -60 }, personalText)
end

-- One updater for all three. Timers need a quick refresh, and the others are cheap.
local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    if not built then
        return
    end
    elapsed = elapsed + dt
    if elapsed < REFRESH_SECONDS then
        return
    end
    elapsed = 0
    NoteWindow:RefreshAll()
end)
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("PLAYER_ROLES_ASSIGNED")
driver:SetScript("OnEvent", function(_, event)
    changed()
    if event == "PLAYER_LOGIN" then
        build()
        styleAll()
    end
end)

Notes:OnChange(function()
    changed()
    if built then
        styleAll()
    end
end)

CRT.UI:RegisterPreview("note", function(on)
    build()
    previewOn = on and true or false
    changed()
    styleAll()
end)
