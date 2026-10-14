local ADDON, CRT = ...

-- The note window: the active note on screen. Before a pull it lists every timer by phase. During a fight
-- each line counts down, lines for you are marked, and lines whose time has passed disappear. The free
-- text of the note sits underneath. Font, size, transparency and position are per player.

local Notes = CRT.Notes
local Engine = CRT.NoteEngine
local Window = {}
CRT.NoteWindow = Window

local REFRESH_SECONDS = 0.1

Window.FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

local frame, handle, title, body
local previewOn = false
local elapsed = 0
local lastText
local noteFont

local function settings()
    return Notes:Window()
end

local function fontPath()
    local wanted = settings().font
    for _, font in ipairs(Window.FONTS) do
        if font.name == wanted then
            return font.path
        end
    end
    return Window.FONTS[1].path
end

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

local function names(item)
    local parts = {}
    for _, tag in ipairs(item.tags) do
        local class = classOf(tag)
        local color = class and RAID_CLASS_COLORS[class]
        if color and color.colorStr then
            parts[#parts + 1] = "|c" .. color.colorStr .. tag .. "|r"
        else
            parts[#parts + 1] = tag
        end
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

local function line(item, seconds)
    local mine = Engine:IsMine(item)
    local time = fmtTime(seconds)
    if mine then
        return "|cffffd100> " .. time .. "|r  " .. describe(item) .. "  " .. names(item)
    end
    return "|cffaaaaaa" .. time .. "|r  " .. describe(item) .. "  " .. names(item)
end

local SAMPLE = "|cffffd100> 0:03|r  Avenging Wrath  Crazyoio\n|cffaaaaaa0:06|r  Sample spell  Cheoeqar\n|cffaaaaaa0:34|r  |cff00ffffGroup 1 go in|r  Cheoeqar Djaztech\n\nRealm Group 1: Cheoeqar Djaztech Gadios"

local function buildText()
    local _, record, note = Notes:Active()
    if not note then
        return previewOn and SAMPLE or "No note loaded.", previewOn and "Raid note (sample)" or "Raid note"
    end
    local lines = {}
    local heading = record.name .. (record.difficulty and (" (" .. record.difficulty .. ")") or "")

    if Engine.running and Engine:Note() == note then
        local phase = Engine:CurrentPhase()
        heading = heading .. "   Phase " .. tostring(phase) .. "   " .. fmtTime(Engine:Elapsed() or 0)
        local waiting = {}
        for _, item in ipairs(note.timers) do
            local remaining = Engine:Remaining(item)
            if remaining == nil then
                waiting[item.ph] = true
            elseif not (settings().hidePassed and remaining < -(item.dur or 0)) then
                lines[#lines + 1] = line(item, remaining)
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
            if item.ph ~= lastPhase then
                lines[#lines + 1] = "|cffffd100Phase " .. item.ph .. "|r"
                lastPhase = item.ph
            end
            lines[#lines + 1] = line(item, item.time)
        end
    end

    if #note.lines > 0 then
        lines[#lines + 1] = ""
        for _, text in ipairs(note.lines) do
            lines[#lines + 1] = text
        end
    end
    return table.concat(lines, "\n"), heading
end

-- Font, size and transparency from the settings.
function Window:ApplyStyle()
    if not frame then
        return
    end
    local s = settings()
    noteFont:SetFont(fontPath(), s.fontSize or 14, "")
    frame:SetSize(s.width or 420, s.height or 300)
    frame:SetAlpha((s.alpha or 100) / 100)
    frame:SetBackdropColor(0, 0, 0, (s.bgAlpha or 50) / 100)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, (s.bgAlpha or 50) / 100)
    lastText = nil
end

function Window:Refresh()
    if not frame then
        return
    end
    local _, record = Notes:Active()
    local visible = previewOn or (settings().shown and record ~= nil)
    frame:SetShown(visible)
    handle:SetShown(previewOn)
    if not visible then
        return
    end
    local text, heading = buildText()
    title:SetText(heading)
    if text ~= lastText then
        body:SetText(text)
        lastText = text
    end
end

local function applyPosition()
    local p = settings().position or { point = "LEFT", relativePoint = "LEFT", x = 40, y = 80 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
end

function Window:ResetPosition()
    settings().position = nil
    if frame then
        applyPosition()
    end
end

local function build()
    if frame then
        return
    end
    noteFont = CreateFont("CRTNoteFont")
    noteFont:CopyFontObject(GameFontHighlight)

    frame = CreateFrame("Frame", "CowfeeRaidToolsNoteWindow", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    title = frame:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetPoint("TOPRIGHT", -8, -6)
    title:SetJustifyH("LEFT")

    body = frame:CreateFontString(nil, "OVERLAY")
    body:SetFontObject(noteFont)
    body:SetPoint("TOPLEFT", 8, -28)
    body:SetPoint("BOTTOMRIGHT", -8, 8)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetShadowOffset(1, -1)

    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    handle:SetBackdropColor(0.1, 0.25, 0.1, 0.9)
    handle:SetBackdropBorderColor(0.3, 0.9, 0.3, 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("CENTER")
    text:SetText("Raid note: drag to move")
    handle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        settings().position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    handle:Hide()

    applyPosition()
    Window:ApplyStyle()
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < REFRESH_SECONDS then
            return
        end
        elapsed = 0
        Window:Refresh()
    end)
    frame:Hide()
end

-- The window has its own updater, but it is hidden when there is nothing to show, so this frame keeps
-- checking whether it should appear.
local watcher = CreateFrame("Frame")
local watchElapsed = 0
watcher:SetScript("OnUpdate", function(_, dt)
    watchElapsed = watchElapsed + dt
    if watchElapsed < 0.5 then
        return
    end
    watchElapsed = 0
    if frame and not frame:IsShown() then
        Window:Refresh()
    end
end)

watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
    build()
    Window:Refresh()
end)

Notes:OnChange(function()
    if frame then
        Window:ApplyStyle()
        Window:Refresh()
    end
end)

CRT.UI:RegisterPreview("note", function(on)
    build()
    previewOn = on and true or false
    lastText = nil
    Window:Refresh()
end)
