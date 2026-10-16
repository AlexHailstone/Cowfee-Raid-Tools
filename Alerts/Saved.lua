local ADDON, CRT = ...

-- Saved alerts: one alert's setup without its time, kept to place on any boss's Timeline or to open in
-- the alert editor. Stored in CRT.db.alerts.saved[id] (ids from nextSavedId) as
--   { name, saveAs, tags, spellID, iconID, text, color, outputs = { alert, text, icon, bar, circle, speech },
--     speech, sound, glow, warn, linger }
-- where `tags` are the words of the editor's For choice, `saveAs` is "note" or "mine", and `speech` is
-- "text", "textcount" or "count" as a reminder keeps it. The time, phase, boss and difficulty of the alert
-- a saved alert was made from are never kept. A saved alert's name defaults to its text, else its spell's
-- name. Every change tells the alerts windows (CRT.Alerts:Fire) and this store's own listeners.

local TEXT = {
    unnamed = "Saved alert",
}

local Alerts = CRT.Alerts

local Saved = {}
CRT.AlertSaved = Saved

local OUTPUT_KEYS = { "alert", "text", "icon", "bar", "circle", "speech" }
local listeners = {}

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

local function copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = copy(x)
    end
    return out
end

local function validID(v)
    return readable(v) and type(v) == "number" and v > 0 and v or nil
end

local function store(create)
    local db = Alerts:Settings()
    if not db then
        return nil
    end
    if create and type(db.saved) ~= "table" then
        db.saved = {}
    end
    return db.saved
end

local function changed()
    Alerts:Fire()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and geterrorhandler then
            geterrorhandler()(err)
        end
    end
end

-- fn is called after every change to the saved alerts.
function Saved:OnChange(fn)
    listeners[#listeners + 1] = fn
end

-- The name a saved alert gets when none is typed: its text, else its spell's name.
function Saved.DefaultName(s)
    local text = trim(s and s.text)
    if text ~= "" then
        return text
    end
    local id = validID(s and s.spellID)
    local name = id and CRT.AlertReminders and CRT.AlertReminders.SpellName(id)
    if name and trim(name) ~= "" then
        return name
    end
    return TEXT.unnamed
end

function Saved:Get(id)
    local all = store()
    return all and all[id] or nil
end

-- { { id, s } } sorted by name (any case), then oldest first.
function Saved:List()
    local out = {}
    for id, s in pairs(store() or {}) do
        out[#out + 1] = { id = id, s = s }
    end
    table.sort(out, function(a, b)
        local x, y = tostring(a.s.name or ""):lower(), tostring(b.s.name or ""):lower()
        if x ~= y then
            return x < y
        end
        return a.id < b.id
    end)
    return out
end

-- The words of a tags list, or of a text.
local function tagList(v)
    local out = {}
    if type(v) == "string" then
        for word in v:gmatch("%S+") do
            out[#out + 1] = word
        end
    elseif type(v) == "table" then
        for _, word in ipairs(v) do
            if type(word) == "string" and trim(word) ~= "" then
                out[#out + 1] = trim(word)
            end
        end
    end
    return out
end

-- Saves a copy of the setup in `fields` (only a saved alert's own fields are kept: not the time, phase,
-- encounter, boss or difficulty). id nil makes a new saved alert; an id that exists is overwritten, and
-- keeps its name when `fields` has none. Returns the id.
function Saved:Save(id, fields)
    local all = store(true)
    local db = Alerts:Settings()
    if not (all and db and type(fields) == "table") then
        return nil
    end
    local s = {
        saveAs = fields.saveAs == "note" and "note" or "mine",
        tags = tagList(fields.tags),
        spellID = validID(fields.spellID),
        iconID = validID(fields.iconID),
        text = trim(fields.text),
        color = copy(fields.color),
        speech = fields.speech,
        sound = fields.sound,
        glow = fields.glow and true or nil,
        warn = type(fields.warn) == "number" and fields.warn or 5,
        linger = type(fields.linger) == "number" and fields.linger > 0 and fields.linger or nil,
        outputs = {},
    }
    for _, k in ipairs(OUTPUT_KEYS) do
        s.outputs[k] = fields.outputs and fields.outputs[k] and true or false
    end
    local name = trim(fields.name)
    if name == "" and id and all[id] then
        name = all[id].name
    end
    s.name = (name and name ~= "") and name or Saved.DefaultName(s)
    if not id then
        id = db.nextSavedId or 1
    end
    if id >= (db.nextSavedId or 1) then
        db.nextSavedId = id + 1
    end
    all[id] = s
    changed()
    return id
end

-- False when there is no such saved alert. An empty name takes the default.
function Saved:Rename(id, name)
    local s = self:Get(id)
    if not s then
        return false
    end
    name = trim(name)
    s.name = name ~= "" and name or Saved.DefaultName(s)
    changed()
    return true
end

function Saved:Delete(id)
    local all = store()
    if all and all[id] ~= nil then
        all[id] = nil
        changed()
    end
end

-- The prefill for Editor:Open on a boss: every saved field, at phase ph and time (seconds into it) when
-- given. A spell dropped on an icon wins over the saved alert's own. Nil when there is no such saved alert.
function Saved:Prefill(id, encounterID, ph, time, spellID, boss)
    local s = self:Get(id)
    if not s then
        return nil
    end
    return {
        saved = id,
        spellID = validID(spellID) or s.spellID,
        saveAs = s.saveAs,
        ph = ph,
        time = time,
        boss = boss,
    }
end
