local ADDON, CRT = ...

-- A spell lookup by name for any edit box: 3 letters or more list the matching spells of a boss's
-- Journal abilities, its reference rows and your spellbook (first source wins a spell), names holding
-- the letters first, then close spellings. A pick, Enter (the top match) or Escape goes back to the
-- owner; letters never change anything by themselves. The pop-out editor's Spell / Icon ID box and the
-- Mech Alerts panel's Icon box both use it.
--
-- local lookup = CRT.AlertSpellLookup.Attach(edit, opts) with opts:
--   encounterID()  the boss whose abilities are offered (nil: your spellbook only)
--   boss()         the boss's name, for its references
--   enabled()      false while letters must open nothing (a read-only draft)
--   onPick(match)  { spellID, name, icon, source } was picked
--   onClose()      the list closed without a pick (put the box's ID back)
--   levelFrame     the frame the list sits over (its strata, and a level above it); default the box's parent
--   alignRight     true to line the list's right edge up with the box's, for a box near the right edge
--   onCommit()     optional: the box is done with (Enter without a pick, or the focus left), so the owner
--                  can save a number typed in it
-- It sets the box's OnEnterPressed, OnEscapePressed and OnEditFocusLost. The owner calls
-- lookup:Text(text) from OnTextChanged: true means the text was a name (the list is handled), false a
-- number or nothing for the owner to read. lookup.list is the list frame, lookup:Hide() and :Close()
-- close it, and CRT.AlertSpellLookup.Forget() reads the spellbook again on the next lookup.

local Reminders = CRT.AlertReminders

local TEXT = {
    boss = "Boss",
    timeline = "Timeline",
    yours = "Yours",
    none = "No spells match",
}

local MIN_LETTERS = 3 -- letters before a name lookup opens
local ROWS = 8
local ROW_HEIGHT = 20
local WIDTH = 320
local LEVEL = 50 -- the list's frame level over its frame's, so it covers the rows below

local SpellLookup = {}
CRT.AlertSpellLookup = SpellLookup
SpellLookup.MIN_LETTERS, SpellLookup.WIDTH = MIN_LETTERS, WIDTH

local SOURCE_ORDER = { boss = 1, timeline = 2, yours = 3 }
local SOURCE_TAG = { boss = TEXT.boss, timeline = TEXT.timeline, yours = TEXT.yours }
local yours -- your spellbook's spells, read once until Forget, the first time a name is looked up

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readable(v)
    local T = CRT.Timeline
    if T and T.readable then
        return T.readable(v)
    end
    return true
end

local function validID(v)
    return type(v) == "number" and v > 0 and v or nil
end

local function readableString(v)
    return readable(v) and type(v) == "string" and v ~= ""
end

local function readableID(v)
    return readable(v) and validID(v) or nil
end

local function readableIcon(v)
    if readable(v) and v ~= nil and (type(v) == "number" or type(v) == "string") then
        return v
    end
end

function SpellLookup.Forget()
    yours = nil
end

-- Your spellbook's spells, { spellID, name, icon }: spells only (no future spells, flyouts or pet
-- actions), anything missing or secret skipped.
local function spellbook()
    if yours then
        return yours
    end
    yours = {}
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then
        return yours
    end
    local E = Enum
    local bank = E and E.SpellBookSpellBank and E.SpellBookSpellBank.Player or 0
    local spellType = E and E.SpellBookItemType and E.SpellBookItemType.Spell or 1
    local ok, count = pcall(SB.GetNumSpellBookSkillLines)
    if not (ok and readable(count) and type(count) == "number") then
        return yours
    end
    for i = 1, count do
        local okLine, line = pcall(SB.GetSpellBookSkillLineInfo, i)
        if okLine and type(line) == "table" then
            local offset, num = line.itemIndexOffset, line.numSpellBookItems
            if readable(offset) and readable(num) and type(offset) == "number" and type(num) == "number" then
                for index = offset + 1, offset + num do
                    local okItem, item = pcall(SB.GetSpellBookItemInfo, index, bank)
                    if okItem and type(item) == "table" then
                        local id, name, kind = readableID(item.spellID), item.name, item.itemType
                        local passive = item.isPassive
                        passive = readable(passive) and passive == true
                        if id and not passive and readableString(name) and readable(kind) and kind == spellType then
                            yours[#yours + 1] = { spellID = id, name = name, icon = readableIcon(item.iconID) }
                        end
                    end
                end
            end
        end
    end
    return yours
end

-- Every spell the lookup can offer, in source order, each spell once: { spellID, name, icon, source }.
local function candidates(encounterID, bossName)
    local out, seen = {}, {}
    local function add(id, name, icon, source)
        id = readableID(id)
        if id and not seen[id] and readableString(name) then
            seen[id] = true
            out[#out + 1] = { spellID = id, name = name, icon = readableIcon(icon), source = source }
        end
    end
    if type(encounterID) == "number" then
        local journal = {}
        local J = CRT.TimelineJournal
        if J and J.Rows then
            local ok, rows = pcall(J.Rows, J, encounterID)
            if ok and type(rows) == "table" then
                journal = rows
            end
        end
        for _, row in ipairs(journal) do
            if type(row) == "table" then
                -- your own rows added to the boss's list are not its abilities
                add(row.spellID, row.name, row.icon, row.own and "timeline" or "boss")
            end
        end
        local Ref, Lanes = CRT.TimelineReference, CRT.TimelineLanes
        if Ref and Lanes and Lanes.RowSpell then
            local okRefs, entries = pcall(Ref.ForBoss, Ref, encounterID, bossName)
            for _, entry in ipairs(okRefs and type(entries) == "table" and entries or {}) do
                for _, row in ipairs(entry.ref and entry.ref.rows or {}) do
                    local okSpell, id = pcall(Lanes.RowSpell, row, encounterID, journal)
                    id = okSpell and readableID(id)
                    if id and not seen[id] then
                        add(id, Reminders.SpellName(id) or row.name, nil, "timeline")
                    end
                end
            end
        end
    end
    for _, s in ipairs(spellbook()) do
        add(s.spellID, s.name, s.icon, "yours")
    end
    return out
end

-- Optimal string alignment distance (Levenshtein plus swapping two neighbours) between q and the len
-- characters of s from position from, both already lower case. Three rows, reused.
local osaRows = { {}, {}, {} }
local function nearDistance(q, s, from, len)
    local back2, back1, row = osaRows[1], osaRows[2], osaRows[3]
    for j = 0, len do
        back1[j] = j
    end
    local qPrev
    for i = 1, #q do
        local qc = q:byte(i)
        row[0] = i
        local sPrev
        for j = 1, len do
            local sc = s:byte(from + j - 1)
            local v = back1[j - 1] + (qc == sc and 0 or 1)
            if back1[j] + 1 < v then
                v = back1[j] + 1
            end
            if row[j - 1] + 1 < v then
                v = row[j - 1] + 1
            end
            if i > 1 and j > 1 and qc == sPrev and qPrev == sc and back2[j - 2] + 1 < v then
                v = back2[j - 2] + 1
            end
            row[j] = v
            sPrev = sc
        end
        qPrev = qc
        back2, back1, row = back1, row, back2
    end
    return back1[len]
end

-- The most typos a near match may have: more for a longer query, none under 4 letters (too many hits).
local function nearLimit(n)
    if n >= 10 then
        return 3
    elseif n >= 6 then
        return 2
    elseif n >= 4 then
        return 1
    end
    return -1
end

local function isWordByte(c)
    return (c >= 48 and c <= 57) or (c >= 97 and c <= 122) or c >= 128
end

-- The best distance of q to the name's start, or to the same length from any word start in it.
local function nameDistance(q, name)
    local n, total = #q, #name
    local best = nearDistance(q, name, 1, math.min(n, total))
    for at = 2, total do
        if best == 0 then
            break
        end
        if isWordByte(name:byte(at)) and not isWordByte(name:byte(at - 1)) then
            local d = nearDistance(q, name, at, math.min(n, total - at + 1))
            if d < best then
                best = d
            end
        end
    end
    return best
end

-- The spells for a query, in any case: names holding it (those starting with it first), then near
-- matches, close spellings of the name's start or of a word in it, by distance. Each group by source,
-- then by name.
function SpellLookup.Find(query, encounterID, bossName)
    local q = query:lower()
    local limit = nearLimit(#q)
    local found = {}
    for _, c in ipairs(candidates(encounterID, bossName)) do
        local key = c.name:lower()
        c.key = key
        local at = key:find(q, 1, true)
        if at then
            c.rank, c.dist = at == 1 and 0 or 1, 0
            found[#found + 1] = c
        else
            local d = nameDistance(q, key)
            if d <= limit then
                c.rank, c.dist = 2, d
                found[#found + 1] = c
            end
        end
    end
    table.sort(found, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        if a.dist ~= b.dist then
            return a.dist < b.dist
        end
        if a.source ~= b.source then
            return SOURCE_ORDER[a.source] < SOURCE_ORDER[b.source]
        end
        if a.key ~= b.key then
            return a.key < b.key
        end
        return a.spellID < b.spellID
    end)
    return found
end

local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and readable(tex) and tex ~= nil then
            return tex
        end
    end
end

-- The list frame: a column of rows under the box, over whatever is below it.
local function makeList(edit, opts, lookup)
    local parent = opts.levelFrame or edit:GetParent()
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(WIDTH, ROW_HEIGHT + 4)
    if opts.alignRight then
        list:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", 4, -2)
    else
        list:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -4, -2)
    end
    list:SetFrameStrata(parent:GetFrameStrata())
    list:SetFrameLevel((parent:GetFrameLevel() or 1) + LEVEL)
    list:EnableMouse(true)
    -- a click on the list between rows closes it too, so it is never left open without the focus
    list:SetScript("OnMouseDown", function()
        lookup:Close()
    end)
    local M = CRT.MOCHA
    list.edge = list:CreateTexture(nil, "BACKGROUND")
    list.edge:SetAllPoints()
    list.edge:SetColorTexture(M.edge[1], M.edge[2], M.edge[3], 1)
    list.bg = list:CreateTexture(nil, "BORDER")
    list.bg:SetPoint("TOPLEFT", 1, -1)
    list.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    list.bg:SetColorTexture(M.espresso[1], M.espresso[2], M.espresso[3], 1)
    list.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetSize(WIDTH - 4, ROW_HEIGHT)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_HEIGHT)
        r.highlight = r:CreateTexture(nil, "HIGHLIGHT")
        r.highlight:SetAllPoints()
        r.highlight:SetColorTexture(M.mocha[1], M.mocha[2], M.mocha[3], 0.5)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
        r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.tagText = r:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        r.tagText:SetPoint("RIGHT", -4, 0)
        r.tagText:SetWidth(56)
        r.tagText:SetJustifyH("RIGHT")
        r.tagText:SetTextColor(0.6, 0.6, 0.6)
        r.idText = r:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        r.idText:SetPoint("RIGHT", r.tagText, "LEFT", -6, 0)
        r.idText:SetWidth(56)
        r.idText:SetJustifyH("RIGHT")
        r.nameText = r:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        r.nameText:SetPoint("LEFT", ROW_HEIGHT + 2, 0)
        r.nameText:SetPoint("RIGHT", r.idText, "LEFT", -6, 0)
        r.nameText:SetJustifyH("LEFT")
        r.nameText:SetWordWrap(false)
        -- a match is picked; the grey "No spells match" row closes the list
        r:SetScript("OnClick", function(self)
            if self.match then
                lookup:Pick(self.match)
            else
                lookup:Close()
            end
        end)
        list.rows[i] = r
    end
    list:Hide()
    return list, parent
end

function SpellLookup.Attach(edit, opts)
    local lookup = { matches = {} }
    local list, over = makeList(edit, opts, lookup)
    lookup.list = list

    local function enabled()
        return not opts.enabled or opts.enabled()
    end

    function lookup:Hide()
        wipe(self.matches)
        list:Hide()
    end

    function lookup:Close()
        self:Hide()
        if opts.onClose then
            opts.onClose()
        end
    end

    function lookup:Pick(m)
        self:Hide()
        if m and enabled() and opts.onPick then
            opts.onPick(m)
        end
    end

    function lookup:Show(query)
        if not enabled() then
            return self:Hide()
        end
        local matches = self.matches
        wipe(matches)
        local encounterID = opts.encounterID and opts.encounterID()
        for i, m in ipairs(SpellLookup.Find(query, encounterID, opts.boss and opts.boss())) do
            if i > ROWS then
                break
            end
            matches[i] = m
        end
        for i, row in ipairs(list.rows) do
            local m = matches[i]
            row.match = m or false
            if m then
                row.icon:SetTexture(m.icon or spellIcon(m.spellID))
                row.icon:Show()
                row.nameText:SetText(m.name)
                row.nameText:SetTextColor(1, 1, 1)
                row.idText:SetText(tostring(m.spellID))
                row.tagText:SetText(SOURCE_TAG[m.source] or "")
                row:SetEnabled(true)
                row:Show()
            elseif i == 1 then
                row.icon:Hide()
                row.nameText:SetText(TEXT.none)
                row.nameText:SetTextColor(0.6, 0.6, 0.6)
                row.idText:SetText("")
                row.tagText:SetText("")
                row:Show()
            else
                row:Hide()
            end
        end
        list:SetHeight(math.max(1, #matches) * ROW_HEIGHT + 4)
        list:SetFrameStrata(over:GetFrameStrata())
        list:SetFrameLevel((over:GetFrameLevel() or 1) + LEVEL)
        list:Show()
    end

    -- The box's text: letters look a name up (true), anything else is the owner's to read (false).
    function lookup:Text(text)
        local s = trim(text)
        if s:find("%a") then
            if #s >= MIN_LETTERS then
                self:Show(s)
            else
                self:Hide()
            end
            return true
        end
        self:Hide()
        return false
    end

    -- Enter picks the top match of a name lookup; Escape or leaving the box closes the list
    edit:SetScript("OnEnterPressed", function(self)
        local top = list:IsShown() and lookup.matches[1]
        if top then
            lookup:Pick(top)
        elseif opts.onCommit then
            opts.onCommit()
        end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        lookup:Close()
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function()
        -- a click on the list takes the focus first: the click itself closes the list then
        if not (list:IsShown() and list:IsMouseOver()) then
            lookup:Close()
        end
        if opts.onCommit then
            opts.onCommit()
        end
    end)
    return lookup
end
