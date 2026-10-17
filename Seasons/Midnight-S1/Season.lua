local ADDON, CRT = ...

-- Midnight Season 1: one file per boss in this folder, each a CRT.Bosses:Register call (see
-- Bosses/Registry.lua for the fields). A new season gets a folder of its own, its own Season.lua with
-- current = true, and this one's current set to false.

CRT.Bosses:Season({
    key = "midnight-s1",
    name = "Midnight Season 1",
    expansion = "Midnight",
    order = 1,
    current = true,
    -- The raid progression route: the raids in order, each with its bosses in order. Every boss list
    -- in the addon follows it (CRT.Bosses:Route). Set it with Boss order on the Development page, then
    -- paste its Export here. Until the raids are split out, every boss is in one group, in the order
    -- the boss files load.
    raids = {
        {
            key = "midnight-s1",
            name = "Midnight Season 1",
            bosses = {
                3470, -- Nek'zali the Soulcoiler
                3420, -- Sszorak
                3445, -- Entombed Sentinels
                3421, -- The Twin Fangs
                3497, -- The Lost Explorers
                3455, -- Vashnik the Malignant
                3429, -- The Coiled Altar
                3492, -- Ula'tek
            },
        },
    },
})
