# Addon Audit Feature

## Overview
The Addon Audit feature in OG-RaidHelper allows raid leaders to check which raid members have specific addons installed and their versions.

## Version
Added in OG-RaidHelper v1.8.0

## How to Use

1. **Open the Audit Window**
   - Click the RH minimap button
   - Select "Audit Addons" from the menu

2. **Audit an Addon**
   - Left panel shows available addons to audit
   - Click on an addon (e.g., BigWigs) to select it
   - Window will automatically query all raid members

3. **Review Results**
   - Right panel displays three sections:
     - **Players WITHOUT the addon**: Listed with "Not Installed"
     - **Players WITH the addon**: Shows version numbers (green = Pepo version)
     - **Offline Players**: Shows who is offline
   
4. **Refresh Data**
   - Click the "Refresh" button at the bottom to re-query

## Supported Addons

### BigWigs
- Detects BigWigs installation
- Shows version numbers
- Identifies Pepo BigWigs fork (displayed in green)
- Uses BigWigs' built-in version query system

## Requirements
- Must be in a party or raid to query addon versions
- Queried addon must be installed on your character to check others
- Results depend on other players having BigWigs installed and responding to queries

## Technical Details

### Files Added
- `OGRH_AddonAudit.lua` - Main addon audit module

### Integration
- Integrated into RH button menu
- Participates in mutual window exclusion
- Uses BigWigs' version query protocol (BWVQ/BWVR sync)

### How It Works
1. When you select BigWigs, the addon calls `BigWigsVersionQuery:QueryVersion("BigWigs")`
2. BigWigs broadcasts a version query to all raid members
3. Responses are collected in `BigWigsVersionQuery.responseTable` and `BigWigsVersionQuery.pepoResponseTable`
4. Results are parsed and displayed after a 3-second collection period

## Future Enhancements
The addon list can be extended to support other addons that have similar version query systems.
