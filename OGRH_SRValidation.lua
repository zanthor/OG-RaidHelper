-- OGRH_SRValidation.lua
-- SR+ Validation Interface - Track and validate SR+ changes over time

-- Namespace
OGRH = OGRH or {}
OGRH.SRValidation = {}

-- Local references
local selectedPlayer = nil

-- Initialize saved variables
function OGRH.SRValidation.EnsureSV()
  OGRH_SV = OGRH_SV or {}
  OGRH_SV.srValidation = OGRH_SV.srValidation or {}
  OGRH_SV.srValidation.records = OGRH_SV.srValidation.records or {}
  -- Structure: records[playerName] = { {date, time, validator, instance, srData}, ... }
end

-- Debug command to check SR+ for a specific player/item
function OGRH.SRValidation.DebugSRPlus(playerName, itemId)
  if not RollForCharDb or not RollForCharDb.softres or not RollForCharDb.softres.data then
    OGRH.Msg("No RollFor data available")
    return
  end
  
  local encodedData = RollForCharDb.softres.data
  OGRH.Msg("Encoded data length: " .. string.len(encodedData))
  
  local decodedData = RollFor.SoftRes.decode(encodedData)
  if not decodedData then
    OGRH.Msg("Failed to decode RollFor data")
    return
  end
  
  OGRH.Msg("Decoded data successfully")
  
  -- Debug: Show structure of decoded data
  if decodedData.softreserves and type(decodedData.softreserves) == "table" then
    OGRH.Msg("Found softreserves table")
    
    -- Find the specific player
    for idx, srEntry in ipairs(decodedData.softreserves) do
      if srEntry.name == playerName then
        OGRH.Msg("Found player: " .. playerName .. " at index " .. idx)
        if srEntry.items and type(srEntry.items) == "table" then
          OGRH.Msg("  Items table exists (is array: " .. tostring(table.getn(srEntry.items) > 0) .. ")")
          for itemIdx, itemEntry in ipairs(srEntry.items) do
            if type(itemEntry) == "table" then
              OGRH.Msg("    Item [" .. itemIdx .. "]:")
              for k, v in pairs(itemEntry) do
                OGRH.Msg("      " .. tostring(k) .. " = " .. tostring(v) .. " (type: " .. type(v) .. ")")
              end
            else
              OGRH.Msg("    Item [" .. itemIdx .. "] = " .. tostring(itemEntry))
            end
          end
        else
          OGRH.Msg("  No items table or not a table")
        end
        break
      end
    end
  else
    OGRH.Msg("No softreserves key found or not a table")
  end
  
  local softresData = RollFor.SoftResDataTransformer.transform(decodedData)
  if not softresData then
    OGRH.Msg("Failed to transform RollFor data")
    return
  end
  
  OGRH.Msg("Transformed data successfully")
  
  -- Search for the player/item combination
  local found = false
  for sItemId, itemData in pairs(softresData) do
    if (not itemId or tonumber(sItemId) == tonumber(itemId)) and type(itemData) == "table" and itemData.rollers then
      for _, roller in ipairs(itemData.rollers) do
        if roller and roller.name == playerName then
          local itemName = GetItemInfo(sItemId) or "Item " .. sItemId
          OGRH.Msg("Found: " .. playerName .. " - " .. itemName .. " (" .. sItemId .. ") - SR+: " .. (roller.sr_plus or 0))
          found = true
          if itemId then break end
        end
      end
    end
    if found and itemId then break end
  end
  
  if not found then
    if itemId then
      OGRH.Msg("No SR data found for " .. playerName .. " and item " .. itemId)
    else
      OGRH.Msg("No SR data found for " .. playerName)
    end
  end
  
  -- Also check RollFor.Db if it exists
  if RollFor and RollFor.Db and RollFor.Db.softres then
    OGRH.Msg("RollFor.Db.softres exists")
  else
    OGRH.Msg("RollFor.Db.softres does NOT exist")
  end
end

SlashCmdList["OGRHSRDEBUG"] = function(msg)
  local args = {}
  for word in string.gfind(msg, "%S+") do
    table.insert(args, word)
  end
  
  if table.getn(args) < 1 then
    OGRH.Msg("Usage: /ogrhsr <playerName> [itemId]")
    return
  end
  
  local playerName = args[1]
  local itemId = args[2] and tonumber(args[2]) or nil
  
  OGRH.SRValidation.DebugSRPlus(playerName, itemId)
end
SLASH_OGRHSRDEBUG1 = "/ogrhsr"

