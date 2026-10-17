<h1 align="center">Cowfee Raid Tools</h1>

<p align="center">
  <strong>Raid groups, ready checks, raid notes, debuffs, a late tracker and Tattlebot, in one panel.</strong>
</p>

<p align="center">
  <strong>Game version</strong> <code>12.1.5</code> &nbsp;&nbsp;·&nbsp;&nbsp; <strong>Addon version</strong> <code>0.18.1</code> &nbsp;&nbsp;·&nbsp;&nbsp; <strong>License</strong> <code>MIT</code>
</p>

<!-- Add a screenshot taken with dummy names, then uncomment:
<p align="center"><img src="docs/raid-groups.png" alt="The Raid Groups page" width="720"></p>
-->

Cowfee Raid Tools is a World of Warcraft addon for raid leaders, officers and raiders. Type `/crt` to open one panel with a page for each tool.

> [!NOTE]
> **Beta.** Raid Groups has been used in its author's raids. The other pages (Ready Check, Debuffs, Raid Notes, Late Tracker, Tattlebot, Timeline) are new and have not been tested in a live raid yet. Applying a layout moves real players, so try it on a small group first, and please report anything odd.

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
- [Timeline](#timeline)
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
| **Raid Notes** | Notes per boss with timers that count down from the pull, shared by the raid leader. Windows for the timers, the assignments and your own personal note, a personal alert for your next spell with text to speech, and a "show only me" filter. Your own reminders for boss abilities, with times taken from the boss's reference timeline, that alert, show as bars and speak. Phases that start on a boss emote, a boss becoming untargetable or targetable, or a new boss unit, and four movable alert areas (icons, texts, bars and circles) with their own Alerts tab, where you choose which of your note lines go where and how each looks. One popout editor makes an alert a line of the boss's raid note, for you, a role, a class, a group or a name, or one of your own, and a double-click on the Timeline drops a note there, templates to place from a strip under it, with a row of healer cooldowns and raid defensives filtered by class, drag to move a note and Alt+drag to add another time. In the alert editor, type a spell's name (a close spelling works) to look it up. Everyone can add their own reminders on the Timeline's **Personal notes** row; they stay on your PC, are never shared, and list in your personal note window by phase, counting down in a fight. Only the raid leader and assistants (the party leader in a party) can change the raid note: everyone else sees its lines read-only and can copy one to their own reminders |
| **Quality of Life** | Small conveniences: an experimental LOW HEALTH banner at or under a health percent you set with a slider. A low-health sound is a work in progress and switched off for now |
| **General Settings** | Settings for the whole addon: a Modern look (coffee colors, flat controls, grouped menu) or the Classic look, the window scale (50% to 200%, also Ctrl + mouse wheel over the panel), the game's window style or minimal black in Classic, the window's opacity (30% to 100%), the font, outline and text size (8 to 22 pt) of all the addon's text (the note windows included, after a confirmation, with fonts other addons share through LibSharedMedia when one is installed), which layer each window is drawn in, the sound channel the addon's sounds play through, whether reports and Discord exports leave out realm names, the minimap button, and profiles (each character picks one; create, copy, reset, delete, export and import) |
| **Late Tracker** | Raid days and a start time. Anyone expected who is not in the group gets a running clock until they join, and every night is kept in a history with totals |
| **Tattlebot** | After each boss pull, reads the game's damage meter and reports who took damage from a built-in list of boss mechanics, per pull and per night, with how many pulls each player was hit in. Posts to chat and exports for Discord |
| **Timeline** | Saves every raid boss pull, ten per boss and difficulty, and draws it as a timeline: time runs left to right, with a row for each boss ability and a row of deaths. Zoom, scroll, hover for the time, and draw the deaths of recent pulls over the shown one to see who keeps dying and when. A boss's reference timeline (shipped for Nek'zali the Soulcoiler on Mythic, or pasted in) shows its planned casts with phase lines and duration bars, and a recent pull can be laid over it |
| **Pace** | Where each boss's health should be as the fight goes, by phase (seconds into each phase) or by time from the pull. In the pull, a movable window shows each boss's health with a tick where it should be, and AHEAD or BEHIND. Add rows one at a time, or import and export them as text. A raid leader or assistant can share plans with the raid; a shared plan is kept apart from your own and becomes the plan in use |

