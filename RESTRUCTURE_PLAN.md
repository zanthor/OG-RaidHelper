# OG-RaidHelper: File Restructuring Plan

**Date:** January 22, 2026  
**Version:** 1.31.2 (File restructure - no version bump)

---

## Overview

This document outlines the restructuring of OG-RaidHelper from a flat file structure to a modular, organized directory structure. The goal is to improve maintainability, clarity, and scalability.

---

## Proposed Directory Structure

```
OG-RaidHelper/
├── OG-RaidHelper.toc              # Updated with new paths
├── README.md
├── CHANGELOG.md
├── LICENSE
├── TODO.md
│
├── Documentation/                  # Keep as-is
│   └── ...
│
├── Images/                        # Keep as-is
│   └── ...
│
├── textures/                      # Keep as-is
│   └── ...
│
├── Libs/                          # External libraries (no changes)
│   ├── LibStub/
│   ├── OGST/
│   ├── OGAddonMsg/
│   └── json.lua
│
├── Core/                          # Core system files
│   ├── Backport.lua              # OGRH_Backport.lua
│   ├── Core.lua                  # OGRH_Core.lua (namespace, constants, class cache)
│   ├── Utilities.lua             # OGRH_Utilities.lua (helper functions)
│   ├── Defaults.lua              # OGRH_Defaults.lua (factory defaults)
│   └── ConTrack_Defaults.lua     # OGRH_ConTrack_Defaults.lua
│
├── Infrastructure/                # Low-level communication & data
│   ├── MessageTypes.lua          # OGRH_MessageTypes.lua
│   ├── MessageRouter.lua         # OGRH_MessageRouter.lua
│   ├── Permissions.lua           # OGRH_Permissions.lua
│   ├── Versioning.lua            # OGRH_Versioning.lua
│   ├── Sync_v2.lua               # OGRH_Sync_v2.lua (OGAddonMsg sync)
│   ├── SyncIntegrity.lua         # OGRH_SyncIntegrity.lua
│   ├── SyncDelta.lua             # OGRH_SyncDelta.lua
│   └── DataManagement.lua        # OGRH_DataManagement.lua (import/export)
│
├── Configuration/                 # Raid roster & consumables management
│   ├── Invites.lua               # OGRH_Invites.lua
│   ├── Invites_Test.lua          # OGRH_Invites_Test.lua
│   ├── Roster.lua                # OGRH_Roster.lua (roster management)
│   ├── Promotes.lua              # OGRH_Promotes.lua (raid promotions)
│   ├── Consumes.lua              # OGRH_Consumes.lua (consume UI)
│   ├── ConsumesTracking.lua      # OGRH_ConsumesTracking.lua
│   └── Consumables.csv           # OGRH_Consumables.csv
│
├── Raid/                          # Raid encounter management
│   ├── EncounterMgmt.lua         # OGRH_EncounterMgmt.lua
│   ├── EncounterSetup.lua        # OGRH_EncounterSetup.lua
│   ├── RolesUI.lua               # OGRH_RolesUI.lua
│   ├── ClassPriority.lua         # OGRH_ClassPriority.lua
│   ├── LinkRole.lua              # OGRH_LinkRole.lua
│   ├── Poll.lua                  # OGRH_Poll.lua (role polling)
│   ├── Announce.lua              # OGRH_Announce.lua (tag replacement)
│   ├── AdvancedSettings.lua      # OGRH_AdvancedSettings.lua
│   ├── BigWigs.lua               # OGRH_BigWigs.lua (encounter detection)
│   └── Trade.lua                 # OGRH_Trade.lua (automated trade system)
│
├── Administration/                # Guild & admin features
│   ├── AdminSelection.lua        # OGRH_AdminSelection.lua
│   ├── Recruitment.lua           # OGRH_Recruitment.lua
│   ├── SRValidation.lua          # OGRH_SRValidation.lua (Soft Reserve tracking)
│   └── AddonAudit.lua            # OGRH_AddonAudit.lua (addon version checking)
│
├── UI/                            # Main UI components
│   └── MainUI.lua                # OGRH_MainUI.lua
│
└── Modules/                       # Encounter-specific modules (no changes)
    ├── cthun.lua
    ├── OGRH-ConsumeHelper.lua
    └── OGRH-ConsumeHelperDefaults.lua
```

---

## File Categorization Details

### Core/ (7 files)
**Purpose:** Essential initialization, namespace, utilities, and default configurations.

