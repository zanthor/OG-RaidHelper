-- _Raid/BuffManagerPP.lua
-- PallyPower ↔ BuffManager bridge (direct-integration).
--
-- Reads talent/spell data directly from PallyPower's in-memory globals
-- (AllPallys, AllPallysAuras, PallyPower_Assignments, etc.) and writes
-- assignment changes back into those same tables, then lets PallyPower
-- handle its own network sync via PallyPower_SendMessage().
--
-- PallyPower is a HARD DEPENDENCY — this bridge is inert if PP isn't loaded.
-- We never listen for or emit PLPWR addon messages ourselves, eliminating
-- the echo/loopback problem that plagued the message-based approach.

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: BuffManagerPP requires OGRH_Core to be loaded first!|r")
  return
end

-- VERY FIRST log – proves the file started loading
if OGRH.Msg then
  OGRH.Msg("|cffccaaff[BM-PP]|r FILE START - BuffManagerPP.lua is executing")
else
  DEFAULT_CHAT_FRAME:AddMessage("|cffccaaff[BM-PP]|r FILE START (Msg not available)")
end

OGRH.BuffManagerPP = OGRH.BuffManagerPP or {}
OGRH.BuffManagerPP.debug = false  -- Toggle with /ogrh debug pp

-- Flag to suppress RefreshWindow during batch imports
local suppressRefresh = false

-- Debug logging helper (only prints when debug flag is on)
local function Log(msg)
  if not OGRH.BuffManagerPP.debug then return end
  if OGRH.Msg then
    OGRH.Msg("|cffccaaff[BM-PP]|r " .. msg)
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffccaaff[BM-PP]|r " .. msg)
  end
end

-- ============================================
-- PP DEPENDENCY CHECK
-- ============================================

--- Returns true if PallyPower's core globals are available.
local function IsPPLoaded()
  local loaded = (AllPallys ~= nil and PallyPower_Assignments ~= nil)
  return loaded
end

-- ============================================
-- CONSTANTS / MAPPINGS
-- ============================================

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

--- Find the paladin buffRole (brIdx=1) and its assigned player slots for active raid.
--- Returns role, roleIndex, encounterIdx, buffRole, brIdx (always 1 for paladin)
local function GetPaladinBuffRole()
  local role, roleIndex, encounterIdx = OGRH.BuffManager.GetRole(1)
  if not role then Log("GetPaladinBuffRole: GetRole(1)=nil"); return nil end
  OGRH.BuffManager.EnsureBuffRoles(role)
  local br = role.buffRoles and role.buffRoles[1]
  if not br then Log("GetPaladinBuffRole: buffRoles[1]=nil"); return nil end
  if not br.isPaladinRole then Log("GetPaladinBuffRole: buffRoles[1].isPaladinRole=false"); return nil end
  return role, roleIndex, encounterIdx, br, 1
end

--- Find an empty (unassigned) slot index, auto-growing if necessary.
--- Returns slotIdx suitable for a new paladin assignment.
local function FindNextEmptySlot(br)
  if not br.assignedPlayers then br.assignedPlayers = {} end
  local maxSlot = 0
  for idx, _ in pairs(br.assignedPlayers) do
    local n = tonumber(idx) or idx
    if type(n) == "number" and n > maxSlot then maxSlot = n end
  end
  for i = 1, math.max(maxSlot, 2) do
    local p = br.assignedPlayers[i]
    if not p or p == "" then return i end
  end
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

--- Poke PP's scan timer so it refreshes its UI on the next frame.
local function PokePPScan()
  if PP_NextScan ~= nil then
    PP_NextScan = 0
  end
end

--- Send a REQ message via PP to solicit fresh SELF from all paladins in the group.
local function SendPPRequest()
  if not IsPPLoaded() then Log("SendPPRequest: PP not loaded, skip"); return end
  if not PallyPower_SendMessage then Log("SendPPRequest: no SendMessage func"); return end
  if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then Log("SendPPRequest: no group"); return end
  Log("SendPPRequest: sending REQ")
  PallyPower_SendMessage("REQ")
end

-- ============================================
-- READ: PallyPower Globals → BuffManager
-- ============================================

--- Extract talent flags from PP's AllPallys for a paladin.
-- Reads directly from AllPallys[paladinName].
-- @param paladinName string
-- @return talents table {improvedMight, improvedWisdom, kings, sanctuary, mightPoints, wisdomPoints}
local function ExtractTalents(paladinName)
  if not IsPPLoaded() then return {} end
  local data = AllPallys[paladinName]
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