-- Get SR+ data from RollFor using existing Invites function
function OGRH.SRValidation.GetSRPlusData()
  if not OGRH.Invites or not OGRH.Invites.GetSoftResPlayers then
    return nil
  end
  
  local players = OGRH.Invites.GetSoftResPlayers()
  if not players or table.getn(players) == 0 then
    return nil
  end
  
  -- Update player classes using existing function
  for _, playerData in ipairs(players) do
    OGRH.Invites.UpdatePlayerClass(playerData)
  end
  
  return players, OGRH.Invites.GetMetadata()
end

-- Get SR+ value for a player
function OGRH.SRValidation.GetPlayerSRPlus(playerData)
  if not playerData then
    return 0
  end
  
  return playerData.srPlus or 0
end

-- Get items for a specific player from RollFor data
function OGRH.SRValidation.GetPlayerItems(playerName)
  if not RollFor or not RollForCharDb or not RollForCharDb.softres then
    return {}
  end
  
  local encodedData = RollForCharDb.softres.data
  if not encodedData or encodedData == "" then
    return {}
  end
  
  local decodedData = RollFor.SoftRes.decode(encodedData)
  if not decodedData then
    return {}
  end
  
  local softresData = RollFor.SoftResDataTransformer.transform(decodedData)
  if not softresData then
    return {}
  end
  
  local items = {}
  for itemId, itemData in pairs(softresData) do
    if type(itemData) == "table" and itemData.rollers then
      for _, roller in ipairs(itemData.rollers) do
        if roller and roller.name == playerName then
          -- Get item name from WoW API using itemId
          local itemName = GetItemInfo(itemId) or "Item " .. tostring(itemId)
          table.insert(items, {
            name = itemName,
            plus = roller.sr_plus or 0,
            itemId = itemId
          })
        end
      end
    end
  end
  
  return items
end