| Current File                    | New Path                          | Purpose |
|---------------------------------|-----------------------------------|---------|
| OGRH_Backport.lua               | Core/Backport.lua                 | Lua 5.0/5.1 compatibility shims |
| OGRH_Core.lua                   | Core/Core.lua                     | Namespace, constants, class cache, initialization |
| OGRH_Utilities.lua              | Core/Utilities.lua                | Helper functions (table ops, string ops, etc.) |
| OGRH_Defaults.lua               | Core/Defaults.lua                 | Factory default raid/encounter configurations |
| OGRH_ConTrack_Defaults.lua      | Core/ConTrack_Defaults.lua        | Default consumable tracking settings |

**Rationale:** These files are the foundation that everything else depends on. They must load first.

---

### Infrastructure/ (9 files)
**Purpose:** Low-level communication, synchronization, and data exchange between clients.

| Current File                    | New Path                            | Purpose |
|---------------------------------|-------------------------------------|---------|
| OGRH_MessageTypes.lua           | Infrastructure/MessageTypes.lua     | Message type definitions for addon comms |
| OGRH_MessageRouter.lua          | Infrastructure/MessageRouter.lua    | Central message routing via OGAddonMsg |
| OGRH_Permissions.lua            | Infrastructure/Permissions.lua      | Permission checking (lead/assist) |
| OGRH_Versioning.lua             | Infrastructure/Versioning.lua       | Version checking & compatibility |
| OGRH_Sync_v2.lua                | Infrastructure/Sync_v2.lua          | OGAddonMsg-based sync system |
| OGRH_SyncIntegrity.lua          | Infrastructure/SyncIntegrity.lua    | Data integrity validation |
| OGRH_SyncDelta.lua              | Infrastructure/SyncDelta.lua        | Delta sync for incremental updates |
| OGRH_DataManagement.lua         | Infrastructure/DataManagement.lua   | Import/export, push structure |
| OGRH_SyncUI.lua                 | Infrastructure/SyncUI.lua           | Sync status display window |

**Rationale:** These files handle addon-to-addon communication and data synchronization. The SyncUI provides visibility into the sync infrastructure state. Users don't directly configure these systems, but they're critical infrastructure.

---

### Configuration/ (7 files)
**Purpose:** Managing raid roster, invites, promotions, and consumable tracking.

| Current File                    | New Path                              | Purpose |
|---------------------------------|---------------------------------------|---------|
| OGRH_Invites.lua                | Configuration/Invites.lua             | Raid invite system (RollFor/RaidHelper integration) |
| OGRH_Invites_Test.lua           | Configuration/Invites_Test.lua        | Test harness for invite system |
| OGRH_Roster.lua                 | Configuration/Roster.lua              | Roster management (group organization) |
| OGRH_Promotes.lua               | Configuration/Promotes.lua            | Auto-promote raid members |
| OGRH_Consumes.lua               | Configuration/Consumes.lua            | Consume tracking UI |
| OGRH_ConsumesTracking.lua       | Configuration/ConsumesTracking.lua    | Backend consume tracking logic |
| OGRH_Consumables.csv            | Configuration/Consumables.csv         | Consumable item database |

**Rationale:** These files are all about configuring the raid roster and tracking consumables before/during raids. They're directly user-facing configuration.

---

### Raid/ (10 files)
**Purpose:** Encounter setup, role assignments, class priority, announcements, and raid mechanics.

| Current File                    | New Path                          | Purpose |
|---------------------------------|-----------------------------------|---------|
| OGRH_EncounterMgmt.lua          | Raid/EncounterMgmt.lua            | Encounter database and management |
| OGRH_EncounterSetup.lua         | Raid/EncounterSetup.lua           | Per-encounter setup window |
| OGRH_RolesUI.lua                | Raid/RolesUI.lua                  | Role assignment UI |
| OGRH_ClassPriority.lua          | Raid/ClassPriority.lua            | Class priority selection dialog |
| OGRH_LinkRole.lua               | Raid/LinkRole.lua                 | Link roles together (shared assignments) |
| OGRH_Poll.lua                   | Raid/Poll.lua                     | Role polling (ready checks) |
| OGRH_Announce.lua               | Raid/Announce.lua                 | Announcement tag replacement system |
| OGRH_AdvancedSettings.lua       | Raid/AdvancedSettings.lua         | Advanced raid settings UI |
| OGRH_BigWigs.lua                | Raid/BigWigs.lua                  | BigWigs encounter detection integration |
| OGRH_Trade.lua                  | Raid/Trade.lua                    | Automated item trading system (raid consumables) |

