---
type: reference
area: wow-addons
status: draft
created: 2026-10-13
updated: 2026-10-13
tags: [wow, addon, publishing, readme]
---

# Cowfee Raid Tools: public README

The text for GitHub (`README.md`) and the CurseForge project page. Copy only the part under "Publishable README" below. Everything above it is private notes for you. Keep this note in step with the addon: the `wow-addon-patch-maintenance` skill updates it, and the facts come from [[Cowfee Raid Tools - readme]] and [[Cowfee Raid Tools - Architecture]].

Related: [[Cowfee Raid Tools - Build and Patch Runbook]], [[2026-10-12 Cowfee Raid Tools clean-room rewrite]]

## Before you publish

- [ ] Test Apply, drag and drop, and export and import in a real raid. The README is honest that it is a beta, but do not post it before the main features have worked once.
- [ ] Pick a license and add a `LICENSE` file to the addon folder. The code is all original, so the choice is yours. A permissive one such as MIT lets others reuse it, and "All Rights Reserved" keeps it closed. The README says "see the LICENSE file", so it must exist before you post.
- [ ] Take new screenshots with dummy names. The one from 2026-10-13 shows real guild member names, so do not post it as is.
- [ ] Put the addon under Git first, because the packager needs a repository. See the version control section of [[Cowfee Raid Tools - Build and Patch Runbook]].
- [ ] Choose where bug reports go and say so in the README. CurseForge strongly recommends a support channel, and a GitHub issue tracker is the easiest.
- [ ] Preview the description on CurseForge before saving. The README is mostly headings and lists so it should render on both sites, but CurseForge's Markdown support was not confirmed.
- [ ] Confirm the `## Interface:` number in the `.toc` against `/dump select(4, GetBuildInfo())`, and update the Compatibility line below.

> [!warning] Do not publish with a placeholder
> Anything in the publishable text that says "TBD" or points to a file that does not exist should be fixed first.

## Publishing notes

These are from pages that were opened on 2026-10-13. CurseForge's [project page guidelines](https://support.curseforge.com/support/solutions/articles/9000197279) ask for a description that explains what the project does in functional detail, a separate one-sentence summary that does not repeat the description, a name in English without the game name, class names or version numbers, and an avatar of 400 by 400 pixels that is not .webp because of a known bug. Third-party content must be allowed by its license, which does not apply here because no libraries are bundled.

