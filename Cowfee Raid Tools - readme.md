---
type: index
area: wow-addons
status: active
created: 2026-10-12
updated: 2026-10-12
tags: [wow, addon, lua, raids]
---

# Cowfee Raid Tools

A private World of Warcraft raid addon, written from scratch for Alex. Version 0.1.0 does one thing well: save, edit and apply raid group layouts, in a panel with a menu on the left so more pages can be added later.

Related: [[Raids - readme]], [[Cowfee Raid Tools - Architecture]], [[Cowfee Raid Tools - Build and Patch Runbook]], [[Cowfee Raid Tools - GitHub README]] (the repository README), [[Cowfee Raid Tools - Public README]] (CurseForge text and publishing notes), [[2026-10-12 Cowfee Raid Tools clean-room rewrite]]

## Status

| Item | State |
|---|---|
| Version | 0.1.1. First written 2026-10-12, and confirmed loading in game on 2026-10-13 |
| Tested | Loads and renders in the game client (screenshot 2026-10-13: grid, Quick Load, role icon, lit and dim names). Apply, drag and drop, and export and import are still to be tested in a raid |
| Client target | Retail, `## Interface: 120100` (assumed from the other installed addons, confirm with `/dump select(4, GetBuildInfo())`) |
| License | MIT, copyright 2026 Alex. All code is original, see [[2026-10-12 Cowfee Raid Tools clean-room rewrite]]. The `LICENSE` file is in the addon folder |
| Patch support | The `wow-addon-patch-maintenance` skill in `.claude/skills/`: ask Claude to check the addon for a new patch or expansion |
| Next step | Run the first-load test list in [[Cowfee Raid Tools - Build and Patch Runbook]] |

> [!warning] Not under version control
> The only copy is the AddOns folder below, with no Git history and no backup. Set up the repository in the runbook before adding more features.

## Where it lives

The addon folder is `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CowfeeRaidTools`. Saved settings are written by the game to the `CRTDB` variable in `WTF\Account\<account>\SavedVariables\CowfeeRaidTools.lua`.

## Commands

| Command | What it does |
|---|---|
| `/crt` | Opens or closes the main panel on the last page you used |
| `/crt groups` | Opens the panel on the Raid Groups page |
| `/crt help` | Lists the commands |

## What the Raid Groups page does

- **Group grid:** 8 groups of 5 slots. Click a slot to pick a name, drag to move or swap, right-click to clear.
- **Lit and dim names:** names in your current group show bright in class color with a role icon, and names not in the group show dark grey with a muted red border. Solo counts as a group of one.
- **Role icons:** tank, healer or damage, read from the group's assigned roles, with your own spec as the fallback. The last role seen for each name is remembered.
- **Name picker:** type to filter, drawing from the Raid or Guild list (the toggle at the top). Enter accepts the first match, or the exact text you typed.
- **Quick Load:** your saved layouts. Click one to load it into the grid.
- **Rename:** with a layout loaded, the "Editing:" line is an edit box. Type a new name and press Enter or click away. A clash gets a number, like "Mythic Roster (2)".
- **Keep changes:** when on, every edit auto-saves to the selected layout, and the label shows an asterisk while edits are unsaved.
- **Save current roster as new:** saves the grid under a name. Delete needs two clicks.
- **Set current roster and Clear grid:** the first fills the grid from your live group, the second empties it.
- **Export and Import:** a `CRT1;` text string, or a plain list of names pasted from a spreadsheet, one per line, row 1 is slot 1.
- **Apply groups:** moves the raid into the grid's layout, one move at a time. It needs raid leader or assist, it skips players in combat, and it lists anyone in the layout who isn't in the raid.

## Using it

1. Open `/crt groups` and fill the grid by picking names, pasting a list, or pressing Set current roster.
2. Press Save current roster as new and name it. It appears in Quick Load.
3. On raid night, load the layout, check who is dim, then press Apply groups as leader or assist.
4. Edit freely. With Keep changes on, the saved layout updates as you go.

## Known limits

- Role icons only appear for players the group has a role for. Other players show no icon until one is assigned.
- Names you pick from the Guild list have no role until you have seen that player in a group.
- Apply cannot move players who are in combat, and it stops if you enter combat.
- Split roster is not built.
- Export strings are not compatible with any other addon.

## Roadmap

The backlog lives in the runbook so it sits next to the build steps. See the Backlog section of [[Cowfee Raid Tools - Build and Patch Runbook]].