-- Edit an item's SR+ value
function OGRH.SRValidation.EditItemPlus(playerName, itemId, currentPlus)
  if not RollForCharDb or not RollForCharDb.softres or not RollForCharDb.softres.data then
    OGRH.Msg("No RollFor data available")
    return
  end
  
  -- Get expected value from last validation record (last validated + 10)
  local expectedPlus = 10
  OGRH.SRValidation.EnsureSV()
  local records = OGRH_SV.srValidation.records[playerName]
  if records and table.getn(records) > 0 then
    local lastRecord = records[table.getn(records)]
    if lastRecord.items then
      for _, item in ipairs(lastRecord.items) do
        if tonumber(item.itemId) == tonumber(itemId) then
          expectedPlus = (item.plus or 0) + 10
          break
        end
      end
    end
  end
  
  -- Create custom edit dialog
  local editFrame = CreateFrame("Frame", "OGRH_EditSRPlusFrame", UIParent)
  editFrame:SetWidth(350)
  editFrame:SetHeight(200)
  editFrame:SetPoint("CENTER", 0, 0)
  editFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  editFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  editFrame:SetBackdropColor(0, 0, 0, 0.9)
  editFrame:EnableMouse(true)
  editFrame:SetMovable(true)
  editFrame:RegisterForDrag("LeftButton")
  editFrame:SetScript("OnDragStart", function() this:StartMoving() end)
  editFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  
  -- Title
  local title = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Edit SR+ Value")
  
  -- Player name
  local playerText = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  playerText:SetPoint("TOP", 0, -40)
  playerText:SetText("Player: " .. playerName)
  
  -- Item ID
  local itemText = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemText:SetPoint("TOP", 0, -60)
  itemText:SetText("Item: " .. itemId)
  
  -- Current value
  local currentText = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  currentText:SetPoint("TOP", 0, -80)
  currentText:SetText("Current SR+: |cffff0000" .. currentPlus .. "|r")
  
  -- Expected value
  local expectedText = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  expectedText:SetPoint("TOP", 0, -100)
  expectedText:SetText("Expected Value: |cff00ff00" .. expectedPlus .. "|r")
  
  -- Edit box label
  local editLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  editLabel:SetPoint("TOP", 0, -120)
  editLabel:SetText("New SR+ Value:")
  
  -- Edit box
  local editBox = CreateFrame("EditBox", nil, editFrame)
  editBox:SetWidth(80)
  editBox:SetHeight(25)
  editBox:SetPoint("TOP", 0, -145)
  editBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  editBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
  editBox:SetFontObject(GameFontHighlight)
  editBox:SetMaxLetters(3)
  editBox:SetNumeric(true)
  editBox:SetAutoFocus(false)
  editBox:SetJustifyH("CENTER")
  editBox:SetText(tostring(expectedPlus))
  editBox:SetScript("OnEscapePressed", function() editFrame:Hide() end)
  editBox:SetScript("OnEnterPressed", function()
    local newValue = tonumber(editBox:GetText())
    if not newValue or newValue < 0 then
      OGRH.Msg("Invalid SR+ value")
      return
    end
    
    -- Get the encoded data
    if not RollForCharDb or not RollForCharDb.softres or not RollForCharDb.softres.data then
      OGRH.Msg("RollFor data not available")
      editFrame:Hide()
      return
    end
    
    local encodedData = RollForCharDb.softres.data
    local decodedData = RollFor.SoftRes.decode(encodedData)
    if not decodedData or type(decodedData) ~= "table" then
      OGRH.Msg("Failed to decode RollFor data")
      editFrame:Hide()
      return
    end
    
    -- Update the raw decoded data directly
    -- Decoded data format: {softreserves = {{name="Player", items={{id=itemId, sr_plus=50, quality=4}, ...}}, ...}}
    local found = false
    local oldValue = 0
    
    if decodedData.softreserves and type(decodedData.softreserves) == "table" then
      for _, srEntry in ipairs(decodedData.softreserves) do
        if srEntry.name == playerName and srEntry.items and type(srEntry.items) == "table" then
          for _, itemEntry in ipairs(srEntry.items) do
            if type(itemEntry) == "table" and tonumber(itemEntry.id) == tonumber(itemId) then
              oldValue = itemEntry.sr_plus or 0
              itemEntry.sr_plus = newValue
              found = true
              break
            end
          end
        end
        if found then break end
      end
    end
    
    if found then
      -- Re-encode the data using RollFor's encode function if it exists
      local newEncodedData = encodedData
      if RollFor.SoftRes.encode and type(RollFor.SoftRes.encode) == "function" then
        newEncodedData = RollFor.SoftRes.encode(decodedData)
        RollForCharDb.softres.data = newEncodedData
        OGRH.Msg("Updated " .. playerName .. "'s SR+ from " .. oldValue .. " to " .. newValue .. " for item " .. itemId .. " (encoded)")
      else
        OGRH.Msg("Updated " .. playerName .. "'s SR+ from " .. oldValue .. " to " .. newValue .. " for item " .. itemId .. " (no encode)")
      end
      
      -- Clear RollFor's cache so it reloads the data
      if RollFor and RollFor.Db then
        RollFor.Db.softres = nil
      end
      
      -- Verify the change
      OGRH.SRValidation.DebugSRPlus(playerName, itemId)
      
      -- Refresh display
      if OGRH.SRValidation.RefreshPlayerList then
        OGRH.SRValidation.RefreshPlayerList()
      end
    else
      OGRH.Msg("Could not find item in decoded data")
    end
    
    editFrame:Hide()
  end)
  
  -- Save button
  local saveBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
  saveBtn:SetWidth(80)
  saveBtn:SetHeight(22)
  saveBtn:SetPoint("BOTTOM", -45, 10)
  saveBtn:SetText("Save")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(saveBtn)
  end
  saveBtn:SetScript("OnClick", function()
    editBox:GetScript("OnEnterPressed")()
  end)
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(22)
  cancelBtn:SetPoint("BOTTOM", 45, 10)
  cancelBtn:SetText("Cancel")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(cancelBtn)
  end
  cancelBtn:SetScript("OnClick", function()
    editFrame:Hide()
  end)
  
  editFrame:Show()
  editBox:SetFocus()
end

-- Validate player's SR+ (check if it increased by more than 10 from last validation)
function OGRH.SRValidation.ValidatePlayer(playerName, currentSRPlus)
  OGRH.SRValidation.EnsureSV()
  
  local records = OGRH_SV.srValidation.records[playerName]
  if not records or table.getn(records) == 0 then
    -- No previous records, validation passes
    return true, "No previous data", {}
  end
  
  -- Get most recent validation
  local lastRecord = records[table.getn(records)]
  local lastSRPlus = lastRecord.srPlus or 0
  local increase = currentSRPlus - lastSRPlus
  
  -- Build a map of items that increased
  local itemIncreases = {}
  if lastRecord.items then
    local currentItems = OGRH.SRValidation.GetPlayerItems(playerName)
    
    for _, currentItem in ipairs(currentItems) do
      local foundInLast = false
      local oldPlus = 0
      
      for _, lastItem in ipairs(lastRecord.items) do
        if lastItem.itemId == currentItem.itemId then
          foundInLast = true
          oldPlus = lastItem.plus or 0
          break
        end
      end
      
      if foundInLast and currentItem.plus > oldPlus then
        itemIncreases[currentItem.itemId] = currentItem.plus - oldPlus
      elseif not foundInLast and currentItem.plus > 0 then
        itemIncreases[currentItem.itemId] = currentItem.plus
      end
    end
  end
  
  if increase > 10 then
    return false, "SR+ increased by " .. increase .. " (>" .. lastSRPlus .. ")", itemIncreases
  end
  
  return true, "SR+ within acceptable range", itemIncreases
