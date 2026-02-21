-- _Raid/BuffManagerPP.lua
-- PallyPower ↔ BuffManager bridge.
-- Parses PallyPower addon messages directly so BM works without PP installed.
-- Reads talents + assignments FROM PallyPower protocol (Raid-Admin only).
-- Writes assignment changes TO PallyPower protocol as they are made.
--
-- Only CHAT_MSG_ADDON from Admin (A) or Leader (L) is accepted for ASSIGN/MASSIGN/CLEAR.
-- Outbound writes only happen when the local player is Admin.

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: BuffManagerPP requires OGRH_Core to be loaded first!|r")
  return
end

OGRH.BuffManagerPP = OGRH.BuffManagerPP or {}

-- Flag to suppress RefreshWindow during batch imports
local suppressRefresh = false

-- ============================================
-- CONSTANTS / MAPPINGS
-- ============================================

local PP_PREFIX = "PLPWR"

-- PP blessing ID → BM blessing key
local PP_BLESSING_TO_KEY = {
  [0] = "wisdom",
  [1] = "might",
  [2] = "salvation",
  [3] = "light",
  [4] = "kings",
  [5] = "sanctuary",
}

-- BM blessing key → PP blessing ID
local BM_KEY_TO_PP = {}
for id, key in pairs(PP_BLESSING_TO_KEY) do
  BM_KEY_TO_PP[key] = id
end

-- PP class ID → BM class name (same order as PALADIN_CLASSES)
local PP_CLASS_TO_NAME = {
  [0] = "WARRIOR",
  [1] = "ROGUE",
  [2] = "PRIEST",
  [3] = "DRUID",
  [4] = "PALADIN",
  [5] = "HUNTER",
  [6] = "MAGE",
  [7] = "WARLOCK",
  [8] = "SHAMAN",
}

-- BM class name → PP class ID
local BM_CLASS_TO_PP = {}
for id, name in pairs(PP_CLASS_TO_NAME) do
  BM_CLASS_TO_PP[name] = id
end

-- ============================================
-- INTERNAL DATA STORE
-- ============================================
-- Mirror of PP's AllPallys / PallyPower_Assignments, maintained by parsing
-- the PLPWR protocol directly so we don't depend on PP being installed.
--
-- ppPallyData[name][blessingId] = { rank = "3", talent = "5" }
-- ppAssignments[name][classId]  = blessingId (-1 = none)
local ppPallyData   = {}
local ppAssignments  = {}

-- ============================================
-- HELPERS
-- ============================================

--- Build sync metadata for active-raid delta sync (mirrors BuffManager.BuildSyncMeta).
local function BuildSyncMeta(raidIdx)
  local syncLevel = (raidIdx == 1) and "REALTIME" or "MANUAL"
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  local raidName = (raids and raids[raidIdx] and raids[raidIdx].name) or "Unknown"
  return {
    syncLevel = syncLevel,
    componentType = "assignments",
    scope = {
      raid = raidName,
      encounter = "Admin",
      isActiveRaid = (raidIdx == 1)
    }
  }
end

--- Is the local player the Raid Admin?
local function IsLocalAdmin()
  local admin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
  return admin and admin == UnitName("player")
end

--- Is `sender` the Raid Leader or a Raid Assist? (rank >= 1)
--- We also accept the OGRH Raid Admin because they may be the source of truth.
local function IsAdminOrLeader(sender)
  if not sender then return false end
  -- Accept from OGRH admin
  local admin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
  if admin and sender == admin then return true end
  -- Check raid roster for L / A
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == sender then return rank >= 1 end
  end
  return false
end

--- Find the paladin buffRole (brIdx=1) and its assigned player slots for active raid.
--- Returns role, roleIndex, encounterIdx, buffRole, brIdx (always 1 for paladin)
local function GetPaladinBuffRole()
  local role, roleIndex, encounterIdx = OGRH.BuffManager.GetRole(1)
  if not role then return nil end
  OGRH.BuffManager.EnsureBuffRoles(role)
  local br = role.buffRoles and role.buffRoles[1]
  if not br or not br.isPaladinRole then return nil end
  return role, roleIndex, encounterIdx, br, 1
end

--- Find an empty (unassigned) slot index, auto-growing if necessary.
--- Returns slotIdx suitable for a new paladin assignment.
local function FindNextEmptySlot(br)
  if not br.assignedPlayers then br.assignedPlayers = {} end
  -- Scan existing slots for an empty one
  local maxSlot = 0
  for idx, _ in pairs(br.assignedPlayers) do
    local n = tonumber(idx) or idx
    if type(n) == "number" and n > maxSlot then maxSlot = n end
  end
  for i = 1, math.max(maxSlot, 2) do
    local p = br.assignedPlayers[i]
    if not p or p == "" then return i end
  end
  -- All existing slots occupied — add one more
  return maxSlot + 1
end

