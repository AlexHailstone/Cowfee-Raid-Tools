local ADDON, CRT = ...

_G.CRT = CRT
CRT.name = ADDON
CRT.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local defaults = {
    window = { point = "CENTER", x = 0, y = 0, scale = 100 }, -- the main panel; scale is a percent, 50 to 200
    -- The Addon Settings page. font is "default" (the game's own) or a name from CRT.FONTS, outline is
    -- "", "OUTLINE" or "THICKOUTLINE", textSize a percent. style is "game" (the game's window art) or
    -- "minimal" (flat black), bgAlpha the main window background's opacity in percent. layers holds a
    -- frame strata for each kind of window moved off its default (UI.LAYERS in UI/Panel.lua).
    ui = { font = "default", outline = "", textSize = 100, style = "game", bgAlpha = 100, layers = {} },
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
        notStarter = false, -- true hides your bar on a ready check you started yourself
        lowMinutes = 10,
        categoryOrder = {},
        itemOrder = {},
        extra = {}, -- the player's own additions, { { item, name }, ... } per category
        learned = {}, -- buffs worked out from use, itemId -> spellId
        -- position = { point, relativePoint, x, y } is added when the bar is moved. Without it the
        -- bar sits above the ready check dialog.
    },
    -- The Ready Check page: the raid report of everyone's consumables and raid buffs. output is
    -- "self", "raid" or "officer". food is "any" or "best". flaskWarn is minutes, 0 for off.
    readycheck = {
        tab = "window",
        auto = true,
        onPull = false,
        output = "self",
        raidsOnly = true,
        notLFR = true,
        include = { food = true, flask = true, rune = true, vantus = false, buffs = true },
        food = "any",
        flaskWarn = 5,
        lowFlask = true,
        -- The ready check window. columns[key] shows that column, order is their left-to-right order.
        -- position is added when it is moved.
        window = {
            enabled = true,
            leadOnly = true, -- only open it for the raid leader and assistants
            seconds = 30,
            scale = 100, -- percent
            groupBuffsOnly = true, -- raid buff columns only for buffs your group can give
            order = {}, -- column keys left to right, filled in when a column is moved
            sort = "group", -- players by "group", "role" or "name"
            classBars = true, -- a class colored bar behind each player's row
            columns = {
                food = true, flask = true, rune = true, vantus = false,
                intellect = true, stamina = true, attack = true, versatility = true, mastery = true, movement = true,
                durability = true,
            },
        },
    },
    -- The in-combat debuff panel. Every player has their own copy of these in their own saved
    -- variables, so nothing here is shared between players. position is added when it is moved.
    debuffs = {
        enabled = true,
        size = 44, -- icon size in pixels
        maxCount = 4, -- how many to show at once
        dispelIcon = false, -- show the dispel type icon on mechanic debuffs
        includeRegular = false, -- also show regular (not boss mechanic) debuffs in a second row
        -- The look: only what the game lets an addon pass to its own debuff icons.
        swipe = true, -- the dark swipe that sweeps over the icon as the debuff runs out
        swipeEdge = true, -- the bright line on the swipe's edge
        -- The timer: below, above, left, right or center (the game's timer text there), numbers (the
        -- game's countdown numbers on the swipe instead) or hidden. A countdownNumbers key saved
        -- before 0.13.1 may remain and is ignored.
        timerPosition = "below",
        timerX = 0, -- nudges the timer text, in pixels
        timerY = 0,
        borderScale = 1, -- the game's debuff border is the icon plus 5 x this many pixels, 0 to 6
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
            iconPosition = "left", -- the spell icon: left, right, above or below the text
        },
    },
    -- Quality of Life options. lowHealth is the experimental low-health alert: threshold is the health
    -- percent at or under which the banner shows. position is added when the banner is moved.
    qol = {
        lowHealth = { enabled = false, threshold = 35 },
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

-- The fonts the addon offers: on the Addon Settings page for all its text, and for each note window.
-- All four ship with the game.
CRT.FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

function CRT:FontPath(name)
    for _, font in ipairs(self.FONTS) do
        if font.name == name then
            return font.path
        end
    end
    return nil
end

-- Shared font objects: Blizzard's fonts scaled up so every label, button and list is easier to read.
-- Every text the addon draws uses one of these, so CRT:ApplyFonts changes all of it at once.
CRT.FONT_SCALE = 1.2
local fonts = {} -- { object, path, size, flags }: each font object and the game font it started as

local function makeFont(name, source)
    local font = CreateFont(name)
    font:CopyFontObject(source)
    local path, size, flags = font:GetFont()
    size = math.floor(size * CRT.FONT_SCALE + 0.5)
    -- SetFont's third argument is no longer optional (12.0.5), so pass "" when there are no flags.
    font:SetFont(path, size, flags or "")
    fonts[#fonts + 1] = { object = font, path = path, size = size, flags = flags or "" }
    return font
end

-- Applies the Addon Settings page's font, outline and text size to every shared font. Text drawn
-- with them changes straight away.
function CRT:ApplyFonts()
    local s = self.db and self.db.ui
    if not s then
        return
    end
    local factor = (s.textSize or 100) / 100
    for _, f in ipairs(fonts) do
        local path = self:FontPath(s.font) or f.path
        local flags = s.outline or ""
        if flags == "" then
            flags = f.flags
        end
        f.object:SetFont(path, math.floor(f.size * factor + 0.5), flags)
    end
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
        CRT:ApplyFonts()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
