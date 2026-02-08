# Segment Recovery from Combat Log

## Overview

When game clients crash, pending segment data stored in SavedVariables can be lost. To prevent this, OGRH automatically writes segment data to the combat log (if SuperWoW is available) when segments are captured.

This recovery system allows you to extract lost segments from your `WoWCombatLog.txt` file and import them back into OGRH.

---

## Requirements

- **SuperWoW addon** must be installed and active during segment capture
- Combat logs are written to: `<WoW Directory>\Logs\WoWCombatLog.txt`
- **Python 3.6+** to run the extraction script

---

## Recovery Workflow

### 1. Extract Segments from Combat Log

Run the extraction script to parse your combat log:

**Windows (Easy Method):**
- Double-click `extract_segments.bat` (auto-detects WoWCombatLog.txt)
- OR drag-and-drop WoWCombatLog.txt onto `extract_segments.bat`

**Windows (PowerShell):**
```powershell
python .\extract_segments.py "C:\Games\TurtleWow\Logs\WoWCombatLog.txt"
```

**Linux/Mac:**
```bash
python extract_segments.py ~/Games/TurtleWow/Logs/WoWCombatLog.txt
```

### 2. Copy Segment Data

The script will output each found segment in this format:

```
========================================
SEGMENT 1: Ragnaros - 19:30:45
========================================
Timestamp: 2026-02-06 19:30:45
Raid: Molten Core (Index: 1)
Encounter: Ragnaros (Index: 9)
Combat Time: 180.50s
Players: 25

--- IMPORTABLE DATA (Copy everything between START and END) ---
START_SEGMENT_DATA
SEGMENT_META|Ragnaros - 19:30:45|2026-02-06 19:30:45|Molten Core|1|Ragnaros|9|180.50
PlayerName|WARRIOR|TANKS|50000|0|0
HealerName|PRIEST|HEALERS|5000|45000|50000
...
END_SEGMENT_DATA
```

**Copy everything between `START_SEGMENT_DATA` and `END_SEGMENT_DATA` (inclusive).**

### 3. Import into OGRH

1. Launch WoW and log in
2. Type `/ogrh roster` to open the Roster Management window
3. Click **"Import Ranking Data"** button
4. In the Source dropdown, select **"Import CSV"** (the text box will appear)
5. **Paste** the copied segment data into the text box
6. The system will automatically:
   - Detect the segment recovery format
   - Parse all player data (damage, healing, roles)
   - Reconstruct the segment
   - Add it to **Pending Segments** list
   - Populate the role columns with player data

7. Click **"Update ELO"** to apply the rankings to your roster

---

## Data Format

### Segment Metadata Line
```
SEGMENT_META|SegmentName|Timestamp|RaidName|RaidIndex|EncounterName|EncounterIndex|CombatTime
```

### Player Data Lines
```
PlayerName|Class|Role|Damage|EffectiveHealing|TotalHealing
```

**Example:**
```
SEGMENT_META|Ragnaros Kill|2026-02-06 19:30:45|Molten Core|1|Ragnaros|9|180.50
Tankmedady|WARRIOR|TANKS|25000|0|0
Pirotes|ROGUE|MELEE|85000|0|0
Lucifron|PRIEST|HEALERS|8000|120000|135000
```

---

## Important Notes

### Automatic Export
- Segments are **automatically** written to combat log when captured (if SuperWoW is available)
- No additional action required during gameplay
- Export happens immediately after segment creation

### Data Limitations
- **Effective Combat Time**: Not recoverable (complex per-player data)
- **Top DPS/Healer**: Recalculated during import
- **Import Status**: Always starts as `imported = false`

### Multiple Segments
- The extraction script will find **all** OGRH segments in the combat log
- Each segment is output separately
- Import them one at a time as needed

### Timestamps
- Recovered segments use the **original** timestamp from capture
- This preserves chronological ordering
- Segments will expire 2 days from original capture time

---

## Troubleshooting

### "No segments found"
- Verify AutoRank was enabled when segments were created
- Check that SuperWoW was active during segment capture
- Confirm you're looking at the correct combat log file

### "Invalid segment format"
- Ensure you copied the **entire** block between START and END
- Check for line breaks or formatting corruption
- Try re-running the extraction script

### Segment not appearing in Pending Segments list
- Close and reopen the Import Ranking Data window
- Check `/ogrh segments` to verify it was added
- Verify the segment wasn't already marked as imported

### SuperWoW not available
- Install SuperWoW addon from Turtle WoW forums
- Restart the game client
- Verify SuperWoW is loaded: type `/swow` in-game

---

## Example Session

**1. Game crashes during raid**
```
[Player loses all unsaved data]
```

**2. Extract from combat log (next day)**
```bash
$ python extract_segments.py WoWCombatLog.txt
Found 3 segment(s) in combat log

========================================
SEGMENT 1: Ragnaros Kill
========================================
[... segment data ...]
```

**3. Copy segment data**
```
START_SEGMENT_DATA
SEGMENT_META|Ragnaros Kill|2026-02-06 19:30:45|Molten Core|1|Ragnaros|9|180.50
Tankmedady|WARRIOR|TANKS|25000|0|0
...
END_SEGMENT_DATA
```

**4. Import in-game**
```
/ogrh roster → Import Ranking Data → Paste → Import CSV
```

**5. Verify**
```
Source dropdown shows: "Pending Segments (1)"
Segment appears: "Ragnaros Kill [RECOVERED]"
```

**6. Use segment**
```
Click segment → Review players → Update ELO
```

---

## Combat Log Format (Technical)

OGRH writes three types of lines to the combat log:

### Header
```
OGRH_SEGMENT_HEADER: segmentId&name&timestamp&createdAt&raidName&raidIndex&encounterName&encounterIndex&combatTime&playerCount
```

### Player Data
```
OGRH_SEGMENT_PLAYER: playerName&class&role&damage&effectiveHealing&totalHealing
```

### End Marker
```
OGRH_SEGMENT_END: segmentId
```

The extraction script parses these lines and converts them to the importable format.

---

## See Also

- [DPSMate Pending Segment System Documentation](../Documentation/DPSMate%20Pending%20Segment%20System.md)
- [V2 Schema Specification](../Documentation/Spec%20Docs/!%20V2%20Schema%20Specification.md)
- Roster Management: `/ogrh roster`
- Debug Segments: `/ogrh segments`
