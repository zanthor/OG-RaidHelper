All changes are implemented. Here's a summary of what was done across 4 files:

Changes Summary
Permissions.lua

Added lastAdmin field to Permissions.State (persisted via SV)
SetRaidAdmin() now accepts skipLastAdminUpdate parameter — updates lastAdmin by default, skips for Tier 4 temp assignments
SetRaidAdmin() tracks admin's raid rank in AdminDiscovery.lastAdminRank for demotion detection
Added OGRH.GetLastAdmin() getter
PollForRaidAdmin() now delegates to AdminDiscovery.Start()
Permissions.Initialize() no longer auto-assigns leader as admin — clears currentAdmin on load, preserves lastAdmin from SV, defers to discovery system
AdminSelection.lua

Added OGRH.AdminDiscovery module with Start(), Cancel(), AddResponse(), Resolve()
3-tier resolution: lastAdmin → Leader → Assistant (alphabetical) → any OGRH user (alphabetical, temp)
Start(): 5s passive listen → broadcast ADMIN.QUERY → 5s collect → resolve
InitRaidLead() rewritten with consolidated RAID_ROSTER_UPDATE handler:
Leave (>0→0): Cancel discovery, clear admin, preserve lastAdmin
Join (0→>0): Start discovery
Mid-raid demotion: If admin's rank drops from ≥1 to 0, clear admin + re-discover
QueryRaidAdmin() now delegates to AdminDiscovery.Start()
MessageRouter.lua

Fixed critical bug: ADMIN.QUERY handler was being overwritten by SyncIntegrity, breaking admin discovery
New unified ADMIN.QUERY handler: delegates checksum requests to SyncIntegrity, AND has ALL OGRH clients respond with roll-call (staggered 0-2s random delay)
New ADMIN.RESPONSE handler: feeds into AdminDiscovery when active, short-circuits on admin claim, keeps legacy compat
SyncIntegrity.lua

Removed duplicate RAID_ROSTER_UPDATE handler and OnRaidRosterUpdate() function
Removed duplicate ADMIN.QUERY handler registration from Initialize() (now unified in MessageRouter)
StartIntegrityChecks(): Added guard against double-start + 5-second delay before first checksum broadcast
Added proper StopIntegrityChecks() function
Added global aliases OGRH.StartIntegrityChecks / OGRH.StopIntegrityChecks (were previously undefined, called by Permissions.lua)
CheckAdminStatus() now uses StopIntegrityChecks() instead of inline timer cleanup
Edge Cases Covered
Admin DC: No auto-reassign. When admin reconnects, discovery finds them via lastAdmin
Admin demotion: Detected via rank tracking, triggers re-discovery
Tie-break: Alphabetical, deterministic across all clients
Reload mid-raid: Treated as join → discovery runs
Leave during discovery: Timers cancelled, process abandoned
Multiple simultaneous joiners: All broadcast responses, all independently arrive at same deterministic result

Core.lua 
Removed entirely:

PLAYER_ENTERING_WORLD: The StartIntegrityChecks call was dead code (we now clear currentAdmin on init, so GetRaidAdmin() always returns nil at that point). The deprecated field cleanup moved into ADDON_LOADED/VARIABLES_LOADED where it belongs.
RAID_ROSTER_UPDATE: Was only tracking hasPolledOnce, which nothing reads anymore.
Unregistered both events from the frame and removed the hasPolledOnce variable.