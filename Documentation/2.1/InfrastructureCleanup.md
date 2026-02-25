# `_Infrastructure/` Audit Report

**Date:** 2025-02-25  
**Scope:** All 18 files in `_Infrastructure/`  
**Method:** Cross-referenced every export against the full OG-RaidHelper codebase (TOC, `_Core/`, `_Raid/`, `_UI/`, `_Configuration/`, `_Administration/`, `_Modules/`, `_Tests/`)

---

## Summary Table

| # | File | Lines | In TOC | Status | External Consumers |
|---|------|-------|--------|--------|-------------------|
| 1 | DataManagement.lua | 890 | YES | **ACTIVE** | Core.lua |
| 2 | DataManagement_v1.lua | 842 | **NO** | **DEAD** | None |
| 3 | DataManagement_v2.lua | ~200 | **NO** | **DEAD** | None |
| 4 | MessageRouter.lua | 862 | YES | **ACTIVE** | 7+ files |
| 5 | MessageTypes.lua | ~300 | YES | **ACTIVE** | 6+ files |
| 6 | Migration.lua | 2710 | YES | **ACTIVE** (transitional) | Core.lua |
| 7 | MigrationMap.lua | 1780 | YES | **ACTIVE** (coupled) | Migration.lua |
| 8 | Permissions.lua | 488 | YES | **ACTIVE** (critical) | 9+ files |
| 9 | SyncChecksum.lua | 1211 | YES | **ACTIVE** | 5+ files |
| 10 | SyncGranular.lua | 1268 | YES | **ACTIVE** | Infra-only |
| 11 | SyncIntegrity.lua | 1255 | YES | **ACTIVE** | 7+ files |
| 12 | SyncMode.lua | 371 | YES | **ACTIVE** | 2 external |
| 13 | SyncRepair.lua | 902 | YES | **ACTIVE** | SyncRepairHandlers |
| 14 | SyncRepairHandlers.lua | 1047 | YES | **ACTIVE** | 3 infra files |
| 15 | SyncRepairUI.lua | 1073 | YES | **ACTIVE** | 2 infra files |
| 16 | SyncRouter.lua | ~300 | YES | **ACTIVE** | 1 infra + tests |
| 17 | SyncSession.lua | 605 | YES | **ACTIVE** | 3+ files |
| 18 | Versioning.lua | 679 | YES | **ACTIVE** | 4 infra files |

---

## Immediate Removals (Dead Code)

| File | Lines | Reason |
|------|-------|--------|
| `DataManagement_v1.lua` | ~842 | Not in TOC. Legacy pre-SVM version superseded by current `DataManagement.lua`. **Safe to delete.** |
| `DataManagement_v2.lua` | ~200 | Not in TOC. Incomplete intermediate draft. **Safe to delete.** |

---

## Transitional Code (Retire After Full v2 Migration)

| File | Lines | Consumers |
|------|-------|-----------|
| `Migration.lua` | 2710 | `Core.lua` only |
| `MigrationMap.lua` | 1780 | `Migration.lua` only |

These two files total **~4,490 lines** of v1→v2 schema migration. They run on every addon load. Once all guild members are on v2 schema, both can be stubbed to a no-op and eventually removed.

`MigrationMap.lua` uses `_G.OGRH_MIGRATION_MAP` (a global) instead of the `OGRH` namespace — the only file doing this.

---

## Infrastructure-Only Files (No External Consumers)

These 6 files are consumed **only by sibling `_Infrastructure/` files** (and tests). They form a closed sync repair subsystem:

| File | Lines | What It Does | Consumed By |
|------|-------|-------------|------------|
| `SyncGranular.lua` | 1268 | Component-level sync queue | Self-referential only; exports `OGRH.DeepCopy` |
| `SyncRepair.lua` | 902 | Packet builder/applicator | `SyncRepairHandlers` only |
| `SyncRepairHandlers.lua` | 1047 | Repair lifecycle orchestration | `SyncIntegrity`, `SyncRepairUI`, `SyncSession` |
| `SyncRepairUI.lua` | 1073 | Repair progress panels | `SyncRepairHandlers`, `SyncSession` |
| `SyncRouter.lua` | ~300 | Context-aware routing | `SyncSession` only (+ tests) |
| `Versioning.lua` | 679 | Data version tracking | `MessageRouter`, `Permissions`, `SyncSession` |

