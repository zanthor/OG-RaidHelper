-- OGRH_Utilities.lua (Turtle-WoW 1.12)
-- Generic utility functions for OG-RaidHelper

OGRH = OGRH or {}

--[[
    Timer Utilities
]]

-- Schedule a function to execute after a delay (in seconds)
-- Returns the frame handle for optional cancellation
function OGRH.ScheduleFunc(func, delay)
  local frame = CreateFrame("Frame")
  local elapsed = 0
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= delay then
      frame:SetScript("OnUpdate", nil)
      func()
    end
  end)
  return frame
end

-- Cancel a scheduled function (optional - use returned frame handle)
function OGRH.CancelScheduledFunc(frame)
  if frame and frame.SetScript then
    frame:SetScript("OnUpdate", nil)
  end
end

OGRH.Msg("Utilities Loaded")
