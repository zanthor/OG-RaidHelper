-- OGRH_Sync.lua
-- Unified synchronization system for OG-RaidHelper
-- Handles compression, encoding, and transmission of raid data

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_Sync requires OGRH_Core to be loaded first!|r")
  return
end

-- Initialize sync namespace
OGRH.Sync = OGRH.Sync or {}

-- Configuration constants
OGRH.Sync.MAX_CHUNK_SIZE = 250 -- Maximum bytes per addon message (WoW limit is ~255)
OGRH.Sync.ADDON_PREFIX = "OGRH" -- Registered addon communication prefix

-- Message types for different sync operations
OGRH.Sync.MessageType = {
  ENCOUNTER_STRUCTURE = "ENC_STRUCT",
  ENCOUNTER_ASSIGNMENTS = "ENC_ASSIGN",
  ENCOUNTER_ANNOUNCEMENT = "ENC_ANNOUNCE",
  READHELPER_SYNC = "RH_SYNC",
  CHUNK_START = "CHUNK_START",
  CHUNK_DATA = "CHUNK_DATA",
  CHUNK_END = "CHUNK_END",
}

-- Active receiving state for chunked messages
OGRH.Sync.ReceivingChunks = {}

-- Sync state tracking
OGRH.Sync.syncTransmitting = false
OGRH.Sync.syncReceiving = false

-------------------------------------------------------------------------------
-- Encoding Functions
-------------------------------------------------------------------------------

-- Encode data for transmission (serialize only, no compression)
-- Parameters:
--   data: Table to be serialized and encoded
-- Returns: Encoded string ready for transmission, or nil on error
function OGRH.Sync.EncodeData(data)
  if not data then
    return nil
  end
  
  -- Serialize the table to a string
  local serialized = OGRH.Sync.Serialize(data)
  if not serialized then
    return nil
  end
  
  return serialized
end

-- Decode received data
-- Parameters:
--   encoded: Encoded string received from addon message
-- Returns: Deserialized table, or nil on error
function OGRH.Sync.DecodeData(encoded)
  if not encoded or encoded == "" then
    return nil
  end
  
  -- Deserialize back to table
  local data = OGRH.Sync.Deserialize(encoded)
  return data
end

-------------------------------------------------------------------------------
-- Serialization Functions
-------------------------------------------------------------------------------

-- Simple table serialization (can be replaced with AceSerializer if needed)
-- Parameters:
--   tbl: Table to serialize
-- Returns: String representation of table
function OGRH.Sync.Serialize(tbl)
  if type(tbl) ~= "table" then
    return tostring(tbl)
  end
  
  local result = "{"
  local first = true
  
  for k, v in pairs(tbl) do
    if not first then
      result = result .. ","
    end
    first = false
    
    -- Serialize key
    if type(k) == "number" then
      result = result .. "[" .. k .. "]="
    else
      result = result .. "[" .. string.format("%q", k) .. "]="
    end
    
    -- Serialize value
    if type(v) == "table" then
      result = result .. OGRH.Sync.Serialize(v)
    elseif type(v) == "string" then
      result = result .. string.format("%q", v)
    elseif type(v) == "boolean" then
      result = result .. tostring(v)
    else
      result = result .. tostring(v)
    end
  end
  
  result = result .. "}"
  return result
end

-- Simple table deserialization
-- Parameters:
--   str: Serialized string
-- Returns: Deserialized table
function OGRH.Sync.Deserialize(str)
  if not str or str == "" then
    return nil
  end
  
  -- Use loadstring to evaluate the table string
  local func = loadstring("return " .. str)
  if not func then
    return nil
  end
  
  local success, result = pcall(func)
  if success then
    return result
  else
    return nil
  end
end

-------------------------------------------------------------------------------
-- Chunked Transmission Functions
-------------------------------------------------------------------------------

-- Send data in chunks if it exceeds max size
-- Parameters:
--   data: Table to send
--   messageType: Type of message (from OGRH.Sync.MessageType)
--   channel: "RAID", "PARTY", "GUILD", or "WHISPER"
--   target: Player name if channel is "WHISPER"
function OGRH.Sync.SendChunked(data, messageType, channel, target)
  local encoded = OGRH.Sync.EncodeData(data)
  if not encoded then
    return false
  end
  
  local dataSize = string.len(encoded)
  
  -- If data fits in single message, send directly
  if dataSize <= OGRH.Sync.MAX_CHUNK_SIZE then
    OGRH.Sync.SendMessage(messageType, encoded, channel, target)
    return true
  end
  
  -- Split into chunks
  local chunks = {}
  local pos = 1
  while pos <= dataSize do
    local chunk = string.sub(encoded, pos, pos + OGRH.Sync.MAX_CHUNK_SIZE - 1)
    table.insert(chunks, chunk)
    pos = pos + OGRH.Sync.MAX_CHUNK_SIZE
  end
  
  local chunkId = OGRH.Sync.GenerateChunkId()
  local totalChunks = table.getn(chunks)
  
  -- Send chunk start message
  local startData = {
    id = chunkId,
    type = messageType,
    total = totalChunks,
    size = dataSize
  }
  OGRH.Sync.SendMessage(OGRH.Sync.MessageType.CHUNK_START, OGRH.Sync.Serialize(startData), channel, target)
  
  -- Send each chunk
  for i = 1, totalChunks do
    local chunkData = {
      id = chunkId,
      index = i,
      data = chunks[i]
    }
    OGRH.Sync.SendMessage(OGRH.Sync.MessageType.CHUNK_DATA, OGRH.Sync.Serialize(chunkData), channel, target)
  end
  
  -- Send chunk end message
  local endData = {
    id = chunkId,
    total = totalChunks
  }
  OGRH.Sync.SendMessage(OGRH.Sync.MessageType.CHUNK_END, OGRH.Sync.Serialize(endData), channel, target)
  
  return true
end

-- Handle received chunk
-- Parameters:
--   sender: Player name who sent the message
--   messageType: Type of message
--   data: Message data
function OGRH.Sync.HandleChunk(sender, messageType, data)
  if messageType == OGRH.Sync.MessageType.CHUNK_START then
    local startInfo = OGRH.Sync.Deserialize(data)
    if startInfo then
      OGRH.Sync.ReceivingChunks[startInfo.id] = {
        sender = sender,
        type = startInfo.type,
        total = startInfo.total,
        size = startInfo.size,
        chunks = {},
        received = 0
      }
    end
    
  elseif messageType == OGRH.Sync.MessageType.CHUNK_DATA then
    local chunkInfo = OGRH.Sync.Deserialize(data)
    if chunkInfo and OGRH.Sync.ReceivingChunks[chunkInfo.id] then
      local receiving = OGRH.Sync.ReceivingChunks[chunkInfo.id]
      receiving.chunks[chunkInfo.index] = chunkInfo.data
      receiving.received = receiving.received + 1
    end
    
  elseif messageType == OGRH.Sync.MessageType.CHUNK_END then
    local endInfo = OGRH.Sync.Deserialize(data)
    if endInfo and OGRH.Sync.ReceivingChunks[endInfo.id] then
      local receiving = OGRH.Sync.ReceivingChunks[endInfo.id]
      
      -- Verify all chunks received
      if receiving.received == receiving.total then
        -- Reassemble chunks
        local fullData = ""
        for i = 1, receiving.total do
          fullData = fullData .. receiving.chunks[i]
        end
        
        -- Decode
        local decodedData = OGRH.Sync.DecodeData(fullData)
        if decodedData then
          -- Route to appropriate handler based on original message type
          OGRH.Sync.RouteMessage(receiving.sender, receiving.type, decodedData)
        end
      end
      
      -- Clean up
      OGRH.Sync.ReceivingChunks[endInfo.id] = nil
    end
  end
