-- OGST_Sample.lua - Sample implementation for OGST Docked Panel Positioning
-- Run with: /ogst

OGST_Sample = OGST_Sample or {}

function OGST_Sample.Show()
  -- Create main window if it doesn't exist
  if not OGST_Sample.mainWindow then
    local window = OGST.CreateStandardWindow({
      name = "OGST_SampleWindow",
      width = 400,
      height = 200,
      title = "Window Title",
      closeButton = true,
      escapeCloses = true,
      closeOnNewWindow = false,
      resizable = true,
      minWidth = 400,
      minHeight = 200
    })
    
    window:SetPoint("CENTER", UIParent, "CENTER")
    
    -- Initialize panel counts
    OGST_Sample.horizontalPanelCount = 1
    OGST_Sample.verticalPanelCount = 1
    OGST_Sample.dockedPanels = {}
    
    -- Create side-by-side content panels that fill the window
    -- Left panel: fixed 200px width, fills height
    local leftPanel = OGST.CreateContentPanel(window.contentFrame, {
      width = 200,
      height = 100
    })
    OGST.AnchorElement(leftPanel, window.contentFrame, { fillHeight = true, align = "left" })
    
    -- Right panel: fills remaining space
    local rightPanel = OGST.CreateContentPanel(window.contentFrame, {
      width = 160,
      height = 100
    })
    OGST.AnchorElement(rightPanel, leftPanel, { position = "right", fill = true })
    -- Anchor right edge to parent to fill remaining space
    rightPanel:SetPoint("RIGHT", window.contentFrame, "RIGHT", 0, 0)
    
    -- Add Sample Dialog button to right panel
    local dialogBtnContainer = CreateFrame("Frame", nil, rightPanel)
    dialogBtnContainer:SetWidth(140)  -- Fixed width
    dialogBtnContainer:SetHeight(24)
    OGST.AnchorElement(dialogBtnContainer, rightPanel, { position = "top", align = "left" })
    
    local dialogBtn = CreateFrame("Button", nil, dialogBtnContainer)
    dialogBtn:SetAllPoints(dialogBtnContainer)
    
    local dialogBtnText = dialogBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialogBtnText:SetPoint("CENTER", dialogBtn, "CENTER", 0, 0)
    dialogBtnText:SetText("Sample Dialog")
    dialogBtnText:SetTextColor(1, 0.82, 0, 1)  -- Gold text (OGST standard)
    
    OGST.StyleButton(dialogBtn)
    
    dialogBtn:SetScript("OnClick", function()
      -- Create and show sample dialog
      local dialogData = OGST.CreateDialog({
        title = "Sample Dialog",
        width = 450,
        height = 250,
        content = "This is a sample dialog demonstrating OGST.CreateDialog().\n\nThe dialog supports:\n- Modal backdrop (dims background)\n- Configurable title\n- Content frame for custom UI\n- Multiple buttons with callbacks\n- ESC key closes dialog",
        buttons = {
          {text = "OK", onClick = function()
            DEFAULT_CHAT_FRAME:AddMessage("Sample Dialog: OK clicked")
          end},
          {text = "Cancel", onClick = function()
            DEFAULT_CHAT_FRAME:AddMessage("Sample Dialog: Cancel clicked")
          end}
        },
        onClose = function()
          DEFAULT_CHAT_FRAME:AddMessage("Sample Dialog closed")
        end
      })
      
      -- Show the dialog
      dialogData.backdrop:Show()
    end)
    
    window.dialogBtnContainer = dialogBtnContainer
    
    -- Add Static Text samples to right panel
    
    -- Single-line static text (label)
    local singleLineText = OGST.CreateStaticText(rightPanel, {
      text = "Single Line Label",
      font = "GameFontNormalLarge",
      color = {r = 1, g = 0.82, b = 0, a = 1},  -- Gold
      align = "LEFT"
    })
    
    OGST.AnchorElement(singleLineText, dialogBtnContainer, { position = "below", fillToParent = true })
    window.singleLineText = singleLineText
    
    -- Single-line centered text
    local centeredText = OGST.CreateStaticText(rightPanel, {
      text = "Centered Text",
      font = "GameFontNormal",
      color = {r = 0.5, g = 1, b = 0.5, a = 1},  -- Light green
      align = "CENTER"
    })
    
    OGST.AnchorElement(centeredText, singleLineText, { position = "below", fill = true })
    window.centeredText = centeredText
    
    -- Multi-line static text
    local multiLineText = OGST.CreateStaticText(rightPanel, {
      text = "This is a multi-line text demonstration. It will wrap automatically to fit the specified width.",
      font = "GameFontNormalSmall",
      color = {r = 1, g = 1, b = 1, a = 1},  -- White
      align = "LEFT",
      multiline = true
      -- No fixed width - will fill parent when anchored with fill=true
    })
    
    OGST.AnchorElement(multiLineText, centeredText, { position = "below", fill = true })
    window.multiLineText = multiLineText
    
    -- Initialize settings
    OGST_Sample.horizontalAlignment = "left"
    OGST_Sample.verticalAlignment = "bottom"
    
    -- Add alignment menu button (inside left panel)
    local alignmentMenuItems = {
      {text = "Anchor Left", selected = true, onClick = function()
        OGST_Sample.horizontalAlignment = "left"
        OGST_Sample.CreateDockedPanels(window)
        DEFAULT_CHAT_FRAME:AddMessage("Horizontal panels anchor: LEFT")
      end},
      {text = "Anchor Right", selected = false, onClick = function()
        OGST_Sample.horizontalAlignment = "right"
        OGST_Sample.CreateDockedPanels(window)
        DEFAULT_CHAT_FRAME:AddMessage("Horizontal panels anchor: RIGHT")
      end},
      {text = "Anchor Bottom", selected = true, onClick = function()
        OGST_Sample.verticalAlignment = "bottom"
        OGST_Sample.CreateDockedPanels(window)
        DEFAULT_CHAT_FRAME:AddMessage("Vertical panels anchor: BOTTOM")
      end},
      {text = "Anchor Top", selected = false, onClick = function()
        OGST_Sample.verticalAlignment = "top"
        OGST_Sample.CreateDockedPanels(window)
        DEFAULT_CHAT_FRAME:AddMessage("Vertical panels anchor: TOP")
      end}
    }
    
    local alignContainer, alignButton, alignMenu, alignLabel = OGST.CreateMenuButton(leftPanel, {
      label = "Alignment",
      labelAnchor = "LEFT",
      labelWidth = 100,
      buttonText = "Select...",
      buttonWidth = 85,
      menuItems = alignmentMenuItems
    })
    OGST.AnchorElement(alignContainer, leftPanel, { position = "top", align = "left" })
    
    -- Store reference for design mode toggle
    window.alignContainer = alignContainer
    
    -- Add horizontal panel count text box (inside left panel)
    local hContainer, hBackdrop, hEditBox, hLabel = OGST.CreateSingleLineTextBox(leftPanel, 80, 24, {
      align = "CENTER",
      numeric = true,
      label = "Horizontal Panels",
      labelAnchor = "LEFT",
      labelWidth = 100,
      textBoxWidth = "Fill",
      onChange = function(text)
        -- Validate on change but don't update yet
      end,
      onEnter = function(text)
        OGST_Sample.UpdateHorizontalPanels(tonumber(text) or 1)
      end
    })
    OGST.AnchorElement(hContainer, alignContainer, { position = "below", fill = true })
    hEditBox:SetText("1")
    hEditBox:SetScript("OnEditFocusLost", function()
      local value = tonumber(hEditBox:GetText()) or 1
      if value < 1 then value = 1 end
      hEditBox:SetText(tostring(value))
      OGST_Sample.UpdateHorizontalPanels(value)
    end)
    
    -- Store reference for design mode toggle
    window.hContainer = hContainer
    
    -- Add vertical panel count text box (inside left panel)
    local vContainer, vBackdrop, vEditBox, vLabel = OGST.CreateSingleLineTextBox(leftPanel, 80, 24, {
      align = "CENTER",
      numeric = true,
      label = "Vertical Panels",
      labelAnchor = "LEFT",
      labelWidth = 100,
      textBoxWidth = "Fill",
      onChange = function(text)
        -- Validate on change but don't update yet
      end,
      onEnter = function(text)
        OGST_Sample.UpdateVerticalPanels(tonumber(text) or 1)
      end
    })
    OGST.AnchorElement(vContainer, hContainer, { position = "below", fill = true })
    vEditBox:SetText("1")
    vEditBox:SetScript("OnEditFocusLost", function()
      local value = tonumber(vEditBox:GetText()) or 1
      if value < 1 then value = 1 end
      vEditBox:SetText(tostring(value))
      OGST_Sample.UpdateVerticalPanels(value)
    end)
    
    -- Store reference for design mode toggle
    window.vContainer = vContainer
    vEditBox:SetText("1")
    vEditBox:SetScript("OnEditFocusLost", function()
      local value = tonumber(vEditBox:GetText()) or 1
      if value < 1 then value = 1 end
      vEditBox:SetText(tostring(value))
      OGST_Sample.UpdateVerticalPanels(value)
    end)
    
    -- Store reference for design mode toggle
    window.vContainer = vContainer
    
    -- Add checkbox demo (inside left panel)
    local checkContainer, checkButton, checkLabel = OGST.CreateCheckbox(leftPanel, {
      label = "Auto Move Panels",
      labelAnchor = "RIGHT",
      labelWidth = 100,
      checked = true,
      onChange = function(isChecked)
        DEFAULT_CHAT_FRAME:AddMessage("Auto Move: " .. (isChecked and "ON" or "OFF"))
        OGST_Sample.autoMove = isChecked
        if OGST_Sample.dockedPanels then
          for _, panel in ipairs(OGST_Sample.dockedPanels) do
            -- Update auto move setting for existing panels
            for _, panelData in ipairs(OGST.DockedPanels.panels) do
              if panelData.frame == panel then
                panelData.autoMove = isChecked
                break
              end
            end
          end
        end
      end
    })
    OGST.AnchorElement(checkContainer, vContainer, { position = "below", fill = true })
    
    -- Store reference for design mode toggle
    window.checkContainer = checkContainer
    
    -- Add another checkbox with label on left
    local checkContainer2, checkButton2, checkLabel2 = OGST.CreateCheckbox(leftPanel, {
      label = "Hide in Combat",
      labelAnchor = "RIGHT",
      labelWidth = 100,
      checked = false,
      onChange = function(isChecked)
        DEFAULT_CHAT_FRAME:AddMessage("Hide in Combat: " .. (isChecked and "ON" or "OFF"))
        OGST_Sample.hideInCombat = isChecked
        if OGST_Sample.dockedPanels then
          for _, panel in ipairs(OGST_Sample.dockedPanels) do
            -- Update hide in combat setting
            for _, panelData in ipairs(OGST.DockedPanels.panels) do
              if panelData.frame == panel then
                panelData.hideInCombat = isChecked
                break
              end
            end
          end
        end
      end
    })
    OGST.AnchorElement(checkContainer2, checkContainer, { position = "below", fill = true })
    
    -- Store reference for design mode toggle
    window.checkContainer2 = checkContainer2
    
    -- Initialize settings
    OGST_Sample.autoMove = true
    OGST_Sample.hideInCombat = false
    
    -- Create initial docked panels
    OGST_Sample.CreateDockedPanels(window)
    
    OGST_Sample.mainWindow = window
  end
  
  OGST_Sample.mainWindow:Show()
