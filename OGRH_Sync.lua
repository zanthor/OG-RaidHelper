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
function OGRH.Sync.ShowDataManagementWindow()
  -- Create window if it doesn't exist
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
    
    -- Register ESC key handler
    if OGRH.MakeFrameCloseOnEscape then
      OGRH.MakeFrameCloseOnEscape(frame, "OGRH_DataManagementFrame")
    end
    
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
    local outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGRH.CreateStyledScrollList(frame, listWidth, listHeight)
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
  if frame.detailText then frame.detailText:Show() end
  
  -- If Load Defaults is selected, show special UI
  if selectedAction == "Load Defaults" then
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
      name = "Push Structure",
      description = "Broadcast the current encounter structure to all raid members.\n\nThis will send:\n- Roles and assignments\n- Raid marks\n- Assignment numbers\n- Announcement templates\n\nAll raid members will receive and apply this data.",
      action = function()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Push Structure - Coming Soon!")
      end
    },
    {
      name = "Load Defaults",
      description = "Load factory default data from OGRH_Defaults.lua.\n\nThis will replace all current data with:\n- Default encounter structures\n- Default role configurations\n- Default announcements\n- Default trade settings\n- Default consumes\n\nWarning: This will overwrite your current configuration!",
      action = function()
        if OGRH.Sync.LoadDefaults then
          OGRH.Sync.LoadDefaults()
        end
      end
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
  
  -- Update scrollbar
  if OGRH_DataManagementFrame.scrollBar and OGRH_DataManagementFrame.scrollFrame then
    local scrollBar = OGRH_DataManagementFrame.scrollBar
    local scrollFrame = OGRH_DataManagementFrame.scrollFrame
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll > 0 then
      scrollBar:SetMinMaxValues(0, maxScroll)
      scrollBar:Show()
    else
      scrollBar:Hide()
    end
  end
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

-- Module initialization message (optional, can be removed for production)
-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Sync module loaded")