end

-------------------------------------------------------------------------------
-- Message Routing Functions
-------------------------------------------------------------------------------

-- Send a message via addon communication
-- Parameters:
--   messageType: Type of message (from OGRH.Sync.MessageType)
--   data: String data to send
--   channel: "RAID", "PARTY", "GUILD", or "WHISPER"
--   target: Player name if channel is "WHISPER"
function OGRH.Sync.SendMessage(messageType, data, channel, target)
  local message = messageType .. ":" .. data
  
  if channel == "WHISPER" and target then
    SendAddonMessage(OGRH.Sync.ADDON_PREFIX, message, channel, target)
  else
    SendAddonMessage(OGRH.Sync.ADDON_PREFIX, message, channel)
  end
end

-- Route received message to appropriate handler
-- Parameters:
--   sender: Player name who sent the message
--   messageType: Type of message
--   data: Decoded/decompressed data table
function OGRH.Sync.RouteMessage(sender, messageType, data)
  -- TODO: Implement routing to specific handlers based on message type
  -- This will be filled in as we migrate existing sync code
  
  if messageType == OGRH.Sync.MessageType.ENCOUNTER_STRUCTURE then
    -- Route to encounter structure handler
    if OGRH.HandleEncounterSync then
      OGRH.HandleEncounterSync(sender, data)
    end
    
  elseif messageType == OGRH.Sync.MessageType.ENCOUNTER_ASSIGNMENTS then
    -- Route to assignment handler
    if OGRH.HandleAssignmentSync then
      OGRH.HandleAssignmentSync(sender, data)
    end
    
  elseif messageType == OGRH.Sync.MessageType.READHELPER_SYNC then
    -- Route to ReadHelper sync handler
    if OGRH.HandleReadHelperSync then
      OGRH.HandleReadHelperSync(sender, data)
    end
    
  elseif messageType == "ROLESUI_SYNC" then
    -- Route to RolesUI sync handler
    if OGRH.HandleRolesUISync then
      OGRH.HandleRolesUISync(sender, data)
    end
  end
end

-------------------------------------------------------------------------------
-- Utility Functions
-------------------------------------------------------------------------------

-- Generate unique chunk ID
function OGRH.Sync.GenerateChunkId()
  return "CHUNK_" .. GetTime() .. "_" .. math.random(1000, 9999)
end

-------------------------------------------------------------------------------
-- Event Registration
-------------------------------------------------------------------------------

-- Note: Turtle WoW does not require RegisterAddonMessagePrefix

-- Create event handler frame
local syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("CHAT_MSG_ADDON")

syncFrame:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    local prefix, message, channel, sender = arg1, arg2, arg3, arg4
    
    if prefix == OGRH.Sync.ADDON_PREFIX then
      -- Handle special sync protocol messages
      if string.find(message, "SYNC_REQUEST:") == 1 then
        local checksum = string.sub(message, 14)
        OGRH.Sync.HandleSyncRequest(sender, checksum)
        return
      elseif string.find(message, "SYNC_RESPONSE:") == 1 then
        local data = string.sub(message, 15)
        local colonPos = string.find(data, ":")
        if colonPos then
          local response = string.sub(data, 1, colonPos - 1)
          local target = string.sub(data, colonPos + 1)
          -- Only process if we're the intended recipient
          if target == UnitName("player") then
            OGRH.Sync.HandleSyncResponse(sender, response)
          end
        end
        return
      elseif message == "SYNC_CANCEL" then
        OGRH.Sync.HandleSyncCancel(sender)
        return
      elseif string.find(message, "SYNC_DATA_START:") == 1 then
        local data = string.sub(message, 17)
        OGRH.Sync.HandleSyncDataStart(sender, data)
        return
      elseif string.find(message, "SYNC_DATA_CHUNK:") == 1 then
        local data = string.sub(message, 17)
        OGRH.Sync.HandleSyncDataChunk(sender, data)
        return
      elseif string.find(message, "SYNC_DATA_END:") == 1 then
        local data = string.sub(message, 15)
        OGRH.Sync.HandleSyncDataEnd(sender, data)
        return
      end
      
      -- Parse message type and data
      local colonPos = string.find(message, ":")
      if colonPos then
        local messageType = string.sub(message, 1, colonPos - 1)
        local data = string.sub(message, colonPos + 1)
        
        -- Check if this is a chunked message
        if messageType == OGRH.Sync.MessageType.CHUNK_START or
           messageType == OGRH.Sync.MessageType.CHUNK_DATA or
           messageType == OGRH.Sync.MessageType.CHUNK_END then
          OGRH.Sync.HandleChunk(sender, messageType, data)
        else
          -- Handle single message
          local decodedData = OGRH.Sync.DecodeData(data)
          if decodedData then
            OGRH.Sync.RouteMessage(sender, messageType, decodedData)
          end
        end
      end
    end
  end
end)

-------------------------------------------------------------------------------
-- Data Management Window
-------------------------------------------------------------------------------

-- Show Data Management window with action list and detail panel
function OGRH.Sync.ShowDataManagementWindow(forceRecreate)
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
          OGRH.Sync.LoadDefaults()
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
      OGRH.Sync.InitiatePushStructure()
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
      OGRH.Sync.StartPushStructurePoll()
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
    
    -- Set up keyboard capture on the detail panel
    detailPanel:EnableKeyboard(true)
    detailPanel:SetScript("OnKeyDown", function()
      if arg1 == "ESCAPE" then
        -- Pass ESC through to close the window
        frame:Hide()
      end
    end)
    
    -- Set focus to editbox when Import/Export is shown
    local originalUpdateDetailPanel = OGRH.Sync.UpdateDetailPanel
    OGRH.Sync.UpdateDetailPanel = function()
      originalUpdateDetailPanel()
      if frame.selectedActionName == "Import / Export" and frame.importExportBackdrop and frame.importExportBackdrop:IsVisible() then
        frame.importExportEditBox:SetFocus()
      end
    end
    
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
      OGRH.Sync.ExportData()
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
      OGRH.Sync.ImportData()
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
    OGRH.Sync.RefreshDataManagementList()
  end
  
  OGRH_DataManagementFrame:Show()
end

-- Update the detail panel based on selected action
function OGRH.Sync.UpdateDetailPanel()
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
    OGRH.Sync.StartPushStructurePoll()
    
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
    
    local currentChecksum = OGRH.Sync.GetCurrentChecksum()
    local defaultsChecksum = OGRH.Sync.GetDefaultsChecksum()
    
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

