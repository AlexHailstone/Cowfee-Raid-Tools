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
-- Food needs no buff: every food gives the same kind of buff, so food is checked against foodBuffs
-- below. The food list only says which food a click on your bar eats, first one in your bags first.
-- low   Optional, flask only: true for a lower quality flask, which the raid report can flag.
--
-- Players can reorder which item is used first and the order of the icons, but not edit this list.
-- To find IDs, buff up in the game and run `/crt consumables scan`, which prints your buffs and
-- the consumables in your bags as lines you can paste here.
--
-- Midnight item IDs below were taken on 2026-10-14 from the item links on Method's "List of all
-- Midnight consumables, enchants and gems" guide
-- (https://www.method.gg/guides/list-of-all-midnight-consumables-enchants-and-gems), written
-- 2026-09-06 for patch 12.1. It listed no buff IDs, and the augment rune had no link, so the rune's
-- IDs came from the game instead. Confirm with `/crt consumables check`.

CRT.ConsumablesDB = {
    expansion = "Midnight",
    updated = "2026-10-14",
    -- The food buffs the ready check and your bar look for, whatever was eaten. Buffs with "Well Fed"
    -- anywhere in their name count too, on an English client.
    foodBuffs = {
        -- Both from Alex on 2026-10-14: Hearty Well Fed from the game tooltip, and Well Fed, which may be
        -- the shared buff behind every Well Fed food, from a screenshot of its spell page.
        { buff = 456410, name = "Well Fed" },
        { buff = 1233724, name = "Hearty Well Fed" },
    },
    categories = {
        food = {
            -- Feasts
            { item = 255845, name = "Silvermoon Parade" }, -- main stat
            { item = 255846, name = "Harandar Celebration" }, -- main stat
            { item = 275264, name = "Amani Cornucopia" },
            { item = 275265, name = "Loa's Gathering" },
            { item = 275266, name = "Feast of Knowledge" },
            { item = 242272, name = "Quel'dorei Medley" },
            { item = 242273, name = "Blooming Feast" },
            -- Primary stat
            { item = 255847, name = "Impossibly Royal Roast" },
            { item = 242275, name = "Royal Roast" },
            { item = 242288, name = "Twilight Angler's Medley" },
            { item = 242289, name = "Spellfire Filet" },
            { item = 242303, name = "Mana-Infused Stew" },
            { item = 242302, name = "Bloom Skewers" },
            -- Highest secondary stat
            { item = 255848, name = "Flora Frenzy" },
            { item = 242274, name = "Champion's Bento" },
            { item = 275260, name = "Puffer Plate" },
            { item = 275261, name = "Sweet-And-Sour Skewers" },
            { item = 275258, name = "Venom-Spiced Cutlets" },
            -- One secondary stat
            { item = 242285, name = "Warped Wise Wings" }, -- mastery
            { item = 242281, name = "Glitter Skewers" }, -- mastery
            { item = 242284, name = "Void-Kissed Fish Rolls" }, -- versatility
            { item = 242280, name = "Buttered Root Crab" }, -- versatility
            { item = 242276, name = "Braised Blood Hunter" }, -- versatility
            { item = 242294, name = "Felberry Figs" }, -- versatility
            { item = 242283, name = "Sun-Seared Lumifin" }, -- critical strike
            { item = 242287, name = "Arcano Cutlets" }, -- critical strike
            { item = 242278, name = "Tasty Smoked Tetra" }, -- critical strike
            { item = 242282, name = "Null and Void Plate" }, -- haste
            { item = 242286, name = "Fel-Kissed Filet" }, -- haste
            { item = 242277, name = "Crimson Calamari" }, -- haste
            -- Two secondary stats
            { item = 242293, name = "Sunwell Delight" }, -- versatility, haste
            { item = 242295, name = "Hearthflame Supper" }, -- critical strike, haste
            { item = 242291, name = "Fried Bloomtail" }, -- mastery, versatility
            { item = 242292, name = "Eversong Pudding" }, -- mastery, critical strike
            { item = 242296, name = "Bloodthistle-Wrapped Cutlets" }, -- mastery, haste
            { item = 242290, name = "Wise Tails" }, -- critical strike, versatility
            { item = 242304, name = "Spiced Biscuits" }, -- critical strike, versatility
            { item = 242305, name = "Silvermoon Standard" }, -- mastery, versatility
            { item = 242307, name = "Quick Sandwich" }, -- versatility, haste
            { item = 242308, name = "Portable Snack" }, -- critical strike, haste
            { item = 242306, name = "Forager's Medley" }, -- mastery, critical strike
            { item = 242309, name = "Farstrider Rations" }, -- mastery, haste
        },
        flask = {
            { item = 241324, name = "Flask of the Blood Knights" }, -- haste
            { item = 241326, name = "Flask of the Shattered Sun" }, -- critical strike
            { item = 241322, name = "Flask of the Magisters" }, -- mastery
            { item = 241321, name = "Flask of Thalassian Resistance" }, -- versatility
        },
        potion = {
            { item = 241308, name = "Light's Potential" }, -- primary stat, 30 seconds
            { item = 241292, name = "Draught of Rampant Abandon" }, -- primary stat, 30 seconds
            { item = 241288, name = "Potion of Recklessness" }, -- highest secondary stat
            { item = 241296, name = "Potion of Zealotry" }, -- holy damage
            { item = 271887, name = "Liquid Luster" }, -- stacking versatility
            { item = 271890, name = "Alluring Nostrum" }, -- shadow damage
        },
        weapon = {
            { item = 243734, name = "Thalassian Phoenix Oil" }, -- critical strike, haste
            { item = 243738, name = "Smuggler's Enchanted Edge" }, -- arcane damage
            { item = 243736, name = "Oil of Dawn" }, -- absorb shield
            { item = 237371, name = "Refulgent Whetstone" }, -- bladed weapons
            { item = 237369, name = "Refulgent Weightstone" }, -- blunt weapons
            { item = 257750, name = "Laced Zoomshots" }, -- hunter ammo
            { item = 257752, name = "Weighted Boomshots" }, -- hunter ammo
        },
        rune = {
            -- Item ID and buff ID from Alex in the game on 2026-10-14. The buff is named "Void-Touched",
            -- without "Augment", so it is matched by its ID, not by the English name fallback.
            { item = 259085, buff = 1264426, name = "Void-Touched Augment Rune" },
        },
    },
}
