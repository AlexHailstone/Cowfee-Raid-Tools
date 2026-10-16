local ADDON, CRT = ...

-- The Phases tab of the Raid Notes page (Notes/Page.lua builds it into its tab): for one boss, what
-- starts each phase after the first. A phase can start by hand (Next phase), on a boss emote, when a
-- boss becomes untargetable or targetable, or when a new boss unit appears. Shipped triggers are
-- marked "Shipped"; changing one saves yours, and Use shipped puts the shipped one back. The triggers
-- are kept by Alerts/Phases.lua, which this tab only reads when it is built, after login.

local UI = CRT.UI

-- Every word on this tab, in one place so the wording is easy to change. Keep the keys, change the
-- text in quotes, save, and /reload.
local TEXT = {
    title = "Phases",
    help = "What starts each phase after the first one. The first phase starts with the pull. A phase set to Next phase only starts when you press Next phase on the Notes tab or type /crt note next, which also starts any phase here by hand, whatever its trigger.\n\nA phase appears here when your note or reminders use it, or when it has a trigger.\n\nShipped triggers come with the addon. Change one and it becomes yours; Use shipped puts the shipped one back.",
    boss = "Boss",
    phasePull = "Phase %s \226\128\148 the pull",
    phase = "Phase %s",
    shipped = "Shipped",
    yours = "Yours",
    useShipped = "Use shipped",
}

local ROW_H = 28
local MAX_ROWS = 12
local ROW_W = 650 -- the tab is 686 wide
local UNITS_ALL = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local UNITS_NEW = { "boss2", "boss3", "boss4", "boss5" }

local selected
local tab, rows, bossDrop
local pending = {} -- [ph] = kind picked but not saved yet (an emote has no words yet)
local listening = false

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function pickBoss(list)
    local found
    for _, b in ipairs(list) do
        if b.key == selected then
            found = true
        end
    end
    if not found then
        selected = list[1] and list[1].key or nil
        pending = {}
    end
    return selected
end

