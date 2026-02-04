-- OGRH_DataManagement.lua
-- Data Management UI and Functions - v2 Schema Compatible
-- Factory Reset, Import/Export, Push Structure

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_DataManagement requires OGRH_Core to be loaded first!|r")
  return
end

-- Initialize namespace
OGRH.DataManagement = OGRH.DataManagement or {}

-------------------------------------------------------------------------------
-- Helper: Strip Player Assignments from Encounter Roles
-------------------------------------------------------------------------------

local function StripPlayerAssignments(encounterMgmt)
  if not encounterMgmt or not encounterMgmt.raids then
    return encounterMgmt
  end
  
  local stripped = OGRH.DeepCopy(encounterMgmt)
  
  -- Iterate through raids
  for raidIdx = 1, table.getn(stripped.raids) do
    local raid = stripped.raids[raidIdx]
    if raid and raid.encounters then
      -- Iterate through encounters
      for encIdx = 1, table.getn(raid.encounters) do
        local encounter = raid.encounters[encIdx]
        if encounter and encounter.roles then
          -- Iterate through roles
          for roleIdx = 1, table.getn(encounter.roles) do
            local role = encounter.roles[roleIdx]
            if role and role.slots then
              -- Clear all slot assignments
              for slotIdx = 1, table.getn(role.slots) do
                role.slots[slotIdx] = nil
              end
            end
          end
        end
      end
    end
  end
  
  return stripped
end

-------------------------------------------------------------------------------
-- Factory Reset
-------------------------------------------------------------------------------

function OGRH.DataManagement.LoadDefaults()
  if not OGRH.FactoryDefaults or type(OGRH.FactoryDefaults) ~= "table" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper] Error:|r No factory defaults configured in OGRH_Defaults.lua")
    DEFAULT_CHAT_FRAME:AddMessage("Edit OGRH_Defaults.lua and paste your export string after the = sign.")
    return
  end
  
  -- Check for version field
  if not OGRH.FactoryDefaults.version then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper] Error:|r Invalid factory defaults format in OGRH_Defaults.lua")
    return
  end
  
  -- Import using SVM
  if OGRH.FactoryDefaults.encounterMgmt then
    OGRH.SVM.Set("encounterMgmt", nil, OGRH.FactoryDefaults.encounterMgmt)
  end
  if OGRH.FactoryDefaults.tradeItems then
    OGRH.SVM.Set("tradeItems", nil, OGRH.FactoryDefaults.tradeItems)
  end
  if OGRH.FactoryDefaults.consumes then
    OGRH.SVM.Set("consumes", nil, OGRH.FactoryDefaults.consumes)
  end
  if OGRH.FactoryDefaults.rgo then
    OGRH.SVM.Set("rgo", nil, OGRH.FactoryDefaults.rgo)
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Factory defaults loaded successfully!")
  
  -- Refresh windows
  OGRH.DataManagement.RefreshAllWindows()
  
  if OGRH_DataManagementFrame and OGRH_DataManagementFrame:IsShown() then
    OGRH.DataManagement.UpdateDetailPanel()
  end
end

-------------------------------------------------------------------------------
-- Checksum Helpers
-------------------------------------------------------------------------------

function OGRH.DataManagement.GetCurrentChecksum()
  if OGRH.Sync and OGRH.Sync.ComputeCurrentChecksum then
    return tostring(OGRH.Sync.ComputeCurrentChecksum())
  end
  return "UNAVAILABLE"
end

function OGRH.DataManagement.GetDefaultsChecksum()
  if not OGRH.FactoryDefaults then
    return "NO_DEFAULTS"
  end
  
  if OGRH.Versioning and OGRH.Versioning.ComputeChecksum then
    return tostring(OGRH.Versioning.ComputeChecksum(OGRH.FactoryDefaults))
  end
  
  return "UNAVAILABLE"
end

-------------------------------------------------------------------------------
-- Export
-------------------------------------------------------------------------------

