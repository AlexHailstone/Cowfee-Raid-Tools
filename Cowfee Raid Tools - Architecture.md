---
type: reference
area: wow-addons
status: active
created: 2026-10-12
updated: 2026-10-12
tags: [wow, addon, lua, architecture]
---

# Cowfee Raid Tools: architecture

How the addon is put together, so a new feature or a patch fix can be made without re-reading every file. Start from [[Cowfee Raid Tools - readme]]. Build steps and patch checks are in [[Cowfee Raid Tools - Build and Patch Runbook]].

## Files and load order

Files load in the order the `.toc` lists them. Each file starts with `local ADDON, CRT = ...`, which gives every file the same private table. `Core.lua` also exposes it as the global `CRT` for debugging.

| Order | File | Job |
|---|---|---|
| 1 | `Core.lua` | Creates `CRT`, the default settings, the `CRTDB` saved variable, `CRT:Print`, and the scaled font objects |
| 2 | `Slash.lua` | The `/crt` command |
| 3 | `UI\Panel.lua` | The main window, the left menu and the page registry |
| 4 | `Groups\Data.lua` | Names, rosters, roles, the working grid, saved layouts, export and import |
| 5 | `Groups\Apply.lua` | Moves the live raid into the grid's layout |
| 6 | `Groups\Page.lua` | The Raid Groups page: grid, picker, dialogs, Quick Load list, buttons |

`CowfeeRaidTools.toc` holds the title, version, `## Interface:` number and `## SavedVariables: CRTDB`.

## Saved data (`CRTDB`)

```lua
CRTDB = {
    window = { point, x, y },        -- panel position
    lastPage = "groups",             -- page key reopened by /crt
    classCache = { ["name-realm"] = "WARRIOR" },   -- last class seen, lowercase keys
    roleCache  = { ["name-realm"] = "TANK" },      -- last role seen, lowercase keys
    groups = {
        presets = { { id = 1, name = "Mythic Roster", slots = { 40 strings } } },
        nextId = 2,
        selected = 1,                -- id of the loaded layout, or nil
        keepChanges = true,          -- auto-save edits to the selected layout
        source = "raid",             -- name picker source: "raid" or "guild"
        working = { 40 strings },    -- the grid being edited
    },
}
```

A slot holds `"Name-Realm"` or `""`. Slot number is `(group - 1) * 5 + position`, so slots 1 to 5 are Group 1. Defaults are merged into the saved table on load by `copyDefaults` in `Core.lua`, so adding a new setting only needs a new default.

## Names

Every stored name is `Name-Realm`, so same-name players on different realms stay distinct. `Groups.Normalize` appends your own realm to a bare name. `Groups.Display` uses `Ambiguate(key, "none")`, which hides the realm when it is your own. Comparisons use lowercase keys.

A name pasted without a realm is stored with your realm. `Groups.MakeLookup` (grid) and `resolveLayout` (apply) both fall back to matching the bare name against a raid member when the match is unique, so cross-realm players still match.

## Roles and class

`Groups:ReadRoster` returns `{ key, subgroup, class, role }` for each member. Raid uses `GetRaidRosterInfo`. Party and solo use `UnitFullName` and treat everyone as group 1, so you always appear in your own roster. Role comes from `UnitGroupRolesAssigned`, and your own role falls back to your spec. Every class and role seen is cached in `CRTDB` so absent players keep their color and icon.

## Panel and pages

`UI:RegisterPage(key, title, builder)` adds a menu entry. The panel builds each page lazily the first time it is selected and calls `builder(pageFrame)`. The page sets its own `OnShow` to refresh. `UI:Show(key)` and `UI:Toggle()` open the panel.

## The Raid Groups page

| Piece | How it works |
|---|---|
| Slots | 40 backdrop buttons. Left-click opens the picker, right-click clears, drag swaps |
| Drag and drop | A ghost frame follows the cursor and the drop target is found with `IsMouseOver`, because other frames get no mouse events during a drag |
| Picker | One shared popup with an edit box and 10 rows, plus a full-screen click catcher that closes it |
| Dialog | One shared frame for the one-line name prompt and the multi-line Export and Import box |
| Quick Load | A scroll list of saved layouts, rebuilt on every change |
| Rename | An edit box in the header, shown when a layout is loaded. It saves through `Groups:Rename` when it loses focus, and the refresh never overwrites it while it is being typed in |
| Refresh | Every edit calls `Groups:Fire()`, which refreshes the page. The page also refreshes on group, guild, role and spec events |

