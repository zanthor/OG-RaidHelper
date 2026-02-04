# OG-RaidHelper

**Author:** Gnuzmas  
**Special Thanks:** Claude v4.5, Blood and Thunder Leadership, Pepopo  
**Compatible with:** World of Warcraft 1.12.1 (Vanilla / Turtle WoW)

A comprehensive raid management addon for organizing encounters, assigning roles, managing trade distributions, coordinating raid activities, and validating soft-reserve integrity.

<img width="1351" height="613" alt="image" src="https://github.com/user-attachments/assets/7ea5c4a7-d61a-4aee-ad98-abba03bf1f1c" />

---

## Dependencies

**Recommended:**
- **[RollFor 4.8.1](https://github.com/sica42/RollFor)** - Soft-reserve addon that provides the underlying data for the Raid Invites and SR+ Validation features. OG-RaidHelper reads RollFor's encoded soft-reserve data to display players, roles and SR+ values for items.
- **[Puppeteer](https://github.com/OldManAlpha/Puppeteer)** - Raid Frames with Support for Tank and Healer roles.  OG-RaidHelper automatically sets roles on players.
- **[pfUI](https://github.com/shagu/pfUI)** - Raid Frames with support for Tank roles.  OG-RaidHelper automatically sets roles on players.

---
## Disclaimer

This addon is entirely vibe coded using Claude Sonnet 3.5 and 4.5.  I deliberately kept myself out of the code because I want to bolster my knowledge of AI in the workplace, and what better way to do that than to create an entire TWoW addon.

I learned a ton about how to use AI to effectively code in the v1.x work, and I applied everything I learned in my work on the v2.0 release.  I'm sure real programmers will look at this (statement and code) and cringe a lot, I know I have cringed a lot working on this.

---

## Table of Contents

- [Dependencies](#dependencies)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Main Window](#main-window)
- [Roles Window](#roles-window)
- [Raid Invites System](#raid-invites-system)
- [SR+ Validation System](#sr-validation-system)
- [Encounters System](#encounters-system)
- [Trade System](#trade-system)
- [Share System](#share-system)
- [Poll System](#poll-system)
- [Slash Commands](#slash-commands)
- [Announcement Tags](#announcement-tags)

---

## Installation

1. Extract the `OG-RaidHelper` folder to your `Interface\AddOns` directory
2. Restart World of Warcraft or type `/reload` if you are just updating in-game
3. You should see the OG-RaidHelper main window on your screen or the mini map button RH.
4. Seriously, skip all this and use the GIT Addon manager.
5. or Skip GIT Addon manager and install from the TWOW Launcher.
   
---

## Main Window

The compact main window provides quick access to all major features.

![Main UI](Images/mainui.jpg)

### Window Controls

Located in the title bar:
- **RH** - Addon's main menu - same as MiniMap Menu
- **Rdy** - Performs a Ready Check (left-click), or toggle remote ready checks on/off (right-click)
- **Admin** - Left Click opens the Select Admin Interface - pick someone to be admin.  If you right click and are an A or L you just take control.
- **Roles** - Open the Roles UI where you can quickly and easily organize players by their roles.  This interface is used heavily for Auto-Assignments when you didn't import your data, it's also used for the consumes logging so if you switch someone their consumes may be tracked inaccurately.
- **L** - Lock/unlock window position (drag to move when unlocked)
- **<** - Previous Encounter
- **>** - You'll never guess what this one does.
- **Incindis** - This button is named "Encounter Select" button, if you right click you can select the current encounter instead of moving next or previous, and you can switch which raid is the "Active Raid".
- **A** - Left Click to Announce the template from the selected encounter, right click to announce any Consumes required.
- **M** - Mark players if configured, mark target + others in it's pack using AutoMarker.

**Window Position:** Drag the window by its title bar when unlocked. Position is automatically saved.

---

## Roles Window

The Roles Window displays your raid composition organized into four columns: **Tanks**, **Healers**, **Melee**, and **Ranged**.

![Roles UI](Images/RolesUI.jpg)

### Window Features

- **Alphabetical Display** - Players are automatically sorted A-Z within each role
- **Class Colors** - Player names are colored by their class
- **Drag and Drop** - Click and drag players between role columns to reassign them

### Window Controls

- **Poll Button** (top-left) - Starts a sequential poll through all four roles
  - Click once to start: prompts Tanks → Healers → Melee → Ranged (10 seconds each)
  
- **Role Column Headers** (Tanks, Healers, Melee, Ranged) - Clickable headers for single-role polls
  - Click a header (e.g., "Tanks") to poll only that role
  - Header shows a poll is active for that role
  - Click the header again to cancel

- **Close Button** (top-right) - Closes the Roles Window

### Using the Poll System

**Full Poll (All Roles):**
1. Click the **Poll** button in the top-left
2. Raid chat message: "TANKS put + in raid chat."
3. Players respond with "+" in raid chat
4. After 10 seconds, automatically advances to next role
5. Sequence: Tanks → Healers → Melee → Ranged

**Single Role Poll:**
1. Click any role column header (e.g., "Healers")
2. Raid chat message: "HEALERS put + in raid chat."
3. Players respond with "+" in raid chat
4. Poll continues until you click the header again to cancel

**How It Works:**
- Players who respond with "+" are automatically moved to the requested role
- Names appear in the role column as they respond
- You can manually drag/drop players between columns after polling


---

## Raid Invites System

The Raid Invites system integrates with RollFor or RaidHelper to allow easy import of a raid roster and automatic invites.

![Raid Invites](Images/RaidInvites.jpg)

**Player List Display:**
- Shows all players from imported data that aren't in raid.
- **Class Colors** - Player names colored by class
- **Online Status** - Green background for online players, gray for offline

### Using Raid Invites

**Inviting Players:**
1. Click minimap button → **Raid Invites** to open window
2. Click "Import Roster" and pick your source.
  - Note: If you are using RollFor we cannot directly access their data so you have to have already imported the data to RollFor.
3. **Start Invite Mode**
   - Click **Start Invite Mode** button to start sending invites.
   - Auto-Announces to the guild that you are sending invites.
   - Auto-Sends 4 invites (Unless you are in a raid)
   - Auto-Converts to a raid, and invites everyone else.
   - If players are in a group, it reports this to /guild
   - If players whisper you it invites or tells them why not.
   - If Sort is toggled (Only for RaidHelper source) to green it will auto-sort the group to match your raid composition.

**Refresh Button:**
- Click **Refresh** to reload import data and updates player list, SR+ values, and online status
- Click **Clear Status** to re-try sending invites to people the addon may not try again.

---

## SR+ Validation System

### Pending Major Overhaul ###
---

## Active Raid - Encounter Planning and Design

The Encounters system provides comprehensive tools for pre-planning raid encounters with role assignments, player pools, raid marks, and automated announcements.

### Encounter Planning Window

Access by clicking the **Encounter** button on the main UI.

![Encounter Management](Images/EncounterMgmt.jpg)

#### Window Layout

**Left Panel: Raids & Encounters**
- [Active Raid] will always be your "top" raid in this interface.
  - This raid is special and disposable.
  - Automatically syncs from the Raid Admin to other players in the raid.
  - Gets copied from one of the other raids by the Raid Admin
  - Planning can be done in the Active Raid or it's Source
  - The active raid NEVER updates the source.
- Click a raid name to manage its encounters
- Click an encounter name to load its configuration in the right panels
- Click the Notepad icon to access Advanced Options for Raids or Encounters.

**Middle Panel: Role Management**
- Shows player slots needing to be assigned for the encounter.
- Drag players from guild list to assignment slots, right click to clear.
- Drag players from one slot to another as needed.
- **Announcements Panel** - Create automated announcements with [tag support](#announcement-tags)

**Right Panel: Players**
- **Roster/Raid** - The left menu lets you choose the source for planning encounters.
  - Roster is created from your Invite Source.
  - Raid is created from your raid group.
  - Both show guild members both online and offline so you can plan even if someone didn't sign up.
- **Role Filter** - The Right button is the Roles Filter allowing you to quickly narrow what players you are trying to assign.
- - Players in Raid are shown based off their role in the RolesUI (which gets updated from the invite system but can be changed manually).
- - Players in Roster are sorted based off the role they signed up as.

**Auto Assign:**
- Click **Auto Assign** button to automatically fill the roles in the selected encounter.
- Automatically fills all roles from their configured player pools
- Roles can be configured for generic roles (Tank, Healer, etc) or by using the Class Priority System to fill them in very specific fashions.

#### Announcements Tab

Create automated raid announcements using dynamic tags:

**Announcement Builder:**
- 8 text input lines for creating multi-line announcements
- Use [tags](#announcement-tags) to insert dynamic player/role information
- Empty lines are skipped when announcing

**Example Announcement:**
```
[R1.T] [R1.P1] healed by [R5.P1][ and [R5.P2]]
[R3.T] [R3.M1] [R3.P1], [R3.M2] [R3.P2] healed by [R5.P3]
Kill priority: [R3.M1] then [R3.M2]
```

**Announcing to Raid:**
1. Ensure encounter assignments are complete
2. Click **Announce** button on main window (or in Announcements tab)
3. Each non-empty line is sent to `/raid` chat with a 1.5 second delay

See [Announcement Tags](#announcement-tags) section for complete tag documentation.

### Encounter Setup Window

Access via **Encounters** → **Setup Raids** from the main window.

![Encounter Setup](Images/EncounterSetup.jpg)

This is an alternative interface for managing the same encounter data with a different workflow. Both interfaces modify the same saved configuration.

#### Window Layout

**Left Panel: Raids List**
- Scrollable list of raids
- Click a raid to load its encounters (left-click)
- Right-click a raid to rename it

**Middle Panel: Encounters List**
- Shows encounters for selected raid
- Click an encounter to load its role configuration (left-click)
- Right-click an encounter to rename it

**Right Panel: Role Configuration**
- Add/edit/delete roles for selected encounter
- Configure role properties
- Two-column layout similar to Encounter Planning window

---

## Trade System

The Trade system allows you to configure and distribute items to raid members quickly.

### Trade Settings Window

Access via **Trade** button → **Settings** (bottom of menu) from main window.

**Window Layout:**
- Scrollable list of configured trade items
- Each item shows: Name, Quantity, and controls

**Item Controls:**
- **Up Arrow** - Move item up in list
- **Down Arrow** - Move item down in list
- **Delete (X)** - Remove item from list

**Adding Items:**
1. Click **Add Item** button at bottom
2. Enter **Item ID** (numeric ID from game database)
3. Enter **Quantity** (1-255)
4. Click **Add**

**Example Trade Items:**
- Hourglass Sand (Item ID: 19183, Quantity: 5)
- Greater Fire Protection Potion (Item ID: 13457, Quantity: 1)
- Frozen Rune (Item ID: 22682, Quantity: 1)

### Using the Trade Menu

1. Click **Trade** button on main window
2. Menu appears showing all configured items
3. Click an item to **set it as active** (header turns green)
4. Open trade window with a player
5. Click the **OGRH** button above the Trade button
6. Items are automatically placed in trade window

**Active Item Indicator:**
- The currently selected trade item is highlighted in **green** in the menu
- This is the item that will be traded when you click OGRH button

**Trade Workflow:**
1. Select trade item from menu (e.g., "Hourglass Sand x5")
2. Target and right-click player to open trade
3. Click **OGRH** button in trade window
4. Items are placed automatically
5. Click **Trade** to complete

**Alternative: Slash Command**
- `/ogrh sand` - Legacy command for Sand trade (if configured)

---

## Announcement Tags

The Announcement Builder uses a powerful tag system to dynamically insert player and role information into raid announcements.

For complete tag documentation, see **[ANNOUNCEMENT_TAGS.md](ANNOUNCEMENT_TAGS.md)**

### Quick Reference

**Tag Format:** `[Rx.TYPE]`
- `R` = Role indicator
- `x` = Role number (1-based, left-to-right, top-to-bottom)
- `TYPE` = Information type

**Available Tags:**
- `[Rx.T]` - Role title (e.g., "Main Tank")
- `[Rx.Py]` - Player name (e.g., "Tankmedady")
- `[Rx.My]` - Raid mark (e.g., "{Star}")
- `[Rx.Ay]` - Assignment number (1-9)
- `[Rx.Cy]` - Consume item (e.g., "Greater Fire Protection Potion")

**Example:**
```
[R1.T] [R1.P1] healed by [R5.P1]
```

**Output:**
```
Main Tank Tankmedady healed by Gnuzmas
```

### Conditional Blocks

**OR Logic (Default):**
```
[R3.P1][, [R3.P2]] will tank
```
- Shows entire block if ANY tag has a value
- Unassigned tags are removed from output

**AND Logic (& prefix):**
```
[&[R3.P1] and [R3.P2]] will tank
```
- Shows block ONLY if ALL tags have values
- Entire block removed if any tag is unassigned

**Nested Conditionals:**
```
[R1.T] [R1.P1][ with [R2.P1][ and [R2.P2]]]
```
Creates three conditional levels for complex announcements.

For full details, examples, and raid mark symbols, see **[ANNOUNCEMENT_TAGS.md](ANNOUNCEMENT_TAGS.md)**

---

## Tips and Best Practices

### For Raid Leaders

1. **Pre-configure Encounters** - Set up all your raid encounters during downtime
2. **Use Pool Defaults** - Configure your core team in Pool Defaults to save time
3. **Share Configs** - Export and share standard strategies with your raid team
4. **Use Auto Assign** - Let the addon fill basic roles, then fine-tune manually
5. **Test Announcements** - Use `/say` to test announcement formatting before raid night
6. **Validate SR+ Regularly** - Check SR+ Validation before each raid to flag suspicious increases
7. **Use Auto-Invites** - Click "Invite All" from solo state, addon handles party-to-raid conversion

### For Officers

1. **Import Leader Configs** - Get standardized encounter setups via Share system
2. **Customize Pools** - Adjust player pools for your raid group composition
3. **Save Backups** - Export configurations periodically as backups
4. **Monitor SR+ Changes** - Use SR+ Validation to track soft-reserve changes over time
5. **Review Validation History** - Check previous validations to investigate SR+ progression

### For Players

1. **Respond to Polls Quickly** - Watch for "[ROLE] put + in raid chat" messages
2. **Type "+" to Sign Up** - Simple plus sign in raid chat assigns you to role
3. **Listen for Announcements** - Pay attention to raid chat for automated callouts
4. **Accept Raid Invites** - Watch for automatic invites from Raid Invites system

---

---

## Credits

- **Author:** Gnuzmas
- **Community:** OG Guild on Turtle WoW

---

## Version History

**2.0.x** 
- Total overhaul of how I store data.
- Total overhaul of how I sync data.
- Total overhaul of how invites system works.
- Total overhaul of BigWigs integration.
- Total overhaul of Consume Tracking.
- In case you missed it - this was a big one... I totally overhauled a lot.

**1.8.1** 
- Added "Trade Settings" option to minimap menu for configuring trade items
- Enhanced Addon Audit system:
  - Added TWThreat addon detection and version checking
  - Fixed Lua 5.0 compatibility issues (replaced % operator with math.mod)
  - Improved window mutual exclusion for Trade Settings
- Fixed: Trade Settings window was inaccessible from menu

**1.8.0**
- Added Addon Audit window to check which raid members have specific addons installed
  - BigWigs version detection and comparison
  - TWThreat version detection and comparison
  - Visual list of players with/without target addon
  - Version display for installed addons
  - Offline player detection
  - Refresh button for re-querying
  - Accessible via minimap menu "Audit Addons"

**1.7.3**
- Fixed: Encounter nav button on main UI now displays saved raid/encounter on addon load
- Fixed: Previous/Next navigation buttons now properly enable/disable based on saved state
- Fixed: UpdateEncounterNavButton now checks saved variables when frame doesn't exist yet

**1.7.2**
- **Refactored:** Removed legacy "BWL" naming from encounter window functions and frame names
  - `OGRH.ShowBWLEncounterWindow` → `OGRH.ShowEncounterWindow`
  - `OGRH_BWLEncounterFrame` → `OGRH_EncounterFrame`
- **NEW:** Selected raid and encounter now persist between sessions
  - Automatically restores last selected raid/encounter when opening Encounter Planning
  - Saves selection when clicking raids, encounters, or using navigation buttons

**1.7.1**
- Fixed: Encounter Planning window now properly closes SR+ Validation and Share windows
- Fixed: Encounter button on main UI now opens Encounter Planning window consistently
- Fixed: Removed "No raid selected" error when opening Encounter Planning without a selected raid

**1.7.0**
- **NEW:** Raid Invites system with RollFor integration
  - Display all soft-reserve players with SR+ values
  - Invite individual or all online players
  - Auto-conversion from solo → party → raid
  - Automatic invite continuation after raid forms
  - Online/offline status indicators
  - Class-colored player names
- **NEW:** SR+ Validation system for audit tracking
  - Track SR+ changes over time per player
  - Automatic flagging of suspicious increases (>10)
  - Complete item history in validation records
  - Visual indicators (green/red) for validation status
  - Expected value display for validation errors
  - Red markers on items with SR+ increases
  - Duplicate prevention and auto-purge features
  - Debug command `/ogrhsr` for data inspection
- **NEW:** RollFor dependency for soft-reserve data
- Added comprehensive documentation with images
- Fixed: Raid invites now work from solo state
- Fixed: Event handling for automatic party-to-raid conversion

**1.14.0**
- Added Trade system with dynamic item configuration
- Added Share system for configuration export/import
- Added trade items to Share data
- Improved announcement tag system with conditional blocks
- Enhanced Roles UI with single-role polling
- Added assignment numbers support
- **NEW:** Minimized window encounter navigation controls (Previous, Announce, Mark, Next)
- **NEW:** Mark Players button with AutoMarker fallback support
- **NEW:** Player Selection dialog with filter dropdown (All/Pool/Tanks/Healers/Melee/Ranged)
- **NEW:** Right-click rename for raids and encounters in Setup window
- **NEW:** Search/filter box in Pool Defaults window
- **NEW:** Announcement tags: `[Rx.P]` (all players in role) and `[Rx.A=y]` (players with assignment number)
- **NEW:** Independent column layout (eliminates whitespace between unequal columns)
- **NEW:** Role ordering fixes for consistent tag mapping
- Fixed: Pool selection now shows correct role's pool
- Fixed: Mark Players now applies marks to all roles (not just R1)
- Fixed: Announcement role ordering now matches visual display order
- Changed: Role defaults from checkboxes to radio buttons (single selection)

**Earlier Versions:**
- Poll system implementation
- Encounter management system
- Role assignment system
- Initial release

---

## License

See [LICENSE](LICENSE) file for details.

---

## Support

For bugs, feature requests, or questions:
- In-game: Contact Gnuzmas on Turtle WoW
- GitHub: Submit an issue.

---

