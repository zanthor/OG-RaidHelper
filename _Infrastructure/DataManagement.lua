-- OGRH_DataManagement.lua
-- Data Management UI and Functions
-- Load Defaults, Import/Export, Push Structure

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_DataManagement requires OGRH_Core to be loaded first!|r")
  return
end

-- Initialize namespace if not exists
OGRH.DataManagement = OGRH.DataManagement or {}

-------------------------------------------------------------------------------
-- Helper: Strip Player Assignments from Encounter Management
-------------------------------------------------------------------------------

local function StripPlayerAssignments(encounterMgmt)
  if not encounterMgmt then return nil end
  
  -- Deep copy helper that strips player assignment fields
  local function deepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    
    local copy = {}
    for k, v in pairs(tbl) do
      -- Strip player assignment fields at any level
      if k == "assignedPlayers" or k == "tempAssignedPlayers" then
        -- Completely skip player assignment arrays
      else
        copy[k] = deepCopy(v)
      end
    end
    return copy
  end
  
  return deepCopy(encounterMgmt)
end

-------------------------------------------------------------------------------
-- Load Defaults
-------------------------------------------------------------------------------

function OGRH.DataManagement.LoadDefaults()
  if not OGRH.FactoryDefaults or type(OGRH.FactoryDefaults) ~= "table" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper] Error:|r No factory defaults configured in OGRH_Defaults.lua")
    DEFAULT_CHAT_FRAME:AddMessage("Edit OGRH_Defaults.lua and paste your export string after the = sign.")
    return
  end
  
  -- Check if it has the version field (basic validation)
  if not OGRH.FactoryDefaults.version then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper] Error:|r Invalid factory defaults format in OGRH_Defaults.lua")
    return
  end
  
  if OGRH.EnsureSV then
    OGRH.EnsureSV()
  end
  
  -- Use SVM to set all data (schema-independent)
  if not OGRH.SVM then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper] Error:|r SavedVariablesManager not available")
    return
  end
  
  -- Load factory defaults (v2 format: consumes, tradeItems, encounterMgmt)
  if OGRH.FactoryDefaults.consumes then
    OGRH.SVM.Set("consumes", nil, OGRH.FactoryDefaults.consumes)
  end
  if OGRH.FactoryDefaults.tradeItems then
    OGRH.SVM.Set("tradeItems", nil, OGRH.FactoryDefaults.tradeItems)
  end
  if OGRH.FactoryDefaults.encounterMgmt then
    -- Preserve Active Raid (raids[1]) when loading defaults
    local currentEncounterMgmt = OGRH.SVM.Get("encounterMgmt")
    local activeRaid = nil
    if currentEncounterMgmt and currentEncounterMgmt.raids and currentEncounterMgmt.raids[1] then
      activeRaid = OGRH.DeepCopy(currentEncounterMgmt.raids[1])
    end
    
    -- Load factory defaults
    OGRH.SVM.Set("encounterMgmt", nil, OGRH.FactoryDefaults.encounterMgmt)
    
    -- Restore Active Raid to raids[1]
    if activeRaid then
      local newEncounterMgmt = OGRH.SVM.Get("encounterMgmt")
      if newEncounterMgmt and newEncounterMgmt.raids then
        table.insert(newEncounterMgmt.raids, 1, activeRaid)
        OGRH.SVM.Set("encounterMgmt", nil, newEncounterMgmt)
      end
    end
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Factory defaults loaded successfully!")
  
  -- Refresh any open windows
  OGRH.DataManagement.RefreshAllWindows()
  
  -- Refresh data management window if open
  if OGRH_DataManagementFrame and OGRH_DataManagementFrame:IsShown() then
    OGRH.DataManagement.UpdateDetailPanel()
  end
end

function OGRH.DataManagement.GetCurrentChecksum()
  -- TODO: Revisit checksum implementation
  return "STUB_CURRENT"
end

function OGRH.DataManagement.GetDefaultsChecksum()
  -- TODO: Revisit checksum implementation
  return "STUB_DEFAULTS"