--- Import talent data from PP's AllPallys for a specific paladin.
local function ImportTalentsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  if not IsPPLoaded() then return end
  if not AllPallys[paladinName] then return end
  local talents = ExtractTalents(paladinName)
  WriteTalentsToSlot(slotIdx, talents, br, roleIndex, encounterIdx)
end

--- Import class-wide blessing assignments from PP's PallyPower_Assignments for a specific paladin.
local function ImportBlessingsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  if not IsPPLoaded() then return end
  local source = PallyPower_Assignments[paladinName]
  if not source then Log("ImportBlessings: no PP_Assignments for '" .. tostring(paladinName) .. "'"); return end

  local assignments = {}
  for classId = 0, 8 do
    local blessingId = source[classId]
    local className = PP_CLASS_TO_NAME[classId]
    if className and blessingId and blessingId >= 0 then
      assignments[className] = PP_BLESSING_TO_KEY[blessingId]
      Log("ImportBlessings: " .. paladinName .. " " .. className .. "=" .. tostring(PP_BLESSING_TO_KEY[blessingId]))
    end
  end

  if not br.paladinAssignments then br.paladinAssignments = {} end
  br.paladinAssignments[slotIdx] = assignments

  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinAssignments." .. slotIdx, assignments, BuildSyncMeta(1))
end

--- Auto-assign any paladins present in PP's AllPallys that are not yet in a BM slot.
--- Creates new slots as needed.
local function AutoAddPPPaladins(br, roleIndex, encounterIdx)
  if not IsPPLoaded() then return false end

  -- Build set of already-assigned paladin names
  local assigned = {}
  if br.assignedPlayers then
    for _, name in pairs(br.assignedPlayers) do
      if name and name ~= "" then assigned[name] = true end
    end
  end

  local added = false
  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)

  for paladinName, _ in pairs(AllPallys) do
    if not assigned[paladinName] then
      local slotIdx = FindNextEmptySlot(br)
      if not br.assignedPlayers then br.assignedPlayers = {} end
      br.assignedPlayers[slotIdx] = paladinName
      OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, paladinName, BuildSyncMeta(1))
      assigned[paladinName] = true
      added = true
      Log("AutoAddPPPaladins: added '" .. paladinName .. "' to slot " .. tostring(slotIdx))
    else
      Log("AutoAddPPPaladins: '" .. paladinName .. "' already assigned")
    end
  end

  return added
end

--- Full import: pull all talent + blessing data for every paladin
--- that has an assigned slot in BM.  Admin-only.
function OGRH.BuffManagerPP.ImportAll()
  Log("ImportAll called")
  if not OGRH.BuffManager.CanEdit(1) then Log("ImportAll: CanEdit(1)=false, bail"); return end
  if not IsPPLoaded() then Log("ImportAll: PP not loaded, bail"); return end

  local role, roleIndex, encounterIdx, br, brIdx = GetPaladinBuffRole()
  if not br then Log("ImportAll: no paladin buffRole found, bail"); return end

  -- Count AllPallys entries
  local ppCount = 0
  for name, _ in pairs(AllPallys) do ppCount = ppCount + 1 end
  Log("ImportAll: AllPallys has " .. ppCount .. " paladins")

  -- Count PallyPower_Assignments entries
  local paCount = 0
  for name, _ in pairs(PallyPower_Assignments) do paCount = paCount + 1 end
  Log("ImportAll: PallyPower_Assignments has " .. paCount .. " entries")

  -- Log existing BM slots
  local slotCount = 0
  if br.assignedPlayers then
    for idx, name in pairs(br.assignedPlayers) do
      if name and name ~= "" then
        slotCount = slotCount + 1
        Log("ImportAll: existing slot[" .. tostring(idx) .. "]='" .. name .. "'")
      end
    end
  end
  Log("ImportAll: " .. slotCount .. " existing BM slots")

  suppressRefresh = true

  local slotsAdded = AutoAddPPPaladins(br, roleIndex, encounterIdx)
  Log("ImportAll: AutoAddPPPaladins returned " .. tostring(slotsAdded))

  local changed = false
  if br.assignedPlayers then
    for slotIdx, paladinName in pairs(br.assignedPlayers) do
      if paladinName and paladinName ~= "" then
        local numIdx = tonumber(slotIdx) or slotIdx
        Log("ImportAll: importing slot[" .. tostring(numIdx) .. "]='" .. paladinName .. "'")
        ImportTalentsForPaladin(paladinName, numIdx, br, roleIndex, encounterIdx)
        ImportBlessingsForPaladin(paladinName, numIdx, br, roleIndex, encounterIdx)
        changed = true
      end
    end
  end

  suppressRefresh = false
  Log("ImportAll: done. changed=" .. tostring(changed) .. " slotsAdded=" .. tostring(slotsAdded))

  if (changed or slotsAdded) and OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    Log("ImportAll: refreshing window")
    OGRH.BuffManager.RefreshWindow()
  end