**Previews**, in the top right of the panel, shows every movable window at once so you can drag them into place. The button beside it, or a double-click on the title bar, minimizes the panel to its title bar, and the same again (or `/crt`) restores it. Positions are saved per character.

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
| Click or drag a name under **In group, not in layout** | Puts someone who is in your group but not in the grid (a renamed or new character, say) into the first empty slot of their raid group, or onto the slot you drop them on |
| Edit the name at the top | The layout is renamed when you press Enter or click away |
| Press **Set current roster** | The grid fills from your live group, in its current subgroups, after asking if the grid has names |
| Press **Clear grid** | The grid empties |
| Press **Use This Group** | The open layout becomes the raid's active roster, marked active in Quick Load. The Late Tracker expects the people in it, in their groups, and follows it if it changes during a raid night |
| Press **Arrange Groups** | The raid is moved into the layout, one move at a time. Leader or assistant only, out of combat |

**Bright and dim names.** A name in your current group shows in its class color with a role icon. A name that is not shows dark grey with a muted red border.

**Import and export.** Export gives a `CRT1;` string to share with anyone using the addon. Import also takes plain names, one per line, such as a column copied from a spreadsheet: rows 1 to 5 fill Group 1, rows 6 to 10 Group 2, and a blank row leaves a slot empty.

**How Arrange Groups works.** It moves one player at a time and waits for the game to confirm each move. Players not in the layout keep their group if there is room. Players in combat are skipped and listed, and so are names in the layout who are not in the raid. It stops if combat starts.

## Ready Check

`/crt check` opens the ready check window for your group at any time. **Shift-click a column heading** in it to post who is missing that consumable or buff to raid chat, such as "Mark of the Wild missing: Solex". Raid buffs only get a column when someone in the group can give them, and players whose buffs the game hides are listed as "couldn't check", never as missing.

`/crt readycheck` opens the page, which has three tabs.

