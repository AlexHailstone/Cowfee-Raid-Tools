local ADDON, CRT = ...

-- Midnight Season 2: one file per boss in this folder, each a CRT.Bosses:Register call (see
-- Bosses/Registry.lua for the fields). A new season gets a folder of its own, its own Season.lua with
-- current = true, and this one's current set to false.

CRT.Bosses:Season({
    key = "midnight-s1",
    name = "Midnight Season 2",
    expansion = "Midnight",
    order = 1,
    current = true,
    -- The raid progression route: the raids in order, each with its bosses in order. Every boss list
    -- in the addon follows it (CRT.Bosses:Route). Set it with Boss order on the Development page, then
    -- paste its Export here. The progression order is Alex's, from 2026-10-17; every boss is in one
    -- raid group until the raids are split out.
    raids = {
        {
            key = "midnight-s1",
            name = "Midnight Season 2",
            bosses = {
                3470, -- Nek'zali the Soulcoiler
                3497, -- The Lost Explorers
                3445, -- Entombed Sentinels
                3455, -- Vashnik the Malignant
                3420, -- Sszorak
                3421, -- The Twin Fangs
                3429, -- The Coiled Altar
                3492, -- Ula'tek
            },
        },
    },
})
