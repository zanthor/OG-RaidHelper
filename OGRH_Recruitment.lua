-- OGRH_Recruitment.lua
-- Guild recruitment advertising and contact tracking module

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_Recruitment requires OGRH_Core to be loaded first!|r")
  return
end

-- Module registration
OGRH.RegisterModule({
  id = "recruitment",
  name = "Recruitment",
  description = "Guild recruitment advertising and contact tracking"
})

-- ========================================
-- SAVED VARIABLES INITIALIZATION
-- ========================================

function OGRH.EnsureRecruitmentSV()
  OGRH.EnsureSV()
  
  if not OGRH_SV.recruitment then
    OGRH_SV.recruitment = {
      enabled = false,
      message = "",
      messages = {"", "", "", "", ""}, -- 5 preset messages
      messages2 = {"", "", "", "", ""}, -- 5 preset second messages
      selectedMessageIndex = 1, -- Currently selected message (1-5)
      selectedChannel = "general", -- Radio button selection: general, trade, world, raid
      interval = 600, -- Default 10 minutes between ads
      lastAdTime = 0,
      contacts = {}, -- Track people spoken to: {name, timestamp, messages = {}}
      whisperHistory = {}, -- [playerName] = {messages = {{text, timestamp, incoming}}, lastContact = timestamp}
      playerCache = {}, -- [playerName] = {class = "CLASS", level = number, guild = "name"}
      deletedContacts = {}, -- [playerName] = true for explicitly deleted contacts
      autoAd = false, -- Auto-advertise on interval
      isRecruiting = false, -- Currently recruiting
      rotateMessages = {false, false, false, false, false}, -- Which messages to include in rotation
      lastRotationIndex = 0 -- Last message index sent in rotation
    }
  end
  
  -- Ensure whisperHistory, playerCache, and deletedContacts exist (for migration)
  if not OGRH_SV.recruitment.whisperHistory then
    OGRH_SV.recruitment.whisperHistory = {}
  end
  if not OGRH_SV.recruitment.playerCache then
    OGRH_SV.recruitment.playerCache = {}
  end
  if not OGRH_SV.recruitment.deletedContacts then
    OGRH_SV.recruitment.deletedContacts = {}
  end
  
  -- Ensure messages array exists (for migration)
  if not OGRH_SV.recruitment.messages then
    OGRH_SV.recruitment.messages = {"", "", "", "", ""}
    -- Migrate old single message to Message 1
    if OGRH_SV.recruitment.message and OGRH_SV.recruitment.message ~= "" then
      OGRH_SV.recruitment.messages[1] = OGRH_SV.recruitment.message
    end
  end
  if not OGRH_SV.recruitment.messages2 then
    OGRH_SV.recruitment.messages2 = {"", "", "", "", ""}
  end
  if not OGRH_SV.recruitment.selectedMessageIndex then
    OGRH_SV.recruitment.selectedMessageIndex = 1
  end
  if not OGRH_SV.recruitment.rotateMessages then
    OGRH_SV.recruitment.rotateMessages = {false, false, false, false, false}
  end
  if not OGRH_SV.recruitment.lastRotationIndex then
    OGRH_SV.recruitment.lastRotationIndex = 0
  end
  if not OGRH_SV.recruitment.targetTime then
    OGRH_SV.recruitment.targetTime = ""
  end
  
  -- Migrate old channels format to new selectedChannel format
  if OGRH_SV.recruitment.channels then
    -- Pick the first checked channel as the selected one
    if OGRH_SV.recruitment.channels.general then
      OGRH_SV.recruitment.selectedChannel = "general"
    elseif OGRH_SV.recruitment.channels.trade then
      OGRH_SV.recruitment.selectedChannel = "trade"
    elseif OGRH_SV.recruitment.channels.world then
      OGRH_SV.recruitment.selectedChannel = "world"
    elseif OGRH_SV.recruitment.channels.localdefense then
      OGRH_SV.recruitment.selectedChannel = "general" -- Map old localdefense to general
    end
    OGRH_SV.recruitment.channels = nil -- Remove old format
  end
end

-- ========================================
-- RECRUITMENT WINDOW
-- ========================================

local recruitmentFrame = nil

