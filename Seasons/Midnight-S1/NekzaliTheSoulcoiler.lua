local ADDON, CRT = ...

-- Nek'zali the Soulcoiler. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3470 comes from an example raid note and isn't confirmed in a pull yet. The reference
--             has no Encounter: line, so the Timeline matches it by the boss's name either way.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot with each ability's type from
--             Alex. Moved here from Timeline/Database.lua in the boss library change.

CRT.Bosses:Register({
    encounterID = 3470,
    name = "Nek'zali the Soulcoiler",
    season = "midnight-s1",
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
})
