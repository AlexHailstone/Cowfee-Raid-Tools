---
type: runbook
area: wow-addons
status: active
created: 2026-10-12
updated: 2026-10-12
tags: [wow, addon, lua, patch, maintenance]
---

# Cowfee Raid Tools: build and patch runbook

Everything needed to keep building the addon and to keep it working after game patches. For what the addon does see [[Cowfee Raid Tools - readme]], and for how the code fits together see [[Cowfee Raid Tools - Architecture]].

## First load test

The addon has been syntax-checked but never run in the game. Do this once before adding anything.

- [ ] Turn on Lua errors with `/console scriptErrors 1`, then `/reload`
- [ ] Confirm the addon shows in the AddOns list as not out of date, and `/dump select(4, GetBuildInfo())` matches the `## Interface:` number in the `.toc`
- [ ] `/crt` opens the panel with a left menu and a Raid Groups entry, and the text is readable at the 1.2 scale
- [ ] `/crt groups` opens the Raid Groups page, and the hint line no longer overlaps Groups 7 and 8
- [ ] Solo: your own name shows lit in class color with a role icon after pressing Set current roster
- [ ] Click a slot, type a name, press Enter, and the name appears. Right-click clears it
- [ ] Drag a name onto another slot and the two swap
- [ ] Save current roster as new, `/reload`, and the layout is still in Quick Load
- [ ] Import a pasted column of names from a spreadsheet and check rows 1 to 5 land in Group 1
- [ ] Export, then Import the string back, and the layout round-trips
- [ ] In a raid as leader or assist, press Apply groups on a small test group first and watch for "isn't accepting group moves"

If something errors, the message names the file and line. Common first-load failures are a frame template name that no longer exists, and the role icon texture looking cropped.

## Version control

This folder is the repository: `C:\Users\Alex\OneDrive\Documents\Mythic Lab\projects\WoW Addons\Cowfee Raid Tools`, on branch `main`. It was cloned from GitHub on 2026-10-13, and the addon source was added on top of the notes already in it. The game loads the addon from `...\Interface\AddOns\CowfeeRaidTools`, which is a junction pointing at this folder, so you edit and `/reload` as before.

| Item | Value |
|---|---|
| Repository | This folder, inside the vault |
| Remote | `origin`, `https://github.com/AlexHailstone/Cowfee-Raid-Tools.git` |
| Game path | A junction at `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CowfeeRaidTools` pointing here |
| Identity | The GitHub noreply email `76534423+AlexHailstone@users.noreply.github.com`, set locally on this repo |
| First release | Tag `v0.1.1`, local so far. The packager expects tags named for versions |
| Source of truth for the public README | `README.md` in this folder. Edit it here, not in a copy |
| Older copies | `C:\dev\CowfeeRaidTools` (a separate repo with one commit) and `C:\dev\CowfeeRaidTools-pre-git-backup`. Safe to delete once this setup has worked for a while |

Working rules:

1. Commit after every working change, with a clear message, and bump the version in the `.toc` for anything players would notice.
2. Tag each release, such as `git tag -a v0.1.2 -m "Cowfee Raid Tools 0.1.2"`.
3. Ask before any push, and never use `--force`.
4. Commit addon files and notes separately, so a release does not drag documentation edits with it.

> [!warning] The repository is inside OneDrive
> OneDrive syncing a live `.git` folder can corrupt the repository, usually as missing or half-synced objects. The safest fix is to keep the Git data outside OneDrive while the files stay here, with `git init --separate-git-dir=C:\dev\CowfeeRaidTools.git` run in this folder, which replaces `.git` with a small pointer file. Not done yet, so ask first.

> [!warning] Private notes are in a public repository
> The notes in this folder were committed and are on GitHub, along with the addon. They contain local paths and a pre-publish checklist. If the repository is public, either remove them with `git rm --cached` and a `.gitignore` entry, which stops them going forward but leaves them in history, or move the addon into its own folder. Decide before the next push. Early commits in this repo also carry a personal email address as the author, which cannot be removed without rewriting history.

If the game shows the addon missing, recreate the junction from PowerShell with `New-Item -ItemType Junction -Path "<AddOns path>\CowfeeRaidTools" -Target "<this folder>"` after making sure the AddOns path does not already exist. Removing a junction does not delete the folder it points to.

## Development loop

1. Edit the Lua files in this folder, or through the AddOns junction, which is the same place.
2. Run the syntax check below.
3. `/reload` in the game and read any Lua error.
4. Test the change in the first-load list, in a raid for anything that touches Apply.
5. Commit it.

Lua syntax check without the game: no Lua interpreter is installed on this machine, so use the `luaparse` package from a scratch folder.

```bash
mkdir -p /tmp/crt-lint && cd /tmp/crt-lint && npm init -y && npm install luaparse@0.3.1
```

Save this as `check.js` in that folder and run `node check.js "<addon folder>"`. It prints OK or the file and line of a syntax error. It catches typos and bad syntax, not wrong API names or runtime errors.