--- Lookup a paladin name → slotIdx in the buffRole.
local function FindSlotByPaladin(br, paladinName)
  if not br or not br.assignedPlayers then return nil end
  for idx, name in pairs(br.assignedPlayers) do
    if name == paladinName then return tonumber(idx) or idx end
  end
  return nil
end

-- ============================================
-- SELF MESSAGE PARSER
-- ============================================

--- Parse a SELF message directly from the PP protocol.
-- Format: "SELF <12 chars: 6 blessing entries × (rank digit + talent digit)>@<up to 10 assignment digits>"
-- Blessing IDs: 0=Wisdom, 1=Might, 2=Salvation, 3=Light, 4=Kings, 5=Sanctuary
-- Each blessing entry is 2 chars: rank digit (or "n" if not learned) + talent digit (or "n")
-- Assignments: classId 0-9, each char is blessingId or "n" for unassigned
--
-- Example: "SELF 32320111nn@n0nn1nnnn"
--   Wisdom: rank=3, talent=2  (has Improved Blessings rank 2)
--   Might:  rank=3, talent=2  (has Improved Blessings rank 2)
--   Salv:   rank=0, talent=1
--   Light:  rank=1, talent=1
--   Kings:  n,n = does not have Kings
--   Sanc:   nothing
--
-- @return pallyData table  {[blessingId] = {rank=string, talent=string}} or nil
-- @return assignData table {[classId] = blessingId} or nil
local function ParseSelfMessage(msg)
  local _, _, numbers, assign = string.find(msg, "^SELF ([0-9n]+)@?([0-9n]*)")
  if not numbers then return nil, nil end

  local pallyData = {}
  for id = 0, 5 do
    local rank   = string.sub(numbers, id * 2 + 1, id * 2 + 1)
    local talent = string.sub(numbers, id * 2 + 2, id * 2 + 2)
    if rank ~= "n" and rank ~= "" then
      pallyData[id] = { rank = rank, talent = talent }
    end
  end

  local assignData = {}
  if assign and assign ~= "" then
    for id = 0, 9 do
      local ch = string.sub(assign, id + 1, id + 1)
      if ch == "n" or ch == "" then
        assignData[id] = -1
      else
        assignData[id] = tonumber(ch) or -1
      end
    end
  end

  return pallyData, assignData
end

-- ============================================
-- INBOUND: PallyPower Protocol → BuffManager
-- ============================================

--- Extract talent flags from our parsed pallyData for a paladin.
-- @param paladinName string
-- @return talents table {improvedMight, improvedWisdom, kings, sanctuary, mightPoints, wisdomPoints}
local function ExtractTalents(paladinName)
  local data = ppPallyData[paladinName]
  if not data then return {} end

  local talents = {}

  -- Improved Blessings: talent field on Wisdom (0) or Might (1) > 0
  local wisdomEntry = data[0]
  local mightEntry  = data[1]
  local mTalent = mightEntry  and tonumber(mightEntry.talent)
  local wTalent = wisdomEntry and tonumber(wisdomEntry.talent)
  if mTalent and mTalent > 0 then talents.improvedMight  = true end
  if wTalent and wTalent > 0 then talents.improvedWisdom = true end
  talents.mightPoints  = mTalent or 0
  talents.wisdomPoints = wTalent or 0

  -- Kings: has the spell (rank not nil/"n")
  local kingsEntry = data[4]
  if kingsEntry and kingsEntry.rank and tostring(kingsEntry.rank) ~= "n" then
    talents.kings = true
  end

  -- Sanctuary: has the spell (rank not nil/"n")
  local sancEntry = data[5]
  if sancEntry and sancEntry.rank and tostring(sancEntry.rank) ~= "n" then
    talents.sanctuary = true
  end

  return talents
end

--- Write talent data for a paladin slot into the BM data model + SVM.
local function WriteTalentsToSlot(slotIdx, talents, br, roleIndex, encounterIdx)
  if not br.paladinTalents then br.paladinTalents = {} end
  br.paladinTalents[slotIdx] = talents
  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinTalents." .. slotIdx, talents, BuildSyncMeta(1))
end

--- Import talent data from our internal store for a specific paladin.
local function ImportTalentsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  -- Try our own parsed data first, fall back to PP's AllPallys if available
  if ppPallyData[paladinName] then
    local talents = ExtractTalents(paladinName)
    WriteTalentsToSlot(slotIdx, talents, br, roleIndex, encounterIdx)
    return
  end

  -- Fallback: PP's AllPallys (for when PP is installed and has data we haven't seen via messages)
  if AllPallys and AllPallys[paladinName] then
    ppPallyData[paladinName] = AllPallys[paladinName]
    local talents = ExtractTalents(paladinName)
    WriteTalentsToSlot(slotIdx, talents, br, roleIndex, encounterIdx)
  end
end

