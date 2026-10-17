local ADDON, CRT = ...

-- DEVELOPER ONLY. The layout check (/crt dev layout): opens every page of the main window and clicks
-- through its tabs, then prints every shown frame and text that reaches outside the page area
-- (UI.PAGE_W x UI.PAGE_H), and by how much. Content inside a scroll frame is skipped, since a scroll
-- child is meant to be larger than its frame. The page you were on is selected again at the end; each
-- page remembers the last tab clicked, so pages with tabs end on their last tab. This file never ships:
-- its .toc line is inside the do-not-package block.

local Check = {}
CRT.LayoutCheck = Check

local UI = CRT.UI

local SLACK = 1 -- pixels of rounding allowed
local MAX_LINES = 40

local function isUnder(frame, root)
    while frame do
        if frame == root then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end

local function label(obj)
    local name = obj.GetName and obj:GetName()
    if not name and obj.GetDebugName then
        name = obj:GetDebugName()
    end
    local text = obj.GetText and obj:GetText()
    if type(text) == "string" and text ~= "" then
        return string.format("%s \"%s\"", obj:GetObjectType(), (text:gsub("\n.*", ""):sub(1, 30)))
    end
    return obj:GetObjectType() .. " " .. tostring(name or "?"):gsub("^.*%.", "")
end

-- How far obj reaches past the page frame's edges, as "right 24, bottom 10", or nil when inside.
local function overflow(obj, pl, pr, pt, pb)
    local l, r, t, b = obj:GetLeft(), obj:GetRight(), obj:GetTop(), obj:GetBottom()
    if not (l and r and t and b) or r - l < 1 or t - b < 1 then
        return nil
    end
    local parts = {}
    if l < pl - SLACK then parts[#parts + 1] = string.format("left %.0f", pl - l) end
    if r > pr + SLACK then parts[#parts + 1] = string.format("right %.0f", r - pr) end
    if t > pt + SLACK then parts[#parts + 1] = string.format("top %.0f", t - pt) end
    if b < pb - SLACK then parts[#parts + 1] = string.format("bottom %.0f", pb - b) end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- Every shown frame and non-empty text under the page that reaches outside it.
local function scan(pf, where, out)
    local pl, pr, pt, pb = pf:GetLeft(), pf:GetRight(), pf:GetTop(), pf:GetBottom()
    if not (pl and pr and pt and pb) then
        return
    end
    local function walk(frame, depth)
        if depth > 15 then
            return
        end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "FontString" and region:IsVisible() and (region:GetText() or "") ~= "" then
                local over = overflow(region, pl, pr, pt, pb)
                if over then
                    out[#out + 1] = string.format("%s: %s past by %s", where, label(region), over)
                end
            end
        end
        local scrollChild = frame.GetScrollChild and frame:GetScrollChild()
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsVisible() and child ~= scrollChild then
                local over = overflow(child, pl, pr, pt, pb)
                if over then
                    out[#out + 1] = string.format("%s: %s past by %s", where, label(child), over)
                end
                walk(child, depth + 1)
            end
        end
    end
    walk(pf, 1)
end

function Check:Run()
    UI:Show()
    local before = CRT.db.lastPage
    local out, checked = {}, 0
    for _, key in ipairs(UI.order) do
        local page = UI.pages[key]
        if page and not page.hidden then
            UI:SelectPage(key)
            local pf = page.frame
            local tabs = {}
            for _, b in ipairs(UI.tabs or {}) do
                if isUnder(b, pf) and b:IsVisible() then
                    tabs[#tabs + 1] = b
                end
            end
            if #tabs == 0 then
                scan(pf, page.title, out)
                checked = checked + 1
            else
                for _, b in ipairs(tabs) do
                    local click = b:GetScript("OnClick")
                    if click then
                        click(b, "LeftButton")
                    end
                    local text = b.text and b.text:GetText() or "tab"
                    scan(pf, page.title .. " > " .. text, out)
                    checked = checked + 1
                end
            end
        end
    end
    UI:SelectPage(before)
    CRT:Print(string.format("Layout check: %d page views against %d x %d. %s", checked, UI.PAGE_W, UI.PAGE_H, #out == 0 and "Everything fits." or (#out .. " things reach outside:")))
    for i = 1, math.min(#out, MAX_LINES) do
        print("|cffc8a050layout|r " .. out[i])
    end
    if #out > MAX_LINES then
        print(string.format("|cffc8a050layout|r ...and %d more.", #out - MAX_LINES))
    end
end
