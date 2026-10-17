local ADDON, CRT = ...

-- DEVELOPER ONLY. /crt dev late: shows a sample raid night on the Late Tracker's Tonight tab, to see
-- the grid without a real raid. It is display only (CRT.LatePage.Preview): nothing is saved, the real
-- night and the history are untouched, and the page's buttons still act on the real night. The same
-- command again goes back to the real night. This file never ships: its .toc line is inside the
-- do-not-package block.
--
-- The sample uses the active Raid Groups layout, or sample names when there is none. It
-- started 25 minutes ago with the picked grace minutes; in a repeating pattern, players are here on
-- time, joined late (3 to 12 minutes), or not here yet.

local Test = {}
CRT.LateTest = Test

local SAMPLE = {
    "Whitecrows", "Mesmertism", "Abu", "Granddh", "Skarghan", "Teronhorefnd", "Djaztech", "Rixxy",
    "Lichkingstoy", "Thisisfartaa", "Gadios", "Balevolence", "Xuelan", "Sixz", "Dotsanhots", "Durayn",
    "Sarrantha", "Notkvr", "Cheoeqar", "Teronhorefnd-Tichondrius",
}
local STARTED_AGO = 25 * 60

local showing = false

local function sampleNight()
    local s = CRT.Late:Settings()
    local now = time()
    local night = { startedAt = now - STARTED_AGO, how = "button", grace = s.grace or 0, players = {} }
    local preset = CRT.Groups:Find(CRT.Groups:Active())
    local keys = {}
    if preset then
        night.layout = preset.name
        for i = 1, CRT.Groups.NUM_SLOTS do
            local key = preset.slots[i]
            if key and key ~= "" then
                keys[#keys + 1] = key
            end
        end
    end
    if #keys == 0 then
        night.layout = "sample names"
        keys = SAMPLE
    end
    for i, key in ipairs(keys) do
        local p = { key = key }
        local kind = i % 5
        if kind == 1 or kind == 2 then
            p.joinedAt = night.startedAt -- on time
        elseif kind == 3 then
            p.joinedAt = night.startedAt + (3 + (i % 10)) * 60 -- late
        end -- kinds 4 and 0: not here yet
        night.players[#night.players + 1] = p
    end
    return night
end

function Test:Toggle()
    showing = not showing
    CRT.LatePage.Preview(showing and sampleNight() or nil)
    CRT:Print(showing and "Late Tracker: showing a sample night (nothing is saved). /crt dev late again goes back." or "Late Tracker: back to the real night.")
end
