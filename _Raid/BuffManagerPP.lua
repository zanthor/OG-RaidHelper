-- _Raid/BuffManagerPP.lua
-- PallyPower ↔ BuffManager bridge.
-- Reads talents + assignments FROM PallyPower (Raid-Admin only).
-- Writes assignment changes TO PallyPower as they are made.
--
-- Only CHAT_MSG_ADDON from Admin (A) or Leader (L) is accepted.
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
-- HELPERS
-- ============================================

--- Is PallyPower loaded?
local function PP_Loaded()
  return (PallyPower_Assignments ~= nil)
end

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
-- INBOUND: PallyPower → BuffManager
-- ============================================

--- Import talent data from PP's AllPallys table for a specific paladin.
--- Populates paladinTalents[slotIdx] = {improved, kings, sanctuary}
local function ImportTalentsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  if not AllPallys or not AllPallys[paladinName] then return end

  local ppData = AllPallys[paladinName]
  local talents = {}

  -- Improved Blessings: talent field on Wisdom (0) or Might (1) is > 0.
  -- The value can be a number (local player via ScanSpells) or a string (remote via SELF message).
  local wisdomEntry = ppData[0]
  local mightEntry = ppData[1]
  local wTalent = wisdomEntry and tonumber(wisdomEntry.talent)
  local mTalent = mightEntry and tonumber(mightEntry.talent)
  if (wTalent and wTalent > 0) or (mTalent and mTalent > 0) then
    talents.improved = true
  end

  -- Kings: has the spell (rank not nil/"n")
  local kingsEntry = ppData[4]
  if kingsEntry and kingsEntry.rank and tostring(kingsEntry.rank) ~= "n" then
    talents.kings = true
  end

  -- Sanctuary: has the spell (rank not nil/"n")
  local sancEntry = ppData[5]
  if sancEntry and sancEntry.rank and tostring(sancEntry.rank) ~= "n" then
    talents.sanctuary = true
  end

  -- Write to data model
  if not br.paladinTalents then br.paladinTalents = {} end
  br.paladinTalents[slotIdx] = talents

  -- Persist + delta sync to other OGRH clients
  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinTalents." .. slotIdx, talents, BuildSyncMeta(1))
end

--- Import class-wide blessing assignments from PallyPower for a specific paladin.
local function ImportBlessingsForPaladin(paladinName, slotIdx, br, roleIndex, encounterIdx)
  if not PallyPower_Assignments or not PallyPower_Assignments[paladinName] then return end

  local ppAssign = PallyPower_Assignments[paladinName]
  local assignments = {}

  for classId = 0, 8 do
    local blessingId = ppAssign[classId]
    local className = PP_CLASS_TO_NAME[classId]
    if className and blessingId and blessingId >= 0 then
      assignments[className] = PP_BLESSING_TO_KEY[blessingId]
    end
  end

  -- Write to data model
  if not br.paladinAssignments then br.paladinAssignments = {} end
  br.paladinAssignments[slotIdx] = assignments

  -- Persist + delta sync to other OGRH clients
  local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
  OGRH.SVM.SetPath(basePath .. ".buffRoles.1.paladinAssignments." .. slotIdx, assignments, BuildSyncMeta(1))
end

--- Auto-assign any paladins found in AllPallys that are not yet in a BM slot.
--- Creates new slots as needed.  Admin-only.
local function AutoAddPPPaladins(br, roleIndex, encounterIdx)
  if not AllPallys then return false end

  -- Build set of already-assigned paladin names
  local assigned = {}
  if br.assignedPlayers then
    for _, name in pairs(br.assignedPlayers) do
      if name and name ~= "" then assigned[name] = true end
    end
  end

  local added = false
  for paladinName, _ in pairs(AllPallys) do
    if not assigned[paladinName] then
      local slotIdx = FindNextEmptySlot(br)
      -- Write directly (bypasses CanEdit since caller already checked admin)
      if not br.assignedPlayers then br.assignedPlayers = {} end
      br.assignedPlayers[slotIdx] = paladinName
      local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
      OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, paladinName, BuildSyncMeta(1))
      assigned[paladinName] = true
      added = true
    end
  end
  return added
end

--- Full import: pull all talent + blessing data from PallyPower for every paladin
--- that has an assigned slot in BM.  Admin-only.
function OGRH.BuffManagerPP.ImportAll()
  if not PP_Loaded() then return end
  if not IsLocalAdmin() then return end

  local role, roleIndex, encounterIdx, br, brIdx = GetPaladinBuffRole()
  if not br then return end

  -- Suppress per-item RefreshWindow calls during batch work
  suppressRefresh = true

  -- Auto-add any PP paladins not yet assigned to a BM slot
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