end

-------------------------------------------------------------------------------
-- Import / Export
-------------------------------------------------------------------------------

function OGRH.DataManagement.ExportData()
  if not OGRH_DataManagementFrame or not OGRH_DataManagementFrame.importExportEditBox then
    return
  end
  
  if OGRH.EnsureSV then
    OGRH.EnsureSV()
  end
  
  -- Use SVM to get data (schema-independent)
  if not OGRH.SVM then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper] Error:|r SavedVariablesManager not available")
    return
  end
  
  -- Get data and strip player assignments from encounterMgmt
  local rawEncounterMgmt = OGRH.SVM.Get("encounterMgmt")
  local cleanedEncounterMgmt = StripPlayerAssignments(rawEncounterMgmt)
  
  -- Exclude Active Raid (raids[1]) from export
  if cleanedEncounterMgmt and cleanedEncounterMgmt.raids then
    local exportRaids = {}
    for i = 2, table.getn(cleanedEncounterMgmt.raids) do
      table.insert(exportRaids, cleanedEncounterMgmt.raids[i])
    end
    cleanedEncounterMgmt.raids = exportRaids
  end
  
  local exportData = {
    version = "2.0",
    consumes = OGRH.SVM.Get("consumes") or {},
    tradeItems = OGRH.SVM.Get("tradeItems") or {},
    encounterMgmt = cleanedEncounterMgmt or {}
  }
  
  -- Serialize to compact format (pretty print chokes the game client)
  local serialized = OGRH.Serialize(exportData)
  
  local editBox = OGRH_DataManagementFrame.importExportEditBox
  editBox:SetText(serialized)
  editBox:HighlightText()
  editBox:SetFocus()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Data exported to textbox (excluding Active Raid).")
end

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
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Invalid data format.")
    return
  end
  
  if OGRH.EnsureSV then
    OGRH.EnsureSV()
  end
  
  -- Use SVM to set data (schema-independent)
  if not OGRH.SVM then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper] Error:|r SavedVariablesManager not available")
    return
  end
  
  -- Import only the data that was exported (v2 format)
  -- SVM.Set signature: Set(key, subkey, value, syncMetadata)
  -- For top-level keys, subkey is nil
  if importData.consumes then
    OGRH.SVM.Set("consumes", nil, importData.consumes)
  end
  if importData.tradeItems then
    OGRH.SVM.Set("tradeItems", nil, importData.tradeItems)
  end
  if importData.encounterMgmt then
    -- Preserve Active Raid (raids[1]) during import
    local currentEncounterMgmt = OGRH.SVM.Get("encounterMgmt")
    local activeRaid = nil
    if currentEncounterMgmt and currentEncounterMgmt.raids and currentEncounterMgmt.raids[1] then
      activeRaid = OGRH.DeepCopy(currentEncounterMgmt.raids[1])
    end
    
    -- Import the data
    OGRH.SVM.Set("encounterMgmt", nil, importData.encounterMgmt)
    
    -- Restore Active Raid to raids[1]
    if activeRaid then
      local newEncounterMgmt = OGRH.SVM.Get("encounterMgmt")
      if newEncounterMgmt and newEncounterMgmt.raids then
        table.insert(newEncounterMgmt.raids, 1, activeRaid)
        OGRH.SVM.Set("encounterMgmt", nil, newEncounterMgmt)
      end
    end
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Data imported successfully (version " .. (importData.version or "unknown") .. ").")
  
  -- Refresh all windows
  OGRH.DataManagement.RefreshAllWindows()
end

-------------------------------------------------------------------------------
-- Push Structure (uses new Sync v2)
-------------------------------------------------------------------------------

function OGRH.DataManagement.InitiatePushStructure()
  -- Use new Sync v2 system
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
  
  -- Broadcast using new system
  OGRH.Sync.BroadcastFullSync()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Broadcasting structure to raid...")
end