local function unitOptions(kind)
    local out = {}
    for _, u in ipairs(kind == "newboss" and UNITS_NEW or UNITS_ALL) do
        out[#out + 1] = { key = u, label = u }
    end
    return out
end

local function isUnitKind(kind)
    return kind == "untargetable" or kind == "targetable" or kind == "newboss"
end

-- The phases to show: those the note and reminders use, and those with a trigger. The lowest one starts
-- at the pull, so it is the fixed first row.
local function phaseList(enc)
    local seen, list = {}, {}
    local function add(ph)
        if type(ph) == "number" and not seen[ph] then
            seen[ph] = true
            list[#list + 1] = ph
        end
    end
    -- The tab has no difficulty choice, so reminders of every difficulty count.
    for _, ph in ipairs(CRT.Alerts:PhasesFor({ encounterID = enc, anyDifficulty = true })) do
        add(ph)
    end
    for ph in pairs(CRT.AlertPhases:For(enc)) do
        add(ph)
    end
    if #list == 0 then
        list[1] = 1
    end
    table.sort(list)
    return list
end

local function current(enc, ph)
    local e = CRT.AlertPhases:For(enc)[ph]
    local kind = pending[ph] or (e and e.kind) or "manual"
    local value = e and e.kind == kind and e.value or nil
    return kind, value, e
end

local function setKind(enc, ph, kind)
    local _, _, e = current(enc, ph)
    local value
    if isUnitKind(kind) then
        local old = e and isUnitKind(e.kind) and e.value or nil
        if old and not (kind == "newboss" and old == "boss1") then
            value = old
        else
            value = kind == "newboss" and "boss2" or "boss1"
        end
    elseif kind == "emote" and e and e.kind == "emote" then
        value = e.value
    end
    -- Cleared first, so the refresh Set causes draws the new kind.
    pending[ph] = nil
    if CRT.AlertPhases:Set(enc, ph, kind, value) then
        return true -- Set told the listeners, which refresh the tab
    end
    -- An emote needs words first: the box shows and the trigger is saved when they are typed.
    pending[ph] = kind == "emote" and kind or nil
    return false
end

local function refresh()
    if not tab then
        return
    end
    local enc = pickBoss(CRT.NoteReminders.BossList())
    local phases = enc and phaseList(enc) or {}
    for i, row in ipairs(rows) do
        local ph = phases[i]
        if enc and ph then
            row.ph = ph
            row.frame:Show()
            if i == 1 then
                row.name:SetText(string.format(TEXT.phasePull, tostring(ph)))
            else
                row.name:SetText(string.format(TEXT.phase, tostring(ph)))
                local kind, value, e = current(enc, ph)
                row.kind.refresh()
                row.value:SetShown(isUnitKind(kind))
                row.value.refresh()
                row.edit:SetShown(kind == "emote")
                if kind == "emote" and not row.edit:HasFocus() then
                    row.edit:SetText(value or "")
                end
                row.marker:SetText(e and (e.from == "yours" and TEXT.yours or TEXT.shipped) or "")
                row.useShipped:SetShown(e ~= nil and e.from == "yours")
            end
        else
            row.ph = nil
            row.frame:Hide()
        end
    end
    bossDrop.refresh()
end

local function makeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontNormal)
    b:SetHighlightFontObject(CRTFontHighlight)
    b:SetDisabledFontObject(CRTFontDisable)
    b:SetSize(width, height or 22)
    b:SetText(label)
    return b
end

local function makeRow(f, i)
    local frame = CreateFrame("Frame", nil, f)
    frame:SetSize(ROW_W, ROW_H - 2)
    frame:SetPoint("TOPLEFT", 8, -60 - (i - 1) * ROW_H)
    local row = { frame = frame }
    row.name = frame:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(135)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    if i == 1 then
        return row
    end

    row.kind = UI.Dropdown(frame, "", {
        labelWidth = 1,
        width = 180,
        options = function()
            local out = {}
            for _, k in ipairs(CRT.AlertPhases.KINDS) do
                out[#out + 1] = { key = k.key, label = k.label }
            end
            return out
        end,
        get = function()
            return row.ph and selected and (current(selected, row.ph)) or "manual"
        end,
        set = function(key)
            if row.ph and selected then
                if not setKind(selected, row.ph, key) then
                    refresh()
                end
            end
        end,
    })
    row.kind:SetPoint("LEFT", 140, 0)

    row.value = UI.Dropdown(frame, "", {
        labelWidth = 1,
        width = 100,
        options = function()
            local kind = row.ph and selected and (current(selected, row.ph))
            return unitOptions(kind)
        end,
        get = function()
            if not (row.ph and selected) then
                return nil
            end
            local kind, value = current(selected, row.ph)
            return value or (kind == "newboss" and "boss2" or "boss1")
        end,
        set = function(key)
            if row.ph and selected then
                local kind = current(selected, row.ph)
                CRT.AlertPhases:Set(selected, row.ph, kind, key)
            end
        end,
    })
    row.value:SetPoint("LEFT", 340, 0)

    row.edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    row.edit:SetSize(150, 20)
    row.edit:SetPoint("LEFT", 350, 0)
    row.edit:SetAutoFocus(false)
    row.edit:SetFontObject(CRTFontEdit)
    local function commit(self)
        local text = trim(self:GetText())
        if row.ph and selected and text ~= "" then
            local kind, value = current(selected, row.ph)
            if not (kind == "emote" and value == text) and CRT.AlertPhases:Set(selected, row.ph, "emote", text) then
                pending[row.ph] = nil
                return -- Set told the listeners, which refresh the tab
            end
        end
        refresh()
    end
    row.edit:SetScript("OnEnterPressed", function(self)
        commit(self)
        self:ClearFocus()
    end)
    row.edit:SetScript("OnEditFocusLost", commit)
    row.edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    row.marker = frame:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.marker:SetPoint("LEFT", 510, 0)
    row.marker:SetWidth(56)
    row.marker:SetJustifyH("LEFT")

    row.useShipped = makeButton(frame, TEXT.useShipped, 80, 20)
    row.useShipped:SetPoint("RIGHT", 0, 0)
    row.useShipped:SetScript("OnClick", function()
        if row.ph and selected then
            pending[row.ph] = nil
            CRT.AlertPhases:UseShipped(selected, row.ph)
        end
    end)
    return row
end

local function build(f)
    tab = f
    selected, pending = nil, {}

    local title = f:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(TEXT.title)
    UI.Help(f, TEXT.title, TEXT.help):SetPoint("LEFT", title, "RIGHT", 6, 0)

    bossDrop = UI.Dropdown(f, TEXT.boss, {
        labelWidth = 40,
        width = 230,
        options = function()
            local out = {}
            for _, b in ipairs(CRT.NoteReminders.BossList()) do
                out[#out + 1] = { key = b.key, label = b.label }
            end
            return out
        end,
        get = function()
            return pickBoss(CRT.NoteReminders.BossList())
        end,
        set = function(key)
            selected, pending = key, {}
            refresh()
        end,
    })
    bossDrop:SetPoint("TOPLEFT", 8, -30)

    rows = {}
    for i = 1, MAX_ROWS do
        rows[i] = makeRow(f, i)
    end
    f.rows = rows

    f:SetScript("OnShow", refresh)
    if not listening then
        listening = true
        CRT.Alerts:OnChange(function()
            if tab and tab:IsShown() then
                refresh()
            end
        end)
    end
    refresh()
end

CRT.NotePhases = { Build = build, Refresh = refresh }