end

function OGST_Sample.ClearDockedPanels()
  if OGST_Sample.dockedPanels then
    for _, panel in ipairs(OGST_Sample.dockedPanels) do
      OGST.UnregisterDockedPanel(panel)
      panel:Hide()
      panel:SetParent(nil)
    end
  end
  OGST_Sample.dockedPanels = {}
end

function OGST_Sample.CreateDockedPanels(window)
  OGST_Sample.ClearDockedPanels()
  
  local panelWidth = window:GetWidth()
  local panelHeight = 40
  
  local colors = {
    {r=1, g=0, b=0},     -- Red
    {r=0, g=1, b=0},     -- Green
    {r=0, g=0, b=1},     -- Blue
    {r=1, g=1, b=0},     -- Yellow
    {r=1, g=0, b=1},     -- Magenta
    {r=0, g=1, b=1},     -- Cyan
  }
  
  local sides = {"bottom", "top", "left", "right"}
  local panelIndex = 1
  
  -- Create horizontal panels (left/right)
  for i = 1, OGST_Sample.horizontalPanelCount do
    local colorIndex = math.mod(panelIndex - 1, table.getn(colors)) + 1
    local color = colors[colorIndex]
    
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(50)  -- Explicit width for horizontal panels
    
    OGST.RegisterDockedPanel(panel, {
      parentFrame = window,
      axis = "horizontal",
      preferredSide = OGST_Sample.horizontalAlignment or "left",
      priority = i,
      autoMove = OGST_Sample.autoMove,
      hideInCombat = OGST_Sample.hideInCombat,
      title = "Horizontal " .. i
    })
    
    panel:Show()
    table.insert(OGST_Sample.dockedPanels, panel)
    panelIndex = panelIndex + 1
  end
  
  -- Create vertical panels (top/bottom)
  for i = 1, OGST_Sample.verticalPanelCount do
    local colorIndex = math.mod(panelIndex - 1, table.getn(colors)) + 1
    local color = colors[colorIndex]
    
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetHeight(50)  -- Explicit height for vertical panels
    
    OGST.RegisterDockedPanel(panel, {
      parentFrame = window,
      axis = "vertical",
      preferredSide = OGST_Sample.verticalAlignment or "bottom",
      priority = i,
      autoMove = OGST_Sample.autoMove,
      hideInCombat = OGST_Sample.hideInCombat,
      title = "Vertical " .. i
    })
    
    panel:Show()
    table.insert(OGST_Sample.dockedPanels, panel)
    panelIndex = panelIndex + 1
  end
