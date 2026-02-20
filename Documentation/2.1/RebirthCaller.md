# Rebirth Caller — Design Document

**Version:** 1.0  
**Module:** RebirthCaller.lua  
**Location:** `_Raid/RebirthCaller.lua`  
**Target Release:** 2.1  
**Last Updated:** February 20, 2026  
**Status:** Phase 2 Complete  
**Dependencies:** ReadynessDashboard.lua (cooldown tracker), UnitXP_SP3 (distance/LoS), OGST, SVM, ChatThrottleLib

---

## Executive Summary

Rebirth Caller is a combat resurrection assignment system that automatically determines the most ideal druid to resurrect a dead raid member. It uses the Readyness Dashboard's cooldown tracking data to know which druids have Rebirth available, and UnitXP Service Pack 3's distance and line-of-sight APIs to find the closest eligible druid to the corpse. The system can be invoked from its own standalone UI (a configurable grid of dead players) or programmatically from external unit frames such as Puppeteer.

**Core Goals:**

- **Automatic Assignment** — When a raid member dies, instantly determine the best druid to Rebirth them based on cooldown availability, distance, and line of sight
- **One-Click Calling** — Click a dead player in the Rebirth Caller UI or Puppeteer frame to announce the assignment to raid chat
- **Real-Time Cooldown Data** — Leverages the existing cooldown sync system (combat log detection, admin sync broadcast, druid self-reporting via `GetSpellCooldown`)
- **Spatial Awareness** — Uses UnitXP SP3 `distanceBetween` and `inSight` to rank druids by proximity and LoS to the dead player
- **Configurable Layout** — Dead player list supports configurable columns to suit different screen setups
- **External Integration** — Exposes a clean API for Puppeteer and other unit frame addons to query and trigger Rebirth assignments

---

## Problem Statement

### Current State

1. **Manual coordination** — When someone dies in combat, the raid leader must visually scan raid frames to identify the dead player, mentally recall which druids have Rebirth available, estimate which druid is closest, and call it out in voice or chat
2. **No spatial data** — Leaders have no way to know which druid is physically closest to the corpse or has line of sight
3. **Cooldown blindness** — Without the Readyness Dashboard's cooldown tracking, leaders don't know which druids have Rebirth on cooldown vs. available
4. **Delayed response** — The cognitive overhead of identifying the best druid costs seconds during combat, potentially leading to wipes
5. **No integration with unit frames** — Puppeteer and other raid frames show health bars but offer no one-click Rebirth assignment

### Target State

A system that, when a raid member dies, instantly computes the optimal druid assignment and surfaces it through both a standalone dead-player list UI and an API callable from external unit frames. One click announces the assignment to raid chat.

---

## Architecture

### Module Hierarchy

```
_Raid/
  RebirthCaller.lua          -- Core logic: assignment algorithm, death tracking, API
  RebirthCallerUI.lua         -- Standalone dead-player list UI
  ReadynessDashboard.lua      -- Provides CooldownTrackers.rebirth data
  ReadynessDashboardUI.lua    -- Readyness Dashboard UI (sibling module)
```

### Integration Points

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Rebirth Caller                                  │
├────────────────┬──────────────────┬──────────────────┬───────────────────┤
│  Dead Player   │  Druid Rebirth   │  Distance &      │  Assignment       │
│  Detection     │  Availability    │  Line of Sight   │  Announcement     │
├────────────────┼──────────────────┼──────────────────┼───────────────────┤
│ UNIT_HEALTH    │ CooldownTrackers │ UnitXP SP3       │ SendAnnouncement  │
│ UnitIsDead()   │ .rebirth.casts   │ "distanceBetween"│ /rw or /raid      │
│ COMBAT_LOG     │ .rebirth         │ "inSight"        │ SendChatMessage   │
│                │ .reportedReady   │                  │ WhisperDruid      │
│                │ COOLDOWN_SYNC    │                  │                   │
└────────────────┴──────────────────┴──────────────────┴───────────────────┘
                                    │
                         ┌──────────┴──────────┐
                         │   External Callers   │
                         ├──────────────────────┤
                         │ RebirthCallerUI      │
                         │ (Dead Player List)   │
                         ├──────────────────────┤
                         │ Puppeteer            │
                         │ (Unit Frame Click)   │
                         ├──────────────────────┤
                         │ Any Addon via API     │
                         │ OGRH.RebirthCaller.  │
                         │  GetAssignment(name) │
                         └──────────────────────┘