--- Import class-wide blessing assignments from our internal store for a specific paladin.
local function ImportBlessingsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  -- Try our own parsed data first, fall back to PP's PallyPower_Assignments
  local source = ppAssignments[paladinName]
  if not source and PallyPower_Assignments then
    source = PallyPower_Assignments[paladinName]
  end
  if not source then return end

  local assignments = {}
  for classId = 0, 8 do
    local blessingId = source[classId]
    local className = PP_CLASS_TO_NAME[classId]
    if className and blessingId and blessingId >= 0 then
      assignments[className] = PP_BLESSING_TO_KEY[blessingId]
    end
  end

  if not br.paladinAssignments then br.paladinAssignments = {} end
  br.paladinAssignments[slotIdx] = assignments

  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinAssignments." .. slotIdx, assignments, BuildSyncMeta(1))
end

--- Auto-assign any paladins found in our internal store that are not yet in a BM slot.
--- Creates new slots as needed.  Admin-only.
local function AutoAddPPPaladins(br, roleIndex, encounterIdx)
  -- Build set of already-assigned paladin names
  local assigned = {}
  if br.assignedPlayers then
    for _, name in pairs(br.assignedPlayers) do
      if name and name ~= "" then assigned[name] = true end
    end
  end

  local added = false

  -- Add from our own internal store
  for paladinName, _ in pairs(ppPallyData) do
    if not assigned[paladinName] then
      local slotIdx = FindNextEmptySlot(br)
      if not br.assignedPlayers then br.assignedPlayers = {} end
      br.assignedPlayers[slotIdx] = paladinName
      local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
      OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, paladinName, BuildSyncMeta(1))
      assigned[paladinName] = true
      added = true
    end
  end

  -- Also check PP's AllPallys if installed (may have data from before we loaded)
  if AllPallys then
    for paladinName, _ in pairs(AllPallys) do
      if not assigned[paladinName] then
        local slotIdx = FindNextEmptySlot(br)
        if not br.assignedPlayers then br.assignedPlayers = {} end
        br.assignedPlayers[slotIdx] = paladinName
        local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
        OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, paladinName, BuildSyncMeta(1))
        assigned[paladinName] = true
        added = true
      end
    end
  end

  return added
end

--- Full import: pull all talent + blessing data for every paladin
--- that has an assigned slot in BM.  Admin-only.
function OGRH.BuffManagerPP.ImportAll()
  if not IsLocalAdmin() then return end

  local role, roleIndex, encounterIdx, br, brIdx = GetPaladinBuffRole()
  if not br then return end

  -- Suppress per-item RefreshWindow calls during batch work
  suppressRefresh = true

  -- Auto-add any known paladins not yet assigned to a BM slot
  local slotsAdded = AutoAddPPPaladins(br, roleIndex, encounterIdx)

  -- Import talents + blessings for every assigned paladin
  local changed = false
  if br.assignedPlayers then
    for slotIdx, paladinName in pairs(br.assignedPlayers) do
      if paladinName and paladinName ~= "" then
        local numIdx = tonumber(slotIdx) or slotIdx
        ImportTalentsForPaladin(paladinName, numIdx, br, roleIndex, encounterIdx)
        ImportBlessingsForPaladin(paladinName, numIdx, br, roleIndex, encounterIdx)
        changed = true
      end
    end
  end

  suppressRefresh = false

  -- Single refresh at end of batch
  if (changed or slotsAdded) and OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    OGRH.BuffManager.RefreshWindow()
  end
end

--- Re-import talents from ppPallyData for a list of paladins assigned to slots.
--- Called by AutoAssignPaladin after clearing and re-assigning slots.
function OGRH.BuffManagerPP.ImportTalentsForSlots(br, brIdx, raidIdx, encounterIdx, roleIndex)
  if not br or not br.assignedPlayers then return end
  for slotIdx, paladinName in pairs(br.assignedPlayers) do
    if paladinName and paladinName ~= "" then
      local numIdx = tonumber(slotIdx) or slotIdx
      ImportTalentsForPaladin(paladinName, numIdx, br, roleIndex, encounterIdx)
    end
  end
end

--- Remove paladins from BM slots who are no longer in the raid.
--- Clears their talents, assignments, and slot assignment.
--- This is a local cleanup — safe to run regardless of admin status.
function OGRH.BuffManagerPP.CleanStalePaladins()
  local role, roleIndex, encounterIdx, br, brIdx = GetPaladinBuffRole()
  if not br or not br.assignedPlayers then return end

  -- Build set of current raid/party member names
  local raidNames = {}
  for i = 1, GetNumRaidMembers() do
    local name = GetRaidRosterInfo(i)
    if name then raidNames[name] = true end
  end
  for i = 1, GetNumPartyMembers() do
    local name = UnitName("party" .. i)
    if name then raidNames[name] = true end
  end
  local selfName = UnitName("player")
  if selfName then raidNames[selfName] = true end

  -- If we couldn't build a roster at all (too early), bail out
  if not next(raidNames) then return end

  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  local syncMeta = BuildSyncMeta(1)
  local changed = false

  for slotIdx, paladinName in pairs(br.assignedPlayers) do
    if paladinName and paladinName ~= "" and not raidNames[paladinName] then
      -- This paladin is no longer in the group — clear the slot
      br.assignedPlayers[slotIdx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, nil, syncMeta)
      if br.paladinTalents and br.paladinTalents[slotIdx] then
        br.paladinTalents[slotIdx] = nil
        OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinTalents." .. slotIdx, nil, syncMeta)
      end
      if br.paladinAssignments and br.paladinAssignments[slotIdx] then
        br.paladinAssignments[slotIdx] = nil
        OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinAssignments." .. slotIdx, nil, syncMeta)
      end
      -- Also clear PP assignment data (only broadcasts if admin)
      OGRH.BuffManagerPP.ClearBlessingsForPaladin(paladinName)
      changed = true
    end
  end

  if changed and OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    OGRH.BuffManager.RefreshWindow()
  end