-- Start polling for raid member checksums (for Push Structure UI)
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
  
  -- Send poll request via MessageRouter
  OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.POLL_VERSION, "")
  
  -- Add self to responses
  local selfName = UnitName("player")
  local myChecksum = OGRH.DataManagement.GetCurrentChecksum()
  
  table.insert(OGRH.DataManagement.pushPollResponses, {
    name = selfName,
    version = OGRH.VERSION or "Unknown",
    checksum = myChecksum
  })
  
  -- Refresh the list after a short delay to collect responses
  OGRH.ScheduleFunc(function()
    OGRH.DataManagement.pushPollInProgress = false
    OGRH.DataManagement.RefreshPushStructureList()
  end, 2)
end

-- Handle poll responses for push structure
function OGRH.DataManagement.HandlePushPollResponse(sender, version, checksum)
  if not OGRH.DataManagement.pushPollInProgress then
    return
  end
  
  -- Check if already recorded
  if OGRH.DataManagement.pushPollResponses then
    for i = 1, table.getn(OGRH.DataManagement.pushPollResponses) do
      if OGRH.DataManagement.pushPollResponses[i].name == sender then
        return -- Already recorded
      end
    end
  end
  
  -- Add to responses
  table.insert(OGRH.DataManagement.pushPollResponses, {
    name = sender,
    version = version,
    checksum = checksum
  })
  
  -- Auto-refresh UI if window is visible
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
    
    -- Disable push button
    if OGRH_DataManagementFrame.pushStructureBtn then
      OGRH_DataManagementFrame.pushStructureBtn:Disable()
    end
    return
  end
  
  -- Use poll responses if available, otherwise show message
  if not OGRH.DataManagement.pushPollResponses or table.getn(OGRH.DataManagement.pushPollResponses) == 0 then
    local infoText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -10)
    infoText:SetText("Click Refresh to poll for addon users...")
    infoText:SetTextColor(1, 0.82, 0)
    table.insert(scrollChild.rows, infoText)
    
    -- Disable push button
    if OGRH_DataManagementFrame.pushStructureBtn then
      OGRH_DataManagementFrame.pushStructureBtn:Disable()
    end
    return
  end
  
  local myChecksum = OGRH.DataManagement.GetCurrentChecksum()
  local yOffset = -5
  local rowHeight = 20
  local hasTargets = false
  
  -- Display poll responses (only addon users)
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
      
      -- Show checksum and sync status
      local checksumText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      checksumText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
      
      if response.checksum == myChecksum then
        checksumText:SetText("Synced (" .. response.checksum .. ")")
        checksumText:SetTextColor(0, 1, 0)  -- Green
      else
        checksumText:SetText("Out of sync (" .. response.checksum .. ")")
        checksumText:SetTextColor(1, 0.65, 0)  -- Orange
        hasTargets = true
      end
      
      table.insert(scrollChild.rows, row)
      yOffset = yOffset - rowHeight
    end
  end
  
  -- Enable/disable push button based on targets
  if OGRH_DataManagementFrame.pushStructureBtn then
    if hasTargets then
      OGRH_DataManagementFrame.pushStructureBtn:Enable()
    else
      OGRH_DataManagementFrame.pushStructureBtn:Disable()
    end
  end
end

-------------------------------------------------------------------------------
-- UI Helper Functions
-------------------------------------------------------------------------------