end

-- Save validation record
function OGRH.SRValidation.SaveValidation(playerName, currentSRPlus, instance)
  OGRH.SRValidation.EnsureSV()
  
  -- Get current items for the player
  local items = OGRH.SRValidation.GetPlayerItems(playerName)
  
  local playerName_normalized = UnitName("player")
  local dateStr = date("%Y-%m-%d")
  local timeStr = date("%H:%M:%S")
  
  OGRH_SV.srValidation.records[playerName] = OGRH_SV.srValidation.records[playerName] or {}
  
  -- Build item data for the record
  local itemData = {}
  for _, item in ipairs(items) do
    table.insert(itemData, {
      itemId = item.itemId,
      name = item.name,
      plus = item.plus
    })
  end
  
  -- Check if this exact data already exists in the last record
  local records = OGRH_SV.srValidation.records[playerName]
  if table.getn(records) > 0 then
    local lastRecord = records[table.getn(records)]
    
    -- Compare SR+ totals
    if lastRecord.srPlus == currentSRPlus and lastRecord.items then
      -- Check if items match
      local itemsMatch = true
      
      if table.getn(lastRecord.items) ~= table.getn(itemData) then
        itemsMatch = false
      else
        -- Compare each item
        for i, newItem in ipairs(itemData) do
          local oldItem = lastRecord.items[i]
          if not oldItem or oldItem.itemId ~= newItem.itemId or oldItem.plus ~= newItem.plus then
            itemsMatch = false
            break
          end
        end
      end
      
      if itemsMatch then
        OGRH.Msg("Validation for " .. playerName .. " already saved (no changes)")
        return false
      end
    end
  end
  
  local record = {
    date = dateStr,
    time = timeStr,
    validator = playerName_normalized,
    instance = instance,
    srPlus = currentSRPlus,
    items = itemData
  }
  
  table.insert(OGRH_SV.srValidation.records[playerName], record)
  
  -- If all items are at +0, purge older records but keep this final +0 record
  local allZero = true
  for _, item in ipairs(items) do
    if item.plus > 0 then
      allZero = false
      break
    end
  end
  
  if allZero and currentSRPlus == 0 then
    -- Keep only the latest (just added) record
    local latestRecord = OGRH_SV.srValidation.records[playerName][table.getn(OGRH_SV.srValidation.records[playerName])]
    OGRH_SV.srValidation.records[playerName] = {latestRecord}
    OGRH.Msg("Purged old SR validation records for " .. playerName .. " (all items at +0, keeping current)")
  else
    -- Keep only last 10 records per player
    while table.getn(OGRH_SV.srValidation.records[playerName]) > 10 do
      table.remove(OGRH_SV.srValidation.records[playerName], 1)
    end
  end
  
  return true
end

-- Get last N validation records for a player
function OGRH.SRValidation.GetPlayerRecords(playerName, count)
  OGRH.SRValidation.EnsureSV()
  
  local records = OGRH_SV.srValidation.records[playerName]
  if not records or table.getn(records) == 0 then
    return {}
  end
  
  count = count or 5
  local result = {}
  local startIdx = math.max(1, table.getn(records) - count + 1)
  
  for i = startIdx, table.getn(records) do
    table.insert(result, records[i])
  end
  
  return result
end

