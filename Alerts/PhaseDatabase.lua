local ADDON, CRT = ...

-- Shipped phase triggers: the event that starts a phase of a boss. An entry is added only after
-- /crt dev probe confirms in a real pull that the event and its value are readable, in the form
--   [encounterID] = { [ph] = { kind, value } }
-- where ph is the phase number (1.5 is allowed), kind is "emote", "untargetable", "targetable" or
-- "newboss", and value is the emote text or a unit (boss1 to boss5). Your own triggers
-- (CRT.db.alerts.phases) are laid over these.

CRT.AlertPhaseDB = {} -- filled by Bosses/Registry.lua from each boss file's phases