function OGRH.DataManagement.RefreshAllWindows()
  -- Refresh any open windows
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
  -- Refresh RGO window (even if not visible, so it's ready when opened)
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
-- Data Management Window UI
-------------------------------------------------------------------------------

function OGRH.DataManagement.ShowWindow(forceRecreate)
  -- Create window if it doesn't exist (or force recreation)
  if forceRecreate and OGRH_DataManagementFrame then
    OGRH_DataManagementFrame:Hide()
    OGRH_DataManagementFrame = nil
  end
  
  if not OGRH_DataManagementFrame then
    local frame = CreateFrame("Frame", "OGRH_DataManagementFrame", UIParent)
    frame:SetWidth(600)
    frame:SetHeight(450)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Backdrop
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    
    -- Store frame globally before registering ESC handler
    OGRH_DataManagementFrame = frame
    
    -- Register ESC key handler
    table.insert(UISpecialFrames, "OGRH_DataManagementFrame")
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Data Management")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    if OGRH.StyleButton then
      OGRH.StyleButton(closeBtn)
    end
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOPLEFT", 20, -45)
    instructions:SetText("Select an action:")
    
    -- Create left list panel using standard template
    local listWidth = 175
    local listHeight = frame:GetHeight() - 85
    local outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGRH.CreateStyledScrollList(frame, listWidth, listHeight, true)
    outerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, -75)
    
    frame.scrollChild = scrollChild
    frame.scrollFrame = scrollFrame
    frame.scrollBar = scrollBar
    
    -- Create right detail panel
    local detailPanel = CreateFrame("Frame", nil, frame)
    detailPanel:SetWidth(380)
    detailPanel:SetHeight(listHeight)
    detailPanel:SetPoint("TOPLEFT", outerFrame, "TOPRIGHT", 10, 0)
    detailPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    detailPanel:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    
    -- Detail panel title
    local detailTitle = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailTitle:SetPoint("TOP", detailPanel, "TOP", 0, -10)
    detailTitle:SetText("Action Details")
    frame.detailTitle = detailTitle
    
    -- Checksum labels (hidden by default)
    local currentChecksumLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentChecksumLabel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 15, -35)
    currentChecksumLabel:SetJustifyH("LEFT")
    currentChecksumLabel:SetText("Current Checksum: ")
    currentChecksumLabel:Hide()
    frame.currentChecksumLabel = currentChecksumLabel
    
    local defaultsChecksumLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    defaultsChecksumLabel:SetPoint("TOPLEFT", currentChecksumLabel, "BOTTOMLEFT", 0, -5)
    defaultsChecksumLabel:SetJustifyH("LEFT")
    defaultsChecksumLabel:SetText("Defaults Checksum: ")
    defaultsChecksumLabel:Hide()
    frame.defaultsChecksumLabel = defaultsChecksumLabel
    
    -- Load Defaults button (hidden by default)
    local loadDefaultsBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
    loadDefaultsBtn:SetWidth(120)
    loadDefaultsBtn:SetHeight(24)
    loadDefaultsBtn:SetPoint("TOPLEFT", defaultsChecksumLabel, "BOTTOMLEFT", 0, -10)
    loadDefaultsBtn:SetText("Load Defaults")
    if OGRH.StyleButton then
      OGRH.StyleButton(loadDefaultsBtn)
    end
    loadDefaultsBtn:SetScript("OnClick", function()
      -- Show confirmation dialog
      StaticPopupDialogs["OGRH_CONFIRM_LOAD_DEFAULTS"] = {
        text = "Are you sure you want to load factory defaults?\n\nThis will overwrite your current configuration!",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
          OGRH.DataManagement.LoadDefaults()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true
      }
      StaticPopup_Show("OGRH_CONFIRM_LOAD_DEFAULTS")
    end)
    loadDefaultsBtn:Hide()
    frame.loadDefaultsBtn = loadDefaultsBtn
    
    -- Warning text (hidden by default)
    local warningText = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warningText:SetPoint("TOPLEFT", loadDefaultsBtn, "BOTTOMLEFT", 0, -15)
    warningText:SetPoint("RIGHT", detailPanel, "RIGHT", -15, 0)
    warningText:SetJustifyH("LEFT")
    warningText:SetJustifyV("TOP")
    warningText:SetText("This will replace all current data with:\n- Default encounter structures\n- Default role configurations\n- Default announcements\n- Default trade settings\n- Default consumes\n\nWarning: This will overwrite your current configuration!")
    warningText:SetTextColor(1, 0.82, 0)
    warningText:Hide()
    frame.warningText = warningText
    
    -- Push Structure button (hidden by default)
    local pushStructureBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
    pushStructureBtn:SetWidth(140)
    pushStructureBtn:SetHeight(24)
    pushStructureBtn:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 15, -35)
    pushStructureBtn:SetText("Push Structure")
    if OGRH.StyleButton then
      OGRH.StyleButton(pushStructureBtn)
    end
    pushStructureBtn:SetScript("OnClick", function()
      OGRH.DataManagement.InitiatePushStructure()
    end)
    pushStructureBtn:Hide()
    frame.pushStructureBtn = pushStructureBtn
    
    -- Refresh button (hidden by default)
    local refreshBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
    refreshBtn:SetWidth(70)
    refreshBtn:SetHeight(24)
    refreshBtn:SetPoint("LEFT", pushStructureBtn, "RIGHT", 5, 0)
    refreshBtn:SetText("Refresh")
    if OGRH.StyleButton then
      OGRH.StyleButton(refreshBtn)
    end
    refreshBtn:SetScript("OnClick", function()
      OGRH.DataManagement.StartPushStructurePoll()
    end)
    refreshBtn:Hide()
    frame.refreshBtn = refreshBtn
    
    -- Push Structure user list (hidden by default)
    local pushListWidth = 350
    local pushListHeight = 290
    local pushOuterFrame, pushScrollFrame, pushScrollChild, pushScrollBar, pushContentWidth = OGRH.CreateStyledScrollList(detailPanel, pushListWidth, pushListHeight)
    pushOuterFrame:SetPoint("TOPLEFT", pushStructureBtn, "BOTTOMLEFT", 0, -10)
    pushOuterFrame:Hide()
    frame.pushOuterFrame = pushOuterFrame
    frame.pushScrollChild = pushScrollChild
    frame.pushScrollFrame = pushScrollFrame
    frame.pushScrollBar = pushScrollBar
    
    -- Import/Export scrolling text box (hidden by default)
    local importExportBackdrop, importExportEditBox, importExportScrollFrame, importExportScrollBar = OGRH.CreateScrollingTextBox(detailPanel, 350, 240)
    importExportBackdrop:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 15, -35)
    importExportBackdrop:Hide()
    frame.importExportBackdrop = importExportBackdrop
    frame.importExportEditBox = importExportEditBox
    frame.importExportScrollFrame = importExportScrollFrame
    frame.importExportScrollBar = importExportScrollBar
    
    -- Import/Export buttons (hidden by default)
    local ieExportBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
    ieExportBtn:SetWidth(80)
    ieExportBtn:SetHeight(24)
    ieExportBtn:SetPoint("TOPLEFT", importExportBackdrop, "BOTTOMLEFT", 0, -10)
    ieExportBtn:SetText("Export")
    if OGRH.StyleButton then
      OGRH.StyleButton(ieExportBtn)
    end
    ieExportBtn:SetScript("OnClick", function()
      OGRH.DataManagement.ExportData()
    end)
    ieExportBtn:Hide()
    frame.ieExportBtn = ieExportBtn
    
    local ieImportBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
    ieImportBtn:SetWidth(80)
    ieImportBtn:SetHeight(24)
    ieImportBtn:SetPoint("LEFT", ieExportBtn, "RIGHT", 5, 0)
    ieImportBtn:SetText("Import")
    if OGRH.StyleButton then
      OGRH.StyleButton(ieImportBtn)
    end
    ieImportBtn:SetScript("OnClick", function()
      OGRH.DataManagement.ImportData()
    end)
    ieImportBtn:Hide()
    frame.ieImportBtn = ieImportBtn
    
    local ieClearBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
    ieClearBtn:SetWidth(80)
    ieClearBtn:SetHeight(24)
    ieClearBtn:SetPoint("LEFT", ieImportBtn, "RIGHT", 5, 0)
    ieClearBtn:SetText("Clear")
    if OGRH.StyleButton then
      OGRH.StyleButton(ieClearBtn)
    end
    ieClearBtn:SetScript("OnClick", function()
      frame.importExportEditBox:SetText("")
      frame.importExportEditBox:SetFocus()
    end)
    ieClearBtn:Hide()
    frame.ieClearBtn = ieClearBtn
    
    -- Detail text area
    local detailText = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailText:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 15, -35)
    detailText:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", -15, 15)
    detailText:SetJustifyH("LEFT")
    detailText:SetJustifyV("TOP")
    detailText:SetText("Select an action from the list to see details.")
    frame.detailText = detailText
    
    frame.detailPanel = detailPanel
    
    OGRH_DataManagementFrame = frame
    
    -- Populate the action list
    OGRH.DataManagement.RefreshActionList()
  end
  
  OGRH_DataManagementFrame:Show()
