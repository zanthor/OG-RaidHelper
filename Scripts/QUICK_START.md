# Combat Log Feature - Quick Start Guide

## In-Game Setup (30 seconds)

1. `/ogrh` → Track Consumes
2. Click "Tracking"
3. ✓ Enable "Track on Pull"
4. ✓ Enable "Combat Log" (requires SuperWoW)
5. Set seconds before pull (default: 2)

## After Your Raid

### Windows Users
1. Double-click `parse_consume_log.bat`
2. Check for CSV files in the Scripts folder

### Manual Python
```bash
cd Interface/AddOns/OG-RaidHelper/Scripts
python parse_consume_log.py --aggregate
```

## What You Get

### Player Statistics CSV
- Average consume score per player
- Min/Max scores
- Total pulls tracked
- Sorted by performance

### Encounter Statistics CSV  
- Pull counts per boss
- Average raid prep by encounter
- Group size and dates

## Quick Commands

```bash
# Basic - show summary + export stats
python parse_consume_log.py

# Export everything
python parse_consume_log.py --csv --json --aggregate

# Top 50 players
python parse_consume_log.py --top 50

# Custom log location
python parse_consume_log.py "C:/Custom/Path/WoWCombatLog.txt"

# Silent mode (just export)
python parse_consume_log.py --quiet --aggregate
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Combat Log checkbox grayed out | Install SuperWoW addon |
| No data after pulls | Check "Track on Pull" is enabled |
| Python not found | Install Python 3.6+ from python.org |
| Empty output | Verify log file path is correct |

## Data Location

**In-Game Logs:** `<WoW>/Logs/WoWCombatLog.txt`  
**Exports:** `<WoW>/Interface/AddOns/OG-RaidHelper/Scripts/`

## Log Format (for custom parsing)

```
OGRH_CONSUME_PULL: timestamp&date&time&raid&encounter&pullNum&requester&size
OGRH_CONSUME_PLAYER: name&class&role&score&actual&possible
...
OGRH_CONSUME_END: timestamp
```

## Pro Tips

✓ Enable at raid start for full night tracking  
✓ Parse after each raid night  
✓ Share player stats CSV with guild leadership  
✓ Use Excel pivot tables for deeper analysis  
✓ Archive old combat logs to save disk space  

---

**Need Help?** See full README_CONSUME_LOG.md in Scripts folder
