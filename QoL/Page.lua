local ADDON, CRT = ...

-- The Quality of Life page: a home for small conveniences and their settings. Empty for now, with a
-- line saying so. Settings for it go in CRTDB.qol, with defaults in Core.lua.

local UI = CRT.UI

-- Every word on this page, in one place so the wording is easy to change.
local TEXT = {
    title = "Quality of Life",
    hint = "Small conveniences for raid nights. Nothing here yet: new options and their settings will appear on this page.",
}

local function build(pf)
    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(TEXT.title)

    local hint = pf:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -34)
    hint:SetWidth(670)
    hint:SetJustifyH("LEFT")
    hint:SetText(TEXT.hint)
end

UI:RegisterPage("qol", TEXT.title, build)