**Rationale:** These files are all about raid encounters - setting them up, assigning roles, announcing, and managing mechanics. Trade is included here because it's a core raid feature for distributing consumables during raids.

---

### Administration/ (4 files)
**Purpose:** Guild administration, recruitment, and validation tools.

| Current File                    | New Path                              | Purpose |
|---------------------------------|---------------------------------------|---------|
| OGRH_AdminSelection.lua         | Administration/AdminSelection.lua     | Select admin for current raid |
| OGRH_Recruitment.lua            | Administration/Recruitment.lua        | Guild recruitment tools |
| OGRH_SRValidation.lua           | Administration/SRValidation.lua       | Soft Reserve validation & tracking |
| OGRH_AddonAudit.lua             | Administration/AddonAudit.lua         | Addon version audit for raid members |

**Rationale:** These are guild management and validation tools primarily used by raid leaders and officers.

---

### UI/ (1 file)
**Purpose:** Main user interface and menu system.

| Current File                    | New Path                          | Purpose |
|---------------------------------|-----------------------------------|---------|
| OGRH_MainUI.lua                 | UI/MainUI.lua                     | Main window, menus, tabs |

**Rationale:** The main UI orchestrates everything. It's separate from specific feature UIs.

---

### Modules/ (No changes)
**Purpose:** Encounter-specific modules and consume helper.

Keep as-is. These are dynamically loaded encounter modules.

---

## Updated .toc File Load Order

```toc
## Interface: 11200
## Title: OG-RaidHelper
## Author: Gnuzmas
## Version: 1.31.2
## Notes: A comprehensive raid management addon for organizing encounters, assigning roles, managing trade distributions, coordinating raid activities, and validating soft-reserve integrity.
## SavedVariables: OGRH_SV, OGRH_ConsumeHelper_SV

## ===================================================================
## Phase 0: Compatibility & External Libraries
## ===================================================================
Core\Backport.lua

Libs\LibStub\LibStub.lua
Libs\Libs.xml
Libs\OGST\OGST.lua
Libs\OGST\OGST_Sample.lua
Libs\json.lua

## OGAddonMsg - Embedded Communication Library
Libs\OGAddonMsg\Core.lua
Libs\OGAddonMsg\Config.lua
Libs\OGAddonMsg\Chunker.lua
Libs\OGAddonMsg\Queue.lua
Libs\OGAddonMsg\Retry.lua
Libs\OGAddonMsg\Handlers.lua
Libs\OGAddonMsg\API.lua
Libs\OGAddonMsg\StatsPanel.lua
Libs\OGAddonMsg\Commands.lua

## ===================================================================
## Phase 1: Core System - Namespace & Utilities
## ===================================================================
Core\Core.lua
Core\Utilities.lua
Core\Defaults.lua
Core\ConTrack_Defaults.lua

## ===================================================================
## Phase 2: Infrastructure - Communication & Sync
## ===================================================================
Infrastructure\MessageTypes.lua
Infrastructure\Permissions.lua
Infrastructure\Versioning.lua
Infrastructure\MessageRouter.lua
Infrastructure\Sync_v2.lua
Infrastructure\DataManagement.lua
Infrastructure\SyncIntegrity.lua
Infrastructure\SyncDelta.lua
Infrastructure\SyncUI.lua

## ===================================================================
## Phase 3: Configuration - Roster & Consumables
## ===================================================================
Configuration\Invites.lua
Configuration\Invites_Test.lua
Configuration\Roster.lua
Configuration\Promotes.lua
Configuration\Consumes.lua
Configuration\ConsumesTracking.lua

## ===================================================================
## Phase 4: Raid - Encounters & Roles
## ===================================================================
Raid\EncounterMgmt.lua
Raid\EncounterSetup.lua
Raid\RolesUI.lua
Raid\ClassPriority.lua
Raid\LinkRole.lua
Raid\Poll.lua
Raid\Announce.lua
Raid\AdvancedSettings.lua
Raid\BigWigs.lua
Raid\Trade.lua

## ===================================================================
## Phase 5: Administration - Guild & Validation
## ===================================================================
Administration\AdminSelection.lua
Administration\Recruitment.lua
Administration\SRValidation.lua
Administration\AddonAudit.lua

## ===================================================================
## Phase 6: UI - Main Interface
## ===================================================================
UI\MainUI.lua

## ===================================================================
## Phase 7: Modules - Encounter-Specific
## ===================================================================
Modules\cthun.lua
Modules\OGRH-ConsumeHelperDefaults.lua
Modules\OGRH-ConsumeHelper.lua
```

