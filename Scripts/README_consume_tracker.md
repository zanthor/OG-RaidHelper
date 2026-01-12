# OG-RaidHelper Consume Tracker

This script parses `WoWCombatLog.txt` for OGRH_CONSUME tracking entries and generates reports.

## Quick Start - Interactive Mode

Simply run the script with no arguments:

```bash
python parse_consume_log.py
```

The script will automatically enter **interactive mode** and prompt you for:

1. **Output Mode**: Choose between Summary (aggregated stats) or Details (individual pulls)
2. **Encounter Selection**: Select a specific encounter or all encounters
3. **Player Display** (Summary mode only): Choose Top X players or All players

### Example Interactive Session

```
Parsing WoWCombatLog.txt...

================================================================================
OG-RaidHelper Consume Tracker - Configuration
================================================================================

1. Output Mode:
   [1] Summary - Aggregated player statistics
   [2] Details - Individual pull data

Select output mode (1 or 2): 1

2. Encounter Selection:
   [0] All encounters
   [1] Naxx - Faerlina (15 pulls)
   [2] Naxx - Maexxna (10 pulls)
   [3] Emerald Sanctum - Hard Mode (8 pulls)
   ...

Select encounter (0-10): 1

3. Player Display:
   [0] All players
   [X] Top X players (enter a number)

Enter 0 for all, or a number for top X players: 10

================================================================================
Configuration Summary:
  Output Mode: Summary
  Encounter: Naxx - Faerlina
  Players: Top 10
================================================================================
```

## Command Line Options

For automated/scripted use, bypass interactive mode with flags:

### Export Formats

```bash
# Export to CSV (details mode)
python parse_consume_log.py --csv

# Export to JSON
python parse_consume_log.py --json

# Export aggregated statistics
python parse_consume_log.py --aggregate

# Combine multiple formats
python parse_consume_log.py --csv --json --aggregate
```

### Control Output

```bash
# Show top 20 players (default)
python parse_consume_log.py --aggregate --top 20

# Suppress console output
python parse_consume_log.py --aggregate --quiet

# Specify custom log file location
python parse_consume_log.py /path/to/WoWCombatLog.txt

# Custom output directory
python parse_consume_log.py --aggregate -o ./reports
```

### Force Interactive Mode

```bash
# Explicitly enable interactive mode
python parse_consume_log.py --interactive
```

## Output Files

### Summary Mode
- `consume_player_stats_YYYYMMDD_HHMMSS.csv` - Player statistics aggregated across all selected pulls
- `consume_encounter_stats_YYYYMMDD_HHMMSS.csv` - Encounter statistics

### Details Mode
- `consume_tracking_YYYYMMDD_HHMMSS.csv` - Individual pull data (one row per player per pull)
- `consume_tracking_YYYYMMDD_HHMMSS.json` - Complete pull data in JSON format

## Examples

### Example 1: Quick check of specific boss
```bash
python parse_consume_log.py
# Select: Summary mode -> Specific encounter -> Top 10 players
```

### Example 2: Export all data for spreadsheet analysis
```bash
python parse_consume_log.py --csv --json
```

### Example 3: Generate full raid report
```bash
python parse_consume_log.py --aggregate
```

### Example 4: Automated daily report
```bash
python parse_consume_log.py --aggregate --quiet -o ./daily_reports
```

## Data Fields

### Player Statistics (Summary)
- PlayerName, Class, Role
- Pulls (number of pulls tracked)
- AvgScore, MinScore, MaxScore (percentage)
- TotalActualPoints, TotalPossiblePoints
- Raids, Encounters

### Encounter Statistics (Summary)
- Encounter, Raid
- Pulls (number of pulls)
- AvgGroupSize, AvgScore
- Dates, Requesters

### Pull Details
- LogTimestamp, Date, Time
- Raid, Encounter, PullNumber
- Requester, GroupSize
- PlayerName, Class, Role
- Score, ActualPoints, PossiblePoints