```

### Data Flow

```
Death detected (UNIT_HEALTH / combat log):
  1. Add player to RD.deadPlayers list
  2. If RebirthCaller UI is open, update list

Assignment requested (click or API call):
  1. GetAvailableDruids()      → Filter CooldownTrackers.rebirth for druids with Rebirth available
  2. RankDruidsByProximity()   → UnitXP("distanceBetween", druidUnit, deadUnit, "ranged")
  3. GetLineOfSight()          → UnitXP("inSight", druidUnit, deadUnit) (informational only)
  4. SelectBestDruid()         → Closest druid with Rebirth available
  5. AnnounceAssignment()      → Send to /rw or /raid + whisper the druid
```

---

## Data Structures

### Dead Player Tracking

```lua
RC.deadPlayers = {}
-- Keyed by player name, value is table:
-- {
--   name = "Playername",
--   unitId = "raid5",          -- raid unit ID for UnitXP calls
--   deathTime = GetTime(),     -- when they died
--   class = "ROGUE",           -- uppercase class token
--   role = "MELEE",            -- from OGRH_GetPlayerRole
--   assignedDruid = nil,       -- name of druid assigned to rez (or nil)
--   announced = false,         -- whether assignment has been announced
-- }
```

### Assignment Result

```lua
-- Returned by RC.GetAssignment(deadPlayerName)
{
  deadPlayer = "Playername",
  druid = "Druidname",           -- Best druid, or nil if none available
  druidUnit = "raid12",          -- Unit ID for targeting
  distance = 28.5,              -- Yards from druid to dead player
  hasLoS = true,                -- Line of sight status
  fallbackDruids = {            -- Sorted list of all eligible druids
    { name = "Druid2", unit = "raid7", distance = 35.2, hasLoS = true },
    { name = "Druid3", unit = "raid20", distance = 42.1, hasLoS = false },
  },
  reason = nil,                 -- If no druid available, reason string
}
```

---

## Assignment Algorithm

### Priority Order

The algorithm selects the best druid using the following priority:

1. **Rebirth must be available** — Filter out druids with Rebirth on cooldown (from `CooldownTrackers.rebirth.casts`)
2. **Must be alive** — Filter out dead druids
3. **Closest distance wins** — `UnitXP("distanceBetween", druidUnit, deadUnit, "ranged")`, smallest wins
4. **Range check** — Rebirth has a 30-yard range; prioritize druids within range but don't exclude those outside (they may move)
5. **Line of sight (informational)** — `UnitXP("inSight", druidUnit, deadUnit)` is displayed in the UI but does not affect ranking (druids can reposition)

### Pseudocode

```lua
function RC.GetAssignment(deadPlayerName)
  local deadUnit = RC.GetUnitId(deadPlayerName)
  if not deadUnit or not UnitIsDead(deadUnit) then
    return { deadPlayer = deadPlayerName, druid = nil, reason = "Player not dead or not found" }
  end

  -- Step 1: Get all druids with Rebirth available
  local tracker = RD.CooldownTrackers.rebirth
  local candidates = {}
  local now = GetTime()

  for i = 1, GetNumRaidMembers() do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    if name and string.upper(class) == "DRUID" then
      local unit = "raid" .. i
      -- Must be alive
      if not UnitIsDead(unit) then
        -- Check Rebirth availability
        local available = true
        local cast = tracker.casts[name]
        if cast and cast.lastCast then
          local elapsed = now - cast.lastCast
          if elapsed < tracker.cooldownDuration then
            available = false  -- Still on cooldown
          end
        end

        if available then
          -- Step 2: Get distance and LoS
          local distance = UnitXP("distanceBetween", unit, deadUnit, "ranged")
          local hasLoS = UnitXP("inSight", unit, deadUnit)

          if distance then
            table.insert(candidates, {
              name = name,
              unit = unit,
              distance = distance,
              hasLoS = (hasLoS == true),
            })
          end
        end
      end
    end
  end

  -- Step 3: Sort by distance (closest first; LoS is informational only)
  table.sort(candidates, function(a, b)
    return a.distance < b.distance
  end)

  -- Step 4: Select best
  if table.getn(candidates) > 0 then
    local best = candidates[1]
    table.remove(candidates, 1)
    return {
      deadPlayer = deadPlayerName,
      druid = best.name,
      druidUnit = best.unit,
      distance = best.distance,
      hasLoS = best.hasLoS,
      fallbackDruids = candidates,
      reason = nil,
    }
  else
    return {
      deadPlayer = deadPlayerName,
      druid = nil,
      reason = "No druids with Rebirth available",
    }
  end
