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

`UI/SettingsPage.lua` is the Addon Settings page, saved in `CRTDB.ui` (and `CRTDB.window.scale`, which moved there from Quality of Life). Fonts: every addon text uses the `CRTFont*` objects made in `Core.lua` (including `CRTFontEdit` for edit boxes, `CRTFontButtonSmall*` and `CRTFontStandard*` at the game's own sizes, and the dropdown and slider template text), and `CRT:ApplyFonts` sets their face, outline and size together. `CRT:FontList` is the game's four fonts plus any shared through LibSharedMedia-3.0 when another addon loaded it (read through `LibStub`, never shipped). Picking a font on Addon Settings asks first in the game's confirmation box, then `CRT:SetAddonFont` sets it for all text and every note window, which redraw through `Notes:Fire`. Fonts are applied again at `PLAYER_LOGIN`, once every addon has registered its shared fonts. Style: `UI:ApplyStyle` hides or shows the `BasicFrameTemplateWithInset` textures and a flat black background, and sets their alpha. Layers: each floating window calls `UI:RegisterLayer(key, frame)` instead of `SetFrameStrata`, with the kinds and defaults in `UI.LAYERS`; `UI:SetLayer` saves a change and applies it, and a protected frame (the consumables bar) waits until combat ends. The boss debuff timers keep the game's own font, because `Blizzard_PrivateAurasUI` draws them with the shared `GameFontNormalSmall` in a protected environment.

## Ready Check

`ReadyCheck/Page.lua` is the Ready Check settings page, with the tabs Window, Your bar and Settings (the automatic report, called On ready check before 0.13.1) (the Raid report tab was removed in 0.13.0, and checking the group now happens in the ready check window, where `Window:PostColumn` posts a shift-clicked column).

Your bar is built by `Consumables/Page.lua` through `CRT.ConsumablesPage.Build`, so the consumables code is unchanged apart from `Consumables:BuffIds`, which hands the report the buff IDs listed or learned for a category. Both lists on Your bar are reordered by dragging rows (`draggable` in `Consumables/Page.lua`, which calls `Consumables:MoveCategoryTo` and `Consumables:MoveItemTo`). The bar's on/off, Not when I start the ready check (`consumables.notStarter`, checked on `READY_CHECK` in `Consumables/Display.lua`) and the warning minutes are on the Settings tab. `ReadyCheck/Report.lua` reads every group member's buffs with `C_UnitAuras.GetAuraDataByIndex`, runs the food, flask, rune, Vantus rune and raid buff checks, and posts or prints the result. It also runs on `READY_CHECK` and `START_PLAYER_COUNTDOWN`, and posts to chat only for whoever started them. Players whose buffs come back secret are reported as couldn't check.

`ReadyCheck/BuffLock.lua` is the Ready button lock (`readycheck.buffLock`, on by default). On `READY_CHECK` it finds your class's raid buffs in `Report.BUFFS`, reads the group with `Report:ReadGroup` and `Report.Cell`, and if anyone readable is missing one it disables the game's `ReadyCheckFrameYesButton` and lays a cover button over it with a tooltip of who is missing what. The cover rechecks after `UNIT_AURA` (at most every 0.25 s, only while locked), unlocks when everyone has the buff, after 10 seconds, or on `READY_CHECK_FINISHED`. While Shift is held it enables the game's button and stops taking the mouse, so the click is the game's own and the addon never answers the ready check itself.

`ReadyCheck/Window.lua` is the ready check window, built on `Report:ReadGroup` and `Report.Cell`, with durability shared over the `CRTReady` addon message prefix. See the maintenance skill's `references/readycheck.md`.

## Debuffs

`Debuffs/Data.lua` holds the settings, `Debuffs/Panel.lua` builds a plain movable frame whose slots are private aura anchors (`C_UnitAuras.AddPrivateAuraAnchor`), which is how the game lets an addon place its boss mechanic debuffs, plus an optional second row using a Blizzard `AuraContainer` for regular debuffs, and `Debuffs/Page.lua` is the settings page. The panel is faded with alpha, not shown or hidden, so combat cannot block it. The container formats are largely undocumented, so each setup call is guarded and `/crt debuffs info` reports what worked. See the maintenance skill's `references/debuffs.md`.

The Look settings (`swipe`, `swipeEdge`, `countdownNumbers`, `timerPosition`, `timerX`, `timerY`, `borderScale`) are passed straight into each anchor's arguments: `showCooldownFrame`, `showCooldownEdge`, `showCountdownNumbers`, `iconInfo.borderScale`, and `durationAnchor`, which is left out when the timer is hidden. `Debuffs:TimerAnchor` turns a position into anchor points. The anchors are rebuilt out of combat whenever any of these change, the preview tiles draw the same choices with a live Cooldown swipe, and the regular row's swipes follow them too.

## Raid notes

`Notes/Parse.lua` reads the note text into timers, phases, free text and an invite list. `Notes/Data.lua` stores notes in `CRTDB.notes`, caches spell names and icons out of combat, and turns an invite list into a Raid Groups layout. `Notes/Engine.lua` starts the timers on `ENCOUNTER_START` (or a test run), starts later phases on Next phase, and decides which lines are yours by name or role. `Notes/Window.lua` builds three windows from one design (timers, assignments, personal note), each lockable and resizable by hand, `Notes/Page.lua` is the Raid Notes page with a Notes tab and a Settings tab, `Notes/Settings.lua` builds the Settings tab (the windows, your alert and sharing), `Notes/Alert.lua` is the personal alert, and `Notes/Comm.lua` shares a note in parts over addon messages. See the maintenance skill's `references/notes.md`.

## Late tracker

`Late/Data.lua` keeps the schedule and the expected Raid Groups layout in `CRTDB.late`, starts a raid night from the schedule (a 5-second ticker) or from Start raid now, marks players as joined on `GROUP_ROSTER_UPDATE`, ends the night when the group disbands, on End raid or after 8 hours, and adds up the totals. `Late/Page.lua` is the Late Tracker page. The running night is stored in saved variables, so a reload does not lose it. See the maintenance skill's `references/late.md`.

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