The [BigWigs packager](https://github.com/BigWigsMods/packager) builds the zip from a Git checkout and can upload it to CurseForge, WoWInterface, Wago and GitHub. It expects tags named for versions, builds the changelog from commits since the previous tag, and reads the IDs from `## X-Curse-Project-ID`, `## X-WoWI-ID` and `## X-Wago-ID` in the `.toc`. Add those lines after the project exists on each site. Its README points to the wiki for a GitHub Actions workflow.

CurseForge summary, to paste into the summary field (it is one sentence and does not repeat the description):

```text
Save, edit and apply raid group layouts from a clean in-game panel, with role icons and spreadsheet import.
```

## Publishable README

Everything from the line below to the end of the note is the public text.

---

# Cowfee Raid Tools

Plan your raid groups once, save them, and apply them with one click.

Cowfee Raid Tools is a World of Warcraft addon for raid leaders and officers. It gives you a panel where you build a layout of 8 groups with 5 slots each, save it under a name, edit it later, and move your raid into it when you are ready.

> **Beta.** This is an early version and has had little testing outside its author's own raids. Applying a layout moves real players, so try it on a small group first and report anything odd.

## Features

- **Save and reload layouts.** Keep as many named layouts as you like, such as "Heroic main" or "Alt night", and load them from the Quick Load list.
- **Edit any time.** Click a slot to pick a name, drag a name to move or swap it, and right-click to clear a slot. You do not need to be in a raid to edit.
- **Auto-save.** With Keep changes on, every edit is saved to the layout you have loaded.
- **Rename.** With a layout loaded, the name at the top is an edit box. Type a new name and press Enter.
- **See who is here.** Names in your current group show bright in class color with a role icon. Names that are not in your group show dark grey with a muted red border, so gaps are easy to spot. If you are solo, you count as a group of one.
- **Role icons.** Tank, healer and damage icons come from the roles assigned in your group. The addon remembers the last role it saw for each player, so benched players keep their icon.
- **Pick names from your raid or your guild.** Type to filter the list, or type any name and press Enter.
- **Apply to the live raid.** One button moves everyone into the layout, one move at a time. Players who are not in the layout keep their place if there is room.
- **Import and export.** Share a layout as a short text string, or paste a column of names straight from a spreadsheet.
- **Larger text.** All text is scaled up for readability.

## Installation

1. Download the latest release and unzip it.
2. Copy the `CowfeeRaidTools` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
3. Start the game, or type `/reload` if you are already in it.
4. Type `/crt` to open the panel.

## Quick start

1. Type `/crt groups` to open the Raid Groups page.
2. Fill the grid. Pick names from the list, press Set current roster to copy your live group, or use Import to paste a list.
3. Press Save current roster as new and give the layout a name. It appears under Quick Load.
4. On raid night, load the layout, check who is dimmed, then press Apply groups. You need to be the raid leader or an assistant.

## Commands

- `/crt` opens or closes the panel.
- `/crt groups` opens the Raid Groups page.
- `/crt help` lists the commands.

## Import and export

**Export** gives you a text string starting with `CRT1;`. Copy it from the box and share it with anyone using the addon. Press Import and paste it to add the layout.

**Paste a name list.** You can also paste plain names, one per line, into Import. Row 1 becomes slot 1, so rows 1 to 5 fill Group 1, rows 6 to 10 fill Group 2, and so on. This works with a column copied straight from a spreadsheet:

- A blank row leaves that slot empty.
- If you copy several columns, the first non-empty cell on each row is used as the name.
- Names with no realm are treated as your own realm. A raid member with that name from another realm is still matched if there is only one.
- Up to 40 rows are accepted, and a repeated name is only used once.

## How Apply works

Apply works out where everyone should go and moves one player at a time, waiting for the game to confirm each move. It will:

- Only run for the raid leader or an assistant, in a raid, and out of combat.
- Leave players in combat where they are, and tell you who it could not move.
- Tell you which names in the layout are not in the raid.
- Stop if combat starts.

## Known limitations

- A role icon only shows for players the group has a role for. Names picked from the guild list have no icon until you have seen that player in a group.
- Apply cannot move a player who is in combat.
- Export strings only work with this addon.
- There is no Split roster feature yet.

## Compatibility

Retail World of Warcraft, interface 120100. The addon keeps its own data and does not depend on any other addon, and it does not talk to other players' addons.

## FAQ

**Where are my layouts saved?** In the game's saved variables, in `WTF\Account\<account>\SavedVariables\CowfeeRaidTools.lua`. Back that file up if you want to keep your layouts.

**Do other raid members need the addon?** No. Only the person who applies a layout needs it.

**Does it work with my other raid addons?** It is standalone and uses its own saved data, so it can sit next to them. It does not read their settings.

**Why are some names dimmed?** They are in your layout but not in your current group.

**How do I reset everything?** Close the game and delete `CowfeeRaidTools.lua` from your SavedVariables folder.

## Reporting a problem

Please include what you did, what you expected, and the exact error text if there is one. To see Lua errors, type `/console scriptErrors 1` and `/reload`. Include your game version, from `/dump select(4, GetBuildInfo())`.

## Credits and license

Written by Alex. All code is original, and no third-party libraries are bundled. See the `LICENSE` file for the license.

World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. This addon is not made by or endorsed by Blizzard.

## Changelog

### 0.1.1

- Rename a saved layout from the edit box at the top of the Raid Groups page.

### 0.1.0

- First release: the panel with a left menu and the Raid Groups page.
- Save, load, edit, delete and auto-save layouts.
- Apply a layout to a live raid.
- Export and import, including pasting a column of names from a spreadsheet.
- Role icons, bright and dim names, and larger text.