end

--- Handle a SELF message from the PP protocol (paladin announcing skills + assignments).
--- Parses the message directly — does NOT rely on PP being installed.
local function HandlePPSelf(sender, msg)
  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  -- Parse the SELF message ourselves
  local pallyData, assignData = ParseSelfMessage(msg)
  if not pallyData then return end

  -- Store in our internal tables
  ppPallyData[sender] = pallyData
  if assignData then
    ppAssignments[sender] = assignData
  end

  -- Also update PP's tables if PP is installed (keep them in sync)
  if AllPallys then
    AllPallys[sender] = pallyData
  end
  if PallyPower_Assignments and assignData then
    PallyPower_Assignments[sender] = {}
    for id = 0, 9 do
      if assignData[id] then
        PallyPower_Assignments[sender][id] = assignData[id]
      end
    end
  end

  -- Auto-add this paladin if not already in a slot
  local slotIdx = FindSlotByPaladin(br, sender)
  if not slotIdx then
    slotIdx = FindNextEmptySlot(br)
    if not br.assignedPlayers then br.assignedPlayers = {} end
    br.assignedPlayers[slotIdx] = sender
    local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
    OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, sender, BuildSyncMeta(1))
  end

  -- Import talents and blessings immediately (no delay needed — we parsed it ourselves)
  ImportTalentsForPaladin(sender, slotIdx, br, roleIndex, encounterIdx)
  ImportBlessingsForPaladin(sender, slotIdx, br, roleIndex, encounterIdx)

  if not suppressRefresh and OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    OGRH.BuffManager.RefreshWindow()
  end
end

--- Handle an ASSIGN message from PallyPower ("ASSIGN <paladin> <classId> <blessingId>").
local function HandlePPAssign(sender, msg)
  local _, _, paladinName, classIdStr, blessingIdStr = string.find(msg, "^ASSIGN (%S+) (%d+) ([%d%-]+)")
  if not paladinName then return end

  local classId = tonumber(classIdStr)
  local blessingId = tonumber(blessingIdStr)
  if not classId or not blessingId then return end

  local className = PP_CLASS_TO_NAME[classId]
  if not className then return end

  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  -- Update our internal assignment store
  if not ppAssignments[paladinName] then ppAssignments[paladinName] = {} end
  ppAssignments[paladinName][classId] = blessingId

  -- Also update PP's table if installed
  if PallyPower_Assignments then
    if not PallyPower_Assignments[paladinName] then
      PallyPower_Assignments[paladinName] = {}
    end
    PallyPower_Assignments[paladinName][classId] = blessingId
  end

  local slotIdx = FindSlotByPaladin(br, paladinName)
  if not slotIdx then
    slotIdx = FindNextEmptySlot(br)
    if not br.assignedPlayers then br.assignedPlayers = {} end
    br.assignedPlayers[slotIdx] = paladinName
    local bp = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
    OGRH.SVM.SetPath(bp .. ".buffRoles.1.assignedPlayers." .. slotIdx, paladinName, BuildSyncMeta(1))
    -- Also import talents if available
    ImportTalentsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  end

  local blessingKey = (blessingId >= 0) and PP_BLESSING_TO_KEY[blessingId] or nil

  -- Update data model directly (bypass CanEdit since we already checked sender permission)
  if not br.paladinAssignments then br.paladinAssignments = {} end
  if not br.paladinAssignments[slotIdx] then br.paladinAssignments[slotIdx] = {} end
  br.paladinAssignments[slotIdx][className] = blessingKey

  -- Persist
  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinAssignments." .. slotIdx .. "." .. className, blessingKey, BuildSyncMeta(1))

  if OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    OGRH.BuffManager.RefreshWindow()
  end
end