end

function OGST_Sample.UpdateHorizontalPanels(count)
  if count < 1 then count = 1 end
  OGST_Sample.horizontalPanelCount = count
  if OGST_Sample.mainWindow then
    OGST_Sample.CreateDockedPanels(OGST_Sample.mainWindow)
  end
end

function OGST_Sample.UpdateVerticalPanels(count)
  if count < 1 then count = 1 end
  OGST_Sample.verticalPanelCount = count
  if OGST_Sample.mainWindow then
    OGST_Sample.CreateDockedPanels(OGST_Sample.mainWindow)
  end
end

-- UI Spy function
function OGST_Sample.SpyUI()
  -- Create spy window if it doesn't exist
  if not OGST_Sample.spyWindow then
    local spy = OGST.CreateStandardWindow({
      name = "OGST_SpyWindow",
      width = 350,
      height = 220,
      title = "UI Spy",
      closeButton = true,
      escapeCloses = true,
      closeOnNewWindow = false,
      minWidth = 350,
      minHeight = 220
    })
    
    spy:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    
    -- Create text labels
    local yOffset = -10
    local lineHeight = 18
    
    spy.nameLabel = spy.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spy.nameLabel:SetPoint("TOPLEFT", spy.contentFrame, "TOPLEFT", 5, yOffset)
    spy.nameLabel:SetJustifyH("LEFT")
    spy.nameLabel:SetWidth(320)
    yOffset = yOffset - lineHeight
    
    spy.typeLabel = spy.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spy.typeLabel:SetPoint("TOPLEFT", spy.contentFrame, "TOPLEFT", 5, yOffset)
    spy.typeLabel:SetJustifyH("LEFT")
    spy.typeLabel:SetWidth(320)
    yOffset = yOffset - lineHeight
    
    spy.textureLabel = spy.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spy.textureLabel:SetPoint("TOPLEFT", spy.contentFrame, "TOPLEFT", 5, yOffset)
    spy.textureLabel:SetJustifyH("LEFT")
    spy.textureLabel:SetWidth(320)
    yOffset = yOffset - lineHeight
    
    spy.normalTexLabel = spy.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spy.normalTexLabel:SetPoint("TOPLEFT", spy.contentFrame, "TOPLEFT", 5, yOffset)
    spy.normalTexLabel:SetJustifyH("LEFT")
    spy.normalTexLabel:SetWidth(320)
    yOffset = yOffset - lineHeight
    
    spy.highlightTexLabel = spy.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spy.highlightTexLabel:SetPoint("TOPLEFT", spy.contentFrame, "TOPLEFT", 5, yOffset)
    spy.highlightTexLabel:SetJustifyH("LEFT")
    spy.highlightTexLabel:SetWidth(320)
    yOffset = yOffset - lineHeight
    
    spy.sizeLabel = spy.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spy.sizeLabel:SetPoint("TOPLEFT", spy.contentFrame, "TOPLEFT", 5, yOffset)
    spy.sizeLabel:SetJustifyH("LEFT")
    spy.sizeLabel:SetWidth(320)
    yOffset = yOffset - lineHeight
    
    spy.parentLabel = spy.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spy.parentLabel:SetPoint("TOPLEFT", spy.contentFrame, "TOPLEFT", 5, yOffset)
    spy.parentLabel:SetJustifyH("LEFT")
    spy.parentLabel:SetWidth(320)
    
    -- Update on every frame
    spy:SetScript("OnUpdate", function()
      local f = GetMouseFocus()
      if not f then
        this.nameLabel:SetText("|cffffcc00Name:|r N/A")
        this.typeLabel:SetText("|cffffcc00Type:|r N/A")
        this.textureLabel:SetText("")
        this.normalTexLabel:SetText("")
        this.highlightTexLabel:SetText("")
        this.sizeLabel:SetText("")
        this.parentLabel:SetText("")
        return
      end
      
      local name = f:GetName() or "Anonymous"
      local objType = f:GetObjectType()
      
      this.nameLabel:SetText("|cffffcc00Name:|r " .. name)
      this.typeLabel:SetText("|cffffcc00Type:|r " .. objType)
      
      -- Texture
      if objType == "Texture" then
        local tex = f:GetTexture()
        this.textureLabel:SetText("|cffffcc00Texture:|r " .. (tex or "none"))
      else
        this.textureLabel:SetText("")
      end
      
      -- Normal texture
      if f.GetNormalTexture then
        local nt = f:GetNormalTexture()
        if nt and nt:GetTexture() then
          this.normalTexLabel:SetText("|cffffcc00NormalTex:|r " .. nt:GetTexture())
        else
          this.normalTexLabel:SetText("")
        end
      else
        this.normalTexLabel:SetText("")
      end
      
      -- Highlight texture
      if f.GetHighlightTexture then
        local ht = f:GetHighlightTexture()
        if ht and ht:GetTexture() then
          this.highlightTexLabel:SetText("|cffffcc00HighlightTex:|r " .. ht:GetTexture())
        else
          this.highlightTexLabel:SetText("")
        end
      else
        this.highlightTexLabel:SetText("")
      end
      
      -- Size
      if f.GetWidth and f.GetHeight then
        local w = math.floor(f:GetWidth() + 0.5)
        local h = math.floor(f:GetHeight() + 0.5)
        this.sizeLabel:SetText("|cffffcc00Size:|r " .. w .. " x " .. h)
      else
        this.sizeLabel:SetText("")
      end
      
      -- Parent
      local parent = f:GetParent()
      if parent then
        local parentName = parent:GetName() or "Anonymous"
        this.parentLabel:SetText("|cffffcc00Parent:|r " .. parentName)
      else
        this.parentLabel:SetText("")
      end
    end)
    
    OGST_Sample.spyWindow = spy
  end
  
  OGST_Sample.spyWindow:Show()
