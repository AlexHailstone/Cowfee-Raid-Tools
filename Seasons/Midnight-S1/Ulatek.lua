local ADDON, CRT = ...

-- Ula'tek. Everything the addon ships about this boss, read by Bosses/Registry.lua.
--
-- encounterID 3492 comes from the boss's Warcraft Logs rankings link (boss=3492), not from a pull
--             yet.
-- references  The Mythic reference timeline, in the Timeline's text format (see Timeline/Database.lua
--             for the format), transcribed from a planner screenshot on 2026-10-17 (the vault note
--             "Cowfee Raid Tools - Boss Reference Transcriptions"). The rows have no types yet: Alex
--             sets them in game with the Reference types tool on the Development page, and its export
--             replaces this block.

CRT.Bosses:Register({
    encounterID = 3492,
    name = "Ula'tek",
    season = "midnight-s1",
    references = {
        [[
Boss: Ula'tek
Difficulty: Mythic
Length: 10:15
Encounter: 3492
Necrotic Vapors: 0:00+615
Call of the Serpent: 0:04, 1:15, 5:23, 6:21, 6:51, 8:29
Toxic Incubation (lead 6): 0:15+15, 1:24+15, 7:23+15
Mother's Wrath: 0:26, 1:36, 6:27, 7:52, 9:00
Mephitic Thrash: 0:48, 1:46
Caustic Waves (lead 6): 0:56, 1:52, 7:06, 8:01, 8:51, 9:35
Submerge: 1:19, 7:22, 8:14, 9:14
Rage of the Shackled (lead 6): 2:25+20, 4:54+20, 9:43+20
Venomous Heart: 2:25+20, 4:54+20, 9:43+20
Writhing Gestation: 3:04, 4:12
Blight Vein: 3:33
Slithering Gestation: 6:22, 6:52, 8:30
Serpent's Bite: 6:42, 7:46, 9:30
Volatile Purge: 7:01, 8:06, 9:49
Circling Prey (lead 6): 7:20, 8:11, 9:12
Fester Burst: 0:39, 1:14, 1:48, 2:23, 7:45, 8:19
# Left out, labels overlapped: Spectral Coils (three groups, near 0:4x, 2:1x and 6:2x), Shadow Molt (near 2:5x or 3:50), Grasping Fangs (near 3:1x), Acidic Expulsion (near 8:40), a second Necrotic Vapors cast near 2:51, and a second Blight Vein cast near 3:2x.
# Left out, cut off at the edge: Circling Prey's last cast near 10:1x.
# The phases: Stage 1 at 0:00, Stage 2 at about 2:24, Int at about 4:56 and Stage 3 at about 6:00.
]],
    },
})