- **Window.** A table that opens on a ready check for the raid leader and assistants: every player's ready answer, consumables, raid buffs and durability, for 30 seconds or until you right-click it. Arrange its columns by dragging the headings in the copy on this tab, and click a heading to hide it. Sort players by group, role or name, with a class color bar behind each row. Hover any cell to see the buff and how long it has left, or why it is missing.
- **Your bar.** Five icons above the ready check for your own food, flask, potions, weapon oil and augment rune, with time left or bag count. Food, flask, weapon oil and augment rune are clickable to use them, using fleeting items first and then the highest quality rank. The potion icon only shows how many potions you have, every rank counted. Drag items from your bags onto the bar to add your own, and drag the rows to set the icon order and which item is used first. Hover an icon to see the active buff or weapon oil and its time left.
- **Settings.** Run the report automatically on a ready check or a pull timer, choose where it goes, and what counts (flask expiring warning, lower quality flasks). Any food buff counts as fed, whatever was eaten. The automatic report only goes to chat from whoever started the ready check, so it is posted once. Here you also turn your bar on or off, hide it on a ready check you started yourself, and set when it warns that a buff is running low.
- **Pull timer.** When a pull timer starts, your bar and the ready check window fade out over 2 seconds. If someone starts the fight more than half a second before the timer ends, **Early pull** reports the first players in combat and who cast just before (other players' spells are hidden by the game, so only their names and times), to you or to raid or officer chat. Both are settings on the Ready Check page.
- **Ready button lock** (on by default). If your class gives a raid buff and someone in the group is missing it, your Ready button is greyed out until they have it; hover it to see who. Hold Shift and click Ready to ready anyway, and it unlocks by itself after 10 seconds. Players the game can't check never lock you.

Durability and weapon oils in the window only show for players running Cowfee Raid Tools, since each one sends their own: the game never shows addons another player's weapon oil, because oils are weapon enchants, not buffs. Shift-clicking the Dur heading posts everyone under 30%.

## Debuffs

`/crt debuffs`, the **Debuffs** tab of Quality of Life. A movable panel that shows the boss mechanic debuffs on you during combat, using the slots the game provides for them. Choose the icon size and how many to show, and place it with Previews. Under Look, set where the timer text goes (below, above, on the icon, left, right or hidden, with a nudge in pixels), the swipe and its edge, the countdown numbers, the dispel type icon and the border size. The game draws these debuffs itself, so their font, text size and colors can't be changed by any addon.

## Raid Notes

`/crt notes` opens the page, with five tabs: **Notes**, **Reminders**, **Phases**, **Alerts** and **Settings**.

**The note format.** Lines of `key:value;` pairs. A timer line looks like `time:34;ph:1;tag:Name;spellid:64843;` or `time:48;ph:1;tag:G1;text:Group 1 go in;dur:8;`. A tag can be a player name, a role (`tank`, `healer`, `dps`, `melee`, `ranged`), a raid group (`G1`, `Group 1`), or `everyone`. A line starting `EncounterID:` names the boss, and an `invitelist:` line becomes a Raid Groups layout. Every other line is assignment text.

- **Share to raid** sends the note to everyone with the addon and makes it the active note for all of them, you included. Raiders who already have that exact note just switch to it, so you can share notes ahead of time and share one again to switch the raid to it. Notes are compressed, so most arrive at once. Only the leader or an assistant can share, and only before the pull, since the game blocks addon messages during a boss fight; anyone else, or a leader not in a group, still gets the note as their own active note, and the chat says why it wasn't sent. Whenever the active note changes (shared, received, or made from the Timeline), this page switches to it, so the text you see is the note that runs. The Timeline's **Share note** does the same for the boss on screen, and makes the boss's note first, with its EncounterID, Difficulty and Name header, when it has none; lines added or moved on the Timeline are written into that note's text here. Raiders need version 0.13.0 or later to receive notes shared from 0.13.0.
- **Three windows:** the timers, counting down from the pull; the assignments, with your lines marked and names class colored; and your own personal note. Each can be locked so clicks pass through, or unlocked to drag and resize.
- **Show only me** keeps only the timers for your name, role, raid group or everyone.
- **Your alert** shows your next spell or callout before it is due, with the name and countdown centered under each other and the spell icon, two lines tall, to the left, right, above or below. It can read it out with text to speech. Its timing and voice are on the **Settings** tab; turning it and the speech on or off is on the **Alerts** tab.
- **Phases.** The first phase starts on the pull. Later phases start when someone presses **Next phase** or types `/crt note next` (the button shows which phase it starts next, such as **Next phase (1.5)**, the chat line says which phase started, and both work on a pull with only reminders and no note), or on a trigger you set on the **Phases** tab: a boss emote containing some text, a boss becoming untargetable or targetable, or a new boss unit appearing. Whichever comes first starts the phase, and a repeat is ignored. If a later phase starts while an earlier one never did, the earlier one is skipped and its alerts do not fire. The game can hide these values in a boss fight, and a value it hides never matches, so Next phase is always the fallback. No trigger ships with the addon yet.
- **Mech Alerts.** `/crt reminders` opens the **Mech Alerts** tab. Pick a boss and difficulty: the list on the left shows the abilities from the boss's Encounter Journal, then your own reminders. Tick one to get a reminder with the times of the boss's reference timeline (a small dot means the reference has times for it). Click a row to see its alert in the panel on the right: Show from and Linger, the times (read only), **Show on the Timeline**, how it shows, its text, icon (a spell ID, an icon ID or a spell name to look up), colour and sound, with **Test** and **Save as template**. Every change saves at once. **Your own reminder** adds one that is not tied to an ability. You can also double-click a cast on the Timeline to make a reminder from it (see **Alert editor** and **Notes on the Timeline** below). A reminder with no reference and no typed times is listed as "No times" and never fires. Reminders are kept per boss encounter, so a boss appears once it has been pulled, while you stand in its raid, or once its reference names its encounter. The next spell alert shows a reminder's own text, with its spell's icon.
- **Alerts tab.** The left side, **Your note lines go to**, ticks where your own lines from the raid note show: the Next spell alert, text, icon, bar or circle, as many as you like, and **Read them out (text to speech)**, which reads them wherever they show, with or without the Next spell alert, and plays their sounds. It is also the master switch for all speech, so turning it off silences your reminders too. A note line that names its own displays keeps them, though each display's own switch can still turn it off. Under it, **Previews** and **Test all areas** (three test alerts counting down in each). The right side, **Configuration**, has a list of **Icons**, **Texts**, **Bars** and **Circles**; pick one to see its settings. Each has **Show these alerts**, how many at once and which way it grows, then its own: icons have a size, font, outline, whether to show the text and whether the icon **fades to grey as time runs out**; texts a font, size (12 to 72), outline and alignment; bars how far ahead they show, width, height, font and the bar, background and text colours; circles a size, ring thickness (thin, medium or thick), ring colour with opacity, font and outline.
- **Alert areas.** An alert can show in four movable places: **Icons** (the spell's icon with a countdown swipe over the icon only, the seconds in its middle and the text beside it), **Texts** (big text with the seconds after it), **Bars** (what is coming up, soonest first, with the icon, text, seconds left and a bar that empties) and **Circles** (a ring with a clear centre that empties, the seconds inside and the text under it, starting over your character). Press **Previews** and each area shows sample alerts in a box with its name, a cog and a Reset button: drag the box to move the area, and the cog opens its settings on the Alerts tab (the main window steps aside to the far side of the screen while Previews are on, and returns when they turn off). An alert's own colour wins on bars and rings. Every area shows its alerts soonest first, up to its cap. A note line and a reminder at the same moment both show, and speech plays one line at a time: if it falls behind, your reminders are kept, then your note lines. If you had the Next spell alert off but text to speech on, your note lines are now read out; you get one chat line about it, and unticking **Read them out** stops it.
- **Alert editor.** One window edits every alert: a double-click on the Timeline or on a marker opens it. Pick **Save as** a **Raid note** line or **Only me**. For a raid note line pick who it is for (everyone, you, a role, a class, a group or a name) and the difficulty. The line is added to the boss's note for that difficulty, or to the boss's other note if that is the one the pull reads, and a note is made only when the boss has none; a line under the first row tells you which. Then set the time (from the pull or from a phase), how early it shows and how long it stays, the icon (a spell or an icon ID), the text and its colour, and tick how it shows (Next spell alert, text, icon, bar, circle) and whether it speaks the text, counts down 3 2 1, glows at 0 and plays a sound. **Test** shows it now, **Export** gives it as a note line to copy, **Delete** removes only that alert, and **Save** keeps it. The window follows the Modern or Classic look.
- **Note lines.** A timed line in a raid note can say how it shows with extra fields next to the usual ones: `show:` (a list of `alert`, `text`, `icon`, `bar` and `circle`), `tts:1` to read it out, `count:1` to count down 3 2 1, `sound:<name>`, `glow:1`, `warn:<seconds>` for how early it shows, `linger:<seconds>` for how long it stays and `icon:<id>`. A tag can name a class, such as `DEATHKNIGHT`, and `tag:everyone;` is for everyone. A line without `show:` behaves as it always did, so existing notes do not change. Your own settings still win: a note line cannot show something you have turned off.
- **Notes on the Timeline.** Double-click anywhere on the Review track to drop a blank note at that time; double-click a boss ability's icon to take that ability as well. The time becomes a phase and seconds from the reference's phase lines (on a recorded pull, from the pull). Every saved note line and reminder of the boss shows as a small flag at its time, raid notes and your own in different colours; hover one to see the text and who it is for, and double-click it to edit. Until the Timeline can tell difficulties apart, the flags show every difficulty's note.
- **Moving an alert on the Timeline.** Drag a flag to move its alert to another time, or hold **Alt** when you let go to add another time to the same alert (a raid note line gets an identical new line there, which you edit separately afterwards). A raid note line that was changed since you grabbed it, such as by a new share, is not moved, and a message says so. Let go off the track, or over the alert editor, to cancel. Moving or adding a time to a reminder that followed the boss's reference gives it its own typed times from then on.
- **Templates.** A template is one alert's setup without its time: the text, icon, how it shows, speech, sound, colour, and who it is for. Make one with **Save As Template** in the alert editor, or with the **+** chip in the strip along the bottom of the Timeline. Drag a chip onto the track to open the editor on a new alert there (dropped on a boss ability's icon it takes that ability), or right-click the track without dragging for **New alert here** or **Place**. Right-click a chip to edit, rename or delete it.
- **Cooldowns.** Under the templates, a row of healer cooldowns and raid defensives (Tranquility, Spirit Link Totem, Rallying Cry and others), filtered by class with your own class first. Drag one onto the Timeline like a template, or right-click it to keep it as a template. A raid leader or assistant who drops one gets a small menu: that class's players from the active Raid Groups layout (or the group you're in), Anyone else, or Just me; picking a player makes a raid note line for them, and with nobody of that class it can be left unassigned until one joins. Templates and cooldowns wrap onto up to three rows, and the mouse wheel scrolls any more.