function OGRH.ShowRecruitmentWindow()
  OGRH.EnsureRecruitmentSV()
  
  -- Close other windows
  if OGRH.CloseAllWindows then
    OGRH.CloseAllWindows("OGRH_RecruitmentFrame")
  end
  
  if recruitmentFrame then
    recruitmentFrame:Show()
    -- Refresh the contact list to show any new whispers
    if recruitmentFrame.PopulateLeftList then
      recruitmentFrame.PopulateLeftList()
    end
    -- Refresh the view to update button state
    if recruitmentFrame.ShowAdvertiseView then
      recruitmentFrame.ShowAdvertiseView()
    end
    return
  end
  
  -- Create main frame
  local frame = CreateFrame("Frame", "OGRH_RecruitmentFrame", UIParent)
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
  recruitmentFrame = frame
  
  -- Register ESC key handler
  table.insert(UISpecialFrames, "OGRH_RecruitmentFrame")
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Guild Recruitment")
  
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
  instructions:SetText("Select an option:")
  
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
  frame.detailPanel = detailPanel
  
  -- Store reference to current content function
  frame.currentView = nil
  frame.ShowAdvertiseView = function()
    OGRH.ShowRecruitmentAdvertiseView(frame)
  end
  
  -- Function to populate the left list with options and contacts
  frame.PopulateLeftList = function()
    -- Clear existing items
    local children = {scrollChild:GetChildren()}
    for _, child in ipairs(children) do
      child:Hide()
      child:SetParent(nil)
    end
    
    OGRH.EnsureRecruitmentSV()
    
    local yOffset = 0
    
    -- Advertise option
    local advertiseRow = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
    advertiseRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    
    local advertiseText = advertiseRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    advertiseText:SetPoint("LEFT", advertiseRow, "LEFT", 8, 0)
    advertiseText:SetText("Advertise")
    
    advertiseRow:SetScript("OnClick", function()
      OGRH.ShowRecruitmentAdvertiseView(frame)
    end)
    
    yOffset = yOffset - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    
    -- Contact entries
    local whisperHistory = OGRH_SV.recruitment.whisperHistory
    local contacts = {}
    for name, data in pairs(whisperHistory) do
      table.insert(contacts, {name = name, lastContact = data.lastContact or 0})
    end
    table.sort(contacts, function(a, b) return a.lastContact > b.lastContact end)
    
    for i, contact in ipairs(contacts) do
      local row = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
      
      -- Get class color
      local r, g, b, class = OGRH.GetRecruitmentPlayerClass(contact.name)
      
      -- Format timestamp as MM/DD HH:MM
      local timeStr = ""
      if contact.lastContact and contact.lastContact > 0 then
        timeStr = date("%m/%d %H:%M", contact.lastContact)
      end
      
      local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      nameText:SetPoint("LEFT", row, "LEFT", 20, 0)
      nameText:SetPoint("RIGHT", row, "RIGHT", -40, 0)
      nameText:SetJustifyH("LEFT")
      nameText:SetText(contact.name .. "  |cff888888" .. timeStr .. "|r")
      nameText:SetTextColor(r, g, b)
      
      -- Capture contact name in closure
      local contactName = contact.name
      
      -- Add standard delete button
      OGRH.AddListItemButtons(row, i, table.getn(contacts), nil, nil, function()
        OGRH_SV.recruitment.whisperHistory[contactName] = nil
        OGRH_SV.recruitment.deletedContacts[contactName] = true
        frame.PopulateLeftList()
      end, true)
      
      -- Click to view chat
      row:SetScript("OnClick", function()
        OGRH.ShowRecruitmentChatView(frame, contactName)
      end)
      
      yOffset = yOffset - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    end
    
    scrollChild:SetHeight(math.max(1, -yOffset))
  end
  
  -- Initial populate
  frame.PopulateLeftList()
  
  -- Add OnUpdate handler for scheduled refreshes
  frame:SetScript("OnUpdate", function()
    if this.refreshScheduled and GetTime() >= this.refreshTime then
      this.refreshScheduled = false
      if this.PopulateLeftList then
        this.PopulateLeftList()
      end
    end
  end)
  
  -- Show default view
  frame.ShowAdvertiseView()
  frame:Show()
end