end

--- Re-import talents from AllPallys for a list of paladins assigned to slots.
--- Called by AutoAssignPaladin after clearing and re-assigning slots.
function OGRH.BuffManagerPP.ImportTalentsForSlots(br, brIdx, raidIdx, encounterIdx, roleIndex)
  if not IsPPLoaded() then return end
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
      -- Also clear PP assignment data for this paladin
      OGRH.BuffManagerPP.ClearBlessingsForPaladin(paladinName)
      changed = true
    end
  end

  if changed and OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
    OGRH.BuffManager.RefreshWindow()
  end
end

-- ============================================
-- WRITE: BuffManager → PallyPower Globals (+ PP network sync)
-- ============================================
-- Strategy: write directly into PP's in-memory tables, then call
-- PallyPower_SendMessage() to let PP broadcast the change itself.
-- This ensures PP stays in sync without us emitting raw addon messages
-- that PP also listens to (which caused echo/loopback).

--- Send a blessing assignment change to PallyPower.
--- Writes to PP locals and lets PP broadcast.
function OGRH.BuffManagerPP.SendBlessing(paladinName, className, blessingKey)
  Log("SendBlessing: " .. tostring(paladinName) .. " " .. tostring(className) .. "=" .. tostring(blessingKey))
  if not IsPPLoaded() then Log("SendBlessing: PP not loaded"); return end
  if not OGRH.BuffManager.CanEdit(1) then Log("SendBlessing: CanEdit=false"); return end

  local classId = BM_CLASS_TO_PP[className]
  if classId == nil then Log("SendBlessing: unknown class '" .. tostring(className) .. "'"); return end

  local blessingId = blessingKey and BM_KEY_TO_PP[blessingKey] or -1

  -- Write directly into PP's assignment table
  if not PallyPower_Assignments[paladinName] then
    PallyPower_Assignments[paladinName] = {}
  end
  PallyPower_Assignments[paladinName][classId] = blessingId

  -- Clear any per-player normal assignments PP may have cached for this class
  if PallyPower_NormalAssignments and PallyPower_NormalAssignments[paladinName]
     and PallyPower_NormalAssignments[paladinName][classId] then
    for lname in pairs(PallyPower_NormalAssignments[paladinName][classId]) do
      if blessingId == -1 or PallyPower_NormalAssignments[paladinName][classId][lname] == blessingId then
        PallyPower_NormalAssignments[paladinName][classId][lname] = -1
      end
    end
  end

  -- Let PP broadcast to the raid
  if PallyPower_SendMessage then
    local msg = "ASSIGN " .. paladinName .. " " .. classId .. " " .. blessingId
    Log("SendBlessing: broadcasting '" .. msg .. "'")
    PallyPower_SendMessage(msg)
  end

  PokePPScan()
end

--- Clear all blessing assignments for a specific paladin.
--- Writes to PP locals and lets PP broadcast.
function OGRH.BuffManagerPP.ClearBlessingsForPaladin(paladinName)
  if not IsPPLoaded() then return end
  if not OGRH.BuffManager.CanEdit(1) then return end

  if PallyPower_Assignments[paladinName] then
    for classId = 0, 9 do
      PallyPower_Assignments[paladinName][classId] = -1
    end
    -- Also clear per-player normal assignments
    if PallyPower_NormalAssignments and PallyPower_NormalAssignments[paladinName] then
      for classId = 0, 9 do
        if PallyPower_NormalAssignments[paladinName][classId] then
          for lname in pairs(PallyPower_NormalAssignments[paladinName][classId]) do
            PallyPower_NormalAssignments[paladinName][classId][lname] = -1
          end
        end
      end
    end
  end

  if PallyPower_SendMessage then
    PallyPower_SendMessage("MASSIGN " .. paladinName .. " -1")
  end

  PokePPScan()
