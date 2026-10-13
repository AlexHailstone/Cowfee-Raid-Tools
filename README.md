<h1 align="center">Cowfee Raid Tools</h1>

<p align="center">
  <strong>Plan your raid groups once, save them, and apply them with one click.</strong>
</p>

<p align="center">
  World of Warcraft Retail &nbsp;·&nbsp; Interface 120100 &nbsp;·&nbsp; Version 0.1.1 &nbsp;·&nbsp; MIT License
</p>

<!-- Add a screenshot taken with dummy names, then uncomment:
<p align="center"><img src="docs/raid-groups.png" alt="The Raid Groups page" width="720"></p>
-->

<img width="1079" height="936" alt="{E25B4934-0893-4D80-8215-5D491909EE3B}" src="https://github.com/user-attachments/assets/c858952a-aef5-4fa2-a6ab-eec86204b1eb" />
<img width="1049" height="921" alt="{205BF2AF-6756-44AC-A621-8BF74F923280}" src="https://github.com/user-attachments/assets/4819d0ea-ffbe-4e57-bb5d-eb6a8fc1d0af" />


Cowfee Raid Tools is a World of Warcraft addon for raid leaders and officers. It gives you a panel where you build a layout of 8 groups with 5 slots each, save it under a name, edit it whenever you like, and move your raid into it when you are ready.

