local ADDON, CRT = ...

-- The marker displays that ship with the addon, one per boss encounter at most, keyed by the
-- encounter ID. Each is made in the dev editor (/crt dev markers, Dev/MarkerEditor.lua) and its
-- Export written into the boss file, so everyone with the addon gets the same display.
--
--   name       what the display is called, shown on its drag bar and the Reminders tab
--   slots      how many messages it shows, 1 to 8, in the order they are sent
--   layout     "row" (left to right), "column" (top to bottom) or "grid" (rows of four)
--   iconSize   the marker's size in pixels
--   number     true to show the slot number above each marker
--   names      true to show who sent it under each marker
--   clearGap   seconds after the last message before it clears, 0 for never
--   clearFull  seconds after the last slot fills before it clears, 0 for never
--   clearPhase true to clear when a new phase starts (Alerts/Engine.lua)
-- It always clears when the pull starts and when it ends, kill or wipe.
--
-- Raiders send the markers with macros such as /raid {rt3} (or {diamond}), one per marker.

-- They ship in each boss's file in the season packs (field markers), and Bosses/Registry.lua puts
-- the loaded seasons' displays here.

CRT.MarkerDisplayDB = {
    displays = {},
}
