# Session Admin Testing Guide

## What Changed

### Removed
- `HARDCODED_ADMINS` table (Tankmedady, Gnuzmas)
- `IsHardcodedAdmin()` function
- All hardcoded admin bypass logic (6 locations)

### Added
- `sessionAdmin` field in `Permissions.State`
- `IsSessionAdmin(playerName)` function
- `SetSessionAdmin(playerName)` function
- `/ogrh sa` slash command

## Session Admin Behavior

Session admin is **temporary** and:
- Grants full admin permissions for the current session
- Is automatically cleared when another admin is selected via normal policies
- Is lost on logout/reload (not saved to SavedVariables)
- Does not interfere with normal raid admin operations

## Testing Commands

### Grant Session Admin
```lua
/ogrh sa
```

### Verify Session Admin State
```lua
-- Check if session admin is set
/script DEFAULT_CHAT_FRAME:AddMessage("Session Admin: " .. tostring(OGRH.Permissions.State.sessionAdmin))

-- Check if you are admin
/script DEFAULT_CHAT_FRAME:AddMessage("Is Admin: " .. tostring(OGRH.IsRaidAdmin(UnitName("player"))))

-- Check permission level
/script DEFAULT_CHAT_FRAME:AddMessage("Permission Level: " .. OGRH.GetPermissionLevel(UnitName("player")))

-- Check current admin (from normal admin system)
/script DEFAULT_CHAT_FRAME:AddMessage("Current Admin: " .. tostring(OGRH.GetRaidAdmin()))
```

### Test Normal Admin Override
```lua
-- 1. Grant yourself session admin
/ogrh sa

-- 2. Verify you have admin (sync button should be green)
/script DEFAULT_CHAT_FRAME:AddMessage("Is Admin: " .. tostring(OGRH.IsRaidAdmin(UnitName("player"))))

-- 3. Have raid lead/assist use "/ogrh takeadmin" OR run admin poll
-- Session admin should be cleared automatically when another admin is selected
```

### Test Session Persistence
```lua
-- 1. Grant session admin
/ogrh sa

-- 2. Reload UI
/reload

-- 3. Check session admin (should be nil)
/script DEFAULT_CHAT_FRAME:AddMessage("Session Admin: " .. tostring(OGRH.Permissions.State.sessionAdmin))
```

## Expected Behavior

### UI Changes
- Sync button turns **green** when you have session admin
- Sync button tooltip shows "Current Raid Admin: [YourName]" (session admin is treated as current admin)
- All admin-only features become available (sync, structure save, etc.)

### Permission Checks
Session admin passes these checks:
- `IsRaidAdmin(playerName)` → `true`
- `IsRaidOfficer(playerName)` → `true`
- `GetPermissionLevel(playerName)` → `"ADMIN"`
- `CanModifyStructure(playerName)` → `true`

### Clearing Session Admin
Session admin is cleared when:
1. Another player is selected as admin via normal policies (poll, takeadmin, etc.)
2. Player logs out
3. Player reloads UI (`/reload`)

## Common Use Cases

### Development Testing
```lua
-- As a developer without raid lead/assist rank:
/ogrh sa
-- Now you can test admin features without changing your raid rank
```

### Temporary Admin Access
```lua
-- Need quick admin access for a specific task:
/ogrh sa
-- Do your task (sync, save structure, etc.)
-- When raid selects a proper admin, your session admin is cleared automatically
```

## Error Cases

### Not in Raid
Session admin works solo/party/raid - it only affects OGRH permission checks, not WoW's built-in raid system.

### Multiple Session Admins
Only one session admin at a time. Last person to run `/ogrh sa` gets session admin.

## Success Criteria

✅ `/ogrh sa` grants session admin  
✅ Session admin has full admin permissions  
✅ Sync button turns green for session admin  
✅ Normal admin selection clears session admin  
✅ `/reload` clears session admin  
✅ No hardcoded admin references remain  
✅ No Lua errors

## Debug Commands

```lua
-- Print full permission state
/ogrh permissions

-- Check all permission functions
/script DEFAULT_CHAT_FRAME:AddMessage("Session: " .. tostring(OGRH.Permissions.State.sessionAdmin))
/script DEFAULT_CHAT_FRAME:AddMessage("Current: " .. tostring(OGRH.Permissions.State.currentAdmin))
/script DEFAULT_CHAT_FRAME:AddMessage("IsAdmin: " .. tostring(OGRH.IsRaidAdmin(UnitName("player"))))
/script DEFAULT_CHAT_FRAME:AddMessage("IsOfficer: " .. tostring(OGRH.IsRaidOfficer(UnitName("player"))))
```

## Migration Notes

This replaces the hardcoded admin system which:
- Had usernames hardcoded in the source code (Tankmedady, Gnuzmas)
- Could not be changed without editing OGRH_Permissions.lua
- Bypassed normal permission checks in 6 locations

The new session admin system:
- Uses a slash command (no code editing required)
- Is session-based (temporary, safe for testing)
- Respects normal admin flow (cleared when another admin is selected)
- Is more maintainable and flexible
