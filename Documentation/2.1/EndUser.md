# OG-RaidHelper v2.1 — End User Guide

**Version:** 2.1  
**Last Updated:** February 20, 2026

---

## Table of Contents

1. [Overview](#overview)
2. [Admin Encounter](#admin-encounter)
3. [Buff Manager](#buff-manager)
4. [Readyness Dashboard](#readyness-dashboard)
5. [Rebirth Caller](#rebirth-caller)
6. [Slash Commands](#slash-commands)
7. [Minimap Menu](#minimap-menu)

---

## Overview

Version 2.1 adds four major features to OG-RaidHelper:

- **Admin Encounter** — A permanent first encounter in every raid with loot settings, disenchant assignment, and info fields
- **Buff Manager** — Multi-class buff coordination with visual assignments, coverage tracking, and PallyPower integration
- **Readyness Dashboard** — A compact status panel showing buff, consume, mana, health, and cooldown readiness at a glance
- **Rebirth Caller** — A combat resurrection assignment system that finds the best druid to Rebirth a dead player

All features are accessible from the minimap menu and/or slash commands.

---

## Admin Encounter

The Admin Encounter is automatically added as the first encounter (index 1) in every raid. It cannot be deleted and does not appear in the encounter navigation buttons.

### Roles

| Role | Type | Description |
|------|------|-------------|
| **Master Looter** | Player slot | Assign the Master Looter for the raid |
| **Loot Settings** | Custom panel | Configure loot method, auto-switch, and threshold |
| **Disenchant** | Player slot | Assign the player who handles disenchanting |
| **Loot Rules** | Text field | Free-form text for loot rules (e.g., "MS > OS") |
| **Bagspace Buffer** | Player slot | Assign a backup player for bag management |
| **Discord** | Text field | Paste a Discord invite link |
| **SR Link** | Text field | Paste a Soft Reserve link |
| **Buff Manager** | Custom panel | Buff coordination (see Buff Manager section) |

### Loot Settings

- **Loot Method**: Master Looter or Group Loot
- **Auto-Switch**: When enabled, automatically switches to Master Looter for bosses and Group Loot for trash
- **Threshold**: Uncommon, Rare, or Epic
- Click **Apply** to push settings to the raid (requires Raid Leader or Assistant)

### Announcement Tags

All roles support `[Rx.Py]` tags in announcement templates. For example, `[R6.P1]` announces the Discord link, and `[R4.P1]` announces the Loot Rules text.

---

## Buff Manager

The Buff Manager lives as a role inside the Admin Encounter. It coordinates raid buff assignments across all classes. Click **Manage Buffs** in the Admin encounter to open the full configuration window.

### Managed vs. Unmanaged Classes

Each buff class has a checkbox in the compact Admin view:

- **Managed** (checked): BuffManager assignments control who buffs which groups. Announcements are directed at the assigned caster.
- **Unmanaged** (unchecked): Simple presence check — is the buff on the raid? Deficits contribute to readiness but aren't announced with a specific assignee.
- **Paladin** always uses PallyPower integration regardless of the checkbox.

### Supported Buffs

| Buff | Class | Single / Group |
|------|-------|----------------|
| Power Word: Fortitude / Prayer of Fortitude | Priest | Both |
| Divine Spirit / Prayer of Spirit | Priest | Both |
| Shadow Protection / Prayer of Shadow Protection | Priest | Both |
| Mark of the Wild / Gift of the Wild | Druid | Both |
| Arcane Intellect / Arcane Brilliance | Mage | Both |
| Paladin Blessings (Might, Wisdom, Kings, Salvation, etc.) | Paladin | Per-class |

### Buff Manager Window

The full window (710×550) has two sections:

**Left side — Buff Assignments:**
Each buff type has one or more player slots. For each slot:
- Select a caster from the player dropdown
- Check the groups (1-8) that player is responsible for
- A coverage progress bar shows how well that assignment is covered

**Right side — Roster Panel:**
- Toggle between **Raid** (live raid members) and **Roster** (planning roster)
- Filter by role: Tanks / Healers / Melee / Ranged / Unassigned
- Search by name
- Drag players from the roster onto assignment slots

**Title bar buttons:**
- **Settings**: Configure scan interval, thresholds, PallyPower sync
- **Track**: Opens the Buff Tracker window

### Buff Tracker

The Tracker window shows:
- Overall coverage percentage
- Missing buffs grouped by player and group
- Which assigned buffers are underperforming
- **Whisper Missing**: Privately whispers underperforming buffers
- **Announce Report**: Posts a public report to raid chat

### PallyPower Integration

- **Import**: Read existing PallyPower assignments
- **Broadcast**: Push your assignments to PallyPower
- Both directions can be toggled independently in settings

### Key Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Auto-Scan | On | Periodically scan buff coverage |
| Scan Interval | 30s | Seconds between scans |
| Warn Threshold | 5 min | Warn when buff duration is below this |
| Shame Threshold | 80% | Coverage % before public shaming |
| Whisper First | On | Whisper underperformers before public announce |

---

## Readyness Dashboard

The Readyness Dashboard is a compact panel that shows at-a-glance raid readiness across 8 categories. It docks below the main OGRH frame by default.

### Indicators

The dashboard has two rows of indicators:

| Indicator | What It Shows |
|-----------|---------------|
| **Buffs** | Missing raid buffs — red/yellow/green dot with X/Y count |
| **CCon** (Class Consumes) | Consumable compliance per player vs. the encounter threshold |
| **ECon** (Encounter Consumes) | Whether players have used encounter-specific consumes (e.g., GFPP). Hidden if not applicable. |
| **H** / **D** (Healer/DPS Mana) | Dual progress bars showing mana readiness |
| **T** / **R** (Tank/Raid Health) | Dual progress bars showing health readiness |
| **Reb** (Rebirth) | X/Y druids with Rebirth off cooldown |
| **Tranq** (Tranquility) | X/Y druids with Tranquility off cooldown |
| **Taunt** (AOE Taunt) | X/Y warriors + druids with AOE taunt off cooldown |

### Traffic-Light Colors

- **Green**: Full readiness (100% or above threshold)
- **Yellow**: Partial readiness (meets minimum)
- **Red**: Below threshold

### Interactions

- **Left-click** any indicator: Announces deficits to raid chat. Uses `/rw` if you're Raid Leader/Assistant, otherwise `/raid`.
- **Hover**: Shows a detailed tooltip with per-player breakdown (who is low on mana, which druids have cooldowns, etc.)

### Cooldown Indicators (Reb / Tranq / Taunt)

These track ability cooldowns across the raid using three detection methods:

1. **Combat log** — Automatically detects when someone casts Rebirth, Tranquility, Challenging Shout, or Challenging Roar
2. **Self-report** — Druids/Warriors with the addon report their own cooldowns via `GetSpellCooldown`
3. **Admin sync** — The admin/leader can broadcast cooldown state to all members

**Click behavior changes based on combat:**
- **Out of combat**: Posts a poll ("Druids: + in /raid if your Rebirth is ready") to confirm cooldown state
- **In combat**: Announces which druids have the ability available

### Dock / Undock

The dashboard docks below the main OGRH frame by default. A small button in the bottom-right corner toggles between docked and floating. When floating, the panel can be dragged freely and its position is saved.

### Key Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Enabled | On | Master toggle |
| Docked | On | Dock to main frame or float |
| Scan Interval | 5s (3s in combat) | How often readiness is recalculated |
| Mana Threshold | 80% | Below this, mana is considered "low" |
| Health Threshold | 80% | Below this, health is considered "low" |
| Show In Raid Only | On | Hide when not in a raid group |

---

## Rebirth Caller

The Rebirth Caller is a combat resurrection assignment system. When a raid member dies, it determines the best druid to Rebirth them based on cooldown availability, physical distance, and line of sight.

### How It Works

1. A raid member dies in combat
2. The Rebirth Caller panel appears automatically (if Auto-Show is enabled)
3. Dead players are listed as class-colored buttons, sorted by priority: **Tanks > Healers > Ranged > Melee**
4. The system computes the best druid for each dead player based on:
   - Has Rebirth off cooldown (from the Readyness Dashboard's cooldown tracker)
   - Is alive
   - Is closest to the corpse (via UnitXP SP3 distance measurement)
   - Has line of sight to the corpse
5. Click a dead player's name to announce the assignment

### Visual Indicators

| Visual | Meaning |
|--------|---------|
| **Green backdrop + gold border** | A druid with Rebirth available is within 30 yards and has line of sight — can res immediately |
| **Dark backdrop, dim border** | No druid currently in position |
| **Class-colored text** | Player names in their class color (orange = Druid, white = Priest, etc.) |

### Clicking Dead Players

- **Left-click**: Announces the best druid assignment to raid chat and whispers the druid
- **Right-click**: Cycles to the next-best druid (useful if the closest druid is busy)
- **Hover**: Shows a tooltip with the best druid, distance, LoS status, and fallback druids

### Announcement Format

- **Raid chat**: `Druidname [Rebirth] -> DeadPlayer (28 yds)`
- **Whisper to druid**: `Rebirth DeadPlayer (28 yds)`

Announcements use `/rw` if you're Raid Leader/Assistant, otherwise `/raid`.

### Docking

The Rebirth Caller panel can be docked or floating:
- **Docked**: Attaches below the Readyness Dashboard (or main frame if the dashboard is undocked). When docked, button widths automatically scale to fill the available space.
- **Floating**: Freely movable. Button widths use the configured Column Width setting. Position is saved.

### Settings Dialog

Access via minimap menu → **Dashboards** → **Settings** (under Rebirth Caller).

| Setting | Default | Description |
|---------|---------|-------------|
| **Docked** | On | Dock to main frame / dashboard |
| **Columns** | 2 | Number of columns in the grid (1-10). Label changes to "Rows" when Growth Direction is Left or Right. |
| **Column Width** | 80 | Button width in pixels when undocked (40-200). Not used when docked — buttons auto-size to fill the panel. |
| **Growth Direction** | Down | Direction the grid grows as more players die: Down, Up, Left, or Right. Only available when undocked. |
| **Auto-Show on Death** | On | Automatically show the panel when someone dies |
| **Whisper Druid on Assign** | On | Whisper the assigned druid when you click to announce |

### Without UnitXP SP3

If UnitXP Service Pack 3 is not installed, distance and line-of-sight features are unavailable. The system falls back to assigning the first available druid alphabetically. A warning is shown at startup.

### Test Mode

For layout testing, use the slash command:

```
/ogrh test rebirth [N]
```

Where `N` is the number of fake deaths to inject (1-40). Omit `N` for the default of 8. Run the command again to clear test data.

If you're in a raid, test mode uses real raid member names. If solo, it generates placeholder names.

---

## Slash Commands

| Command | Description |
|---------|-------------|
| `/ogrh` or `/ogrh help` | Show all available commands |
| `/ogrh ready` | Toggle Readyness Dashboard visibility |
| `/ogrh ready dock` | Dock the dashboard |
| `/ogrh ready undock` | Float the dashboard |
| `/ogrh ready scan` | Force an immediate readiness scan |
| `/ogrh ready reset` | Reset dashboard position and dock state |
| `/ogrh test rebirth [N]` | Toggle Rebirth Caller test mode with N fake deaths (1-40) |

---

## Minimap Menu

Right-click the OGRH minimap button to access the menu. Under the **Dashboards** submenu:

| Item | Action |
|------|--------|
| **Readyness Dashboard** | Toggle on/off (green text = enabled) |
| Docked | Toggle dock state (green = docked) |
| **Rebirth Caller** | Toggle on/off (green text = enabled) |
| Settings | Opens the Rebirth Caller settings dialog |

---

## Tips

- **Pre-pull checklist**: Glance at the Readyness Dashboard before every pull. Green across the board means the raid is ready.
- **Quick Rebirth calls**: When someone dies, one left-click on their name in the Rebirth Caller panel handles everything — raid announcement and druid whisper.
- **Right-click to override**: If the closest druid is tanking or otherwise occupied, right-click cycles to the next-best option.
- **Layout testing**: Use `/ogrh test rebirth 40` to see how the panel looks with a full raid of deaths, then adjust columns and width in settings.
- **Gold borders**: During combat, watch for gold-bordered names — those can be ressed immediately because a druid is in range with Rebirth available.
