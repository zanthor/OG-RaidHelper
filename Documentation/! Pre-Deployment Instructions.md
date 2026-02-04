# OG-RaidHelper: Pre-Deployment Instructions for Git

**Version:** 1.0 (January 2026)

This document provides step-by-step instructions for AI agents to prepare the OG-RaidHelper addon for Git deployment. Follow these instructions precisely before committing to the repository.

---

## Overview

Before deploying OG-RaidHelper to Git, we must:

1. **Copy shared libraries** from the AddOns folder to the local `Libs/` directory
2. **Update the TOC file** to reference the local library files
3. **Verify all dependencies** are properly included
4. **Validate the structure** for standalone distribution

This ensures that OG-RaidHelper is self-contained and can be deployed independently without requiring users to manually install separate library addons.

---

## STEP 1: Prepare the Libs Directory

Create or verify the `Libs/` directory structure exists:

```
OG-RaidHelper/
├── Libs/
│   ├── OGAddonMsg/
│   └── OGST/
```

**Commands:**

```powershell
# Ensure Libs directory exists
New-Item -Path "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs" -ItemType Directory -Force

# Create subdirectories for libraries
New-Item -Path "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGAddonMsg" -ItemType Directory -Force
New-Item -Path "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGST" -ItemType Directory -Force
```

---

## STEP 2: Copy OGAddonMsg Library

Copy all files from `_OGAddonMsg` to `Libs/OGAddonMsg/`:

**Source Location:**
```
d:\games\TurtleWow\Interface\AddOns\_OGAddonMsg\
```

**Destination:**
```
d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGAddonMsg\
```

**Commands:**

```powershell
# Copy all OGAddonMsg files
Copy-Item -Path "d:\games\TurtleWow\Interface\AddOns\_OGAddonMsg\*" `
          -Destination "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGAddonMsg\" `
          -Recurse -Force
```

**Files to verify:**
- `OGAddonMsg.lua` (main library file)
- `OGAddonMsg.toc` (optional, for reference)
- Any other supporting files

---

## STEP 3: Copy OGST Library

Copy all files from `_OGST` to `Libs/OGST/`:

**Source Location:**
```
d:\games\TurtleWow\Interface\AddOns\_OGST\
```

**Destination:**
```
d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGST\
```

**Commands:**

```powershell
# Copy all OGST files
Copy-Item -Path "d:\games\TurtleWow\Interface\AddOns\_OGST\*" `
          -Destination "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGST\" `
          -Recurse -Force
```

**Files to verify:**
- `OGST.lua` (main library file)
- `README.md` (API documentation)
- `img/` directory (texture resources)
- Any other supporting files

---

## STEP 4: Update TOC File

Modify `OG-RaidHelper.toc` to include the local library files.

### Current TOC Structure (Example)

The TOC file currently might reference the libraries as separate addons:

```toc
## Interface: 11200
## Title: OG-RaidHelper
## Notes: Raid assistance tools
## Author: Your Name
## Version: 1.0
## SavedVariables: OGRH_DB
## SavedVariablesPerCharacter: OGRH_CharDB
## Dependencies: _OGAddonMsg, _OGST

Core.lua
Database.lua
Utils.lua
...
```

### Required Changes

**Remove** the `## Dependencies:` line and **add** explicit file references to the libraries at the **top** of the load order:

```toc
## Interface: 11200
## Title: OG-RaidHelper
## Notes: Raid assistance tools
## Author: Your Name
## Version: 1.0
## SavedVariables: OGRH_DB
## SavedVariablesPerCharacter: OGRH_CharDB

# Embedded Libraries (load first)
Libs\OGAddonMsg\OGAddonMsg.lua
Libs\OGST\OGST.lua

# Core addon files
Core.lua
Database.lua
Utils.lua
...
```

### Critical TOC Requirements

