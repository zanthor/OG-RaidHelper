# Data Structure Migration Cleanup

## Overview
During the implementation of Advanced Settings (BigWigs integration and Consume Tracking), the data structure was changed from a keyed table to an array-based structure. However, several legacy code locations still use the old data structure format and need to be updated.

## Data Structure Change

### Old Structure (Deprecated)
```lua
OGRH_SV.encounterMgmt = {
  encounters = {
    ["RaidName"] = { "Encounter1", "Encounter2", ... }
  }
}
```

### New Structure (Current)
```lua
OGRH_SV.encounterMgmt = {
  raids = {
    [1] = {
      name = "RaidName",
      encounters = {
        [1] = {
          name = "Encounter1",
          advancedSettings = { ... }
        },
        [2] = {
          name = "Encounter2",
          advancedSettings = { ... }
        }
      }
    }
  }
}
```

## Locations Requiring Updates

### 1. OGRH_EncounterMgmt.lua

**Lines 55-56** - Migration Code
```lua
-- BROKEN: Old structure access
if OGRH_SV.encounterMgmt.encounters and OGRH_SV.encounterMgmt.encounters[raidName] then
  local encounterNames = OGRH_SV.encounterMgmt.encounters[raidName]
```

**Fix Required:** Iterate through `raids` array to find raid by `name`, then access its `encounters` array.

---

### 2. OGRH_Core.lua

**Lines 4478-4502** - Import/Merge Function
```lua
-- BROKEN: Old structure access
if importData.encounterMgmt.encounters then
  if not OGRH_SV.encounterMgmt.encounters then OGRH_SV.encounterMgmt.encounters = {} end
  for raidName, encounters in pairs(importData.encounterMgmt.encounters) do
    if not OGRH_SV.encounterMgmt.encounters[raidName] then
      OGRH_SV.encounterMgmt.encounters[raidName] = {}
    end
    for i = 1, table.getn(encounters) do
      local encounterName = encounters[i]
      local exists = false
      for j = 1, table.getn(OGRH_SV.encounterMgmt.encounters[raidName]) do
        if OGRH_SV.encounterMgmt.encounters[raidName][j] == encounterName then
```

**Fix Required:** Update to work with new array-based structure. Loop through `raids` array to find matching raid by name.

---

### 3. OGRH_EncounterSetup.lua

#### Line 923 - Delete Raid Function
```lua
-- BROKEN: Old structure access
OGRH_SV.encounterMgmt.encounters[raidName] = nil
```

**Fix Required:** Find raid in `raids` array and remove it. Already handles new structure for raid object itself, but this line tries to clean up old structure reference.

---

#### Lines 956-970 - Add Encounter Function
```lua
-- BROKEN: Old structure access
if not OGRH_SV.encounterMgmt.encounters[raidName] then
  OGRH_SV.encounterMgmt.encounters[raidName] = {}
end

for _, name in ipairs(OGRH_SV.encounterMgmt.encounters[raidName]) do
  if name == encounterName then
    exists = true
    break
  end
end

if not exists then
  table.insert(OGRH_SV.encounterMgmt.encounters[raidName], encounterName)
```

**Fix Required:** Loop through `raids` array to find raid by name, then properly add encounter object to its `encounters` array with full structure including `advancedSettings`.

---

#### Lines 1007-1010 - Delete Encounter Function
```lua
-- BROKEN: Old structure access
if OGRH_SV.encounterMgmt.encounters[raidName] then
  for i, name in ipairs(OGRH_SV.encounterMgmt.encounters[raidName]) do
    if name == encounterName then
      table.remove(OGRH_SV.encounterMgmt.encounters[raidName], i)
```

**Fix Required:** Find raid in `raids` array, then find encounter in its `encounters` array by comparing `.name` property.

---

#### Lines 1075-1077 - Rename Raid Function
```lua
-- BROKEN: Old structure access
if OGRH_SV.encounterMgmt.encounters[oldName] then
  OGRH_SV.encounterMgmt.encounters[newName] = OGRH_SV.encounterMgmt.encounters[oldName]
  OGRH_SV.encounterMgmt.encounters[oldName] = nil
end
```

**Fix Required:** Find raid in `raids` array by old name and update its `.name` property. Already handles new structure for raid object, but this tries to migrate old structure.

---

#### Lines 1176-1177 - Rename Encounter Function
```lua
-- BROKEN: Old structure access
if OGRH_SV.encounterMgmt.encounters[raidName] then
  for _, name in ipairs(OGRH_SV.encounterMgmt.encounters[raidName]) do
```

**Fix Required:** Find raid in `raids` array by name, then find encounter in its `encounters` array and update the `.name` property.

---

## Pattern for Accessing New Structure

### Finding a Raid
```lua
local raidObj = nil
if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
  for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
    local raid = OGRH_SV.encounterMgmt.raids[i]
    if raid.name == raidName then
      raidObj = raid
      break
    end
  end
end
```

### Finding an Encounter
```lua
local encounterObj = nil
if raidObj and raidObj.encounters then
  for i = 1, table.getn(raidObj.encounters) do
    local enc = raidObj.encounters[i]
    if enc.name == encounterName then
      encounterObj = enc
      break
    end
  end
end
```

### Creating a New Encounter
```lua
local newEncounter = {
  name = encounterName,
  advancedSettings = {
    bigwigs = {
      enabled = false,
      encounterId = "",
      autoAnnounce = false
    },
    consumeTracking = {
      enabled = nil,
      readyThreshold = nil,
      requiredFlaskRoles = {}
    }
  }
}
table.insert(raidObj.encounters, newEncounter)
```

## Testing Checklist

After fixing each location, verify:
- [ ] Raid creation works
- [ ] Raid deletion works
- [ ] Raid renaming works
- [ ] Encounter creation works
- [ ] Encounter deletion works
- [ ] Encounter renaming works
- [ ] Data import/merge works
- [ ] Migration from old structure to new structure works
- [ ] No errors when accessing encounters
- [ ] Advanced settings are preserved

## Status

- [x] **OGRH_Core.lua Line 3078-3180** - ENCOUNTER_SELECT handler - **FIXED**
- [ ] OGRH_EncounterMgmt.lua Lines 55-56
- [ ] OGRH_Core.lua Lines 4478-4502
- [ ] OGRH_EncounterSetup.lua Line 923
- [ ] OGRH_EncounterSetup.lua Lines 956-970
- [ ] OGRH_EncounterSetup.lua Lines 1007-1010
- [ ] OGRH_EncounterSetup.lua Lines 1075-1077
- [ ] OGRH_EncounterSetup.lua Lines 1176-1177
