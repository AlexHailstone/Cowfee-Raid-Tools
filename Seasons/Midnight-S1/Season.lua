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
})
