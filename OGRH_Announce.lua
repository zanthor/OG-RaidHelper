-- OGRH_Announce.lua
-- Announcement Tag Replacement System
-- Self-contained module with no external addon dependencies

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_Announce requires OGRH_Core to be loaded first!|r")
  return
end

OGRH.Announcements = OGRH.Announcements or {}

-- Main tag replacement function
-- Replaces tags like [R1.T], [R1.P1], etc. with actual values
-- Parameters:
--   text: The announcement text with tags
--   roles: Array of role definitions {name, isConsumeCheck, consumes}
--   assignments: Array of player assignments per role [roleIndex][slotIndex] = playerName
--   raidMarks: Array of raid marks per role [roleIndex][slotIndex] = markIndex (1-8)
--   assignmentNumbers: Array of assignment numbers per role [roleIndex][slotIndex] = assignmentNum
function OGRH.Announcements.ReplaceTags(text, roles, assignments, raidMarks, assignmentNumbers)
  if not text or text == "" then
    return ""
  end
  
  -- Use the cached class lookup system from OGRH_Core
  local function GetPlayerClass(playerName)
    return OGRH.GetPlayerClass(playerName)
  end
  
  -- Helper function to check if a tag is valid (has a value)
  local function IsTagValid(tagText, assignmentNumbers)
    -- Check [Rx.T] tags
    local roleNum = string.match(tagText, "^%[R(%d+)%.T%]$")
    if roleNum then
      local roleIndex = tonumber(roleNum)
      return roles and roles[roleIndex] ~= nil
    end
    
    -- Check [Rx.P] tags (all players in role)
    roleNum = string.match(tagText, "^%[R(%d+)%.P%]$")
    if roleNum then
      local roleIndex = tonumber(roleNum)
      -- Valid if role exists and has at least one assigned player
      if assignments and assignments[roleIndex] then
        for _, playerName in pairs(assignments[roleIndex]) do
          if playerName then
            return true
          end
        end
      end
      return false
    end
    
    -- Check [Rx.PA] tags (all players with assignments)
    roleNum = string.match(tagText, "^%[R(%d+)%.PA%]$")
    if roleNum then
      local roleIndex = tonumber(roleNum)
      -- Valid if role exists and has at least one assigned player
      if assignments and assignments[roleIndex] then
        for _, playerName in pairs(assignments[roleIndex]) do
          if playerName then
            return true
          end
        end
      end
      return false
    end
    
    -- Check [Rx.Py] tags
    local roleNum, playerNum = string.match(tagText, "^%[R(%d+)%.P(%d+)%]$")
    if roleNum and playerNum then
      local roleIndex = tonumber(roleNum)
      local playerIndex = tonumber(playerNum)
      return assignments and assignments[roleIndex] and assignments[roleIndex][playerIndex] ~= nil
    end
    
    -- Check [Rx.My] tags
    roleNum, playerNum = string.match(tagText, "^%[R(%d+)%.M(%d+)%]$")
    if roleNum and playerNum then
      local roleIndex = tonumber(roleNum)
      local playerIndex = tonumber(playerNum)
      if not raidMarks or not raidMarks[roleIndex] or not raidMarks[roleIndex][playerIndex] then
        return false
      end
      local markIndex = raidMarks[roleIndex][playerIndex]
      return markIndex ~= 0
    end
    
    -- Check [Rx.Ay] tags
    roleNum, playerNum = string.match(tagText, "^%[R(%d+)%.A(%d+)%]$")
    if roleNum and playerNum then
      local roleIndex = tonumber(roleNum)
      local playerIndex = tonumber(playerNum)
      if not assignmentNumbers or not assignmentNumbers[roleIndex] or not assignmentNumbers[roleIndex][playerIndex] then
        return false
      end
      local assignIndex = assignmentNumbers[roleIndex][playerIndex]
      return assignIndex ~= 0
    end
    
    -- Check [Rx.A=y] tags (all players with assignment y in role x)
    local roleNum, assignNum = string.match(tagText, "^%[R(%d+)%.A=(%d+)%]$")
    if roleNum and assignNum then
      local roleIndex = tonumber(roleNum)
      local targetAssign = tonumber(assignNum)
      
      -- Check if any player in this role has this assignment
      if assignmentNumbers and assignmentNumbers[roleIndex] and assignments and assignments[roleIndex] then
        for slotIndex, playerName in pairs(assignments[roleIndex]) do
          if playerName and assignmentNumbers[roleIndex][slotIndex] == targetAssign then
            return true -- At least one player has this assignment
          end
        end
      end
      
      return false -- No players with this assignment
    end
    
    -- Check [Rx.Cy] tags (Consume items)
    roleNum, consumeNum = string.match(tagText, "^%[R(%d+)%.C(%d+)%]$")
    if roleNum and consumeNum then
      local roleIndex = tonumber(roleNum)
      local consumeIndex = tonumber(consumeNum)
      
      -- Check if role is a consume check role and has consume data
      if roles and roles[roleIndex] and roles[roleIndex].isConsumeCheck then
        if roles[roleIndex].consumes and roles[roleIndex].consumes[consumeIndex] then
          local consumeData = roles[roleIndex].consumes[consumeIndex]
          -- Valid if primary name is set
          return consumeData.primaryName ~= nil and consumeData.primaryName ~= ""
        end
      end
      
      return false -- Invalid consume reference
    end
    
    return true -- Not a tag, consider it valid
  end
  
  -- Process conditional blocks: [text with [tags]]
  -- Default is OR: show block if ANY tag is valid, hide if ALL are invalid
  -- If first char after [ is &, it's AND: show block only if ALL tags are valid
  local function ProcessConditionals(inputText)
    local result = inputText
    local maxIterations = 100 -- Prevent infinite loops
    local iterations = 0
    
    while iterations < maxIterations do
      iterations = iterations + 1
      local foundBlock = false
      
      -- Find innermost conditional blocks
      -- Look for patterns like [text [Rx.T] more text] where there's at least one tag
      local searchPos = 1
      local bestStart, bestEnd, bestContent = nil, nil, nil
      
      while searchPos <= string.len(result) do
        -- Find opening bracket
        local openBracket = string.find(result, "%[", searchPos)
        if not openBracket then break end
        
        -- Find matching closing bracket (innermost one)
        local closeBracket = openBracket + 1
        local nestLevel = 0
        local foundClose = false
        
        while closeBracket <= string.len(result) do
          local char = string.sub(result, closeBracket, closeBracket)
          if char == "[" then
            nestLevel = nestLevel + 1
          elseif char == "]" then
            if nestLevel == 0 then
              foundClose = true
              break
            else
              nestLevel = nestLevel - 1
            end
          end
          closeBracket = closeBracket + 1
        end
        
        if foundClose then
          local content = string.sub(result, openBracket + 1, closeBracket - 1)
          
          -- Check if this block contains at least one tag
          if string.find(content, "%[R%d+%.[TPMAC]") then
            -- This is a conditional block
            bestStart = openBracket
            bestEnd = closeBracket
            bestContent = content
            foundBlock = true
            break
          end
        end
        
        searchPos = openBracket + 1
      end
      
      if not foundBlock then
        break
      end
      
      -- Process this conditional block
      local isAndBlock = false
      local contentToCheck = bestContent
      
      if string.sub(bestContent, 1, 1) == "&" then
        isAndBlock = true
        contentToCheck = string.sub(bestContent, 2) -- Remove the & prefix
      end
      
      -- Collect all tags and their validity
      local tags = {}
      local pos = 1
      
      while true do
        local tagStart, tagEnd = string.find(contentToCheck, "%[R%d+%.[TPMAC][^%]]*%]", pos)
        if not tagStart then break end
        
        local tagText = string.sub(contentToCheck, tagStart, tagEnd)
        local valid = IsTagValid(tagText, assignmentNumbers)
        
        table.insert(tags, {
          text = tagText,
          valid = valid,
          startPos = tagStart,
          endPos = tagEnd
        })
        
        pos = tagEnd + 1
      end
      
      -- Determine if block should be shown
      local showBlock = false
      
      if isAndBlock then
        -- AND logic: show only if ALL tags are valid
        showBlock = true
        for _, tag in ipairs(tags) do
          if not tag.valid then
            showBlock = false
            break
          end
        end
      else
        -- OR logic: show if ANY tag is valid
        showBlock = false
        for _, tag in ipairs(tags) do
          if tag.valid then
            showBlock = true
            break
          end
        end
      end
      
      -- Replace the conditional block
      local before = string.sub(result, 1, bestStart - 1)
      local after = string.sub(result, bestEnd + 1)
      
      if showBlock then
        -- For OR blocks, remove invalid tags from the content
        if not isAndBlock then
          -- Build cleaned content by removing invalid tags
          local cleanedContent = ""
          local lastPos = 1
          
          -- Sort tags by start position
          table.sort(tags, function(a, b) return a.startPos < b.startPos end)
          
          for _, tag in ipairs(tags) do
            if tag.valid then
              -- Keep everything up to and including this valid tag
              cleanedContent = cleanedContent .. string.sub(contentToCheck, lastPos, tag.endPos)
              lastPos = tag.endPos + 1
            else
              -- Keep text before the invalid tag, skip the tag itself
              cleanedContent = cleanedContent .. string.sub(contentToCheck, lastPos, tag.startPos - 1)
              lastPos = tag.endPos + 1
            end
          end
          
          -- Add any remaining text after the last tag
          if lastPos <= string.len(contentToCheck) then
            cleanedContent = cleanedContent .. string.sub(contentToCheck, lastPos)
          end
          
          result = before .. cleanedContent .. after
        else
          -- For AND blocks, keep all content as-is (all tags are valid)
          result = before .. contentToCheck .. after
        end
      else
        -- Remove the entire block
        result = before .. after
      end
    end
    
    return result
  end
  
  -- First, process conditional blocks
  local result = ProcessConditionals(text)
  
  -- Build a table of tag replacements with their positions
  local replacements = {}
  
  -- Helper to add a replacement
  local function AddReplacement(startPos, endPos, replacement, color, isValid)
    table.insert(replacements, {
      startPos = startPos,
      endPos = endPos,
      text = replacement,
      color = color,
      isValid = isValid
    })
  end
  
  -- Find [Rx.T] tags (Role Title)
  local pos = 1
  while true do
    local tagStart, tagEnd, roleNum = string.find(result, "%[R(%d+)%.T%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    
    if roles and roles[roleIndex] then
      local replacement = roles[roleIndex].name or "Unknown"
      local color = OGRH.COLOR.HEADER
      AddReplacement(tagStart, tagEnd, replacement, color, true)
    else
      -- Invalid tag - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Find [Rx.P] tags (All Players in Role) - Must come before [Rx.Py]
  pos = 1
  while true do
    local tagStart, tagEnd, roleNum = string.find(result, "%[R(%d+)%.P%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    
    -- Build list of all players in this role with class colors
    local allPlayers = {}
    
    if assignments and assignments[roleIndex] then
      -- Iterate through all slots in this role
      for slotIndex, playerName in pairs(assignments[roleIndex]) do
        if playerName then
          -- Get player's class for coloring
          local playerClass = GetPlayerClass(playerName)
          local color = OGRH.COLOR.ROLE
          
          if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
            color = OGRH.COLOR.CLASS[string.upper(playerClass)]
          end
          
          -- Add player with color code prefix only (no reset)
          table.insert(allPlayers, {index = slotIndex, name = color .. playerName})
        end
      end
    end
    
    if table.getn(allPlayers) > 0 then
      -- Sort by slot index to maintain assignment order
      table.sort(allPlayers, function(a, b) return a.index < b.index end)
      
      -- Extract just the names
      local playerNames = {}
      for _, player in ipairs(allPlayers) do
        table.insert(playerNames, player.name)
      end
      
      -- Join with space and reset code between each player
      local playerList = table.concat(playerNames, OGRH.COLOR.RESET .. " ")
      -- Pass empty color and use the embedded colors
      AddReplacement(tagStart, tagEnd, playerList, "", false)
    else
      -- No players - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Find [Rx.PA] tags (All Players with Assignment Numbers)
  pos = 1
  while true do
    local tagStart, tagEnd, roleNum = string.find(result, "%[R(%d+)%.PA%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    
    -- Build list of all players in this role with their assignment numbers
    local allPlayers = {}
    
    if assignments and assignments[roleIndex] then
      -- Iterate through all slots in this role
      for slotIndex, playerName in pairs(assignments[roleIndex]) do
        if playerName then
          -- Get player's class for coloring
          local playerClass = GetPlayerClass(playerName)
          local color = OGRH.COLOR.ROLE
          
          if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
            color = OGRH.COLOR.CLASS[string.upper(playerClass)]
          end
          
          -- Get assignment number for this player
          local assignNum = ""
          if assignmentNumbers and assignmentNumbers[roleIndex] and assignmentNumbers[roleIndex][slotIndex] then
            local assignIndex = assignmentNumbers[roleIndex][slotIndex]
            if assignIndex and assignIndex ~= 0 then
              assignNum = " (" .. assignIndex .. ")"
            end
          end
          
          -- Add player with color code and assignment number
          table.insert(allPlayers, {index = slotIndex, text = color .. playerName .. assignNum})
        end
      end
    end
    
    if table.getn(allPlayers) > 0 then
      -- Sort by slot index to maintain assignment order
      table.sort(allPlayers, function(a, b) return a.index < b.index end)
      
      -- Extract just the text
      local playerTexts = {}
      for _, player in ipairs(allPlayers) do
        table.insert(playerTexts, player.text)
      end
      
      -- Join with space and reset code between each player
      local playerList = table.concat(playerTexts, OGRH.COLOR.RESET .. " ")
      -- Pass empty color and use the embedded colors
      AddReplacement(tagStart, tagEnd, playerList, "", false)
    else
      -- No players - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Find [Rx.Py] tags (Player Name)
  pos = 1
  while true do
    local tagStart, tagEnd, roleNum, playerNum = string.find(result, "%[R(%d+)%.P(%d+)%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    local playerIndex = tonumber(playerNum)
    
    if assignments and assignments[roleIndex] and assignments[roleIndex][playerIndex] then
      local playerName = assignments[roleIndex][playerIndex]
      local playerClass = GetPlayerClass(playerName)
      local color = OGRH.COLOR.ROLE
      
      if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
        color = OGRH.COLOR.CLASS[string.upper(playerClass)]
      end
      
      AddReplacement(tagStart, tagEnd, playerName, color, true)
    else
      -- Invalid tag - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Find [Rx.My] tags (Raid Mark)
  pos = 1
  while true do
    local tagStart, tagEnd, roleNum, playerNum = string.find(result, "%[R(%d+)%.M(%d+)%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    local playerIndex = tonumber(playerNum)
    
    -- Raid mark names
    local markNames = {
      [1] = "(Star)",
      [2] = "(Circle)",
      [3] = "(Diamond)",
      [4] = "(Triangle)",
      [5] = "(Moon)",
      [6] = "(Square)",
      [7] = "(Cross)",
      [8] = "(Skull)"
    }
    
    if raidMarks and raidMarks[roleIndex] and raidMarks[roleIndex][playerIndex] then
      local markIndex = raidMarks[roleIndex][playerIndex]
      if markIndex ~= 0 and markNames[markIndex] then
        local color = OGRH.COLOR.MARK[markIndex] or OGRH.COLOR.ROLE
        AddReplacement(tagStart, tagEnd, markNames[markIndex], color, true)
      else
        -- Mark is 0 (none) - replace with empty string
        AddReplacement(tagStart, tagEnd, "", "", false)
      end
    else
      -- Invalid tag - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Find [Rx.Ay] tags (Assignment Number)
  pos = 1
  while true do
    local tagStart, tagEnd, roleNum, playerNum = string.find(result, "%[R(%d+)%.A(%d+)%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    local playerIndex = tonumber(playerNum)
    
    if assignmentNumbers and assignmentNumbers[roleIndex] and assignmentNumbers[roleIndex][playerIndex] then
      local assignIndex = assignmentNumbers[roleIndex][playerIndex]
      if assignIndex ~= 0 then
        local color = OGRH.COLOR.ROLE
        AddReplacement(tagStart, tagEnd, tostring(assignIndex), color, true)
      else
        -- Assignment is 0 (none) - replace with empty string
        AddReplacement(tagStart, tagEnd, "", "", false)
      end
    else
      -- Invalid tag - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Find [Rx.A=y] tags (All players with assignment number y in role x)
  pos = 1
  while true do
    local tagStart, tagEnd, roleNum, assignNum = string.find(result, "%[R(%d+)%.A=(%d+)%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    local targetAssign = tonumber(assignNum)
    
    -- Build list of players with this assignment number with class colors
    local matchingPlayers = {}
    
    if assignmentNumbers and assignmentNumbers[roleIndex] and assignments and assignments[roleIndex] then
      -- Iterate through all slots in this role
      for slotIndex, playerName in pairs(assignments[roleIndex]) do
        if playerName and assignmentNumbers[roleIndex][slotIndex] == targetAssign then
          -- Get player's class for coloring
          local playerClass = GetPlayerClass(playerName)
          local color = OGRH.COLOR.ROLE
          
          if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
            color = OGRH.COLOR.CLASS[string.upper(playerClass)]
          end
          
          -- Add player with color code prefix only (no reset)
          table.insert(matchingPlayers, color .. playerName)
        end
      end
    end
    
    if table.getn(matchingPlayers) > 0 then
      -- Join with space and reset code between each player
      local playerList = table.concat(matchingPlayers, OGRH.COLOR.RESET .. " ")
      -- Pass empty color and use the embedded colors
      AddReplacement(tagStart, tagEnd, playerList, "", false)
    else
      -- No matching players - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Find [Rx.Cy] tags (Consume items from Consume Check role)
  pos = 1
  while true do
    local tagStart, tagEnd, roleNum, consumeNum = string.find(result, "%[R(%d+)%.C(%d+)%]", pos)
    if not tagStart then break end
    
    local roleIndex = tonumber(roleNum)
    local consumeIndex = tonumber(consumeNum)
    
    -- Check if this role is a consume check role
    if roles and roles[roleIndex] and roles[roleIndex].isConsumeCheck then
      local consumeRole = roles[roleIndex]
      
      -- Check if consume data exists for this index
      if consumeRole.consumes and consumeRole.consumes[consumeIndex] then
        local consumeData = consumeRole.consumes[consumeIndex]
        
        -- Use the helper function to format item links (no escaping needed)
        local consumeText = ""
        if OGRH.FormatConsumeItemLinks then
          consumeText = OGRH.FormatConsumeItemLinks(consumeData, false)
        end
        
        if consumeText ~= "" then
          -- Item links have their own color codes and must be inserted exactly as-is
          -- Use special marker to indicate this replacement should not be wrapped
          AddReplacement(tagStart, tagEnd, consumeText, "__NOCOLOR__", false)
        else
          -- No consume configured - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
      else
        -- Invalid consume index - replace with empty string
        AddReplacement(tagStart, tagEnd, "", "", false)
      end
    else
      -- Not a consume check role - replace with empty string
      AddReplacement(tagStart, tagEnd, "", "", false)
    end
    
    pos = tagEnd + 1
  end
  
  -- Sort replacements by position (descending) so we can replace from end to start
  table.sort(replacements, function(a, b) return a.startPos > b.startPos end)
  
  -- Build result string by replacing tags from end to start
  for _, repl in ipairs(replacements) do
    local before = string.sub(result, 1, repl.startPos - 1)
    local after = string.sub(result, repl.endPos + 1)
    
    if repl.text == "" then
      -- Empty replacement - just remove the tag
      result = before .. after
    elseif repl.color == "__NOCOLOR__" then
      -- Special case: Item links that must be inserted exactly as-is
      result = before .. repl.text .. after
    else
      -- Non-empty replacement - add with color codes
      result = before .. repl.color .. repl.text .. OGRH.COLOR.RESET .. after
    end
  end
  
  -- Color any plain text with ROLE color
  -- BUT: If the result contains item links (|H), skip this processing entirely
  -- Item links are fragile and must be sent exactly as-is
  if string.find(result, "|H", 1, true) then
    return result
  end
  
  -- Split by color codes to identify plain text
  local finalResult = ""
  local lastPos = 1
  
  while true do
    -- Find next color code
    local colorStart = string.find(result, "|c%x%x%x%x%x%x%x%x", lastPos)
    local hyperlinkStart = nil  -- Not needed since we skip if |H exists
    
    if not colorStart then
      -- No more color codes or hyperlinks, add remaining text
      local remaining = string.sub(result, lastPos)
      if remaining ~= "" then
        finalResult = finalResult .. OGRH.COLOR.ROLE .. remaining .. OGRH.COLOR.RESET
      end
      break
    end
    
    -- Add plain text before color code
    if colorStart > lastPos then
      local plainText = string.sub(result, lastPos, colorStart - 1)
      finalResult = finalResult .. OGRH.COLOR.ROLE .. plainText .. OGRH.COLOR.RESET
    end
    
    -- Find the end of this colored section (next |r or end of string)
    local resetPos = string.find(result, "|r", colorStart)
    if not resetPos then
      -- Add rest of string as-is
      finalResult = finalResult .. string.sub(result, colorStart)
      break
    end
    
    -- Add colored section
    finalResult = finalResult .. string.sub(result, colorStart, resetPos + 1)
    lastPos = resetPos + 2
  end
  
  return finalResult
end

-- Build consume announcement lines from a consume check role
-- Parameters:
--   encounterName: Name of the encounter for the title
--   consumeRole: Role definition with consumes array
-- Returns: Array of announcement lines ready to send
function OGRH.Announcements.BuildConsumeAnnouncement(encounterName, consumeRole)
  if not consumeRole or not consumeRole.consumes then
    return {}
  end
  
  local announceLines = {}
  local titleColor = OGRH.COLOR.HEADER or "|cFFFFD100"
  table.insert(announceLines, titleColor .. "Consumes for " .. encounterName .. OGRH.COLOR.RESET)
  
  for i = 1, (consumeRole.slots or 1) do
    if consumeRole.consumes[i] then
      local consumeData = consumeRole.consumes[i]
      
      -- Use the existing FormatConsumeItemLinks function from Core
      if OGRH.FormatConsumeItemLinks then
        local lineText = OGRH.FormatConsumeItemLinks(consumeData, false)
        if lineText and lineText ~= "" then
          table.insert(announceLines, lineText)
        end
      end
    end
  end
  
  return announceLines
end

-- Unified function to send encounter announcements
-- Parameters:
--   selectedRaid: The raid name (e.g., "Molten Core")
--   selectedEncounter: The encounter name (e.g., "Ragnaros")
-- Returns: true if announcement was sent, false otherwise
function OGRH.Announcements.SendEncounterAnnouncement(selectedRaid, selectedEncounter)
  if not selectedRaid or not selectedEncounter then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No encounter selected")
    return false
  end
  
  -- Check if in raid
  if GetNumRaidMembers() == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r You must be in a raid to announce.")
    return false
  end
  
  -- Broadcast sync to ReadHelper users
  if OGRH.SendReadHelperSyncData then
    OGRH.SendReadHelperSyncData(nil)
  end
  
  -- Get announcement text from saved variables
  if not OGRH_SV.encounterAnnouncements or 
     not OGRH_SV.encounterAnnouncements[selectedRaid] or
     not OGRH_SV.encounterAnnouncements[selectedRaid][selectedEncounter] then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No announcement text configured for this encounter.")
    return false
  end
  
  local announcementData = OGRH_SV.encounterAnnouncements[selectedRaid][selectedEncounter]
  
  -- Get role configuration
  local roles = OGRH_SV.encounterMgmt.roles
  if not roles or not roles[selectedRaid] or not roles[selectedRaid][selectedEncounter] then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
    return false
  end
  
  local encounterRoles = roles[selectedRaid][selectedEncounter]
  local column1 = encounterRoles.column1 or {}
  local column2 = encounterRoles.column2 or {}
  
  -- Build roles array indexed by roleId (not by position)
  local orderedRoles = {}
  for i = 1, table.getn(column1) do
    local role = column1[i]
    local roleId = role.roleId or i
    orderedRoles[roleId] = role
  end
  for i = 1, table.getn(column2) do
    local role = column2[i]
    local roleId = role.roleId or (table.getn(column1) + i)
    orderedRoles[roleId] = role
  end
  
  -- Get assignments
  local assignments = {}
  if OGRH_SV.encounterAssignments and 
     OGRH_SV.encounterAssignments[selectedRaid] and
     OGRH_SV.encounterAssignments[selectedRaid][selectedEncounter] then
    assignments = OGRH_SV.encounterAssignments[selectedRaid][selectedEncounter]
  end
  
  -- Get raid marks
  local raidMarks = {}
  if OGRH_SV.encounterRaidMarks and
     OGRH_SV.encounterRaidMarks[selectedRaid] and
     OGRH_SV.encounterRaidMarks[selectedRaid][selectedEncounter] then
    raidMarks = OGRH_SV.encounterRaidMarks[selectedRaid][selectedEncounter]
  end
  
  -- Get assignment numbers
  local assignmentNumbers = {}
  if OGRH_SV.encounterAssignmentNumbers and
     OGRH_SV.encounterAssignmentNumbers[selectedRaid] and
     OGRH_SV.encounterAssignmentNumbers[selectedRaid][selectedEncounter] then
    assignmentNumbers = OGRH_SV.encounterAssignmentNumbers[selectedRaid][selectedEncounter]
  end
  
  -- Process announcement lines using ReplaceTags
  local announcementLines = {}
  for i = 1, table.getn(announcementData) do
    local lineText = announcementData[i]
    if lineText and lineText ~= "" then
      local processedText = OGRH.Announcements.ReplaceTags(lineText, orderedRoles, assignments, raidMarks, assignmentNumbers)
      if processedText and processedText ~= "" then
        table.insert(announcementLines, processedText)
      end
    end
  end
  
  -- Send announcements to raid chat
  if table.getn(announcementLines) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No announcement text to send.")
    return false
  end
  
  -- Send announcement using SendAnnouncement (which checks for raid warning permission)
  if OGRH.SendAnnouncement then
    OGRH.SendAnnouncement(announcementLines)
  else
    -- Fallback if SendAnnouncement not loaded
    for _, line in ipairs(announcementLines) do
      SendChatMessage(line, "RAID")
    end
  end
  
  return true
end

-- Global wrapper function for backward compatibility
-- This allows existing code to call OGRH.ReplaceAnnouncementTags()
function OGRH.ReplaceAnnouncementTags(text, roles, assignments, raidMarks, assignmentNumbers)
  return OGRH.Announcements.ReplaceTags(text, roles, assignments, raidMarks, assignmentNumbers)
end

-- Module initialization message
-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Announcement system loaded")
