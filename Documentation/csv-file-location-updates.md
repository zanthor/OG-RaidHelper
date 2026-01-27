# CSV File Location Updates

## Purpose
This document maps data fields to their primary file locations for the v1-to-v2 migration CSV.

## File Location Mappings

### Roster Management
- `.class` → Configuration/Roster.lua:1130 (auto-populated from UnitClass)
- `.lastUpdated` → Configuration/Roster.lua:1156,1686 (auto-set via time())
- `.config` → Configuration/Roster.lua:82-105 (EnsureSV initialization)
- `.syncMeta` → Configuration/Roster.lua:82-105 (sync metadata structure)
- `.rankingHistory` → Configuration/Roster.lua:82-105 (historical rankings)

### Roles Assignment
- `OGRH_SV.roles[playerName]` → Raid/RolesUI.lua:794,818 (player role bucket assignments)

### Consume Tracking
- `.history[idx]` → Configuration/ConsumesTracking.lua (consume tracking events)
- `.trackingProfiles` → Configuration/ConsumesTracking.lua (tracking profiles)
- `.pullTriggers` → Configuration/ConsumesTracking.lua (pull detection triggers)
- `.conflicts` → Configuration/ConsumesTracking.lua (conflict resolution data)
- `.weights` → Configuration/ConsumesTracking.lua (item weight values)
- `.enabled` → Configuration/ConsumesTracking.lua (global enable flag)
- `.trackOnPull` → Configuration/ConsumesTracking.lua (track on pull detection)
- `.maxEntries` → Configuration/ConsumesTracking.lua (max history entries)
- `.roleMapping` → Configuration/ConsumesTracking.lua (role to category mapping)
- `.mapping` → Configuration/ConsumesTracking.lua (item to category mapping)
- `.secondsBeforePull` → Configuration/ConsumesTracking.lua (pull window timing)
- `.logToMemory` → Configuration/ConsumesTracking.lua (memory logging flag)
- `.logToCombatLog` → Configuration/ConsumesTracking.lua (combat log output flag)

### UI State
- `ui.minimized` → UI/MainUI.lua (minimize state)
- `ui.hidden` → UI/MainUI.lua (visibility state)
- `ui.locked` → UI/MainUI.lua (lock state)
- `ui.point` → UI/MainUI.lua (anchor point)
- `ui.relPoint` → UI/MainUI.lua (relative anchor point)
- `ui.x` → UI/MainUI.lua (x position)
- `ui.y` → UI/MainUI.lua (y position)
- `ui.selectedRaid` → UI/MainUI.lua (currently selected raid)
- `ui.selectedEncounter` → UI/MainUI.lua (currently selected encounter)

### Roles UI State
- `rolesUI.point` → Raid/RolesUI.lua (window anchor)
- `rolesUI.relPoint` → Raid/RolesUI.lua (window relative anchor)
- `rolesUI.x` → Raid/RolesUI.lua (window x position)
- `rolesUI.y` → Raid/RolesUI.lua (window y position)

### Permissions
- `Permissions.adminHistory[idx]` → Infrastructure/Permissions.lua (admin change history)
- `Permissions.permissionDenials` → Infrastructure/Permissions.lua (denied operation log)

### Versioning
- `Versioning.globalVersion` → Infrastructure/Versioning.lua (global version counter)
- `Versioning.encounterVersions` → Infrastructure/Versioning.lua (per-encounter versions)
- `Versioning.assignmentVersions` → Infrastructure/Versioning.lua (assignment versions)

### Invites
- `.history[idx]` → Configuration/Invites.lua (invite history)
- `.autoSortEnabled` → Configuration/Invites.lua (auto-sort after invite)
- `.declinedPlayers` → Configuration/Invites.lua (players who declined)
- `.currentSource` → Configuration/Invites.lua (RollFor/RaidHelper source)
- `.invitePanelPosition` → Configuration/Invites.lua (panel position)

### Recruitment
- `.contacts` → Administration/Recruitment.lua:33 (contact tracking - deprecated, use whisperHistory)
- `.deletedContacts` → Administration/Recruitment.lua:36,52 (explicitly deleted contacts)
- `.playerCache` → Administration/Recruitment.lua:35,49 (cached player info)
- `.enabled` → Administration/Recruitment.lua:25 (recruitment enabled flag)
- `.lastAdTime` → Administration/Recruitment.lua:32 (last advertisement timestamp)
- `.autoAd` → Administration/Recruitment.lua:37 (auto-advertise flag)

### Consumables
- `consumes[idx]` → Core/Core.lua (consumable item definitions)
- `consumes[idx].primaryName` → Core/Core.lua (item primary name)

### Auto-Promotes
- `autoPromotes[idx]` → Configuration/Promotes.lua (auto-promote list)
- `autoPromotes[idx].name` → Configuration/Promotes.lua (player name)
- `autoPromotes[idx].class` → Configuration/Promotes.lua (player class)

### Sort Order
- `order.HEALERS` → Raid/RolesUI.lua (healer sort order)
- `order.TANKS` → Raid/RolesUI.lua (tank sort order)
- `order.MELEE` → Raid/RolesUI.lua (melee sort order)
- `order.RANGED` → Raid/RolesUI.lua (ranged sort order)

### Minimap
- `minimap.angle` → Core/Core.lua:5173,5177,5540 (minimap button position angle)

### Player Assignments
- `playerAssignments[playerName]` → Raid/EncounterMgmt.lua (player to encounter assignments)

### Sorting
- `sorting.speed` → Raid/RolesUI.lua (sort animation speed)

### Global Flags
- `monitorConsumes` → Core/Core.lua (consume monitoring flag)
- `raidLead` → Core/Core.lua (raid leader name)
- `allowRemoteReadyCheck` → Core/Core.lua (allow remote ready checks)
- `firstRun` → Core/Core.lua (first run flag)
- `syncLocked` → Core/Core.lua (sync lock flag)
- `pollTime` → Core/Core.lua (poll interval)

### Sort Order Paths
- `OGRH_SV.encounterMgmt.raids[raidName].sortOrder` → Raid/EncounterSetup.lua (raid drag/drop reorder)
- `OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].sortOrder` → Raid/EncounterSetup.lua (encounter drag/drop reorder)

### Advanced Settings Parent Paths
- `.advancedSettings` → Raid/AdvancedSettings.lua:52-100 (advanced settings initialization)
- `.consumeTracking` → Raid/AdvancedSettings.lua:60-72 (consume tracking parent)
- `.bigwigs` → Raid/AdvancedSettings.lua:80-92 (BigWigs settings parent)

### Announcement Fields
- `.enabled` → Raid/EncounterMgmt.lua (announcement enabled flag)
- `.channel` → Raid/EncounterMgmt.lua (announcement channel)

## Notes Column Migration

Move these generic descriptions from File Location to Notes:
- "unchanged" → (keep in Notes, find actual file location)
- "preserved" → (keep in Notes, find actual file location)
- "settings" → (keep in Notes, find actual file location)
- "structure" → (keep in Notes, find actual file location)
- "mapping" → (keep in Notes, find actual file location)