end

--- Notify PP that an entire paladin slot's assignments changed (batch operation).
--- Called from CycleAllBlessings / ClearAllBlessings in BuffManager.lua.
--- @param brIdx number   Buff role index (always 1 for paladin)
--- @param slotIdx number Paladin slot
--- @param raidIdx number Raid index (PP outbound only for raid 1)
function OGRH.BuffManagerPP.NotifySlotChanged(brIdx, slotIdx, raidIdx)
  Log("NotifySlotChanged: brIdx=" .. tostring(brIdx) .. " slotIdx=" .. tostring(slotIdx) .. " raidIdx=" .. tostring(raidIdx))
  if raidIdx ~= 1 then Log("NotifySlotChanged: not active raid, skip"); return end
  if not IsPPLoaded() then Log("NotifySlotChanged: PP not loaded"); return end
  if not OGRH.BuffManager.CanEdit(1) then Log("NotifySlotChanged: CanEdit=false"); return end

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
          uniformKey = bk
          first = false
        elseif bk ~= uniformKey then
          uniformKey = false
          break
        end
      end
    end
  end

  -- Ensure PP's assignment table exists for this paladin
  if not PallyPower_Assignments[paladinName] then
    PallyPower_Assignments[paladinName] = {}
  end

  if uniformKey == false then
    -- Mixed blessings — write each class individually
    for classId = 0, 8 do
      local className = PP_CLASS_TO_NAME[classId]
      if className then
        local blessingKey = assignments and assignments[className]
        local blessingId = blessingKey and BM_KEY_TO_PP[blessingKey] or -1
        PallyPower_Assignments[paladinName][classId] = blessingId
        if PallyPower_SendMessage then
          PallyPower_SendMessage("ASSIGN " .. paladinName .. " " .. classId .. " " .. blessingId)
        end
      end
    end
  else
    -- Uniform blessing (all same, or all cleared) — single MASSIGN
    local blessingId = uniformKey and BM_KEY_TO_PP[uniformKey] or -1
    for classId = 0, 9 do
      PallyPower_Assignments[paladinName][classId] = blessingId
    end
    if PallyPower_SendMessage then
      PallyPower_SendMessage("MASSIGN " .. paladinName .. " " .. blessingId)
    end
  end

  -- Clear per-player normal assignments for the affected classes
  if PallyPower_NormalAssignments and PallyPower_NormalAssignments[paladinName] then
    for classId = 0, 9 do
      if PallyPower_NormalAssignments[paladinName][classId] then
        for lname in pairs(PallyPower_NormalAssignments[paladinName][classId]) do
          local bid = PallyPower_Assignments[paladinName][classId]
          if bid == -1 or PallyPower_NormalAssignments[paladinName][classId][lname] == bid then
            PallyPower_NormalAssignments[paladinName][classId][lname] = -1
          end
        end
      end
    end
  end

  PokePPScan()
end

--- Push all current BM assignments for a specific paladin into PP's tables + broadcast.
local function PushPaladinToPP(paladinName)
  if not IsPPLoaded() then return end

  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  local slotIdx = FindSlotByPaladin(br, paladinName)
  if not slotIdx then return end

  local assignments = br.paladinAssignments and br.paladinAssignments[slotIdx]

  -- Ensure PP's table exists
  if not PallyPower_Assignments[paladinName] then
    PallyPower_Assignments[paladinName] = {}
  end

  if not assignments then
    -- No assignments — clear
    for classId = 0, 9 do
      PallyPower_Assignments[paladinName][classId] = -1
    end
    if PallyPower_SendMessage then
      PallyPower_SendMessage("MASSIGN " .. paladinName .. " -1")
    end
  else
    -- Write each class assignment
    for classId = 0, 8 do
      local className = PP_CLASS_TO_NAME[classId]
      if className then
        local blessingKey = assignments[className]
        local blessingId = blessingKey and BM_KEY_TO_PP[blessingKey] or -1
        PallyPower_Assignments[paladinName][classId] = blessingId
        if PallyPower_SendMessage then
          PallyPower_SendMessage("ASSIGN " .. paladinName .. " " .. classId .. " " .. blessingId)
        end
      end
    end
  end

  PokePPScan()
end

