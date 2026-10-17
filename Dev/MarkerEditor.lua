local ADDON, CRT = ...

-- DEVELOPER ONLY. The marker display editor, /crt dev markers: make a boss's marker display
-- (Markers/Display.lua), try it with Test, and Export it as a line to paste into
-- Markers/Database.lua so it ships for everyone. Drafts are saved in CRTDB.dev.markerDisplays and
-- used in place of the shipped display while they exist, so a display can be tried in a real pull
-- before it ships. Delete drops a draft.
--
-- This file never ships: its .toc line is inside the do-not-package block, and the Dev folder is in
-- .pkgmeta's ignore list.

local UI = CRT.UI
local Markers = CRT.MarkerDisplay

local Editor = {}
CRT.MarkerEditor = Editor

local LAYOUTS = {
    { key = "row", label = "Row (left to right)" },
    { key = "column", label = "Column (top to bottom)" },
    { key = "grid", label = "Grid (rows of four)" },
}
local DEFAULT = { name = "Marker display", slots = 4, layout = "row", iconSize = 40, number = true, names = true, clearGap = 10, clearFull = 0, clearPhase = false }
local FIELDS = { "name", "slots", "layout", "iconSize", "number", "names", "clearGap", "clearFull", "clearPhase" }

local win
local controls = {}
local bossID -- the encounter being edited
local draft = {}

local function drafts()
    CRT.db.dev = CRT.db.dev or {}
    CRT.db.dev.markerDisplays = CRT.db.dev.markerDisplays or {}
    return CRT.db.dev.markerDisplays
end

local function loadDraft(id)
    bossID = id
    local src = (id and Markers:For(id)) or DEFAULT
    draft = {}
    for _, f in ipairs(FIELDS) do
        local v = src[f]
        if v == nil then
            v = DEFAULT[f]
        end
        draft[f] = v
    end
end

local function refresh()
    if not win or not win:IsShown() then
        return
    end
    for _, c in ipairs(controls) do
        c.refresh()
    end
    if not win.name:HasFocus() then
        win.name:SetText(draft.name or "")
    end
    local shipped = bossID and CRT.MarkerDisplayDB.displays[bossID]
    local hasDraft = bossID and drafts()[bossID]
    win.status:SetText(not bossID and "Pick a boss." or hasDraft and "Saved as a draft (used in place of the shipped one)." or shipped and "This boss's display ships with the addon." or "Not saved.")
    win.test:SetText(Markers:Testing() and "Stop test" or "Test")
end