-- Refresh the data management action list
function OGRH.Sync.RefreshDataManagementList()
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
      description = "Load factory default data from OGRH_Defaults.lua.\n\nThis will replace all current data with:\n- Default encounter structures\n- Default role configurations\n- Default announcements\n- Default trade settings\n- Default consumes\n\nWarning: This will overwrite your current configuration!",
      action = function()
        if OGRH.Sync.LoadDefaults then
          OGRH.Sync.LoadDefaults()
        end
      end
    },
    {
      name = "Push Structure",
      description = "Broadcast the current encounter structure to raid members.\n\nThis will poll raid members and send your current structure to anyone with a different checksum.",
      action = nil
    },
    {
      name = "Import / Export",
      description = "Import or export encounter data as text.\n\nExport: Generate a text string containing all your encounter structures, marks, numbers, announcements, trade items, and consumes.\n\nImport: Paste exported data to load it into your addon.",
      action = nil
    }
  }
  
  local yOffset = -5
  local contentWidth = scrollChild:GetWidth()
  
  for i = 1, table.getn(actions) do
    local actionData = actions[i]
    local idx = i
    
    -- Create list item using standard template
    local row = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    
    -- Row text
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", row, "LEFT", 5, 0)
    text:SetText(actionData.name)
    row.text = text
    
    -- Click handler
    row:SetScript("OnClick", function()
      -- Update detail panel
      if OGRH_DataManagementFrame.detailTitle then
        OGRH_DataManagementFrame.detailTitle:SetText(actionData.name)
      end
      if OGRH_DataManagementFrame.detailText then
        OGRH_DataManagementFrame.detailText:SetText(actionData.description)
      end
      
      -- Deselect previous row
      if OGRH_DataManagementFrame.selectedRow and OGRH_DataManagementFrame.selectedRow ~= this then
        local prevRow = OGRH_DataManagementFrame.selectedRow
        prevRow.isSelected = false
        prevRow.bg:SetVertexColor(
          OGRH.LIST_COLORS.INACTIVE.r,
          OGRH.LIST_COLORS.INACTIVE.g,
          OGRH.LIST_COLORS.INACTIVE.b,
          OGRH.LIST_COLORS.INACTIVE.a
        )
      end
      
      -- Select this row
      this.isSelected = true
      this.bg:SetVertexColor(
        OGRH.LIST_COLORS.SELECTED.r,
        OGRH.LIST_COLORS.SELECTED.g,
        OGRH.LIST_COLORS.SELECTED.b,
        OGRH.LIST_COLORS.SELECTED.a
      )
      OGRH_DataManagementFrame.selectedRow = this
      OGRH_DataManagementFrame.selectedAction = actionData.action
      OGRH_DataManagementFrame.selectedActionName = actionData.name
      
      -- Update special panel content
      OGRH.Sync.UpdateDetailPanel()
    end)
    
    -- Double-click to execute
    row:SetScript("OnDoubleClick", function()
      if actionData.action then
        actionData.action()
      end
    end)
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT - OGRH.LIST_ITEM_SPACING
  end
  
  -- Update scroll child height
  local contentHeight = math.abs(yOffset) + 5
  scrollChild:SetHeight(math.max(contentHeight, 1))
  
  -- Scrollbar is always hidden for this list (passed hideScrollBar=true to template)
  -- No need to show/hide dynamically
end

-- Calculate checksum for a data table
-- Uses the same algorithm as OGRH.CalculateAllStructureChecksum
function OGRH.Sync.CalculateChecksum(data)
  if not data or type(data) ~= "table" then
    return "0"
  end
  
  local checksum = 0
  
  -- Hash raids list (from encounterMgmt.raids)
  if data.encounterMgmt and data.encounterMgmt.raids then
    for i = 1, table.getn(data.encounterMgmt.raids) do
      local raidName = data.encounterMgmt.raids[i]
      for j = 1, string.len(raidName) do
        checksum = checksum + string.byte(raidName, j) * i * 50
      end
    end
  end
  
  -- Hash encounters list (from encounterMgmt.encounters)
  if data.encounterMgmt and data.encounterMgmt.encounters then
    for raidName, encounters in pairs(data.encounterMgmt.encounters) do
      if type(encounters) == "table" then
        for i = 1, table.getn(encounters) do
          local encounterName = encounters[i]
          for j = 1, string.len(encounterName) do
            checksum = checksum + string.byte(encounterName, j) * i * 100
          end
        end
      end
    end
  end
  
  -- Hash all encounter roles (from encounterMgmt.roles)
  if data.encounterMgmt and data.encounterMgmt.roles then
    for raidName, raids in pairs(data.encounterMgmt.roles) do
      for encounterName, encounter in pairs(raids) do
        -- Hash roles from column1
        if encounter.column1 then
          for i = 1, table.getn(encounter.column1) do
            local role = encounter.column1[i]
            checksum = checksum + OGRH.HashRole(role, 10, i)
          end
        end
        
        -- Hash roles from column2
        if encounter.column2 then
          for i = 1, table.getn(encounter.column2) do
            local role = encounter.column2[i]
            checksum = checksum + OGRH.HashRole(role, 20, i)
          end
        end
      end
    end
  end
  
  -- Hash all raid marks
  if data.encounterRaidMarks then
    for raidName, raids in pairs(data.encounterRaidMarks) do
      for encounterName, encounter in pairs(raids) do
        for roleIdx, roleMarks in pairs(encounter) do
          for slotIdx, markValue in pairs(roleMarks) do
            if type(markValue) == "number" then
              checksum = checksum + (markValue * slotIdx * roleIdx * 1000)
            end
          end
        end
      end
    end
  end
  
  -- Hash all assignment numbers
  if data.encounterAssignmentNumbers then
    for raidName, raids in pairs(data.encounterAssignmentNumbers) do
      for encounterName, encounter in pairs(raids) do
        for roleIdx, roleNumbers in pairs(encounter) do
          for slotIdx, numberValue in pairs(roleNumbers) do
            if type(numberValue) == "number" then
              checksum = checksum + (numberValue * slotIdx * roleIdx * 500)
            end
          end
        end
      end
    end
  end
  
  -- Hash all announcements
  if data.encounterAnnouncements then
    for raidName, raids in pairs(data.encounterAnnouncements) do
      for encounterName, announcements in pairs(raids) do
        if type(announcements) == "table" then
          for i = 1, table.getn(announcements) do
            local line = announcements[i]
            if type(line) == "string" then
              for j = 1, string.len(line) do
                checksum = checksum + string.byte(line, j) * i
              end
            end
          end
        elseif type(announcements) == "string" then
          for j = 1, string.len(announcements) do
            checksum = checksum + string.byte(announcements, j)
          end
        end
      end
    end
  end
  
  -- Hash tradeItems (using keys from pairs, matching CalculateAllStructureChecksum)
  if data.tradeItems then
    for itemName, itemData in pairs(data.tradeItems) do
      for j = 1, string.len(itemName) do
        checksum = checksum + string.byte(itemName, j) * 30
      end
    end
  end
  
  -- Hash consumes (using keys from pairs, matching CalculateAllStructureChecksum)
  if data.consumes then
    for consumeName, consumeData in pairs(data.consumes) do
      for j = 1, string.len(consumeName) do
        checksum = checksum + string.byte(consumeName, j) * 40
      end
    end
  end
  
  return tostring(checksum)