## Late Tracker

`/crt late`. The page has three tabs: **Tonight**, **History** and **Settings**. On Settings, tick your raid days and the start time, and pick the Raid Groups layout of who should be there. At the start time, anyone in it who is not in your group gets a running clock until they join, or until the group disbands. **Start raid now** starts a night by hand when invites go out off schedule. Every night is saved to a history with join times, and Totals shows how often each player was late. **Export for Discord** opens the selected totals or night as text to copy and paste into Discord, where the columns line up in a code block.

## Tattlebot

`/crt tattle`. After each boss pull, once you are out of combat, Tattlebot reads the game's own damage meter (Damage Taken) and keeps the damage each player took from the boss mechanics it tracks. A mechanic can have several spell IDs, and they are added together, so each mechanic is one line in the report. The game keeps the meter secret during a fight, so nothing is read until combat ends. The meter has damage per spell but no hit count, so Tattlebot reports each player's damage per mechanic and the number of pulls it hit them in. **Tonight** shows tonight's pulls and totals, **History** keeps every night with totals, and both can post to chat or **Export for Discord**. Totals on Tonight and History, the Discord export and chat posts are all by mechanic, most damage first: a table of Mechanic, Player, Pulls hit and Damage, with each mechanic's name on its first row. Damage is added up over every pull, and Pulls hit is how many pulls it hit that player in. Each pull keeps all the damage taken, so a mechanic added partway through a night also counts on that night's earlier pulls. Chat posts list every player, carrying on onto more lines when a mechanic doesn't fit on one. History has a **Season** filter (**All seasons** or **Current night**, which is tonight's night, or the last one saved when none is running) and a **Mechanic** filter: pick a mechanic and Totals becomes its record, with each player's damage from it, how many pulls on its boss it hit them in, and the average per pull it hit. Nights are also labeled with the season named on **Settings**. **Mechanics** has a boss dropdown that shows the mechanics tracked for each boss with their spell IDs, and **Your own spells**, where you can add spell IDs of your own and name the mechanic they belong to. On **Settings**, Tattlebot can also count everything the game marks as avoidable damage, and post each pull's report on its own (to chat only from the raid leader). The shipped list is in `Tattlebot/Database.lua`, grouped by boss and mechanic. To track more on the fly, pick **Last fight** in the Mechanics dropdown (or type `/crt tattle scan`): it lists every spell that damaged the group in the last fight with a check box, so tick the ones to track and press **Add checked**. They are added for that fight's boss, and spells that share a name become one mechanic. Their damage in that fight counts at once: it is filled in on the pull Tattlebot saved for it, or, if there is none (a fight that wasn't a boss, or a training dummy), the fight is saved as a pull of its own. Tracking starts with the fight you scanned.

## Timeline

`/crt timeline`. Every raid boss pull is saved on its own, from the pull to the kill or wipe, and the last ten pulls of each boss are kept for each difficulty, Normal/Heroic and Mythic counted apart (a pull shorter than 15 seconds is dropped as a reset). The **Review** tab starts with a **Difficulty** dropdown, **Normal/Heroic** or **Mythic** (Normal and Heroic share one schedule, so they are one view; the page opens on the difficulty, boss and reference or pull you last looked at, after a reload too). The boss list, the pull list, the references and the Recent pulls list show only the difficulty picked there, and a boss with pulls only on the other difficulty is listed with none. Pick a boss and a pull and it is drawn as a timeline (**Pop out** moves the Review tab into a window of its own that you can drag to any size, and Dock or closing it puts it back): time runs left to right, with a row for each boss ability and a row for deaths. Hover the timeline to see the time under the mouse, so you can copy it into a note. Zoom with the slider or the mouse wheel over the timeline, hold the right mouse button and drag to move left and right, and use the mouse wheel with Shift to scroll the rows. Hover a death to see the player, the time and, when the game gives it, the killing blow. **Deaths from recent pulls** draws the deaths of the pulls before the shown one over it, fainter the older they are, so deaths that repeat stand out. The ability rows come from the boss's Encounter Journal page, read out of combat, and a cast shows on the row of its spell. **Settings** has the view (visible time, grid interval, icon size), which rows to show or hide, spell IDs of your own to add as rows, the deaths (one row or one per player, which roles, only the first few deaths, how many pulls the overlay covers), and recording (on or off, the shortest pull to keep, delete a boss's pulls). A boss's **references** are listed in the pull dropdown, before its recorded pulls, as `Reference · Mythic · 9:48`, and a boss with one opens on it, even before its first pull. A reference is a planned cast schedule: the abilities in the order the plan lists them, with red phase lines and their labels across the rows, a bar behind a cast that lasts a while, a thin line before an icon that starts early, and a row name in its own color. The color says what the ability is: blue a dispellable debuff, red unavoidable raid-wide damage, green fall-off damage, orange Mythic only, purple Heroic and higher, white a plain mechanic, pink a soak, yellow spread out or get away, teal dodge and lime heavy damage over time. The row behind it is tinted faintly in that color, an ability that is more than one of these gets a dot on its name for each extra one, and the tooltip lists them all. Nek'zali the Soulcoiler (Mythic) ships with the addon, so Normal/Heroic has no shipped reference yet. A row marked `(type mythic)` is Mythic-only and is never drawn on Normal/Heroic, and neither are its casts. The red lines are the phase changes: hold **Shift** and drag one to move it. Its casts move with it, and the casts of the phase before it that would now fall past the line are hidden, not deleted, so they come back when you move it back. Right-click a moved line to put it back. The move is written into the reference as `Phase: P2 2:53 (planned 3:03)`, the planned time being the one it was transcribed with, and a shipped reference is copied into a reference of your own first, since shipped ones never change. When the raid picks the order of a boss's parts (which turtle empowers first on The Lost Explorers), an **Order** dropdown appears beside Pull (on the second row while the Timeline is docked) listing every order, the written one first. Pick one and each part's own rows move into the window it now has, keeping their time from the window's start; rows every part shares stay put, and a cast that would run past its new window is hidden. The phase labels name the part in each window, and labels that would overlap stagger over two rows above the times. The choice is kept per boss and difficulty. The **Recent pulls** list beside a reference shows the boss's saved pulls; click one to lay it over the reference (its deaths in the Deaths row, its casts as ticks on a `Pull N casts` row, and a line where it ended), and click it again to clear it. The **References** tab, between Review and Settings, has a box to paste your own references and a list of the selected boss's, where yours can be edited and deleted and the shipped ones copied into the box to change. **Save** stamps the box with the Difficulty picked on the Review tab (a `Difficulty: Heroic` or `Normal` line is kept on Normal/Heroic), so each reference is one difficulty, and the list shows only that difficulty's. **Copy to** on a listed reference adds a copy for the other one: to Normal/Heroic it leaves out the Mythic-only rows and says how many, which is the quick way to make a Normal/Heroic version from a Mythic one. Under that list, **Journal abilities** shows the boss's Encounter Journal abilities with their spell IDs, and **Fill spell IDs** writes `[spell N]` into every line of the box whose name matches one of them, so the icons and tooltips are fixed in the text. A reference with no `Encounter:` line finds its boss in the Journal by the boss's name, so its icons show before the first pull and outside the raid. A reference is plain text, one line per thing, and nothing is saved until every line reads (the first errors are shown as `Line N: reason`):

```text
Boss: Nek'zali the Soulcoiler
Difficulty: Mythic
Length: 9:48
Phase: P1.5 3:17
Phase: 5:53
Soulcoil Rite (color ff6b7d): 0:02+45, 1:17+45, 2:28+45, 7:38
Possession Barrage (lead 7, color 7ddc6a): 0:36, 1:12, 1:47
Grasping Depths [spell 123456]: 0:42, 1:53
```

`Boss` is required; `Difficulty` (one block per difficulty, each with its own line), `Length` and `Encounter` (the boss's encounter ID) are optional. A time is `m:ss` or plain seconds, `+45` after a time draws a 45-second bar, `lead 7` draws a line 7 seconds before each icon, `color rrggbb` colors the name, `type mythic` (and the other types in the colors above) marks what the ability is, `(planned m:ss)` after a Phase time is where it was before you moved it, `Order: Empowered A, Empowered B, Empowered C = Gebbo, Nama, Iku` names the phases whose parts the raid orders and the parts in the written order (2 to 4, no digits in a part's name; name those phases without digits too, since reminders read a phase's number from its label, and Save warns when a label reads as phase 1 or repeats a number), `part Gebbo` marks a row as that part's, and `[spell N]` gives the icon and tooltip. Blank lines and lines starting with `#` are skipped. Planning markers and sending them to Raid Notes are not built yet.

## Commands

| Command | What it does |
|---|---|
| `/crt` | Opens or closes the panel |
| `/crt groups` | Raid Groups |
| `/crt readycheck` | Ready Check. `/crt consumables` opens its Your bar tab |
| `/crt check` | Opens the ready check window for your current group, open until you right-click it. Shift-click a heading to post who is missing it |
| `/crt check food` (or `flask`, `rune`, `vantus`, `buffs`, `all`) | Checks the group and shows it to you. Add `chat` to post it, such as `/crt check all chat` |
| `/crt rc` | Shows your ready check bar for 20 seconds, for testing |
| `/crt debuffs` | Quality of Life, on the Debuffs tab |
| `/crt notes` | Raid Notes. `/crt notes settings` opens its Notes Settings tab |
| `/crt reminders` | Raid Notes, on the Reminders tab |
| `/crt note test`, `/crt note next`, `/crt note stop` | Start the note in use now, start the next phase (the chat line names it), stop the whole run (note and reminders) |
| `/crt late`, `/crt late start`, `/crt late end` | Late Tracker, start tonight's raid now, end it |
| `/crt late export` | The late totals as text to paste into Discord |
| `/crt tattle`, `/crt tattle post`, `/crt tattle night`, `/crt tattle end` | Tattlebot, post the last pull, post tonight's totals, end the night |
| `/crt tattle scan`, `/crt tattle scan text`, `/crt tattle export` | Pick spells to track from the last fight, the same list as plain text, and the Tattlebot totals for Discord |
| `/crt timeline` | Timeline. `/crt timeline pop` opens the Review tab in its own window, which you can drag to any size |
| `/crt pace` | Pace |
| `/crt previews` | Toggles the previews, same as the button in the panel |
| `/crt break 10` | A break timer for that many minutes, counting down in a small window and ending with a sound; `/crt break 0` cancels it. From a raid leader or assistant it reaches everyone with the addon and is posted as a raid warning |
| `/crt qol` | The Quality of Life page, with the experimental low-health alert and the Debuffs tab |
| `/crt settings` | General Settings: the look, window, fonts, sound, minimap button, layers and profiles |
| `/crt minimap` | Shows or hides the minimap button |
| `/crt lowhp off`, `/crt lowhp on` | Turns the experimental low-health alert off or on |
| `/crt lowhp stop` | Stops any low-health sound the addon is playing |
| `/crt perf` | Shows the addon's CPU use since the last `/reload`, from the game's profiler |
| `/crt help` | Lists the commands |

## FAQ

<details>
<summary><strong>Where are my settings saved?</strong></summary>

In the game's saved variables: `WTF\Account\<account>\SavedVariables\CowfeeRaidTools.lua`. Back that file up if you want to keep your layouts, notes and late history. Each profile is kept there too, and each character's choice of profile is in `WTF\Account\<account>\<realm>\<character>\SavedVariables\CowfeeRaidTools.lua`. Export on General Settings gives a profile as text to keep or share.

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
- Raid note phases after the first need **Next phase** unless you set a trigger on the Phases tab. The game can hide boss emotes and boss unit changes in a fight, and nothing has been confirmed on a real boss yet, so triggers may not fire. Notes must be shared before the pull.
- Alerts show as the Next spell alert, texts, icons, bars and circles, with speech, a sound and a glow. The screen flash, the alert log and practice mode are not built yet. The alerts have been run outside the game only, so how the swipe and ring look, the colour picker, the sounds and large fonts are untested in the game. The new ring pictures need a full restart of the game, not just a reload, to appear.
- Potions and healthstones used in a fight, and other players' armor kits, cannot be checked. Other players' weapon oils and durability only show for raiders who run the addon.
- Apply cannot move a player who is in combat.
- Tattlebot reports damage taken, not the number of hits: the game's damage meter does not count hits, and the combat log is closed to addons during boss fights. It reads the meter after each boss pull, so it needs the game's damage meter to be available.
- Timeline probably records boss casts without the spell's name. The game keeps the spell ID secret during boss fights, so those casts show as "Boss casts (unnamed)", with only their time. Reference icons and spell tooltips come from the Encounter Journal (or from `[spell N]`), and the Journal is not read in combat, so they can be blank until you are out of combat. Deaths and their times come from the game's damage meter after the pull, so they are read once you are out of combat, and a `/reload` in the middle of a pull loses that pull.

## Reporting a problem

Please open an issue and include what you did, what you expected, and the exact error text if there is one. To see Lua errors, type `/console scriptErrors 1` and `/reload`. Include your game version, from `/dump select(4, GetBuildInfo())`, and the addon version from `/crt help`.

## Development

The addon is plain Lua with no bundled libraries.

```
CowfeeRaidTools/
  CowfeeRaidTools.toc    title, version, interface number, saved variable
  Core.lua               namespace, saved data defaults, scaled fonts, the Modern colors
  Profiles.lua           profiles: load, switch, copy, reset, delete, export, import
  Bosses/Registry.lua    the boss library: every boss's shipped data, read by the features
  Seasons/               season packs: one file per boss with all its properties
  Slash.lua              the /crt command
  UI/Panel.lua           main window, left menu, page registry, previews
  UI/Controls.lua        Edit Mode style dropdowns and sliders shared by the pages
  UI/Minimap.lua         the minimap button and the game's addon menu entry
  UI/SettingsPage.lua    the General Settings page
  Sounds/                your own low-health sound files (see its README.txt)
  Groups/                Raid Groups: data, Apply, page
  Consumables/           your ready check bar and the consumables list
  ReadyCheck/            the Ready Check page, raid report and ready check window
  Debuffs/               the debuff panel
  Notes/                 raid notes: parser, timers, windows, alert, sharing, page and its four tabs
  Alerts/                the alerts engine: conflict rules, blocks and phase clock, speech queue, reminders,
                         phase events, templates, the alert areas (icons, texts, bars, circles), the alert
                         editor
  Late/                  the Late Tracker
  Tattlebot/             Tattlebot: the mechanics list, the damage meter reading, page
  Timeline/              Timeline: the recorded pulls, the Journal ability rows, the reference timelines
                         (Database.lua, Reference.lua), the lanes, the timeline view, the pages
                         (Page.lua, ReferencePage.lua)
```

- **Releases.** Pushing a tag such as `v0.12.0` runs the GitHub Actions workflow in `.github/workflows/release.yml`, which builds `CowfeeRaidTools-v0.12.0.zip` with the BigWigs packager (`BigWigsMods/packager`) and attaches it to a GitHub release.
- **Saved data.** Everything lives in the `CRTDB` saved variable. New settings are added as defaults in `Core.lua` so existing saved data keeps loading.
- **After a patch.** Update `## Interface:` in the `.toc` to the new number from `/dump select(4, GetBuildInfo())`.

## License

Released under the [MIT License](LICENSE). World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. This addon is not made by or endorsed by Blizzard.