--- Handle a SELF message from PallyPower (paladin announcing skills + assignments).
--- Auto-adds the paladin to a BM slot if not already assigned, then imports talents/blessings.
local function HandlePPSelf(sender, msg)
  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  -- Auto-add this paladin if not already in a slot
  local slotIdx = FindSlotByPaladin(br, sender)
  if not slotIdx then
    slotIdx = FindNextEmptySlot(br)
    if not br.assignedPlayers then br.assignedPlayers = {} end
    br.assignedPlayers[slotIdx] = sender
    local basePath = string.format("encounterMgmt.raids.1.encounters.%d.roles.%d", encounterIdx, roleIndex)
    OGRH.SVM.SetPath(basePath .. ".buffRoles.1.assignedPlayers." .. slotIdx, sender, BuildSyncMeta(1))
  end

  -- Talent data comes from AllPallys which PP already updated before we get here.
  -- Small delay to let PP finish parsing its own SELF message.
  local timerFrame = OGRH.BuffManagerPP.timerFrame
  if not timerFrame then
    timerFrame = CreateFrame("Frame")
    OGRH.BuffManagerPP.timerFrame = timerFrame
  end
  timerFrame.elapsed = 0
  timerFrame.pendingSender = sender
  timerFrame.pendingSlot = slotIdx
  timerFrame.pendingBR = br
  timerFrame.pendingRoleIdx = roleIndex
  timerFrame.pendingEncIdx = encounterIdx
  timerFrame:SetScript("OnUpdate", function()
    this.elapsed = (this.elapsed or 0) + arg1
    if this.elapsed < 0.2 then return end
    this:SetScript("OnUpdate", nil)
    if PP_Loaded() then
      ImportTalentsForPaladin(this.pendingSender, this.pendingSlot, this.pendingBR, this.pendingRoleIdx, this.pendingEncIdx)
      ImportBlessingsForPaladin(this.pendingSender, this.pendingSlot, this.pendingBR, this.pendingRoleIdx, this.pendingEncIdx)
      if OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
        OGRH.BuffManager.RefreshWindow()
      end
    end
  end)
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

--- Send a blessing assignment change to PallyPower.
--- Called from SetPaladinBlessing.  Admin only.
function OGRH.BuffManagerPP.SendBlessing(paladinName, className, blessingKey)
  if not IsLocalAdmin() then return end

  local classId = BM_CLASS_TO_PP[className]
  if classId == nil then return end

  local blessingId = blessingKey and BM_KEY_TO_PP[blessingKey] or -1

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

--- Re-broadcast all current BM assignments for a specific paladin back to PP.
--- Used to force-correct unauthorized changes from non-A/L players.
local function RebroadcastPaladin(paladinName)
  local role, roleIndex, encounterIdx, br = GetPaladinBuffRole()
  if not br then return end

  local slotIdx = FindSlotByPaladin(br, paladinName)
  if not slotIdx then return end

  local assignments = br.paladinAssignments and br.paladinAssignments[slotIdx]
  if not assignments then
    -- No assignments on file — clear them in PP
    -- Also update local PP table
    if PallyPower_Assignments and PallyPower_Assignments[paladinName] then
      for classId = 0, 8 do
        PallyPower_Assignments[paladinName][classId] = -1
      end
    end
    SendPPMessage("MASSIGN " .. paladinName .. " -1")
    return
  end

  -- Update local PP table + broadcast each class assignment
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
      -- Update local PP table
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

-- ============================================
-- EVENT FRAME: Listen for PP addon messages
-- ============================================

local eventFrame = CreateFrame("Frame", "OGRH_BuffManagerPP_EventFrame", UIParent)
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function()
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

  -- If a new paladin was assigned, do a one-time talent import from PP
  if playerName and playerName ~= "" and playerName ~= oldPlayer then
    local r, ri, ei, br2 = GetPaladinBuffRole()
    if br2 then
      local si = tonumber(slotIdx) or slotIdx
      ImportTalentsForPaladin(playerName, si, br2, ri, ei)
      -- Also import any existing PP assignments for this paladin
      ImportBlessingsForPaladin(playerName, si, br2, ri, ei)
      if not suppressRefresh and OGRH.BuffManager.window and OGRH.BuffManager.window:IsShown() then
        OGRH.BuffManager.RefreshWindow()
      end
    end
  end
end

-- ============================================
-- INITIAL IMPORT: When the BM window opens, pull current PP state
-- ============================================

-- Hook ShowWindow to trigger an initial import
local OrigShowWindow = OGRH.BuffManager.ShowWindow
OGRH.BuffManager.ShowWindow = function(raidIdx, encounterIdx, roleIndex)
  OrigShowWindow(raidIdx, encounterIdx, roleIndex)
  -- After window opens, import PP data (only if active raid and admin)
  if raidIdx == 1 then
    OGRH.BuffManagerPP.ImportAll()
  end
end

-- ============================================
-- DONE
-- ============================================
if DEFAULT_CHAT_FRAME then
  OGRH.Msg("|cff66ff66[RH-BuffManagerPP]|r PallyPower bridge loaded")
end
