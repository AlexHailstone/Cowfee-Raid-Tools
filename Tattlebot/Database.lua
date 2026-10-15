local ADDON, CRT = ...

-- The boss mechanics Tattlebot reports on. This list ships with the addon, so players do not
-- configure it. After each boss pull, Tattlebot reads the game's damage meter (Damage Taken) and
-- keeps only the damage each player took from the spells listed here.
--
-- One line per spell:
--   [<spell ID>] = "label",
--
-- spell ID  The ID of the spell that does the damage, as the damage meter shows it. To find them,
--           do a pull, leave combat and type `/crt tattle scan`: it lists every spell that damaged
--           the group in the last fight as lines you can paste here.
-- label     Only for people reading this file, such as the boss and the mechanic. The game's own
--           spell name is shown in the addon.
--
-- The meter gives damage, not hits, so Tattlebot reports damage taken and how many pulls each
-- player was hit in. The Settings tab can also count every spell the game itself marks avoidable.

CRT.TattleDB = {
    spells = {
        -- [123456] = "Example boss: Falling Debris",
    },
}