These aren't dead — they're needed for the sync system — but they could potentially be **consolidated** (e.g., `SyncRepair` + `SyncRepairHandlers` merged; `SyncRouter` absorbed into `SyncSession`).

---

## Actively Used Outside Infrastructure

These files have consumers in `_Raid/`, `_UI/`, `_Core/`, or `_Configuration/`:

| File | Lines | External Consumer Count | Key External Users |
|------|-------|------------------------|-------------------|
| `Permissions.lua` | 488 | **9+ files** | `EncounterMgmt`, `EncounterSetup`, `MainUI`, `BigWigs`, `BuffManager`, `Invites` |
| `MessageRouter.lua` | 862 | **7+ files** | `EncounterAdmin`, `EncounterMgmt`, `MainUI`, `ReadynessDashboard`, `Core` |
| `MessageTypes.lua` | ~300 | **6+ files** | Same consumers as `MessageRouter` |
| `SyncIntegrity.lua` | 1255 | **4+ files** | `EncounterMgmt`, `MainUI`, `SavedVariablesManager`, `Invites` |
| `SyncSession.lua` | 605 | **2 files** | `EncounterMgmt` (`IsUILocked`), `EncounterSetup` (10+ guard checks) |
| `SyncChecksum.lua` | 1211 | **2 files** | `SavedVariablesManager`, `Core` (`Serialize`/`Deserialize`/`DeepCopy`) |
| `SyncMode.lua` | 371 | **1 file** | `EncounterMgmt` (11 references) |
| `DataManagement.lua` | 890 | **1 file** | `Core.lua` (via `OGRH.Sync.*` aliases) |

---

## Detailed Per-File Analysis

### 1. DataManagement.lua — ACTIVE

- **Exports:** `OGRH.DataManagement.{LoadDefaults, ExportData, ImportData, ShowWindow, InitiatePushStructure, StartPushStructurePoll, HandlePushPollResponse, RefreshAllWindows, GetCurrentChecksum, GetDefaultsChecksum, ...}` plus backward-compat aliases: `OGRH.Sync.LoadDefaults`, `OGRH.Sync.BroadcastFullSync`, `OGRH.Sync.ShowDataManagement`, `OGRH.Sync.ExportData`, `OGRH.Sync.ImportData`
- **External consumers:** `Core.lua` calls `OGRH.Sync.LoadDefaults()` and `OGRH.Sync.BroadcastFullSync()`
- **Notes:** Uses SVM (SavedVariablesManager) for schema-independent data access. External code exclusively uses the `OGRH.Sync.*` aliases, never `OGRH.DataManagement.*` directly. Could theoretically live in `_Core/` since it's a user-facing data management UI, but its deep use of sync infrastructure makes `_Infrastructure/` a reasonable home.

### 2. DataManagement_v1.lua — DEAD CODE

- **Exports:** Same `OGRH.DataManagement.*` namespace (would collide if loaded)
- **External consumers:** None — not in TOC, never loaded
- **Notes:** Legacy pre-SVM version. Writes directly to `OGRH_SV.*` instead of using SavedVariablesManager. References `OGRH.Versioning.ComputeChecksum` for defaults checksum. **Safe to delete.**

### 3. DataManagement_v2.lua — DEAD CODE

- **Exports:** Same `OGRH.DataManagement.*` namespace
- **External consumers:** None — not in TOC, never loaded
- **Notes:** Incomplete intermediate draft (~200 lines, file appears truncated). Accesses `OGRH_SV.v2.*` directly. Superseded by the current `DataManagement.lua` which uses SVM. **Safe to delete.**

### 4. MessageRouter.lua — ACTIVE (critical)

