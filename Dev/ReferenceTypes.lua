local ADDON, CRT = ...

-- DEVELOPER ONLY. The Reference types window (Development page): set each ability's types on a
-- reference timeline with dropdowns, instead of writing (type ...) by hand. Pick a reference, then for
-- each ability a Main type (which colors the row) and any other types (Also, shown as dots).
--   Save as my copy  writes the text as your own reference (or updates it), so the Timeline shows the
--                    colors straight away; your copy is listed before the shipped one
--   Export           the text, to paste to Claude and ship in the boss's file
--   Delete my copy   drops your copy, so the shipped reference shows again
-- Only the (type ...) option of each ability line changes; times, bars, leads, spell IDs, colors and
-- comments are kept. This file never ships: its .toc line is inside the do-not-package block.

local Editor = {}
CRT.ReferenceTypes = Editor

local UI = CRT.UI
local Reference = CRT.TimelineReference

local ROW_H = 30
local TOP = 100 -- where the ability rows start
local HEADERS = { boss = true, difficulty = true, length = true, encounter = true, phase = true }

local win
local entryKey -- the reference being edited
local baseText -- its text when loaded
local rows = {} -- { name, main, also = { [type] = true } } per ability, in text order
local widgets = {} -- one row of controls per ability

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The ability lines of reference text, the same lines Reference.Parse reads as abilities.
local function isAbility(line)
    line = trim((line:gsub("\r", "")))
    if line == "" or line:sub(1, 1) == "#" then
        return false
    end
    local key = line:match("^(%a+)%s*:")
    return not (key and HEADERS[key:lower()])
end

-- Where the times start: the first ':' outside round and square brackets (a lead can be 0:07).
local function timesColon(line)
    local depth = 0
    for i = 1, #line do
        local c = line:sub(i, i)
        if c == "(" or c == "[" then
            depth = depth + 1
        elseif c == ")" or c == "]" then
            depth = math.max(0, depth - 1)
        elseif c == ":" and depth == 0 then
            return i
        end
    end
end

