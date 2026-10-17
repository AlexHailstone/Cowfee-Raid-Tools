local ADDON, CRT = ...

-- DEVELOPER ONLY. A layout editor for the main panel: /crt dev turns it on. Hover to highlight a piece
-- of a page (text, button, box, slider), click to select it, then:
--   drag, or arrow keys        move it (1 pixel, Shift for 10)
--   mouse wheel                width (Shift for 10)
--   Ctrl + mouse wheel         height (Shift for 10)
--   + and -                    font size of selected text
-- Changes are kept in CRTDB.dev.overrides as differences from the code's own layout, applied again
-- after each /reload, and Export lists them so they can be written into the real code. Once they are,
-- /crt dev clear (or Reset page) drops them. Each change also remembers where the code had the piece
-- (base). If the code has since moved it, for example because the change was written in, the change
-- is out of date and is skipped with a chat message, so it is never applied twice.
--
-- This file never ships: the .toc line that loads it is inside a do-not-package block, and the Dev
-- folder is in .pkgmeta's ignore list, so release zips have neither. It is off in combat.

local UI = CRT.UI
local Dev = {}
CRT.Dev = Dev

local on = false
local moving = false -- Move pieces: only then does the overlay take clicks, so the panel works as usual
local overlay, info, hoverBox, selectBox
local hovered, selected
local applied = setmetatable({}, { __mode = "k" }) -- objects already given their saved override
local dragging, lastX, lastY

local function db()
    CRT.db.dev = CRT.db.dev or {}
    CRT.db.dev.overrides = CRT.db.dev.overrides or {}
    return CRT.db.dev
end

-- Finding the pieces ---------------------------------------------------------------------------
-- Each piece gets a path that stays the same between reloads: the page key, then the index of each
-- child frame (c) or font string (r) on the way down, in the order the code created them.

local function shownPage()
    for key, page in pairs(UI.pages) do
        if page.frame and page.frame:IsVisible() then
            return key, page.frame
        end
    end
end

