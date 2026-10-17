local ADDON, CRT = ...

-- The Twin Fangs. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3421 comes from the EncounterID line of Alex's raid note for this boss, not from a pull
--             yet.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot on 2026-10-17 (the vault note
--             "Cowfee Raid Tools - Boss Reference Transcriptions"). The rows have no types yet: Alex
--             sets them in game with the Reference types tool on the Development page, and its export
--             replaces this block.

CRT.Bosses:Register({
    encounterID = 3421,
    name = "The Twin Fangs",
    season = "midnight-s1",
    references = {
        [[
Boss: The Twin Fangs
Difficulty: Mythic
Length: 7:50
Encounter: 3421
Eternal Venom: 0:15+455
Caustic Deluge: 0:09, 1:10, 2:44, 3:45, 5:19, 6:20
Blood Torrent: 0:09, 1:10, 2:44, 3:45, 5:19, 6:20
Stone Breaker: 0:30, 1:31, 3:05, 4:06, 5:40, 6:41
Venomous Emergence: 0:36+20, 1:37+20, 3:11+20, 4:12+20, 5:46+20, 6:47+20
Coiling Ichor: 0:43+15, 1:44+15, 3:18+15, 4:19+15, 5:53+15, 6:54+15
Stir the Depths: 0:47, 1:48, 3:22, 4:23, 5:57, 6:58
Ravenous Feast (lead 6): 1:04, 2:05, 3:39, 4:40, 6:14, 7:15
Tainted Blood: 1:03, 2:04, 3:38, 4:39, 6:13, 7:14
Sanguine Storm: 2:16+20, 4:51+20, 7:26+20
Vile Flood (lead 6): 2:20, 4:55, 7:30
# The bar and lead lengths are estimates from the screenshot's axis.
# Stone Breaker's and Ravenous Feast's labels overlap their icons; their times follow the other rows'
# spacing and need a check against the planner.
]],
    },
})