- **Exports:** `OGRH.MessageRouter.{Send, SendTo, Broadcast, RegisterHandler, UnregisterHandler, GetHandler, Initialize, InitializeOGAddonMsg, OnMessageReceived, RegisterDefaultHandlers}`, `OGRH.SendAddonMessage` (legacy wrapper)
- **External consumers:**
  - `_Raid/EncounterAdmin.lua` — `RegisterHandler`, `Broadcast`
  - `_Raid/EncounterMgmt.lua` — `RegisterHandler`
  - `_UI/MainUI.lua` — `Initialize`, `RegisterHandler`
  - `_Raid/ReadynessDashboard.lua` — `RegisterHandler`, `Broadcast`
  - `_Core/Core.lua` — `Initialize`
  - Plus internal: `SyncRepairHandlers`, `Permissions`, `SyncMode`, `DataManagement`
- **Notes:** Core communication backbone. Every subsystem depends on it.

### 5. MessageTypes.lua — ACTIVE

- **Exports:** `OGRH.MessageTypes.{STRUCT, ASSIGN, SYNC, ADMIN, STATE, READHELPER, ROLESUI, READYDASH}` (message type constant groups), `OGRH.SYNC_VERSION`, `OGRH.MESSAGE_PREFIX`, `OGRH.GetMessageCategory()`, `OGRH.IsValidMessageType()`, `OGRH.DebugPrintMessageTypes()`
- **External consumers:** Same as MessageRouter (`EncounterAdmin`, `ReadynessDashboard`, `Permissions`, `SyncMode`, `SyncRepairHandlers`, `Core.lua`, `test_phase1.lua`)
- **Notes:** Pure constant definitions. Tightly coupled to `MessageRouter`. Could theoretically merge into `MessageRouter` but current separation is clean.

### 6. Migration.lua — ACTIVE (transitional)

- **Exports:** `OGRH.Migration.{MigrateToV2, ValidateV2, CutoverToV2, RollbackFromV2, MigrateToActiveRaid, ...}` (20+ Compare* functions)
- **External consumers:** `Core.lua` at lines 187, 224, 227, 229, 673, 679 — auto-migration on addon load. `Core.lua` also **overrides** `OGRH.Migration.MigrateToV2` with its own wrapper.
- **Notes:** 2710 lines of CSV-driven v1→v2 migration logic. Transitional code — once all users have migrated to v2 schema, this can be stubbed out. For now, it runs on every addon load to ensure migration.

### 7. MigrationMap.lua — ACTIVE (coupled to Migration.lua)

- **Exports:** `_G.OGRH_MIGRATION_MAP` (global table with 176 field-by-field transformation records)
- **External consumers:** `Migration.lua` only (lines 105–111)
- **Notes:** 1780 lines of embedded generated data (from CSV). Only consumer is `Migration.lua`. Using `_G` global instead of `OGRH` namespace is unusual — the only file that does this.

### 8. Permissions.lua — ACTIVE (critical, most cross-cutting)

- **Exports:**
  - Namespace: `OGRH.Permissions.{ADMIN, OFFICER, MEMBER, State, IsSessionAdmin}`
  - Globals (heavily used): `OGRH.{IsRaidAdmin, IsRaidOfficer, GetPermissionLevel, CanModifyStructure, CanModifyAssignments, CanReadData, SetRaidAdmin, GetRaidAdmin, GetLastAdmin, RequestAdminRole, PollForRaidAdmin, SetSessionAdmin, HandlePermissionDenied}`
- **External consumers (widespread, critical):**
  - `_Raid/EncounterMgmt.lua` — `CanModifyStructure`, `IsRaidAdmin`
  - `_Raid/EncounterSetup.lua` — `CanModifyStructure`, `CanModifyAssignments`
  - `_UI/MainUI.lua` — `IsRaidAdmin`, `GetPermissionLevel`, `DebugPrintRaidPermissions`
  - `_Raid/BigWigs.lua` — `CanModifyAssignments`
  - `_Raid/BuffManager.lua` — `CanModifyStructure`
  - `_Configuration/Invites.lua` — permission checks
  - Plus internal: `SyncIntegrity`, `SyncMode`, `MessageRouter`, `SyncRepairHandlers`