-- Show Advertise view in detail panel
function OGRH.ShowRecruitmentAdvertiseView(frame)
  local detailPanel = frame.detailPanel
  
  -- Clear existing content
  if detailPanel.content then
    for _, child in ipairs(detailPanel.content) do
      child:Hide()
      child:SetParent(nil)
    end
  end
  detailPanel.content = {}
  
  -- Recruitment message section
  local messageLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  messageLabel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 15, -15)
  messageLabel:SetText("Recruitment Message (0/255 characters):")
  table.insert(detailPanel.content, messageLabel)
  
  -- Message selector button
  local messageSelectorBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
  messageSelectorBtn:SetPoint("LEFT", messageLabel, "RIGHT", 10, 0)
  messageSelectorBtn:SetWidth(100)
  messageSelectorBtn:SetHeight(22)
  messageSelectorBtn:SetText("Message " .. OGRH_SV.recruitment.selectedMessageIndex)
  if OGRH.StyleButton then
    OGRH.StyleButton(messageSelectorBtn)
  end
  table.insert(detailPanel.content, messageSelectorBtn)
  
  -- Dropdown menu handler
  messageSelectorBtn:SetScript("OnClick", function()
    -- Create menu frame
    local menuFrame = CreateFrame("Frame", nil, UIParent)
    menuFrame:SetWidth(100)
    menuFrame:SetHeight(5 * 20 + 10)
    menuFrame:SetPoint("TOPLEFT", messageSelectorBtn, "BOTTOMLEFT", 0, -2)
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:SetFrameLevel(100)
    menuFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    menuFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    menuFrame:EnableMouse(true)
    
    -- Close menu on hide
    menuFrame:SetScript("OnHide", function()
      this:SetParent(nil)
    end)
    
    -- Create menu items for Message 1-5
    for i = 1, 5 do
      local btn = CreateFrame("Button", nil, menuFrame)
      btn:SetWidth(94)
      btn:SetHeight(18)
      btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 3, -3 - ((i-1) * 20))
      
      local bg = btn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
      bg:Hide()
      
      local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      text:SetPoint("LEFT", btn, "LEFT", 5, 0)
      text:SetText("Message " .. i)
      
      -- Highlight current selection
      if i == OGRH_SV.recruitment.selectedMessageIndex then
        text:SetTextColor(1, 0.82, 0)
      end
      
      -- Capture index for closure
      local messageIndex = i
      
      btn:SetScript("OnEnter", function()
        bg:Show()
      end)
      
      btn:SetScript("OnLeave", function()
        bg:Hide()
      end)
      
      btn:SetScript("OnClick", function()
        -- Save current messages before switching
        if detailPanel.messageBox then
          OGRH_SV.recruitment.messages[OGRH_SV.recruitment.selectedMessageIndex] = detailPanel.messageBox:GetText()
        end
        if detailPanel.messageBox2 then
          OGRH_SV.recruitment.messages2[OGRH_SV.recruitment.selectedMessageIndex] = detailPanel.messageBox2:GetText()
        end
        
        -- Switch to new message
        OGRH_SV.recruitment.selectedMessageIndex = messageIndex
        
        -- Update dropdown button text
        if detailPanel.messageSelectorBtn then
          detailPanel.messageSelectorBtn:SetText("Message " .. messageIndex)
        end
        
        -- Load new message text
        if detailPanel.messageBox then
          local newMessage = OGRH_SV.recruitment.messages[messageIndex] or ""
          detailPanel.messageBox:SetText(newMessage)
          -- Update character count
          if detailPanel.messageLabel then
            detailPanel.messageLabel:SetText("Recruitment Message (" .. string.len(newMessage) .. "/255 characters):")
          end
        end
        if detailPanel.messageBox2 then
          local newMessage2 = OGRH_SV.recruitment.messages2[messageIndex] or ""
          detailPanel.messageBox2:SetText(newMessage2)
          -- Update character count
          if detailPanel.messageLabel2 then
            detailPanel.messageLabel2:SetText("Second Message (" .. string.len(newMessage2) .. "/255 characters):")
          end
        end
        
        menuFrame:Hide()
      end)
    end
    
    -- Close menu when clicking outside
    local closeFrame = CreateFrame("Frame", nil, UIParent)
    closeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    closeFrame:SetFrameLevel(99)
    closeFrame:SetAllPoints()
    closeFrame:EnableMouse(true)
    closeFrame:SetScript("OnMouseDown", function()
      menuFrame:Hide()
      this:Hide()
    end)
    closeFrame:SetScript("OnHide", function()
      this:SetParent(nil)
    end)
    menuFrame:SetScript("OnHide", function()
      closeFrame:Hide()
      this:SetParent(nil)
    end)
  end)
  
  -- Message edit box using ScrollFrame to properly clip text selection
  local messageBackdrop = CreateFrame("Frame", nil, detailPanel)
  messageBackdrop:SetPoint("TOPLEFT", messageLabel, "BOTTOMLEFT", 0, -4)
  messageBackdrop:SetWidth(350)
  messageBackdrop:SetHeight(50)
  messageBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  messageBackdrop:SetBackdropColor(0, 0, 0, 1)
  messageBackdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  table.insert(detailPanel.content, messageBackdrop)
  
  -- ScrollFrame to clip text selection (no visible scrollbar)
  local messageScrollFrame = CreateFrame("ScrollFrame", nil, messageBackdrop)
  messageScrollFrame:SetPoint("TOPLEFT", 5, -5)
  messageScrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)
  
  local contentWidth = 340 - 10
  
  -- Scroll child
  local messageScrollChild = CreateFrame("Frame", nil, messageScrollFrame)
  messageScrollFrame:SetScrollChild(messageScrollChild)
  messageScrollChild:SetWidth(contentWidth)
  messageScrollChild:SetHeight(400)
  
  -- Edit box
  local messageBox = CreateFrame("EditBox", nil, messageScrollChild)
  messageBox:SetPoint("TOPLEFT", 0, 0)
  messageBox:SetWidth(contentWidth)
  messageBox:SetHeight(400)
  messageBox:SetMultiLine(true)
  messageBox:SetAutoFocus(false)
  messageBox:SetMaxLetters(255)
  messageBox:SetFontObject(GameFontHighlightSmall)
  messageBox:SetTextInsets(5, 5, 3, 3)
  messageBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  messageBox:SetScript("OnTextChanged", function()
    local text = this:GetText()
    local len = string.len(text)
    -- Save to current selected message slot
    OGRH_SV.recruitment.messages[OGRH_SV.recruitment.selectedMessageIndex] = text
    -- Also update legacy message field for backward compatibility
    OGRH_SV.recruitment.message = text
    -- Update character count in label
    messageLabel:SetText("Recruitment Message (" .. len .. "/255 characters):")
  end)
  
  -- Load text from selected message slot
  local currentMessage = OGRH_SV.recruitment.messages[OGRH_SV.recruitment.selectedMessageIndex] or ""
  messageBox:SetText(currentMessage)
  
  -- Store references for dropdown handler
  detailPanel.messageBox = messageBox
  detailPanel.messageLabel = messageLabel
  detailPanel.messageSelectorBtn = messageSelectorBtn
  
  -- Second Message label
  local messageLabel2 = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  messageLabel2:SetPoint("TOPLEFT", messageBackdrop, "BOTTOMLEFT", 0, -8)
  messageLabel2:SetText("Second Message (0/255 characters):")
  table.insert(detailPanel.content, messageLabel2)
  
  -- Second Message edit box
  local messageBackdrop2 = CreateFrame("Frame", nil, detailPanel)
  messageBackdrop2:SetPoint("TOPLEFT", messageLabel2, "BOTTOMLEFT", 0, -4)
  messageBackdrop2:SetWidth(350)
  messageBackdrop2:SetHeight(50)
  messageBackdrop2:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  messageBackdrop2:SetBackdropColor(0, 0, 0, 1)
  messageBackdrop2:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  table.insert(detailPanel.content, messageBackdrop2)
  
  -- ScrollFrame for second message
  local messageScrollFrame2 = CreateFrame("ScrollFrame", nil, messageBackdrop2)
  messageScrollFrame2:SetPoint("TOPLEFT", 5, -5)
  messageScrollFrame2:SetPoint("BOTTOMRIGHT", -5, 5)
  
  -- Scroll child for second message
  local messageScrollChild2 = CreateFrame("Frame", nil, messageScrollFrame2)
  messageScrollFrame2:SetScrollChild(messageScrollChild2)
  messageScrollChild2:SetWidth(contentWidth)
  messageScrollChild2:SetHeight(400)
  
  -- Edit box for second message
  local messageBox2 = CreateFrame("EditBox", nil, messageScrollChild2)
  messageBox2:SetPoint("TOPLEFT", 0, 0)
  messageBox2:SetWidth(contentWidth)
  messageBox2:SetHeight(400)
  messageBox2:SetMultiLine(true)
  messageBox2:SetAutoFocus(false)
  messageBox2:SetMaxLetters(255)
  messageBox2:SetFontObject(GameFontHighlightSmall)
  messageBox2:SetTextInsets(5, 5, 3, 3)
  messageBox2:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  messageBox2:SetScript("OnTextChanged", function()
    local text = this:GetText()
    local len = string.len(text)
    -- Save to current selected message slot
    OGRH_SV.recruitment.messages2[OGRH_SV.recruitment.selectedMessageIndex] = text
    -- Update character count in label
    messageLabel2:SetText("Second Message (" .. len .. "/255 characters):")
  end)
  
  -- Load text from selected message slot
  local currentMessage2 = OGRH_SV.recruitment.messages2[OGRH_SV.recruitment.selectedMessageIndex] or ""
  messageBox2:SetText(currentMessage2)
  
  -- Store references for dropdown handler
  detailPanel.messageBox2 = messageBox2
  detailPanel.messageLabel2 = messageLabel2
  
  -- Channel selection (radio buttons in single line)
  local channelLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  channelLabel:SetPoint("TOPLEFT", messageBackdrop2, "BOTTOMLEFT", 0, -12)
  channelLabel:SetText("Advertise in:")
  table.insert(detailPanel.content, channelLabel)
  
  local channels = {
    {key = "general", label = "General Chat"},
    {key = "trade", label = "Trade Chat"},
    {key = "world", label = "World Chat"},
    {key = "raid", label = "Raid Chat"}
  }
  
  -- Store radio buttons for mutual exclusion
  local radioButtons = {}
  
  local xOffset = 0
  for i, channel in ipairs(channels) do
    local radio = CreateFrame("CheckButton", nil, detailPanel, "UICheckButtonTemplate")
    radio:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", xOffset, -8)
    radio:SetWidth(24)
    radio:SetHeight(24)
    radio:SetChecked(OGRH_SV.recruitment.selectedChannel == channel.key)
    
    -- Capture channel key in local variable to avoid closure issue
    local channelKey = channel.key
    radio:SetScript("OnClick", function()
      -- Uncheck all other radio buttons
      for _, otherRadio in ipairs(radioButtons) do
        otherRadio:SetChecked(false)
      end
      -- Check this one
      this:SetChecked(true)
      OGRH_SV.recruitment.selectedChannel = channelKey
    end)
    table.insert(detailPanel.content, radio)
    table.insert(radioButtons, radio)
    
    local label = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
    label:SetText(channel.label)
    
    xOffset = xOffset + 90
  end
  
  -- Interval setting
  local intervalLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  intervalLabel:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 0, -36)
  intervalLabel:SetText("Interval (minutes):")
  table.insert(detailPanel.content, intervalLabel)
  
  local intervalBox = CreateFrame("EditBox", nil, detailPanel)
  intervalBox:SetPoint("LEFT", intervalLabel, "RIGHT", 8, 0)
  intervalBox:SetWidth(60)
  intervalBox:SetHeight(20)
  intervalBox:SetAutoFocus(false)
  intervalBox:SetNumeric(true)
  intervalBox:SetFontObject(GameFontHighlight)
  intervalBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  intervalBox:SetBackdropColor(0, 0, 0, 0.5)
  intervalBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  intervalBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  intervalBox:SetScript("OnTextChanged", function()
    local value = tonumber(this:GetText())
    if value and value > 0 then
      OGRH_SV.recruitment.interval = value * 60
    end
  end)
  intervalBox:SetText(tostring(math.floor((OGRH_SV.recruitment.interval or 600) / 60)))
  table.insert(detailPanel.content, intervalBox)
  
  -- Target Time setting
  local targetTimeLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  targetTimeLabel:SetPoint("LEFT", intervalBox, "RIGHT", 20, 0)
  targetTimeLabel:SetText("Target Time:")
  table.insert(detailPanel.content, targetTimeLabel)
  
  local targetTimeBox = CreateFrame("EditBox", nil, detailPanel)
  targetTimeBox:SetPoint("LEFT", targetTimeLabel, "RIGHT", 8, 0)
  targetTimeBox:SetWidth(60)
  targetTimeBox:SetHeight(20)
  targetTimeBox:SetAutoFocus(false)
  targetTimeBox:SetMaxLetters(4)
  targetTimeBox:SetFontObject(GameFontHighlight)
  targetTimeBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  targetTimeBox:SetBackdropColor(0, 0, 0, 0.5)
  targetTimeBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  targetTimeBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  targetTimeBox:SetScript("OnTextChanged", function()
    local text = this:GetText()
    -- Validate input is numeric and 4 digits or less
    if text and string.len(text) > 0 then
      local value = tonumber(text)
      if value and value >= 0 and value <= 2359 then
        OGRH_SV.recruitment.targetTime = text
      end
    else
      OGRH_SV.recruitment.targetTime = ""
    end
  end)
  targetTimeBox:SetText(OGRH_SV.recruitment.targetTime or "")
  table.insert(detailPanel.content, targetTimeBox)
  
  -- Rotate Message section
  local rotateLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rotateLabel:SetPoint("TOPLEFT", intervalLabel, "BOTTOMLEFT", 0, -12)
  rotateLabel:SetText("Rotate Message #:")
  table.insert(detailPanel.content, rotateLabel)
  
  -- Rotation checkboxes (1-5)
  local rotateCheckboxes = {}
  for i = 1, 5 do
    local checkbox = CreateFrame("CheckButton", nil, detailPanel, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", rotateLabel, "BOTTOMLEFT", (i-1) * 50, -8)
    checkbox:SetWidth(24)
    checkbox:SetHeight(24)
    checkbox:SetChecked(OGRH_SV.recruitment.rotateMessages[i])
    
    -- Capture index for closure
    local messageIndex = i
    checkbox:SetScript("OnClick", function()
      OGRH_SV.recruitment.rotateMessages[messageIndex] = this:GetChecked()
    end)
    table.insert(detailPanel.content, checkbox)
    table.insert(rotateCheckboxes, checkbox)
    
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    label:SetText(i)
  end
  
  -- Start/Stop Recruiting button
  local recruitBtn = CreateFrame("Button", nil, detailPanel, "UIPanelButtonTemplate")
  recruitBtn:SetWidth(140)
  recruitBtn:SetHeight(24)
  recruitBtn:SetPoint("BOTTOM", detailPanel, "BOTTOM", 0, 15)
  recruitBtn:SetText(OGRH_SV.recruitment.isRecruiting and "Stop Recruiting" or "Start Recruiting")
  if OGRH.StyleButton then
    OGRH.StyleButton(recruitBtn)
  end
  recruitBtn:SetScript("OnClick", function()
    if OGRH_SV.recruitment.isRecruiting then
      OGRH.StopRecruiting()
    else
      OGRH.StartRecruiting()
    end
  end)
  table.insert(detailPanel.content, recruitBtn)
  
  -- Store button reference for updates
  detailPanel.recruitBtn = recruitBtn
end

-- ========================================
-- RECRUITMENT ADVERTISING
-- ========================================

function OGRH.SendRecruitmentAd()
  OGRH.EnsureRecruitmentSV()
  
  -- Check if rotation is enabled (more than one message checked)
  local rotateMessages = OGRH_SV.recruitment.rotateMessages
  local checkedMessages = {}
  local checkedCount = 0
  for i = 1, 5 do
    if rotateMessages[i] then
      table.insert(checkedMessages, i)
      checkedCount = checkedCount + 1
    end
  end
  
  local message
  local message2
  local messageIndex
  
  if checkedCount > 1 then
    -- Rotation mode: cycle through checked messages
    local lastIndex = OGRH_SV.recruitment.lastRotationIndex
    
    -- Find next message in rotation
    local nextIndex = nil
    for _, idx in ipairs(checkedMessages) do
      if idx > lastIndex then
        nextIndex = idx
        break
      end
    end
    
    -- If no next message found, wrap around to first
    if not nextIndex then
      nextIndex = checkedMessages[1]
    end
    
    messageIndex = nextIndex
    message = OGRH_SV.recruitment.messages[nextIndex]
    message2 = OGRH_SV.recruitment.messages2[nextIndex]
    OGRH_SV.recruitment.lastRotationIndex = nextIndex
  else
    -- Single message mode: use current selected message
    messageIndex = OGRH_SV.recruitment.selectedMessageIndex
    message = OGRH_SV.recruitment.messages[messageIndex]
    message2 = OGRH_SV.recruitment.messages2[messageIndex]
  end
  
  -- Replace [TTP] tag with minutes until target time
  if OGRH_SV.recruitment.targetTime and OGRH_SV.recruitment.targetTime ~= "" then
    local targetTime = OGRH_SV.recruitment.targetTime
    local targetHour = math.floor(tonumber(targetTime) / 100)
    local targetMin = math.mod(tonumber(targetTime), 100)
    
    -- Get current local time
    local currentHour = tonumber(date("%H"))
    local currentMin = tonumber(date("%M"))
    
    -- Calculate target time in minutes from midnight
    local targetTotalMin = targetHour * 60 + targetMin
    local currentTotalMin = currentHour * 60 + currentMin
    
    -- Calculate difference
    local diffMin = targetTotalMin - currentTotalMin
    
    -- If target is earlier than current time, assume it's tomorrow
    if diffMin < 0 then
      diffMin = diffMin + (24 * 60)
    end
    
    -- Replace [TTP] with the calculated minutes
    if message then
      message = string.gsub(message, "%[TTP%]", tostring(diffMin))
    end
    if message2 and message2 ~= "" then
      message2 = string.gsub(message2, "%[TTP%]", tostring(diffMin))
    end
  end
  
  if not message or message == "" then
    OGRH.Msg("Please set a recruitment message first.")
    return
  end
  
  local selectedChannel = OGRH_SV.recruitment.selectedChannel
  if not selectedChannel then
    OGRH.Msg("No channel selected for recruitment advertising.")
    return
  end
  
  -- Send to the selected channel
  local msgSuffix = ""
  if checkedCount > 1 then
    msgSuffix = " (Message " .. messageIndex .. ")"
  end
  
  local hasSecondMessage = message2 and message2 ~= ""
  
  if selectedChannel == "general" then
    SendChatMessage(message, "CHANNEL", nil, GetChannelName("General"))
    if hasSecondMessage then
      SendChatMessage(message2, "CHANNEL", nil, GetChannelName("General"))
    end
    OGRH.Msg("Recruitment message" .. (hasSecondMessage and "s" or "") .. " sent to General Chat." .. msgSuffix)
  elseif selectedChannel == "trade" then
    SendChatMessage(message, "CHANNEL", nil, GetChannelName("Trade"))
    if hasSecondMessage then
      SendChatMessage(message2, "CHANNEL", nil, GetChannelName("Trade"))
    end
    OGRH.Msg("Recruitment message" .. (hasSecondMessage and "s" or "") .. " sent to Trade Chat." .. msgSuffix)
  elseif selectedChannel == "world" then
    SendChatMessage(message, "CHANNEL", nil, GetChannelName("World"))
    if hasSecondMessage then
      SendChatMessage(message2, "CHANNEL", nil, GetChannelName("World"))
    end
    OGRH.Msg("Recruitment message" .. (hasSecondMessage and "s" or "") .. " sent to World Chat." .. msgSuffix)
  elseif selectedChannel == "raid" then
    if GetNumRaidMembers() > 0 then
      SendChatMessage(message, "RAID")
      if hasSecondMessage then
        SendChatMessage(message2, "RAID")
      end
      OGRH.Msg("Recruitment message" .. (hasSecondMessage and "s" or "") .. " sent to Raid Chat." .. msgSuffix)
    else
      OGRH.Msg("You are not in a raid.")
      return
    end
  end
  
  OGRH_SV.recruitment.lastAdTime = GetTime()
end

-- ========================================
-- RECRUITING PANEL (AUXILIARY PANEL)
-- ========================================

local recruitingPanelFrame = nil

function OGRH.ShowRecruitingPanel()
  -- Create panel if it doesn't exist
  if not recruitingPanelFrame then
    OGRH.CreateRecruitingPanel()
  end
  
  -- Show the panel
  if recruitingPanelFrame and not recruitingPanelFrame:IsVisible() then
    recruitingPanelFrame:Show()
  end
end

-- Create the recruiting panel frame
function OGRH.CreateRecruitingPanel()
  if recruitingPanelFrame then
    return
  end
  
  -- Create auxiliary panel
  local frame = CreateFrame("Frame", "OGRH_RecruitingPanel", UIParent)
  local mainWidth = OGRH_Main and OGRH_Main:GetWidth() or 240
  frame:SetWidth(mainWidth)
  frame:SetHeight(45)
  frame:SetFrameStrata("MEDIUM")
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Title and Stop button on same line
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
  title:SetText("Guild Recruiting")
  
  -- Stop button
  local stopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  stopBtn:SetWidth(50)
  stopBtn:SetHeight(18)
  stopBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
  stopBtn:SetText("Stop")
  if OGRH.StyleButton then
    OGRH.StyleButton(stopBtn)
  end
  stopBtn:SetScript("OnClick", function()
    OGRH.StopRecruiting()
  end)
  
  -- Progress bar (like Ready Check - stretches full width with margins)
  local progressBar = CreateFrame("StatusBar", nil, frame)
  progressBar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  progressBar:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  progressBar:SetHeight(10)
  progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  progressBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
  progressBar:SetMinMaxValues(0, 1)
  progressBar:SetValue(0)
  frame.progressBar = progressBar
  
  -- Progress text (centered on bar like Ready Check)
  local progressText = progressBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  progressText:SetPoint("CENTER", progressBar, "CENTER", 0, 0)
  progressText:SetText("0:00")
  frame.progressText = progressText
  
  -- Update script
  frame:SetScript("OnUpdate", function()
    OGRH.UpdateRecruitingPanel()
  end)
  
  -- Register with auxiliary panel system (priority 15 - between consume monitor and ready check)
  frame:SetScript("OnShow", function()
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(this, 15)
    end
  end)
  
  frame:SetScript("OnHide", function()
    if OGRH.UnregisterAuxiliaryPanel then
      OGRH.UnregisterAuxiliaryPanel(this)
    end
  end)
  
  recruitingPanelFrame = frame
  frame:Show()
  
  -- Manually trigger registration and positioning (in case OnShow doesn't fire)
  if OGRH.RegisterAuxiliaryPanel then
    OGRH.RegisterAuxiliaryPanel(frame, 15)
  end
  if OGRH.RepositionAuxiliaryPanels then
    OGRH.RepositionAuxiliaryPanels()
  end
end

function OGRH.HideRecruitingPanel()
  if recruitingPanelFrame then
    recruitingPanelFrame:Hide()
  end
end

function OGRH.UpdateRecruitingPanel()
  if not recruitingPanelFrame or not OGRH_SV.recruitment.isRecruiting then
    return
  end
  
  local interval = OGRH_SV.recruitment.interval or 600
  local lastAdTime = OGRH_SV.recruitment.lastAdTime or 0
  local currentTime = GetTime()
  local timeSinceLastAd = currentTime - lastAdTime
  local timeUntilNext = math.max(0, interval - timeSinceLastAd)
  
  -- Update progress bar (count down from full to empty)
  local progress = math.max(0, timeUntilNext / interval)
  recruitingPanelFrame.progressBar:SetValue(progress)
  
  -- Update text
  local minutes = math.floor(timeUntilNext / 60)
  local seconds = math.floor(mod(timeUntilNext, 60))
  local secondsStr = tostring(seconds)
  if seconds < 10 then
    secondsStr = "0" .. secondsStr
  end
  recruitingPanelFrame.progressText:SetText(tostring(minutes) .. ":" .. secondsStr)
  
  -- Send ad if time is up
  if timeUntilNext <= 0 and timeSinceLastAd >= interval then
    OGRH.SendRecruitmentAd()
  end
end

-- Start recruiting
function OGRH.StartRecruiting()
  OGRH.EnsureRecruitmentSV()
  
  local message = OGRH_SV.recruitment.message
  if not message or message == "" then
    OGRH.Msg("Please set a recruitment message first.")
    return
  end
  
  local selectedChannel = OGRH_SV.recruitment.selectedChannel
  if not selectedChannel then
    OGRH.Msg("No channel selected for recruitment advertising.")
    return
  end
  
  OGRH_SV.recruitment.isRecruiting = true
  
  -- Send first ad immediately
  OGRH.SendRecruitmentAd()
  
  -- Show recruiting panel
  OGRH.ShowRecruitingPanel()
  
  -- Update button text in window if open
  OGRH.UpdateRecruitmentButton()
  
  OGRH.Msg("Started recruiting. Ads will be sent every " .. math.floor(OGRH_SV.recruitment.interval / 60) .. " minutes.")
end

-- Stop recruiting
function OGRH.StopRecruiting()
  OGRH.EnsureRecruitmentSV()
  
  OGRH_SV.recruitment.isRecruiting = false
  
  -- Hide recruiting panel
  OGRH.HideRecruitingPanel()
  
  -- Update button text in window if open
  OGRH.UpdateRecruitmentButton()
  
  OGRH.Msg("Stopped recruiting.")
end

-- Update recruitment button text if window is open
function OGRH.UpdateRecruitmentButton()
  -- Check if window exists and has the button
  if not recruitmentFrame then
    return
  end
  
  -- If window is not visible, no need to update
  if not recruitmentFrame:IsVisible() then
    return
  end
  
  -- Find the button
  local btn = recruitmentFrame.detailPanel and recruitmentFrame.detailPanel.recruitBtn
  if btn then
    btn:SetText(OGRH_SV.recruitment.isRecruiting and "Stop Recruiting" or "Start Recruiting")
  end
end

-- ========================================
-- CLASS COLOR DETECTION
-- ========================================

local whoQueue = {}
local whoThrottle = 0

-- Get class color for a player name
function OGRH.GetRecruitmentPlayerClass(name)
  OGRH.EnsureRecruitmentSV()
  
  -- Check pfUI database first if available
  if pfUI_playerDB and pfUI_playerDB[name] and pfUI_playerDB[name].class then
    local class = pfUI_playerDB[name].class
    if RAID_CLASS_COLORS[class] then
      return RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, class
    end
  end
  
  -- Check our cache
  if OGRH_SV.recruitment.playerCache[name] and OGRH_SV.recruitment.playerCache[name].class then
    local class = OGRH_SV.recruitment.playerCache[name].class
    if RAID_CLASS_COLORS[class] then
      return RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, class
    end
  end
  
  -- Queue for WHO query if not recently queried
  if not whoQueue[name] then
    whoQueue[name] = GetTime()
  end
  
  return 1, 1, 1, nil
end

-- Process WHO queue
local function ProcessWhoQueue()
  if GetTime() - whoThrottle < 2 then return end -- Throttle WHO queries
  
  for name, queueTime in pairs(whoQueue) do
    if GetTime() - queueTime > 1 then -- Wait 1 second before querying
      SendWho(name)
      whoQueue[name] = nil
      whoThrottle = GetTime()
      return -- Only one query at a time
    end
  end
end

-- Update player cache from WHO results
local function UpdatePlayerCache()
  OGRH.EnsureRecruitmentSV()
  
  for i = 1, GetNumWhoResults() do
    local name, guild, level, _, class = GetWhoInfo(i)
    if name and class then
      OGRH_SV.recruitment.playerCache[name] = {
        class = class,
        level = level,
        guild = guild
      }
    end
  end
  
  -- Refresh UI if recruitment window is open
  if recruitmentFrame and recruitmentFrame:IsVisible() and recruitmentFrame.PopulateLeftList then
    recruitmentFrame.PopulateLeftList()
  end
end

-- ========================================
-- CONTACT TRACKING
-- ========================================

-- Show chat view for a specific contact
function OGRH.ShowRecruitmentChatView(frame, contactName)
  local detailPanel = frame.detailPanel
  
  -- Clear existing content
  if detailPanel.content then
    for _, child in ipairs(detailPanel.content) do
      child:Hide()
      child:SetParent(nil)
    end
  end
  detailPanel.content = {}
  
  frame.currentView = "chat"
  frame.selectedContact = contactName
  
  -- Title
  local title = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 10, -10)
  title:SetText("Chat with " .. contactName)
  table.insert(detailPanel.content, title)
  
  -- Chat interface
  local chatBg = CreateFrame("Frame", nil, detailPanel)
  chatBg:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  chatBg:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", -10, 10)
  chatBg:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  chatBg:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  chatBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  table.insert(detailPanel.content, chatBg)
  
  -- Chat history display
  local chatHistory = chatBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  chatHistory:SetPoint("TOPLEFT", chatBg, "TOPLEFT", 8, -8)
  chatHistory:SetPoint("BOTTOMRIGHT", chatBg, "BOTTOMRIGHT", -8, 40)
  chatHistory:SetJustifyH("LEFT")
  chatHistory:SetJustifyV("TOP")
  chatBg.chatHistory = chatHistory
  
  -- Reply input box
  local replyBox = CreateFrame("EditBox", nil, chatBg)
  replyBox:SetPoint("BOTTOMLEFT", chatBg, "BOTTOMLEFT", 8, 8)
  replyBox:SetPoint("BOTTOMRIGHT", chatBg, "BOTTOMRIGHT", -8, 8)
  replyBox:SetHeight(24)
  replyBox:SetAutoFocus(false)
  replyBox:SetFontObject(GameFontHighlight)
  replyBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  replyBox:SetBackdropColor(0, 0, 0, 0.5)
  replyBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  replyBox:SetTextInsets(5, 5, 0, 0)
  replyBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  replyBox:SetScript("OnEnterPressed", function()
    local text = this:GetText()
    if text and text ~= "" and contactName then
      SendChatMessage(text, "WHISPER", nil, contactName)
      this:SetText("")
      this:ClearFocus()
    end
  end)
  
  -- Load and display chat history
  OGRH.ShowContactChat(chatBg, contactName)
end

-- Display chat history for a contact
function OGRH.ShowContactChat(chatBg, contactName)
  OGRH.EnsureRecruitmentSV()
  local history = OGRH_SV.recruitment.whisperHistory[contactName]
  
  if not history or not history.messages then
    chatBg.chatHistory:SetText("|cff888888No messages with " .. contactName .. "|r")
    return
  end
  
  local lines = {}
  for _, msg in ipairs(history.messages) do
    local timestamp = date("%Y-%m-%d %H:%M", msg.timestamp)
    local color = msg.incoming and "|cff00ff00" or "|cff00aaff"
    local fromChar = msg.fromCharacter or (msg.incoming and contactName or "Unknown")
    
    -- Get class color for the character name
    local r, g, b, class = OGRH.GetRecruitmentPlayerClass(fromChar)
    local classColorHex = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local prefix = "[" .. classColorHex .. fromChar .. "|r] "
    table.insert(lines, color .. timestamp .. " " .. prefix .. msg.text .. "|r")
  end
  
  chatBg.chatHistory:SetText(table.concat(lines, "\n"))
end

-- Track incoming/outgoing whispers
function OGRH.TrackWhisper(sender, message, incoming)
  OGRH.EnsureRecruitmentSV()
  
  -- Don't track if this contact was explicitly deleted
  if OGRH_SV.recruitment.deletedContacts[sender] then
    return
  end
  
  -- Only track whispers if:
  -- 1. Currently recruiting, OR
  -- 2. This contact already exists in history (has not been deleted)
  local contactExists = OGRH_SV.recruitment.whisperHistory[sender] ~= nil
  local isRecruiting = OGRH_SV.recruitment.isRecruiting
  
  if not isRecruiting and not contactExists then
    -- Don't track this whisper
    return
  end
  
  if not OGRH_SV.recruitment.whisperHistory[sender] then
    OGRH_SV.recruitment.whisperHistory[sender] = {
      messages = {},
      lastContact = time()
    }
  end
  
  local history = OGRH_SV.recruitment.whisperHistory[sender]
  local myCharacter = UnitName("player")
  table.insert(history.messages, {
    text = message,
    timestamp = time(),
    incoming = incoming,
    myCharacter = myCharacter,
    fromCharacter = incoming and sender or myCharacter,
    toCharacter = incoming and myCharacter or sender
  })
  history.lastContact = time()
  
  -- Always refresh left list if window is open (use scheduled update to avoid spam)
  if recruitmentFrame and recruitmentFrame:IsVisible() then
    -- Schedule a refresh in 0.5 seconds to batch multiple whispers
    if not recruitmentFrame.refreshScheduled then
      recruitmentFrame.refreshScheduled = true
      recruitmentFrame.refreshTime = GetTime() + 0.5
    end
    
    -- If currently viewing this contact's chat, refresh the chat display immediately
    if recruitmentFrame.currentView == "chat" and recruitmentFrame.selectedContact == sender then
      if recruitmentFrame.detailPanel and recruitmentFrame.detailPanel.content then
        -- Find the chatBg frame and update it
        for _, child in ipairs(recruitmentFrame.detailPanel.content) do
          if child.chatHistory then
            OGRH.ShowContactChat(child, sender)
            break
          end
        end
      end
    end
  end
end

-- ========================================
-- MODULE INITIALIZATION
-- ========================================

-- Initialize on load
OGRH.EnsureRecruitmentSV()

-- Register event handler for ADDON_LOADED and whisper tracking
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("CHAT_MSG_WHISPER")
initFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
initFrame:RegisterEvent("WHO_LIST_UPDATE")
initFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
    OGRH.EnsureRecruitmentSV()
    -- If we were recruiting when we reloaded, show the panel
    if OGRH_SV.recruitment.isRecruiting then
      OGRH.ShowRecruitingPanel()
    end
  elseif event == "CHAT_MSG_WHISPER" then
    -- Incoming whisper
    local message = arg1
    local sender = arg2
    OGRH.TrackWhisper(sender, message, true)
  elseif event == "CHAT_MSG_WHISPER_INFORM" then
    -- Outgoing whisper
    local message = arg1
    local recipient = arg2
    OGRH.TrackWhisper(recipient, message, false)
  elseif event == "WHO_LIST_UPDATE" then
    UpdatePlayerCache()
  end
end)

-- OnUpdate for WHO queue processing
initFrame:SetScript("OnUpdate", function()
  ProcessWhoQueue()
end)