end
```

### Edge Cases

| Scenario | Behavior |
|---|---|
| No druids in raid | Return reason: "No druids in raid" |
| All druids on cooldown | Return reason: "No druids with Rebirth available" |
| All druids dead | Return reason: "No druids with Rebirth available" |
| No druid has LoS | Assign closest druid regardless — LoS is informational only, druid can reposition |
| UnitXP SP3 not installed | Distance/LoS data unavailable; fall back to first available druid alphabetically, warn in UI |
| Dead player released (ghost) | Remove from dead list — released players cannot receive combat res |
| Multiple deaths at once | Each dead player gets an independent assignment; a druid assigned to one is removed from the pool for others |
| Druid assigned then dies | Invalidate assignment; recalculate for the dead player |

### Multi-Death Assignment

When multiple raid members are dead simultaneously, assignments must avoid double-booking a single druid:

```lua
function RC.GetAllAssignments()
  local deadList = RC.GetSortedDeadPlayers()  -- Sorted by priority (tanks > healers > DPS)
  local usedDruids = {}
  local assignments = {}

  for _, dead in ipairs(deadList) do
    local result = RC.GetAssignment(dead.name, usedDruids)  -- Pass exclusion set
    if result.druid then
      usedDruids[result.druid] = true
    end
    table.insert(assignments, result)
  end

  return assignments
end
```

**Dead Player Priority Order:**
1. Tanks (critical to raid survival)
2. Healers (sustain capacity)
3. DPS (ranked by role: RANGED > MELEE, to preserve ranged uptime)

Priority is pulled from `OGRH_GetPlayerRole(name)` which returns `"TANKS"`, `"HEALERS"`, `"MELEE"`, or `"RANGED"`.

---

## UnitXP SP3 Integration

### Dependency Check

```lua
RC.hasUnitXP = (UnitXP ~= nil)

function RC.GetDistance(unit1, unit2)
  if not RC.hasUnitXP then return nil end
  return UnitXP("distanceBetween", unit1, unit2, "ranged")
end

function RC.HasLineOfSight(unit1, unit2)
  if not RC.hasUnitXP then return nil end
  return UnitXP("inSight", unit1, unit2) == true
end
```

### Graceful Degradation

If UnitXP SP3 is not installed:
- Assignment falls back to first available druid (alphabetical order)
- A warning message is shown: `"[RH] UnitXP SP3 not detected — Rebirth Caller spatial features disabled"`
- The system is still functional for manual assignment and announcement

### Distance Meters

- **Ranged** (`"ranged"`) is used for Rebirth assignment — matches the 30-yard cast range of Rebirth
- Distance values are in **yards** (matching WoW spell range units)

---

## Announcement System

### Assignment Announcement

When an assignment is made and confirmed (clicked), announce to raid:

```lua
function RC.AnnounceAssignment(assignment)
  if not assignment or not assignment.druid then return end

  local druidColored = OGRH.ColorName(assignment.druid)
  local deadColored = OGRH.ColorName(assignment.deadPlayer)
  local distText = assignment.distance and string.format("%.0f yds", assignment.distance) or "?"

  -- Raid Warning (if can /rw) or Raid Chat
  local channel = OGRH.CanRW() and "RAID_WARNING" or "RAID"
  local spellLink = "|cff71d5ff|Hspell:20748|h[Rebirth]|h|r"

  SendChatMessage(
    druidColored .. " " .. spellLink .. " → " .. deadColored .. " (" .. distText .. ")",
    channel
  )

  -- Whisper the druid
  SendChatMessage(
    "Rebirth " .. assignment.deadPlayer .. " (" .. distText .. ")",
    "WHISPER", nil, assignment.druid
  )
