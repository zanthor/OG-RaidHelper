# WoW 1.12 Testing: The Correct Approach

**Date:** January 23, 2026  
**Issue:** Incorrect test execution method documented

---

## What Was Wrong

❌ **Incorrect Approach (Not WoW 1.12 Compatible):**
```lua
/script dofile("Interface\\AddOns\\OG-RaidHelper\\Tests\\test_svm.lua")
```

**Why This Doesn't Work:**
- `dofile()` is either not available or severely restricted in WoW 1.12 for security reasons
- This pattern works in modern WoW (Retail, Classic Era+) but NOT in vanilla 1.12
- Attempting this will result in "Function not found" or security errors

---

## The Correct WoW 1.12 Approach

✅ **Method 1: Load via TOC and Run via Slash Command**

**Step 1:** Add test file to `OG-RaidHelper.toc`:
```toc
## Phase 8: Tests (Debug Mode Only)
Tests\test_svm.lua
```

**Step 2:** Structure test file as namespace:
```lua
OGRH = OGRH or {}
OGRH.Tests = OGRH.Tests or {}
OGRH.Tests.SVM = {}

function OGRH.Tests.SVM.RunAll()
    -- Test code here
end
```

**Step 3:** Register slash command in `UI/MainUI.lua`:
```lua
elseif string.find(sub, "^test") then
    local _, _, testName = string.find(fullMsg, "^%s*test%s+(%S+)")
    
    if testName == "svm" then
        if OGRH.Tests and OGRH.Tests.SVM and OGRH.Tests.SVM.RunAll then
            OGRH.Tests.SVM.RunAll()
        else
            OGRH.Msg("SVM tests not loaded.")
        end
    end
```

**Step 4:** Run in-game:
```
/ogrh test svm
```

---

## Why This Works in 1.12

✅ **TOC Load Order:**
- WoW 1.12 loads files in TOC order at addon load time
- Files become part of the global namespace
- No runtime file loading needed

✅ **Slash Commands:**
- Slash commands registered via `SlashCmdList` are the standard 1.12 pattern
- Used by all vanilla addons for user interaction
- No security restrictions

✅ **Global Namespace:**
- All code runs in global scope
- Functions accessible via `OGRH.Tests.SVM.RunAll()`
- No need for dynamic loading

---

## Alternative: Inline Test Execution

If you absolutely need to run tests without modifying the TOC:

```lua
/script if OGRH.Tests and OGRH.Tests.SVM then OGRH.Tests.SVM.RunAll() else DEFAULT_CHAT_FRAME:AddMessage("Tests not loaded") end
```

**Limitation:** Tests must already be loaded via TOC. You cannot load arbitrary .lua files at runtime in 1.12.

---

## Comparison: WoW 1.12 vs Modern WoW

| Feature | WoW 1.12 (Vanilla) | Modern WoW (Retail) |
|---------|-------------------|---------------------|
| `dofile()` | ❌ Not available | ✅ Available |
| TOC Loading | ✅ Required | ✅ Required |
| Slash Commands | ✅ `SlashCmdList` | ✅ `SlashCmdList` |
| Runtime File Load | ❌ Not possible | ✅ Possible with restrictions |
| Security Sandbox | Strict | Very Strict |

---

## Lessons Learned

1. **Always test assumptions** about API availability in target version
2. **Read design philosophy carefully** - constraints are there for a reason
3. **Check existing patterns** in codebase before inventing new ones
4. **WoW 1.12 is NOT modern Lua** - many conveniences don't exist

---

## Fixed Implementation

All documentation has been updated:
- ✅ [SVM-API-Documentation.md](SVM-API-Documentation.md) - Fixed test command
- ✅ [SVM-Quick-Reference.md](SVM-Quick-Reference.md) - Fixed test command
- ✅ [Phase-1-Completion-Summary.md](Phase-1-Completion-Summary.md) - Fixed test instructions
- ✅ [test_svm.lua](../Tests/test_svm.lua) - Restructured as namespace with slash command
- ✅ [MainUI.lua](../UI/MainUI.lua) - Added `/ogrh test svm` command
- ✅ [OG-RaidHelper.toc](../OG-RaidHelper.toc) - Added test file to load order

**Correct Usage:**
```
1. Reload addon (/reload or restart WoW)
2. Run: /ogrh test svm
3. See results in OGRH chat window
```

---

## Apology

This was a fundamental error in understanding the WoW 1.12 environment. The design philosophy document clearly states the constraints, and I failed to apply them consistently. This has been corrected, and all future implementations will properly validate against WoW 1.12 constraints.