local function walk(frame, path, out)
    local regions = { frame:GetRegions() }
    for i, r in ipairs(regions) do
        if r:GetObjectType() == "FontString" then
            out[#out + 1] = { obj = r, path = path .. ".r" .. i }
        end
    end
    local children = { frame:GetChildren() }
    for i, child in ipairs(children) do
        if child ~= overlay and child ~= info then
            local p = path .. ".c" .. i
            out[#out + 1] = { obj = child, path = p }
            walk(child, p, out)
        end
    end
end

-- Every piece of every built page, and of the panel's frame outside the pages (title, menu, Previews).
local function allPieces()
    local out = {}
    for key, page in pairs(UI.pages) do
        if page.frame then
            walk(page.frame, key, out)
        end
    end
    if UI.frame then
        local regions = { UI.frame:GetRegions() }
        for i, r in ipairs(regions) do
            if r:GetObjectType() == "FontString" then
                out[#out + 1] = { obj = r, path = "panel.r" .. i }
            end
        end
        for i, child in ipairs({ UI.frame:GetChildren() }) do
            if child ~= UI.frame.content and child ~= overlay and child ~= info then
                local p = "panel.c" .. i
                out[#out + 1] = { obj = child, path = p }
                walk(child, p, out)
            end
        end
    end
    return out
end

local function label(obj)
    local text
    if obj.GetText then
        text = obj:GetText()
    elseif obj.GetFontString and obj:GetFontString() then
        text = obj:GetFontString():GetText()
    end
    if type(text) == "string" and text ~= "" then
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")
        return #text > 50 and (text:sub(1, 47) .. "...") or text
    end
    return nil
end

-- A piece's effective scale. Text and other regions ask their parent frame, in case they cannot.
local function scaleOf(obj)
    if obj.GetEffectiveScale then
        local ok, s = pcall(obj.GetEffectiveScale, obj)
        if ok and s then
            return s
        end
    end
    return obj:GetParent():GetEffectiveScale()
end

-- The smallest visible piece of the shown page (or the panel frame) under the cursor.
local function pieceUnderCursor()
    local key = shownPage()
    local x, y = GetCursorPosition()
    local best, bestArea
    for _, piece in ipairs(allPieces()) do
        local obj = piece.obj
        local onPage = piece.path:sub(1, #(key or "") + 1) == (key or "") .. "." or piece.path:sub(1, 6) == "panel."
        if onPage and obj:IsVisible() then
            local left, bottom, width, height = obj:GetRect()
            if left and width and width > 0 and height > 0 then
                local s = scaleOf(obj)
                local cx, cy = x / s, y / s
                if cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height then
                    local area = width * height
                    if not bestArea or area < bestArea then
                        best, bestArea = piece, area
                    end
                end
            end
        end
    end
    return best
end

-- Changing a piece ------------------------------------------------------------------------------

-- Where the code put a piece: its first anchor's offsets, its size and its font size, rounded.
local function snapshot(obj)
    local _, _, _, x, y = obj:GetPoint(1)
    local fs = obj.GetFont and obj or (obj.GetFontString and obj:GetFontString()) or nil
    local size = fs and select(2, fs:GetFont()) or 0
    local function r(v)
        return math.floor((v or 0) + 0.5)
    end
    return { x = r(x), y = r(y), w = r(obj:GetWidth()), h = r(obj:GetHeight()), font = r(size) }
end

local function sameSnapshot(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h and a.font == b.font
end

-- The saved change for a piece, made on its first edit with a snapshot of the code's layout.
local function override(path, obj)
    local o = db().overrides[path]
    if not o then
        o = { dx = 0, dy = 0, dw = 0, dh = 0, font = 0, base = obj and snapshot(obj) or nil }
        db().overrides[path] = o
    end
    return o
end

-- Moves every anchor point by the same amount, so a piece anchored at two corners keeps its size.
local function shift(obj, dx, dy)
    local points = {}
    for i = 1, obj:GetNumPoints() do
        points[i] = { obj:GetPoint(i) }
    end
    obj:ClearAllPoints()
    for _, p in ipairs(points) do
        obj:SetPoint(p[1], p[2], p[3], (p[4] or 0) + dx, (p[5] or 0) + dy)
    end
end

-- A piece held by one point gets a new size. One stretched between points gets its right or bottom
-- anchors moved instead, since its size comes from them.
local function resize(obj, dw, dh)
    if obj:GetNumPoints() > 1 then
        local points = {}
        for i = 1, obj:GetNumPoints() do
            points[i] = { obj:GetPoint(i) }
        end
        obj:ClearAllPoints()
        for _, p in ipairs(points) do
            local x, y = p[4] or 0, p[5] or 0
            if p[1]:find("RIGHT") then
                x = x + dw
            end
            if p[1]:find("BOTTOM") then
                y = y - dh
            end
            obj:SetPoint(p[1], p[2], p[3], x, y)
        end
    else
        obj:SetSize(math.max(1, obj:GetWidth() + dw), math.max(1, obj:GetHeight() + dh))
    end
end

local function fontOf(obj)
    if obj.GetFont then
        return obj
    end
    return obj.GetFontString and obj:GetFontString() or nil
end

local function changeFont(obj, delta)
    local fs = fontOf(obj)
    if not fs then
        return false
    end
    local path, size, flags = fs:GetFont()
    if not path then
        return false
    end
    fs:SetFont(path, math.max(6, size + delta), flags or "")
    return true
end

-- Puts a saved override on a piece the first time the piece is seen after a /reload.
local stale = {}

local function applyOverride(piece)
    local o = db().overrides[piece.path]
    if not o or applied[piece.obj] then
        return
    end
    applied[piece.obj] = true
    -- The code moved this piece since the change was made: the change is out of date.
    if o.base and not sameSnapshot(o.base, snapshot(piece.obj)) then
        stale[#stale + 1] = piece.path
        return
    end
    if o.dx ~= 0 or o.dy ~= 0 then
        shift(piece.obj, o.dx, o.dy)
    end
    if o.dw ~= 0 or o.dh ~= 0 then
        resize(piece.obj, o.dw, o.dh)
    end
    if o.font ~= 0 then
        changeFont(piece.obj, o.font)
    end
end

function Dev:ApplyAll()
    local before = #stale
    for _, piece in ipairs(allPieces()) do
        applyOverride(piece)
    end
    if #stale > before then
        CRT:Print(format("Skipped %d dev layout change%s because the code has moved %s since: %s. Type /crt dev clear to drop old changes.", #stale - before, #stale - before == 1 and "" or "s", #stale - before == 1 and "that piece" or "those pieces", table.concat(stale, ", ", before + 1)))
    end
end

-- Pages are built when first shown, so overrides go on after each page change.
local selectPage = UI.SelectPage
UI.SelectPage = function(self, key)
    selectPage(self, key)
    Dev:ApplyAll()
end

-- The overlay and boxes ---------------------------------------------------------------------------

local function outline(r, g, b)
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetFrameStrata("TOOLTIP")
    box.edges = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = box:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, 1)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if i <= 2 then
            t:SetHeight(1)
        else
            t:SetWidth(1)
        end
    end
    box:Hide()
    return box
end

local function frameAround(box, obj)
    if not obj then
        box:Hide()
        return
    end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", obj, "TOPLEFT", -1, 1)
    box:SetPoint("BOTTOMRIGHT", obj, "BOTTOMRIGHT", 1, -1)
    box:Show()
end

local function describe(piece)
    if not piece then
        return "Nothing selected. Hover and click a piece of the panel."
    end
    local obj = piece.obj
    local lines = {
        "|cffffd100" .. obj:GetObjectType() .. "|r  " .. piece.path,
        label(obj) and ('"' .. label(obj) .. '"') or "(no text)",
    }
    for i = 1, obj:GetNumPoints() do
        local p, rel, rp, x, y = obj:GetPoint(i)
        local relName = rel and (rel.GetName and rel:GetName()) or nil
        lines[#lines + 1] = format("%s to %s of %s: %.1f, %.1f", p, rp or "?", relName or "parent", x or 0, y or 0)
    end
    lines[#lines + 1] = format("size %.1f x %.1f", obj:GetWidth(), obj:GetHeight())
    local fs = fontOf(obj)
    if fs then
        local _, size = fs:GetFont()
        lines[#lines + 1] = format("font size %.1f", size or 0)
    end
    local o = db().overrides[piece.path]
    if o then
        lines[#lines + 1] = format("|cff80ff80changed: move %d, %d  size %d, %d  font %d|r", o.dx, o.dy, o.dw, o.dh, o.font)
    end
    return table.concat(lines, "\n")
end

local function refreshInfo()
    if info then
        info.text:SetText(describe(selected))
        info:SetHeight(info.text:GetStringHeight() + 150)
    end
    frameAround(selectBox, selected and selected.obj)
end

-- Records a change on the selected piece and applies it.
local function edit(dx, dy, dw, dh, font)
    if not selected then
        return
    end
    local o = override(selected.path, selected.obj)
    applied[selected.obj] = true
    if dx ~= 0 or dy ~= 0 then
        shift(selected.obj, dx, dy)
        o.dx, o.dy = o.dx + dx, o.dy + dy
    end
    if dw ~= 0 or dh ~= 0 then
        resize(selected.obj, dw, dh)
        o.dw, o.dh = o.dw + dw, o.dh + dh
    end
    if font ~= 0 and changeFont(selected.obj, font) then
        o.font = o.font + font
    end
    refreshInfo()
end

local function exportText()
    local lines = {
        "Cowfee Raid Tools layout changes from the dev editor. Each line: the piece, its text, the change, and where it is now.",
        "",
    }
    local byPath = {}
    for _, piece in ipairs(allPieces()) do
        byPath[piece.path] = piece
    end
    local paths = {}
    for path in pairs(db().overrides) do
        paths[#paths + 1] = path
    end
    table.sort(paths)
    for _, path in ipairs(paths) do
        local o = db().overrides[path]
        local piece = byPath[path]
        local now = ""
        if piece then
            local obj = piece.obj
            local points = {}
            for i = 1, obj:GetNumPoints() do
                local p, _, rp, x, y = obj:GetPoint(i)
                points[#points + 1] = format("%s/%s %.0f,%.0f", p, rp or "?", x or 0, y or 0)
            end
            now = format(" | now %s, size %.0fx%.0f", table.concat(points, "; "), obj:GetWidth(), obj:GetHeight())
        end
        local text = piece and label(piece.obj) or nil
        lines[#lines + 1] = format("%s%s | move %d,%d size %d,%d font %d%s", path, text and (' "' .. text .. '"') or "", o.dx, o.dy, o.dw, o.dh, o.font, now)
    end
    if #paths == 0 then
        lines[#lines + 1] = "No changes yet."
    end
    return table.concat(lines, "\n")
end

local function makeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

local function build()
    if overlay then
        return
    end
    hoverBox = outline(0.2, 0.9, 1)
    selectBox = outline(1, 0.82, 0)

    -- Covers the panel and takes every click, so the panel's own buttons do not fire while editing.
    overlay = CreateFrame("Frame", nil, UI.frame)
    overlay:SetAllPoints(UI.frame)
    overlay:SetFrameStrata("FULLSCREEN")
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    overlay:EnableKeyboard(true)
    local tint = overlay:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints()
    tint:SetColorTexture(0.2, 0.9, 1, 0.04)

    local elapsed = 0
    overlay:SetScript("OnUpdate", function(_, dt)
        if dragging and selected then
            local x, y = GetCursorPosition()
            local s = scaleOf(selected.obj)
            local dx, dy = math.floor((x - lastX) / s + 0.5), math.floor((y - lastY) / s + 0.5)
            if dx ~= 0 or dy ~= 0 then
                edit(dx, dy, 0, 0, 0)
                lastX, lastY = lastX + dx * s, lastY + dy * s
            end
        end
        elapsed = elapsed + dt
        if elapsed > 0.05 then
            elapsed = 0
            hovered = pieceUnderCursor()
            frameAround(hoverBox, hovered and hovered.obj)
        end
    end)
    overlay:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            selected = pieceUnderCursor()
            if selected then
                dragging = true
                lastX, lastY = GetCursorPosition()
            end
            refreshInfo()
        elseif button == "RightButton" then
            selected = nil
            refreshInfo()
        end
    end)
    overlay:SetScript("OnMouseUp", function()
        dragging = false
    end)
    -- Closing the panel (Escape or its close button) turns the editor off too.
    overlay:SetScript("OnHide", function()
        if on then
            Dev:Toggle(false)
        end
    end)
    overlay:SetScript("OnMouseWheel", function(_, delta)
        local step = IsShiftKeyDown() and 10 or 1
        if IsControlKeyDown() then
            edit(0, 0, 0, delta * step, 0)
        else
            edit(0, 0, delta * step, 0, 0)
        end
    end)
    -- Only the editing keys are kept. Every other key goes on to the game as usual.
    overlay:SetScript("OnKeyDown", function(self, key)
        local step = IsShiftKeyDown() and 10 or 1
        local used = true
        if key == "UP" then
            edit(0, step, 0, 0, 0)
        elseif key == "DOWN" then
            edit(0, -step, 0, 0, 0)
        elseif key == "LEFT" then
            edit(-step, 0, 0, 0, 0)
        elseif key == "RIGHT" then
            edit(step, 0, 0, 0, 0)
        elseif key == "=" or key == "+" or key == "NUMPADPLUS" then
            edit(0, 0, 0, 0, 1)
        elseif key == "-" or key == "NUMPADMINUS" then
            edit(0, 0, 0, 0, -1)
        else
            used = false
        end
        self:SetPropagateKeyboardInput(not used)
    end)

    -- The info box, to the right of the panel.
    info = CreateFrame("Frame", "CowfeeRaidToolsDevInfo", UIParent, "BackdropTemplate")
    info:SetFrameStrata("FULLSCREEN")
    info:SetSize(340, 220)
    info:SetPoint("TOPLEFT", UI.frame, "TOPRIGHT", 8, 0)
    info:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    info:SetBackdropColor(0.02, 0.06, 0.08, 0.92)
    info:SetBackdropBorderColor(0.2, 0.9, 1, 1)
    local title = info:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("|cff33e6ffDev layout editor|r")
    info.text = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info.text:SetPoint("TOPLEFT", 8, -30)
    info.text:SetWidth(324)
    info.text:SetJustifyH("LEFT")
    local help = info:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("BOTTOMLEFT", 8, 56)
    help:SetWidth(324)
    help:SetJustifyH("LEFT")
    help:SetText("Click to select, right-click to clear. Drag or arrows: move. Wheel: width. Ctrl + wheel: height. + and -: font size. Hold Shift for steps of 10.")

    local reset = makeButton(info, "Reset piece", 104)
    reset:SetPoint("BOTTOMLEFT", 8, 30)
    reset:SetScript("OnClick", function()
        if selected then
            db().overrides[selected.path] = nil
            CRT:Print("Reset " .. selected.path .. ". /reload to see the code's own layout.")
            refreshInfo()
        end
    end)
    local resetPage = makeButton(info, "Reset page", 104)
    resetPage:SetPoint("LEFT", reset, "RIGHT", 6, 0)
    resetPage:SetScript("OnClick", function()
        local key = shownPage()
        if key then
            for path in pairs(db().overrides) do
                if path:sub(1, #key + 1) == key .. "." then
                    db().overrides[path] = nil
                end
            end
            CRT:Print("Reset every change on " .. key .. ". /reload to see the code's own layout.")
            refreshInfo()
        end
    end)
    local export = makeButton(info, "Export", 104)
    export:SetPoint("LEFT", resetPage, "RIGHT", 6, 0)
    export:SetScript("OnClick", function()
        CRT.ConsumablesTools:ShowText("Dev layout changes (Ctrl+C to copy, paste to Claude)", exportText())
    end)
    -- Move pieces: off, the panel's buttons work as usual and nothing is picked or moved.
    info.move = CreateFrame("CheckButton", nil, info, "UICheckButtonTemplate")
    info.move:SetSize(22, 22)
    info.move:SetPoint("TOPRIGHT", -96, -4)
    local moveText = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moveText:SetPoint("LEFT", info.move, "RIGHT", 2, 0)
    moveText:SetText("Move pieces")
    info.move:SetScript("OnClick", function(self)
        Dev:SetMoving(self:GetChecked() and true or false)
    end)

    local done = makeButton(info, "Done", 104)
    done:SetPoint("BOTTOMLEFT", 8, 6)
    local diag = makeButton(info, "Debuff diags", 104)
    diag:SetPoint("LEFT", done, "RIGHT", 6, 0)
    diag:SetScript("OnClick", function()
        CRT.DebuffPanel:ShowInfo()
    end)
    local resetAll = makeButton(info, "Reset all pos.", 104)
    resetAll:SetPoint("LEFT", diag, "RIGHT", 6, 0)
    resetAll:SetScript("OnClick", function()
        Dev:ResetAllPositions()
    end)
    done:SetScript("OnClick", function()
        Dev:Toggle(false)
    end)
end

-- /crt dev reset: puts every movable window and the main panel back where they start.
function Dev:ResetAllPositions()
    CRT.ConsumablesDisplay:ResetPosition()
    CRT.DebuffPanel:ResetPosition()
    CRT.NoteAlert:ResetPosition()
    CRT.AlertBars:ResetPosition()
    CRT.AlertAreas:ResetAllPositions()
    CRT.AlertEditor:ResetPosition()
    for _, key in ipairs({ "window", "assignments", "personal" }) do
        CRT.NoteWindow:ResetPosition(key)
    end
    CRT.LowHealth:ResetPosition()
    CRT.ReadyCheckWindow:ResetPosition()
    CRT.MarkerDisplay:ResetPosition()
    CRT.Pace:ResetPosition()
    CRT.BreakTimer:ResetPosition()
    local pop = CRT.db.timeline.popout
    pop.point, pop.relativePoint, pop.x, pop.y = nil, nil, nil, nil
    local w = CRT.db.window
    w.point, w.relativePoint, w.x, w.y = "CENTER", "CENTER", 0, 0
    if UI.frame then
        UI.frame:ClearAllPoints()
        UI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    CRT:Print("Every window is back in its starting position.")
end

-- /crt dev clear: drops every saved change, for after they have been written into the code.
function Dev:ClearAll()
    local count = 0
    for _ in pairs(db().overrides) do
        count = count + 1
    end
    db().overrides = {}
    CRT:Print(format("Cleared %d dev layout change%s. /reload to see the code's own layout.", count, count == 1 and "" or "s"))
end

function Dev:Toggle(state)
    if state == nil then
        state = not on
    end
    if state and InCombatLockdown() then
        CRT:Print("The dev editor is off in combat.")
        return
    end
    if state then
        UI:Show()
        build()
        self:ApplyAll()
        on = true
        overlay:SetShown(moving)
        info.move:SetChecked(moving)
        info:Show()
        refreshInfo()
        CRT:Print("Dev layout editor on. Tick Move pieces to pick and move things; untick it to use the panel as usual. Done to stop.")
    else
        on = false
        dragging = false
        if overlay then
            overlay:Hide()
            info:Hide()
            hoverBox:Hide()
            selectBox:Hide()
        end
        CRT:Print("Dev layout editor off.")
    end
end

-- Move pieces on or off. Off, the overlay is hidden, so clicks reach the panel and nothing is picked.
function Dev:SetMoving(state)
    moving = state and true or false
    if not on or not overlay then
        return
    end
    dragging = false
    overlay:SetShown(moving)
    info.move:SetChecked(moving)
    if not moving then
        hoverBox:Hide()
    end
end

function Dev:IsOn()
    return on
end

function Dev:IsMoving()
    return moving
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    if on then
        Dev:Toggle(false)
    end
end)