end
```

### Announcement Examples

**Raid Warning:**
```
|cffFF7D0AHooliganscha|r |cff71d5ff[Rebirth]|r → |cffFFF569Gnuzmas|r (28 yds)
```

**Whisper to Druid:**
```
Rebirth Gnuzmas (28 yds)
```

---

## Standalone UI — Dead Player List

### Layout

The Rebirth Caller UI is a simple list of dead raid member names arranged in configurable columns. It appears as an OGST-dockable panel or a standalone floating window. Clicking a name computes the best druid assignment and announces it.

```
┌────────────────────────────┐
│  Rebirth Caller            [X] │
├─────────────┬──────────────┤
│  Gnuzmas    │  Derpadin     │
│  Tankmedady │              │
└─────────────┴──────────────┘
```

Each name is class-colored. No druid assignment, distance, or LoS information is displayed in the UI — the assignment is computed and announced when the name is clicked.

### Backdrop

Each button has a backdrop that indicates whether a Rebirth is immediately castable on that dead player:

| Backdrop | Condition |
|---|---|
| **Green** | At least one druid with Rebirth available is within 30 yards **and** has line of sight to the corpse |
| **None / default** | No druid currently in range + LoS (Rebirth may still be available but requires repositioning) |

The backdrop is updated on each UI refresh (event-driven, not polled). This gives the raid leader a quick visual signal of which deaths can be resolved immediately without any druid needing to move.

### Click Behavior

| Action | Result |
|---|---|
| **Left-click** | Compute best druid assignment → announce to raid chat + whisper druid |
| **Right-click** | Compute assignment but cycle to next-best druid instead of the closest |

### Configuration

```lua
RC.UIConfig = {
  columns = 2,         -- Default 2 columns
  buttonWidth = 80,
  buttonHeight = 20,
  spacing = 2,
  autoShow = true,     -- Auto-show when someone dies in combat
  autoHide = true,     -- Auto-hide when no one is dead
}
```

### Settings Persistence (SVM)

```
rebirthCaller.enabled          -- boolean, default true
rebirthCaller.columns          -- number, default 2
rebirthCaller.autoShow         -- boolean, default true
rebirthCaller.autoHide         -- boolean, default true
rebirthCaller.announceChannel  -- string, default "AUTO" (auto-detect /rw or /raid)
rebirthCaller.whisperDruid     -- boolean, default true
```

---

## External API

### For Puppeteer and Other Unit Frames

The Rebirth Caller exposes a global API on `OGRH.RebirthCaller` for external addons to query and trigger assignments:

```lua
-- Get the best druid assignment for a dead player
-- @param deadPlayerName string  Name of the dead player
-- @return assignment table (see Assignment Result structure above)
OGRH.RebirthCaller.GetAssignment(deadPlayerName)

-- Get assignments for all currently dead players
-- @return table of assignment results, priority-ordered
OGRH.RebirthCaller.GetAllAssignments()

-- Announce a specific assignment to raid chat
-- @param deadPlayerName string  Name of the dead player
OGRH.RebirthCaller.CallRebirth(deadPlayerName)

-- Check if a player is dead and tracked
-- @param playerName string
-- @return boolean
OGRH.RebirthCaller.IsPlayerDead(playerName)

-- Get list of currently dead players
-- @return table of { name, unitId, deathTime, class, role }
OGRH.RebirthCaller.GetDeadPlayers()

-- Check if UnitXP SP3 is available for spatial features
-- @return boolean
OGRH.RebirthCaller.HasSpatialData()
```

### Puppeteer Integration Example

Puppeteer can call the API when a dead unit frame is clicked with a modifier key:

```lua
-- In Puppeteer's unit frame click handler:
if IsAltKeyDown() and UnitIsDead(self.unit) then
  local name = UnitName(self.unit)
  if OGRH and OGRH.RebirthCaller and OGRH.RebirthCaller.CallRebirth then
    OGRH.RebirthCaller.CallRebirth(name)
  end
  return
end
```

### Callback Registration

External addons can register for death/assignment events:

```lua
-- Register a callback for when assignments change
OGRH.RebirthCaller.RegisterCallback("OnAssignmentChanged", function(deadPlayer, assignment)
  -- Update your UI
end)

-- Register a callback for when a player dies
OGRH.RebirthCaller.RegisterCallback("OnPlayerDeath", function(deadPlayer)
  -- React to death
end)