Edits go through `Groups:SetSlot`, `Swap` and `ReplaceWorking`. Each ends in `Groups:Touch()`, which marks the grid unsaved, auto-saves when Keep changes is on, and fires the refresh.

## Consumables

The ready check row is separate from the group layout code. `Consumables/Database.lua` is the list of consumables that ships with the addon. `Consumables/Data.lua` holds the categories, the player's saved order in `CRTDB.consumables`, bag helpers, and `Consumables:Status(key)`, which turns one category into an icon, a time, a count and a state (active, low, missing, unknown, unset).

`Consumables/Bar.lua` draws the icons, and is shared by the ready check row and the bar on the tab.

The tab lets the player drag items onto the bar to add their own entries (`CRTDB.consumables.extra`), and `Data.lua` learns the buff of an item the first time it is used, by watching its bag count drop and a new long buff appear (`CRTDB.consumables.learned`).

`Consumables/Ants.lua` is the marching ants animation, and `Consumables/Tools.lua` holds the `scan` and `check` maintainer commands. `Consumables/Display.lua` is the five-icon frame, shown on `READY_CHECK`, anchored to Blizzard's dialog when it can be found, and refreshed twice a second.

Food, flask and weapon icons are secure buttons that use the first assigned item in your bags, which makes the row protected, so showing, hiding, moving and changing the click action wait for the end of combat.

`Consumables/Page.lua` is the tab: the live bar, drag and drop, the icon order, and the item priority. The full detail, display rules and the update routine are in the maintenance skill's `references/consumables.md`.

## Previews and saved positions

`UI/Panel.lua` has a preview registry. A floating panel calls `UI:RegisterPreview(key, setFn)`, and the **Previews** button in the corner of the main window calls every registered function, then turns them off again when the window closes. Each panel shows a drag handle during a preview and saves its position in `CRTDB` when dropped, in `CRTDB.consumables.position` and `CRTDB.debuffs.position`. All of this is saved per player in their own saved variables, and new settings are added as defaults in `Core.lua`.

`UI/Controls.lua` builds every dropdown and slider on the pages, in the style of the game's Edit Mode settings: `UI.Dropdown` uses `WowStyle1DropdownTemplate` with a radio menu (`SetupMenu`, `CreateRadio`, `GenerateMenu` on refresh), and `UI.Slider` uses `MinimalSliderWithSteppersTemplate` (`Init`, the `OnValueChanged`, `OnInteractStart` and `OnInteractEnd` callbacks, and a Right label formatter). Each returns a row frame with `refresh()`, so pages add it to their controls list. No page cycles through choices with a button.

