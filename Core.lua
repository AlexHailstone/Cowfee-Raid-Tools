local ADDON, CRT = ...

_G.CRT = CRT
CRT.name = ADDON
CRT.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local defaults = {
    window = { point = "CENTER", x = 0, y = 0 },
    lastPage = "groups",
    classCache = {},
    roleCache = {},
    groups = {
        presets = {},
        nextId = 1,
        keepChanges = true,
        source = "raid",
        working = {},
    },
    -- The consumables list ships in Consumables/Database.lua. Players choose the order
    -- (categoryOrder is the icon order, itemOrder[category] is which item is used first) and
    -- may add their own items. An older "categories" key from version 0.2.0 may remain in
    -- saved data and is ignored.
    consumables = {
        enabled = true,
        lowMinutes = 10,
        categoryOrder = {},
        itemOrder = {},
        extra = {}, -- the player's own additions, { { item, name }, ... } per category
        learned = {}, -- buffs worked out from use, itemId -> spellId
        -- position = { point, relativePoint, x, y } is added when the bar is moved. Without it the
        -- bar sits above the ready check dialog.
    },
    -- The in-combat debuff panel. Every player has their own copy of these in their own saved
    -- variables, so nothing here is shared between players. position is added when it is moved.
    debuffs = {
        enabled = true,
        size = 44, -- icon size in pixels
        maxCount = 4, -- how many to show at once
        dispelIcon = false, -- show the dispel type icon on mechanic debuffs
        includeRegular = false, -- also show regular (not boss mechanic) debuffs in a second row
    },
    -- Raid notes. list[id] holds each imported or received note. window and alert hold the
    -- note window and personal alert settings, with position added when they are moved.
    notes = {
        list = {},
        nextId = 1,
        trustedOnly = true, -- only accept shared notes from the raid leader or assistants
        window = { -- the timers
            shown = true,
            locked = true,
            hidePassed = true,
            onlyMe = false, -- show only your lines: your name, role, raid group, everyone, or no tag
            fontSize = 14,
            alpha = 100, -- percent
            bgAlpha = 50, -- percent
            width = 420,
            height = 300,
            font = "Friz Quadrata",
        },
        assignments = { -- the note's text that is not a timer
            shown = true,
            locked = true,
            fontSize = 14,
            alpha = 100,
            bgAlpha = 50,
            width = 360,
            height = 240,
            font = "Friz Quadrata",
        },
        personal = { -- your own personal note
            shown = true,
            locked = true,
            fontSize = 14,
            alpha = 100,
            bgAlpha = 50,
            width = 300,
            height = 180,
            font = "Friz Quadrata",
        },
        personalText = "",
        alert = {
            enabled = true,
            seconds = 10, -- show your next spell this many seconds early
            tts = true,
            ttsSeconds = 3, -- read it out at this many seconds left
            ttsVolume = 100,
            ttsRate = 0,
        },
    },
    -- The late tracker. days[wday] is true for raid days (1 is Sunday, as date() counts them), and
    -- hour and minute are the start on this computer's clock. layoutId is the Raid Groups layout
    -- that lists who is expected. current is the running night, history the finished ones.
    late = {
        days = {},
        hour = 20,
        minute = 0,
        grace = 0, -- minutes after the start before someone counts as late
        history = {},
        nextId = 1,
        lastAuto = "", -- the day the schedule last started (or skipped) a night
    },
}

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Shared font objects: Blizzard's fonts scaled up so every label, button and list is easier to read.
CRT.FONT_SCALE = 1.2

local function makeFont(name, source)
    local font = CreateFont(name)
    font:CopyFontObject(source)
    local path, size, flags = font:GetFont()
    -- SetFont's third argument is no longer optional (12.0.5), so pass "" when there are no flags.
    font:SetFont(path, math.floor(size * CRT.FONT_SCALE + 0.5), flags or "")
    return font
end

makeFont("CRTFontNormal", GameFontNormal)
makeFont("CRTFontHighlight", GameFontHighlight)
makeFont("CRTFontDisable", GameFontDisable)
makeFont("CRTFontSmall", GameFontHighlightSmall)
makeFont("CRTFontDisableSmall", GameFontDisableSmall)
makeFont("CRTFontLarge", GameFontNormalLarge)

function CRT:Print(msg)
    print("|cffc8a050Cowfee Raid Tools|r: " .. tostring(msg))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        CRTDB = CRTDB or {}
        copyDefaults(defaults, CRTDB)
        CRT.db = CRTDB
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