end

-- Slash command handler
SlashCmdList["OGST"] = function(msg)
  if msg == "spy" then
    OGST_Sample.SpyUI()
  elseif msg == "design" then
    -- Use library function to toggle design mode
    OGST.ToggleDesignMode()
    
    -- Update tooltips helper
    local function updateTooltips(frame, name, frameType)
      if OGST.DESIGN_MODE then
        OGST.AddDesignTooltip(frame, name, frameType)
      else
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
      end
    end
    
    -- Update sample-specific components that aren't part of standard windows
    -- Update sample-specific components that aren't part of standard windows
    if OGST_Sample.mainWindow then
      -- Toggle textbox containers
      if OGST_Sample.mainWindow.hContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.hContainer:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
          })
          OGST_Sample.mainWindow.hContainer:SetBackdropBorderColor(1, 1, 0, 1)
        else
          OGST_Sample.mainWindow.hContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.hContainer, "Horizontal Panels", "Frame")
      end
      
      if OGST_Sample.mainWindow.vContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.vContainer:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
          })
          OGST_Sample.mainWindow.vContainer:SetBackdropBorderColor(1, 1, 0, 1)
        else
          OGST_Sample.mainWindow.vContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.vContainer, "Vertical Panels", "Frame")
      end
      
      -- Toggle checkbox containers
      if OGST_Sample.mainWindow.checkContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.checkContainer:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
          })
          OGST_Sample.mainWindow.checkContainer:SetBackdropBorderColor(1, 0.5, 0, 1)
        else
          OGST_Sample.mainWindow.checkContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.checkContainer, "Auto Move Panels", "Frame")
      end
      
      if OGST_Sample.mainWindow.checkContainer2 then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.checkContainer2:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
          })
          OGST_Sample.mainWindow.checkContainer2:SetBackdropBorderColor(1, 0.5, 0, 1)
        else
          OGST_Sample.mainWindow.checkContainer2:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.checkContainer2, "Hide in Combat", "Frame")
      end
      
      -- Toggle menu button container
      if OGST_Sample.mainWindow.alignContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.alignContainer:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
          })
          OGST_Sample.mainWindow.alignContainer:SetBackdropBorderColor(0, 1, 1, 1)
        else
          OGST_Sample.mainWindow.alignContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.alignContainer, "Alignment", "Frame")
      end
      
      -- Toggle dialog button container
      if OGST_Sample.mainWindow.dialogBtnContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.dialogBtnContainer:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
          })
          OGST_Sample.mainWindow.dialogBtnContainer:SetBackdropBorderColor(0.5, 0.5, 1, 1)
        else
          OGST_Sample.mainWindow.dialogBtnContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.dialogBtnContainer, "Sample Dialog Button", "Button")
      end
      
      -- Toggle single line text container
      if OGST_Sample.mainWindow.singleLineContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.singleLineContainer:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
          })
          OGST_Sample.mainWindow.singleLineContainer:SetBackdropColor(0, 0, 0, 0)
          OGST_Sample.mainWindow.singleLineContainer:SetBackdropBorderColor(1, 0, 1, 1)
        else
          OGST_Sample.mainWindow.singleLineContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.singleLineContainer, "Single Line Static Text", "FontString")
      end
      
      -- Toggle centered text container
      if OGST_Sample.mainWindow.centeredContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.centeredContainer:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
          })
          OGST_Sample.mainWindow.centeredContainer:SetBackdropColor(0, 0, 0, 0)
          OGST_Sample.mainWindow.centeredContainer:SetBackdropBorderColor(1, 0, 1, 1)
        else
          OGST_Sample.mainWindow.centeredContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.centeredContainer, "Centered Static Text", "FontString")
      end
      
      -- Toggle multi-line text container
      if OGST_Sample.mainWindow.multiLineContainer then
        if OGST.DESIGN_MODE then
          OGST_Sample.mainWindow.multiLineContainer:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
          })
          OGST_Sample.mainWindow.multiLineContainer:SetBackdropColor(0, 0, 0, 0)
          OGST_Sample.mainWindow.multiLineContainer:SetBackdropBorderColor(1, 0, 1, 1)
        else
          OGST_Sample.mainWindow.multiLineContainer:SetBackdrop(nil)
        end
        updateTooltips(OGST_Sample.mainWindow.multiLineContainer, "Multi-line Static Text", "FontString")
      end
    end
  else
    OGST_Sample.Show()
  end
end
SLASH_OGST1 = "/ogst"

-- Load message
DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGST Sample:|r Type /ogst to test docked panel positioning or /ogst spy to inspect UI elements")
