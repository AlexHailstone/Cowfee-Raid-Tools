local ADDON, CRT = ...

-- Season data for the Timeline's Cooldowns row (read by Alerts/Cooldowns.lua): healer cooldowns and
-- raid defensives as { class, spellID, kind }, where kind is "healer" (a healer's cooldown) or "raid" (a
-- raid defensive). The names beside the IDs are for the reader only; the row shows the game's own name.
-- Last checked: 12.1.5 (spell IDs written from memory, not yet confirmed in game)
-- Check this list on every patch pass. An ID the game deleted outright has no name and is skipped at
-- runtime, but a removed or reworked talent may keep its name and go on showing, so only the check
-- catches it.

CRT.AlertCooldownData = {
    { class = "DRUID", spellID = 740, kind = "healer" }, -- Tranquility
    { class = "DRUID", spellID = 33891, kind = "healer" }, -- Incarnation: Tree of Life
    { class = "DRUID", spellID = 391528, kind = "healer" }, -- Convoke the Spirits
    { class = "DRUID", spellID = 197721, kind = "healer" }, -- Flourish
    { class = "EVOKER", spellID = 363534, kind = "healer" }, -- Rewind
    { class = "EVOKER", spellID = 359816, kind = "healer" }, -- Dream Flight
    { class = "EVOKER", spellID = 370960, kind = "healer" }, -- Emerald Communion
    { class = "EVOKER", spellID = 370537, kind = "healer" }, -- Stasis
    { class = "EVOKER", spellID = 374227, kind = "raid" }, -- Zephyr
    { class = "MONK", spellID = 115310, kind = "healer" }, -- Revival
    { class = "MONK", spellID = 388615, kind = "healer" }, -- Restoral
    { class = "MONK", spellID = 322118, kind = "healer" }, -- Invoke Yu'lon, the Jade Serpent
    { class = "MONK", spellID = 325197, kind = "healer" }, -- Invoke Chi-Ji, the Red Crane
    { class = "MONK", spellID = 116849, kind = "healer" }, -- Life Cocoon
    { class = "PALADIN", spellID = 31821, kind = "healer" }, -- Aura Mastery
    { class = "PALADIN", spellID = 31884, kind = "healer" }, -- Avenging Wrath
    { class = "PALADIN", spellID = 375576, kind = "healer" }, -- Divine Toll
    { class = "PALADIN", spellID = 6940, kind = "healer" }, -- Blessing of Sacrifice
    { class = "PRIEST", spellID = 64843, kind = "healer" }, -- Divine Hymn
    { class = "PRIEST", spellID = 265202, kind = "healer" }, -- Holy Word: Salvation
    { class = "PRIEST", spellID = 200183, kind = "healer" }, -- Apotheosis
    { class = "PRIEST", spellID = 62618, kind = "healer" }, -- Power Word: Barrier
    { class = "PRIEST", spellID = 47536, kind = "healer" }, -- Rapture
    { class = "PRIEST", spellID = 246287, kind = "healer" }, -- Evangelism
    { class = "PRIEST", spellID = 33206, kind = "healer" }, -- Pain Suppression
    { class = "PRIEST", spellID = 47788, kind = "healer" }, -- Guardian Spirit
    { class = "SHAMAN", spellID = 108280, kind = "healer" }, -- Healing Tide Totem
    { class = "SHAMAN", spellID = 98008, kind = "healer" }, -- Spirit Link Totem
    { class = "SHAMAN", spellID = 114052, kind = "healer" }, -- Ascendance
    { class = "WARRIOR", spellID = 97462, kind = "raid" }, -- Rallying Cry
    { class = "DEMONHUNTER", spellID = 196718, kind = "raid" }, -- Darkness
    { class = "DEATHKNIGHT", spellID = 51052, kind = "raid" }, -- Anti-Magic Zone
    { class = "DRUID", spellID = 106898, kind = "raid" }, -- Stampeding Roar
}