1. **Library files MUST be listed FIRST** - Before any addon code
2. **Use backslashes** (`\`) for paths (WoW 1.12 convention)
3. **Remove Dependencies line** - Libraries are now embedded
4. **Verify exact filenames** - Case-sensitive on some systems
5. **Load order matters** - If OGST depends on OGAddonMsg, list OGAddonMsg first

### TOC Update Process

**Step 4a: Read the current TOC file**

```lua
-- Use read_file to examine the current TOC structure
```

**Step 4b: Identify library dependencies**

Check if the TOC currently has:
- `## Dependencies:` line mentioning `_OGAddonMsg` or `_OGST`
- `## OptionalDeps:` line mentioning these libraries

**Step 4c: Update the TOC**

Use `replace_string_in_file` or `multi_replace_string_in_file` to:
1. Remove the `## Dependencies:` or `## OptionalDeps:` line (if present)
2. Add library file references at the top of the file list
3. Preserve all other TOC metadata

**Example replacement:**

```
OLD:
## SavedVariablesPerCharacter: OGRH_CharDB
## Dependencies: _OGAddonMsg, _OGST

Core.lua

NEW:
## SavedVariablesPerCharacter: OGRH_CharDB

# Embedded Libraries (load first)
Libs\OGAddonMsg\OGAddonMsg.lua
Libs\OGST\OGST.lua

# Core addon files
Core.lua
```

---

## STEP 5: Verify Library File Paths

Ensure all library file paths are correct by scanning the copied directories.

**For OGAddonMsg:**

```powershell
# List all files in OGAddonMsg
Get-ChildItem -Path "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGAddonMsg\" -Recurse
```

Verify the main file is `OGAddonMsg.lua`. If there are additional Lua files, add them to the TOC in the correct load order.

**For OGST:**

```powershell
# List all files in OGST
Get-ChildItem -Path "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGST\" -Recurse
```

Verify the main file is `OGST.lua`. Check for any additional Lua files that need to be loaded. Common patterns:
- `OGST.lua` (main file)
- `Utils.lua` (helpers)
- `Components/` directory (if modular)

**Update TOC if additional files found:**

```toc
# Embedded Libraries
Libs\OGAddonMsg\OGAddonMsg.lua

Libs\OGST\OGST.lua
Libs\OGST\Utils.lua
Libs\OGST\Components\Windows.lua
# ... etc
```

---

## STEP 6: Validate Resource Paths

OGST uses texture resources from its `img/` directory. Verify these paths are correct.

**Check for hardcoded paths in OGST.lua:**

Search for any references to:
- `Interface\\AddOns\\_OGST\\img\\`
- Absolute paths to the OGST addon directory

**Update if necessary:**

These should be relative paths or use `OGST.GetResourcePath()`:

```lua
-- CORRECT (relative from addon root)
local texPath = "Interface\\AddOns\\OG-RaidHelper\\Libs\\OGST\\img\\texture-name"

-- CORRECT (if OGST has a GetResourcePath function)
local texPath = OGST.GetResourcePath() .. "img\\texture-name"

-- WRONG (absolute path to separate addon)
local texPath = "Interface\\AddOns\\_OGST\\img\\texture-name"
```

**AI Agent Task:**

Use `grep_search` to find any hardcoded `_OGST` paths in the copied OGST library files:

```lua
-- Search pattern
grep_search: "_OGST\\img\\" in Libs/OGST/
```

Replace any found instances with the correct relative path.

---

## STEP 7: Test Namespace Collisions

Ensure the embedded libraries don't conflict with standalone versions.

**Potential Issues:**

1. User has both `_OGST` addon AND embedded OGST in OG-RaidHelper
2. Libraries might register themselves globally and conflict

**Solution:**

Add version checks or namespace protection in `Core.lua`:

```lua
-- In OG-RaidHelper Core.lua (OnLoad)
function OGRH.OnLoad()
    -- Verify libraries are loaded
    if not OGAddonMsg then
        DEFAULT_CHAT_FRAME:AddMessage("OG-RaidHelper: Missing OGAddonMsg library!", 1, 0, 0)
        return
    end
    
    if not OGST then
        DEFAULT_CHAT_FRAME:AddMessage("OG-RaidHelper: Missing OGST library!", 1, 0, 0)
        return
    end
    
    -- Optional: Version check
    local requiredOGSTVersion = "2.0"
    if OGST.VERSION and OGST.VERSION < requiredOGSTVersion then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OG-RaidHelper: OGST version %s required (found %s)", 
                requiredOGSTVersion, OGST.VERSION or "unknown"),
            1, 0.5, 0
        )
    end
    
    -- Initialize addon
    OGRH.EnsureSV()
    -- ... rest of initialization
end
```

---

## STEP 8: Update README.md (If Exists)

If OG-RaidHelper has a README.md, update the installation instructions.

**Add section:**

```markdown
## Installation

1. Download the latest release
2. Extract to `World of Warcraft\Interface\AddOns\`
3. Restart WoW

**Note:** OG-RaidHelper includes embedded copies of OGAddonMsg and OGST libraries. 
You do NOT need to install these separately.
```

---

## STEP 9: Create .gitignore (If Missing)

Ensure unnecessary files are excluded from Git:

**File:** `OG-RaidHelper/.gitignore`

```gitignore
# WoW cache files
*.bak
*.tmp

# Editor files
.vscode/
.idea/
*.swp
*~

# OS files
.DS_Store
Thumbs.db
desktop.ini

# Don't ignore our embedded libs
!Libs/
```

---

## STEP 10: Final Verification Checklist

Before committing to Git, verify:

### File Structure
- [ ] `Libs/OGAddonMsg/` directory exists
- [ ] `Libs/OGAddonMsg/OGAddonMsg.lua` exists
- [ ] `Libs/OGST/` directory exists  
- [ ] `Libs/OGST/OGST.lua` exists
- [ ] `Libs/OGST/img/` directory exists (if OGST uses textures)

### TOC File
- [ ] `## Dependencies:` line removed (or doesn't reference _OGAddonMsg/_OGST)
- [ ] `Libs\OGAddonMsg\OGAddonMsg.lua` listed first in file section
- [ ] `Libs\OGST\OGST.lua` listed second in file section
- [ ] All other addon files listed after libraries
- [ ] Paths use backslashes (`\`), not forward slashes

### Code References
- [ ] No hardcoded paths to `_OGAddonMsg` or `_OGST` addon directories
- [ ] Resource paths are relative or use library helper functions
- [ ] Namespace checks added in `Core.lua` (optional but recommended)

### Documentation
- [ ] README.md updated (if exists)
- [ ] Installation instructions note embedded libraries
- [ ] .gitignore excludes unnecessary files

### Testing (If Possible)
- [ ] Addon loads without errors in WoW 1.12
- [ ] Libraries are accessible (OGST, OGAddonMsg globals exist)
- [ ] No conflicts with standalone library addons

---

## AI Agent Workflow

When executing these instructions:

1. **Start with file structure** - Create directories, copy files
2. **Verify file lists** - Use list_dir to confirm files were copied
3. **Read TOC file** - Use read_file to see current structure
4. **Update TOC** - Use replace_string_in_file for precise edits
5. **Search for issues** - Use grep_search to find hardcoded paths
6. **Fix any issues** - Use replace_string_in_file to correct paths
7. **Report results** - Summarize what was done and any issues found

### Example AI Response

```
✅ Completed pre-deployment preparation:

1. Created Libs/ directory structure
2. Copied _OGAddonMsg to Libs/OGAddonMsg/ (1 file)
3. Copied _OGST to Libs/OGST/ (3 files + img/ directory)
4. Updated OG-RaidHelper.toc:
   - Removed ## Dependencies: _OGAddonMsg, _OGST
   - Added Libs\OGAddonMsg\OGAddonMsg.lua at load position 1
   - Added Libs\OGST\OGST.lua at load position 2
5. Found 2 hardcoded paths in OGST.lua, corrected to relative paths
6. Verified all files present

⚠️ Note: Unable to test in-game. Please verify addon loads correctly.

The addon is ready for Git commit.
```

---

## Troubleshooting

### Issue: Library files not copied

**Symptom:** `Libs/` directory is empty or missing files

**Solution:** Verify source paths are correct. The libraries might be in different locations:
```powershell
# Search for OGAddonMsg
Get-ChildItem -Path "d:\games\TurtleWow\Interface\AddOns\" -Filter "OGAddonMsg*" -Directory

# Search for OGST
Get-ChildItem -Path "d:\games\TurtleWow\Interface\AddOns\" -Filter "OGST*" -Directory
```

### Issue: TOC file references wrong paths

**Symptom:** Addon fails to load, lua errors about missing files

**Solution:** Double-check backslash usage and exact filenames. WoW 1.12 is case-sensitive on some systems.

### Issue: Resource textures not loading

**Symptom:** OGST UI elements have missing textures

**Solution:** Verify `img/` directory was copied and paths updated:
```powershell
Get-ChildItem -Path "d:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Libs\OGST\img\" -Recurse
```

### Issue: Addon loads but libraries are nil

**Symptom:** `OGAddonMsg` or `OGST` global is nil

**Solution:** Check TOC load order. Libraries must be listed BEFORE any addon code that references them.

---

## Post-Deployment

After deploying to Git, users will:

1. Clone the repository or download the release
2. Place `OG-RaidHelper/` folder in their AddOns directory  
3. Launch WoW - everything should work without additional setup

**No additional downloads required** - all dependencies are embedded.

---

**END OF PRE-DEPLOYMENT INSTRUCTIONS**

Follow these steps carefully to ensure a clean, standalone distribution of OG-RaidHelper.