--- Handle a MASSIGN message ("MASSIGN <paladin> <blessingId>") — all classes same blessing.
local function HandlePPMassign(sender, msg)
  local _, _, paladinName, blessingIdStr = string.find(msg, "^MASSIGN (%S+) ([%d%-]+)")
  if not paladinName then return end

  local blessingId = tonumber(blessingIdStr)
  if not blessingId then return end

  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  -- Update our internal assignment store
  if not ppAssignments[paladinName] then ppAssignments[paladinName] = {} end
  for classId = 0, 8 do
    ppAssignments[paladinName][classId] = blessingId
  end

  -- Also update PP's table if installed
  if PallyPower_Assignments then
    if not PallyPower_Assignments[paladinName] then
      PallyPower_Assignments[paladinName] = {}
    end
    for classId = 0, 8 do
      PallyPower_Assignments[paladinName][classId] = blessingId
    end
  end

  local slotIdx = FindSlotByPaladin(br, paladinName)
  if not slotIdx then
    slotIdx = FindNextEmptySlot(br)
    if not br.assignedPlayers then br.assignedPlayers = {} end
    br.assignedPlayers[slotIdx] = paladinName
    local bp = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
    OGRH.SVM.SetPath(bp .. ".buffRoles.1.assignedPlayers." .. slotIdx, paladinName, BuildSyncMeta(1))
    ImportTalentsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  end

  local blessingKey = (blessingId >= 0) and PP_BLESSING_TO_KEY[blessingId] or nil

  local assignments = {}
  for classId = 0, 8 do
    local className = PP_CLASS_TO_NAME[classId]
    if className then
      assignments[className] = blessingKey
    end
  end

  if not br.paladinAssignments then br.paladinAssignments = {} end
  br.paladinAssignments[slotIdx] = assignments

  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinAssignments." .. slotIdx, assignments, BuildSyncMeta(1))

  if OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    OGRH.BuffManager.RefreshWindow()
  end
end

--- Handle a CLEAR message — wipe all paladin assignments in BM.
local function HandlePPClear(sender, msg)
  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  -- Clear all slots
  br.paladinAssignments = {}
  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinAssignments", {}, BuildSyncMeta(1))

  if OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    OGRH.BuffManager.RefreshWindow()
  end
end

-- ============================================
-- OUTBOUND: BuffManager → PallyPower
-- ============================================

--- Send a raw PLPWR addon message (works whether or not PallyPower is installed).
local function SendPPMessage(msg)
  local channel = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
  SendAddonMessage(PP_PREFIX, msg, channel)
end

--- Send a REQ message to solicit SELF responses from all paladins with PallyPower.
local function SendPPRequest()
  SendPPMessage("REQ")
end

--- Send a blessing assignment change to PallyPower.
--- Called from SetPaladinBlessing.  Admin only.
function OGRH.BuffManagerPP.SendBlessing(paladinName, className, blessingKey)
  if not IsLocalAdmin() then return end

  local classId = BM_CLASS_TO_PP[className]
  if classId == nil then return end

  local blessingId = blessingKey and BM_KEY_TO_PP[blessingKey] or -1

  -- Update our internal assignment store
  if not ppAssignments[paladinName] then ppAssignments[paladinName] = {} end
  ppAssignments[paladinName][classId] = blessingId

  -- Update PP's local table if PP is installed
  if PallyPower_Assignments then
    if not PallyPower_Assignments[paladinName] then
      PallyPower_Assignments[paladinName] = {}
    end
    PallyPower_Assignments[paladinName][classId] = blessingId
  end

  -- Broadcast via PP protocol (always, even without PP installed)
  SendPPMessage("ASSIGN " .. paladinName .. " " .. classId .. " " .. blessingId)

  -- Trigger PP UI refresh if PP is installed
  if PP_NextScan ~= nil then
    PP_NextScan = 0
  end
end

--- Send a CLEAR to PallyPower for a specific paladin slot (all classes → -1).
function OGRH.BuffManagerPP.ClearBlessingsForPaladin(paladinName)
  if not IsLocalAdmin() then return end

  -- Update our internal assignment store
  if ppAssignments[paladinName] then
    for classId = 0, 8 do
      ppAssignments[paladinName][classId] = -1
    end
  end

  -- Update PP's local table if PP is installed
  if PallyPower_Assignments and PallyPower_Assignments[paladinName] then
    for classId = 0, 8 do
      PallyPower_Assignments[paladinName][classId] = -1
    end
  end

  -- Broadcast via PP protocol (always, even without PP installed)
  SendPPMessage("MASSIGN " .. paladinName .. " -1")

  -- Trigger PP UI refresh if PP is installed
  if PP_NextScan ~= nil then
    PP_NextScan = 0
  end
end