function OGRH.DataManagement.ExportData()
  if not OGRH_DataManagementFrame or not OGRH_DataManagementFrame.importExportEditBox then
    return
  end
  
  -- Read data via SVM (schema-independent)
  local encounterMgmt = OGRH.SVM.Get("encounterMgmt")
  local tradeItems = OGRH.SVM.Get("tradeItems")
  local consumes = OGRH.SVM.Get("consumes")
  
  -- Strip player assignments from encounter roles
  local cleanEncounterMgmt = StripPlayerAssignments(encounterMgmt)
  
  -- Build export package
  local exportData = {
    version = "2.0",  -- v2 schema export
    encounterMgmt = cleanEncounterMgmt,
    tradeItems = tradeItems or {},
    consumes = consumes or {}
    -- Future: consumesTracking, rosterManagement, srValidation
  }
  
  -- Serialize to string
  local serialized = OGRH.Serialize(exportData)
  
  local editBox = OGRH_DataManagementFrame.importExportEditBox
  editBox:SetText(serialized)
  editBox:HighlightText()
  editBox:SetFocus()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Data exported to textbox (player assignments stripped).")
end

-------------------------------------------------------------------------------
-- Import
-------------------------------------------------------------------------------

function OGRH.DataManagement.ImportData()
  if not OGRH_DataManagementFrame or not OGRH_DataManagementFrame.importExportEditBox then
    return
  end
  
  local editBox = OGRH_DataManagementFrame.importExportEditBox
  local dataString = editBox:GetText()
  
  if not dataString or dataString == "" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r No data to import.")
    return
  end
  
  -- Deserialize
  local success, importData = pcall(OGRH.Deserialize, dataString)
  
  if not success or not importData then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Failed to parse import data.")
    return
  end
  
  -- Validate version
  if not importData.version then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Invalid data format (missing version).")
    return
  end
  
  -- Import via SVM (triggers migration if needed)
  if importData.encounterMgmt then
    OGRH.SVM.Set("encounterMgmt", nil, importData.encounterMgmt)
  end
  if importData.tradeItems then
    OGRH.SVM.Set("tradeItems", nil, importData.tradeItems)
  end
  if importData.consumes then
    OGRH.SVM.Set("consumes", nil, importData.consumes)
  end
  
  -- Future imports (when implemented)
  if importData.consumesTracking then
    OGRH.SVM.Set("consumesTracking", nil, importData.consumesTracking)
  end
  if importData.rosterManagement then
    OGRH.SVM.Set("rosterManagement", nil, importData.rosterManagement)
  end
  if importData.srValidation then
    OGRH.SVM.Set("srValidation", nil, importData.srValidation)
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Data imported successfully (version " .. importData.version .. ").")
  
  -- Refresh windows
  OGRH.DataManagement.RefreshAllWindows()
end

-------------------------------------------------------------------------------
-- Push Structure
-------------------------------------------------------------------------------

function OGRH.DataManagement.InitiatePushStructure()
  if not OGRH.Sync or not OGRH.Sync.BroadcastFullSync then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Sync system not available")
    return
  end
  
  -- Check permissions
  if not OGRH.CanModifyStructure(UnitName("player")) then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Only admin can broadcast structure")
    return
  end
  
  -- Check if in raid
  if GetNumRaidMembers() == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Must be in a raid to push structure")
    return
  end
  
  -- Broadcast using Sync system
  OGRH.Sync.BroadcastFullSync()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Broadcasting structure to raid...")
end

-- Poll for checksums (Push Structure UI)
function OGRH.DataManagement.StartPushStructurePoll()
  if not OGRH_DataManagementFrame then return end
  
  if GetNumRaidMembers() == 0 then
    OGRH.DataManagement.RefreshPushStructureList()
    return
  end
  
  -- Reset poll state
  OGRH.DataManagement.pushPollResponses = {}
  OGRH.DataManagement.pushPollInProgress = true
  OGRH.DataManagement.lastPushPollTime = GetTime()
  
  -- Send poll request
  OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.POLL_VERSION, "")
  
  -- Add self
  local selfName = UnitName("player")
  local myChecksum = OGRH.DataManagement.GetCurrentChecksum()
  
  table.insert(OGRH.DataManagement.pushPollResponses, {
    name = selfName,
    version = OGRH.VERSION or "Unknown",
    checksum = myChecksum
  })
  
  -- Refresh after 2 seconds
  OGRH.ScheduleFunc(function()
    OGRH.DataManagement.pushPollInProgress = false
    OGRH.DataManagement.RefreshPushStructureList()
  end, 2)
end

