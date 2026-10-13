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
