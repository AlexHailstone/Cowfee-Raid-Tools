local ADDON, CRT = ...

-- Profiles. A profile is a full copy of the addon's saved data: every setting, plus the raid layouts,
-- notes, consumables lists, and the Late Tracker and Tattlebot history. The class and role caches are
-- shared by every profile.
--
-- The active profile lives at the top of CRTDB, under the same keys as before profiles existed, so no
-- stored field moved. The others wait in CRTDB.profiles[name]. Each character remembers its profile in
-- CRTDBChar.profile (SavedVariablesPerCharacter), and a character with none uses CRTDB.defaultProfile.
-- The swap happens in CRT.Profiles:Load, as the saved data loads and before anything reads it, so
-- switching, copying or resetting a profile saves the choice and reloads the interface.

local Profiles = {}
CRT.Profiles = Profiles

local DEFAULT = "Default"
local SHARED = { classCache = true, roleCache = true }
local EXPORT_PREFIX = "CRTP1:"

-- The top-level keys a profile holds: every key in the defaults, except the shared caches.
local function profileKeys()
    local keys = {}
    for key in pairs(CRT.defaults) do
        if not SHARED[key] then
            keys[#keys + 1] = key
        end
    end
    return keys
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

-- Takes the active profile's data off the top of CRTDB, as a table.
local function takeActive(db)
    local data = {}
    for _, key in ipairs(profileKeys()) do
        data[key] = db[key]
        db[key] = nil
    end
    return data
end

-- Puts a profile's data at the top of CRTDB. Missing keys are filled from the defaults afterwards.
local function putActive(db, data)
    for _, key in ipairs(profileKeys()) do
        db[key] = data and data[key] or nil
    end
end

-- Called from Core.lua on ADDON_LOADED, before the defaults are filled in.
function Profiles:Load()
    local db = CRTDB
    CRTDBChar = CRTDBChar or {}
    db.profiles = db.profiles or {}
    db.activeProfile = db.activeProfile or DEFAULT
    db.defaultProfile = db.defaultProfile or DEFAULT
    local want = CRTDBChar.profile or db.defaultProfile
    if want ~= db.activeProfile then
        db.profiles[db.activeProfile] = takeActive(db)
        putActive(db, db.profiles[want])
        db.profiles[want] = nil
        db.activeProfile = want
    end
    CRTDBChar.profile = want
end

function Profiles:Current()
    return CRTDB.activeProfile or DEFAULT
end

function Profiles:Default()
    return CRTDB.defaultProfile or DEFAULT
end

function Profiles:SetDefault(name)
    if self:Exists(name) then
        CRTDB.defaultProfile = name
    end
end

function Profiles:Exists(name)
    return name == self:Current() or CRTDB.profiles[name] ~= nil
end

-- Every profile's name, sorted, with the active one included.
function Profiles:List()
    local names = { self:Current() }
    for name in pairs(CRTDB.profiles) do
        if name ~= self:Current() then
            names[#names + 1] = name
        end
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

-- Every profile except the active one, as dropdown options.
function Profiles:Others()
    local out = {}
    for _, name in ipairs(self:List()) do
        if name ~= self:Current() then
            out[#out + 1] = { key = name, label = name }
        end
    end
    return out
end

function Profiles:All()
    local out = {}
    for _, name in ipairs(self:List()) do
        out[#out + 1] = { key = name, label = name }
    end
    return out
end

-- Switches this character to a profile, new or existing, and reloads.
function Profiles:Switch(name)
    name = strtrim(name or "")
    if name == "" or name == self:Current() then
        return
    end
    if not CRTDB.profiles[name] then
        CRTDB.profiles[name] = {} -- a new profile starts from the defaults
    end
    CRTDBChar.profile = name
    ReloadUI()
end

-- Replaces the active profile's data with a copy of another profile's, and reloads.
function Profiles:CopyFrom(name)
    local source = CRTDB.profiles[name]
    if not source then
        return
    end
    putActive(CRTDB, deepCopy(source))
    ReloadUI()
end

-- Puts the active profile back to the defaults, and reloads.
function Profiles:Reset()
    putActive(CRTDB, nil)
    ReloadUI()
end

-- Deletes a profile that isn't active. A character that used it starts on the default profile, and a
-- deleted default profile becomes the active one.
function Profiles:Delete(name)
    if name == self:Current() or not CRTDB.profiles[name] then
        return
    end
    CRTDB.profiles[name] = nil
    if CRTDB.defaultProfile == name then
        CRTDB.defaultProfile = self:Current()
    end
end

-- The active profile as one line of text to share, through the game's own CBOR, deflate and base64.
function Profiles:Export()
    local E = C_EncodingUtil
    if not (E and E.SerializeCBOR and E.CompressString and E.EncodeBase64) then
        return nil, "This game client can't export profiles."
    end
    local data = {}
    for _, key in ipairs(profileKeys()) do
        data[key] = CRTDB[key]
    end
    local ok, text = pcall(function()
        return E.EncodeBase64(E.CompressString(E.SerializeCBOR({ v = 1, data = data })))
    end)
    if not ok or not text then
        return nil, "The profile couldn't be exported."
    end
    return EXPORT_PREFIX .. text
end

-- Reads an exported profile and saves it as a new profile. Returns true, or nil and the reason.
function Profiles:Import(text, name)
    name = strtrim(name or "")
    text = strtrim(text or "")
    if name == "" then
        return nil, "Give the new profile a name."
    end
    if self:Exists(name) then
        return nil, "A profile named " .. name .. " already exists."
    end
    if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "That isn't a Cowfee Raid Tools profile."
    end
    local E = C_EncodingUtil
    local ok, decoded = pcall(function()
        return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(text:sub(#EXPORT_PREFIX + 1))))
    end)
    if not ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
        return nil, "The profile text is damaged. Copy it again."
    end
    local data = {}
    for _, key in ipairs(profileKeys()) do
        if type(decoded.data[key]) == type(CRT.defaults[key]) then
            data[key] = decoded.data[key]
        end
    end
    CRTDB.profiles[name] = data
    return true
end