end

-- Get checksum for current saved data
function OGRH.Sync.GetCurrentChecksum()
  if OGRH.EnsureSV then
    OGRH.EnsureSV()
  end
  
  local currentData = {
    encounterMgmt = OGRH_SV.encounterMgmt,
    encounterRaidMarks = OGRH_SV.encounterRaidMarks,
    encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers,
    encounterAnnouncements = OGRH_SV.encounterAnnouncements,
    tradeItems = OGRH_SV.tradeItems,
    consumes = OGRH_SV.consumes
  }
  
  return OGRH.Sync.CalculateChecksum(currentData)
end

-- Get checksum for factory defaults
function OGRH.Sync.GetDefaultsChecksum()
  if not OGRH.FactoryDefaults or type(OGRH.FactoryDefaults) ~= "table" then
    return "NO_DEFAULTS"
  end
  
  local defaultsData = {
    encounterMgmt = OGRH.FactoryDefaults.encounterMgmt,
    encounterRaidMarks = OGRH.FactoryDefaults.encounterRaidMarks,
    encounterAssignmentNumbers = OGRH.FactoryDefaults.encounterAssignmentNumbers,
    encounterAnnouncements = OGRH.FactoryDefaults.encounterAnnouncements,
    tradeItems = OGRH.FactoryDefaults.tradeItems,
    consumes = OGRH.FactoryDefaults.consumes
  }
  
  return OGRH.Sync.CalculateChecksum(defaultsData)
end

-- Load factory defaults (identical to Import/Export Defaults button)
function OGRH.Sync.LoadDefaults()
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
  
  -- Import all encounter management data directly from the table
  if OGRH.FactoryDefaults.encounterMgmt then
    OGRH_SV.encounterMgmt = OGRH.FactoryDefaults.encounterMgmt
  end
  if OGRH.FactoryDefaults.encounterRaidMarks then
    OGRH_SV.encounterRaidMarks = OGRH.FactoryDefaults.encounterRaidMarks
  end
  if OGRH.FactoryDefaults.encounterAssignmentNumbers then
    OGRH_SV.encounterAssignmentNumbers = OGRH.FactoryDefaults.encounterAssignmentNumbers
  end
  if OGRH.FactoryDefaults.encounterAnnouncements then
    OGRH_SV.encounterAnnouncements = OGRH.FactoryDefaults.encounterAnnouncements
  end
  if OGRH.FactoryDefaults.tradeItems then
    OGRH_SV.tradeItems = OGRH.FactoryDefaults.tradeItems
  end
  if OGRH.FactoryDefaults.consumes then
    OGRH_SV.consumes = OGRH.FactoryDefaults.consumes
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Factory defaults loaded successfully!")
  
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
  
  -- Refresh data management window if open
  if OGRH_DataManagementFrame and OGRH_DataManagementFrame:IsShown() then
    OGRH.Sync.UpdateDetailPanel()
  end
end

-------------------------------------------------------------------------------
-- Import / Export Functions
-------------------------------------------------------------------------------

-- Export data to text
function OGRH.Sync.ExportData()
  if not OGRH_DataManagementFrame or not OGRH_DataManagementFrame.importExportEditBox then
    return
  end
  
  if OGRH.EnsureSV then
    OGRH.EnsureSV()
  end
  
  -- Collect all encounter management data (same as OGRH.ExportShareData)
  local encounterMgmt = {}
  if OGRH_SV.encounterMgmt then
    encounterMgmt.raids = OGRH_SV.encounterMgmt.raids
    encounterMgmt.encounters = OGRH_SV.encounterMgmt.encounters
    encounterMgmt.roles = OGRH_SV.encounterMgmt.roles
  end
  
  local exportData = {
    version = "1.0",
    encounterMgmt = encounterMgmt,
    encounterRaidMarks = OGRH_SV.encounterRaidMarks or {},
    encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {},
    encounterAnnouncements = OGRH_SV.encounterAnnouncements or {},
    tradeItems = OGRH_SV.tradeItems or {},
    consumes = OGRH_SV.consumes or {}
  }
  
  -- Serialize to string
  local serialized = OGRH.Sync.Serialize(exportData)
  
  local editBox = OGRH_DataManagementFrame.importExportEditBox
  editBox:SetText(serialized)
  editBox:HighlightText()
  editBox:SetFocus()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Data exported to textbox.")
end

-- Import data from text
function OGRH.Sync.ImportData()
  if not OGRH_DataManagementFrame or not OGRH_DataManagementFrame.importExportEditBox then
    return
  end
  
  local editBox = OGRH_DataManagementFrame.importExportEditBox
  local dataString = editBox:GetText()
  
  if not dataString or dataString == "" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r No data to import.")
    return
  end
  
  -- Deserialize (same as OGRH.ImportShareData)
  local success, importData = pcall(OGRH.Sync.Deserialize, dataString)
  
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
  
  -- Full import - overwrite everything
  if importData.encounterMgmt then
    OGRH_SV.encounterMgmt = importData.encounterMgmt
  end
  if importData.encounterRaidMarks then
    OGRH_SV.encounterRaidMarks = importData.encounterRaidMarks
  end
  if importData.encounterAssignmentNumbers then
    OGRH_SV.encounterAssignmentNumbers = importData.encounterAssignmentNumbers
  end
  if importData.encounterAnnouncements then
    OGRH_SV.encounterAnnouncements = importData.encounterAnnouncements
  end
  if importData.tradeItems then
    OGRH_SV.tradeItems = importData.tradeItems
  end
  if importData.consumes then
    OGRH_SV.consumes = importData.consumes
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Encounter data imported successfully.")
  
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
end

-------------------------------------------------------------------------------
-- Push Structure Functions
-------------------------------------------------------------------------------

-- Start poll for push structure
function OGRH.Sync.StartPushStructurePoll()
  -- Must be in a raid
  if GetNumRaidMembers() == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r You must be in a raid to push structure.")
    return
  end
  
  -- Must be raid leader or assistant
  local playerName = UnitName("player")
  local hasPermission = false
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == playerName and (rank == 2 or rank == 1) then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Only raid leaders or assistants can push structure.")
    return
  end
  
  -- Reset poll state
  OGRH.Sync.pushPollResponses = {}
  OGRH.Sync.pushPollInProgress = true
  
  -- Send poll request
  SendAddonMessage(OGRH.Sync.ADDON_PREFIX, "ADDON_POLL", "RAID")
  
  -- Add self to responses
  local selfName = UnitName("player")
  local checksum = OGRH.Sync.GetCurrentChecksum()
  
  table.insert(OGRH.Sync.pushPollResponses, {
    name = selfName,
    version = OGRH.VERSION or "Unknown",
    checksum = checksum
  })
  
  -- Refresh list
  OGRH.Sync.RefreshPushStructureList()
  
  -- Keep poll open for 3 seconds
  OGRH.ScheduleFunc(function()
    OGRH.Sync.pushPollInProgress = false
    OGRH.Sync.RefreshPushStructureList()
  end, 3)
