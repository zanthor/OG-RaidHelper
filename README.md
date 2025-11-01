# OG-RaidHelper

**Version:** 1.14.0  
**Author:** Gnuzmas  
**Compatible with:** World of Warcraft 1.12.1 (Vanilla / Turtle WoW)

A comprehensive raid management addon for organizing encounters, assigning roles, managing trade distributions, and coordinating raid activities.

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Main Window](#main-window)
- [Roles Window](#roles-window)
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
3. You should see the OG-RaidHelper main window on your screen
4. Seriously, skip all this and use the GIT Addon manager.

---

## Quick Start

1. **Access Main UI**: The small main window appears on login or type `/ogrh`
2. **Open Roles Window**: Click the **Roles** button to manage your raid composition
3. **Poll for Roles**: Use the **Poll** button to request players sign up via raid chat
4. **Setup Encounters**: Click **Encounters** → **Manage** to access encounter planning
5. **Trade Items**: Use the **Trade** button to set up and distribute items to raid members
6. **Share Configs**: Click **Share** to export/import your encounter and trade configurations

---

## Main Window

The compact main window provides quick access to all major features.

### Window Controls

Located in the title bar:
- **RC** - Performs a Ready Check (left-click), or toggle remote ready checks on/off (right-click)
- **Announce** - Sends the current encounter's announcement to raid chat
- **-** - Minimize/expand window
- **L** - Lock/unlock window position (drag to move when unlocked)

### Main Buttons

- **Roles** - Opens the [Roles Window](#roles-window) for managing raid composition
- **Encounters** - Opens a dropdown menu with encounter options:
  - **Manage** - Opens [Encounter Planning](#encounter-planning-window)
  - **Setup Raids** - Opens [Encounter Setup](#encounter-setup-window)
- **Trade** - Opens dropdown menu with trade item options (see [Trade System](#trade-system))
- **Share** - Opens [Share Window](#share-system) to export/import configurations

**Window Position:** Drag the window by its title bar when unlocked. Position is automatically saved.

---

## Roles Window

The Roles Window displays your raid composition organized into four columns: **Tanks**, **Healers**, **Melee**, and **Ranged**.

### Window Features

- **Alphabetical Display** - Players are automatically sorted A-Z within each role
- **Class Colors** - Player names are colored by their class
- **Drag and Drop** - Click and drag players between role columns to reassign them
- **Persistent Storage** - Role assignments are saved to `OGRH_SV.roles`

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
- Players who respond with "+" are automatically added to the requested role
- Players are moved from their current role if already assigned elsewhere
- Names appear in the role column as they respond
- You can manually drag/drop players between columns after polling

---

## Encounters System

The Encounters system provides comprehensive tools for pre-planning raid encounters with role assignments, player pools, raid marks, and automated announcements.

### Encounter Planning Window

Access via **Encounters** → **Manage** from the main window.

#### Window Layout

**Left Panel: Raids & Encounters**
- Displays a hierarchical list of raids and their encounters
- Click **Add Raid** to create a new raid category (e.g., "MC", "BWL", "K40")
- Click **Add Encounter** (when a raid is selected) to add an encounter
- Click a raid name to manage its encounters
- Click an encounter name to load its configuration in the right panels
- Right-click raids or encounters to rename/delete them

**Middle Panel: Player Pool Management**
- Shows available players for each role required by the encounter
- Four default pools: Tanks, Healers, Melee, Ranged (customizable via Pool Defaults)
- **Pool Defaults Button** (top-left) - Configure default players for all encounters
- Add players by typing names (comma-separated) or using the guild roster
- Role filter dropdown to show only players of specific roles
- Drag players from guild list to pool, or from pool to assignments

**Right Panel: Encounter Configuration**
- **Roles Tab** - Design the encounter's role structure
- **Assignments Tab** - Assign specific players to roles
- **Announcements Tab** - Create automated announcements with [tag support](#announcement-tags)

#### Creating an Encounter

1. Click **Add Raid** (bottom-left), enter raid name (e.g., "BWL")
2. Select the raid, then click **Add Encounter**, enter encounter name (e.g., "Razorgore")
3. Click the encounter to load it

#### Roles Tab

Design the encounter's role requirements:

- **Two-column layout** - Organize roles into left and right columns
- **Add Role** buttons at bottom of each column
- **Role Button Controls**:
  - **Text** - Role name (click to rename)
  - **Up/Down Arrows** - Reorder roles within column
  - **Delete (X)** - Remove role
  - Drag roles between columns

**Editing a Role** (click role to open edit window):
- **Role Name** - Descriptive name (e.g., "Main Tank", "Orb Controller")
- **Player Slots** - Number of players needed (1-15)
- **Default Player Roles** - Which pools to draw from:
  - ☑ Tanks
  - ☑ Healers
  - ☑ Melee
  - ☑ Ranged
  - ☑ DPS (generic DPS)
- **Allow Other Roles** - If checked, players from non-default pools can be manually assigned
- **Show Raid Icons** - Display raid mark buttons next to assigned players
- **Mark Player by Default** - Automatically assign raid marks to players
- **Show Assignment Numbers** - Display assignment number controls (1-9)

#### Assignments Tab

Assign players to the roles you designed:

**Layout:**
- Left side: Role containers matching your role design
- Each role shows slots for the number of players configured
- Empty slots show as gray placeholders
- Assigned players appear with their name and class color

**Assigning Players:**
1. Ensure players are in the appropriate pools (middle panel)
2. Drag a player from the pool to an empty slot in a role
3. Or click **Auto Assign** to automatically fill all roles from pools

**Player Controls** (when assigned):
- **Raid Mark Icons** (if enabled for role) - Click to assign marks (Star, Circle, Diamond, etc.)
- **Assignment Number** (if enabled for role) - Click to cycle through numbers 1-9
  - Left-click: Increment
  - Right-click: Decrement
- **Remove (X)** - Remove player from assignment

**Auto Assign:**
- Click **Auto Assign** button (bottom-left of right panel)
- Automatically fills all roles from their configured player pools
- Uses default roles settings to match players to slots
- Manual assignments override auto-assignments

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

This is an alternative interface for managing the same encounter data with a different workflow. Both interfaces modify the same saved configuration.

#### Window Layout

**Left Panel: Raids List**
- Scrollable list of raids
- Click a raid to load its encounters

**Middle Panel: Encounters List**
- Shows encounters for selected raid
- Click encounter to load its role configuration

**Right Panel: Role Configuration**
- Add/edit/delete roles for selected encounter
- Configure role properties
- Two-column layout similar to Encounter Planning window

**Note:** Changes made in either the Encounter Planning or Encounter Setup window are synchronized as they modify the same underlying data structure.

### Pool Defaults Window

Configure default player pools used for all encounters:

Access via **Pool Defaults** button in Encounter Planning window.

**Four Default Pools:**
1. Tanks
2. Healers
3. Melee
4. Ranged

**Managing Pools:**
- Add players to each pool (comma-separated or one per line)
- These defaults are used as starting pools for new encounters
- Individual encounter pools can be customized independently

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

## Share System

The Share system allows you to export and import all your configurations to share with other raid leaders or backup your settings.

### Share Window

Access via **Share** button on main window.

**What is Shared:**
- Encounter Management (raids, encounters, role designs)
- Player Pool Defaults
- Encounter Player Pools (custom pools per encounter)
- Encounter Assignments (player assignments to roles)
- Encounter Raid Marks
- Encounter Assignment Numbers
- Encounter Announcements (all announcement text)
- Trade Items (configured trade items and quantities)

**Layout:**
- Large text box for export/import data
- **Export** button - Generates shareable string
- **Import** button - Loads configuration from string
- **Clear** button - Clears text box
- **Close** button

### Exporting Configuration

1. Click **Share** button
2. Click **Export** button
3. Copy the generated text from the text box (Ctrl+C)
4. Share via Discord, paste into a text file, etc.

**What Gets Exported:**
- All raids and encounters
- All role designs for each encounter
- All player assignments
- All raid marks and assignment numbers
- All announcement templates
- All trade item configurations

### Importing Configuration

1. Obtain a shared configuration string
2. Click **Share** button
3. Paste the string into the text box (Ctrl+V)
4. Click **Import** button
5. Success message appears
6. All windows refresh with imported data

**Important Notes:**
- Import **overwrites** existing data with the same names
- Existing encounters not in the import are **preserved**
- Any open encounter windows will refresh automatically
- Trade Settings window refreshes if open

**Use Cases:**
- Share raid strategies with co-raid-leaders
- Backup configurations before major changes
- Transfer settings between characters
- Distribute standard encounter setups to multiple officers

---

## Poll System

The Poll system automates role signups via raid chat.

### How Polling Works

**Sequential Poll (All Roles):**
1. Click **Poll** button in Roles Window
2. Sends: "TANKS put + in raid chat."
3. Listens for "+" responses in raid chat
4. Adds responding players to Tanks
5. After 10 seconds, advances to next role: "HEALERS put + in raid chat."
6. Continues through all four roles (Tanks → Healers → Melee → Ranged)

**Single Role Poll:**
1. Click a role column header (e.g., "Healers")
2. Sends: "HEALERS put + in raid chat."
3. Listens for "+" responses
4. Adds responding players to Healers
5. Continues until you click the header again or click Poll to cancel

**Player Behavior:**
- Responding with "+" adds player to the requested role
- Players already in another role are **moved** to the new role
- Players appear in real-time as they respond
- Poll can be canceled at any time by clicking Poll button or role header

**Roster Synchronization:**
- Poll system monitors `RAID_ROSTER_UPDATE` events
- Automatically refreshes player list when raid changes
- Players who leave raid are removed from roles

---

## Slash Commands

Type commands in chat to control the addon:

### Main Commands

- `/ogrh` or `/rh` - Show/hide main window
- `/ogrh sand` - Legacy: Execute sand trade (if configured)

### Additional Features

- **Minimap Button** - Drag to reposition on minimap (if enabled)
- **Ready Check** - RC button on main window title bar

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

### For Officers

1. **Import Leader Configs** - Get standardized encounter setups via Share system
2. **Customize Pools** - Adjust player pools for your raid group composition
3. **Save Backups** - Export configurations periodically as backups

### For Players

1. **Respond to Polls Quickly** - Watch for "[ROLE] put + in raid chat" messages
2. **Type "+" to Sign Up** - Simple plus sign in raid chat assigns you to role
3. **Listen for Announcements** - Pay attention to raid chat for automated callouts

---

## Troubleshooting

**Roles Window not loading:**
- Type `/reload` to reload UI
- Check for Lua errors (if you have an error display addon)

**Players not appearing in pools:**
- Ensure players are in your raid group
- Check role filter dropdown is set to correct role or "all"

**Trade items not working:**
- Verify Item ID is correct
- Ensure you have items in your bags
- Open trade window before clicking OGRH button

**Import fails:**
- Ensure entire export string was copied (very long string)
- Check for missing characters at beginning/end
- Try exporting from source again

**Encounter assignments not saving:**
- Ensure you clicked out of text fields before closing windows
- Type `/reload` to save and reload

---

## SavedVariables Structure

The addon stores data in `OGRH_SV` (saved per character):

```lua
OGRH_SV = {
  roles = {}, -- Player role assignments
  encounterMgmt = {}, -- Raid/encounter structure
  poolDefaults = {}, -- Default player pools
  encounterPools = {}, -- Per-encounter player pools
  encounterAssignments = {}, -- Player assignments to roles
  encounterRaidMarks = {}, -- Raid mark assignments
  encounterAssignmentNumbers = {}, -- Assignment numbers
  encounterAnnouncements = {}, -- Announcement templates
  tradeItems = {}, -- Trade item configurations
  ui = {} -- Window positions
}
```

**Backup:** Manually copy `WTF\Account\[Account]\[Server]\[Character]\SavedVariables\OG-RaidHelper.lua`

---

## Credits

- **Author:** Gnuzmas
- **Contributors:** ChatGPT (code assistance)
- **Community:** OG Guild on Turtle WoW

---

## Version History

**1.14.0** (Current)
- Added Trade system with dynamic item configuration
- Added Share system for configuration export/import
- Added trade items to Share data
- Improved announcement tag system with conditional blocks
- Enhanced Roles UI with single-role polling
- Added assignment numbers support

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
- GitHub: Submit an issue (if repository is public)

---

**Happy Raiding!**