-- Validate all players who passed the automatic validation
function OGRH.SRValidation.ValidateAllPassed()
  local players, metadata = OGRH.SRValidation.GetSRPlusData()
  if not players then
    return
  end
  
  local validatedCount = 0
  local playerName = UnitName("player")
  local instance = metadata and metadata.instance or "Unknown"
  
  for _, playerData in ipairs(players) do
    local currentSRPlus = playerData.srPlus or 0
    local isValid = OGRH.SRValidation.ValidatePlayer(playerData.name, currentSRPlus)
    
    -- Only save validation for players who passed
    if isValid then
      local saved = OGRH.SRValidation.SaveValidation(playerData.name, currentSRPlus, instance)
      if saved then
        validatedCount = validatedCount + 1
      end
    end
  end
  
  if validatedCount > 0 then
    DEFAULT_CHAT_FRAME:AddMessage("SR+ Validation: Saved records for " .. validatedCount .. " players", 0, 1, 0)
  else
    DEFAULT_CHAT_FRAME:AddMessage("SR+ Validation: No new records to save", 1, 1, 0)
  end
  
  -- Refresh the display
  OGRH.SRValidation.RefreshPlayerList()
end

-- Refresh the player list display
function OGRH.SRValidation.RefreshPlayerList()
  if not OGRH_SRValidationFrame or not OGRH_SRValidationFrame.scrollFrame then
    return
  end
  
  local players, metadata = OGRH.SRValidation.GetSRPlusData()
  if not players then
    return
  end
  
  local frame = OGRH_SRValidationFrame
  local scrollFrame = frame.scrollFrame
  local scrollChild = scrollFrame.scrollChild
  
  -- Clear existing buttons
  if scrollChild.buttons then
    for _, btn in ipairs(scrollChild.buttons) do
      btn:Hide()
      btn:SetParent(nil)
    end
  end
  scrollChild.buttons = {}
  
  local yOffset = 0
  local buttonHeight = 20
  
  -- Players already sorted by GetSoftResPlayers, validate each one
  local validatedPlayers = {}
  for _, playerData in ipairs(players) do
    local currentSRPlus = OGRH.SRValidation.GetPlayerSRPlus(playerData)
    local isValid, reason = OGRH.SRValidation.ValidatePlayer(playerData.name, currentSRPlus)
    
    table.insert(validatedPlayers, {
      name = playerData.name,
      data = playerData,
      srPlus = currentSRPlus,
      isValid = isValid,
      reason = reason
    })
  end
  
  -- Create buttons for each player
  for _, playerInfo in ipairs(validatedPlayers) do
    local btn = CreateFrame("Button", nil, scrollChild)
    btn:SetWidth(175)
    btn:SetHeight(buttonHeight)
    btn:SetPoint("TOPLEFT", 5, -yOffset)
    
    -- Background highlight for validation status
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    if playerInfo.isValid then
      bg:SetTexture(0, 0.5, 0, 0.3) -- Green
    else
      bg:SetTexture(0.5, 0, 0, 0.3) -- Red
    end
    btn.bg = bg
    
    -- Player name with class color (using existing class cache)
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 5, 0)
    text:SetJustifyH("LEFT")
    
    if playerInfo.data.class then
      OGRH.Roles.nameClass[playerInfo.name] = playerInfo.data.class
      text:SetText(OGRH.ColorName(playerInfo.name))
    else
      text:SetText(playerInfo.name)
    end
    btn.text = text
    
    -- Click handler
    local playerName = playerInfo.name
    local playerData = playerInfo.data
    local playerSRPlus = playerInfo.srPlus
    btn:SetScript("OnClick", function()
      OGRH.SRValidation.SelectPlayer(playerName, playerData, playerSRPlus)
    end)
    
    -- Hover effect - capture bg and isValid in closure
    local btnBg = bg
    local isValid = playerInfo.isValid
    btn:SetScript("OnEnter", function()
      btnBg:SetTexture(0.2, 0.2, 0.2, 0.5)
    end)
    btn:SetScript("OnLeave", function()
      if isValid then
        btnBg:SetTexture(0, 0.5, 0, 0.3)
      else
        btnBg:SetTexture(0.5, 0, 0, 0.3)
      end
    end)
    
    table.insert(scrollChild.buttons, btn)
    yOffset = yOffset + buttonHeight
  end
  
  -- Update scroll child height
  local contentHeight = yOffset + 5
  scrollChild:SetHeight(contentHeight)
  
  -- Reset scroll position
  scrollFrame:SetVerticalScroll(0)
end

