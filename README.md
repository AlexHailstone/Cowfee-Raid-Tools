<h1 align="center">Cowfee Raid Tools</h1>

<p align="center">
  <strong>Raid groups, ready checks, raid notes, debuffs and a late tracker, in one panel.</strong>
</p>

<p align="center">
  <strong>Game version</strong> <code>12.1.5</code> &nbsp;&nbsp;·&nbsp;&nbsp; <strong>Addon version</strong> <code>0.13.0</code> &nbsp;&nbsp;·&nbsp;&nbsp; <strong>License</strong> <code>MIT</code>
</p>

<!-- Add a screenshot taken with dummy names, then uncomment:
<p align="center"><img src="docs/raid-groups.png" alt="The Raid Groups page" width="720"></p>
-->

Cowfee Raid Tools is a World of Warcraft addon for raid leaders, officers and raiders. Type `/crt` to open one panel with a page for each tool.

> [!NOTE]
> **Beta.** Raid Groups has been used in its author's raids. The other pages (Ready Check, Debuffs, Raid Notes, Late Tracker) are new and have not been tested in a live raid yet. Applying a layout moves real players, so try it on a small group first, and please report anything odd.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Raid Groups](#raid-groups)
- [Ready Check](#ready-check)
- [Debuffs](#debuffs)
- [Raid Notes](#raid-notes)
- [Late Tracker](#late-tracker)
- [Commands](#commands)
- [FAQ](#faq)
- [Known limitations](#known-limitations)
- [Reporting a problem](#reporting-a-problem)
- [Development](#development)
- [License](#license)

## Features

| Page | What it does |
|---|---|
| **Raid Groups** | Save raid layouts of 8 groups, edit them any time, and move the live raid into one with a click. Import a layout string or a pasted column of names |
| **Ready Check** | Your own consumables bar on every ready check. A raid report of everyone's food, flask, augment rune, Vantus rune and the raid buffs your group can give, shown to you or posted to chat. A ready check window for leaders with every player's answer, consumables, buffs and durability |
| **Debuffs** | A movable panel for the boss mechanic debuffs on you in combat |
| **Raid Notes** | Notes per boss with timers that count down from the pull, shared by the raid leader. Windows for the timers, the assignments and your own personal note, a personal alert for your next spell with text to speech, and a "show only me" filter |
| **Late Tracker** | Raid days and a start time. Anyone expected who is not in the group gets a running clock until they join, and every night is kept in a history with totals |

**Toggle previews**, in the top right of the panel, shows every movable window at once so you can drag them into place. Positions are saved per character.

## Installation

1. Download `CowfeeRaidTools-<version>.zip` from the [latest release](../../releases/latest) and unzip it.
2. Copy the `CowfeeRaidTools` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
3. Start the game, or type `/reload` if you are already in it.
4. Type `/crt` to open the panel.

The folder name must be exactly `CowfeeRaidTools`, with the `.toc` file directly inside it. Do not use GitHub's green Code button or the "Source code" downloads, which give a folder with the wrong name.

## Quick start

1. Type `/crt` and press **Toggle previews** to place the windows you want.
2. Raid leaders: build and save your layouts on **Raid Groups**, and import the night's notes on **Raid Notes**, then press **Share to raid** before the pull.
3. Everyone: the Ready Check bar, the debuff panel and the raid note windows work on their own once placed.

## Raid Groups

Build a layout of 8 groups with 5 slots each, save it under a name, edit it whenever you like, and move your raid into it when you are ready.

| You do this | What happens |
|---|---|
| Click a slot | A picker opens. Type to filter your raid or guild, and press Enter to accept the first match or the exact text you typed |
| Drag a name onto another slot | The two names swap, or the name moves into an empty slot |
| Right-click a slot | The slot is cleared |
| Click a layout in Quick Load | It loads into the grid |
| Edit the name at the top | The layout is renamed when you press Enter or click away |
| Press **Set current roster** | The grid fills from your live group, in its current subgroups, after asking if the grid has names |
| Press **Clear grid** | The grid empties |
| Press **Apply groups** | The raid is moved into the layout, one move at a time. Leader or assistant only, out of combat |

**Bright and dim names.** A name in your current group shows in its class color with a role icon. A name that is not shows dark grey with a muted red border.

**Import and export.** Export gives a `CRT1;` string to share with anyone using the addon. Import also takes plain names, one per line, such as a column copied from a spreadsheet: rows 1 to 5 fill Group 1, rows 6 to 10 Group 2, and a blank row leaves a slot empty.

**How Apply works.** It moves one player at a time and waits for the game to confirm each move. Players not in the layout keep their group if there is room. Players in combat are skipped and listed, and so are names in the layout who are not in the raid. It stops if combat starts.

## Ready Check

`/crt readycheck` opens the page, which has four tabs.

- **Raid report.** Check the group's food, flask, augment rune, Vantus rune and raid buffs. **Check** shows the result only to you, **Post to chat** sends it to the raid. Raid buffs are only checked when someone in the group can give them. Players whose buffs the game hides are listed as "couldn't check", never as missing.
- **On ready check.** Run the report automatically on a ready check or a pull timer, choose where it goes, and what counts (best food only, flask expiring warning). The automatic report only goes to chat from whoever started the ready check, so it is posted once.
- **Window.** A table that opens on a ready check for the raid leader and assistants: every player's ready answer, consumables, raid buffs and durability, for 30 seconds or until you right-click it. Arrange its columns by dragging the headings in the copy on this tab, and click a heading to hide it. Sort players by group, role or name, with a class color bar behind each row.
- **Your bar.** Five icons above the ready check for your own food, flask, potions, weapon oil and augment rune, with time left or bag count. Food, flask and weapon oil are clickable to use them. Drag items from your bags onto the bar to add your own.

Durability in the window only shows for players running Cowfee Raid Tools, since each one sends their own. `/crt check` opens the window for your group at any time, with no timer.

## Debuffs

`/crt debuffs`. A movable panel that shows the boss mechanic debuffs on you during combat, using the slots the game provides for them. Choose the icon size and how many to show, and place it with Toggle previews.

## Raid Notes

`/crt notes` opens the page, with a **Notes** tab and a **Settings** tab.

**The note format.** Lines of `key:value;` pairs. A timer line looks like `time:34;ph:1;tag:Name;spellid:64843;` or `time:48;ph:1;tag:G1;text:Group 1 go in;dur:8;`. A tag can be a player name, a role (`tank`, `healer`, `dps`, `melee`, `ranged`), a raid group (`G1`, `Group 1`), or `everyone`. A line starting `EncounterID:` names the boss, and an `invitelist:` line becomes a Raid Groups layout. Every other line is assignment text.

- **Share to raid** sends the note to everyone with the addon. Notes are compressed, so most arrive at once. Only the leader or an assistant can share, and only before the pull, since the game blocks addon messages during a boss fight. Raiders need version 0.13.0 or later to receive notes shared from 0.13.0.
- **Three windows:** the timers, counting down from the pull; the assignments, with your lines marked and names class colored; and your own personal note. Each can be locked so clicks pass through, or unlocked to drag and resize.
- **Show only me** keeps only the timers for your name, role, raid group or everyone.
- **Your alert** shows your next spell or callout before it is due, and can read it out with text to speech.
- **Phases.** The first phase starts on the pull. The game gives addons no phase-change signal, so later phases start when someone presses **Next phase** or types `/crt note next`.

## Late Tracker

`/crt late`. Tick your raid days and the start time, and pick the Raid Groups layout of who should be there. At the start time, anyone in it who is not in your group gets a running clock until they join, or until the group disbands. **Start raid now** starts a night by hand when invites go out off schedule. Every night is saved to a history with join times, and Totals shows how often each player was late. **Export for Discord** opens the selected totals or night as text to copy and paste into Discord, where the columns line up in a code block.

## Commands

| Command | What it does |
|---|---|
| `/crt` | Opens or closes the panel |
| `/crt groups` | Raid Groups |
| `/crt readycheck` | Ready Check. `/crt consumables` opens its Your bar tab |
| `/crt check` | Opens the ready check window for your current group, open until you right-click it |
| `/crt check food` (or `flask`, `rune`, `vantus`, `buffs`, `all`) | Checks the group and shows it to you. Add `chat` to post it, such as `/crt check all chat` |
| `/crt rc` | Shows your ready check bar for 20 seconds, for testing |
| `/crt debuffs` | Debuffs |
| `/crt notes` | Raid Notes. `/crt notes settings` opens its Settings tab |
| `/crt note test`, `/crt note next`, `/crt note stop` | Start the note in use now, start the next phase, stop |
| `/crt late`, `/crt late start`, `/crt late end` | Late Tracker, start tonight's raid now, end it |
| `/crt late export` | The late totals as text to paste into Discord |
| `/crt previews` | Toggles the previews, same as the button in the panel |
| `/crt perf` | Shows the addon's CPU use since the last `/reload`, from the game's profiler |
| `/crt help` | Lists the commands |

## FAQ

<details>
<summary><strong>Where are my settings saved?</strong></summary>

In the game's saved variables: `WTF\Account\<account>\SavedVariables\CowfeeRaidTools.lua`. Back that file up if you want to keep your layouts, notes and late history.

</details>

<details>
<summary><strong>Do other raid members need the addon?</strong></summary>

Not for Raid Groups, the raid report or the Late Tracker. Raiders need it to receive shared raid notes, to get the note windows and alert, and for their durability to show in the ready check window.

</details>

<details>
<summary><strong>Does it work with my other raid addons?</strong></summary>

It is standalone, keeps its own data and has no bundled libraries, so it can sit next to them.

</details>

<details>
<summary><strong>How do I reset everything?</strong></summary>

Close the game and delete `CowfeeRaidTools.lua` from your SavedVariables folder.

</details>

## Known limitations

- During combat and boss fights the game hides many values from addons. The raid report and ready check window list players they cannot read as "couldn't check", and it is not yet confirmed whether other players' buffs can be read inside a raid instance.
- The built-in consumables list is still being filled in. Until it is, food, flasks and runes on other players are recognized by their English buff names, so the raid report needs an English game client.
- Raid note phases after the first need **Next phase**, and notes must be shared before the pull.
- Potions and healthstones used in a fight, and other players' weapon oils and armor kits, cannot be checked.
- Apply cannot move a player who is in combat.

## Reporting a problem

Please open an issue and include what you did, what you expected, and the exact error text if there is one. To see Lua errors, type `/console scriptErrors 1` and `/reload`. Include your game version, from `/dump select(4, GetBuildInfo())`, and the addon version from `/crt help`.

## Development

The addon is plain Lua with no bundled libraries.

```
CowfeeRaidTools/
  CowfeeRaidTools.toc    title, version, interface number, saved variable
  Core.lua               namespace, saved data defaults, scaled fonts
  Slash.lua              the /crt command
  UI/Panel.lua           main window, left menu, page registry, previews
  Groups/                Raid Groups: data, Apply, page
  Consumables/           your ready check bar and the consumables list
  ReadyCheck/            the Ready Check page, raid report and ready check window
  Debuffs/               the debuff panel
  Notes/                 raid notes: parser, timers, windows, alert, sharing, page
  Late/                  the Late Tracker
```

- **Releases.** Pushing a tag such as `v0.12.0` runs the GitHub Actions workflow in `.github/workflows/release.yml`, which builds `CowfeeRaidTools-v0.12.0.zip` with the BigWigs packager (`BigWigsMods/packager`) and attaches it to a GitHub release.
- **Saved data.** Everything lives in the `CRTDB` saved variable. New settings are added as defaults in `Core.lua` so existing saved data keeps loading.
- **After a patch.** Update `## Interface:` in the `.toc` to the new number from `/dump select(4, GetBuildInfo())`.

## License

Released under the [MIT License](LICENSE). World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. This addon is not made by or endorsed by Blizzard.
