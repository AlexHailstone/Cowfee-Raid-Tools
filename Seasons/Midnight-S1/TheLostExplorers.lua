local ADDON, CRT = ...

-- The Lost Explorers. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3497 comes from the boss's Warcraft Logs rankings link (boss=3497), not from a pull
--             yet.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot on 2026-10-17 (the vault note
--             "Cowfee Raid Tools - Boss Reference Transcriptions"). The rows have no types yet: Alex
--             sets them in game with the Reference types tool on the Development page, and its export
--             replaces this block.

CRT.Bosses:Register({
    encounterID = 3497,
    name = "The Lost Explorers",
    season = "midnight-s1",
    references = {
        [[
Boss: The Lost Explorers
Difficulty: Mythic
Length: 7:31
Encounter: 3497
Phase: Empowered 1 1:04
Phase: Empowered 2 3:03
Phase: Empowered 3 5:06
Phase: 7:08
Malevolent Presence: 0:02+62, 1:04+119, 3:03+123, 5:06+145
Empower: 0:00, 2:02, 4:01, 6:04
Blink Nova (lead 8): 0:17, 0:48, 2:20, 2:51, 4:19, 4:50, 5:33, 6:22, 6:53
Shell Spin (lead 6): 0:22, 0:38, 0:53, 1:14, 1:46, 2:25, 2:41, 2:56, 4:24, 4:40, 4:55, 5:25, 5:52, 6:27, 6:43, 6:58
Shredding Shards: 0:30, 1:33, 2:33, 3:32, 4:32, 5:35, 6:35
Disgusting Fish: 0:37, 1:04, 2:40, 3:03, 4:39, 5:06, 6:42
Empowered Ascension (lead 6): 5:05, 7:08
Throw Junk: 0:27, 0:58, 1:37, 2:30, 3:01, 3:29, 4:00, 4:29, 5:00, 5:19, 5:46, 6:32, 7:03
Evil Eyes: 1:04, 3:03, 5:06
Binding Anguish: 1:04, 3:03, 5:06
Mushroom Toss (lead 8): 1:13, 1:45
Explosive Surprise (lead 12): 1:26, 1:58
Dark Whispers: 2:01, 4:00, 6:03
Mighty Thud (lead 10): 3:15, 3:47
Frostfire Volley (lead 8): 5:20, 5:47
]],
    },
})