--- Push ALL paladin assignments from BM into PP's tables + broadcast.
local function PushAllPaladinsToPP()
  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br or not br.assignedPlayers then return end

  for slotIdx, paladinName in pairs(br.assignedPlayers) do
    if paladinName and paladinName ~= "" then
      PushPaladinToPP(paladinName)
    end
  end
end

--- Public wrapper for external callers (e.g. auto-assign).
function OGRH.BuffManagerPP.RebroadcastAll()
  PushAllPaladinsToPP()
end

--- Refresh button handler: clean stale paladins, re-import from PP's live data.
function OGRH.BuffManagerPP.RefreshPaladins()
  Log("RefreshPaladins called")
  if not IsPPLoaded() then
    Log("RefreshPaladins: PP not loaded")
    OGRH.Msg("|cffff9900[BuffManager]|r PallyPower not detected.")
    return
  end

  -- 1. Clean stale paladins from BM slots
  OGRH.BuffManagerPP.CleanStalePaladins()

  -- 2. Re-import all talent + assignment data from PP's live globals
  OGRH.BuffManagerPP.ImportAll()

  -- 3. Solicit fresh SELF from all paladins in the group
  SendPPRequest()

  OGRH.Msg("|cff66ff66[BuffManager]|r Paladin data refreshed from PallyPower.")
end

-- ============================================
-- POLLING: Periodically sync from PP globals
-- ============================================
-- Instead of reacting to addon messages, we poll PP's globals on a timer
-- to pick up changes made by other paladins (whose data arrives via PP's
-- own message handling and is stored into AllPallys / PallyPower_Assignments).

local pollFrame = CreateFrame("Frame", "OGRH_BuffManagerPP_PollFrame", UIParent)
local POLL_INTERVAL = 5  -- seconds between polls
local pollElapsed = 0

--- Snapshot of the last-seen state for change detection.
--- Keyed by paladin name → serialised string of their talent + assignment data.
local lastSnapshot = {}

--- Build a simple fingerprint string from PP's data for a paladin.
local function BuildFingerprint(paladinName)
  if not IsPPLoaded() then return nil end
  local data = AllPallys[paladinName]
  if not data then return nil end

  local parts = {}

  -- Blessings: rank+talent for ids 0-5
  for id = 0, 5 do
    if data[id] then
      table.insert(parts, id .. ":" .. tostring(data[id].rank) .. "+" .. tostring(data[id].talent))
    end
  end

  -- Assignments
  local assign = PallyPower_Assignments[paladinName]
  if assign then
    local a = "A:"
    for classId = 0, 9 do
      a = a .. tostring(assign[classId] or -1)
    end
    table.insert(parts, a)
  end

  return table.concat(parts, "|")
end

pollFrame:SetScript("OnUpdate", function()
  pollElapsed = pollElapsed + arg1
  if pollElapsed < POLL_INTERVAL then return end
  pollElapsed = 0

  if not IsPPLoaded() then return end
  if not OGRH.BuffManager.CanEdit(1) then return end

  -- Only poll when BM window is open (avoid pointless work)
  if not OGRH.BuffManager.window or not OGRH.BuffManager.window:IsShown() then return end
  Log("Poll tick: window open, checking for changes")

  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  local changed = false

  -- Check all paladins in PP's data
  for paladinName, _ in pairs(AllPallys) do
    local fp = BuildFingerprint(paladinName)
    if fp and fp ~= lastSnapshot[paladinName] then
      lastSnapshot[paladinName] = fp

      -- Ensure this paladin has a slot
      local slotIdx = FindSlotByPaladin(br, paladinName)
      if not slotIdx then
        slotIdx = FindNextEmptySlot(br)
        if not br.assignedPlayers then br.assignedPlayers = {} end
        br.assignedPlayers[slotIdx] = paladinName
        local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
        OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, paladinName, BuildSyncMeta(1))
      end

      ImportTalentsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
      ImportBlessingsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
      changed = true
      Log("Poll: changed paladin '" .. paladinName .. "' at slot " .. tostring(slotIdx))
    end
  end

  if changed and not suppressRefresh then
    Log("Poll: refreshing window due to changes")
    OGRH.BuffManager.RefreshWindow()
  end
end)

-- ============================================
-- EVENT FRAME: Roster changes + initial load
-- ============================================
-- We still listen to roster events to clean stale paladins and trigger
-- re-imports, but we do NOT listen to CHAT_MSG_ADDON at all.

