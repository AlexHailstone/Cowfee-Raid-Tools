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
local Journal = CRT.TimelineJournal
local UI = CRT.UI

local ReferencePage = {}
CRT.TimelineReferencePage = ReferencePage

local ROW_H = 24
local BOX_W = 340
local LIST_X = 364
local MAX_ERRORS = 3
local REF_ROWS = 4 -- references listed before the Journal abilities start
local ABILITY_H = 20

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
    .. "Soulcoil Rite (type raid, lead 7) [spell 123456]: 0:02+45, 1:17, 95\n\n"
    .. "A time is m:ss or plain seconds, and +N after it draws a bar N seconds long. type says what the ability is, one or more of the words below: the first colors the row, and each other one adds a dot to its name. lead N draws the cast line N seconds before each icon, color rrggbb colors the name instead of its type, and [spell N] gives the icon and tooltip; without it the row is matched by name to the boss's Journal abilities. Blank lines and lines starting with # are skipped. Nothing is saved until every line reads.\n\n"
    .. CRT.TimelineReference.Legend()
    .. "\n\nIcons and the match to a Journal ability come from the Encounter Journal, which is not read in combat, so they can be blank until you are out of combat."

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
            -- a reference for another boss is not in this boss's list: say where it went
            local saved = Reference.Parse(text)
            local here = false
            for _, entry in ipairs(ctx.references() or {}) do
                here = here or entry.key == editing
            end
            local sameName = saved and ctx.bossName() and saved.boss:lower() == ctx.bossName():lower()
            status:SetText((here or sameName or not saved) and "Saved" or ("Saved for " .. saved.boss))
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

    -- The boss whose Journal abilities fit the box: its Boss and Encounter lines when it has them,
    -- else the selected boss. Returns the encounter ID to ask the Journal (or nil) and a name.
    local function journalBoss()
        local boss, encounterID = Reference.Header(edit:GetText())
        if boss or encounterID then
            return Journal:ResolveID(nil, { boss = boss, encounterID = encounterID }), boss or tostring(encounterID)
        end
        local selected = ctx.selectedBoss()
        local refs = selected and ctx.references() or {}
        return Journal:ResolveID(selected, refs[1] and refs[1].ref), ctx.bossName()
    end

    local refreshAbilities -- set below, with the abilities list

    local fillIDs = button(f, "Fill spell IDs", 110)
    fillIDs:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    fillIDs:SetScript("OnClick", function()
        edit:ClearFocus()
        local id, name = journalBoss()
        local rows = id and Journal:Rows(id) or {}
        if #rows == 0 then
            status:SetText("No Journal abilities found for " .. (name or "this boss") .. ".")
            status:SetTextColor(1, 0.3, 0.3)
        else
            local text, n = Reference.FillSpellIDs(edit:GetText(), rows)
            edit:SetText(text)
            status:SetText(n > 0 and ("Added " .. n .. " spell ID" .. (n == 1 and "" or "s") .. ". Save to keep them.")
                or "No more lines match a Journal ability.")
            status:SetTextColor(0.4, 1, 0.4)
        end
        refreshAbilities()
    end)
    UI.Help(f, "Fill spell IDs", "Adds [spell N] to every line whose name matches one of the boss's Encounter Journal abilities (listed on the right), so its icon and tooltip are fixed in the text. The boss is the one on the Boss line, or the selected boss.\n\nLines that already have a [spell] and lines that match nothing are left as they are. A name that doesn't match can be renamed to the Journal's name, or given [spell N] by hand.\n\nThe Journal is read out of combat with its window closed."):SetPoint("LEFT", fillIDs, "RIGHT", 4, 0)

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

    -- Right, under the references: the boss's Journal abilities with their spell IDs.
    local abilitiesLabel = label(f, "")
    abilitiesLabel:SetWidth(280)
    abilitiesLabel:SetJustifyH("LEFT")
    abilitiesLabel:SetWordWrap(false)
    UI.Help(f, "Journal abilities", "The boss's abilities in the Encounter Journal, with their spell IDs. A reference line whose name matches one gets its icon and tooltip, or use Fill spell IDs to write the IDs into the text.\n\nThe Journal's spell for an ability is sometimes a summary spell rather than the exact cast, so its ID may differ from what the damage meter shows.\n\nNothing shows in combat or while the Journal window is open."):SetPoint("LEFT", abilitiesLabel, "RIGHT", -4, 0)
    local abilitiesNone = label(f, "", "CRTFontSmall")
    abilitiesNone:SetWidth(300)
    abilitiesNone:SetJustifyH("LEFT")
    local abilitiesScroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTimelineAbilitiesScroll", f, "UIPanelScrollFrameTemplate")
    -- the abilities start under the references, however many there are (at least REF_ROWS rows)
    local function placeAbilities(refCount)
        local top = -30 - math.max(REF_ROWS, refCount) * ROW_H - 12
        abilitiesLabel:ClearAllPoints()
        abilitiesLabel:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, top)
        abilitiesNone:ClearAllPoints()
        abilitiesNone:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, top - 24)
        abilitiesScroll:ClearAllPoints()
        abilitiesScroll:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, top - 22)
        abilitiesScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 8)
    end
    placeAbilities(0)
    local abilitiesChild = CreateFrame("Frame", nil, abilitiesScroll)
    abilitiesChild:SetSize(290, 1)
    abilitiesScroll:SetScrollChild(abilitiesChild)
    local abilityLines = {}

    local function abilityLine(i)
        local l = abilityLines[i]
        if l then
            return l
        end
        l = CreateFrame("Frame", nil, abilitiesChild)
        l:SetSize(290, ABILITY_H)
        l:SetPoint("TOPLEFT", abilitiesChild, "TOPLEFT", 0, -(i - 1) * ABILITY_H)
        l.icon = l:CreateTexture(nil, "ARTWORK")
        l.icon:SetSize(16, 16)
        l.icon:SetPoint("LEFT", 0, 0)
        l.name = label(l, "", "CRTFontSmall")
        l.name:SetPoint("LEFT", 22, 0)
        l.name:SetWidth(200)
        l.name:SetJustifyH("LEFT")
        l.name:SetWordWrap(false)
        l.id = label(l, "", "CRTFontSmall")
        l.id:SetPoint("RIGHT", 0, 0)
        l.id:SetTextColor(0.6, 0.6, 0.6)
        abilityLines[i] = l
        return l
    end

    local abilitiesFor -- the encounter ID the list was last filled for, so typing doesn't refill it
    refreshAbilities = function()
        local id, name = journalBoss()
        abilitiesFor = id
        abilitiesLabel:SetText("Journal abilities" .. (name and (": " .. name) or ""))
        local rows = id and Journal:Rows(id) or {}
        for i, row in ipairs(rows) do
            local l = abilityLine(i)
            l.icon:SetTexture(row.icon or 134400)
            l.name:SetText(row.name or "")
            l.id:SetText(tostring(row.spellID))
            l:Show()
        end
        for i = #rows + 1, #abilityLines do
            abilityLines[i]:Hide()
        end
        abilitiesChild:SetHeight(math.max(1, #rows * ABILITY_H))
        abilitiesNone:SetText(name and "No Journal abilities found" or "No boss picked")
        abilitiesNone:SetShown(#rows == 0)
    end
    edit:SetScript("OnTextChanged", function()
        local id = journalBoss()
        if id ~= abilitiesFor then
            refreshAbilities()
        end
    end)

    function tab:Refresh()
        refreshAbilities()
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
        placeAbilities(#refs)
        showMode()
    end

    f:SetScript("OnShow", function()
        ctx.refresh()
    end)
    return tab
end
