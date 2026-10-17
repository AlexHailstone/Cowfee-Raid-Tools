local ADDON, CRT = ...

-- The Timeline page's Settings tab: the view (how much time is visible, the axis labels, the icon
-- size), the rows of the selected boss (show or hide each, add a spell of your own), the deaths
-- filters, and recording (with deleting the boss's pulls). Every control writes through
-- Timeline:Set or the Journal's setters. The Timeline page builds it with Build(parent, ctx) and
-- calls tab:Refresh() when anything changes; ctx gives it selectedBoss(), bossName(),
-- showingReference() (a reference rather than a pull is shown), shownReference() (that reference's
-- entry, else nil) and refresh().

local Timeline = CRT.Timeline
local Journal = CRT.TimelineJournal
local View = CRT.TimelineView
local Lanes = CRT.TimelineLanes
local UI = CRT.UI

local SettingsTab = {}
CRT.TimelineSettingsTab = SettingsTab

local ROW_H = 22
local RIGHT_X = 360

local GRIDS = {
    { key = 10, label = "10 seconds" },
    { key = 15, label = "15 seconds" },
    { key = 30, label = "30 seconds" },
    { key = 60, label = "1 minute" },
}
local DEATH_ROWS = {
    { key = "combined", label = "One row for everyone" },
    { key = "player", label = "A row per player" },
}

local function settings()
    return Timeline:Settings()
end

-- A name as the lanes compare it: trimmed, curly apostrophes made plain, lowercase. The same rule
-- as trimLower in Lanes.lua.
local function nameKey(name)
    local s = tostring(name or ""):gsub("\226\128\153", "'"):gsub("\226\128\152", "'")
    return (s:gsub("^%s+", ""):gsub("%s+$", "")):lower()
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

function SettingsTab.Build(f, ctx)
    local tab = {}
    local controls, rowPool = {}, {}
    local bossLabel, rowsChild, addEdit, addButton, deleteButton

    -- A checkbox with its text on the right. get() is the setting, set(on) saves it.
    local function checkbox(parent, x, y, text, get, set)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 4, y)
        cb.Label = parent:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.Label:SetJustifyH("LEFT")
        cb.Label:SetText(text)
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
        end)
        cb.refresh = function()
            cb:SetChecked(get() and true or false)
        end
        controls[#controls + 1] = cb
        return cb
    end

    local function place(row, parent, x, y)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        controls[#controls + 1] = row
        return row
    end

    local function slider(parent, x, y, text, opts)
        opts.labelWidth, opts.width = 120, 150
        return place(UI.Slider(parent, text, opts), parent, x, y)
    end

    local function settingSlider(parent, x, y, text, field, low, high, step, format)
        return slider(parent, x, y, text, {
            min = low, max = high, step = step, format = format,
            get = function()
                return settings()[field]
            end,
            set = function(value)
                Timeline:Set(field, value)
            end,
        })
    end

    -- A reference row is hidden by its name (as the lanes read it), or by the spell the lanes give it
    -- (its [spell] or its Journal match by name) when that spell is hidden. A boss with a text key
    -- asks the Journal under the same id the lanes use (Journal:ResolveID).
    local function journalKey(entry)
        local selectedBoss = ctx.selectedBoss()
        if type(selectedBoss) ~= "number" and entry then
            return Journal:ResolveID(selectedBoss, entry.ref) or selectedBoss
        end
        return selectedBoss
    end

    local function refRowHidden(row, entry)
        local selectedBoss = ctx.selectedBoss()
        local mine = settings().rows and settings().rows[selectedBoss]
        local eid = journalKey(entry)
        local spellID = Lanes.RowSpell(row, eid)
        return (mine and mine.hiddenNames and mine.hiddenNames[nameKey(row.name)])
            or (spellID ~= 0 and Journal:IsHidden(eid, spellID)) or false
    end

    local function setRefRowHidden(row, hidden, entry)
        local selectedBoss = ctx.selectedBoss()
        local all = settings().rows or {}
        settings().rows = all
        all[selectedBoss] = all[selectedBoss] or {}
        local mine = all[selectedBoss]
        mine.hiddenNames = mine.hiddenNames or {}
        mine.hiddenNames[nameKey(row.name)] = hidden or nil
        local eid = journalKey(entry)
        local spellID = Lanes.RowSpell(row, eid)
        if not hidden and spellID ~= 0 and Journal:IsHidden(eid, spellID) then
            Journal:SetHidden(eid, spellID, false)
        end
        Timeline:Fire()
    end

    -- The rows of the selected boss, one line each: show or hide, the name, and Remove on your own.
    -- With a reference shown, they are the reference's rows instead.
    local function updateRows()
        local selectedBoss = ctx.selectedBoss()
        local entry = ctx.showingReference() and ctx.shownReference()
        local rows = entry and entry.ref.rows or (selectedBoss and Journal:Rows(selectedBoss)) or {}
        -- spells of your own are added to recorded pulls only
        addEdit:SetEnabled(not entry)
        addButton:SetEnabled(not entry)
        bossLabel:SetText(selectedBoss and ("Rows for " .. (ctx.bossName() or selectedBoss)) or "Pick a boss on the Review tab")
        for i, row in ipairs(rows) do
            local line = rowPool[i]
            if not line then
                line = CreateFrame("Frame", nil, rowsChild)
                line:SetSize(300, ROW_H)
                line:SetPoint("TOPLEFT", rowsChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
                line.check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
                line.check:SetSize(22, 22)
                line.check:SetPoint("LEFT", 0, 0)
                line.text = line:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
                line.text:SetPoint("LEFT", line.check, "RIGHT", 2, 0)
                line.text:SetWidth(200)
                line.text:SetJustifyH("LEFT")
                line.text:SetWordWrap(false)
                line.remove = button(line, "Remove", 56)
                line.remove:SetPoint("RIGHT", 0, 0)
                line.check.line = line
                line.check:SetScript("OnClick", function(self)
                    local l = self.line
                    if l.refRow then
                        setRefRowHidden(l.refRow, not self:GetChecked(), l.refEntry)
                    else
                        Journal:SetHidden(ctx.selectedBoss(), l.spellID, not self:GetChecked())
                    end
                end)
                line.remove:SetScript("OnClick", function()
                    Journal:RemoveCustom(ctx.selectedBoss(), line.spellID)
                end)
                rowPool[i] = line
                UI:SkinTree(rowsChild) -- so the Modern look skins the new Remove button
            end
            line.spellID, line.refRow, line.refEntry = row.spellID, entry and row or nil, entry or nil
            line.text:SetText(row.name or tostring(row.spellID))
            if entry then
                line.check:SetChecked(not refRowHidden(row, entry))
            else
                line.check:SetChecked(not Journal:IsHidden(selectedBoss, row.spellID))
            end
            line.remove:SetShown(not entry and row.own and true or false)
            line:Show()
        end
        for i = #rows + 1, #rowPool do
            rowPool[i]:Hide()
        end
        rowsChild:SetHeight(math.max(1, #rows * ROW_H))
    end

    -- Adds a spell of your own to the selected boss's rows, after checking the game knows the ID.
    local function addSpell()
        local text = addEdit:GetText()
        local spellID = tonumber(text)
        if not spellID or spellID <= 0 or spellID ~= math.floor(spellID) then
            CRT:Print("Type a spell ID, a number.")
            return
        end
        local selectedBoss = ctx.selectedBoss()
        if not selectedBoss then
            CRT:Print("Pick a boss on the Review tab first.")
            return
        end
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if not ok or not name then
            CRT:Print("No spell with that ID.")
            return
        end
        Journal:AddCustom(selectedBoss, spellID)
        addEdit:SetText("")
        addEdit:ClearFocus()
    end

    -- View
    label(f, "View"):SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    UI.Help(f, "View", "How much time is visible at once (the mouse wheel over the timeline zooms too), how often the time axis is labelled, and how big the cast icons are."):SetPoint("TOPLEFT", f, "TOPLEFT", 60, -9)
    settingSlider(f, 8, -26, "Seconds visible", "span", 60, 600, 30, View.Format)
    place(UI.Dropdown(f, "Axis labels every", {
        options = GRIDS,
        labelWidth = 120,
        width = 150,
        get = function()
            return settings().grid
        end,
        set = function(key)
            Timeline:Set("grid", key)
        end,
    }), f, 8, -58)
    settingSlider(f, 8, -90, "Icon size", "iconSize", 16, 32, 1)

    -- Rows
    label(f, "Rows"):SetPoint("TOPLEFT", f, "TOPLEFT", 8, -132)
    UI.Help(f, "Rows", "The rows come from the boss's Encounter Journal abilities, then your own. Untick a row to hide it. Add a spell by its ID (the number in its Wowhead address) to track a cast the Journal does not list. The Journal is read out of combat with the Journal window closed.\n\nWith a reference shown, its own rows are listed instead, and unticking one hides it by name. Adding a spell works for recorded pulls only.\n\nA reference row gets its icon, and its match to a Journal ability, from the Encounter Journal, which is not read in combat; they can be blank until you are out of combat."):SetPoint("TOPLEFT", f, "TOPLEFT", 54, -133)
    bossLabel = label(f, "", "CRTFontSmall")
    bossLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -154)
    checkbox(f, 8, -172, "Hide rows with no casts in this pull", function()
        return settings().hideEmpty
    end, function(on)
        Timeline:Set("hideEmpty", on)
    end)
    addEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    addEdit:SetAutoFocus(false)
    addEdit:SetFontObject(CRTFontHighlight)
    addEdit:SetNumeric(true)
    addEdit:SetMaxLetters(8)
    addEdit:SetSize(90, 20)
    addEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -204)
    addEdit:SetScript("OnEnterPressed", addSpell)
    addEdit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    addButton = button(f, "Add", 50)
    addButton:SetPoint("LEFT", addEdit, "RIGHT", 8, 0)
    addButton:SetScript("OnClick", addSpell)
    label(f, "spell ID", "CRTFontSmall"):SetPoint("LEFT", addButton, "RIGHT", 8, 0)

    local scroll = CreateFrame("ScrollFrame", "CowfeeRaidToolsTimelineRowsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -232)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 330, 8)
    rowsChild = CreateFrame("Frame", nil, scroll)
    rowsChild:SetSize(300, 1)
    scroll:SetScrollChild(rowsChild)

    -- Deaths
    label(f, "Deaths"):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -8)
    UI.Help(f, "Deaths", "Whether the deaths share one row or each player gets a row, which roles to show, and whether to show only the first few deaths (0 shows all). With \"Deaths from recent pulls\" on, the overlay covers this many pulls, the shown one included."):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X + 60, -9)
    place(UI.Dropdown(f, "Death rows", {
        options = DEATH_ROWS,
        labelWidth = 120,
        width = 150,
        get = function()
            return settings().deathRows
        end,
        set = function(key)
            Timeline:Set("deathRows", key)
        end,
    }), f, RIGHT_X, -26)
    local roleX = RIGHT_X
    for _, role in ipairs({ { "TANK", "Tanks" }, { "HEALER", "Healers" }, { "DAMAGER", "Damage" } }) do
        checkbox(f, roleX, -62, role[2], function()
            return settings().roles[role[1]]
        end, function(on)
            local roles = settings().roles
            roles[role[1]] = on
            Timeline:Set("roles", roles)
        end)
        roleX = roleX + 100
    end
    settingSlider(f, RIGHT_X, -86, "First deaths only", "firstDeaths", 0, 20, 1, function(v)
        return v == 0 and "All" or tostring(v)
    end)
    settingSlider(f, RIGHT_X, -118, "Overlay pulls", "overlay", 2, 5, 1)

    -- Recording
    label(f, "Recording"):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -166)
    UI.Help(f, "Recording", "Pulls are saved on their own during raid boss fights, ten per boss, the oldest dropped first. Pulls shorter than the shortest pull are not kept."):SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X + 82, -167)
    checkbox(f, RIGHT_X, -186, "Record every pull", function()
        return settings().record
    end, function(on)
        Timeline:Set("record", on)
    end)
    settingSlider(f, RIGHT_X, -212, "Shortest pull (s)", "minPull", 5, 60, 1)
    deleteButton = button(f, "Delete this boss's pulls", 180)
    deleteButton:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -254)
    deleteButton:SetScript("OnClick", function()
        local boss = ctx.selectedBoss()
        if not boss then
            return
        end
        confirm("Delete every saved pull of %s?", ctx.bossName() or tostring(boss), "Delete", function()
            Timeline:DeleteBoss(boss)
        end)
    end)
    f:SetScript("OnShow", function()
        ctx.refresh()
    end)

    -- Redraws the controls from the settings, the rows list, and the Delete button.
    function tab:Refresh()
        for _, control in ipairs(controls) do
            control.refresh()
        end
        updateRows()
        local selectedBoss = ctx.selectedBoss()
        deleteButton:SetEnabled(selectedBoss ~= nil and #Timeline:Pulls(selectedBoss) > 0)
    end

    return tab
end
