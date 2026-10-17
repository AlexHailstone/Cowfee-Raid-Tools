local ADDON, CRT = ...

-- Entombed Sentinels. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3445 comes from the EncounterID line of Alex's raid note for this boss, not from a pull
--             yet.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot on 2026-10-17 (the vault note
--             "Cowfee Raid Tools - Boss Reference Transcriptions"). The rows have no types yet: Alex
--             sets them in game with the Reference types tool on the Development page, and its export
--             replaces this block.

CRT.Bosses:Register({
    encounterID = 3445,
    name = "Entombed Sentinels",
    season = "midnight-s1",
    references = {
        [[
Boss: Entombed Sentinels
Difficulty: Mythic
Length: 7:33
Encounter: 3445
Phase: P2 0:56
Phase: P3 2:37
Phase: P4 4:18
Phase: P5 5:59
Empowering Slam: 0:06, 0:28, 1:04, 1:25, 1:47, 2:09, 2:45, 3:06, 3:28, 3:50, 4:26, 4:47, 5:09, 5:31, 6:07, 6:28, 6:50, 7:12
Bloodvenom Injection: 0:08, 0:30, 1:04, 1:25, 1:47, 2:09, 2:45, 3:06, 3:28, 3:50, 4:26, 4:47, 5:09, 5:31, 6:07, 6:28, 6:50, 7:12
Mark of Acid: 0:08+48, 0:56+101, 2:37+101, 4:18+101, 5:59+94
Venom Coagulation: 0:09, 1:06, 1:58, 2:47, 3:39, 4:28, 5:20, 6:09, 7:01
Toxic Droplets: 0:15, 1:10, 1:43, 2:16, 2:51, 3:24, 3:57, 4:32, 5:05, 5:38, 6:13, 6:46, 7:19
Contaminate: 0:15+18, 1:12+18, 2:04+18, 2:53+18, 3:45+18, 4:34+18, 5:26+18, 6:15+18, 7:07+18
Unstable Miasma (lead 8): 0:26, 1:21, 2:03, 3:02, 3:44, 4:43, 5:25, 6:24, 7:06
Shifting Protovenom (lead 6): 0:36, 1:35, 2:16, 3:16, 3:57, 4:57, 5:38, 6:38, 7:19
Blighted Blood: 0:42+18, 1:38+18, 3:19+18, 5:00+18, 6:41+18
Vitriolic Stasis: 0:46, 2:26, 4:07, 5:48
# The bar and lead lengths are estimates from the screenshot's axis.
# The planner marks a short intermission ("In...") before each phase line; its start isn't readable, so
# only the phase lines are here.
]],
    },
})