local eventFrame = CreateFrame("Frame", "OGRH_BuffManagerPP_EventFrame", UIParent)
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
  Log("Event: " .. tostring(event))
  -- ------------------------------------------------
  -- On login / reload: delayed cleanup + import
  -- ------------------------------------------------
  if event == "PLAYER_ENTERING_WORLD" then
    if not eventFrame.loginThrottle then
      eventFrame.loginThrottle = CreateFrame("Frame")
    end
    eventFrame.loginThrottle.elapsed = 0
    eventFrame.loginThrottle:SetScript("OnUpdate", function()
      this.elapsed = (this.elapsed or 0) + arg1
      if this.elapsed < 3 then return end
      this:SetScript("OnUpdate", nil)
      Log("LoginThrottle fired: IsPPLoaded=" .. tostring(IsPPLoaded()) .. " raidMembers=" .. tostring(GetNumRaidMembers()) .. " partyMembers=" .. tostring(GetNumPartyMembers()))
      if not IsPPLoaded() then Log("LoginThrottle: PP still not loaded after 3s"); return end
      if GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0 then
        OGRH.BuffManagerPP.CleanStalePaladins()
      end
      -- Initial import from PP's already-populated tables
      if OGRH.BuffManager.CanEdit(1) then
        Log("LoginThrottle: CanEdit=true, importing")
        OGRH.BuffManagerPP.ImportAll()
        SendPPRequest()
      else
        Log("LoginThrottle: CanEdit=false, skip import")
      end
    end)
    return
  end

  -- ------------------------------------------------
  -- Roster change: clean stale + reset poll snapshots
  -- ------------------------------------------------
  if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
    if not eventFrame.rosterThrottle then
      eventFrame.rosterThrottle = CreateFrame("Frame")
    end
    eventFrame.rosterThrottle.elapsed = 0
    eventFrame.rosterThrottle:SetScript("OnUpdate", function()
      this.elapsed = (this.elapsed or 0) + arg1
      if this.elapsed < 1 then return end
      this:SetScript("OnUpdate", nil)
      Log("RosterThrottle fired: IsPPLoaded=" .. tostring(IsPPLoaded()))
      if not IsPPLoaded() then return end
      OGRH.BuffManagerPP.CleanStalePaladins()
      if OGRH.BuffManager.CanEdit(1) then
        Log("RosterThrottle: CanEdit=true, resetting snapshots + requesting")
        -- Clear snapshots so next poll picks up fresh data
        lastSnapshot = {}
        SendPPRequest()
      end
    end)
    return
  end
end)

-- ============================================
-- HOOKS: Tie BM mutations → PP writes
-- ============================================

Log("Installing hooks...")
Log("  SetPaladinBlessing exists: " .. tostring(OGRH.BuffManager.SetPaladinBlessing ~= nil))
-- Hook SetPaladinBlessing to also push to PallyPower
local OrigSetPaladinBlessing = OGRH.BuffManager.SetPaladinBlessing
OGRH.BuffManager.SetPaladinBlessing = function(brIdx, slotIdx, className, blessingKey, raidIdx, encounterIdx, roleIndex)
  Log("HOOK SetPaladinBlessing: slot=" .. tostring(slotIdx) .. " class=" .. tostring(className) .. " blessing=" .. tostring(blessingKey) .. " raidIdx=" .. tostring(raidIdx))
  OrigSetPaladinBlessing(brIdx, slotIdx, className, blessingKey, raidIdx, encounterIdx, roleIndex)

  -- Only push to PP for active raid
  if raidIdx ~= 1 then return end

  local role = OGRH.BuffManager.GetRole(1)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)
  local br = role.buffRoles and role.buffRoles[brIdx]
  if not br or not br.isPaladinRole then return end
  local paladinName = br.assignedPlayers and br.assignedPlayers[slotIdx]
  if not paladinName or paladinName == "" then return end

  OGRH.BuffManagerPP.SendBlessing(paladinName, className, blessingKey)
end

Log("  AssignPlayerToSlot exists: " .. tostring(OGRH.BuffManager.AssignPlayerToSlot ~= nil))
-- Hook AssignPlayerToSlot — when a paladin is removed/replaced, clear their PP assignments
local OrigAssignPlayerToSlot = OGRH.BuffManager.AssignPlayerToSlot

