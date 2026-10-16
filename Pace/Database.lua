local ADDON, CRT = ...

-- The pace plans that ship with the addon, keyed by encounter ID: where each boss's health should be
-- as the fight goes. Made on the Pace page, and its Export written into the boss file, so everyone
-- gets them.
--
--   mode   "phase" (times are seconds into each phase, the default) or "time" (seconds from the pull)
--   rows   { { ph = phase, t = seconds, unit = "boss1" to "boss5", hp = expected health in percent } }
-- Between two rows the expected health runs in a straight line from one to the next.

-- They ship in each boss's file in the season packs (field pace), and Bosses/Registry.lua puts the
-- loaded seasons' plans here.

CRT.PaceDB = {
    bosses = {},
}
