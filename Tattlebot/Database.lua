local ADDON, CRT = ...

-- The boss mechanics Tattlebot reports on. This list ships with the addon. After each boss pull,
-- Tattlebot reads the game's damage meter (Damage Taken) and keeps only the damage each player took
-- from the spells listed here. Players can add their own spell IDs on the Mechanics tab as well.
--
-- Bosses are listed in raid order, each with its mechanics:
--   { boss = "Boss name", mechanics = {
--       { name = "Mechanic name", spells = { <spell ID>, <spell ID> } },
--   } },
--
-- boss      The name shown in the boss dropdown on the Mechanics tab. Write it as the game names
--           the encounter, so the History filter can count the pulls on that boss.
-- encounterID  Optional, after boss: the encounter's ID. When given, pulls are matched by it
--           instead of by name, which also works in other game languages.
-- name      The mechanic's name in every report. All its spell IDs are added together under it,
--           so a mechanic with a different ID per difficulty or per hit is still one line.
-- spells    The IDs of the spells that do its damage, as the damage meter shows them. To find
--           them, do a pull, leave combat and type `/crt tattle scan`: it lists every spell that
--           damaged the group in the last fight, with its ID.
--
-- The meter gives damage, not hits, so Tattlebot reports damage taken per mechanic and how many
-- pulls each player was hit in.

-- The mechanics ship in each boss's file in the season packs (field mechanics), and
-- Bosses/Registry.lua adds the loaded seasons' bosses to this list. Pulls are still saved in
-- Tattlebot's own history with the mechanic and boss name, so reports across seasons keep working.

CRT.TattleDB = {
    bosses = {
        -- { boss = "Example Boss", encounterID = 3001, mechanics = {
        --     { name = "Falling Debris", spells = { 123456, 123457 } },
        --     { name = "Void Pool", spells = { 234567 } },
        -- } },
    },
}
