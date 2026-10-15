local ADDON, CRT = ...

-- The Timeline page's References tab. On the left, a box to paste or write a reference timeline
-- (the text format of Timeline/Reference.lua) with Save, and a status line that says "Saved" or
-- the first errors. On the right, the selected boss's references: yours with Edit and Delete, the
-- shipped ones with Copy, which puts their text in the box to change and save as your own. The
-- Timeline page builds it with Build(parent, ctx) and calls tab:Refresh() when anything changes;
-- ctx gives it selectedBoss(), bossName(), references() (the selected boss's references, by the
-- same rule as the boss list) and refresh(). Recent(parent, width, pullLabel, toggle) makes the
-- Review tab's Recent pulls list: the boss's saved pulls beside a reference, where a click lays
-- one over it (toggle(pullID)); the page keeps which one, and says with recent:Update.

local Reference = CRT.TimelineReference
local UI = CRT.UI

local ReferencePage = {}
CRT.TimelineReferencePage = ReferencePage

local ROW_H = 24
local BOX_W = 340
local LIST_X = 364
local MAX_ERRORS = 3

local GRAY = { 0.35, 0.35, 0.35 }
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local FORMAT_HELP = "One line per thing:\n\n"
    .. "Boss: Nek'zali the Soulcoiler  (required)\n"
    .. "Difficulty: Mythic  (shown in its name)\n"
    .. "Length: 9:48  (else the last cast plus its bar)\n"
    .. "Encounter: 3001  (the boss's encounter ID, optional)\n"
    .. "Phase: P2 7:20  (a phase line, the label is optional)\n"
    .. "Soulcoil Rite (lead 7, color ff6b7d) [spell 123456]: 0:02+45, 1:17, 95\n\n"
    .. "A time is m:ss or plain seconds, and +N after it draws a bar N seconds long. lead N draws the cast line N seconds before each icon, color rrggbb colors the name, and [spell N] gives the icon and tooltip; without it the row is matched by name to the boss's Journal abilities. Blank lines and lines starting with # are skipped. Nothing is saved until every line reads."

local function skin(frame, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, alpha or 0.5)
    frame:SetBackdropBorderColor(GRAY[1], GRAY[2], GRAY[3], 1)
end

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "CRTFontNormal")
    fs:SetText(text)
    return fs
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

-- Asks in the game's own confirmation box, then runs accept.
local function confirm(text, arg, acceptText, accept)
    StaticPopup_ShowCustomGenericConfirmation({
        text = text,
        text_arg1 = arg,
        acceptText = acceptText,
        cancelText = CANCEL,
        showAlert = true,
        callback = accept,
    })
end

-- The Recent pulls list -------------------------------------------------------------------------

local RECENT_H = 32

function ReferencePage.Recent(f, width, pullLabel, toggle)
    local frame = CreateFrame("Frame", nil, f)
    frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -96)
    frame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    frame:SetWidth(width)
    frame:Hide()
    local title = label(frame, "Recent pulls")
    title:SetPoint("TOPLEFT", 4, 0)
    UI.Help(frame, "Recent pulls", "This boss's saved pulls. Click one to lay it over the reference: its deaths go in the Deaths row, its casts are drawn as ticks in a row of their own (their spells are usually unreadable), and a line marks where it ended. Click it again to clear it."):SetPoint("LEFT", title, "RIGHT", 4, 0)

    local recent, lines = {}, {}
    -- pulls newest first, overlayID the one laid over the reference (highlighted), shown whether
    -- a reference is shown at all
    function recent:Update(pulls, overlayID, shown)
        frame:SetShown(shown)
        for i, pull in ipairs(pulls) do
            local line = lines[i]
            if not line then
                line = CreateFrame("Button", nil, frame)
                line:SetSize(width, RECENT_H - 2)
                line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -20 - (i - 1) * RECENT_H)
                line.sel = line:CreateTexture(nil, "BACKGROUND")
                line.sel:SetAllPoints()
                line.sel:SetColorTexture(1, 0.82, 0, 0.18)
                line.title = label(line, "", "CRTFontSmall")
                line.title:SetPoint("TOPLEFT", 4, -2)
                line.deaths = label(line, "", "CRTFontSmall")
                line.deaths:SetPoint("TOPLEFT", 4, -16)
                line.deaths:SetTextColor(1, 0.3, 0.3)
                line:SetScript("OnClick", function(self)
                    toggle(self.pullID)
                end)
                lines[i] = line
            end
            line.pullID = pull.id
            line.title:SetText(pullLabel(pull))
            local n = #(pull.deaths or {})
            line.deaths:SetText(n == 1 and "1 death" or (n .. " deaths"))
            line.sel:SetShown(pull.id == overlayID)
            line:Show()
        end
        for i = #pulls + 1, #lines do
            lines[i]:Hide()
        end
    end
    return recent
end

-- The References tab -----------------------------------------------------------------------------