-- Select a player and show their details
function OGRH.SRValidation.SelectPlayer(playerName, playerData, currentSRPlus)
  selectedPlayer = playerName
  
  if not OGRH_SRValidationFrame or not OGRH_SRValidationFrame.detailPanel then
    return
  end
  
  local detailPanel = OGRH_SRValidationFrame.detailPanel
  
  -- Hide initial text
  if detailPanel.initialText then
    detailPanel.initialText:Hide()
  end
  
  -- Clear existing content
  if detailPanel.content then
    for _, obj in ipairs(detailPanel.content) do
      obj:Hide()
      obj:SetParent(nil)
    end
  end
  detailPanel.content = {}
  
  local yOffset = 10
  
  -- Player name header with class color
  local nameText = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  nameText:SetPoint("TOPLEFT", 10, -yOffset)
  
  if playerData.class then
    OGRH.Roles.nameClass[playerName] = playerData.class
    nameText:SetText(OGRH.ColorName(playerName))
  else
    nameText:SetText(playerName)
  end
  table.insert(detailPanel.content, nameText)
  yOffset = yOffset + 25
  
  -- Current SR+ header
  local currentHeader = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  currentHeader:SetPoint("TOPLEFT", 10, -yOffset)
  currentHeader:SetText("Current SR+ Items:")
  table.insert(detailPanel.content, currentHeader)
  yOffset = yOffset + 20
  
  -- Check validation status to identify problem items
  local isValid, validMsg, itemIncreases = OGRH.SRValidation.ValidatePlayer(playerName, currentSRPlus)
  
  -- Get and display items
  local items = OGRH.SRValidation.GetPlayerItems(playerName)
  if table.getn(items) > 0 then
    for _, item in ipairs(items) do
      -- Create a frame to hold item name and plus button
      local itemFrame = CreateFrame("Frame", nil, detailPanel)
      itemFrame:SetWidth(450)
      itemFrame:SetHeight(15)
      itemFrame:SetPoint("TOPLEFT", 20, -yOffset)
      
      -- Item name button (for tooltip)
      local itemBtn = CreateFrame("Button", nil, itemFrame)
      itemBtn:SetHeight(15)
      itemBtn:SetPoint("LEFT", 0, 0)
      
      local itemText = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      itemText:SetPoint("LEFT", 0, 0)
      itemText:SetJustifyH("LEFT")
      
      -- Get item info from WoW API (returns name, link, quality, ...)
      local itemName, itemLink, itemQuality = GetItemInfo(item.itemId)
      
      -- Check if this item has an increase
      local hasIncrease = not isValid and itemIncreases[item.itemId]
      
      -- Format the display text with colored item link
      local displayText
      if itemLink and string.find(itemLink, "|H") then
        displayText = itemLink
      elseif itemName then
        local colorCode = "|cffffffff"
        if itemQuality == 0 then colorCode = "|cff9d9d9d"
        elseif itemQuality == 1 then colorCode = "|cffffffff"
        elseif itemQuality == 2 then colorCode = "|cff1eff00"
        elseif itemQuality == 3 then colorCode = "|cff0070dd"
        elseif itemQuality == 4 then colorCode = "|cffa335ee"
        elseif itemQuality == 5 then colorCode = "|cffff8000"
        end
        displayText = colorCode .. itemName .. "|r"
      else
        displayText = item.name
      end
      
      -- Add red asterisks if this item has an increase
      if hasIncrease then
        displayText = "|cffff0000*** |r" .. displayText .. "|cffff0000 ***|r"
      end
      
      itemText:SetText(displayText)
      itemBtn:SetWidth(itemText:GetStringWidth() + 5)
      
      -- Capture values in closure
      local capturedItemId = item.itemId
      local capturedLink = itemLink
      
      -- Make it clickable to show item tooltip
      itemBtn:SetScript("OnEnter", function()
        if capturedItemId then
          GameTooltip:SetOwner(itemBtn, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink("item:" .. capturedItemId)
          GameTooltip:Show()
        end
      end)
      itemBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      itemBtn:SetScript("OnClick", function()
        if capturedLink and ChatFrameEditBox:IsVisible() then
          ChatFrameEditBox:Insert(capturedLink)
        end
      end)
      
      -- Display SR+ value with expected value if validation error
      local plusText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      plusText:SetPoint("LEFT", itemBtn, "RIGHT", 5, 0)
      
      local displayText = " (+" .. item.plus .. ")"
      
      -- If this item has an increase and validation failed, show expected value
      if hasIncrease then
        -- Get expected value from last validation
        local expectedPlus = 0
        OGRH.SRValidation.EnsureSV()
        local records = OGRH_SV.srValidation.records[playerName]
        if records and table.getn(records) > 0 then
          local lastRecord = records[table.getn(records)]
          if lastRecord.items then
            for _, lastItem in ipairs(lastRecord.items) do
              if tonumber(lastItem.itemId) == tonumber(item.itemId) then
                expectedPlus = (lastItem.plus or 0) + 10
                break
              end
            end
          end
        end
        displayText = displayText .. " |cff00ff00(Expected " .. expectedPlus .. ")|r"
      end
      
      plusText:SetText(displayText)
      
      table.insert(detailPanel.content, itemFrame)
      yOffset = yOffset + 15
    end
  else
    local noItemsText = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noItemsText:SetPoint("TOPLEFT", 20, -yOffset)
    noItemsText:SetText("No items found")
    table.insert(detailPanel.content, noItemsText)
    yOffset = yOffset + 15
  end
  
  yOffset = yOffset + 10
  
  -- Previous validations header
  local historyHeader = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  historyHeader:SetPoint("TOPLEFT", 10, -yOffset)
  historyHeader:SetText("Previous Validations:")
  table.insert(detailPanel.content, historyHeader)
  yOffset = yOffset + 20
  
  -- Get last 5 records
  local records = OGRH.SRValidation.GetPlayerRecords(playerName, 5)
  if table.getn(records) > 0 then
    for i = table.getn(records), 1, -1 do
      local record = records[i]
      
      -- Record header
      local recordHeader = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      recordHeader:SetPoint("TOPLEFT", 20, -yOffset)
      recordHeader:SetWidth(450)
      recordHeader:SetJustifyH("LEFT")
      
      local instanceName = "Unknown"
      if OGRH.Invites and OGRH.Invites.GetInstanceName then
        instanceName = OGRH.Invites.GetInstanceName(record.instance)
      end
      
      recordHeader:SetText(string.format("%s %s - %s - %s (SR+: %d)",
        record.date or "N/A",
        record.time or "N/A",
        instanceName,
        record.validator or "Unknown",
        record.srPlus or 0
      ))
      table.insert(detailPanel.content, recordHeader)
      yOffset = yOffset + 15
      
      -- Show items from this record
      if record.items and table.getn(record.items) > 0 then
        for _, item in ipairs(record.items) do
          local itemText = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          itemText:SetPoint("TOPLEFT", 40, -yOffset)
          itemText:SetWidth(430)
          itemText:SetJustifyH("LEFT")
          
          -- Get item link for coloring
          local itemName, itemLink, itemQuality = GetItemInfo(item.itemId)
          local displayText
          
          if itemLink and string.find(itemLink, "|H") then
            displayText = itemLink .. " (+" .. item.plus .. ")"
          elseif itemName then
            local colorCode = "|cffffffff"
            if itemQuality == 0 then colorCode = "|cff9d9d9d"
            elseif itemQuality == 1 then colorCode = "|cffffffff"
            elseif itemQuality == 2 then colorCode = "|cff1eff00"
            elseif itemQuality == 3 then colorCode = "|cff0070dd"
            elseif itemQuality == 4 then colorCode = "|cffa335ee"
            elseif itemQuality == 5 then colorCode = "|cffff8000"
            end
            displayText = colorCode .. itemName .. "|r (+" .. item.plus .. ")"
          else
            displayText = item.name .. " (+" .. item.plus .. ")"
          end
          
          itemText:SetText("  " .. displayText)
          table.insert(detailPanel.content, itemText)
          yOffset = yOffset + 13
        end
        yOffset = yOffset + 5
      end
    end
  else
    local noHistoryText = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noHistoryText:SetPoint("TOPLEFT", 20, -yOffset)
    noHistoryText:SetText("No previous validations")
    table.insert(detailPanel.content, noHistoryText)
    yOffset = yOffset + 20
  end
  
  -- Validate button
  local validateBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
  validateBtn:SetWidth(120)
  validateBtn:SetHeight(22)
  validateBtn:SetPoint("TOPLEFT", 10, -yOffset)
  validateBtn:SetText("Save Validation")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(validateBtn)
  end
  validateBtn:SetScript("OnClick", function()
    local _, metadata = OGRH.SRValidation.GetSRPlusData()
    local instance = metadata and metadata.instance or 0
    local saved = OGRH.SRValidation.SaveValidation(playerName, currentSRPlus, instance)
    if saved then
      OGRH.Msg("Validation saved for " .. playerName)
      OGRH.SRValidation.RefreshPlayerList()
      OGRH.SRValidation.SelectPlayer(playerName, playerData, currentSRPlus)
    end
  end)
  table.insert(detailPanel.content, validateBtn)
end

-- Show the SR Validation window
function OGRH.SRValidation.ShowWindow()
  -- Check if RollFor is available
  if not RollFor or not RollFor.SoftRes or not RollForCharDb or not RollForCharDb.softres then
    OGRH.Msg("RollFor addon not found or no soft-res data available.")
    return
  end
  
  -- Close other windows
  if OGRH_RolesFrame then OGRH_RolesFrame:Hide() end
  if OGRH_EncounterSetupFrame then OGRH_EncounterSetupFrame:Hide() end
  if OGRH_InvitesFrame then OGRH_InvitesFrame:Hide() end
  if OGRH.BWLFrame then OGRH.BWLFrame:Hide() end
  
  -- If frame exists, just show and refresh
  if OGRH_SRValidationFrame then
    OGRH_SRValidationFrame:Show()
    OGRH.SRValidation.RefreshPlayerList()
    return
  end
  
  -- Get metadata for title
  local _, metadata = OGRH.SRValidation.GetSRPlusData()
  local raidName = "Unknown Raid"
  local instanceId = ""
  if metadata and metadata.instance then
    if OGRH.Invites and OGRH.Invites.GetInstanceName then
      raidName = OGRH.Invites.GetInstanceName(metadata.instance)
    end
    instanceId = " (" .. tostring(metadata.instance) .. ")"
  end
  
  -- Create main frame
  local frame = CreateFrame("Frame", "OGRH_SRValidationFrame", UIParent)
  frame:SetWidth(750)
  frame:SetHeight(500)
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
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("SR+ Validation - " .. raidName .. instanceId)
  frame.title = title
  
  -- Left panel - Player list with scroll
  local leftPanel = CreateFrame("Frame", nil, frame)
  leftPanel:SetWidth(220)
  leftPanel:SetHeight(432)
  leftPanel:SetPoint("TOPLEFT", 10, -35)
  leftPanel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  leftPanel:SetBackdropColor(0, 0, 0, 0.5)
  frame.leftPanel = leftPanel
  
  -- Scroll frame for player list
  local scrollFrame = CreateFrame("ScrollFrame", nil, leftPanel)
  scrollFrame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 5, -5)
  scrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -5, 5)
  frame.scrollFrame = scrollFrame
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(210)
  scrollChild:SetHeight(scrollFrame:GetHeight())
  scrollFrame:SetScrollChild(scrollChild)
  scrollFrame.scrollChild = scrollChild
  scrollChild.buttons = {}
  
  -- Mouse wheel scrolling
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    local delta = arg1
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    
    if maxScroll < 0 then maxScroll = 0 end
    
    if delta > 0 then
      scrollFrame:SetVerticalScroll(math.max(0, current - 24))
    else
      scrollFrame:SetVerticalScroll(math.min(maxScroll, current + 24))
    end
  end)
  
  -- Right panel - Player details
  local rightPanel = CreateFrame("Frame", nil, frame)
  rightPanel:SetWidth(490)
  rightPanel:SetHeight(459)
  rightPanel:SetPoint("TOPRIGHT", -10, -35)
  rightPanel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  rightPanel:SetBackdropColor(0, 0, 0, 0.5)
  frame.detailPanel = rightPanel
  
  -- Initial message
  local initialText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  initialText:SetPoint("CENTER", 0, 0)
  initialText:SetText("Select a player to view details")
  rightPanel.initialText = initialText
  
  -- Validate All Passed button
  local validateAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  validateAllBtn:SetWidth(120)
  validateAllBtn:SetHeight(22)
  validateAllBtn:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -5)
  validateAllBtn:SetText("Validate All Passed")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(validateAllBtn)
  end
  validateAllBtn:SetScript("OnClick", function()
    OGRH.SRValidation.ValidateAllPassed()
  end)
  
  -- Refresh button (same line as Validate All Passed)
  local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(80)
  refreshBtn:SetHeight(22)
  refreshBtn:SetPoint("LEFT", validateAllBtn, "RIGHT", 5, 0)
  refreshBtn:SetText("Refresh")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(refreshBtn)
  end
  refreshBtn:SetScript("OnClick", function()
    OGRH.SRValidation.RefreshPlayerList()
  end)
  
  -- Close button at top right
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(80)
  closeBtn:SetHeight(22)
  closeBtn:SetPoint("TOPRIGHT", -15, -8)
  closeBtn:SetText("Close")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(closeBtn)
  end
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  
  frame:Show()
  OGRH.SRValidation.RefreshPlayerList()
end

-- Initialize
OGRH.SRValidation.EnsureSV()