-- One ability line with its type option replaced by types (a list, main first; empty for none).
local function setLineTypes(line, types)
    local cr = line:sub(-1) == "\r" and "\r" or ""
    line = cr == "" and line or line:sub(1, -2)
    local at = timesColon(line)
    if not at then
        return line .. cr
    end
    local head, times = line:sub(1, at - 1), line:sub(at)
    local indent = head:match("^(%s*)")
    local name = trim(head:match("^%s*([^%[%(]+)") or "")
    local spell = head:match("%[[^%]]*%]")
    local opts = {}
    if #types > 0 then
        opts[1] = "type " .. table.concat(types, " ")
    end
    for group in head:gmatch("%((.-)%)") do
        for opt in (group .. ","):gmatch("([^,]*),") do
            opt = trim(opt)
            if opt ~= "" and not opt:lower():match("^type%s") then
                opts[#opts + 1] = opt
            end
        end
    end
    local out = indent .. name
    if spell then
        out = out .. " " .. spell
    end
    if #opts > 0 then
        out = out .. " (" .. table.concat(opts, ", ") .. ")"
    end
    return out .. times .. cr
end

-- The text with every ability line's types set from list (one entry per ability, in text order).
function Editor.ApplyTypes(text, list)
    local out, i = {}, 0
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        if isAbility(raw) then
            i = i + 1
            raw = setLineTypes(raw, list[i] or {})
        end
        out[#out + 1] = raw
    end
    return table.concat(out, "\n")
end

local function typesOf(row)
    local list = {}
    if row.main then
        list[1] = row.main
    end
    for _, key in ipairs(Reference.TYPE_ORDER) do
        if row.also[key] and key ~= row.main then
            list[#list + 1] = key
        end
    end
    return list
end

local function currentText()
    if not baseText then
        return nil
    end
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = typesOf(row)
    end
    return Editor.ApplyTypes(baseText, list)
end

local function load(key)
    entryKey, baseText = key, nil
    wipe(rows)
    local entry = key and Reference:Find(key)
    if not entry then
        return
    end
    baseText = entry.text
    for _, r in ipairs(entry.ref.rows) do
        local row = { name = r.name, also = {} }
        for i, t in ipairs(r.types or {}) do
            if i == 1 then
                row.main = t
            else
                row.also[t] = true
            end
        end
        rows[#rows + 1] = row
    end
end

local function referenceOptions()
    local list = {}
    for _, entry in ipairs(Reference:List()) do
        local ref = entry.ref
        list[#list + 1] = {
            key = entry.key,
            label = ref.boss .. (ref.difficulty and (" \194\183 " .. ref.difficulty) or "") .. (entry.own and " (your copy)" or " (shipped)"),
        }
    end
    return list
end

local MAIN_OPTIONS = { { key = "none", label = "None" } }
for _, key in ipairs(Reference.TYPE_ORDER) do
    local t = Reference.TYPES[key]
    local c = t.color
    MAIN_OPTIONS[#MAIN_OPTIONS + 1] = {
        key = key,
        label = string.format("|cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), key),
    }
end

local function colored(key)
    local c = Reference.TYPES[key].color
    return string.format("|cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), key)
end

local refresh

-- One ability's controls: its name (in its main type's color) with the Main dropdown, and Also.
local function widgetRow(i)
    if widgets[i] then
        return widgets[i]
    end
    local w = {}
    w.main = UI.Dropdown(win, "", {
        options = MAIN_OPTIONS,
        labelWidth = 170,
        width = 110,
        get = function()
            return rows[i] and rows[i].main or "none"
        end,
        set = function(key)
            if rows[i] then
                rows[i].main = key ~= "none" and key or nil
                rows[i].also[key] = nil
                refresh()
            end
        end,
    })
    w.main:SetPoint("TOPLEFT", 14, -(TOP + (i - 1) * ROW_H))
    w.also = CreateFrame("DropdownButton", nil, win, "WowStyle1DropdownTemplate")
    w.also:SetWidth(110)
    w.also:SetPoint("LEFT", w.main, "RIGHT", 10, 0)
    w.also:SetupMenu(function(_, root)
        for _, key in ipairs(Reference.TYPE_ORDER) do
            if not (rows[i] and rows[i].main == key) then
                root:CreateCheckbox(colored(key), function()
                    return rows[i] and rows[i].also[key] or false
                end, function()
                    if rows[i] then
                        rows[i].also[key] = not rows[i].also[key] or nil
                        refresh()
                    end
                end, key)
            end
        end
    end)
    UI:SkinDropdown(w.also)
    w.alsoText = win:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    w.alsoText:SetPoint("LEFT", w.also, "RIGHT", 8, 0)
    w.alsoText:SetWidth(150)
    w.alsoText:SetJustifyH("LEFT")
    w.alsoText:SetWordWrap(false)
    widgets[i] = w
    return w
end

local function button(text, width)
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetNormalFontObject(CRTFontButtonSmall)
    b:SetHighlightFontObject(CRTFontButtonSmallHighlight)
    b:SetDisabledFontObject(CRTFontButtonSmallDisable)
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

refresh = function()
    if not win then
        return
    end
    win.pick.refresh()
    for i = 1, math.max(#rows, #widgets) do
        local row = rows[i]
        if row then
            local w = widgetRow(i)
            w.main.Label:SetText(row.name)
            local c = row.main and Reference.TYPES[row.main].color
            if c then
                w.main.Label:SetTextColor(c[1], c[2], c[3])
            else
                w.main.Label:SetTextColor(1, 1, 1)
            end
            w.main.refresh()
            w.also:GenerateMenu()
            local extra = {}
            for _, key in ipairs(typesOf(row)) do
                if key ~= row.main then
                    extra[#extra + 1] = colored(key)
                end
            end
            w.alsoText:SetText(#extra > 0 and ("+ " .. table.concat(extra, ", ")) or "")
            w.main:Show()
            w.also:Show()
            w.alsoText:Show()
        elseif widgets[i] then
            widgets[i].main:Hide()
            widgets[i].also:Hide()
            widgets[i].alsoText:Hide()
        end
    end
    local entry = entryKey and Reference:Find(entryKey)
    win.delete:SetEnabled(entry and entry.own or false)
    win.status:SetText(not entry and "Pick a reference." or entry.own and "Your copy: the Timeline shows it before the shipped one." or "The shipped reference. Save as my copy to see the colors on the Timeline.")
    win:SetHeight(TOP + math.max(#rows, 1) * ROW_H + 90)
end

local function build()
    win = CreateFrame("Frame", "CowfeeRaidToolsReferenceTypes", UIParent, "BasicFrameTemplateWithInset")
    UI:StyleWindow(win)
    win:SetSize(600, 400)
    win:SetPoint("CENTER")
    UI:RegisterLayer("popups", win)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving(true) end)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "CowfeeRaidToolsReferenceTypes")
    UI.SetFrameTitle(win, "Reference types (dev)")

    win.pick = UI.Dropdown(win, "Reference", {
        options = referenceOptions,
        labelWidth = 70,
        width = 320,
        get = function()
            return entryKey
        end,
        set = function(key)
            load(key)
            refresh()
        end,
    })
    win.pick:SetPoint("TOPLEFT", 14, -30)
    UI.Help(win, "Reference types", "Main colors the ability's row on the Timeline; Also adds a dot per type, and the tooltip lists them all. No type is a plain white row.\n\nSave as my copy to see it on the Timeline, then Export and paste the text to Claude, who ships it in the boss's file.\n\n" .. Reference.Legend()):SetPoint("LEFT", win.pick, "RIGHT", 6, 0)

    local head = win:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    head:SetPoint("TOPLEFT", 14, -74)
    head:SetText("Ability")
    local headMain = win:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    headMain:SetPoint("TOPLEFT", 189, -74)
    headMain:SetText("Main type")
    local headAlso = win:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    headAlso:SetPoint("TOPLEFT", 309, -74)
    headAlso:SetText("Also")

    win.status = win:CreateFontString(nil, "OVERLAY", "CRTFontDisableSmall")
    win.status:SetPoint("BOTTOMLEFT", 14, 46)
    win.status:SetWidth(570)
    win.status:SetJustifyH("LEFT")

    local save = button("Save as my copy", 130)
    save:SetPoint("BOTTOMLEFT", 14, 16)
    save:SetScript("OnClick", function()
        local entry = entryKey and Reference:Find(entryKey)
        local text = currentText()
        if not entry or not text then
            CRT:Print("Pick a reference first.")
            return
        end
        local ok, errors
        if entry.own then
            ok, errors = Reference:Update(entryKey, text)
        else
            ok, errors = Reference:Add(text)
            if ok then
                entryKey = ok
            end
        end
        if not ok then
            CRT:Print("Couldn't save: " .. table.concat(errors or {}, "; "))
            return
        end
        baseText = text
        CRT:Print("Saved your copy of the " .. (entry.ref.boss or "boss") .. " reference.")
        refresh()
    end)
    local export = button("Export", 100)
    export:SetPoint("LEFT", save, "RIGHT", 6, 0)
    export:SetScript("OnClick", function()
        local text = currentText()
        if not text then
            CRT:Print("Pick a reference first.")
            return
        end
        CRT.ConsumablesTools:ShowText("Reference with types (Ctrl+C to copy, paste to Claude)", text)
    end)
    win.delete = button("Delete my copy", 120)
    win.delete:SetPoint("LEFT", export, "RIGHT", 6, 0)
    win.delete:SetScript("OnClick", function()
        local entry = entryKey and Reference:Find(entryKey)
        if entry and entry.own then
            Reference:Delete(entryKey)
            CRT:Print("Deleted your copy; the shipped reference shows again.")
            local list = referenceOptions()
            load(list[1] and list[1].key or nil)
            refresh()
        end
    end)

    win:SetScript("OnShow", refresh)
    UI:SkinTree(win)
end

function Editor:Toggle()
    if not win then
        build()
        local list = referenceOptions()
        load(list[1] and list[1].key or nil)
    end
    win:SetShown(not win:IsShown())
    refresh()
end