---

## Files Not Clearly Categorized

### ⚠️ Need Clarification:

**None at this time.** All files have been successfully categorized.

However, if during implementation you discover files with unclear purposes, document them here:

| File | Current Purpose (Best Guess) | Suggested Category | Notes |
|------|------------------------------|-------------------|-------|
| _(none)_ | | | |

---

## Migration Checklist

### Pre-Migration
- [ ] Back up current addon directory
- [ ] Verify all files are accounted for in this plan
- [ ] Review load order dependencies
- [ ] Test current version in-game (baseline)

### Directory Creation
- [ ] Create `Core/` directory
- [ ] Create `Infrastructure/` directory
- [ ] Create `Configuration/` directory
- [ ] Create `Raid/` directory
- [ ] Create `Administration/` directory
- [ ] Create `UI/` directory

### File Migration (Scripted)
- [ ] Move all files according to the mapping table
- [ ] Rename files (remove OGRH_ prefix)
- [ ] Update .toc file with new paths
- [ ] Verify no files left in root (except .toc, README, etc.)

### Code Updates
- [ ] Search for any hardcoded file paths in Lua code
- [ ] Update any `loadstring()` or `dofile()` references
- [ ] Update documentation references to file paths

### Testing
- [ ] Verify addon loads without errors
- [ ] Test core functionality (encounter setup, role assignment)
- [ ] Test sync between two clients
- [ ] Test invite system integration
- [ ] Test consume tracking
- [ ] Test admin features (recruitment, SR validation)
- [ ] Test trade system
- [ ] Verify SavedVariables persist correctly

### Post-Migration
- [ ] Update CHANGELOG.md with restructure notes
- [ ] Update README.md with new structure
- [ ] Update Documentation/ with new file references

---

## Implementation Notes

### Automated Migration Script

Consider creating a PowerShell script to automate the file moves:

```powershell
# Example structure (DO NOT RUN YET - REVIEW FIRST)
$moves = @{
    "OGRH_Core.lua" = "Core\Core.lua"
    "OGRH_Utilities.lua" = "Core\Utilities.lua"
    # ... etc
}

foreach ($old in $moves.Keys) {
    $new = $moves[$old]
    $newDir = Split-Path $new -Parent
    if (-not (Test-Path $newDir)) {
        New-Item -ItemType Directory -Path $newDir
    }
    Move-Item $old $new
}
```

### Load Order Dependencies

**Critical:** The load order in the .toc file MUST be preserved. Files are loaded sequentially, and later files depend on earlier ones. The phased structure ensures:

1. **Phase 0:** Compatibility shims and external libraries
2. **Phase 1:** Core namespace and utilities
3. **Phase 2:** Communication infrastructure
4. **Phase 3-7:** Feature modules (can reference core/infrastructure)
5. **Phase 8:** Encounter modules (can reference everything)

### Breaking Changes

This is a **file structure change only** (no version bump) because:
- File paths change (internal only, no external API)
- Import/export data format remains compatible
- SavedVariables remain compatible (no changes to data structure)
- No user-facing functionality changes

---

## Summary

This restructuring plan organizes 43 Lua files into 6 logical categories:

- **Core** (5 files): Foundation & initialization
- **Infrastructure** (9 files): Communication & sync backbone (including SyncUI)
- **Configuration** (7 files): Roster & consumables management
- **Raid** (10 files): Encounter setup & mechanics (including Trade)
- **Administration** (4 files): Guild management & validation
- **UI** (1 file): Main interface
- **Modules** (3 files): Encounter-specific modules (unchanged)

The new structure improves:
- **Clarity:** Files grouped by purpose
- **Maintainability:** Easier to find and update related code
- **Scalability:** Clear place for new features
- **Onboarding:** New developers can understand structure at a glance

**Key Decisions:**
- Trade.lua moved to Raid/ (core raid feature for consumable distribution)
- SyncUI.lua moved to Infrastructure/ (displays sync infrastructure state)
- Version remains 1.31.2 (no version bump for internal restructure)

**Next Steps:** Ready for implementation. Create PowerShell migration script to automate the file moves.

---

**End of Restructuring Plan**