`UI/SettingsPage.lua` is the General Settings page (named Addon Settings before 0.16.0, key still `settings`), in two columns, saved in `CRTDB.ui` (and `CRTDB.window.scale`, which moved there from Quality of Life). Fonts: every addon text uses the `CRTFont*` objects made in `Core.lua` (including `CRTFontEdit` for edit boxes, `CRTFontButtonSmall*` and `CRTFontStandard*` at the game's own sizes, and the dropdown and slider template text), and `CRT:ApplyFonts` sets their face, outline and size together. `CRT:FontList` is the game's four fonts plus any shared through LibSharedMedia-3.0 when another addon loaded it (read through `LibStub`, never shipped). Picking a font on Addon Settings asks first in the game's confirmation box, then `CRT:SetAddonFont` sets it for all text and every note window, which redraw through `Notes:Fire`. Fonts are applied again at `PLAYER_LOGIN`, once every addon has registered its shared fonts. Style: `UI:ApplyStyle` hides or shows the `BasicFrameTemplateWithInset` textures and a flat black background, and sets their alpha. Layers: each floating window calls `UI:RegisterLayer(key, frame)` instead of `SetFrameStrata`, with the kinds and defaults in `UI.LAYERS`; `UI:SetLayer` saves a change and applies it, and a protected frame (the consumables bar) waits until combat ends. The boss debuff timers keep the game's own font, because `Blizzard_PrivateAurasUI` draws them with the shared `GameFontNormalSmall` in a protected environment. Reports: `ui.hideRealms` makes `Groups.ReportName` (in `Groups/Data.lua`) drop realms with `Ambiguate(key, "short")`; the Late Tracker and Tattlebot use it for names on their pages, in chat posts and in Discord exports, while the Raid Groups grid keeps `Groups.Display`.

Since 0.16.0: **Profiles** (`Profiles.lua`). A profile is every key in `CRT.defaults` except the shared `classCache` and `roleCache`. The active profile stays at the top of `CRTDB` under its old keys, the others wait in `CRTDB.profiles[name]`, and `CRTDB.activeProfile` and `CRTDB.defaultProfile` name them. Each character's choice is in the per-character saved variable `CRTDBChar.profile`. `Profiles:Load`, called from `Core.lua` on `ADDON_LOADED` before the defaults are filled in, swaps the character's profile to the top, so switch, copy and reset only save the choice and call `ReloadUI`. Export is `C_EncodingUtil` CBOR, deflate and base64 behind a `CRTP1:` prefix.

**Minimap** (`UI/Minimap.lua`): a draggable button at `CRTDB.minimap.angle`, hidden with `CRTDB.minimap.hide`, plus the global `CowfeeRaidTools_OnAddonCompartmentClick` named in the `.toc` for the game's addon menu.

**Reset position** (after 0.16.0): `UI.ResetButton(parent, onClick)` in `UI/Panel.lua` is a small Reset button on each movable window. It sits on the drag bar of the consumables bar, debuff panel and your next spell alert, in the top right of a note window while it is unlocked, and in the top right of the ready check window and low-health banner during Previews. The pages no longer have Reset position buttons. `/crt dev reset` (developer builds only) resets every window and the main panel at once.

**Looks**: `ui.modern` picks the Modern look. `UI:ApplyStyle` paints the window with `CRT.MOCHA`, `UI:LayoutMenu` groups the menu by `UI.MENU_GROUPS`, page tabs register with `UI:RegisterTab` and change through `UI:SetTabSelected`, and `UI:SkinTree` gives every `UIPanelButtonTemplate` button and `WowStyle1DropdownTemplate` dropdown a flat skin it can switch on and off (run when a page is built and when a tab changes). `CRT:ApplyFonts` uses Arial Narrow at 110% when the font is Default, and turns the game's gold text latte and white text cream.

Sound: every sound the addon plays goes through `CRT:PlaySound(kit)` in `Core.lua`, which uses the channel picked on Addon Settings (`ui.soundChannel`: Master, SFX, Dialog, Ambience or Music). `QoL/LowHealthSound.lua` turns on the game's own low-health pulse from Combat Audio Alerts (`CAAEnabled`, `CAAPulsePlayerHealthPercent` 1 to 9 for under 90% to under 10%, and `C_CombatAudioAlert.SetCategoryVolume` for its volume), because an addon can't compare your secret health to play a sound itself. It saves every game setting it changes in `qol.lowHealth.caaSaved` and puts them back when turned off, and switches off the spoken alerts only when Combat Audio Alerts were off before. The game plays the pulse on its own voice output, unless another Sound or Output is picked: then the game's pulse is set to volume 0 and a `hooksecurefunc` on `CombatAudioAlertManager:SetHealthPulseSoundKit` plays your choice with `C_Sound.PlaySoundWithOptions` on your channel whenever the game's pulse starts, changes tier or stops. **Work in progress since 0.14.1:** the low-health sound is switched off (`LowHealthSound.WIP`), because the game hides its low-health decision from addons and its Combat Audio Alerts code errored on health changes alongside other addons; the code is as in 0.14.0.

## Ready Check

`ReadyCheck/Page.lua` is the Ready Check settings page, with the tabs Window, Your bar and Settings (the automatic report, called On ready check before 0.13.1) (the Raid report tab was removed in 0.13.0, and checking the group now happens in the ready check window, where `Window:PostColumn` posts a shift-clicked column).

Your bar is built by `Consumables/Page.lua` through `CRT.ConsumablesPage.Build`, so the consumables code is unchanged apart from `Consumables:BuffIds`, which hands the report the buff IDs listed or learned for a category. Both lists on Your bar are reordered by dragging rows (`draggable` in `Consumables/Page.lua`, which calls `Consumables:MoveCategoryTo` and `Consumables:MoveItemTo`). The bar's on/off, Not when I start the ready check (`consumables.notStarter`, checked on `READY_CHECK` in `Consumables/Display.lua`) and the warning minutes are on the Settings tab. `ReadyCheck/Report.lua` reads every group member's buffs with `C_UnitAuras.GetAuraDataByIndex`, runs the food, flask, rune, Vantus rune and raid buff checks, and posts or prints the result. It also runs on `READY_CHECK` and `START_PLAYER_COUNTDOWN`, and posts to chat only for whoever started them. Players whose buffs come back secret are reported as couldn't check.

`ReadyCheck/BuffLock.lua` is the Ready button lock (`readycheck.buffLock`, on by default). On `READY_CHECK` it finds your class's raid buffs in `Report.BUFFS`, reads the group with `Report:ReadGroup` and `Report.Cell`, and if anyone readable is missing one it disables the game's `ReadyCheckFrameYesButton` and lays a cover button over it with a tooltip of who is missing what. The cover rechecks after `UNIT_AURA` (at most every 0.25 s, only while locked), unlocks when everyone has the buff, after 10 seconds, or on `READY_CHECK_FINISHED`. While Shift is held it enables the game's button and stops taking the mouse, so the click is the game's own and the addon never answers the ready check itself.

`ReadyCheck/Window.lua` is the ready check window, built on `Report:ReadGroup` and `Report.Cell`, with durability shared over the `CRTReady` addon message prefix. See the maintenance skill's `references/readycheck.md`.

## Debuffs

`Debuffs/Data.lua` holds the settings, `Debuffs/Panel.lua` builds a plain movable frame whose slots are private aura anchors (`C_UnitAuras.AddPrivateAuraAnchor`), which is how the game lets an addon place its boss mechanic debuffs, plus an optional second row using a Blizzard `AuraContainer` for regular debuffs, and `Debuffs/Page.lua` is the settings page. The panel is faded with alpha, not shown or hidden, so combat cannot block it. The container formats are largely undocumented, so each setup call is guarded and `/crt dev debuffs` (developer builds only, also a button in the `/crt dev` editor) reports what worked. See the maintenance skill's `references/debuffs.md`.

The Look settings (`swipe`, `swipeEdge`, `countdownNumbers`, `timerPosition`, `timerX`, `timerY`, `borderScale`) are passed straight into each anchor's arguments: `showCooldownFrame`, `showCooldownEdge`, `showCountdownNumbers`, `iconInfo.borderScale`, and `durationAnchor`, which is left out when the timer is hidden. `Debuffs:TimerAnchor` turns a position into anchor points. The anchors are rebuilt out of combat whenever any of these change, the preview tiles draw the same choices with a live Cooldown swipe, and the regular row's swipes follow them too.

## Raid notes

`Notes/Parse.lua` reads the note text into timers, phases, free text and an invite list. `Notes/Data.lua` stores notes in `CRTDB.notes`, caches spell names and icons out of combat, and turns an invite list into a Raid Groups layout. `Notes/Engine.lua` starts the timers on `ENCOUNTER_START` (or a test run), starts later phases on Next phase, and decides which lines are yours by name or role. `Notes/Window.lua` builds three windows from one design (timers, assignments, personal note), each lockable and resizable by hand, `Notes/Page.lua` is the Raid Notes page with four tabs (Notes, Reminders, Phases, Settings), `Notes/Reminders.lua` and `Notes/Phases.lua` build the Reminders and Phases tabs, `Notes/Settings.lua` builds the Settings tab (the windows, your alert, sharing and the alert bars column), `Notes/Alert.lua` is the personal alert, and `Notes/Comm.lua` shares a note in parts over addon messages. See the maintenance skill's `references/notes.md`.

Since the alerts engine, `Notes/Engine.lua` no longer keeps its own clock. It keeps its public calls (`Start`, `Stop`, `NextPhase`, `Remaining`, `CurrentPhase`, `Elapsed`, `IsMine` and the rest), so the windows and the page did not change, but its timers are the `note` block of the alerts engine and its phase starts come from the engine's clock. `NoteEngine:Start` hands the note to the engine unless the engine is already collecting a pull, `/crt note stop` stops the whole run, and text to speech moved to `Alerts/Speech.lua` (`NoteAlert:Speak` is now a wrapper). Nothing under `CRTDB.notes` was renamed.

## Alerts

`Alerts/` is the engine behind the Raid Notes timers and your own reminders. `Rules.lua` is the conflict rules as plain functions with no game calls (constants `DUPLICATE`, `GROUP`, `SPEECH_BEHIND`, `SPEECH_TIMEOUT`), `Engine.lua` holds the blocks, the run and the one phase clock, `Speech.lua` is the speech queue, `Reminders.lua` saves reminders and works out their times, `PhaseDatabase.lua` is the shipped phase triggers (empty until the dev probe confirms one), `Phases.lua` watches the phase events, `Bars.lua` is the movable bars window and `Editor.lua` is the reminder editor. In `.toc` order, Rules, Engine and Speech load before the Notes files, and Reminders, PhaseDatabase, Phases, Bars and Editor load after the Timeline files, since reminders read the references.

**Blocks.** Everything on screen comes from a block, registered with `Alerts:RegisterBlock(key, { label, group, Entries })`. `Entries(run)` returns items with `ph` (the phase) and `time` (seconds into it). The blocks are `note` (`Notes/Engine.lua`, `group = false`, so a note's lines show exactly as before), `mine` (your reminders, `group = true`) and `minetest` (the editor's Test, which gives items only to a run with reason `test`). Blocks do not compete: duplicates (`DUPLICATE`) and grouping (`GROUP`) apply only inside one block with `group = true`. Speech is the one place that drops across blocks: when the queue falls behind, raid-wide lines are dropped first, your note lines are kept longer, and your reminders are kept longest.

**The run.** `ENCOUNTER_START` calls `Alerts:Start`, which runs the `onPull` hooks (the note engine picks its note, the phase watchers snapshot the boss units), collects every block's items once, then starts the lowest phase. `ENCOUNTER_END` stops a run that began on an encounter. A later phase starts on its event or on Next phase and a repeat is ignored. Starting a phase skips the earlier ones that never began. A phase with an event trigger is never the pull phase. `Alerts:Lines(now)` turns the started phases' items into timed lines through `Rules.Lines`, and the Next spell alert, the bars and the speech queue all read those lines. Items with no output (other players' note timers, which only show in the timers window) are left out, and the lines are built once per change: `Alerts.version` goes up on Start, Stop, StartPhase and RegisterBlock, and until then every caller gets the same table, which they only read. Next phase (the Notes page button, `/crt note next`) works for any run, with or without a note, and walks the merged phase list of every block; `Alerts:PeekNextPhase()` names the phase it would start without starting it, so the button reads `Next phase (1.5)` and the chat line says which phase started. A pull with reminders but no note shows on the Notes page as running reminders, while `NoteEngine.running` (the note windows) stays false. A note run replaced by another run, such as the editor's Test, drops its note.

**Reminders.** `CRT.db.alerts.reminders[encounterID][id]` holds a reminder with its text, spell, outputs (alert, bar, speech), warn, speech mode, priority, difficulty and optional typed `times` (`P1 0:02, 1:17; P2 +0:18`). With no typed times the times come from the boss's reference timeline, converted to a phase and seconds into it through the numbered phase lines. They are keyed by the encounter ID that `ENCOUNTER_START` gives, so the tabs list only bosses with one: recorded pulls, the current raid's bosses from `Journal:RaidBosses()` (shared with the Timeline page) and references with an Encounter line. The double-click on a cast in `Timeline/View.lua` opens the editor with the spell and time filled in (a reference row with no spell prefills the row's name); a boss shown under a reference's name gets its encounter ID from `Journal:ResolveID`. The Next spell alert shows a note line's spell name, as before, and any other line's own text.

**Phase events.** `CRT.db.alerts.phases[encounterID][ph] = { kind, value }` on top of `CRT.AlertPhaseDB`: a boss emote containing text, `UNIT_TARGETABLE_CHANGED` for a boss unit (read through `UnitCanAttack`), or a new boss unit (`INSTANCE_ENCOUNTER_ENGAGE_UNIT`). Values the game hides never match. `Dev/TimelineProbe.lua` logs these events on a real boss so a shipped trigger is added only once the values are readable.

**Saved data.** `CRT.defaults.alerts` in `Core.lua`: `bars = { shown, noteLines, cap, ahead, width, height }` (and `position` once moved), `reminders`, `phases`, `overrides` (empty in Stage 1) and `nextId`. Because `Profiles.lua` reads the defaults, profiles carry it. Settings are read from `CRT.db.alerts` on every use, so a profile switch or reset in the middle of a pull is safe. See the maintenance skill's `references/alerts.md`.

## Late tracker

`Late/Data.lua` keeps the schedule and the expected Raid Groups layout in `CRTDB.late`, starts a raid night from the schedule (a 5-second ticker) or from Start raid now, marks players as joined on `GROUP_ROSTER_UPDATE`, ends the night when the group disbands, on End raid or after 8 hours, and adds up the totals. `Late/Page.lua` is the Late Tracker page. The running night is stored in saved variables, so a reload does not lose it. See the maintenance skill's `references/late.md`.

## Tattlebot

`Tattlebot/Database.lua` is the shipped list of tracked boss mechanics, `CRT.TattleDB.bosses`, each boss with `mechanics = { { name, spells = { IDs } } }`. Players add their own in `CRTDB.tattle.custom[spellID]`, a mechanic name or `{ name, boss, encounterID }` when added from the Mechanics tab's Last fight view, which lists `Tattle:Scan()` with check boxes. `Tattle.LastFightBoss()` says whether the meter's current session is the last boss fight, by counting combat starts since `ENCOUNTER_END`. When that fight is the pull Tattlebot saved (`Tattle.LastFightPull()`), Add checked also writes the added spells' per-player damage from the scan into that pull (`Tattle:Backfill`). With no saved pull, `Tattle:AddScannedPull` saves the scanned fight as a pull (named "Not a boss" when it wasn't one) and keeps it linked to the scan for later adds. `Tattle.List()` maps every tracked spell ID to its mechanic. Pulls store damage per spell ID, and the reports add the IDs of one mechanic together (`Tattle.ByMechanic`), counting a mechanic once per pull. `Tattlebot/Data.lua` waits for `ENCOUNTER_END`, then for `PLAYER_REGEN_ENABLED` if still in combat, and one second later reads `C_DamageMeter.GetCombatSessionFromType(Current, DamageTaken)` and, per player, `GetCombatSessionSourceFromType` for their spells. It keeps only the listed spells, plus the meter's `AvoidableDamageTaken` spells when that setting is on. The meter is secret in combat, so a read that meets a secret is tried again up to 5 times. Players are named by matching the meter's GUID to the group, then by the meter's name. Pulls go into a night in `CRTDB.tattle.current`, which moves to `history` on End night or when the next pull is more than 6 hours later. Each night is filed under `CRTDB.tattle.season` when it starts (`night.season`; older nights count as "Season 1"). History's Season dropdown is All seasons (every saved night) or Current night (the running night, else the last saved one), and the Mechanic dropdown can narrow `Tattle.Summary(nights, mechKey)` to one mechanic, which then counts only pulls on that mechanic's boss, matched by the list's optional `encounterID` or by name. Chat posts go through `CRT.RaidReport:Output`. `Tattlebot/Page.lua` is the page, with Tonight, History, Mechanics (a boss dropdown, the list, and adding your own spell IDs) and Settings tabs. See the maintenance skill's `references/tattlebot.md`.

## Timeline

`Timeline/Data.lua` is the store and the recorder, `Timeline/Journal.lua` finds a boss's ability rows, `Timeline/Database.lua` holds the shipped reference texts, `Timeline/Reference.lua` reads and keeps reference timelines, `Timeline/Lanes.lua` builds the lanes, `Timeline/View.lua` draws a pull or a reference, `Timeline/ReferencePage.lua` is the References tab and the Recent pulls list, and `Timeline/Page.lua` is the page, with Review, References and Settings tabs. They load in that order (Data, Journal, Database, Reference, Lanes, View, ReferencePage, Page) after Tattlebot, and `Dev/TimelineProbe.lua` loads last inside the `.toc`'s do-not-package block. The pulls live in `CRTDB.timeline` (defaults in `Core.lua`, so profiles carry it): `bosses[encounterID] = { name, pulls = { newest last } }`, where a pull is `{ id, encounterID, name, difficultyID, startedAt, length, kill, casts = { { t, dur, spellID or 0 } }, deaths = { { t, name, class, role, recapID, spellID or 0 } } }` with times in seconds from the pull start, rounded to 0.1. Alongside it are `rows[encounterID] = { hidden = { [spellID] = true }, custom = { spellID, ... } }` and the settings `record`, `minPull` (15), `keep` (10), `span`, `grid`, `iconSize`, `deathRows`, `roles`, `firstDeaths`, `overlay` (how many pulls), `overlayOn`, `hideEmpty` and `nextId`. `Timeline:SavePull` numbers a pull from `nextId` and drops the oldest past `keep`; `Timeline:Fire` tells the page (through `OnChange` listeners, each in a `pcall`) after any save or delete. Recording works like Tattlebot's read. `ENCOUNTER_START` in a raid instance (with Record on and a readable encounter ID) starts a pull; `ENCOUNTER_TIMELINE_EVENT_ADDED` notes each boss event (source Encounter) with its duration and spell ID, 0 when the spell is secret; `ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED` turns an event into a cast, timed from the pull start, when `C_EncounterTimeline.GetEventState` says Finished, and drops it when Canceled; `_REMOVED` drops it too. `ENCOUNTER_END` ends the pull, and one shorter than `minPull` is dropped. If still in combat the pull waits for `PLAYER_REGEN_ENABLED`; then, `READ_DELAY` (1 second) later, `readDeaths` reads `C_DamageMeter.GetCombatSessionFromType(Current, Deaths)`: for each source its `deathRecapID`, name, `classFilename` and `deathTimeSeconds`, and the role matched from the group by GUID then name. The killing blow is the first readable spell of `C_DeathRecap.GetRecapEvents` (newest first), else the first meter spell with `isDeadly` from `GetCombatSessionSourceFromType`, else 0. A read that meets a secret name or time is tried again every `RETRY_DELAY` (2 seconds) up to `RETRIES` (5) times, and then saves what it has (a death with no time is listed as "time unknown"). The meter's current session turns into the next fight's when combat starts, so `PLAYER_REGEN_DISABLED` and a new `ENCOUNTER_START` save any pull still waiting at once, with the deaths of its last completed read. A `/reload` mid-pull loses that pull. Secret-value rules: every game call is in a `pcall`, and every value goes through `readable(v)` (`issecretvalue`) before it is compared, tested, added up, counted or used as a key; a secret spell ID records the cast as unnamed (0). `Journal:Rows(encounterID)` walks the boss's Encounter Journal sections (`EJ_GetInstanceForMap`, else `EJ_GetInstanceByIndex` over the current tier, `EJ_SelectInstance`, `EJ_GetEncounterInfoByIndex`, the dungeon encounter ID in the seventh return of `EJ_GetEncounterInfo`, `C_EncounterJournal.GetSectionInfo`), keeps each spell once, then adds your own rows. It runs only out of combat with the Journal window closed, puts back the selected instance, caches by boss, and remembers a miss until the zone changes. `Lanes.Build(base, rows, settings, encounterID, overlay)` builds the deaths row(s), the ability rows and a "Boss casts (unnamed)" row (only when it has casts) for a pull, and returns the lanes, the deaths with no time, and `extra` (`phases`, `length`, `endLine`); the deaths overlay uses `Timeline:RecentDeaths(encounterID, count, fromID)`. The page registers as `timeline` in `UI.MENU_GROUPS`, and `Slash.lua` routes `/crt timeline` to it. `Dev/TimelineProbe.lua` (`CRT.TimelineProbe`) never ships. `/crt dev probe` arms it for the next raid boss pull, and for each timeline, boss cast, meter, recap and Journal field it logs whether the value was secret, readable, missing or an error, when the event fired, at `ENCOUNTER_END` and after combat; the counts go in `CRTDB.dev.probe` and `/crt dev probe show` prints them. See the maintenance skill's `references/timeline.md`.

**Minimize.** `UI:SetMinimized(on)` in `UI/Panel.lua` shrinks the main window to its title bar (26 high), hiding the menu, the content and the template's inset, after pinning its top-left corner so it shrinks upwards. The minimize button (`f.minimizeButton`, a line or a small square drawn with textures, styled by `UI:StyleMinimizeButton` for each look) sits left of Previews, and an invisible `titleBar` button over the title bar moves the window on drag and toggles minimize on double-click. `UI:Show` always restores, so `/crt` restores a minimized window instead of closing it. The state is not saved.

**Pop-out window.** The Review tab's content is built in a frame of its own inside the tab, so Pop out can reparent it into `CowfeeRaidToolsTimelineWindow`, a resizable frame (at least 760 x 360) with a drag header, a `UI.ResetButton`, a size grip and the `timeline` layer. The tab then shows a "Bring it back" note. Closing the window by Dock, its X or Escape reparents the content back. The page's `refresh` also runs while only the window is shown. Size and position are saved in `CRTDB.timeline.popout`, and `/crt timeline pop` calls `CRT.TimelinePopout`.

**Reference timelines.** A reference is a boss's planned cast schedule, written as plain text and parsed by `Reference.Parse(text)` into `{ boss, difficulty, length, encounterID, phases = { { t, label } }, rows = { { name, spellID, color, lead, casts = { { t, dur } } } } }`, or `nil` and a list of `Line N: reason` errors. The text is one line per thing: `Boss:` (required), `Difficulty:`, `Length:`, `Encounter:`, `Phase: [label] time`, and any other line is `Name [spell N] (lead N, color rrggbb): time, time+bar, ...`. A time is `m:ss` or plain seconds; blank lines and `#` lines are skipped; curly apostrophes and stray spaces from pasted text are folded; without `Length:` the length is the last cast plus its bar. Shipped references are `[[ ]]` text blocks in `CRT.TimelineDB.references` (`Timeline/Database.lua`), and your own are saved as `{ id, text }` in `CRTDB.timeline.references` with `nextRef` as the next id (both defaults in `Core.lua`, so profiles carry them; only the text is stored and it is parsed again when needed). `Reference:List()` returns yours first and then the shipped ones as `{ key, ref, own, text }`, the key being `own:<id>` or `ship:<index>`; `Find(key)`, `ForBoss(encounterID, name)` (by encounter ID when the reference has one, else by boss name) and `BossKey(entry, listed)` (the dropdown key of the listed boss it belongs to, else `ref:<name>`) say which belong to which boss; `Add`, `Update` and `Delete` change your own and call `Timeline:Fire()`, and a shipped one cannot be changed. `Label(ref)` is `Reference · Mythic · 9:48`. The page adds a boss that has only a reference to the dropdown by its `ref:` key, and keeps it selected by name when it gains a numeric key. `Lanes.Build` takes `base`, which is a recorded pull, or `{ reference = ref }`: for a reference it builds the deaths lane (from the overlay pull only), one `reference` lane per row in file order, and with an overlay pull a `ticks` lane `Pull N casts` of that pull's cast times; `extra.phases` is the reference's, `extra.length` the longer of the reference and the overlay pull, and `extra.endLine` the overlay pull's length. A row's spell is `Lanes.RowSpell(row, encounterID)`: its `[spell N]`, else the Journal row of the same name (trimmed, any case), else 0; the icon is that Journal row's, else `C_Spell.GetSpellTexture`, else a question mark. A row hidden by spell ID or by name (`rows[encounterID].hiddenNames`) is left out, and `deathRows` is honored for the overlay's deaths. `View` draws `reference` lanes with a bar behind each cast that has a duration, a thin lead line from `t - lead` to the icon, the row name in its color, and red phase lines with their labels; the overlay pull's end is a line. `ReferencePage.Build` is the References tab (a paste box with Save and a list of the selected boss's references with Edit, Delete and Copy) and `ReferencePage.Recent` is the Recent pulls list that sets the overlay pull, which is not saved. Journal reads for a reference use the reference's own `Encounter:` when the boss key is a string. Reference icons and spell tooltips depend on the Journal, which is read only out of combat.

## Apply algorithm

`Apply:Start(slots)` runs only for a raid leader or assistant, in a raid, out of combat.

1. Read the raid and match layout names to members (`resolveLayout`).
2. Give every member a target group. Layout players go where the layout says. Everyone else keeps their group if there is room, otherwise takes the first free seat.
3. Take one step at a time. Pick a misplaced player, then either `SetRaidSubgroup` into a group with space or `SwapRaidSubgroup` with someone who does not belong there, preferring the person who wants the first player's group.
4. Wait for `GROUP_ROSTER_UPDATE`, re-read the raid, and take the next step.

Every step puts one more player in the right place and never disturbs a correct player, so it always finishes. Stop conditions are: combat starts, 150 steps, or three 1.5 second timeouts with no roster update. Players in combat are skipped and reported at the end.

## Export format

`CRT1;<name>;<slot1>,<slot2>,...,<slot40>`. The characters `%`, `;` and `,` inside values are written as `%XX`. No pipe character is used because the game treats `|` as an escape code in text. Import also accepts a plain list: one name per row, tab-separated columns use the first non-empty cell, blank rows leave a slot empty, and more than 40 rows is rejected.

## Fonts and layout

`Core.lua` makes six font objects (`CRTFontNormal`, `CRTFontHighlight`, `CRTFontDisable`, `CRTFontSmall`, `CRTFontDisableSmall`, `CRTFontLarge`) by copying Blizzard's fonts and multiplying the size by `CRT.FONT_SCALE`, currently 1.2. All text uses these, so one number changes every font. Layout constants sit at the top of `Page.lua` and `Panel.lua` (`SLOT_W`, `SLOT_H`, `BLOCK_H`, `GRID_TOP`, `RIGHT_W`, `FRAME_W`, `FRAME_H`). Change fonts and sizes together, or text will not fit its slot.
