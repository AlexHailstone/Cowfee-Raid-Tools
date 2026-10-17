local ADDON, CRT = ...

-- Vashnik the Malignant. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3455 comes from the boss's Warcraft Logs rankings link (boss=3455), not from a pull
--             yet.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot on 2026-10-17 (the vault note
--             "Cowfee Raid Tools - Boss Reference Transcriptions"). The rows have no types yet: Alex
--             sets them in game with the Reference types tool on the Development page, and its export
--             replaces this block.

CRT.Bosses:Register({
    encounterID = 3455,
    name = "Vashnik the Malignant",
    season = "midnight-s1",
    references = {
        [[
Boss: Vashnik the Malignant
Difficulty: Mythic
Length: 8:20
Encounter: 3455
Toxic Vapor: 0:02+498
Dripping Fangs: 0:10, 0:39, 1:06, 1:34, 2:03, 2:30, 2:58, 3:27, 3:54, 4:22, 4:51, 5:18, 5:46, 6:15, 6:42, 7:10, 7:39, 8:06
Imbibe (lead 6): 0:24, 1:48, 3:12, 4:36, 6:00, 7:24, 8:03
Conflagrating Expulsion: 0:24, 1:48, 3:12, 4:36, 6:00, 7:24, 8:03
Gloom Expulsion: 0:24, 1:48, 3:12, 4:36, 6:00, 7:24, 8:03
Burning Presence: 0:27+20, 1:51+20, 3:15+20, 4:39+20, 6:03+20, 7:27+20, 8:06
Caustic Surge: 0:53, 2:17, 3:41, 5:05, 6:29, 7:53
Malignant Catalyst (lead 8): 0:35, 1:14, 1:59, 2:38, 3:23, 4:02, 4:47, 5:26, 6:11, 6:50, 7:35
Exploding Infection: 0:42, 1:41, 2:06, 3:05, 3:30, 4:29, 4:54, 5:53, 6:18, 7:17, 7:42
Caustic Explosion: 0:42, 1:41, 2:06, 3:05, 3:30, 4:29, 4:54, 5:53, 6:18, 7:17, 7:42
Stygian Infection: 0:42, 1:41, 2:06, 3:05, 3:30, 4:29, 4:54, 5:53, 6:18, 7:17, 7:42
Plague Froth: 0:13, 0:54, 1:30, 2:18, 2:54, 3:42, 4:18, 5:06, 5:42, 6:30, 7:06, 7:54
# Left out, labels overlapped: Imbibe, both Expulsions and Burning Presence each have two more casts between 7:24 and 8:03 (read as 7:4x and 7:5x).
# Left out: Caustic Surge's first two casts in each group of three (about 10 seconds apart, before 0:53, 2:17, 3:41, 5:05, 6:29 and 7:53).
# Left out: the last Malignant Catalyst, at 8:1x, cut off at the edge.
]],
    },
})