--- Notify PP that an entire paladin slot's assignments changed (batch operation).
--- Called from CycleAllBlessings / ClearAllBlessings in BuffManager.lua which
--- write the assignments table to SVM in a single call instead of calling
--- SetPaladinBlessing 9 times.  This sends the consolidated PP messages.
--- @param brIdx number   Buff role index (always 1 for paladin)
--- @param slotIdx number Paladin slot
--- @param raidIdx number Raid index (PP outbound only for raid 1)
function OGRH.BuffManagerPP.NotifySlotChanged(brIdx, slotIdx, raidIdx)
  if raidIdx ~= 1 then return end
  if not IsLocalAdmin() then return end

  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  local paladinName = br.assignedPlayers and br.assignedPlayers[slotIdx]
  if not paladinName or paladinName == "" then return end

  local assignments = br.paladinAssignments and br.paladinAssignments[slotIdx]

  -- Check if all classes have the same blessing (or all nil/cleared)
  local uniformKey = nil     -- tracks the common blessing (false = not uniform)
  local first = true
  if assignments then
    for classId = 0, 8 do
      local cls = PP_CLASS_TO_NAME[classId]
      if cls then
        local bk = assignments[cls]
        if first then
          uniformKey = bk  -- may be nil (= cleared)
          first = false
        elseif bk ~= uniformKey then
          uniformKey = false  -- mixed blessings
          break
        end
      end
    end
  end

  -- Update our internal assignment store + PP table
  if not ppAssignments[paladinName] then ppAssignments[paladinName] = {} end
  if PallyPower_Assignments and not PallyPower_Assignments[paladinName] then
    PallyPower_Assignments[paladinName] = {}
  end

  if uniformKey == false then
    -- Mixed blessings (e.g. might/wisdom split) — send individual ASSIGN messages
    for classId = 0, 8 do
      local className = PP_CLASS_TO_NAME[classId]
      if className then
        local blessingKey = assignments and assignments[className]
        local blessingId = blessingKey and BM_KEY_TO_PP[blessingKey] or -1
        ppAssignments[paladinName][classId] = blessingId
        if PallyPower_Assignments and PallyPower_Assignments[paladinName] then
          PallyPower_Assignments[paladinName][classId] = blessingId
        end
        SendPPMessage("ASSIGN " .. paladinName .. " " .. classId .. " " .. blessingId)
      end
    end
  else
    -- Uniform blessing (all same, or all cleared) — send one MASSIGN
    local blessingId = uniformKey and BM_KEY_TO_PP[uniformKey] or -1
    for classId = 0, 8 do
      ppAssignments[paladinName][classId] = blessingId
      if PallyPower_Assignments and PallyPower_Assignments[paladinName] then
        PallyPower_Assignments[paladinName][classId] = blessingId
      end
    end
    SendPPMessage("MASSIGN " .. paladinName .. " " .. blessingId)
  end

  -- Trigger PP UI refresh once
  if PP_NextScan ~= nil then
    PP_NextScan = 0
  end
end

--- Re-broadcast all current BM assignments for a specific paladin back to PP.
--- Used to force-correct unauthorized changes from non-A/L players.
local function RebroadcastPaladin(paladinName)
  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  local slotIdx = FindSlotByPaladin(br, paladinName)
  if not slotIdx then return end

  local assignments = br.paladinAssignments and br.paladinAssignments[slotIdx]
  if not assignments then
    -- No assignments on file — clear them
    if ppAssignments[paladinName] then
      for classId = 0, 8 do ppAssignments[paladinName][classId] = -1 end
    end
    if PallyPower_Assignments and PallyPower_Assignments[paladinName] then
      for classId = 0, 8 do PallyPower_Assignments[paladinName][classId] = -1 end
    end
    SendPPMessage("MASSIGN " .. paladinName .. " -1")
    return
  end

  -- Update internal + PP tables and broadcast each class assignment
  if not ppAssignments[paladinName] then ppAssignments[paladinName] = {} end
  if PallyPower_Assignments then
    if not PallyPower_Assignments[paladinName] then
      PallyPower_Assignments[paladinName] = {}
    end
  end

  for classId = 0, 8 do
    local className = PP_CLASS_TO_NAME[classId]
    if className then
      local blessingKey = assignments[className]
      local blessingId = blessingKey and BM_KEY_TO_PP[blessingKey] or -1
      -- Update internal store
      ppAssignments[paladinName][classId] = blessingId
      -- Update PP's table
      if PallyPower_Assignments and PallyPower_Assignments[paladinName] then
        PallyPower_Assignments[paladinName][classId] = blessingId
      end
      SendPPMessage("ASSIGN " .. paladinName .. " " .. classId .. " " .. blessingId)
    end
  end

  -- Trigger local PP UI refresh
  if PP_NextScan ~= nil then
    PP_NextScan = 0
  end
end

--- Re-broadcast ALL paladin assignments back to PP.
--- Used to force-correct an unauthorized CLEAR or after auto-assign.
local function RebroadcastAllPaladins()
  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br or not br.assignedPlayers then return end

  for slotIdx, paladinName in pairs(br.assignedPlayers) do
    if paladinName and paladinName ~= "" then
      RebroadcastPaladin(paladinName)
    end
  end
end

--- Public wrapper for external callers (e.g. auto-assign).
function OGRH.BuffManagerPP.RebroadcastAll()
  RebroadcastAllPaladins()
end

--- Refresh button handler: clean stale paladins, send REQ, re-import.
--- Mirrors PallyPower's Refresh button behavior.
function OGRH.BuffManagerPP.RefreshPaladins()
  -- 1. Clean stale paladins from BM slots (not admin-gated)
  OGRH.BuffManagerPP.CleanStalePaladins()

  -- 2. Send REQ to solicit fresh SELF from all PP paladins (admin-gated)
  if IsLocalAdmin() and GetNumRaidMembers() > 0 then
    SendPPRequest()
  end

  -- 3. Re-import all known data immediately
  OGRH.BuffManagerPP.ImportAll()

  OGRH.Msg("|cff66ff66[BuffManager]|r Paladin data refreshed.")