function ReferencePage.Build(f, ctx)
    local tab = {}
    local editing -- the key of your reference that is in the box, nil for a new one
    local lines = {}

    -- Left: the text box, Save and Clear, and the status line.
    local title = label(f, "Reference text")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    UI.Help(f, "Reference text", FORMAT_HELP):SetPoint("LEFT", title, "RIGHT", 6, 0)
    local mode = label(f, "", "CRTFontSmall")
    mode:SetPoint("TOPLEFT", f, "TOPLEFT", 160, -10)
    mode:SetWidth(BOX_W - 152)
    mode:SetJustifyH("RIGHT")
    mode:SetWordWrap(false)

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    box:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 84)
    box:SetWidth(BOX_W)
    skin(box, 0.4)
    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTimelineReferenceScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(CRTFontEdit)
    edit:SetWidth(BOX_W - 40)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(_, width)
        edit:SetWidth(width)
    end)
    -- a click anywhere in the box types, not only on the lines that have text
    local function focus()
        edit:SetFocus()
        edit:SetCursorPosition(#(edit:GetText() or ""))
    end
    for _, frame in ipairs({ box, scroll }) do
        frame:EnableMouse(true)
        frame:SetScript("OnMouseDown", focus)
    end

    local status = label(f, "", "CRTFontSmall")
    status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -32)
    status:SetWidth(BOX_W)
    status:SetJustifyH("LEFT")

    local function showMode()
        local entry = editing and Reference:Find(editing)
        if not entry then
            editing = nil
        end
        mode:SetText(entry and ("Editing " .. Reference.Label(entry.ref)) or "New reference")
    end

    -- Fills the box. key is your reference being edited, nil for text to save as a new one.
    local function fill(text, key)
        editing = key
        edit:SetText(text or "")
        edit:SetCursorPosition(0)
        status:SetText("")
        showMode()
    end

    local save = button(f, "Save", 80)
    save:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
    save:SetScript("OnClick", function()
        edit:ClearFocus()
        local text = edit:GetText()
        local ok, errors
        if editing then
            ok, errors = Reference:Update(editing, text)
        else
            local key
            key, errors = Reference:Add(text)
            ok = key ~= nil
            editing = key or nil -- a second Save changes this one instead of adding another
        end
        if ok then
            status:SetText("Saved")
            status:SetTextColor(0.4, 1, 0.4)
        else
            local shown = {}
            for i = 1, math.min(MAX_ERRORS, #errors) do
                shown[i] = errors[i]
            end
            status:SetText(table.concat(shown, "\n"))
            status:SetTextColor(1, 0.3, 0.3)
        end
        showMode()
    end)
    local clear = button(f, "Clear", 80)
    clear:SetPoint("LEFT", save, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        fill("", nil)
    end)

    -- Right: the selected boss's references.
    local listLabel = label(f, "")
    listLabel:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, -8)
    listLabel:SetWidth(310)
    listLabel:SetJustifyH("LEFT")
    listLabel:SetWordWrap(false)
    local empty = label(f, "No references for this boss yet", "CRTFontSmall")
    empty:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, -34)

    local function line(i)
        local l = lines[i]
        if l then
            return l
        end
        l = CreateFrame("Frame", nil, f)
        l:SetSize(310, ROW_H)
        l:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, -30 - (i - 1) * ROW_H)
        l.name = label(l, "", "CRTFontSmall")
        l.name:SetPoint("LEFT", 0, 0)
        l.name:SetWidth(150)
        l.name:SetJustifyH("LEFT")
        l.name:SetWordWrap(false)
        l.kind = label(l, "", "CRTFontSmall")
        l.kind:SetPoint("LEFT", 154, 0)
        l.kind:SetTextColor(0.6, 0.6, 0.6)
        l.delete = button(l, "Delete", 52)
        l.delete:SetPoint("RIGHT", 0, 0)
        l.edit = button(l, "Edit", 44)
        l.edit:SetPoint("RIGHT", l.delete, "LEFT", -4, 0)
        l.copy = button(l, "Copy", 52)
        l.copy:SetPoint("RIGHT", 0, 0)
        l.edit:SetScript("OnClick", function(self)
            local entry = Reference:Find(self.key)
            if entry then
                fill(entry.text, entry.key)
            end
        end)
        l.copy:SetScript("OnClick", function(self)
            local entry = Reference:Find(self.key)
            if entry then
                fill(entry.text, nil)
            end
        end)
        l.delete:SetScript("OnClick", function(self)
            local key = self.key
            local entry = Reference:Find(key)
            if not entry then
                return
            end
            confirm("Delete your reference %s?", Reference.Label(entry.ref), "Delete", function()
                if editing == key then
                    editing = nil
                end
                Reference:Delete(key)
            end)
        end)
        lines[i] = l
        UI:SkinTree(l) -- so the Modern look skins the new buttons
        return l
    end

    function tab:Refresh()
        local boss = ctx.selectedBoss()
        listLabel:SetText(boss and ("References for " .. (ctx.bossName() or tostring(boss))) or "Pick a boss on the Review tab")
        local refs = boss and ctx.references() or {}
        for i, entry in ipairs(refs) do
            local l = line(i)
            l.name:SetText(Reference.Label(entry.ref))
            l.kind:SetText(entry.own and "yours" or "shipped")
            l.edit.key, l.delete.key, l.copy.key = entry.key, entry.key, entry.key
            l.edit:SetShown(entry.own)
            l.delete:SetShown(entry.own)
            l.copy:SetShown(not entry.own)
            l:Show()
        end
        for i = #refs + 1, #lines do
            lines[i]:Hide()
            lines[i].edit:Hide()
            lines[i].delete:Hide()
            lines[i].copy:Hide()
        end
        empty:SetShown(boss ~= nil and #refs == 0)
        showMode()
    end

    f:SetScript("OnShow", function()
        ctx.refresh()
    end)
    return tab
end
