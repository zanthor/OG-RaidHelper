--[[
  C'Thun Encounter Module
  Manually loaded via Custom Module role selection
  Displays the BigWigs C'Thun map with custom numbered texture
]]--

local module = {}

-- Module metadata
module.id = "cthun"
module.name = "C'Thun"
module.description = "C'Thun eye beam and tentacle tracking"

-- Called when the encounter is selected
function module:OnLoad()
  -- Check if BigWigs is loaded
  if not BigWigs then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH C'Thun:|r BigWigs not found! C'Thun map requires BigWigs.")
    return
  end
  
  -- Get the C'Thun module from BigWigs
  local bwCthun = BigWigs:GetModule("C'Thun", true)
  if not bwCthun then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH C'Thun:|r BigWigs C'Thun module not found!")
    return
  end
  
  -- Setup the map if it doesn't exist
  bwCthun:SetupMap()
  
  -- Access the global cthunmap frame
  if not cthunmap then
    return
  end
  
  -- Override the map texture with our custom numbered version
  if cthunmap.map and cthunmap.map.texture then
    cthunmap.map.texture:SetTexture("Interface\\Addons\\OG-RaidHelper\\textures\\cthunmaptexture-ogrh")
  end
  
  -- Set frame strata to HIGH and show the map
  cthunmap:SetFrameStrata("HIGH")
  cthunmap:Show()
end

-- Called when navigating away from the encounter
function module:OnUnload()
  -- Hide the map
  if cthunmap then
    cthunmap:Hide()
  end
end

-- Called when the module is being completely removed (addon unload/reload)
function module:OnCleanup()
  -- Just hide the map, don't destroy it (BigWigs owns it)
  if cthunmap then
    cthunmap:Hide()
  end
end

-- Register the module with OGRH
OGRH.RegisterModule(module)
