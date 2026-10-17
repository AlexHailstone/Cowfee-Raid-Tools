local ADDON, CRT = ...

-- Sszorak. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3420 comes from the Timeline's saved Mythic pulls of this boss.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot, with each ability's type set
--             by Alex in the Reference types tool (Development page). Serpent's Fury (Mythic) waits
--             for its cast times.

CRT.Bosses:Register({
    encounterID = 3420,
    name = "Sszorak",
    season = "midnight-s1",
    references = {
        [[
Boss: Sszorak
Difficulty: Mythic
Length: 6:32
Encounter: 3420
Mutilate (type raid): 0:08+19, 0:55+19, 2:15+19, 3:02+19, 4:22+19, 5:09+19
Ravage (type soak): 0:08, 0:55, 2:15, 3:02, 4:22, 5:09
Tempest (type generic): 0:12, 0:59, 2:19, 3:06, 4:26, 5:13
Venomous Surge (type generic): 0:29, 1:17, 2:36, 3:23, 4:43, 5:30
Virulence (type raid): 0:27, 1:16, 2:32, 3:22, 4:39, 5:29
Raging Crosswinds (type generic): 0:39, 1:26, 2:46, 3:33, 4:53, 5:40
Dig In (type generic): 1:40+27, 3:47+27, 5:54+27
# The bar lengths are estimates from the screenshot's axis. The planner's green bar covers both the
# Mutilate and Ravage rows; it is on Mutilate here until Alex says whose it is.
# Left out, cut off at the end of the screenshot: the last Mutilate and Ravage (about 6:30).
# Raging Crosswinds is greyed out in the planner.
# Missing: Serpent's Fury (type mythic), its cast times aren't known yet.
]],
    },
})