-- The bosses in the raid route, each raid a heading (CRT.Bosses:Options), with their encounter IDs.
local function bosses()
    local out = {}
    for _, o in ipairs(CRT.Bosses:Options()) do
        out[#out + 1] = o.title and o or { key = o.key, label = o.label .. " (" .. o.key .. ")" }
    end
    return out
end

local function exportText()
    local d = draft
    local line = string.format('[%d] = { name = %q, slots = %d, layout = %q, iconSize = %d, number = %s, names = %s, clearGap = %d, clearFull = %d, clearPhase = %s },',
        bossID or 0, d.name or "", d.slots, d.layout, d.iconSize, tostring(d.number), tostring(d.names), d.clearGap, d.clearFull, tostring(d.clearPhase))
    local macros = {}
    for i = 1, 8 do
        macros[#macros + 1] = "/raid {rt" .. i .. "}"
    end
    return "-- Paste into CRT.MarkerDisplayDB.displays in Markers/Database.lua:\n" .. line .. "\n\n-- Macros, one per marker:\n" .. table.concat(macros, "\n")
end

local function add(row, y)
    row:SetPoint("TOPLEFT", 14, y)
    controls[#controls + 1] = row
    return row
end

local function slider(label, field, low, high, y, format)
    return add(UI.Slider(win, label, { min = low, max = high, step = 1, labelWidth = 150, width = 160, format = format,
        get = function()
            return draft[field]
        end,
        set = function(v)
            draft[field] = v
        end }), y)
end

local function check(label, field, y)
    local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 10, y)
    local fs = win:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        draft[field] = self:GetChecked() and true or false
    end)
    cb.refresh = function()
        cb:SetChecked(draft[field] and true or false)
    end
    controls[#controls + 1] = cb
end

local function button(text, width)
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function seconds(v)
    return v == 0 and "never" or (v .. "s")
end

local function build()
    win = CreateFrame("Frame", "CowfeeRaidToolsMarkerEditor", UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(win)
    win:SetSize(420, 520)
    win:SetPoint("CENTER")
    UI:RegisterLayer("popups", win)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "CowfeeRaidToolsMarkerEditor")
    UI.SetFrameTitle(win, "Marker displays (dev)")

    add(UI.Dropdown(win, "Boss", { options = bosses, labelWidth = 60, width = 300,
        get = function()
            return bossID
        end,
        set = function(id)
            loadDraft(id)
            refresh()
        end }), -30)

    local nameLabel = win:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    nameLabel:SetPoint("TOPLEFT", 14, -72)
    nameLabel:SetText("Name")
    win.name = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    win.name:SetSize(240, 20)
    win.name:SetPoint("TOPLEFT", 170, -68)
    win.name:SetAutoFocus(false)
    win.name:SetFontObject(CRTFontEdit)
    win.name:SetScript("OnTextChanged", function(self, user)
        if user then
            draft.name = self:GetText()
        end
    end)
    win.name:SetScript("OnEnterPressed", win.name.ClearFocus)

    slider("Slots", "slots", 1, 8, -96)
    add(UI.Dropdown(win, "Layout", { options = LAYOUTS, labelWidth = 150, width = 200,
        get = function()
            return draft.layout
        end,
        set = function(key)
            draft.layout = key
        end }), -128)
    slider("Icon size", "iconSize", 16, 96, -160)
    check("Show the slot number above each marker", "number", -196)
    check("Show who sent it under each marker", "names", -220)

    local clearTitle = win:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    clearTitle:SetPoint("TOPLEFT", 14, -256)
    clearTitle:SetText("Clear (always on the pull and on a kill or wipe)")
    slider("After no messages for", "clearGap", 0, 60, -276, seconds)
    slider("After the last slot fills", "clearFull", 0, 60, -308, seconds)
    check("When a new phase starts", "clearPhase", -344)

    win.status = win:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    win.status:SetPoint("TOPLEFT", 14, -380)
    win.status:SetWidth(390)
    win.status:SetJustifyH("LEFT")

    local save = button("Save draft", 120)
    save:SetPoint("BOTTOMLEFT", 14, 46)
    save:SetScript("OnClick", function()
        if not bossID then
            CRT:Print("Pick a boss first.")
            return
        end
        local copy = {}
        for _, f in ipairs(FIELDS) do
            copy[f] = draft[f]
        end
        drafts()[bossID] = copy
        CRT:Print("Saved the marker display draft for encounter " .. bossID .. ".")
        refresh()
    end)
    local delete = button("Delete draft", 120)
    delete:SetPoint("LEFT", save, "RIGHT", 6, 0)
    delete:SetScript("OnClick", function()
        if bossID and drafts()[bossID] then
            drafts()[bossID] = nil
            loadDraft(bossID)
            CRT:Print("Deleted the draft for encounter " .. bossID .. ".")
            refresh()
        end
    end)
    win.test = button("Test", 120)
    win.test:SetPoint("LEFT", delete, "RIGHT", 6, 0)
    win.test:SetScript("OnClick", function()
        Markers:Test((not Markers:Testing()) and draft or nil)
        refresh()
    end)
    local export = button("Export", 120)
    export:SetPoint("BOTTOMLEFT", 14, 18)
    export:SetScript("OnClick", function()
        if not bossID then
            CRT:Print("Pick a boss first.")
            return
        end
        CRT.ConsumablesTools:ShowText("Marker display (Ctrl+C to copy, paste to Claude)", exportText())
    end)

    win:SetScript("OnShow", refresh)
    UI:SkinTree(win)
end

function Editor:Toggle()
    if not win then
        build()
        local list = bosses()
        loadDraft(CRT.Bosses.FirstKey(list))
    end
    win:SetShown(not win:IsShown())
    refresh()
end