end

-- ============================================
-- EVENT FRAME: Listen for PP addon messages + roster changes
-- ============================================

local eventFrame = CreateFrame("Frame", "OGRH_BuffManagerPP_EventFrame", UIParent)
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
  -- ------------------------------------------------
  -- On login / reload: clean stale slots and solicit fresh data
  -- ------------------------------------------------
  if event == "PLAYER_ENTERING_WORLD" then
    -- Delay to let SVM, raid roster, and admin discovery initialise
    if not eventFrame.loginThrottle then
      eventFrame.loginThrottle = CreateFrame("Frame")
    end
    eventFrame.loginThrottle.elapsed = 0
    eventFrame.loginThrottle:SetScript("OnUpdate", function()
      this.elapsed = (this.elapsed or 0) + arg1
      if this.elapsed < 3 then return end
      this:SetScript("OnUpdate", nil)
      -- Cleanup stale paladins (always safe, not admin-gated)
      if GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0 then
        OGRH.BuffManagerPP.CleanStalePaladins()
      end
      -- Send REQ only if admin
      if IsLocalAdmin() and GetNumRaidMembers() > 0 then
        SendPPRequest()
      end
    end)
    return
  end

  -- ------------------------------------------------
  -- Roster change: send REQ to solicit SELF from all PP paladins
  -- ------------------------------------------------
  if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
    -- Throttle: avoid spamming on rapid roster changes
    if not eventFrame.rosterThrottle then
      eventFrame.rosterThrottle = CreateFrame("Frame")
    end
    eventFrame.rosterThrottle.elapsed = 0
    eventFrame.rosterThrottle:SetScript("OnUpdate", function()
      this.elapsed = (this.elapsed or 0) + arg1
      if this.elapsed < 1 then return end
      this:SetScript("OnUpdate", nil)

      -- Clean up stale paladins from internal PP tables
      local raidNames = {}
      for i = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(i)
        if name then raidNames[name] = true end
      end
      for name, _ in pairs(ppPallyData) do
        if not raidNames[name] then
          ppPallyData[name] = nil
          ppAssignments[name] = nil
        end
      end

      -- Clean up stale paladins from BM data model (always — not admin-gated)
      OGRH.BuffManagerPP.CleanStalePaladins()

      -- Send REQ only if admin
      if IsLocalAdmin() and GetNumRaidMembers() > 0 then
        SendPPRequest()
      end
    end)
    return
  end

  -- ------------------------------------------------
  -- Addon message handling
  -- ------------------------------------------------
  if event ~= "CHAT_MSG_ADDON" then return end
  if arg1 ~= PP_PREFIX then return end

  local sender = arg4
  local msg = arg2

  -- Gate: only process if local player is admin (we are the source of truth)
  if not IsLocalAdmin() then return end

  -- Skip messages from self for ASSIGN/MASSIGN/CLEAR — we already updated
  -- the data model before sending, so processing our own echo would create
  -- a feedback loop (redundant RefreshWindow + SVM.SetPath calls).
  local isFromSelf = (sender == UnitName("player"))

  -- Dispatch by message type
  -- SELF = paladin announcing skills/talents — accept from any paladin
  if string.find(msg, "^SELF ") then
    HandlePPSelf(sender, msg)
  elseif string.find(msg, "^ASSIGN ") then
    if isFromSelf then
      -- Own echo — already handled, skip
    elseif IsAdminOrLeader(sender) then
      HandlePPAssign(sender, msg)
    else
      -- Unauthorized change — extract paladin name and push back our data
      local _, _, pName = string.find(msg, "^ASSIGN (%S+)")
      if pName then RebroadcastPaladin(pName) end
    end
  elseif string.find(msg, "^MASSIGN ") then
    if isFromSelf then
      -- Own echo — already handled, skip
    elseif IsAdminOrLeader(sender) then
      HandlePPMassign(sender, msg)
    else
      local _, _, pName = string.find(msg, "^MASSIGN (%S+)")
      if pName then RebroadcastPaladin(pName) end
    end
  elseif msg == "CLEAR" then
    if isFromSelf then
      -- Own echo — already handled, skip
    elseif IsAdminOrLeader(sender) then
      HandlePPClear(sender, msg)
    else
      -- Unauthorized clear — re-broadcast everything
      RebroadcastAllPaladins()
    end
  end
  -- REQ, ASELF, SSELF, AASSIGN, SASSIGN, SYMCOUNT, COOLDOWNS, FREEASSIGN, TANK, CLTNK, VERSION — ignored
end)

-- ============================================
-- HOOKS: Tie BM mutations → PP outbound
-- ============================================