```js
const luaparse = require('luaparse');
const fs = require('fs');
const path = require('path');
let bad = 0;
function walk(d) {
  for (const f of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, f.name);
    if (f.isDirectory()) { walk(p); continue; }
    if (!p.endsWith('.lua')) continue;
    try { luaparse.parse(fs.readFileSync(p, 'utf8'), { luaVersion: '5.1' }); console.log('OK  ', f.name); }
    catch (e) { bad++; console.log('FAIL', p, e.message); }
  }
}
walk(process.argv[2]);
process.exit(bad ? 1 : 0);
```

## Adding a new page

Each menu entry is one page in its own folder. Example for a Break Timer page.

1. Create `BreakTimer\Page.lua` with a builder that fills the frame it is given, then registers itself.

```lua
local ADDON, CRT = ...
local UI = CRT.UI

local function build(pf)
    local title = pf:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Break Timer")
    pf:SetScript("OnShow", function() --[[ refresh here ]] end)
end

UI:RegisterPage("breaktimer", "Break Timer", build)
```

2. Add the file to the `.toc` after `UI\Panel.lua`, plus any data or logic files before it.
3. Add its saved settings as defaults in `Core.lua` so existing saved data is filled in on load.
4. Add an `/crt breaktimer` branch in `Slash.lua` that calls `CRT.UI:Show("breaktimer")`.
5. Use the `CRTFont...` objects for every label so the 1.2 scale applies, and keep any logic that does not touch the screen in its own file so it can be tested without a frame.
6. Bump the version in the `.toc`, update [[Cowfee Raid Tools - readme]] and [[Cowfee Raid Tools - Architecture]], and add a line to the Change log below.

## Backlog

| Idea | Notes |
|---|---|
| Split roster | MRT has this next to Set current roster. Splits the raid into parts by a rule, such as role or class. Needs a design first |
| Auto-retry Apply after combat | Today it stops and lists who is in combat, and you press Apply again |
| Spec-based roles for other players | Needs inspect or a spec library, and a license check for any library. Ask first if most of the raid has no assigned role |
| Role-balanced Apply | Put tanks and healers in set groups regardless of the layout |
| Class column from the spreadsheet | The sheet has class colors, so import could read a class column too |
| Font scale slider | Today it is the `CRT.FONT_SCALE` number in `Core.lua` |
| Addon compartment or minimap button | Opens the panel without a command |
| More pages | Reminders, break timer, ready check consumables, interrupt display, nicknames. See the module list in [[2026-10-12 Cowfee Raid Tools clean-room rewrite]] |
| Version control | See the setup section above |

## Patch support

Run this routine whenever the game updates, on the PTR if you want warning, and always after a patch that changes the `## Interface:` number. Ask Claude to use the `wow-addon-patch-maintenance` skill (`.claude/skills/wow-addon-patch-maintenance/`) and it will run these steps, keep the API inventory and the API migrations list up to date, and give you the in-game test list. The tables below are the summary, and the skill's `references/api-inventory.md` is the full, scannable version.

### Every patch