end

-- Refresh the action list
function OGRH.DataManagement.RefreshActionList()
  if not OGRH_DataManagementFrame then return end
  
  local scrollChild = OGRH_DataManagementFrame.scrollChild
  
  -- Clear existing rows
  if scrollChild.rows then
    for i = 1, table.getn(scrollChild.rows) do
      local row = scrollChild.rows[i]
      row:Hide()
      row:SetParent(nil)
    end
  end
  scrollChild.rows = {}
  
  -- Define available actions
  local actions = {
    {
      name = "Load Defaults",
      description = "Load factory default data from OGRH_Defaults.lua.\n\nThis will replace all current data with:\n- Default encounter structures\n- Default role configurations\n- Default announcements\n- Default trade settings\n- Default consumes\n\nWarning: This will overwrite your current configuration!"
    },
    {
      name = "Push Structure",
      description = "Broadcast the current encounter structure to raid members.\n\nThis uses the new OGAddonMsg-based sync system to send your current structure to all raid members."
    },
    {
      name = "Import / Export",
      description = "Import or export encounter data as text.\n\nExport: Generate a text string containing all your encounter structures, marks, numbers, announcements, trade items, and consumes.\n\nImport: Paste exported data to load it into your addon."
    }
  }
  
  local yOffset = -5
  local rowHeight = 30
  local contentWidth = scrollChild:GetWidth()
  
  for i = 1, table.getn(actions) do
    local actionData = actions[i]
    
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetWidth(contentWidth - 10)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
    row:SetNormalTexture("Interface/Buttons/UI-Listbox-Highlight2")
    row:GetNormalTexture():SetAlpha(0)
    row:SetHighlightTexture("Interface/Buttons/UI-Listbox-Highlight")
    row:GetHighlightTexture():SetBlendMode("ADD")
    
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetText(actionData.name)
    
    row:SetScript("OnClick", function()
      -- Update selected state
      OGRH_DataManagementFrame.selectedActionName = actionData.name
      
      -- Update all row backgrounds
      for j = 1, table.getn(scrollChild.rows) do
        local r = scrollChild.rows[j]
        if r == row then
          r:GetNormalTexture():SetAlpha(0.3)
        else
          r:GetNormalTexture():SetAlpha(0)
        end
      end
      
      -- Update detail panel
      OGRH.DataManagement.UpdateDetailPanel()
    end)
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - rowHeight
  end
