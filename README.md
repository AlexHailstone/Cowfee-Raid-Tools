<h1 align="center">Cowfee Raid Tools</h1>

<p align="center">
  <strong>Raid groups, ready checks, raid notes, debuffs, a late tracker and Tattlebot, in one panel.</strong>
</p>

<p align="center">
  <strong>Game version</strong> <code>12.1.5</code> &nbsp;&nbsp;·&nbsp;&nbsp; <strong>Addon version</strong> <code>0.14.3</code> &nbsp;&nbsp;·&nbsp;&nbsp; <strong>License</strong> <code>MIT</code>
</p>

<!-- Add a screenshot taken with dummy names, then uncomment:
<p align="center"><img src="docs/raid-groups.png" alt="The Raid Groups page" width="720"></p>
-->

Cowfee Raid Tools is a World of Warcraft addon for raid leaders, officers and raiders. Type `/crt` to open one panel with a page for each tool.

> [!NOTE]
> **Beta.** Raid Groups has been used in its author's raids. The other pages (Ready Check, Debuffs, Raid Notes, Late Tracker, Tattlebot) are new and have not been tested in a live raid yet. Applying a layout moves real players, so try it on a small group first, and please report anything odd.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Raid Groups](#raid-groups)
- [Ready Check](#ready-check)
- [Debuffs](#debuffs)
- [Raid Notes](#raid-notes)
- [Late Tracker](#late-tracker)
- [Tattlebot](#tattlebot)
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
| **Quality of Life** | Small conveniences: an experimental LOW HEALTH banner at or under a health percent you set with a slider. A low-health sound is a work in progress and switched off for now |
| **Addon Settings** | Settings for the whole addon: the window scale (50% to 200%, also Ctrl + mouse wheel over the panel), the game's window style or minimal black, background opacity, the font, outline and text size of all the addon's text (the note windows included, after a confirmation, with fonts other addons share through LibSharedMedia when one is installed), which layer each window is drawn in, and the sound channel the addon's sounds play through |
| **Late Tracker** | Raid days and a start time. Anyone expected who is not in the group gets a running clock until they join, and every night is kept in a history with totals |
| **Tattlebot** | After each boss pull, reads the game's damage meter and reports who took damage from a built-in list of boss mechanics, per pull and per night, with how many pulls each player was hit in. Posts to chat and exports for Discord |

**Previews**, in the top right of the panel, shows every movable window at once so you can drag them into place. Positions are saved per character.

## Installation

1. Download `CowfeeRaidTools-<version>.zip` from the [latest release](../../releases/latest) and unzip it.
2. Copy the `CowfeeRaidTools` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
3. Start the game, or type `/reload` if you are already in it.
4. Type `/crt` to open the panel.

The folder name must be exactly `CowfeeRaidTools`, with the `.toc` file directly inside it. Do not use GitHub's green Code button or the "Source code" downloads, which give a folder with the wrong name.

## Quick start

1. Type `/crt` and press **Previews** to place the windows you want.
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

`/crt check` opens the ready check window for your group at any time. **Shift-click a column heading** in it to post who is missing that consumable or buff to raid chat, such as "Mark of the Wild missing: Solex". Raid buffs only get a column when someone in the group can give them, and players whose buffs the game hides are listed as "couldn't check", never as missing.

`/crt readycheck` opens the page, which has three tabs.

- **Window.** A table that opens on a ready check for the raid leader and assistants: every player's ready answer, consumables, raid buffs and durability, for 30 seconds or until you right-click it. Arrange its columns by dragging the headings in the copy on this tab, and click a heading to hide it. Sort players by group, role or name, with a class color bar behind each row. Hover any cell to see the buff and how long it has left, or why it is missing.
- **Your bar.** Five icons above the ready check for your own food, flask, potions, weapon oil and augment rune, with time left or bag count. Food, flask and weapon oil are clickable to use them. Drag items from your bags onto the bar to add your own, and drag the rows to set the icon order and which item is used first. Hover an icon to see the active buff or weapon oil and its time left.
- **Settings.** Run the report automatically on a ready check or a pull timer, choose where it goes, and what counts (flask expiring warning, lower quality flasks). Any food buff counts as fed, whatever was eaten. The automatic report only goes to chat from whoever started the ready check, so it is posted once. Here you also turn your bar on or off, hide it on a ready check you started yourself, and set when it warns that a buff is running low.
- **Ready button lock** (on by default). If your class gives a raid buff and someone in the group is missing it, your Ready button is greyed out until they have it; hover it to see who. Hold Shift and click Ready to ready anyway, and it unlocks by itself after 10 seconds. Players the game can't check never lock you.

Durability and weapon oils in the window only show for players running Cowfee Raid Tools, since each one sends their own: the game never shows addons another player's weapon oil, because oils are weapon enchants, not buffs. Shift-clicking the Dur heading posts everyone under 30%.

## Debuffs

`/crt debuffs`. A movable panel that shows the boss mechanic debuffs on you during combat, using the slots the game provides for them. Choose the icon size and how many to show, and place it with Previews. Under Look, set where the timer text goes (below, above, on the icon, left, right or hidden, with a nudge in pixels), the swipe and its edge, the countdown numbers, the dispel type icon and the border size. The game draws these debuffs itself, so their font, text size and colors can't be changed by any addon.

## Raid Notes

`/crt notes` opens the page, with a **Notes** tab and a **Settings** tab.

**The note format.** Lines of `key:value;` pairs. A timer line looks like `time:34;ph:1;tag:Name;spellid:64843;` or `time:48;ph:1;tag:G1;text:Group 1 go in;dur:8;`. A tag can be a player name, a role (`tank`, `healer`, `dps`, `melee`, `ranged`), a raid group (`G1`, `Group 1`), or `everyone`. A line starting `EncounterID:` names the boss, and an `invitelist:` line becomes a Raid Groups layout. Every other line is assignment text.

- **Share to raid** sends the note to everyone with the addon and makes it the active note for all of them, you included. Raiders who already have that exact note just switch to it, so you can share notes ahead of time and share one again to switch the raid to it. Notes are compressed, so most arrive at once. Only the leader or an assistant can share, and only before the pull, since the game blocks addon messages during a boss fight. Raiders need version 0.13.0 or later to receive notes shared from 0.13.0.
- **Three windows:** the timers, counting down from the pull; the assignments, with your lines marked and names class colored; and your own personal note. Each can be locked so clicks pass through, or unlocked to drag and resize.
- **Show only me** keeps only the timers for your name, role, raid group or everyone.
- **Your alert** shows your next spell or callout before it is due, with the name and countdown centered under each other and the spell icon, two lines tall, to the left, right, above or below. It can read it out with text to speech.
- **Phases.** The first phase starts on the pull. The game gives addons no phase-change signal, so later phases start when someone presses **Next phase** or types `/crt note next`.

## Late Tracker

`/crt late`. The page has three tabs: **Tonight**, **History** and **Settings**. On Settings, tick your raid days and the start time, and pick the Raid Groups layout of who should be there. At the start time, anyone in it who is not in your group gets a running clock until they join, or until the group disbands. **Start raid now** starts a night by hand when invites go out off schedule. Every night is saved to a history with join times, and Totals shows how often each player was late. **Export for Discord** opens the selected totals or night as text to copy and paste into Discord, where the columns line up in a code block.

## Tattlebot

`/crt tattle`. After each boss pull, once you are out of combat, Tattlebot reads the game's own damage meter (Damage Taken) and keeps the damage each player took from the boss mechanics it tracks. A mechanic can have several spell IDs, and they are added together, so each mechanic is one line in the report. The game keeps the meter secret during a fight, so nothing is read until combat ends. The meter has damage per spell but no hit count, so Tattlebot reports each player's damage per mechanic and the number of pulls it hit them in. **Tonight** shows tonight's pulls and totals, **History** keeps every night with totals, and both can post to chat or **Export for Discord**. Totals on Tonight and History, the Discord export and chat posts are all by mechanic, most damage first: a table of Mechanic, Player, Pulls hit and Damage, with each mechanic's name on its first row. Tonight adds up every pull of the night. History has a **Season** filter (**All seasons** or **Current night**, which is tonight's night, or the last one saved when none is running) and a **Mechanic** filter: pick a mechanic and Totals becomes its record, with each player's damage from it, how many pulls on its boss it hit them in, and the average per pull it hit. Nights are also labeled with the season named on **Settings**. **Mechanics** has a boss dropdown that shows the mechanics tracked for each boss with their spell IDs, and **Your own spells**, where you can add spell IDs of your own and name the mechanic they belong to. On **Settings**, Tattlebot can also count everything the game marks as avoidable damage, and post each pull's report on its own (to chat only from the raid leader). The shipped list is in `Tattlebot/Database.lua`, grouped by boss and mechanic. To track more on the fly, pick **Last fight** in the Mechanics dropdown (or type `/crt tattle scan`): it lists every spell that damaged the group in the last fight with a check box, so tick the ones to track and press **Add checked**. They are added for that fight's boss, and spells that share a name become one mechanic. Their damage in that fight counts at once: it is filled in on the pull Tattlebot saved for it, or, if there is none (a fight that wasn't a boss, or a training dummy), the fight is saved as a pull of its own. Tracking starts with the fight you scanned.

## Commands

| Command | What it does |
|---|---|
| `/crt` | Opens or closes the panel |
| `/crt groups` | Raid Groups |
| `/crt readycheck` | Ready Check. `/crt consumables` opens its Your bar tab |
| `/crt check` | Opens the ready check window for your current group, open until you right-click it. Shift-click a heading to post who is missing it |
| `/crt check food` (or `flask`, `rune`, `vantus`, `buffs`, `all`) | Checks the group and shows it to you. Add `chat` to post it, such as `/crt check all chat` |
| `/crt rc` | Shows your ready check bar for 20 seconds, for testing |
| `/crt debuffs` | Debuffs |
| `/crt notes` | Raid Notes. `/crt notes settings` opens its Settings tab |
| `/crt note test`, `/crt note next`, `/crt note stop` | Start the note in use now, start the next phase, stop |
| `/crt late`, `/crt late start`, `/crt late end` | Late Tracker, start tonight's raid now, end it |
| `/crt late export` | The late totals as text to paste into Discord |
| `/crt tattle`, `/crt tattle post`, `/crt tattle night`, `/crt tattle end` | Tattlebot, post the last pull, post tonight's totals, end the night |
| `/crt tattle scan`, `/crt tattle scan text`, `/crt tattle export` | Pick spells to track from the last fight, the same list as plain text, and the Tattlebot totals for Discord |
| `/crt previews` | Toggles the previews, same as the button in the panel |
| `/crt qol` | The Quality of Life page, with the experimental low-health alert |
| `/crt settings` | Addon Settings: window scale and style, background opacity, fonts and layers |
| `/crt lowhp off`, `/crt lowhp on` | Turns the experimental low-health alert off or on |
| `/crt lowhp stop` | Stops any low-health sound the addon is playing |
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
- The built-in consumables list is still being filled in. Until it is, flasks and runes on other players are recognized by their English buff names, so the raid report needs an English game client for those. Food is recognized by its buff, in any language.
- Raid note phases after the first need **Next phase**, and notes must be shared before the pull.
- Potions and healthstones used in a fight, and other players' armor kits, cannot be checked. Other players' weapon oils and durability only show for raiders who run the addon.
- Apply cannot move a player who is in combat.
- Tattlebot reports damage taken, not the number of hits: the game's damage meter does not count hits, and the combat log is closed to addons during boss fights. It reads the meter after each boss pull, so it needs the game's damage meter to be available.

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
  UI/Controls.lua        Edit Mode style dropdowns and sliders shared by the pages
  UI/SettingsPage.lua    the Addon Settings page
  Sounds/                your own low-health sound files (see its README.txt)
  Groups/                Raid Groups: data, Apply, page
  Consumables/           your ready check bar and the consumables list
  ReadyCheck/            the Ready Check page, raid report and ready check window
  Debuffs/               the debuff panel
  Notes/                 raid notes: parser, timers, windows, alert, sharing, page
  Late/                  the Late Tracker
  Tattlebot/             Tattlebot: the mechanics list, the damage meter reading, page
```

- **Releases.** Pushing a tag such as `v0.12.0` runs the GitHub Actions workflow in `.github/workflows/release.yml`, which builds `CowfeeRaidTools-v0.12.0.zip` with the BigWigs packager (`BigWigsMods/packager`) and attaches it to a GitHub release.
- **Saved data.** Everything lives in the `CRTDB` saved variable. New settings are added as defaults in `Core.lua` so existing saved data keeps loading.
- **After a patch.** Update `## Interface:` in the `.toc` to the new number from `/dump select(4, GetBuildInfo())`.

## License

Released under the [MIT License](LICENSE). World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. This addon is not made by or endorsed by Blizzard.
