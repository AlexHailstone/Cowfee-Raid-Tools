local ADDON, CRT = ...

-- The Reminders tab of the Raid Notes page (Notes/Page.lua builds it into its tab): pick a boss and
-- see its Encounter Journal abilities, each with a tick that makes it a reminder, the times the
-- reminder gets and an Edit button, then your own reminders that are not tied to an ability. The
-- reminders themselves, their times and the editor are in Alerts/Reminders.lua and Alerts/Editor.lua,
-- which this tab only reads when it is built, after login.

local UI = CRT.UI

-- Every word on this tab, in one place so the wording is easy to change. Keep the keys, change the
-- text in quotes, save, and /reload.
local TEXT = {
    title = "Reminders",
    help = "Tick an ability to get a reminder for it, with the times of the boss's reference timeline. Untick it to turn the reminder off; it is kept, and ticking it again brings it back. Edit changes the text, the times, how it is shown and the difficulty. Your own reminder is one that is not tied to an ability.\n\nDouble-click an ability's row on the Timeline page to make a reminder from it.\n\nThe abilities are read from the Encounter Journal, out of combat only.",
    boss = "Boss",
    difficulty = "Difficulty",
    any = "Any",
    timesFrom = "Times from",
    timesFromHelpTitle = "Times from",
    timesFromHelp = "Which of the boss's reference timelines the times below are read from. A reminder with a difficulty of its own, or times you typed, keeps those.",
    none = "None on reference",
    ownReminder = "Your own reminder",
    edit = "Edit",
    unnamed = "Reminder",
}

local ROW_H = 24
local MAX_ROWS = 14
local ANY = "any"

local WHITE = { 1, 1, 1 }
local GREY = { 0.5, 0.5, 0.5 }

local function lower(s)
    return tostring(s or ""):lower()
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

