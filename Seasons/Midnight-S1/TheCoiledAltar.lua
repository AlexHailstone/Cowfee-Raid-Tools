local ADDON, CRT = ...

-- The Coiled Altar. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3429 comes from the boss's Warcraft Logs rankings link (boss=3429), not from a pull
--             yet.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot on 2026-10-17 (the vault note
--             "Cowfee Raid Tools - Boss Reference Transcriptions"). The rows have no types yet: Alex
--             sets them in game with the Reference types tool on the Development page, and its export
--             replaces this block.

CRT.Bosses:Register({
    encounterID = 3429,
    name = "The Coiled Altar",
    season = "midnight-s1",
    references = {
        [[
Boss: The Coiled Altar
Difficulty: Mythic
Length: 11:17
Encounter: 3429
Phase: P2 2:55
Phase: P2.5 6:22
Phase: P3 7:00
Coalesced Venom: 0:07+168, 7:06+251
Fangs of the Coiled Altar: 0:00, 1:24, 2:49
Toxic Deluge: 0:01, 0:44, 1:26, 2:09, 2:52, 7:02, 7:43, 8:43, 9:24, 10:24
Axegrinder: 0:13, 1:38
Sever: 0:22, 0:39, 0:59, 1:16, 1:47, 2:04, 2:24, 2:41
Venom Rupture: 0:22, 0:39, 0:59, 1:16, 1:47, 2:04, 2:24, 2:41, 7:35, 8:06, 8:39, 9:16, 9:47, 10:19
Venomfang: 0:29, 1:04, 1:54, 2:29
Guillotine: 0:47, 2:12
Dreadful Presence: 2:55+206
Dreadmarch: 3:02, 3:39, 4:27, 5:04, 5:52, 7:56, 9:33, 10:21
Spiritcackle: 3:08, 3:41, 4:33, 5:06, 5:58, 8:02, 9:38
Gloombomb: 3:15, 3:52, 4:40, 5:17, 6:05, 7:26, 8:10, 8:48, 9:52
Retaliatory Malice: 3:12, 3:45, 4:37, 5:10, 6:02
Soul Sever: 3:33, 4:04, 4:58, 5:29
Eternal Nightfall: 4:05+15, 5:30+15, 7:37+15, 9:14+15
Suffocating Darkness: 4:07, 5:32, 7:39, 9:16
Ghastly Regeneration: 6:22
Spirit Erasure: 6:27+20
Defilement of the Coiled Altar: 7:00, 8:42, 10:24
Grim Guillotine (lead 6): 7:21, 8:26, 10:06
Blighted Sever: 7:35, 8:06, 8:39, 9:16, 9:47, 10:19
]],
    },
})
