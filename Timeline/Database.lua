local ADDON, CRT = ...

-- The reference timelines that ship with the addon. Each one is a boss's planned cast schedule,
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
-- To add another boss, transcribe its planner screenshot into another [[ ... ]] block in the list,
-- ask Alex each ability's type (never guess it), and run the reference harness in lint to check
-- that it reads. The timeline-reference skill in the vault walks through it.
--
-- Times that cannot be read from a screenshot, such as a cast cut off at its edge, are left out
-- and named in a # line, rather than guessed.

CRT.TimelineDB = {
    references = {
        [[
Boss: Nek'zali the Soulcoiler
Difficulty: Mythic
Length: 9:48
Phase: P1.5 3:17
Phase: 5:53
Phase: P2 7:20
Soulcoil Rite (type raid): 0:02+45, 1:17+45, 2:28+45, 7:38, 8:26, 8:58
Essence Rend (type dispel): 0:20, 1:00, 1:31, 2:11, 2:42, 8:20
Possession Barrage (type falloff, lead 7): 0:36, 1:12, 1:47, 2:23, 2:58, 8:13, 8:41, 9:33
Grasping Depths (type mythic): 0:42, 1:53, 3:04, 4:02, 4:37, 6:28, 7:03, 7:47, 8:27, 9:07
Restless Amani (type generic): 0:52, 2:01, 3:12, 4:10, 5:57, 6:36, 7:11, 7:55, 8:35, 9:15
Corpse Blight (type heroic raid): 1:08+25, 2:14+25, 3:23+25, 4:25+25, 6:25, 7:00, 7:20, 8:11, 8:55, 9:34
Ritual of Awakening (type generic): 3:17+100, 5:53+87
Soul Transfer (type generic, lead 26): 3:43, 6:08
Hungering Pyre (type soak, lead 6): 3:53, 4:28, 6:19, 6:54
Uncoiling (type generic): 7:20+148
Invoke (type mythic, lead 6): 7:38, 8:26, 8:58
# Left out, cut off at the end of the screenshot: the last Essence Rend (9:5x),
# the last Grasping Depths (about 9:47), and the last Invoke (9:5x).
]],
    },
}
