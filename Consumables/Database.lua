local ADDON, CRT = ...

-- The consumables the ready check row knows about. This list ships with the addon, so players
-- do not configure it. Update it each expansion or tier, then run `/crt consumables check`
-- in the game to confirm every ID is real.
--
-- Entry formats, one per consumable, listed most preferred first:
--   food, flask, rune:  { item = <item ID>, buff = <buff spell ID>, name = "optional label" }
--   potion, weapon:     { item = <item ID>, name = "optional label" }
--
-- item  The item ID you use, as in wowhead.com/item=<ID>.
-- buff  The spell ID of the buff it gives you. If left out, the item's use spell is tried, which
--       works for many flasks and runes but usually not for food.
-- name  Only a label for people reading this file. The game's own name is shown in the addon.
--
-- Players can reorder which item is used first and the order of the icons, but not edit this list.
-- To find IDs, buff up in the game and run `/crt consumables scan`, which prints your buffs and
-- the consumables in your bags as lines you can paste here.

CRT.ConsumablesDB = {
    expansion = "Midnight",
    updated = "2026-10-13",
    categories = {
        food = {},
        flask = {},
        potion = {},
        weapon = {},
        rune = {},
    },
}