-- The bosses the tabs can pick: the active note's boss first, then the bosses with recorded pulls,
-- then the bosses of the references. Only bosses with an encounter ID are listed, since that is what
-- a pull is matched on. { { key = encounterID, name, label } }. Shared with the Phases tab.
local function bossList()
    local list, seen = {}, {}
    local function add(key, name)
        if type(key) == "number" and not seen[key] then
            seen[key] = true
            name = (type(name) == "string" and name ~= "") and name or tostring(key)
            list[#list + 1] = { key = key, name = name, label = name }
        end
    end
    local known = {}
    for _, boss in ipairs(CRT.Timeline and CRT.Timeline:Bosses() or {}) do
        known[boss.encounterID] = boss.name
    end
    local Ref = CRT.TimelineReference
    local refs = Ref and Ref:List() or {}
    for _, entry in ipairs(refs) do
        local id = entry.ref.encounterID
        if id and not known[id] then
            known[id] = entry.ref.boss
        end
    end
    local _, record = CRT.Notes:Active()
    if record and type(record.encounterID) == "number" then
        add(record.encounterID, known[record.encounterID] or record.name)
    end
    for _, boss in ipairs(CRT.Timeline and CRT.Timeline:Bosses() or {}) do
        add(boss.encounterID, boss.name)
    end
    for _, entry in ipairs(refs) do
        add(entry.ref.encounterID, entry.ref.boss)
    end
    return list
end

local function bossName(list, key)
    for _, b in ipairs(list) do
        if b.key == key then
            return b.name
        end
    end
end

-- The tab -----------------------------------------------------------------------------------------

local selected, viewDiff
local tab, rows, items, offset, slider, bossDrop, diffDrop, fromDrop, ownButton
local listening = false

local function pickBoss(list)
    if not selected or not bossName(list, selected) then
        selected = list[1] and list[1].key or nil
        viewDiff = nil
    end
    return selected, selected and bossName(list, selected)
end

-- The ability rows of the boss from the Journal, then the reminders that match none of them.
local function buildItems(enc)
    local Reminders = CRT.AlertReminders
    local out = {}
    if not enc then
        return out
    end
    local journal = {}
    if CRT.TimelineJournal then
        local ok, res = pcall(CRT.TimelineJournal.Rows, CRT.TimelineJournal, enc)
        if ok and type(res) == "table" then
            journal = res
        end
    end
    local saved = Reminders:List(enc)
    local used = {}
    for _, jrow in ipairs(journal) do
        local item = { ability = jrow, spellID = jrow.spellID }
        for _, e in ipairs(saved) do
            if not used[e.id] and e.r.spellID == jrow.spellID then
                used[e.id] = true
                item.id, item.r = e.id, e.r
                break
            end
        end
        out[#out + 1] = item
    end
    for _, e in ipairs(saved) do
        if not used[e.id] then
            out[#out + 1] = { id = e.id, r = e.r, spellID = e.r.spellID }
        end
    end
    return out
end

local function itemName(item)
    if item.r and type(item.r.text) == "string" and item.r.text ~= "" then
        return item.r.text
    end
    if item.ability then
        return CRT.AlertReminders.SpellName(item.spellID) or item.ability.name or TEXT.unnamed
    end
    return CRT.AlertReminders.SpellName(item.spellID) or TEXT.unnamed
end

local function itemIcon(item)
    if item.ability and item.ability.icon then
        return item.ability.icon
    end
    if type(item.spellID) == "number" and item.spellID > 0 and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, item.spellID)
        if ok and tex ~= nil and (not (CRT.Timeline and CRT.Timeline.readable) or CRT.Timeline.readable(tex)) then
            return tex
        end
    end
end

-- The times column: what the reminder gets, from the reference of the difficulty on show.
local function timesText(enc, name, item)
    local Reminders = CRT.AlertReminders
    local r
    if item.r then
        r = copy(item.r)
    else
        r = { spellID = item.spellID, text = itemName(item), boss = name }
    end
    if not r.difficulty then
        r.difficulty = viewDiff
    end
    r.boss = r.boss or name
    local list, source, err = Reminders:Times(enc, r)
    if #list > 0 then
        return Reminders.FormatTimes(list), true
    end
    if source == "typed" and err then
        return err, false
    end
    return TEXT.none, false
end

local function refresh()
    if not tab then
        return
    end
    local list = bossList()
    local enc, name = pickBoss(list)
    items = buildItems(enc)
    local maxOffset = math.max(0, #items - MAX_ROWS)
    offset = math.max(0, math.min(offset or 0, maxOffset))
    for i, row in ipairs(rows) do
        local item = items[offset + i]
        if item then
            local on = not item.r or item.r.enabled ~= false
            row.item = item
            row.icon:SetTexture(itemIcon(item))
            row.icon:SetShown(itemIcon(item) ~= nil)
            row.name:SetText(itemName(item))
            local color = (item.r and on) and WHITE or GREY
            row.name:SetTextColor(color[1], color[2], color[3])
            row.check:SetChecked(item.r ~= nil and on)
            local text, has = timesText(enc, name, item)
            row.times:SetText(text)
            local tc = has and WHITE or GREY
            row.times:SetTextColor(tc[1], tc[2], tc[3])
            row.frame:Show()
        else
            row.item = nil
            row.frame:Hide()
        end
    end
    if slider then
        slider:SetMinMaxValues(0, maxOffset)
        slider:SetValue(offset)
        slider:SetShown(maxOffset > 0)
    end
    for _, d in ipairs({ bossDrop, diffDrop, fromDrop }) do
        d.refresh()
    end
end

local function scrollBy(n)
    offset = (offset or 0) + n
    refresh()
end

-- The references of the boss on show, yours first.
local function bossRefs()
    local Ref = CRT.TimelineReference
    if not (Ref and selected) then
        return {}
    end
    local list = bossList()
    return Ref:ForBoss(selected, bossName(list, selected))
end

local function shownReference()
    local refs = bossRefs()
    if viewDiff then
        for _, entry in ipairs(refs) do
            if entry.ref.difficulty and lower(entry.ref.difficulty) == lower(viewDiff) then
                return entry
            end
        end
    end
    return refs[1]
end

local function onTick(row)
    local item = row.item
    local list = bossList()
    local enc, name = pickBoss(list)
    if not (item and enc) then
        return
    end
    local Reminders = CRT.AlertReminders
    local on = row.check:GetChecked() and true or false
    if item.id then
        local r = Reminders:Get(enc, item.id)
        if r then
            r.enabled = on
            Reminders:Save(enc, item.id, r)
        end
    elseif on then
        Reminders:Save(enc, nil, { spellID = item.spellID, boss = name, text = itemName(item), enabled = true })
    end
    refresh()
end

local function onEdit(row)
    local item = row.item
    local list = bossList()
    local enc, name = pickBoss(list)
    if not (item and enc) then
        return
    end
    if item.id then
        CRT.AlertEditor:Open(enc, item.id)
    else
        CRT.AlertEditor:Open(enc, nil, { spellID = item.spellID, text = itemName(item), boss = name })
    end
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
    frame:SetSize(790, ROW_H - 2)
    frame:SetPoint("TOPLEFT", 8, -92 - (i - 1) * ROW_H)
    local row = { frame = frame }
    row.check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    row.check:SetSize(24, 24)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function()
        onTick(row)
    end)
    row.icon = frame:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 30, 0)
    row.name = frame:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    row.name:SetPoint("LEFT", 56, 0)
    row.name:SetWidth(210)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.times = frame:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.times:SetPoint("LEFT", 276, 0)
    row.times:SetWidth(430)
    row.times:SetJustifyH("LEFT")
    row.times:SetWordWrap(false)
    row.edit = makeButton(frame, TEXT.edit, 56, 20)
    row.edit:SetPoint("RIGHT", 0, 0)
    row.edit:SetScript("OnClick", function()
        onEdit(row)
    end)
    return row
end

local function build(f)
    tab = f
    selected, viewDiff, offset = nil, nil, 0

    local title = f:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(TEXT.title)
    UI.Help(f, TEXT.title, TEXT.help):SetPoint("LEFT", title, "RIGHT", 6, 0)

    bossDrop = UI.Dropdown(f, TEXT.boss, {
        labelWidth = 40,
        width = 230,
        options = function()
            local out = {}
            for _, b in ipairs(bossList()) do
                out[#out + 1] = { key = b.key, label = b.label }
            end
            return out
        end,
        get = function()
            return (pickBoss(bossList()))
        end,
        set = function(key)
            selected, viewDiff, offset = key, nil, 0
            refresh()
        end,
    })
    bossDrop:SetPoint("TOPLEFT", 8, -30)

    diffDrop = UI.Dropdown(f, TEXT.difficulty, {
        labelWidth = 60,
        width = 150,
        options = function()
            local out = { { key = ANY, label = TEXT.any } }
            local seen = {}
            for _, entry in ipairs(bossRefs()) do
                local d = entry.ref.difficulty
                if type(d) == "string" and d ~= "" and not seen[lower(d)] then
                    seen[lower(d)] = true
                    out[#out + 1] = { key = d, label = d }
                end
            end
            return out
        end,
        get = function()
            return viewDiff or ANY
        end,
        set = function(key)
            viewDiff = key ~= ANY and key or nil
            refresh()
        end,
    })
    diffDrop:SetPoint("TOPLEFT", 300, -30)

    fromDrop = UI.Dropdown(f, TEXT.timesFrom, {
        labelWidth = 70,
        width = 330,
        options = function()
            local out = {}
            for _, entry in ipairs(bossRefs()) do
                out[#out + 1] = { key = entry.key, label = CRT.TimelineReference.Label(entry.ref) }
            end
            return out
        end,
        get = function()
            local entry = shownReference()
            return entry and entry.key
        end,
        set = function(key)
            for _, entry in ipairs(bossRefs()) do
                if entry.key == key then
                    local d = entry.ref.difficulty
                    viewDiff = (type(d) == "string" and d ~= "") and d or nil
                end
            end
            refresh()
        end,
    })
    fromDrop:SetPoint("TOPLEFT", 8, -58)
    UI.Help(f, TEXT.timesFromHelpTitle, TEXT.timesFromHelp):SetPoint("LEFT", fromDrop, "RIGHT", 6, 0)

    rows = {}
    for i = 1, MAX_ROWS do
        rows[i] = makeRow(f, i)
    end
    f.rows = rows

    slider = CreateFrame("Slider", nil, f)
    slider:SetOrientation("VERTICAL")
    slider:SetSize(10, MAX_ROWS * ROW_H - 4)
    slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -92)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.2, 0.2, 0.2, 0.6)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(10, 24)
        thumb:SetVertexColor(1, 0.82, 0)
    end
    slider:SetScript("OnValueChanged", function(_, value)
        local v = math.floor((value or 0) + 0.5)
        if v ~= offset then
            offset = v
            refresh()
        end
    end)
    slider:Hide()

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        scrollBy(delta > 0 and -1 or 1)
    end)
    f.scroll = scrollBy

    ownButton = makeButton(f, TEXT.ownReminder, 170, 24)
    ownButton:SetPoint("TOPLEFT", 8, -92 - MAX_ROWS * ROW_H - 8)
    ownButton:SetScript("OnClick", function()
        local enc, name = pickBoss(bossList())
        if enc then
            CRT.AlertEditor:Open(enc, nil, { boss = name })
        end
    end)
    f.ownButton = ownButton

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

CRT.NoteReminders = { Build = build, Refresh = refresh, BossList = bossList }
