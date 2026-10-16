local ADDON, CRT = ...

-- The reference timelines that ship with the addon. They live in each boss's file in the season packs
-- (Seasons/<season>/<Boss>.lua, field references), and Bosses/Registry.lua puts the loaded seasons'
-- references in this list once every file has loaded. Each one is a boss's planned cast schedule,
-- transcribed by hand from a planner screenshot, and the Timeline page reads it as plain text
-- (Timeline/Reference.lua). The Timeline page shows it before any pull, with phase lines, duration
-- bars, colored rows and cast lead lines.
--
-- Each reference is one [[ ... ]] block in the list, one line per thing:
--   Boss: Name                  the boss, as the game names it (required)
--   Difficulty: Mythic          shown in the reference's name
--   Length: 9:48                the fight's length; without it, the last cast plus its bar
--   Phase: P2 7:20              a phase line at that time; the time is the last word
--   Name (options): times       an ability row, with its casts in order
--
-- A time is m:ss or plain seconds. "0:02+45" is a cast at 0:02 with a 45-second bar. The options
-- in round brackets are "type" (what the ability is: dispel, raid, falloff, mythic, heroic,
-- generic, soak or spread; the first colors the row, each other one adds a dot), "lead N" (a cast
-- line N seconds before each icon) and "color rrggbb" (a color instead of the type's). "[spell N]"
-- after a name gives the spell ID for the icon and tooltip. Blank lines
-- and lines starting with # are skipped, so a # line can say what was left out.
--
-- To add another boss, transcribe its planner screenshot into a [[ ... ]] block in that boss's file,
-- ask Alex each ability's type (never guess it), and run the reference harness in lint to check
-- that it reads. The timeline-reference skill in the vault walks through it.
--
-- Times that cannot be read from a screenshot, such as a cast cut off at its edge, are left out
-- and named in a # line, rather than guessed.

CRT.TimelineDB = {
    references = {}, -- filled by Bosses/Registry.lua from the loaded seasons
}
