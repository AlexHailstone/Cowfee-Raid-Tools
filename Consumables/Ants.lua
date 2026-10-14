local ADDON, CRT = ...

-- "Marching ants": small dashes that crawl around the edge of a frame, used on the ready check
-- row to flag a missing or expiring consumable. Written from scratch with plain textures.

local Ants = {}
CRT.Ants = Ants

local COUNT = 14 -- dashes around the edge
local SPEED = 38 -- pixels per second, clockwise
local LONG, SHORT = 7, 2 -- dash length and thickness

function Ants:Attach(frame)
    if frame.ants then
        return
    end
    local ants = { dashes = {}, offset = 0, active = false }
    for i = 1, COUNT do
        local dash = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        dash:SetColorTexture(1, 1, 1, 1)
        dash:Hide()
        ants.dashes[i] = dash
    end
    frame.ants = ants
end

function Ants:Start(frame, r, g, b)
    local ants = frame.ants
    if not ants then
        return
    end
    for _, dash in ipairs(ants.dashes) do
        dash:SetColorTexture(r, g, b, 1)
        dash:Show()
    end
    ants.active = true
end

function Ants:Stop(frame)
    local ants = frame.ants
    if not ants or not ants.active then
        return
    end
    for _, dash in ipairs(ants.dashes) do
        dash:Hide()
    end
    ants.active = false
end

-- Moves every dash along the edge. Call each frame while active.
function Ants:Update(frame, dt)
    local ants = frame.ants
    if not ants or not ants.active then
        return
    end
    local w, h = frame:GetWidth(), frame:GetHeight()
    local perimeter = 2 * (w + h)
    ants.offset = (ants.offset + SPEED * dt) % perimeter
    local spacing = perimeter / COUNT

    for i, dash in ipairs(ants.dashes) do
        local s = (ants.offset + (i - 1) * spacing) % perimeter
        local x, y, horizontal
        if s < w then
            x, y, horizontal = s, 0, true -- top edge, left to right
        elseif s < w + h then
            x, y, horizontal = w, s - w, false -- right edge, downward
        elseif s < 2 * w + h then
            x, y, horizontal = w - (s - w - h), h, true -- bottom edge, right to left
        else
            x, y, horizontal = 0, h - (s - 2 * w - h), false -- left edge, upward
        end
        dash:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
        if dash.horizontal ~= horizontal then
            dash.horizontal = horizontal
            if horizontal then
                dash:SetSize(LONG, SHORT)
            else
                dash:SetSize(SHORT, LONG)
            end
        end
    end
end