end

-- Handle poll response for push structure
function OGRH.Sync.HandlePushPollResponse(sender, version, checksum)
  if not OGRH.Sync.pushPollInProgress then
    return
  end
  
  -- Check if already in list
  if OGRH.Sync.pushPollResponses then
    for i = 1, table.getn(OGRH.Sync.pushPollResponses) do
      if OGRH.Sync.pushPollResponses[i].name == sender then
        return -- Already recorded
      end
    end
  end
  
  -- Add to list
  table.insert(OGRH.Sync.pushPollResponses, {
    name = sender,
    version = version or "Unknown",
    checksum = checksum or "0"
  })
  
  -- Refresh list
  OGRH.Sync.RefreshPushStructureList()
end

-- Refresh push structure user list
function OGRH.Sync.RefreshPushStructureList()
  if not OGRH_DataManagementFrame then return end
  
  local scrollChild = OGRH_DataManagementFrame.pushScrollChild
  local frame = OGRH_DataManagementFrame
  
  -- Clear existing rows
  if scrollChild.rows then
    for i = 1, table.getn(scrollChild.rows) do
      local row = scrollChild.rows[i]
      row:Hide()
      row:SetParent(nil)
    end
  end
  scrollChild.rows = {}
  
  if not OGRH.Sync.pushPollResponses then
    OGRH.Sync.pushPollResponses = {}
  end
  
  local myChecksum = OGRH.Sync.GetCurrentChecksum()
  local hasChecksumMismatch = false
  
  local yOffset = -5
  local contentWidth = scrollChild:GetWidth()
  
  for i = 1, table.getn(OGRH.Sync.pushPollResponses) do
    local userData = OGRH.Sync.pushPollResponses[i]
    
    -- Create list item using Button type for proper styling
    local row = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    
    -- Get class color from cache
    local classColor = {r = 1, g = 1, b = 1}
    local playerClass = OGRH.GetPlayerClass and OGRH.GetPlayerClass(userData.name)
    if playerClass and OGRH.CLASS_RGB and OGRH.CLASS_RGB[playerClass] then
      local rgb = OGRH.CLASS_RGB[playerClass]
      classColor = {r = rgb[1], g = rgb[2], b = rgb[3]}
    end
    
    -- Name (left aligned, class colored)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetText(userData.name)
    nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    nameText:SetWidth(120)
    nameText:SetJustifyH("LEFT")
    
    -- Version
    local versionText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("LEFT", row, "LEFT", 130, 0)
    versionText:SetText(userData.version)
    versionText:SetWidth(50)
    versionText:SetJustifyH("LEFT")
    
    -- Checksum (colored based on match)
    local checksumText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checksumText:SetPoint("LEFT", row, "LEFT", 185, 0)
    checksumText:SetText(userData.checksum)
    checksumText:SetWidth(165)
    checksumText:SetJustifyH("LEFT")
    
    -- Color checksum based on match
    if userData.checksum ~= myChecksum then
      checksumText:SetTextColor(1, 0, 0) -- Red for mismatch
      hasChecksumMismatch = true
    else
      checksumText:SetTextColor(0, 1, 0) -- Green for match
    end
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT - OGRH.LIST_ITEM_SPACING
  end
  
  -- Update scroll child height
  local contentHeight = math.abs(yOffset) + 5
  scrollChild:SetHeight(math.max(contentHeight, 1))
  
  -- Update scrollbar
  if frame.pushScrollBar and frame.pushScrollFrame then
    local scrollBar = frame.pushScrollBar
    local scrollFrame = frame.pushScrollFrame
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll > 0 then
      scrollBar:SetMinMaxValues(0, maxScroll)
      scrollBar:Show()
    else
      scrollBar:Hide()
    end
  end
  
  -- Enable/disable push button based on checksum mismatch
  if frame.pushStructureBtn then
    if hasChecksumMismatch then
      frame.pushStructureBtn:Enable()
    else
      frame.pushStructureBtn:Disable()
    end
  end
end

-------------------------------------------------------------------------------
-- Sync Panel (appears for sender and receivers)
-------------------------------------------------------------------------------

-- Create or show sync panel
function OGRH.Sync.ShowSyncPanel(isSender)
  if OGRH_SyncPanelFrame then
    OGRH_SyncPanelFrame:Show()
    OGRH.Sync.UpdateSyncPanel(isSender)
    -- Manually register and reposition
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(OGRH_SyncPanelFrame, 30)
    end
    if OGRH.RepositionAuxiliaryPanels then
      OGRH.RepositionAuxiliaryPanels()
    end
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_SyncPanelFrame", UIParent)
  frame:SetWidth(180)
  frame:SetHeight(100) -- Increased base height
  frame:SetFrameStrata("MEDIUM")
  frame:EnableMouse(true)
  
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  
  -- Register with auxiliary panel system (priority 30)
  frame:SetScript("OnShow", function()
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(this, 30)
    end
  end)
  
  frame:SetScript("OnHide", function()
    if OGRH.UnregisterAuxiliaryPanel then
      OGRH.UnregisterAuxiliaryPanel(this)
    end
  end)
  
  -- Manually register immediately
  if OGRH.RegisterAuxiliaryPanel then
    OGRH.RegisterAuxiliaryPanel(frame, 30)
  end
  
  -- Register for main UI movement to reposition
  frame:SetScript("OnUpdate", function()
    if not this:IsVisible() then
      return
    end
    
    if this.lastMainPos then
      local currentPos = OGRH_Main and OGRH_Main:GetLeft()
      if currentPos and currentPos ~= this.lastMainPos then
        this:PositionFrame()
        this.lastMainPos = currentPos
      end
    else
      this.lastMainPos = OGRH_Main and OGRH_Main:GetLeft()
    end
  end)
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -10)
  title:SetText("Structure Sync")
  frame.title = title
  
  -- Status text
  local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusText:SetPoint("TOP", title, "BOTTOM", 0, -8)
  statusText:SetWidth(160)
  statusText:SetJustifyH("CENTER")
  frame.statusText = statusText
  
  -- Accept button (for receivers)
  local acceptBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  acceptBtn:SetWidth(70)
  acceptBtn:SetHeight(24)
  acceptBtn:SetPoint("BOTTOM", frame, "BOTTOM", -38, 10)
  acceptBtn:SetText("Accept")
  if OGRH.StyleButton then
    OGRH.StyleButton(acceptBtn)
  end
  acceptBtn:SetScript("OnClick", function()
    OGRH.Sync.RespondToSyncRequest(true)
  end)
  acceptBtn:Hide()
  frame.acceptBtn = acceptBtn
  
  -- Decline button (for receivers)
  local declineBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  declineBtn:SetWidth(70)
  declineBtn:SetHeight(24)
  declineBtn:SetPoint("BOTTOM", frame, "BOTTOM", 38, 10)
  declineBtn:SetText("Decline")
  if OGRH.StyleButton then
    OGRH.StyleButton(declineBtn)
  end
  declineBtn:SetScript("OnClick", function()
    OGRH.Sync.RespondToSyncRequest(false)
  end)
  declineBtn:Hide()
  frame.declineBtn = declineBtn
  
  -- Cancel button (for sender)
  local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(24)
  cancelBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
  cancelBtn:SetText("Cancel")
  if OGRH.StyleButton then
    OGRH.StyleButton(cancelBtn)
  end
  cancelBtn:SetScript("OnClick", function()
    OGRH.Sync.CancelSyncRequest()
  end)
  cancelBtn:Hide()
  frame.cancelBtn = cancelBtn
  
  OGRH_SyncPanelFrame = frame
  
  -- Hide progress bar from previous sync
  if frame.progressBar then
    frame.progressBar:Hide()
  end
  
  OGRH.Sync.UpdateSyncPanel(isSender)
  frame:Show()