Log("  RunAutoAssign exists: " .. tostring(OGRH.BuffManager.RunAutoAssign ~= nil))
-- Hook RunAutoAssign — broadcast paladin assignments to PP after auto-assign
local OrigRunAutoAssign = OGRH.BuffManager.RunAutoAssign
OGRH.BuffManager.RunAutoAssign = function(brIdx)
  OrigRunAutoAssign(brIdx)

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
  local window = OGRH.BuffManager.window

  -- Capture old player before the base function runs (active raid only)
  local oldPlayer = nil
  if window and window.raidIdx == 1 then
    local role = OGRH.BuffManager.GetRole(1)
    if role then
      OGRH.BuffManager.EnsureBuffRoles(role)
      local br = role.buffRoles and role.buffRoles[brIdx]
      if br and br.isPaladinRole and br.assignedPlayers then
        oldPlayer = br.assignedPlayers[slotIdx]
      end
    end
  end

  OrigAssignPlayerToSlot(brIdx, slotIdx, playerName)

  -- Only push to PP for active raid
  if not window or window.raidIdx ~= 1 then return end

  -- If paladin changed or was cleared, clear the old paladin in PP
  if oldPlayer and oldPlayer ~= "" and oldPlayer ~= playerName then
    OGRH.BuffManagerPP.ClearBlessingsForPaladin(oldPlayer)
  end

  -- If a new paladin was assigned, do a one-time talent import from PP
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

Log("  ShowWindow exists: " .. tostring(OGRH.BuffManager.ShowWindow ~= nil))
-- Hook ShowWindow to trigger an initial import
local OrigShowWindow = OGRH.BuffManager.ShowWindow
OGRH.BuffManager.ShowWindow = function(raidIdx, encounterIdx, roleIndex)
  Log("HOOK ShowWindow: raidIdx=" .. tostring(raidIdx) .. " PP=" .. tostring(IsPPLoaded()))
  OrigShowWindow(raidIdx, encounterIdx, roleIndex)
  if raidIdx == 1 and IsPPLoaded() then
    Log("HOOK ShowWindow: starting import")
    OGRH.BuffManagerPP.CleanStalePaladins()
    OGRH.BuffManagerPP.ImportAll()
    SendPPRequest()
    -- Reset snapshots so the poller picks up any changes immediately
    lastSnapshot = {}
  elseif raidIdx ~= 1 then
    Log("HOOK ShowWindow: not active raid (raidIdx=" .. tostring(raidIdx) .. "), skip")
  elseif not IsPPLoaded() then
    Log("HOOK ShowWindow: PP not loaded at runtime! AllPallys=" .. tostring(AllPallys ~= nil) .. " PP_Assignments=" .. tostring(PallyPower_Assignments ~= nil))
  end
end

Log("  SetRaidAdmin exists: " .. tostring(OGRH.SetRaidAdmin ~= nil))
-- Hook SetRaidAdmin: when admin is discovered, trigger cleanup + import
local OrigSetRaidAdmin = OGRH.SetRaidAdmin
OGRH.SetRaidAdmin = function(playerName, suppressBroadcast, skipLastAdminUpdate)
  Log("HOOK SetRaidAdmin: " .. tostring(playerName) .. " (self=" .. tostring(UnitName("player")) .. ")")
  local result = OrigSetRaidAdmin(playerName, suppressBroadcast, skipLastAdminUpdate)
  if playerName == UnitName("player") and IsPPLoaded() then
    Log("HOOK SetRaidAdmin: I am admin, running import")
    OGRH.BuffManagerPP.CleanStalePaladins()
    OGRH.BuffManagerPP.ImportAll()
    SendPPRequest()
    -- Reset snapshots so poller picks up all current data
    lastSnapshot = {}
  end
  return result
end

-- ============================================
-- DONE
-- ============================================
-- At TOC load time, PP loads AFTER OG-RaidHelper (P > O), so AllPallys won't exist yet.
-- This is normal. The bridge activates later when functions are actually called.
Log("File loaded. IsPPLoaded()=" .. tostring(IsPPLoaded()) .. " AllPallys=" .. tostring(AllPallys ~= nil) .. " PP_Assignments=" .. tostring(PallyPower_Assignments ~= nil))
Log("Hooks installed: SetPaladinBlessing, AssignPlayerToSlot, RunAutoAssign, ShowWindow, SetRaidAdmin")
OGRH.Msg("|cff66ff66[RH-BuffManagerPP]|r Bridge loaded (PP detected at runtime)")