-- Register a callback for when a player is resurrected
OGRH.RebirthCaller.RegisterCallback("OnPlayerResurrected", function(playerName)
  -- Clean up UI
end)
```

---

## Death Detection

### Events

```lua
-- Primary: health-based detection
eventFrame:RegisterEvent("UNIT_HEALTH")

-- Backup: combat log death messages
-- "Playername dies." → CHAT_MSG_COMBAT_FRIENDLY_DEATH
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLY_DEATH")
```

### Detection Logic

```lua
function RC.OnUnitHealth(unitId)
  if not UnitExists(unitId) then return end
  if not string.find(unitId, "^raid") then return end

  local name = UnitName(unitId)
  if UnitIsDead(unitId) and not UnitIsGhost(unitId) then
    if not RC.deadPlayers[name] then
      RC.AddDeadPlayer(name, unitId)
    end
  else
    if RC.deadPlayers[name] then
      RC.RemoveDeadPlayer(name)  -- Resurrected or released spirit
    end
  end
end

function RC.OnFriendlyDeath(msg)
  -- Pattern: "Playername dies."
  local _, _, name = string.find(msg, "^(.+) dies%.$")
  if name then
    local unitId = RC.FindRaidUnit(name)
    if unitId then
      RC.AddDeadPlayer(name, unitId)
    end
  end
end
```

### Resurrection Detection

```lua
-- Detect res accept: player transitions from dead → alive
-- Handled via UNIT_HEALTH: when a previously dead player's health > 0

-- Detect Rebirth cast on a specific target (combat log):
-- "Druidname casts Rebirth on Playername."
-- Already detected by ReadynessDashboard's OnCombatLogEvent — sets druid on cooldown
-- RebirthCaller additionally tracks that Playername is being rezzed

function RC.OnRebirthCast(druidName, targetName)
  local dead = RC.deadPlayers[targetName]
  if dead then
    dead.assignedDruid = druidName
    dead.announced = true  -- Mark as handled
  end
end
```

---

## Minimap Menu Integration

The minimap menu structure changes from:

```
Dashboard          >    Enabled
                        Docked
```

To:

```
Dashboards         >    Readyness Dashboard     >    Enabled
                                                      Docked
                        Rebirth Caller           >    Enabled
                                                      Columns: 2
                                                      Auto-Show
                                                      Whisper Druid
```

### Menu Item Specifications

| Item | Type | Default | Behavior |
|---|---|---|---|
| Readyness Dashboard | Submenu | — | Opens submenu with Enabled/Docked toggles |
| Enabled (Readyness) | Toggle | On (green) | Enables/disables the Readyness Dashboard |
|      Docked | Toggle | On (green) | Docks/undocks the Readyness Dashboard |
| Rebirth Caller | Submenu | — | Opens submenu with RC settings |
| Enabled (RC) | Toggle | On (green) | Enables/disables Rebirth Caller |
| Columns: N | Cycle | 2 | Left-click cycles 1→2→3→4 |
| Auto-Show | Toggle | On (green) | Auto-show list when someone dies |
| Whisper Druid | Toggle | On (green) | Whisper the assigned druid when announcing |

---

## Scan Loop

Rebirth Caller does **not** poll on a timer. It is event-driven:

| Trigger | Action |
|---|---|
| `UNIT_HEALTH` fires for a raid unit | Check if dead/alive; update `deadPlayers` |
| `CHAT_MSG_COMBAT_FRIENDLY_DEATH` | Add to `deadPlayers` (backup) |
| Cooldown tracker updates (cast detected, sync received) | Recalculate assignments for all dead players |
| Player clicks a dead-player button | `GetAssignment()` → `AnnounceAssignment()` |
| Dead player list changes | Refresh list UI |

### Performance

- No OnUpdate polling for death detection; fully event-driven
- `UnitXP` calls are cheap (native C++ implementation)
- Assignment recalculation is O(D × R) where D = dead players, R = raid druids (both ≤ 40, typically < 5)
- Grid UI refresh only when dead player list changes

---

## Cooldown Data Dependency

Rebirth Caller reads directly from `RD.CooldownTrackers.rebirth`:

```lua
local tracker = OGRH.ReadynessDashboard.CooldownTrackers.rebirth

-- Available if:
--   No cast recorded: tracker.casts[druidName] == nil
--   Cast expired:     GetTime() - tracker.casts[druidName].lastCast >= tracker.cooldownDuration (1800s)
--   Self-reported:    tracker.reportedReady[druidName] == true