end

-- Update the detail panel based on selected action
function OGRH.DataManagement.UpdateDetailPanel()
  if not OGRH_DataManagementFrame then return end
  
  local frame = OGRH_DataManagementFrame
  local selectedAction = frame.selectedActionName
  
  -- Hide all special controls by default
  if frame.currentChecksumLabel then frame.currentChecksumLabel:Hide() end
  if frame.defaultsChecksumLabel then frame.defaultsChecksumLabel:Hide() end
  if frame.loadDefaultsBtn then frame.loadDefaultsBtn:Hide() end
  if frame.warningText then frame.warningText:Hide() end
  if frame.pushStructureBtn then frame.pushStructureBtn:Hide() end
  if frame.refreshBtn then frame.refreshBtn:Hide() end
  if frame.pushOuterFrame then frame.pushOuterFrame:Hide() end
  if frame.importExportBackdrop then frame.importExportBackdrop:Hide() end
  if frame.ieExportBtn then frame.ieExportBtn:Hide() end
  if frame.ieImportBtn then frame.ieImportBtn:Hide() end
  if frame.ieClearBtn then frame.ieClearBtn:Hide() end
  if frame.detailText then frame.detailText:Show() end
  
  -- If Push Structure is selected, show special UI
  if selectedAction == "Push Structure" then
    if frame.detailText then frame.detailText:Hide() end
    
    -- Show push button, refresh button, and list
    if frame.pushStructureBtn then
      frame.pushStructureBtn:Show()
      frame.pushStructureBtn:Disable()
    end
    if frame.refreshBtn then
      frame.refreshBtn:Show()
    end
    if frame.pushOuterFrame then
      frame.pushOuterFrame:Show()
    end
    
    -- Start polling for raid members
    OGRH.DataManagement.StartPushStructurePoll()
    
  -- If Import / Export is selected, show special UI
  elseif selectedAction == "Import / Export" then
    if frame.detailText then frame.detailText:Hide() end
    
    -- Show import/export controls
    if frame.importExportBackdrop then frame.importExportBackdrop:Show() end
    if frame.ieExportBtn then frame.ieExportBtn:Show() end
    if frame.ieImportBtn then frame.ieImportBtn:Show() end
    if frame.ieClearBtn then frame.ieClearBtn:Show() end
    
  -- If Load Defaults is selected, show special UI
  elseif selectedAction == "Load Defaults" then
    if frame.detailText then frame.detailText:Hide() end
    
    local currentChecksum = OGRH.DataManagement.GetCurrentChecksum()
    local defaultsChecksum = OGRH.DataManagement.GetDefaultsChecksum()
    
    if frame.currentChecksumLabel then
      frame.currentChecksumLabel:SetText("Current Checksum: " .. currentChecksum)
      frame.currentChecksumLabel:Show()
    end
    
    if frame.defaultsChecksumLabel then
      frame.defaultsChecksumLabel:SetText("Defaults Checksum: " .. defaultsChecksum)
      frame.defaultsChecksumLabel:Show()
    end
    
    if frame.loadDefaultsBtn then
      frame.loadDefaultsBtn:Show()
      
      -- Enable or disable button based on checksum match
      if currentChecksum == defaultsChecksum then
        frame.loadDefaultsBtn:Disable()
        frame.loadDefaultsBtn:SetText("Already Loaded")
      else
        frame.loadDefaultsBtn:Enable()
        frame.loadDefaultsBtn:SetText("Load Defaults")
      end
    end
    
    -- Show warning text
    if frame.warningText then
      frame.warningText:Show()
    end
  end