end

-- Update sync panel content
function OGRH.Sync.UpdateSyncPanel(isSender)
  if not OGRH_SyncPanelFrame then return end
  
  local frame = OGRH_SyncPanelFrame
  
  if isSender then
    -- Sender view
    frame:SetHeight(110) -- Taller for timer text
    frame.statusText:SetText("Waiting for responses...")
    frame.acceptBtn:Hide()
    frame.declineBtn:Hide()
    frame.cancelBtn:Show()
    
    -- Show timer
    if not frame.timerText then
      frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      frame.timerText:SetPoint("TOP", frame.statusText, "BOTTOM", 0, -5)
    end
    frame.timerText:Show()
    
  else
    -- Receiver view
    frame:SetHeight(90) -- Standard height for buttons
    local senderName = OGRH.Sync.syncRequestSender or "Unknown"
    
    -- Get class color for sender
    local coloredName = senderName
    local playerClass = OGRH.GetPlayerClass(senderName)
    if playerClass then
      coloredName = OGRH.ClassColorHex(playerClass) .. senderName .. "|r"
    end
    
    frame.statusText:SetText("Accept data sync from " .. coloredName .. "?")
    frame.acceptBtn:Show()
    frame.declineBtn:Show()
    frame.cancelBtn:Hide()
    
    if frame.timerText then
      frame.timerText:Hide()
    end
  end
  
  -- Reposition after size change
  if frame.PositionFrame then
    frame:PositionFrame()
  end
end

-- Show transmission progress
function OGRH.Sync.ShowTransmissionProgress(isSender, progress, complete)
  if not OGRH_SyncPanelFrame then
    OGRH.Sync.ShowSyncPanel(isSender)
  end
  
  local frame = OGRH_SyncPanelFrame
  
  -- Hide accept/decline/cancel buttons
  if frame.acceptBtn then frame.acceptBtn:Hide() end
  if frame.declineBtn then frame.declineBtn:Hide() end
  if frame.cancelBtn then frame.cancelBtn:Hide() end
  if frame.timerText then frame.timerText:Hide() end
  
  -- Create or update progress bar
  if not frame.progressBar then
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetWidth(160)
    bar:SetHeight(16)
    bar:SetPoint("TOP", frame.statusText, "BOTTOM", 0, -10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.8, 0.2)
    bar:SetMinMaxValues(0, 100)
    
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", bar, "CENTER")
    bar.text = text
    
    frame.progressBar = bar
  end
  
  local bar = frame.progressBar
  bar:SetValue(progress)
  bar.text:SetText(string.format("%d%%", progress))
  
  if complete then
    frame.statusText:SetText(isSender and "Sync Complete!" or "Data Received!")
    bar:SetStatusBarColor(0.2, 1, 0.2)
  else
    frame.statusText:SetText(isSender and "Sending data..." or "Receiving data...")
    bar:SetStatusBarColor(0.2, 0.8, 0.2)
  end
  
  bar:Show()
  frame:SetHeight(100)
  
  if frame.PositionFrame then
    frame:PositionFrame()
  end
end

-- Hide sync panel
function OGRH.Sync.HideSyncPanel()
  if OGRH_SyncPanelFrame then
    -- Hide progress bar if it exists
    if OGRH_SyncPanelFrame.progressBar then
      OGRH_SyncPanelFrame.progressBar:Hide()
    end
    OGRH_SyncPanelFrame:Hide()
  end
end

-------------------------------------------------------------------------------
-- Push Structure Workflow
-------------------------------------------------------------------------------

-- Initiate push structure (sender)
function OGRH.Sync.InitiatePushStructure()
  -- Check if sync already in progress
  if OGRH.Sync.syncInProgress or OGRH.Sync.syncTransmitting then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r A sync is already in progress.")
    return
  end
  
  -- Must be in raid
  if GetNumRaidMembers() == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r You must be in a raid to push structure.")
    return
  end
  
  -- Must be raid leader or assistant
  local playerName = UnitName("player")
  local hasPermission = false
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == playerName and (rank == 2 or rank == 1) then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Only raid leaders or assistants can push structure.")
    return
  end
  
  -- Initialize sync state
  OGRH.Sync.syncInProgress = true
  OGRH.Sync.syncResponses = {}
  OGRH.Sync.syncStartTime = GetTime()
  OGRH.Sync.syncTimeout = 30
  
  -- Get current checksum
  local checksum = OGRH.Sync.GetCurrentChecksum()
  
  -- Broadcast sync request
  local message = "SYNC_REQUEST:" .. checksum
  SendAddonMessage(OGRH.Sync.ADDON_PREFIX, message, "RAID")
  
  -- Show sender panel
  OGRH.Sync.ShowSyncPanel(true)
  
  -- Start timer update
  OGRH.Sync.UpdateSyncTimer()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Requesting structure sync from raid members...")
end

-- Update sync timer for sender
function OGRH.Sync.UpdateSyncTimer()
  if not OGRH.Sync.syncInProgress or not OGRH_SyncPanelFrame then
    return
  end
  
  local elapsed = GetTime() - OGRH.Sync.syncStartTime
  local remaining = math.max(0, OGRH.Sync.syncTimeout - elapsed)
  
  if OGRH_SyncPanelFrame.timerText then
    OGRH_SyncPanelFrame.timerText:SetText(string.format("Time remaining: %d seconds", remaining))
  end
  
  -- Check if timeout reached
  if remaining <= 0 then
    OGRH.Sync.CompleteSyncRequest()
    return
  end
  
  -- Check if all responses received
  if OGRH.Sync.AllResponsesReceived() then
    OGRH.Sync.CompleteSyncRequest()
    return
  end
  
  -- Schedule next update
  OGRH.ScheduleFunc(OGRH.Sync.UpdateSyncTimer, 1)
end

