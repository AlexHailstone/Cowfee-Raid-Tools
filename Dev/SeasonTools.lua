local ADDON, CRT = ...

-- DEVELOPER ONLY. /crt dev seasons: the season packs (Seasons/<season>/), which of them load, and
-- purging a season's saved data. See the vault note "Cowfee Raid Tools - Boss Library Design".
--   Load      Current season only (the default) or All seasons, saved in CRTDB.dev.seasons.load.
--             Changing it reloads the interface, since the library fills the features at load.
--   Purge     Deletes the saved data of one season's bosses, those registered in its pack: recorded
--             Timeline pulls and row settings, reminders and phase triggers, pace plans and switches,
--             and marker display switches and drafts. Tattlebot's history, the Late Tracker and raid
--             notes are never touched, and a boss with saved data but no boss file is never purged.
--
-- This file never ships: its .toc line is inside the do-not-package block.

local UI = CRT.UI
local Bosses = CRT.Bosses

local Tools = {}
CRT.SeasonTools = Tools

local win
local rows = {}

local LOADS = {
    { key = "current", label = "Current season only" },
    { key = "all", label = "All seasons" },
}

local function dev()
    CRT.db.dev = CRT.db.dev or {}
    CRT.db.dev.seasons = CRT.db.dev.seasons or {}
    return CRT.db.dev.seasons
end

-- The saved tables keyed by encounter ID that a purge clears, with a label for the confirmation.
local function stores()
    local db = CRT.db
    return {
        { label = "recorded Timeline pulls", t = db.timeline and db.timeline.bosses },
        { label = "Timeline row settings", t = db.timeline and db.timeline.rows },
        { label = "reminders", t = db.alerts and db.alerts.reminders },
        { label = "phase triggers", t = db.alerts and db.alerts.phases },
        { label = "own pace plans", t = db.pace and db.pace.own },
        { label = "shared pace plans", t = db.pace and db.pace.shared },
        { label = "pace plan choices", t = db.pace and db.pace.use },
        { label = "pace switches", t = db.pace and db.pace.disabled },
        { label = "marker display switches", t = db.markers and db.markers.disabled },
        { label = "marker display drafts", t = db.dev and db.dev.markerDisplays },
    }
end

-- What a purge of the season would delete: { { label, count } }, and the total.
function Tools:PurgeCounts(seasonKey)
    local ids = {}
    for _, def in ipairs(Bosses:List(seasonKey)) do
        ids[#ids + 1] = def.encounterID
    end
    local out, total = {}, 0
    for _, store in ipairs(stores()) do
        local n = 0
        if type(store.t) == "table" then
            for _, id in ipairs(ids) do
                if store.t[id] ~= nil then
                    n = n + 1
                end
            end
        end
        if n > 0 then
            out[#out + 1] = { label = store.label, count = n }
            total = total + n
        end
    end
    return out, total, #ids
end

function Tools:Purge(seasonKey)
    local n = 0
    for _, def in ipairs(Bosses:List(seasonKey)) do
        for _, store in ipairs(stores()) do
            if type(store.t) == "table" and store.t[def.encounterID] ~= nil then
                store.t[def.encounterID] = nil
                n = n + 1
            end
        end
    end
    return n
end

local function confirmPurge(def)
    local counts, total, bosses = Tools:PurgeCounts(def.key)
    if total == 0 then
        CRT:Print("Nothing saved for the " .. bosses .. " boss" .. (bosses == 1 and "" or "es") .. " of " .. (def.name or def.key) .. ".")
        return
    end
    local parts = {}
    for _, c in ipairs(counts) do
        parts[#parts + 1] = c.count .. " " .. c.label
    end
    StaticPopup_ShowCustomGenericConfirmation({
        text = "Purge %s? This deletes, for its bosses: " .. table.concat(parts, ", ") .. ".\n\nTattlebot's history, the Late Tracker and raid notes are kept. This can't be undone.",
        text_arg1 = def.name or def.key,
        acceptText = "Purge",
        cancelText = CANCEL,
        showAlert = true,
        callback = function()
            local n = Tools:Purge(def.key)
            CRT:Print("Purged " .. n .. " saved entr" .. (n == 1 and "y" or "ies") .. " for " .. (def.name or def.key) .. ". /reload to see it everywhere.")
            Tools:Refresh()
        end,
    })
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

function Tools:Refresh()
    if not win or not win:IsShown() then
        return
    end
    win.load.refresh()
    for i, def in ipairs(Bosses:Seasons()) do
        local r = rows[i]
        if not r then
            r = CreateFrame("Frame", nil, win)
            r:SetSize(400, 24)
            r:SetPoint("TOPLEFT", 14, -86 - (i - 1) * 26)
            r.text = r:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
            r.text:SetPoint("LEFT", 0, 0)
            r.text:SetWidth(280)
            r.text:SetJustifyH("LEFT")
            r.purge = button(r, "Purge", 80)
            r.purge:SetPoint("RIGHT", 0, 0)
            UI:SkinTree(r)
            rows[i] = r
        end
        local _, total, bosses = Tools:PurgeCounts(def.key)
        r.text:SetText(string.format("%s%s: %d boss%s, %d saved", def.name or def.key, def.current and " (current)" or "", bosses, bosses == 1 and "" or "es", total))
        r.purge:SetScript("OnClick", function()
            confirmPurge(def)
        end)
        r:Show()
    end
end

local function build()
    win = CreateFrame("Frame", "CowfeeRaidToolsSeasonTools", UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(win)
    win:SetSize(430, 300)
    win:SetPoint("CENTER")
    UI:RegisterLayer("popups", win)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CowfeeRaidToolsSeasonTools")
    UI.SetFrameTitle(win, "Season packs (dev)")

    win.load = UI.Dropdown(win, "Load", { options = LOADS, labelWidth = 60, width = 220,
        get = function()
            return Bosses:LoadMode()
        end,
        set = function(key)
            if key == Bosses:LoadMode() then
                return
            end
            dev().load = key ~= "current" and key or nil
            StaticPopup_ShowCustomGenericConfirmation({
                text = "Load %s? Your interface reloads.",
                text_arg1 = key == "all" and "all seasons" or "the current season only",
                acceptText = "Reload",
                cancelText = CANCEL,
                callback = ReloadUI,
            })
        end })
    win.load:SetPoint("TOPLEFT", 14, -32)
    local note = win:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    note:SetPoint("TOPLEFT", 16, -66)
    note:SetText("Seasons, their bosses, and what is saved for them:")
    win:SetScript("OnShow", function()
        Tools:Refresh()
    end)
    UI:SkinTree(win)
end

function Tools:Toggle()
    if not win then
        build()
    end
    win:SetShown(not win:IsShown())
    self:Refresh()
end