- **Notes:** Most critical infrastructure file. Cannot be relocated.

### 9. SyncChecksum.lua — ACTIVE

- **Exports:**
  - Namespace: `OGRH.SyncChecksum.{HashString, HashRole, Serialize, Deserialize, DeepCopy, CalculateStructureChecksum, CalculateAllStructureChecksum, ComputeRaidStructureChecksum, ComputeEncountersChecksums, ComputeRolesChecksums, ComputeApRoleChecksums, CalculateRolesUIChecksum, ComputeRaidChecksum, ...}`
  - Legacy wrappers: `OGRH.Serialize`, `OGRH.Deserialize`, `OGRH.DeepCopy`
- **External consumers:**
  - `_Core/SavedVariablesManager.lua` — checksum computation
  - `_Core/Core.lua` — `OGRH.Serialize`, `OGRH.Deserialize`
  - Plus internal: `SyncIntegrity`, `SyncRepair`, `test_phase1.lua`
- **Notes:** `OGRH.DeepCopy` is defined both here AND in `SyncGranular.lua`. Since `SyncGranular` loads after `SyncChecksum` in the TOC, `SyncGranular`'s definition wins at runtime.

### 10. SyncGranular.lua — ACTIVE (infra-only)

- **Exports:** `OGRH.SyncGranular.{State, SetContext, ProcessQueue, ExecuteSync, CompleteSyncOperation, RequestComponentSync, SendComponentSync, ReceiveComponentSync, ExtractComponentData, ApplyComponentData, ValidateComponentStructure, RequestEncounterSync, RequestRaidSync, RequestGlobalComponentSync}`, plus `OGRH.DeepCopy()` (global, line 41)
- **External consumers:** `OGRH.SyncGranular.*` is entirely self-referential. **No external consumers** of the namespace. However, `OGRH.DeepCopy` (defined here, overriding `SyncChecksum`'s version) is used by `DataManagement.lua`, `SyncIntegrity.lua`, and self.
- **Notes:** The granular component sync queue system is internal plumbing only. Its most important externally-visible contribution is the `OGRH.DeepCopy` utility.

### 11. SyncIntegrity.lua — ACTIVE

- **Exports:**
  - Namespace: `OGRH.SyncIntegrity.{State, BroadcastChecksums, OnChecksumBroadcast, QueueRepairRequest, OnRepairRequest, FlushRepairBuffer, RepairBuffer, EnterRepairMode, ExitRepairMode, RecordAdminModification, OnAdminQuery}`
  - Globals: `OGRH.StartIntegrityChecks`, `OGRH.StopIntegrityChecks`
- **External consumers:**
  - `_Raid/EncounterMgmt.lua` — `RecordAdminModification`
  - `_UI/MainUI.lua` — `State` checks
  - `_Configuration/Invites.lua` — integrity checks
  - `_Core/SavedVariablesManager.lua` — integration
  - `Permissions.lua` — `StartIntegrityChecks`/`StopIntegrityChecks`
  - Plus internal: `SyncRepairHandlers`, `MessageRouter` (debug flag)
  - Tests: `test_svm.lua`
- **Notes:** Core sync engine. Admin broadcasts checksums every 30s; clients compare and trigger repairs. Deeply integrated.

### 12. SyncMode.lua — ACTIVE

- **Exports:** `OGRH.SyncMode.{State, StartSyncOffBroadcast, StopSyncOffBroadcast, BroadcastSyncOff, BroadcastSyncOn, EnableSync, OnSyncModeOff, OnSyncModeOn, IsSyncEnabled, CanBroadcastChecksum, CanSendDeltaUpdate, CanRequestRepair, Initialize, RegisterHandlers}`
- **External consumers:**
  - `_Raid/EncounterMgmt.lua` — `IsSyncEnabled`, `State.enabled`, `State.isClientWaiting`, `StopSyncOffBroadcast`, `StartSyncOffBroadcast` (11 references)
  - Plus internal: `SyncRepairUI` (`EnableSync`), `SyncIntegrity` (`IsSyncEnabled`)
- **Notes:** Small (371 lines) but important pause/resume mechanism for admin editing.

### 13. SyncRepair.lua — ACTIVE (infra-only)

- **Exports:** `OGRH.SyncRepair.{State, BuildStructurePacket, BuildRolesUIPacket, BuildEncountersPackets, BuildRolesPackets, BuildAssignmentsPackets, DetermineRepairPriority, SendStructurePacket, SendEncountersPackets, ApplyStructurePacket, ApplyRolesUIPacket, ApplyEncountersPacket, ApplyRolesPacket, ApplyAssignmentsPacket, ComputeValidationChecksums, ValidateRepair, UpdateAdaptiveDelay}`
- **External consumers:** `SyncRepairHandlers.lua` only — 16 references (`Build*`, `Apply*`, `DetermineRepairPriority`, `ComputeValidationChecksums`, `ValidateRepair`, `UpdateAdaptiveDelay`, `State`)
- **Notes:** Packet builder/applicator. Single consumer (`SyncRepairHandlers`). Could be merged with `SyncRepairHandlers` but current separation (packet logic vs network orchestration) is clean.

### 14. SyncRepairHandlers.lua — ACTIVE (infra-only)

- **Exports:** `OGRH.SyncRepairHandlers.{InitiateRepair, SendRepairPackets, SendPacketsWithPacing, WaitForCTLDrain, RequestValidation, CheckValidationComplete, CompareValidationChecksums, RetryFailedEncounters, CompleteRepair, OnRepairStart, OnRepairData, RegisterHandlers, currentToken, hasRequestedRepair, skipNextChecksumValidation, repairCompletedAt, waitingForRepair, waitingToken}`
- **External consumers:**
  - `SyncIntegrity.lua` — `InitiateRepair`, `currentToken`, `hasRequestedRepair`, `skipNextChecksumValidation`, `repairCompletedAt`
  - `SyncRepairUI.lua` — `currentToken`, `waitingForRepair`, `waitingToken`
  - `SyncSession.lua` — `currentToken`, `waitingForRepair`, `waitingToken`
- **Notes:** All consumers are within `_Infrastructure/`. Orchestrates the repair lifecycle. The exposed state fields (`currentToken`, `hasRequestedRepair`, etc.) are read/written directly by peer files — a code smell suggesting these should be formalized.

### 15. SyncRepairUI.lua — ACTIVE (infra-only)

- **Exports:** `OGRH.SyncRepairUI.{State, CreateAdminPanel, ShowAdminPanel, HideAdminPanel, ShowWaitingPanel, HideWaitingPanel, ShowClientPanel, HideClientPanel, UpdateAdminProgress, ResetAdminTimeout, ResetClientTimeout}`
- **External consumers:**
  - `SyncRepairHandlers.lua` — Show/Hide/Update panel functions (14 references)
  - `SyncSession.lua` — State access + Hide panel functions
- **Notes:** All consumers are within `_Infrastructure/`. This is a UI file that could arguably live in `_UI/` but it's tightly coupled to the sync repair subsystem.

### 16. SyncRouter.lua — ACTIVE (infra-only)

- **Exports:** `OGRH.SyncRouter.{State, DetectContext, DetermineSyncLevel, ExtractScope, Route, ParsePath, IsActiveRaid, Initialize, BroadcastChange}`
- **External consumers:**
  - `SyncSession.lua` — `BroadcastChange`
  - `_Tests/test_phase1.lua` — `DetectContext`, `DetermineSyncLevel`, `Route`, `ParsePath` (15 references, test-only)
- **Notes:** Context-aware routing (REALTIME/BATCH/MANUAL). Only one production consumer (`SyncSession`). Most of the API surface is only exercised by tests. Low external coupling suggests this could be absorbed into `SyncSession` or `SyncGranular`.

### 17. SyncSession.lua — ACTIVE

- **Exports:** `OGRH.SyncSession.{State, GenerateToken, ValidateToken, StartSession, CompleteSession, CancelSession, TimeoutSession, IsSessionActive, GetActiveSession, RecordClientValidation, GetClientValidations, SetRepairParticipants, AreAllClientsValidated, LockUI, UnlockUI, EnterRepairMode, ExitRepairMode, IsUILocked, IsSVMLocked}`
- **External consumers:**
  - `SyncRepairHandlers.lua` — `StartSession`, `GetActiveSession`, `SetRepairParticipants`, `AreAllClientsValidated`, `RecordClientValidation`, `GetClientValidations`, `CompleteSession` (20+ references)
  - `_Raid/EncounterMgmt.lua` — `IsUILocked`
  - `_Raid/EncounterSetup.lua` — `IsUILocked`, `IsSVMLocked` (10+ guard checks)
- **Notes:** Session lifecycle management. Heavily used both internally and externally. The `IsUILocked`/`IsSVMLocked` guards are sprinkled throughout `EncounterSetup`.

### 18. Versioning.lua — ACTIVE (infra-only)

- **Exports:**
  - Namespace: `OGRH.Versioning.{State, CompareVersions}`
  - Globals: `OGRH.{IncrementDataVersion, GetDataVersion, SetDataVersion, GetEncounterVersion, SetEncounterVersion, IncrementEncounterVersion, GetAssignmentVersion, SetAssignmentVersion, IncrementAssignmentVersion, RecordChange, GetRecentChanges, ClearChangeLog, CompareVersions, ResolveConflict, CreateVersionMetadata, UpdateVersionMetadata, NeedsUpdate, Hash, ComputeChecksum}`
- **External consumers (all within `_Infrastructure/`):**
  - `MessageRouter.lua` — `OGRH.GetDataVersion()`, `OGRH.ComputeChecksum()`
  - `Permissions.lua` — `OGRH.IncrementDataVersion()`
  - `SyncSession.lua` — `OGRH.Versioning.CompareVersions()`
  - `DataManagement_v1.lua` — `OGRH.Versioning.ComputeChecksum` (dead code)
- **Notes:** Despite defining many global functions (`OGRH.Hash`, `OGRH.ComputeChecksum`, etc.), **no code outside `_Infrastructure/` calls them**. The `OGRH.Hash`/`OGRH.ComputeChecksum` globals overlap conceptually with `OGRH.SyncChecksum.HashString`/`OGRH.SyncChecksum.CalculateStructureChecksum` — potential consolidation opportunity.

---

## Issues Found

1. **Duplicate `OGRH.DeepCopy`** — Defined in both `SyncChecksum.lua` (~line 1192) and `SyncGranular.lua` (~line 41). `SyncGranular` loads later in the TOC and silently wins. Should consolidate to one location (likely `_Core/Utilities.lua`).

2. **Overlapping hash APIs** — `OGRH.Hash`/`OGRH.ComputeChecksum` (from `Versioning.lua`) vs `OGRH.SyncChecksum.HashString`/`OGRH.SyncChecksum.Calculate*Checksum`. Two parallel hashing systems; `Versioning`'s versions are only used by 3 infra peers.

3. **Exposed internal state** — `SyncRepairHandlers` exposes raw fields (`currentToken`, `hasRequestedRepair`, `waitingForRepair`, etc.) that peers read/write directly — a code smell that should be formalized behind accessor functions.

4. **Global namespace pollution** — `MigrationMap.lua` writes to `_G.OGRH_MIGRATION_MAP` instead of the `OGRH` namespace. Only file doing this.

---

## Versioning.lua — Deep Analysis

Out of 679 lines, only ~50 lines of code are actually exercised at runtime. The rest is dead.
Further investigation reveals that even the "live" code is largely vestigial — values are
sent in messages but never consumed on the receiving end.

### Dead Code (zero external callers — safe to delete immediately)

All of these functions are defined in `Versioning.lua` but never called from any other file:

| Function | Lines | Category |
|----------|-------|----------|
| `OGRH.SetDataVersion()` | 40-46 | Version counter |
| `OGRH.GetEncounterVersion()` | 53-55 | Per-encounter versioning |
| `OGRH.SetEncounterVersion()` | 59-69 | Per-encounter versioning |
| `OGRH.IncrementEncounterVersion()` | 73-81 | Per-encounter versioning |
| `OGRH.GetAssignmentVersion()` | 89-91 | Per-assignment versioning |
| `OGRH.SetAssignmentVersion()` | 95-106 | Per-assignment versioning |
| `OGRH.IncrementAssignmentVersion()` | 109-117 | Per-assignment versioning |
| `OGRH.RecordChange()` | 125-139 | Change log |
| `OGRH.GetRecentChanges()` | 143-153 | Change log |
| `OGRH.ClearChangeLog()` | 157-159 | Change log |
| `OGRH.ResolveConflict()` | 196-223 | Conflict resolution |
| `OGRH.CreateVersionMetadata()` | 231-237 | Metadata helpers |
| `OGRH.UpdateVersionMetadata()` | 241-251 | Metadata helpers |
| `OGRH.NeedsUpdate()` | 255-263 | Metadata helpers |
| `OGRH.VerifyChecksum()` | 319-323 | Integrity |
| `OGRH.Versioning.ComputeChecksum()` | 414-656 | Large checksum (242 lines, zero callers) |
| `OGRH.Versioning.IncrementDataVersion()` | 660-667 | Convenience wrapper |
| `OGRH.Versioning.GetGlobalVersion()` | 670-672 | Convenience wrapper |
| `OGRH.Versioning.SetGlobalVersion()` | 674-676 | Convenience wrapper |

**Action:** Delete all of the above from `Versioning.lua`. No other file changes needed.

### Vestigial Code (has callers, but the values are never consumed)

#### 1. `OGRH.IncrementDataVersion()` (lines 29-32) — 2 external callers

`Permissions.lua` calls this when broadcasting ADMIN.TAKEOVER (line 253) and ADMIN.ASSIGN
(line 345), embedding the result as a `version` field in the broadcast payload. However, the
**receiving handlers** in `MessageRouter.lua` (lines 371-383) completely ignore `data.version` —
they only read `data.newAdmin` and `data.assignedBy`.

- [ ] `Permissions.lua` line 253: Remove `version = OGRH.IncrementDataVersion and OGRH.IncrementDataVersion() or 1` from TAKEOVER payload
- [ ] `Permissions.lua` line 345: Remove `version = OGRH.IncrementDataVersion and OGRH.IncrementDataVersion() or 1` from ASSIGN payload
- [ ] `Versioning.lua`: Delete `OGRH.IncrementDataVersion()` function (lines 29-32)

#### 2. `OGRH.GetDataVersion()` (lines 35-37) — 1 external caller

`MessageRouter.lua` line 484 sends `dataVersion = OGRH.GetDataVersion()` in
ADMIN.POLL_RESPONSE messages. The **receiving handler** (MessageRouter.lua lines 781-788)
ignores `data.dataVersion` entirely — it only reads `data.version` (addon version string),
`data.checksum`, and `data.tocVersion`.

- [ ] `MessageRouter.lua` line 484: Remove `dataVersion = OGRH.GetDataVersion(),` from POLL_RESPONSE payload
- [ ] `Versioning.lua`: Delete `OGRH.GetDataVersion()` function (lines 35-37)

#### 3. `OGRH.ComputeChecksum()` + `OGRH.Hash()` (lines 270-316) — 1 external caller

`MessageRouter.lua` line 485 sends `checksum = OGRH.ComputeChecksum and OGRH.ComputeChecksum(...)` in POLL_RESPONSE messages. Same as above — the **receiving handler** reads
`data.checksum` but only passes it to `OGRH.HandleAddonPollResponse`. This feed's into
`AddonAudit` display only as a raw string — it is never compared against anything.

**Note:** These are distinct from `OGRH.SyncChecksum.HashString` / `OGRH.SyncChecksum.Calculate*Checksum` which are the actual live checksum system. The Versioning versions
are a separate, unused implementation.

- [ ] Verify `OGRH.HandleAddonPollResponse` — confirm the checksum value is display-only and not used for validation
- [ ] `MessageRouter.lua` line 485: Remove or replace with a static string (e.g., `checksum = "N/A"`)
- [ ] `Versioning.lua`: Delete `OGRH.Hash()` (lines 270-278) and `OGRH.ComputeChecksum()` (lines 283-316)

#### 4. `OGRH.Versioning.State` + `Initialize` / `Save` (lines 17-352) — 2 external callers

`Core.lua` calls `OGRH.Versioning.Initialize()` (line 264) on addon load and
`OGRH.Versioning.Save()` (line 2425) on logout. These persist `globalVersion`,
`encounterVersions`, and `assignmentVersions` to SavedVariables via SVM. Since ALL consumers
of those values are being removed, the persistence lifecycle is also dead.

- [ ] `Core.lua` line 263-264: Remove the `OGRH.Versioning.Initialize()` call (and its guard)
- [ ] `Core.lua` line 2424-2425: Remove the `OGRH.Versioning.Save()` call (and its guard)
- [ ] `Versioning.lua`: Delete `OGRH.Versioning.State` (lines 17-23), `OGRH.Versioning.Initialize()` (lines 331-341), and `OGRH.Versioning.Save()` (lines 345-352)
- [ ] Consider cleaning the `versioning` key from SVM/SavedVariables if it exists

#### 5. `OGRH.Versioning.CompareVersions()` → `OGRH.CompareVersions()` (lines 166-190) — STILL NEEDED

`SyncSession.lua` uses this (lines 405, 428-429) to compare **addon version strings**
(e.g., `"2.1.13"` vs `"2.1.12"`) and warn users when someone in the raid has a newer version.
This is a legitimate active feature.

However, the function is using Lua's `>` operator on strings, which gives lexicographic
comparison — this is **buggy for semver** (e.g., `"2.1.9" > "2.1.13"` is `true`). It also
accepts `timestamp` and `author` parameters that SyncSession never passes.

- [ ] Move `CompareVersions` to `_Core/Utilities.lua` as a proper semver-aware function
- [ ] Simplify signature to just `(version1, version2)` — the timestamp/author tiebreaker logic is unused
- [ ] Update `SyncSession.lua` calls to use the new location

#### 6. `DebugPrintState` / `DebugPrintChanges` (lines 360-403) — debug only

`MainUI.lua` wires these to `/ogrh debug version` and `/ogrh debug changes` slash commands.
They print `Versioning.State` contents — which will be empty/zeroed once the versioning
system is removed.

- [ ] `MainUI.lua` lines 996-1005: Remove both `elseif` blocks for `"debug version"` and `"debug changes"`
- [ ] `Versioning.lua`: Delete `DebugPrintState()` (lines 360-383) and `DebugPrintChanges()` (lines 386-403)

### After All Removals

Once all tasks above are complete, `Versioning.lua` will contain only:

- The `OGRH.Versioning = {}` namespace declaration
- The loaded message

The file can then either be deleted entirely (removing it from the TOC) or retained as a
minimal stub if `OGRH.Versioning` is referenced defensively elsewhere.

---

## Recommended Action Plan

| Priority | Action | Impact |
|----------|--------|--------|
| **1 — Done** | ~~Delete `DataManagement_v1.lua` and `DataManagement_v2.lua`~~ | ~1,042 lines removed |
| **2 — Done** | ~~Move `OGRH.DeepCopy` to `_Core/Utilities.lua`, remove duplicates~~ | Eliminates silent override bug |
| **3 — Next** | Gut `Versioning.lua` — remove dead code, vestigial callers, relocate `CompareVersions` | ~650 lines removed, eliminates overlapping hash APIs |
| **4 — When ready** | Stub out `Migration.lua` + `MigrationMap.lua` after confirming all users on v2 | ~4,490 lines removed |
| **5 — Optional** | Merge `SyncRepair` into `SyncRepairHandlers`; absorb `SyncRouter` into `SyncSession` | Reduce file count by 2 |
| **6 — Optional** | Move `SyncRepairUI` to `_UI/` for strict layer separation | Organizational |
| **7 — Optional** | Formalize `SyncRepairHandlers` state fields behind proper accessors | Code quality |
