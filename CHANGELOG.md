# OG-RaidHelper Changelog

## Version 1.9.0 - Raid Lead System
**Release Date:** November 20, 2025

### Major Features
- **Raid Lead System**: Coordinate encounter planning across your raid with designated raid lead
  - Right-click Sync button to poll addon users and select a raid lead
  - Only raid leaders and assistants can initiate polls and be selected as raid lead
  - Designated raid lead automatically syncs changes to all raid members
  - Permission system prevents non-leads from editing assignments while in raid
  - Automatic query for current raid lead when joining a raid
  - Raid lead cleared when leaving raid to allow solo editing

### Sync Improvements
- Drag/drop player assignments now automatically broadcast to raid (raid lead only)
- Assignment updates bypass sync lock when coming from designated raid lead
- Full encounter sync updates bypass sync lock when from designated raid lead
- Sync button tooltip shows current raid lead
- Left-click sync broadcasts current encounter (raid lead only)
- Left-click sync requests update from raid lead (non-leads)

### Permission Controls
- Auto-Assign button restricted to raid lead
- Drag/drop functionality restricted to raid lead
- Right-click clear assignment restricted to raid lead
- Edit Role button restricted to raid lead
- Edit unlock button restricted to raid lead
- Announcement edit boxes only unlockable by raid lead
- All restrictions lifted when not in raid for solo planning

### UI Enhancements
- Select Raid Lead dialog with class-colored player names
- Current raid lead highlighted with green background
- Player list shows raid rank indicators (L for Leader, A for Assistant)
- Compact dialog styling matching addon's visual standards
- Proper spacing and margins for improved readability

### Technical Improvements
- Added RAID_LEAD_QUERY message for discovering current lead
- Added RAID_LEAD_SET message for broadcasting lead changes
- RAID_ROSTER_UPDATE event handling for automatic state management
- Class color caching system for Select Raid Lead dialog
- Automatic cleanup of raid lead state when leaving raid

### Bug Fixes
- Fixed sync system to respect raid lead permissions
- Fixed edit controls to properly check permissions before allowing actions
- Fixed assignment broadcasts to only send from designated raid lead
- Fixed poll system to only include players with proper raid rank

---

## Version 1.8.5
**Release Date:** Prior Release

### Bug Fixes
- Fixed invite auto-convert to only trigger within 60s of clicking Invite All
