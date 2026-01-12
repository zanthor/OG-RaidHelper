# Changes Made to parse_consume_log.py

## Summary
Added interactive prompts at the start of the script to allow users to choose runtime output options.

## New Features

### 1. Interactive Mode (Auto-enabled by default)
When running the script without command-line flags, it now enters interactive mode with three prompts:

#### Prompt 1: Output Mode
- **[1] Summary** - Aggregated player statistics across all selected pulls
- **[2] Details** - Individual pull data with full per-pull information

#### Prompt 2: Encounter Selection
- **[0] All encounters** - Include data from all raid encounters
- **[1-N] Specific encounter** - Filter to a single encounter (e.g., "Naxx - Faerlina")
  - Shows pull count for each encounter
  - Sorted by pull count (most pulls first)

#### Prompt 3: Player Display (Summary mode only)
- **[0] All players** - Show and export all players
- **[X] Top X players** - Show only top X players by average score

### 2. Smart Default Behavior
- Interactive mode is automatically enabled when no export flags are provided
- Original command-line behavior is preserved when using `--csv`, `--json`, `--aggregate`, or `--quiet`
- Can explicitly force interactive mode with `--interactive` flag

## New Function

### `get_user_choices(logs: List[Dict[str, Any]])`
Displays interactive prompts and collects user preferences:
- Parses unique encounters from logs
- Validates user input
- Returns configuration dictionary with:
  - `output_mode`: 'summary' or 'details'
  - `selected_encounter`: encounter key or None for all
  - `top_n`: number of players or None for all

## Modified Functions

### `main()`
- Added `--interactive` argument
- Auto-enables interactive mode when appropriate
- Filters logs by encounter if selected
- Routes to different output modes based on user choices
- Maintains backward compatibility with existing command-line usage

## Usage Examples

### Interactive Mode (Default)
```bash
python parse_consume_log.py
# User is prompted for output preferences
```

### Command-Line Mode (Bypasses Interactive)
```bash
# These commands work exactly as before
python parse_consume_log.py --csv
python parse_consume_log.py --aggregate --top 10
python parse_consume_log.py --json --quiet
```

### Force Interactive
```bash
python parse_consume_log.py --interactive
```

## Output Files

### Summary Mode
- `consume_player_stats_YYYYMMDD_HHMMSS.csv`
- `consume_encounter_stats_YYYYMMDD_HHMMSS.csv`

### Details Mode
- `consume_tracking_YYYYMMDD_HHMMSS.csv`
- `consume_tracking_YYYYMMDD_HHMMSS.json`

## Benefits
1. **User-friendly**: No need to remember command-line flags for common use cases
2. **Flexible filtering**: Easy encounter selection at runtime
3. **Dynamic top N**: Adjust player count without editing script
4. **Backward compatible**: All existing command-line usage still works
5. **Smart defaults**: Interactive mode only when it makes sense