> [!NOTE]
> **Beta.** This is an early version and has had little testing outside its author's own raids. Applying a layout moves real players, so try it on a small group first and report anything odd.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [The Raid Groups page](#the-raid-groups-page)
- [Import and export](#import-and-export)
- [How Apply works](#how-apply-works)
- [Commands](#commands)
- [FAQ](#faq)
- [Known limitations](#known-limitations)
- [Reporting a problem](#reporting-a-problem)
- [Development](#development)
- [License](#license)

## Features

- **Save as many layouts as you like.** "Heroic main", "Alt night", "Mythic 4/2". Load any of them from the Quick Load list.
- **Edit any time.** Click a slot to pick a name, drag to move or swap, right-click to clear. You do not need to be in a raid to edit.
- **Auto-save.** With *Keep changes* on, every edit is saved to the layout you have loaded.
- **Rename in place.** With a layout loaded, its name at the top is an edit box.
- **See who is here.** Names in your group are bright and class colored. Names that are not are dark grey with a muted red border.
- **Role icons.** Tank, healer and damage icons next to each name, remembered for players who are not in the group right now.
- **Pick from your raid or your guild**, or type any name.
- **Apply to the live raid** with one button, one safe move at a time.
- **Import and export.** Share a layout as a text string, or paste a column of names straight from a spreadsheet.
- **Readable.** All text is scaled up 20 percent.

## Installation

1. Download the latest release and unzip it.
2. Copy the `CowfeeRaidTools` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
3. Start the game, or type `/reload` if you are already in it.
4. Type `/crt` to open the panel.

The folder name must be exactly `CowfeeRaidTools`, with the `.toc` file directly inside it.

## Quick start

1. Type `/crt groups` to open the Raid Groups page.
2. Fill the grid. Pick names from the list, press **Set current roster** to copy your live group, or press **Import** to paste a list.
3. Press **Save current roster as new** and give the layout a name. It appears under **Quick Load**.
4. On raid night, load the layout, check who is dimmed, then press **Apply groups**. You need to be the raid leader or an assistant.

## The Raid Groups page

```
  Group 1               Group 2                 Quick Load
  [tank]  Name-Realm    [heal]  Name-Realm      > Mythic Roster
  [dps]   Name-Realm    [dps]   Name-Realm        Heroic Main
  [dps]   Name-Realm    [dps]   Name-Realm        Alt Night
  ...                   ...
  Group 3               Group 4                 [x] Keep changes
  ...                   ...                     [ Save current roster as new ]
                                                [ Delete layout ]
  [ Set current roster ] [ Clear grid ]         [ Export current groups ]
  [        Apply groups          ]              [ Import ]
```

| You do this | What happens |
|---|---|
| Click a slot | A picker opens. Type to filter your raid or guild, and press Enter to accept the first match or the exact text you typed |
| Drag a name onto another slot | The two names swap, or the name moves into an empty slot |
| Right-click a slot | The slot is cleared |
| Click a layout in Quick Load | It loads into the grid |
| Edit the name at the top | The layout is renamed when you press Enter or click away |
| Press **Set current roster** | The grid fills from your live group, in its current subgroups |
| Press **Clear grid** | The grid empties |

**Bright and dim names.** A name in your current group shows in its class color with a role icon. A name that is not in your group shows dark grey, with a dimmed icon if the addon has seen that player's role before, and a muted red border. If you are solo, you count as a group of one.

**Roles.** Icons come from the roles assigned in your group. Your own role falls back to your current specialization. The addon remembers the last role it saw for each player.

**Pick names from.** The *Raid* and *Guild* switch at the top chooses which list the picker shows. Raid means your current group, and Guild means your guild roster.

## Import and export

**Export** gives you a text string starting with `CRT1;`. Copy it from the box and share it with anyone using the addon. They press **Import** and paste it to add the layout.

**Paste a name list.** You can also paste plain names, one per line. Row 1 becomes slot 1, so rows 1 to 5 fill Group 1, rows 6 to 10 fill Group 2, and so on. This works with a column copied straight from a spreadsheet:

```
Mesmerism
Whitecrow
Rixxie
Cheoeqar
Abu
Crazyio
Dots
```

- A blank row leaves that slot empty, so you can leave gaps for benched players.
- If you copy several columns, the first non-empty cell on each row is used as the name.
- Names with no realm are treated as your own realm. A raid member with that name from another realm is still matched if there is only one.
- Up to 40 rows are accepted, and a repeated name is only used once.

## How Apply works

Apply works out where everyone should go and moves one player at a time, waiting for the game to confirm each move. It always finishes in a bounded number of moves, and never moves a player who is already in the right place.

- It only runs for the raid leader or an assistant, in a raid, and out of combat.
- Players who are not in the layout keep their group if there is room, and otherwise take the first free seat.
- Players in combat are left where they are, and you are told who could not be moved.
- Names in the layout who are not in the raid are listed.
- It stops if combat starts, or if the game stops accepting moves.

## Commands

| Command | What it does |
|---|---|
| `/crt` | Opens or closes the panel |
| `/crt groups` | Opens the Raid Groups page |
| `/crt help` | Lists the commands |

## FAQ

<details>
<summary><strong>Where are my layouts saved?</strong></summary>

In the game's saved variables: `WTF\Account\<account>\SavedVariables\CowfeeRaidTools.lua`. Back that file up if you want to keep your layouts.

</details>

<details>
<summary><strong>Do other raid members need the addon?</strong></summary>

No. Only the person who applies a layout needs it, and it does not talk to other players' addons.

</details>

<details>
<summary><strong>Does it work with my other raid addons?</strong></summary>

It is standalone and keeps its own data, so it can sit next to them. It does not read their settings.

</details>

<details>
<summary><strong>Why are some names dimmed?</strong></summary>

They are in your layout but not in your current group.

</details>

<details>
<summary><strong>How do I reset everything?</strong></summary>

Close the game and delete `CowfeeRaidTools.lua` from your SavedVariables folder.

</details>

## Known limitations

- A role icon only shows for players the group has assigned a role to. Names picked from the guild list have no icon until you have seen that player in a group.
- Apply cannot move a player who is in combat.
- Export strings only work with this addon.
- There is no Split roster feature yet.

## Reporting a problem

Please open an issue and include what you did, what you expected, and the exact error text if there is one. To see Lua errors, type `/console scriptErrors 1` and `/reload`. Include your game version, from `/dump select(4, GetBuildInfo())`.

## Development

The addon is plain Lua with no bundled libraries.

```
CowfeeRaidTools/
  CowfeeRaidTools.toc    title, version, interface number, saved variable
  Core.lua               namespace, saved data defaults, scaled fonts
  Slash.lua              the /crt command
  UI/Panel.lua           main window, left menu, page registry
  Groups/Data.lua        names, rosters, roles, layouts, import and export
  Groups/Apply.lua       moves the live raid into a layout
  Groups/Page.lua        the Raid Groups page
```

- **Adding a page.** Create a file that builds its frame and calls `CRT.UI:RegisterPage(key, title, builder)`, then add it to the `.toc`. The panel adds the menu entry for you.
- **Saved data.** Everything lives in the `CRTDB` saved variable. New settings are added as defaults in `Core.lua` so existing saved data keeps loading.
- **Syntax check.** There is no Lua runtime outside the game, so a syntax check with the `luaparse` package catches typos before a `/reload`. Runtime errors still need the game, with `/console scriptErrors 1`.
- **After a patch.** Update `## Interface:` in the `.toc` to the new number from `/dump select(4, GetBuildInfo())`, then test the page and Apply on a small group.

## License

Released under the [MIT License](LICENSE). World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. This addon is not made by or endorsed by Blizzard.
