-- OGRH_Backport.lua
-- Lua 5.1 compatibility shims for WoW 1.12 (Lua 5.0)
-- Provides string.match which is needed for tag replacement

-- string.match compatibility wrapper
-- In Lua 5.1+, string.match returns captures from pattern matching
-- In Lua 5.0, we use string.find which returns position + captures
if not string.match then
  string.match = function(str, pattern)
    if not str then return nil end
    
    local _, _, r1, r2, r3, r4, r5, r6, r7, r8, r9 = string.find(str, pattern)
    return r1, r2, r3, r4, r5, r6, r7, r8, r9
  end
end

-- string.gmatch compatibility (if needed in future)
if not string.gmatch then
  string.gmatch = string.gfind
end
