-- OGST_Test.lua - Test file for OGST Auxiliary Panel Positioning
-- Run with: /script OGST_Test.Show()

OGST_Test = OGST_Test or {}

function OGST_Test.Show()
  -- Create main window if it doesn't exist
  if not OGST_Test.mainWindow then
    local window = OGST.CreateStandardWindow({
      name = "OGST_TestWindow",
      width = 300,
      height = 200,
      title = "OGST Panel Test",
      closeButton = true,
      escapeCloses = true,
      closeOnNewWindow = false
    })
    
    window:SetPoint("CENTER", UIParent, "CENTER")
    
    -- Create test panels
    OGST_Test.topPanel = OGST_Test.CreateTestPanel("TOP", {r=1, g=0, b=0})
    OGST_Test.bottomPanel = OGST_Test.CreateTestPanel("BOTTOM", {r=0, g=1, b=0})
    OGST_Test.leftPanel = OGST_Test.CreateTestPanel("LEFT", {r=0, g=0, b=1})
    OGST_Test.rightPanel = OGST_Test.CreateTestPanel("RIGHT", {r=1, g=1, b=0})
    
    -- Register panels
    OGST.RegisterAuxiliaryPanel(OGST_Test.topPanel, {
      parentFrame = window,
      side = "top",
      priority = 1,
      autoMove = true,
      hideInCombat = false
    })
    
    OGST.RegisterAuxiliaryPanel(OGST_Test.bottomPanel, {
      parentFrame = window,
      side = "bottom",
      priority = 1,
      autoMove = true,
      hideInCombat = false
    })
    
    OGST.RegisterAuxiliaryPanel(OGST_Test.leftPanel, {
      parentFrame = window,
      side = "left",
      priority = 1,
      autoMove = true,
      hideInCombat = false
    })
    
    OGST.RegisterAuxiliaryPanel(OGST_Test.rightPanel, {
      parentFrame = window,
      side = "right",
      priority = 1,
      autoMove = true,
      hideInCombat = false
    })
    
    -- Create checkboxes for toggling autoMove
    local verticalCheckbox = CreateFrame("CheckButton", nil, window.contentFrame, "UICheckButtonTemplate")
    verticalCheckbox:SetWidth(24)
    verticalCheckbox:SetHeight(24)
    verticalCheckbox:SetPoint("TOPLEFT", window.contentFrame, "TOPLEFT", 10, -20)
    verticalCheckbox:SetChecked(true)
    
    local verticalLabel = verticalCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    verticalLabel:SetPoint("LEFT", verticalCheckbox, "RIGHT", 5, 0)
    verticalLabel:SetText("Auto-move Vertical (Top/Bottom)")
    
    verticalCheckbox:SetScript("OnClick", function()
      local enabled = this:GetChecked()
      OGST.RegisterAuxiliaryPanel(OGST_Test.topPanel, {
        parentFrame = window,
        side = "top",
        priority = 1,
        autoMove = enabled,
        hideInCombat = false
      })
      OGST.RegisterAuxiliaryPanel(OGST_Test.bottomPanel, {
        parentFrame = window,
        side = "bottom",
        priority = 1,
        autoMove = enabled,
        hideInCombat = false
      })
    end)
    
    local horizontalCheckbox = CreateFrame("CheckButton", nil, window.contentFrame, "UICheckButtonTemplate")
    horizontalCheckbox:SetWidth(24)
    horizontalCheckbox:SetHeight(24)
    horizontalCheckbox:SetPoint("TOPLEFT", verticalCheckbox, "BOTTOMLEFT", 0, -10)
    horizontalCheckbox:SetChecked(true)
    
    local horizontalLabel = horizontalCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    horizontalLabel:SetPoint("LEFT", horizontalCheckbox, "RIGHT", 5, 0)
    horizontalLabel:SetText("Auto-move Horizontal (Left/Right)")
    
    horizontalCheckbox:SetScript("OnClick", function()
      local enabled = this:GetChecked()
      OGST.RegisterAuxiliaryPanel(OGST_Test.leftPanel, {
        parentFrame = window,
        side = "left",
        priority = 1,
        autoMove = enabled,
        hideInCombat = false
      })
      OGST.RegisterAuxiliaryPanel(OGST_Test.rightPanel, {
        parentFrame = window,
        side = "right",
        priority = 1,
        autoMove = enabled,
        hideInCombat = false
      })
    end)
    
    -- Add instruction text
    local instructions = window.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", horizontalCheckbox, "BOTTOMLEFT", 0, -20)
    instructions:SetPoint("RIGHT", window.contentFrame, "RIGHT", -10, 0)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("Drag the main window to see panels follow. Uncheck to disable auto-positioning.")
    instructions:SetTextColor(0.7, 0.7, 0.7)
    
    OGST_Test.mainWindow = window
    
    -- Show all panels
    OGST_Test.topPanel:Show()
    OGST_Test.bottomPanel:Show()
    OGST_Test.leftPanel:Show()
    OGST_Test.rightPanel:Show()
  end
  
  OGST_Test.mainWindow:Show()
end

function OGST_Test.CreateTestPanel(label, color)
  local panel = CreateFrame("Frame", nil, UIParent)
  panel:SetWidth(50)
  panel:SetHeight(50)
  panel:SetFrameStrata("MEDIUM")
  
  -- Background
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(panel)
  bg:SetTexture(0, 0, 0, 0.8)
  
  -- Border
  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture(color.r, color.g, color.b, 1)
  border:SetVertexColor(color.r, color.g, color.b, 1)
  
  -- Inset the background slightly to show border
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
  
  -- Label
  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER")
  text:SetText(label)
  text:SetTextColor(1, 1, 1)
  
  return panel
end

-- Auto-show on load for testing
DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGST Test:|r Type /script OGST_Test.Show() to test auxiliary panels")