-- Hook SetPaladinBlessing to also push to PallyPower
local OrigSetPaladinBlessing = OGRH.BuffManager.SetPaladinBlessing
OGRH.BuffManager.SetPaladinBlessing = function(brIdx, slotIdx, className, blessingKey, raidIdx, encounterIdx, roleIndex)
  OrigSetPaladinBlessing(brIdx, slotIdx, className, blessingKey, raidIdx, encounterIdx, roleIndex)

  -- Only push to PP for active raid
  if raidIdx ~= 1 then return end

  -- Look up the paladin name for this slot
  local role = OGRH.BuffManager.GetRole(1)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)
  local br = role.buffRoles and role.buffRoles[brIdx]
  if not br or not br.isPaladinRole then return end
  local paladinName = br.assignedPlayers and br.assignedPlayers[slotIdx]
  if not paladinName or paladinName == "" then return end

  OGRH.BuffManagerPP.SendBlessing(paladinName, className, blessingKey)
end

-- Hook AssignPlayerToSlot — when a paladin is removed/replaced, clear their PP assignments
local OrigAssignPlayerToSlot = OGRH.BuffManager.AssignPlayerToSlot

-- Hook RunAutoAssign — broadcast paladin assignments to PP after auto-assign
local OrigRunAutoAssign = OGRH.BuffManager.RunAutoAssign
OGRH.BuffManager.RunAutoAssign = function(brIdx)
  OrigRunAutoAssign(brIdx)

  -- After paladin auto-assign, broadcast all assignments to PP
  local window = OGRH.BuffManager.window
  if not window or window.raidIdx ~= 1 then return end
  local role = OGRH.BuffManager.GetRole(1)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)
  local br = role.buffRoles and role.buffRoles[brIdx]
  if br and br.isPaladinRole then
    OGRH.BuffManagerPP.RebroadcastAll()
  end
end

OGRH.BuffManager.AssignPlayerToSlot = function(brIdx, slotIdx, playerName)
  -- Capture old player before the base function runs
  local role = OGRH.BuffManager.GetRole(1)
  local oldPlayer = nil
  if role then
    OGRH.BuffManager.EnsureBuffRoles(role)
    local br = role.buffRoles and role.buffRoles[brIdx]
    if br and br.isPaladinRole and br.assignedPlayers then
      oldPlayer = br.assignedPlayers[slotIdx]
    end
  end

  OrigAssignPlayerToSlot(brIdx, slotIdx, playerName)

  -- If paladin changed or was cleared, clear the old paladin in PP
  if oldPlayer and oldPlayer ~= "" and oldPlayer ~= playerName then
    OGRH.BuffManagerPP.ClearBlessingsForPaladin(oldPlayer)
  end

  -- If a new paladin was assigned, do a one-time talent import
  if playerName and playerName ~= "" and playerName ~= oldPlayer then
    local r, ri, ei, br2 = GetPaladinBuffRole()
    if br2 then
      local si = tonumber(slotIdx) or slotIdx
      ImportTalentsForPaladin(playerName, si, br2, ri, ei)
      ImportBlessingsForPaladin(playerName, si, br2, ri, ei)
      if not suppressRefresh and OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
        OGRH.BuffManager.RefreshWindow()
      end
    end
  end
end

-- ============================================
-- INITIAL IMPORT: When the BM window opens, pull current state
-- ============================================

-- Hook ShowWindow to trigger an initial import + REQ
local OrigShowWindow = OGRH.BuffManager.ShowWindow
OGRH.BuffManager.ShowWindow = function(raidIdx, encounterIdx, roleIndex)
  OrigShowWindow(raidIdx, encounterIdx, roleIndex)
  -- After window opens, clean stale paladins and import data
  if raidIdx == 1 then
    -- Clean stale paladins first (always safe, not admin-gated)
    OGRH.BuffManagerPP.CleanStalePaladins()
    -- Import PP data (admin-gated internally)
    OGRH.BuffManagerPP.ImportAll()
    -- Send REQ to solicit fresh SELF from all PP paladins
    if IsLocalAdmin() and GetNumRaidMembers() > 0 then
      SendPPRequest()
    end
  end
end

-- Hook SetRaidAdmin: when admin is discovered (especially after reload),
-- trigger cleanup + REQ immediately
local OrigSetRaidAdmin = OGRH.SetRaidAdmin
OGRH.SetRaidAdmin = function(playerName, suppressBroadcast, skipLastAdminUpdate)
  local result = OrigSetRaidAdmin(playerName, suppressBroadcast, skipLastAdminUpdate)
  -- If we just became admin, clean stale paladins and request PP data
  if playerName == UnitName("player") then
    OGRH.BuffManagerPP.CleanStalePaladins()
    if GetNumRaidMembers() > 0 then
      SendPPRequest()
    end
  end
  return result
end

-- ============================================
-- DONE
-- ============================================
if DEFAULT_CHAT_FRAME then
  OGRH.Msg("|cff66ff66[RH-BuffManagerPP]|r PallyPower bridge loaded")
end