end

-- Legacy compatibility - redirect old Sync namespace calls to DataManagement
if OGRH.Sync then
  OGRH.Sync.ShowDataManagementWindow = OGRH.DataManagement.ShowWindow
  OGRH.Sync.LoadDefaults = OGRH.DataManagement.LoadDefaults
  OGRH.Sync.ExportData = OGRH.DataManagement.ExportData
  OGRH.Sync.ImportData = OGRH.DataManagement.ImportData
  OGRH.Sync.UpdateDetailPanel = OGRH.DataManagement.UpdateDetailPanel
  OGRH.Sync.RefreshDataManagementList = OGRH.DataManagement.RefreshActionList
  OGRH.Sync.InitiatePushStructure = OGRH.DataManagement.InitiatePushStructure
  OGRH.Sync.StartPushStructurePoll = OGRH.DataManagement.StartPushStructurePoll
  OGRH.Sync.HandlePushPollResponse = OGRH.DataManagement.HandlePushPollResponse
  OGRH.Sync.GetCurrentChecksum = OGRH.DataManagement.GetCurrentChecksum
  OGRH.Sync.GetDefaultsChecksum = OGRH.DataManagement.GetDefaultsChecksum
end

OGRH.Msg("|cff00ccff[RH-DataManagement]|r Loaded")
