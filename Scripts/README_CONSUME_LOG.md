# OG-RaidHelper Consume Tracking - Combat Log Export

This feature allows you to automatically log consume tracking data to the WoW combat log file for later analysis.

## Requirements

- **SuperWoW addon** - Required for combat log functionality
  - Download from: https://github.com/balakethelock/SuperWoW
  - Without SuperWoW, the Combat Log checkbox will be disabled

## How to Use

### In-Game Setup

1. Open the Track Consumes window in OG-RaidHelper
2. Go to the "Tracking" section
3. Enable "Track on Pull" checkbox
4. Set "seconds before pull" to your desired timing (default: 2 seconds)
5. Enable "Combat Log" checkbox (only works with SuperWoW installed)

### How It Works

When enabled, the addon will:
1. Listen for BigWigs pull timers in raid chat
2. Wait until N seconds before the pull (configurable)
3. Capture all raid members' consume scores
4. Write the data directly to `Logs/WoWCombatLog.txt` via SuperWoW

**Important:** The data is written immediately - no need to `/reload` or logout!

### Data Format

The combat log entries follow this format:

```
MM/DD HH:MM:SS.mmm  OGRH_CONSUME_PULL: timestamp&date&time&raid&encounter&pullNumber&requester&groupSize
MM/DD HH:MM:SS.mmm  OGRH_CONSUME_PLAYER: playerName&class&role&score&actualPoints&possiblePoints
MM/DD HH:MM:SS.mmm  OGRH_CONSUME_PLAYER: ...
MM/DD HH:MM:SS.mmm  OGRH_CONSUME_END: timestamp
```

## Parsing the Logs

### Python Script

A Python script is included to parse and analyze the combat log data.

**Location:** `Scripts/parse_consume_log.py`

### Basic Usage

```bash
# Show summary and export player/encounter statistics
python parse_consume_log.py

# Specify custom log file location
python parse_consume_log.py "C:/Path/To/WoWCombatLog.txt"

# Export to JSON format
python parse_consume_log.py --json

# Export detailed CSV (one row per player per pull)
python parse_consume_log.py --csv

# Export aggregated statistics
python parse_consume_log.py --aggregate

# Show top 50 players instead of default 20
python parse_consume_log.py --top 50

# Quiet mode (no console output, just export)
python parse_consume_log.py --quiet --aggregate
```

### Output Files

The script generates timestamped CSV files:

1. **consume_player_stats_YYYYMMDD_HHMMSS.csv**
   - One row per player
   - Shows: Average score, min/max scores, total pulls, raids/encounters played
   - Sorted by average score (highest first)

2. **consume_encounter_stats_YYYYMMDD_HHMMSS.csv**
   - One row per raid encounter
   - Shows: Number of pulls, average group size, average score, dates, requesters

3. **consume_tracking_YYYYMMDD_HHMMSS.csv** (with --csv flag)
   - Detailed data: One row per player per pull
   - All fields included for maximum detail

4. **consume_tracking_YYYYMMDD_HHMMSS.json** (with --json flag)
   - Full structured data in JSON format
   - Useful for custom analysis or importing into other tools

### Example Output

```
================================================================================
OG-RaidHelper Consume Tracking Summary
================================================================================
Total Pulls: 47
Date Range: 01/07 to 01/08
Raids: Naxxramas
Encounters: 12 unique encounters
Unique Players: 38
Average Score: 87.3% (min: 45%, max: 100%)

================================================================================

Recent Pulls (last 5):
--------------------------------------------------------------------------------
01/08 19:45 | Naxxramas - Patchwerk
  Pull #5 by RaidLeader (40 players)
  Average Score: 91.2%

...

================================================================================
Top 20 Players by Average Score
================================================================================
Rank   Player               Class      Role     Pulls   Avg     Min     Max    
--------------------------------------------------------------------------------
1      Healbot              Priest     HEALERS  47      99.8    98      100    
2      Tankmaster           Warrior    TANKS    47      98.5    95      100    
3      DPSgod               Rogue      MELEE    45      95.2    87      100    
...
```

## Use Cases

### Guild Leadership
- Track raid preparedness over time
- Identify players who consistently under-prepare
- Reward players with high consume scores
- Compare different raid nights/encounters

### Personal Improvement
- Track your own consume score trends
- Identify which consumables you frequently forget
- Set goals for improvement

### Raid Analysis
- Correlate consume scores with boss kill success
- Identify if certain encounters have lower preparation
- Track pull requester patterns

## Tips

1. **Enable at raid start:** Turn on tracking at the beginning of the raid night
2. **Parse after raid:** Run the Python script after the raid to generate reports
3. **Regular cleanup:** The combat log file can get large - archive or clear it periodically
4. **Role assignment:** Make sure all raiders have roles assigned in OG-RaidHelper for accurate scoring
5. **Weight configuration:** Adjust consumable weights in the "Weights" tab to match your raid priorities

## Troubleshooting

**Combat Log checkbox is grayed out**
- SuperWoW is not installed or not working
- Check that SuperWoW_DLL folder is in your AddOns directory
- Restart the game after installing SuperWoW

**No data in combat log after pulls**
- Verify "Track on Pull" is enabled
- Verify "Combat Log" checkbox is checked
- Check that a raid/encounter is selected in OG-RaidHelper
- Ensure BigWigs is broadcasting pull timers (must be raid assist or leader)

**Python script shows "No entries found"**
- Check the log file path is correct (default: `../../Logs/WoWCombatLog.txt`)
- Verify data was actually written during pulls
- The combat log file may have been cleared/reset

**Scores seem wrong**
- Verify roles are assigned correctly in Roles UI
- Check that RABuffs profile "OGRH_Consumables" exists and has bars
- Review consumable weights in the Weights tab
- Ensure role mapping in Mapping tab is correct

## Advanced Usage

### Custom Analysis

The JSON export can be imported into your own analysis tools:

```python
import json

with open('consume_tracking_20260108_194500.json') as f:
    data = json.load(f)

# Analyze as needed
for entry in data:
    print(f"Pull: {entry['raid']} - {entry['encounter']}")
    for player in entry['players']:
        if player['score'] < 80:
            print(f"  {player['name']}: {player['score']}%")
```

### Excel Integration

Both CSV outputs can be directly opened in Excel for:
- Pivot tables
- Charts and graphs
- Conditional formatting
- Custom formulas and analysis

## Version History

- **v1.0** (2025-01-08)
  - Initial release
  - SuperWoW integration
  - Python parser with aggregation
  - CSV/JSON export support
