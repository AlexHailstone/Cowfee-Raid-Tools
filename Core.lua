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
        buffLock = true, -- grey out your Ready button until everyone has your class's raid buff
        food = "any", -- before 0.13.2: "best" counted only the best food. Ignored now.
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
                weapon = true, -- weapon oil or stone, for players running the addon (0.13.2)
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
-- These four ship with the game. CRT:FontList adds the fonts other addons share through
-- LibSharedMedia-3.0, when one of them has loaded it. Cowfee Raid Tools does not ship the library.
CRT.FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

-- LibSharedMedia-3.0, if another addon loaded it. Its documented calls are List(mediatype) and
-- Fetch(mediatype, key, noDefault), with the media type "font".
local function sharedMedia()
    if not LibStub then
        return nil
    end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibSharedMedia-3.0", true)
    return ok and lib or nil
end

local function samePath(path)
    return ((path or ""):lower():gsub("/", "\\"))
end

-- Every font to choose from: { name, path, shared }. The game's four first, then the shared ones in
-- LibSharedMedia's sorted order, leaving out any that is the same file as one already listed.
function CRT:FontList()
    local out, seen, names = {}, {}, {}
    for _, font in ipairs(self.FONTS) do
        out[#out + 1] = { name = font.name, path = font.path }
        seen[samePath(font.path)] = true
        names[font.name] = true
    end
    local lib = sharedMedia()
    if lib then
        local ok, list = pcall(lib.List, lib, "font")
        if ok and type(list) == "table" then
            for _, name in ipairs(list) do
                local okPath, path = pcall(lib.Fetch, lib, "font", name, true)
                if okPath and type(path) == "string" and not seen[samePath(path)] and not names[name] then
                    out[#out + 1] = { name = name, path = path, shared = true }
                    seen[samePath(path)] = true
                    names[name] = true
                end
            end
        end
    end
    return out
end

-- The file for a font name, or nil for "default" or a shared font that is no longer loaded.
function CRT:FontPath(name)
    if not name or name == "default" then
        return nil
    end
    for _, font in ipairs(self:FontList()) do
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

local function makeFont(name, source, scale)
    local font = CreateFont(name)
    font:CopyFontObject(source)
    local path, size, flags = font:GetFont()
    size = math.floor(size * (scale or CRT.FONT_SCALE) + 0.5)
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
    -- The note windows keep their own font objects, so they redraw with the new font and outline.
    if self.Notes and self.Notes.Fire and self.ready then
        self.Notes:Fire()
    end
end

-- Sets the font for everything the addon draws, the note windows included, from the Addon Settings
-- page after its confirmation box. Each note window can still be given its own font afterwards.
function CRT:SetAddonFont(name)
    self.db.ui.font = name
    local notes = self.db.notes
    for _, key in ipairs({ "window", "assignments", "personal" }) do
        if type(notes[key]) == "table" then
            notes[key].font = name
        end
    end
    self:ApplyFonts()
end

makeFont("CRTFontNormal", GameFontNormal)
makeFont("CRTFontHighlight", GameFontHighlight)
makeFont("CRTFontDisable", GameFontDisable)
makeFont("CRTFontSmall", GameFontHighlightSmall)
makeFont("CRTFontDisableSmall", GameFontDisableSmall)
makeFont("CRTFontLarge", GameFontNormalLarge)
-- The game's own sizes, unscaled, for the small title-bar and page buttons, the standard buttons,
-- the dropdown and slider text, and the edit boxes. They follow the Addon Settings font too.
makeFont("CRTFontButtonSmall", GameFontNormalSmall, 1)
makeFont("CRTFontButtonSmallHighlight", GameFontHighlightSmall, 1)
makeFont("CRTFontButtonSmallDisable", GameFontDisableSmall, 1)
makeFont("CRTFontStandard", GameFontNormal, 1)
makeFont("CRTFontStandardHighlight", GameFontHighlight, 1)
makeFont("CRTFontStandardDisable", GameFontDisable, 1)
makeFont("CRTFontEdit", ChatFontNormal, 1)

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
        self:RegisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGIN" then
        -- Every addon has loaded by now, so a font shared through LibSharedMedia can be found.
        CRT.ready = true
        CRT:ApplyFonts()
    end
end)
