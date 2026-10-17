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

function Log:Toggle()
    local f = UI:Create()
    hook(f)
    on = not on
    CRT:Print("Window log " .. (on and "on: every move of the main window prints here. /crt dev winlog turns it off." or "off."))
    if on then
        say("now", f)
    end
end
