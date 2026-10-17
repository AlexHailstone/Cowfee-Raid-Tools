local ADDON, CRT = ...

-- DEVELOPER ONLY. The window log (/crt dev winlog): prints to chat every time something moves, sizes
-- or rescales the main window, with its anchor and screen place and the line of code that did it, to
-- find what makes it jump. A drag also prints the place one frame after it starts and after it ends.
-- /crt dev winlog again turns it off. This file never ships: its .toc line is inside the
-- do-not-package block.

local Log = {}
CRT.WindowLog = Log

local UI = CRT.UI

local on, hooked = false, false

local function where(f)
    local point, rel, relPoint, x, y = f:GetPoint()
    local relName = rel == nil and "screen" or (rel == UIParent and "UIParent") or (rel.GetName and rel:GetName()) or "a frame"
    return string.format("%s of %s %s %+.0f %+.0f | left %.0f top %.0f | scale %.2f h %.0f", tostring(point), relName, tostring(relPoint), x or 0, y or 0, f:GetLeft() or -1, f:GetTop() or -1, f:GetScale(), f:GetHeight() or 0)
end

-- The file and line that called the hooked method, without the folder path.
local function caller()
    local stack = debugstack(3, 3, 0) or ""
    local out = {}
    for file, line in stack:gmatch("([%w_%-]+%.lua)\"?%]?:(%d+)") do
        out[#out + 1] = file .. ":" .. line
    end
    return #out > 0 and table.concat(out, " < ") or "?"
end

local function say(what, f, from)
    if on then
        print("|cffc8a050winlog|r " .. what .. ": " .. where(f) .. (from and (" |cff888888from " .. from .. "|r") or ""))
    end
end

local function hook(f)
    if hooked then
        return
    end
    hooked = true
    for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetHeight", "SetSize", "SetScale", "StartMoving", "StopMovingOrSizing" }) do
        hooksecurefunc(f, method, function(self)
            say(method, self, caller())
            if method == "StartMoving" and on then
                C_Timer.After(0, function()
                    say("one frame into the drag", self)
                end)
            elseif method == "StopMovingOrSizing" and on then
                C_Timer.After(0, function()
                    say("one frame after the drag", self)
                end)
            end
        end)
    end
end

-- Every frame while the log is on: a jump (the window's corner moving more than JUMP pixels in one
-- frame) prints where it was and where it went, the cursor and the anchor; a press of the left button
-- over the window prints where it starts. The drag handler keeps the game's own StartMoving, so the
-- method hook above never sees a drag start.
local JUMP = 40
local watcher = CreateFrame("Frame")
local wasDown

local function cursor(f)
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    return string.format("cursor %.0f,%.0f", x / s, y / s)
end

-- The shown frames inside the window that reach past its edges, the farthest first (up to 4), to test
-- whether something docked back into it (the Timeline's pop-out) makes the screen clamp push it.
local function outside(f)
    local fl, fr, ft, fb = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    local found = {}
    local function walk(frame, depth)
        if depth > 12 then
            return
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsShown() then
                local l, r, t, b = child:GetLeft(), child:GetRight(), child:GetTop(), child:GetBottom()
                if l and r and t and b then
                    local over = math.max(fl - l, r - fr, t - ft, fb - b)
                    if over > 2 then
                        found[#found + 1] = { over = over, text = string.format("%s %s past by %.0f (l %.0f r %.0f t %.0f b %.0f)", child:GetObjectType(), child:GetName() or (child.GetDebugName and child:GetDebugName()) or "?", over, l, r, t, b) }
                    end
                end
                walk(child, depth + 1)
            end
        end
    end
    walk(f, 1)
    table.sort(found, function(a, b)
        return a.over > b.over
    end)
    for i = 1, math.min(4, #found) do
        print("|cffc8a050winlog|r   outside: " .. found[i].text)
    end
    if #found == 0 then
        print("|cffc8a050winlog|r   nothing inside reaches past the window's edges")
    end
end

-- The windows watched: the main one and the Timeline's pop-out, each with its last place.
local WATCHED = {
    { name = "main", get = function() return UI.frame end },
    { name = "pop-out", get = function() return _G.CowfeeRaidToolsTimelineWindow end },
}

watcher:SetScript("OnUpdate", function()
    local down = IsMouseButtonDown("LeftButton")
    for _, w in ipairs(WATCHED) do
        local f = w.get()
        if not on or not f or not f:IsShown() then
            w.left, w.top = nil, nil
        else
            if down and not wasDown and f:IsMouseOver() then
                say(w.name .. ", left button down, " .. cursor(f), f)
                if w.name == "main" then
                    outside(f)
                end
            end
            local left, top = f:GetLeft(), f:GetTop()
            if left and top and w.left and (math.abs(left - w.left) > JUMP or math.abs(top - w.top) > JUMP) then
                say(string.format("|cffff4040JUMP|r %s from left %.0f top %.0f, %s", w.name, w.left, w.top, cursor(f)), f)
            end
            w.left, w.top = left, top
        end
    end
    wasDown = down
end)

-- /crt dev stamp: plays the note windows' "note updated" stamp now, without a share, and prints for each
-- window whether it is shown and whether the stamp is playing a moment later.
function Log:Stamp()
    local NW = CRT.NoteWindow
    if not (NW and NW.Flash) then
        CRT:Print("Note stamp: the note windows aren't loaded.")
        return
    end
    NW:Flash()
    C_Timer.After(0.3, function()
        for _, key in ipairs({ "window", "assignments", "personal" }) do
            local w = NW:Get(key)
            if not w then
                print("|cffc8a050stamp|r " .. key .. ": no window")
            else
                local t, f = w.stampTexture, w.frame
                print(string.format("|cffc8a050stamp|r %s: shown %s, stamp playing %s, pending %s | layer %s, alpha %.2f, shown %s, size %.0fx%.0f | window alpha %.2f, strata %s, level %d, size %.0fx%.0f", key, tostring(f:IsShown()), tostring(w.stamp and w.stamp:IsPlaying()), tostring(w.flashPending),
                    t and tostring(t:GetDrawLayer()) or "?", t and t:GetAlpha() or -1, t and tostring(t:IsShown()) or "?", t and t:GetWidth() or 0, t and t:GetHeight() or 0,
                    f:GetEffectiveAlpha(), f:GetFrameStrata(), f:GetFrameLevel(), f:GetWidth(), f:GetHeight()))
            end
        end
    end)
end

function Log:Toggle()
    local f = UI:Create()
    hook(f)
    on = not on
    CRT:Print("Window log " .. (on and "on: every move of the main window prints here. /crt dev winlog turns it off." or "off."))
    if on then
        say("now", f)
    end
end
