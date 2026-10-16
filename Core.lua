local ADDON, CRT = ...

_G.CRT = CRT
CRT.name = ADDON
CRT.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local defaults = {
    window = { point = "CENTER", x = 0, y = 0, scale = 100 }, -- the main panel; scale is a percent, 50 to 200
    -- The General Settings page. font is "default" (the game's own) or a name from CRT.FONTS, outline is
    -- "", "OUTLINE" or "THICKOUTLINE", fontSize the body text size in points (set the first time from
    -- textSize, the percent used before 0.17.2). style is "game" (the game's window art) or
    -- "minimal" (flat black), bgAlpha the main window's opacity in percent (30 to 100). layers holds a
    -- frame strata for each kind of window moved off its default (UI.LAYERS in UI/Panel.lua).
    -- soundChannel is the game sound channel every sound the addon plays goes through (CRT:PlaySound).
    -- modern is the Modern look (UI:ApplyStyle in UI/Panel.lua); off is the Classic look.
    -- hideRealms leaves realm names out of the Late Tracker and Tattlebot, on screen, in chat and in exports.
    ui = { font = "default", outline = "", textSize = 100, style = "game", bgAlpha = 100, layers = {}, soundChannel = "Master", hideRealms = false, modern = false },
    lastPage = "groups",
    -- The minimap button (UI/Minimap.lua): angle is its place around the minimap, in degrees.
    minimap = { hide = false, angle = 225 },
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
        fadeOnPull = true, -- fade out your bar and the ready check window when a pull timer starts
        earlyPull = true, -- report who entered combat first when it happens before a pull timer ends
        earlyPullOutput = "self", -- where that report goes: "self", "raid" or "officer"
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
        -- sound turns on the game's own low-health pulse (QoL/LowHealthSound.lua), soundVolume is its
        -- volume, and caaSaved holds the game settings it changed, to put back when it is turned off.
        -- soundChoice is "pulse" (the game's own) or a key of LowHealthSound.CHOICES, soundChannel is
        -- "game" (the game's own output) or a sound channel from CRT.SOUND_CHANNELS.
        -- soundOnce plays the sound one time, in full, each time your health drops under the threshold
        -- (off: it repeats). customSounds lists file names in the addon's Sounds folder that the player
        -- added. A soundLength key from a 0.14.0 test build may remain and is ignored.
        lowHealth = { enabled = false, threshold = 35, sound = false, soundVolume = 100, soundChoice = "pulse", soundChannel = "game", soundOnce = true, customSounds = {} },
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
    -- Tattlebot. After each boss pull it reads the game's damage meter for the spells in
    -- Tattlebot/Database.lua. current is tonight, { id, startedAt, lastAt, pulls }, and each pull has
    -- players[key] = { class, spells = { [spellID] = damage } }. history holds the finished nights.
    -- output is "self", "raid" or "officer". maxPlayers is no longer used: chat posts list every
    -- player, on more lines when needed. Each pull keeps every spell's damage (pull.all), and the
    -- reports pick out the tracked ones.
    tattle = {
        enabled = true,
        raidsOnly = true,
        avoidable = false, -- also count what the game's meter marks as avoidable damage
        autoPost = false, -- post each pull's report when it is read (to chat only for the raid leader)
        output = "self",
        maxPlayers = 10,
        custom = {}, -- the player's own tracked spells, [spellID] = mechanic name ("" for the spell's name)
        season = "Season 1", -- the season new nights are filed under, for the History filter
        history = {},
        nextId = 1,
    },
    -- Timeline. Boss pulls recorded for the Timeline page (Timeline/Data.lua). bosses[encounterID] =
    -- { name, pulls = { newest last } }, and each pull has the boss casts and the deaths in seconds
    -- from the pull start. rows[encounterID] holds the player's hidden and added spell rows.
    timeline = {
        record = true,
        minPull = 15, -- seconds; shorter pulls are not kept
        keep = 10, -- pulls kept per boss
        bosses = {},
        rows = {}, -- [encounterID] = { hidden = { [spellID] = true }, custom = { spellID, ... } }
        span = 300, -- seconds visible
        grid = 30,
        iconSize = 22,
        deathRows = "combined", -- or "player"
        roles = { TANK = true, HEALER = true, DAMAGER = true },
        firstDeaths = 0, -- show only the first N deaths, 0 for all
        overlay = 3, -- how many pulls the death overlay covers
        overlayOn = false, -- draw the deaths of recent pulls over the shown one
        hideEmpty = false, -- hide rows that have no casts in the shown pull
        -- The pop-out window (Timeline/Page.lua): its size, and its position once it is moved.
        popout = { width = 1200, height = 600 },
        references = {}, -- the player's own reference timelines, { id, text } (Timeline/Reference.lua)
        nextRef = 1,
        nextId = 1,
    },
    -- Alerts. Reminders, phase events and bar settings for the alerts engine (Alerts/Engine.lua).
    -- reminders are the player's own timed reminders, phases the phase events they set up, overrides
    -- their changes to shared packs, and nextId numbers them. The bars window position is added when moved.
    -- areas are the icon, text and circle areas' settings (Alerts/Areas.lua); position is added when moved.
    -- Marker displays (Markers/Display.lua): disabled[encounterID] is true for a boss whose display
    -- you turned off on the Reminders tab; position is added when the window is moved.
    markers = { disabled = {} },
    alerts = {
        bars = { shown = true, noteLines = true, cap = 5, ahead = 20, width = 240, height = 20 },
        areas = {
            icons = { shown = true, cap = 5, size = 44, font = "Friz Quadrata", fontSize = 20, outline = "OUTLINE", grow = "down", showText = true },
            texts = { shown = true, cap = 3, font = "Friz Quadrata", fontSize = 36, outline = "THICKOUTLINE", grow = "down", align = "CENTER" },
            circles = { shown = true, cap = 3, size = 64, fontSize = 16, grow = "right" },
        },
        reminders = {},
        phases = {},
        overrides = {},
        nextId = 1,
    },
}

-- Profiles.lua reads these to know which keys a profile holds and to start a profile afresh.
CRT.defaults = defaults

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

-- The fonts the addon offers: on the General Settings page for all its text, and for each note window.
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

-- The Modern look's coffee colors, { r, g, b }. UI/Panel.lua paints the window with them and
-- CRT:ApplyFonts colors the text.
CRT.MOCHA = {
    espresso = { 0.11, 0.078, 0.063 }, -- the window background
    roast = { 0.165, 0.122, 0.098 }, -- menu blocks, fields and buttons
    edge = { 0.30, 0.235, 0.188 }, -- borders
    mocha = { 0.44, 0.31, 0.22 }, -- the selected page and tab
    caramel = { 0.78, 0.56, 0.36 }, -- lines and accents
    latte = { 0.87, 0.73, 0.56 }, -- headings and button text (the game's gold text)
    cream = { 0.95, 0.90, 0.84 }, -- body text (the game's white text)
}
-- The Modern look's font, when the font setting is the default.
CRT.MODERN_FONT = "Fonts\\ARIALN.TTF"

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
    local r, g, b = font:GetTextColor()
    fonts[#fonts + 1] = { object = font, path = path, size = size, flags = flags or "", color = { r, g, b } }
    return font
end

-- Applies the General Settings page's font, outline and text size to every shared font. Text drawn
-- with them changes straight away.
function CRT:ApplyFonts()
    local s = self.db and self.db.ui
    if not s then
        return
    end
    -- Text size is fontSize, the body text size in points (8 to 22); headings and small text keep
    -- their sizes relative to it. Before 0.17.2 it was textSize, a percent, which becomes the nearest
    -- point size the first time.
    if not s.fontSize then
        s.fontSize = math.max(8, math.min(22, math.floor(self.BODY_SIZE * (s.textSize or 100) / 100 + 0.5)))
    end
    local factor = s.fontSize / self.BODY_SIZE
    local modern = s.modern
    -- Arial Narrow is drawn smaller than the game's font at the same size, so Modern sizes it up a step.
    local modernDefault = modern and not self:FontPath(s.font)
    for _, f in ipairs(fonts) do
        local path = self:FontPath(s.font) or (modern and self.MODERN_FONT) or f.path
        local flags = s.outline or ""
        if flags == "" then
            flags = f.flags
        end
        local size = f.size * factor * (modernDefault and 1.1 or 1)
        f.object:SetFont(path, math.floor(size + 0.5), flags)
        -- Modern: the game's gold text turns latte and its white text cream; grey stays grey.
        local r, g, b = f.color[1], f.color[2], f.color[3]
        if modern and r and r > 0.9 then
            local c = (g > 0.9 and b > 0.9) and self.MOCHA.cream or (b < 0.2 and self.MOCHA.latte) or nil
            if c then
                r, g, b = c[1], c[2], c[3]
            end
        end
        if r then
            f.object:SetTextColor(r, g, b)
        end
    end
    -- The note windows keep their own font objects, so they redraw with the new font and outline.
    if self.Notes and self.Notes.Fire and self.ready then
        self.Notes:Fire()
    end
end

-- Sets the font for everything the addon draws, the note windows included, from the General Settings
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
-- The body text size in points at the default text size: the game's normal font scaled up.
CRT.BODY_SIZE = fonts[1].size
makeFont("CRTFontHighlight", GameFontHighlight)
makeFont("CRTFontDisable", GameFontDisable)
makeFont("CRTFontSmall", GameFontHighlightSmall)
makeFont("CRTFontDisableSmall", GameFontDisableSmall)
makeFont("CRTFontLarge", GameFontNormalLarge)
-- The game's own sizes, unscaled, for the small title-bar and page buttons, the standard buttons,
-- the dropdown and slider text, and the edit boxes. They follow the General Settings font too.
makeFont("CRTFontButtonSmall", GameFontNormalSmall, 1)
makeFont("CRTFontButtonSmallHighlight", GameFontHighlightSmall, 1)
makeFont("CRTFontButtonSmallDisable", GameFontDisableSmall, 1)
makeFont("CRTFontStandard", GameFontNormal, 1)
makeFont("CRTFontStandardHighlight", GameFontHighlight, 1)
makeFont("CRTFontStandardDisable", GameFontDisable, 1)
makeFont("CRTFontEdit", ChatFontNormal, 1)

-- The game's sound channels a sound can play through, for the General Settings page.
CRT.SOUND_CHANNELS = {
    { key = "Master", label = "Master" },
    { key = "SFX", label = "Sound effects" },
    { key = "Dialog", label = "Dialog" },
    { key = "Ambience", label = "Ambience" },
    { key = "Music", label = "Music" },
    { key = "Talking Head", label = "Talking head" },
}

-- Plays a sound kit through the channel chosen on the General Settings page. Every sound the addon plays
-- goes through here. Returns the sound handle, to stop it with StopSound.
function CRT:PlaySound(kit)
    local channel = (self.db and self.db.ui and self.db.ui.soundChannel) or "Master"
    local ok, willPlay, handle = pcall(PlaySound, kit, channel)
    if ok and willPlay then
        return handle
    end
    return nil
end

function CRT:Print(msg)
    print("|cffc8a050Cowfee Raid Tools|r: " .. tostring(msg))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        CRTDB = CRTDB or {}
        -- Puts this character's profile on top of CRTDB before anything reads it.
        CRT.Profiles:Load()
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