-- Check if all expected responses received
function OGRH.Sync.AllResponsesReceived()
  if not OGRH.Sync.pushPollResponses then
    return false
  end
  
  local expected = table.getn(OGRH.Sync.pushPollResponses) - 1 -- Exclude self
  local received = 0
  
  for name, response in pairs(OGRH.Sync.syncResponses) do
    received = received + 1
  end
  
  return received >= expected
end

-- Complete sync request (timeout or all responses received)
function OGRH.Sync.CompleteSyncRequest()
  OGRH.Sync.syncInProgress = false
  
  -- Build list of acceptors
  local acceptors = {}
  for name, response in pairs(OGRH.Sync.syncResponses) do
    if response == true then
      table.insert(acceptors, name)
    end
  end
  
  if table.getn(acceptors) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[RaidHelper]|r No players accepted the sync.")
    OGRH.Sync.HideSyncPanel()
    return
  end
  
  -- Start transmission
  OGRH.Sync.StartTransmission(acceptors)
end

-- Start data transmission to acceptors
function OGRH.Sync.StartTransmission(acceptors)
  OGRH.Sync.syncTransmitting = true
  
  -- Build structure data payload
  local structureData = {
    encounterMgmt = OGRH_SV.encounterMgmt,
    encounterRaidMarks = OGRH_SV.encounterRaidMarks,
    encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers,
    encounterAnnouncements = OGRH_SV.encounterAnnouncements,
    tradeItems = OGRH_SV.tradeItems,
    consumes = OGRH_SV.consumes,
    checksum = OGRH.Sync.GetCurrentChecksum()
  }
  
  -- Encode the data
  local encoded = OGRH.Sync.EncodeData(structureData)
  if not encoded then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Failed to encode structure data.")
    OGRH.Sync.syncTransmitting = false
    OGRH.Sync.HideSyncPanel()
    return
  end
  
  local dataSize = string.len(encoded)
  
  -- Split into chunks
  local chunks = {}
  local pos = 1
  while pos <= dataSize do
    local chunk = string.sub(encoded, pos, pos + OGRH.Sync.MAX_CHUNK_SIZE - 1)
    table.insert(chunks, chunk)
    pos = pos + OGRH.Sync.MAX_CHUNK_SIZE
  end
  
  local totalChunks = table.getn(chunks)
  local chunkId = OGRH.Sync.GenerateChunkId()
  
  -- Store transmission state
  OGRH.Sync.transmissionState = {
    acceptors = acceptors,
    chunks = chunks,
    totalChunks = totalChunks,
    currentChunk = 0,
    chunkId = chunkId
  }
  
  -- Update panel to show progress
  OGRH.Sync.ShowTransmissionProgress(true, 0)
  
  -- Broadcast start message
  local startData = {
    id = chunkId,
    type = OGRH.Sync.MessageType.ENCOUNTER_STRUCTURE,
    total = totalChunks,
    size = dataSize
  }
  SendAddonMessage(OGRH.Sync.ADDON_PREFIX, "SYNC_DATA_START:" .. OGRH.Sync.Serialize(startData), "RAID")
  
  -- Start sending chunks
  OGRH.Sync.SendNextChunk()
end

-- Send next chunk in transmission
function OGRH.Sync.SendNextChunk()
  if not OGRH.Sync.syncTransmitting or not OGRH.Sync.transmissionState then
    return
  end
  
  local state = OGRH.Sync.transmissionState
  state.currentChunk = state.currentChunk + 1
  
  if state.currentChunk > state.totalChunks then
    -- Transmission complete
    OGRH.Sync.CompleteTransmission()
    return
  end
  
  -- Send current chunk
  local chunkData = {
    id = state.chunkId,
    index = state.currentChunk,
    data = state.chunks[state.currentChunk]
  }
  SendAddonMessage(OGRH.Sync.ADDON_PREFIX, "SYNC_DATA_CHUNK:" .. OGRH.Sync.Serialize(chunkData), "RAID")
  
  -- Update progress
  local progress = (state.currentChunk / state.totalChunks) * 100
  OGRH.Sync.ShowTransmissionProgress(true, progress)
  
  -- Schedule next chunk (throttle to avoid flooding)
  OGRH.ScheduleFunc(OGRH.Sync.SendNextChunk, 0.1)
end

-- Complete transmission
function OGRH.Sync.CompleteTransmission()
  if not OGRH.Sync.transmissionState then
    return
  end
  
  -- Send end message
  local endData = {
    id = OGRH.Sync.transmissionState.chunkId,
    total = OGRH.Sync.transmissionState.totalChunks
  }
  SendAddonMessage(OGRH.Sync.ADDON_PREFIX, "SYNC_DATA_END:" .. OGRH.Sync.Serialize(endData), "RAID")
  
  -- Show completion
  OGRH.Sync.ShowTransmissionProgress(true, 100, true)
  
  -- Refresh push structure list if Data Management window is open
  if OGRH_DataManagementFrame and OGRH_DataManagementFrame:IsVisible() and 
     OGRH_DataManagementFrame.selectedActionName == "Push Structure" then
    OGRH.Sync.StartPushStructurePoll()
  end
  
  -- Clean up
  OGRH.Sync.syncTransmitting = false
  OGRH.Sync.transmissionState = nil
  
  -- Auto-close after 10 seconds
  OGRH.ScheduleFunc(function()
    OGRH.Sync.HideSyncPanel()
  end, 10)
end

-- Cancel sync request (sender cancels)
function OGRH.Sync.CancelSyncRequest()
  if not OGRH.Sync.syncInProgress then
    return
  end
  
  OGRH.Sync.syncInProgress = false
  
  -- Broadcast cancellation
  SendAddonMessage(OGRH.Sync.ADDON_PREFIX, "SYNC_CANCEL", "RAID")
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Structure sync cancelled.")
  
  OGRH.Sync.HideSyncPanel()
end

-- Handle incoming sync request (receiver)
function OGRH.Sync.HandleSyncRequest(sender, checksum)
  -- Ignore if we're the sender
  if sender == UnitName("player") then
    return
  end
  
  -- Check if our checksum matches
  local myChecksum = OGRH.Sync.GetCurrentChecksum()
  
  if myChecksum == checksum then
    -- Already have same data, auto-accept
    local message = "SYNC_RESPONSE:accept:" .. sender
    SendAddonMessage(OGRH.Sync.ADDON_PREFIX, message, "RAID")
    return
  end
  
  -- Show panel to accept/decline
  OGRH.Sync.syncRequestSender = sender
  OGRH.Sync.syncRequestTime = GetTime()
  OGRH.Sync.ShowSyncPanel(false)
end

