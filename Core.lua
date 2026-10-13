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