1. Get the new number with `/dump select(4, GetBuildInfo())`. If the addon shows out of date, edit `## Interface:` in `CowfeeRaidTools.toc`. The [TOC format page](https://warcraft.wiki.gg/wiki/The_TOC_Format) allows several numbers on one line, such as `120100, 120105`, so one file can cover two clients.
2. Read that patch's API changes page on the Warcraft Wiki and search it for every API in the table below. The 12.0.5 page, [Patch 12.0.5/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes), shows the layout. Newer patches use the same page name pattern with the patch number.
3. Turn on Lua errors, `/reload`, and click through the first-load test list. A removed API shows as "attempt to call a nil value" with the file and line.
4. Test Apply on a small group, because the group-move calls are the most restricted part.
5. Update the "Last checked" column and the Change log, and bump the version.

> [!warning] Test Apply on a small group first
> A bad Apply on a full raid can shuffle 40 people. A bug here is annoying but not dangerous, so test small, then trust it.

### API checklist

"Checked" means the Warcraft Wiki page was opened and read on 2026-10-12. "Not checked" means the call is standard but its page has not been read yet.

| API | Used for | What was found | State |
|---|---|---|---|
| [SetRaidSubgroup](https://warcraft.wiki.gg/wiki/API_SetRaidSubgroup) | Moving a player into a group with space | Restricted and cannot be called in combat | Checked |
| [SwapRaidSubgroup](https://warcraft.wiki.gg/wiki/API_SwapRaidSubgroup) | Swapping two players | Restricted, not in combat, flagged protected since 4.0.1 | Checked |
| [GetRaidRosterInfo](https://warcraft.wiki.gg/wiki/API_GetRaidRosterInfo) | Raid names and subgroups | Returns name, rank, subgroup, level, class, fileName, then more. The 12th value is combatRole. Cross-realm names include the realm | Checked |
| [UnitGroupRolesAssigned](https://warcraft.wiki.gg/wiki/API_UnitGroupRolesAssigned) | Role icons | Returns TANK, HEALER, DAMAGER or NONE. The page does not say `raidN` tokens work, so confirm in game. May be secret when unit identity is restricted | Checked, confirm in game |
| [GetGuildRosterInfo](https://warcraft.wiki.gg/wiki/API_GetGuildRosterInfo) | Guild name picker | The 11th return is the class file name, which the code reads | Checked |
| [C_GuildInfo.GuildRoster](https://warcraft.wiki.gg/wiki/API_C_GuildInfo.GuildRoster) | Refreshing the guild list | Calls within 10 seconds of the last one are ignored | Checked |
| [GetSpecialization](https://warcraft.wiki.gg/wiki/API_GetSpecialization) | Your own role fallback | The global is deprecated since 11.2.0. The code prefers `C_SpecializationInfo.GetSpecialization` and falls back to the global | Checked |
| [GetSpecializationRole](https://warcraft.wiki.gg/wiki/API_GetSpecializationRole) | Your own role fallback | Returns DAMAGER, TANK or HEALER, or 0 if invalid. Not noted as moved | Checked |
| [UnitAffectingCombat](https://warcraft.wiki.gg/wiki/API_UnitAffectingCombat) | Skipping players in combat | Returns a boolean. The page does not say if it can be secret, so the code guards with `issecretvalue` | Checked |
| `FontString:SetFont` | Scaling fonts | Since 12.0.5 the third argument is required, so the code passes `""` for no flags | Fixed |
| `UnitFullName`, `Ambiguate`, `GetNormalizedRealmName`, `UnitClass`, `IsInRaid`, `IsInGroup`, `GetNumGroupMembers`, `GetNumSubgroupMembers`, `UnitIsGroupLeader`, `UnitIsGroupAssistant`, `InCombatLockdown` | Names and group state | Long-standing | Not checked |
| `C_Timer.After`, `C_AddOns.GetAddOnMetadata`, `CreateFont`, `issecretvalue` | Timers, version text, fonts, secret guard | Not changed in the 12.0.5 page | Not checked |
| `BasicFrameTemplateWithInset`, `BackdropTemplate`, `UIPanelButtonTemplate`, `UIRadioButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`, `UIPanelScrollFrameTemplate` | Frames and widgets | Unverified on the current client, the first thing to check if the panel errors | Not checked |
| Role icon texture `Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES` and its coordinates | Role icons | Written from memory. Replace with an atlas if it looks cropped | Not checked |
| Events `GROUP_ROSTER_UPDATE`, `GUILD_ROSTER_UPDATE`, `PLAYER_ROLES_ASSIGNED`, `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_REGEN_DISABLED` | Refresh and combat stop | Not checked | Not checked |

### Secret values (Midnight and later)

Since patch 12.0.0 some combat and unit values are "secret", and addon code cannot compare them, do arithmetic on them, or use them as table keys. The [Secret values page](https://warcraft.wiki.gg/wiki/Secret_values) lists the sources and says to test with `issecretvalue` before using a value. This addon only needs group and role data, so it is low risk, but watch these places.

- `inCombat` in `Apply.lua` already guards the combat check with `pcall` and `issecretvalue`.
- Names for units outside your group can be restricted. If a name or role comes back as a secret, comparing it will error, so guard it the same way and skip the player.
- Any new page that reads combat data, such as an interrupt display or cooldown check, will hit this first. Design those around passing values straight to the display APIs, as the wiki page advises.

### If something breaks after a patch

| Symptom | Likely cause | Fix |
|---|---|---|
| Addon shown as out of date | New `## Interface:` number | Update the `.toc` |
| `attempt to call a nil value` | An API was removed or moved | Find it in the patch's API changes page and swap in the replacement |
| `Couldn't find template` or a missing frame part | A frame template or its child names changed | Check the template name on the wiki, or build that widget by hand |
| Apply stops with "isn't accepting group moves" | The group-move calls changed or need a hardware event | Check the two checked API pages above, and test one move from a button click |
| Role icons missing for everyone | `UnitGroupRolesAssigned` returns NONE or a secret | Test `UnitGroupRolesAssigned("raid1")` in game and guard the value |
| Fonts or text clipped | Font or template defaults changed | Adjust `FONT_SCALE` and the layout constants together |

### Rolling back

If a patch fix goes wrong, restore the previous Git commit and `/reload`. Saved layouts are unaffected, because the addon only adds settings and never removes them. Do not rename `CRTDB` or the `SavedVariables` line, or all saved layouts will appear lost.

## Change log

| Date | Version | Change |
|---|---|---|
| 2026-10-13 | 0.1.1 (Git) | This folder became the repository (cloned from `AlexHailstone/Cowfee-Raid-Tools`), with a junction into AddOns, MIT license, GitHub README with screenshot, and tag `v0.1.1`. No code change |
| 2026-10-13 | 0.1.1 | Rename a saved layout: the "Editing:" name is now an edit box, saved on Enter or when you click away. Added `Groups:Rename` |
| 2026-10-12 | 0.1.0 | First build: panel with menu, Raid Groups page, save, edit, apply, export, import (including pasted name lists), role icons, lit and dim names, 1.2 font scale. Fixed `SetFont` third argument for 12.0.5 and later |