-- Respond to sync request (receiver)
function OGRH.Sync.RespondToSyncRequest(accept)
  if not OGRH.Sync.syncRequestSender then
    return
  end
  
  local response = accept and "accept" or "decline"
  local message = "SYNC_RESPONSE:" .. response .. ":" .. OGRH.Sync.syncRequestSender
  SendAddonMessage(OGRH.Sync.ADDON_PREFIX, message, "RAID")
  
  if accept then
    -- Prepare to receive data
    OGRH.Sync.syncReceiving = true
    OGRH.Sync.receivingFrom = OGRH.Sync.syncRequestSender
    OGRH.Sync.syncRequestSender = nil
    
    -- Show waiting panel
    OGRH.Sync.ShowTransmissionProgress(false, 0)
    
    -- Set timeout for receiving (60 seconds from accept)
    OGRH.Sync.receiveTimeout = GetTime() + 60
    OGRH.Sync.CheckReceiveTimeout()
  else
    OGRH.Sync.syncRequestSender = nil
    OGRH.Sync.HideSyncPanel()
  end
end

-- Handle sync response (sender receives)
function OGRH.Sync.HandleSyncResponse(sender, response)
  if not OGRH.Sync.syncInProgress then
    return
  end
  
  local accepted = response == "accept"
  OGRH.Sync.syncResponses[sender] = accepted
  
  -- Update status
  if OGRH_SyncPanelFrame and OGRH_SyncPanelFrame.statusText then
    local count = 0
    for _ in pairs(OGRH.Sync.syncResponses) do
      count = count + 1
    end
    OGRH_SyncPanelFrame.statusText:SetText(string.format("Responses: %d", count))
  end
end

-- Check receive timeout
function OGRH.Sync.CheckReceiveTimeout()
  if not OGRH.Sync.syncReceiving then
    return
  end
  
  if GetTime() > OGRH.Sync.receiveTimeout then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Sync receive timeout. No data received.")
    OGRH.Sync.syncReceiving = false
    OGRH.Sync.receivingFrom = nil
    OGRH.Sync.receivingData = nil
    OGRH.Sync.HideSyncPanel()
    return
  end
  
  OGRH.ScheduleFunc(OGRH.Sync.CheckReceiveTimeout, 1)
end

-- Handle sync data start (receiver)
function OGRH.Sync.HandleSyncDataStart(sender, data)
  if not OGRH.Sync.syncReceiving or OGRH.Sync.receivingFrom ~= sender then
    return
  end
  
  local startInfo = OGRH.Sync.Deserialize(data)
  if not startInfo then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Failed to parse sync data start.")
    OGRH.Sync.syncReceiving = false
    OGRH.Sync.HideSyncPanel()
    return
  end
  
  -- Initialize receiving state
  OGRH.Sync.receivingData = {
    id = startInfo.id,
    total = startInfo.total,
    size = startInfo.size,
    chunks = {},
    received = 0
  }
  
  OGRH.Sync.ShowTransmissionProgress(false, 0)
end

-- Handle sync data chunk (receiver)
function OGRH.Sync.HandleSyncDataChunk(sender, data)
  if not OGRH.Sync.syncReceiving or OGRH.Sync.receivingFrom ~= sender or not OGRH.Sync.receivingData then
    return
  end
  
  local chunkInfo = OGRH.Sync.Deserialize(data)
  if not chunkInfo or chunkInfo.id ~= OGRH.Sync.receivingData.id then
    return
  end
  
  -- Store chunk
  OGRH.Sync.receivingData.chunks[chunkInfo.index] = chunkInfo.data
  OGRH.Sync.receivingData.received = OGRH.Sync.receivingData.received + 1
  
  -- Update progress
  local progress = (OGRH.Sync.receivingData.received / OGRH.Sync.receivingData.total) * 100
  OGRH.Sync.ShowTransmissionProgress(false, progress)
end

-- Handle sync data end (receiver)
function OGRH.Sync.HandleSyncDataEnd(sender, data)
  if not OGRH.Sync.syncReceiving or OGRH.Sync.receivingFrom ~= sender or not OGRH.Sync.receivingData then
    return
  end
  
  local endInfo = OGRH.Sync.Deserialize(data)
  if not endInfo or endInfo.id ~= OGRH.Sync.receivingData.id then
    return
  end
  
  -- Verify all chunks received
  if OGRH.Sync.receivingData.received ~= OGRH.Sync.receivingData.total then
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RaidHelper]|r Sync failed: received %d/%d chunks.", OGRH.Sync.receivingData.received, OGRH.Sync.receivingData.total))
    OGRH.Sync.syncReceiving = false
    OGRH.Sync.receivingData = nil
    OGRH.Sync.HideSyncPanel()
    return
  end
  
  -- Reassemble data
  local fullData = ""
  for i = 1, OGRH.Sync.receivingData.total do
    fullData = fullData .. OGRH.Sync.receivingData.chunks[i]
  end
  
  -- Decode and apply
  local structureData = OGRH.Sync.DecodeData(fullData)
  if not structureData then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RaidHelper]|r Failed to decode structure data.")
    OGRH.Sync.syncReceiving = false
    OGRH.Sync.receivingData = nil
    OGRH.Sync.HideSyncPanel()
    return
  end
  
  -- Apply structure data
  if structureData.encounterMgmt then
    OGRH_SV.encounterMgmt = structureData.encounterMgmt
  end
  if structureData.encounterRaidMarks then
    OGRH_SV.encounterRaidMarks = structureData.encounterRaidMarks
  end
  if structureData.encounterAssignmentNumbers then
    OGRH_SV.encounterAssignmentNumbers = structureData.encounterAssignmentNumbers
  end
  if structureData.encounterAnnouncements then
    OGRH_SV.encounterAnnouncements = structureData.encounterAnnouncements
  end
  if structureData.tradeItems then
    OGRH_SV.tradeItems = structureData.tradeItems
  end
  if structureData.consumes then
    OGRH_SV.consumes = structureData.consumes
  end
  
  -- Verify checksum
  local newChecksum = OGRH.Sync.GetCurrentChecksum()
  if structureData.checksum and newChecksum ~= structureData.checksum then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[RaidHelper]|r Warning: Checksum mismatch after sync.")
  end
  
  -- Refresh open windows
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshAll then
    OGRH_EncounterSetupFrame.RefreshAll()
  end
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
    OGRH_EncounterFrame.RefreshRaidsList()
  end
  
  -- Show success
  OGRH.Sync.ShowTransmissionProgress(false, 100, true)
  
  -- Refresh push structure list if Data Management window is open
  if OGRH_DataManagementFrame and OGRH_DataManagementFrame:IsVisible() and 
     OGRH_DataManagementFrame.selectedActionName == "Push Structure" then
    OGRH.Sync.StartPushStructurePoll()
  end
  
  -- Clean up
  OGRH.Sync.syncReceiving = false
  OGRH.Sync.receivingFrom = nil
  OGRH.Sync.receivingData = nil
  
  -- Auto-close after 10 seconds
  OGRH.ScheduleFunc(function()
    OGRH.Sync.HideSyncPanel()
  end, 10)
end

-- Handle sync cancel (receiver)
function OGRH.Sync.HandleSyncCancel(sender)
  if OGRH.Sync.syncRequestSender == sender then
    OGRH.Sync.syncRequestSender = nil
    OGRH.Sync.HideSyncPanel()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Structure sync cancelled by sender.")
  end
end

-- Module initialization message (optional, can be removed for production)
-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Sync module loaded")