-- On cooldown if:
--   Cast recorded and elapsed < cooldownDuration
```

### Data Sources (inherited from Readyness Dashboard)

| Source | Description |
|---|---|
| Combat log detection | `"DruidName casts Rebirth on Target"` → records `lastCast` timestamp |
| `COOLDOWN_CAST` broadcast | Any OGRH player sees a cast → broadcasts to raid |
| `COOLDOWN_SYNC` (admin, 60s OOC) | Admin broadcasts full cooldown state with remaining seconds |
| `COOLDOWN_CORRECTION` (druid self-report, 60s OOC) | Druid checks own `GetSpellCooldown("Rebirth")` → corrects drift |
| Poll results (`POLL_RESULTS`) | Raid-chat poll where druids type "+" to confirm availability |
| Default assumption | At raid start, all druids assumed available until a cast is detected |

---

## Testing Checklist

1. **Single death** — One player dies → assignment appears in list → click announces → druid gets whisper
2. **Multi death** — Two players die → each assigned to a different druid → no double-booking
3. **No druids available** — All druids on cooldown or dead → list shows "No Rebirth" → click does nothing
4. **Druid dies after assignment** — Reassignment triggers automatically
5. **Resurrection detected** — Dead player's health goes > 0 → removed from list
6. **Ghost/Released** — Player releases spirit → removed from list (no longer eligible for combat res)
7. **UnitXP not installed** — Assignment falls back to alphabetical druid order
8. **Distance update** — Druid moves closer → assignment recalculates on next query
9. **Line of sight** — Druid behind a wall → LoS shows red in UI (informational) → assignment unchanged (closest wins)
10. **Puppeteer integration** — Alt-click dead unit in Puppeteer → calls `OGRH.RebirthCaller.CallRebirth(name)` → announcement fires
11. **Cooldown sync** — Admin broadcasts sync → druids' availability updates → assignments recalculate
12. **Menu toggles** — Enable/disable from minimap menu → UI shows/hides correctly
13. **Re-announce** — Click already-announced player → re-sends announcement
15. **Right-click cycle** — Right-click dead player → cycles to next available druid

---

## File Structure

```
_Raid/
  RebirthCaller.lua            -- Core: death tracking, assignment algorithm, API, announcement
  RebirthCallerUI.lua           -- UI: dead player list, buttons, layout, tooltips
```

### Load Order (in .toc)

```
_Raid\ReadynessDashboard.lua
_Raid\ReadynessDashboardUI.lua
_Raid\RebirthCaller.lua
_Raid\RebirthCallerUI.lua
```

RebirthCaller must load after ReadynessDashboard since it depends on `RD.CooldownTrackers`.

---

## Development Plan

### Phase 1 — Core Logic
- Death detection (UNIT_HEALTH + combat log backup)
- Dead player list management (add/remove/ghost filtering)
- Assignment algorithm (cooldown check → distance sort)
- UnitXP dependency check and graceful fallback

### Phase 2 — UI & Announcement
- Dead player list frame (configurable columns)
- Class-colored name buttons
- Green backdrop for in-range + LoS
- Left-click announce, right-click cycle druid
- `AnnounceAssignment()` — raid warning / raid chat output
- Druid whisper
- Multi-death dedup (don't double-book a druid)
- Auto-show on death, auto-hide when clear
- Minimap menu items (Enabled, Columns, Auto-Show, Whisper Druid)
- SVM persistence for all settings

### Phase 3 — External API & Integration
- `OGRH.RebirthCaller` public API (GetAssignment, CallRebirth, GetDeadPlayers, etc.)
- Callback registration (OnPlayerDeath, OnPlayerResurrected, OnAssignmentChanged)
- Puppeteer integration example / documentation

---

## Future Considerations

- **Innervate Caller** — Same pattern for calling Innervate on OOM healers (distance + mana % + druid availability)
- **Battle Res Priority Config** — Admin-configurable priority list (e.g., always rez tanks first, or specific players)
- **Voice Integration** — TTS announcement of Rebirth assignments via WoW's PlaySoundFile
- **Automatic Casting** — If SuperWoW is available, could theoretically auto-target and begin casting (requires careful opt-in design)