function OGRH.DataManagement.HandlePushPollResponse(sender, version, checksum)
  if not OGRH.DataManagement.pushPollInProgress then
    return
  end
  
  -- Check if already recorded
  if OGRH.DataManagement.pushPollResponses then
    for i = 1, table.getn(OGRH.DataManagement.pushPollResponses) do
      if OGRH.DataManagement.pushPollResponses[i].name == sender then
        return
      end
    end
  end
  
  -- Add response
  table.insert(OGRH.DataManagement.pushPollResponses, {
    name = sender,
    version = version,
    checksum = checksum
  })
  
  -- Refresh UI if visible
  if OGRH_DataManagementFrame and OGRH_DataManagementFrame:IsVisible() then
    OGRH.DataManagement.RefreshPushStructureList()
  end
end

function OGRH.DataManagement.RefreshPushStructureList()
  if not OGRH_DataManagementFrame or not OGRH_DataManagementFrame.pushScrollChild then
    return
  end
  
  local scrollChild = OGRH_DataManagementFrame.pushScrollChild
  
  -- Clear existing rows
  if scrollChild.rows then
    for i = 1, table.getn(scrollChild.rows) do
      local row = scrollChild.rows[i]
      row:Hide()
      row:SetParent(nil)
    end
  end
  scrollChild.rows = {}
  
  -- Get raid members
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    local noRaidText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noRaidText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -10)
    noRaidText:SetText("You are not in a raid.")
    noRaidText:SetTextColor(1, 0.82, 0)
    table.insert(scrollChild.rows, noRaidText)
    
    if OGRH_DataManagementFrame.pushStructureBtn then
      OGRH_DataManagementFrame.pushStructureBtn:Disable()
    end
    return
  end
  
  -- Show poll message if no responses
  if not OGRH.DataManagement.pushPollResponses or table.getn(OGRH.DataManagement.pushPollResponses) == 0 then
    local infoText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -10)
    infoText:SetText("Click Refresh to poll for addon users...")
    infoText:SetTextColor(1, 0.82, 0)
    table.insert(scrollChild.rows, infoText)
    
    if OGRH_DataManagementFrame.pushStructureBtn then
      OGRH_DataManagementFrame.pushStructureBtn:Disable()
    end
    return
  end
  
  local myChecksum = OGRH.DataManagement.GetCurrentChecksum()
  local yOffset = -5
  local rowHeight = 20
  local hasTargets = false
  
  -- Display responses
  for i = 1, table.getn(OGRH.DataManagement.pushPollResponses) do
    local response = OGRH.DataManagement.pushPollResponses[i]
    
    -- Skip self
    if response.name ~= UnitName("player") then
      local row = CreateFrame("Frame", nil, scrollChild)
      row:SetWidth(scrollChild:GetWidth() - 10)
      row:SetHeight(rowHeight)
      row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
      
      local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
      nameText:SetText(response.name)
      
      local checksumText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      checksumText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
      
      if response.checksum == myChecksum then
        checksumText:SetText("Synced (" .. response.checksum .. ")")
        checksumText:SetTextColor(0, 1, 0)
      else
        checksumText:SetText("Out of sync (" .. response.checksum .. ")")
        checksumText:SetTextColor(1, 0.65, 0)
        hasTargets = true
      end
      
      table.insert(scrollChild.rows, row)
      yOffset = yOffset - rowHeight
    end
  end
  
  -- Enable/disable push button
  if OGRH_DataManagementFrame.pushStructureBtn then
    if hasTargets then
      OGRH_DataManagementFrame.pushStructureBtn:Enable()
    else
      OGRH_DataManagementFrame.pushStructureBtn:Disable()
    end
  end
end

-------------------------------------------------------------------------------
-- UI Refresh Helper
-------------------------------------------------------------------------------

function OGRH.DataManagement.RefreshAllWindows()
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshAll then
    OGRH_EncounterSetupFrame.RefreshAll()
  end
  if OGRH_TradeSettingsFrame and OGRH_TradeSettingsFrame.RefreshList then
    OGRH_TradeSettingsFrame.RefreshList()
  end
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
    OGRH_EncounterFrame.RefreshRaidsList()
  end
  if OGRH_ConsumesFrame and OGRH_ConsumesFrame.RefreshConsumesList then
    OGRH_ConsumesFrame.RefreshConsumesList()
  end
  if RGOFrame then
    for groupNum = 1, 8 do
      for slotNum = 1, 5 do
        if OGRH.UpdateRGOSlotDisplay then
          OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
        end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- UI Window (Keeping existing UI code structure)
-- NOTE: Rest of UI code remains the same as current implementation
-------------------------------------------------------------------------------

-- UI creation code would continue here with the same structure as current file
-- but all data access goes through SVM and handles v2 schema properly
