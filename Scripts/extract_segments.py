#!/usr/bin/env python3
"""
OG-RaidHelper Segment Recovery - WoWCombatLog Parser
Extracts OGRH segment data from WoWCombatLog.txt for crash recovery
Written by OGRH.PendingSegments.WriteSegmentToCombatLog()

Usage: python extract_segments.py [path_to_WoWCombatLog.txt]
"""

import re
import sys
from pathlib import Path
from typing import List, Dict, Any


def parse_segments_from_combatlog(filepath: Path) -> List[Dict[str, Any]]:
    """
    Parse WoWCombatLog.txt for OGRH_SEGMENT entries
    
    Format:
    OGRH_SEGMENT_HEADER: segmentId&name&timestamp&createdAt&raidName&raidIndex&encounterName&encounterIndex&combatTime&playerCount
    OGRH_SEGMENT_PLAYER: playerName&class&role&damage&effectiveHealing&totalHealing
    OGRH_SEGMENT_END: segmentId
    """
    segments = []
    current_segment = None
    
    with filepath.open('r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            
            # OGRH_SEGMENT_HEADER: header line
            if 'OGRH_SEGMENT_HEADER:' in line:
                match = re.search(r'OGRH_SEGMENT_HEADER:\s+(.+)', line)
                if match:
                    data = match.group(1).split('&')
                    
                    if len(data) >= 10:
                        # Save previous segment if exists
                        if current_segment:
                            segments.append(current_segment)
                        
                        current_segment = {
                            'segmentId': data[0],
                            'name': data[1],
                            'timestamp': data[2],
                            'createdAt': data[3],
                            'raidName': data[4],
                            'raidIndex': int(data[5]) if data[5].isdigit() else 0,
                            'encounterName': data[6],
                            'encounterIndex': int(data[7]) if data[7].isdigit() else 0,
                            'combatTime': float(data[8]) if data[8].replace('.', '', 1).isdigit() else 0.0,
                            'playerCount': int(data[9]) if data[9].isdigit() else 0,
                            'players': []
                        }
            
            # OGRH_SEGMENT_PLAYER: player data line
            elif 'OGRH_SEGMENT_PLAYER:' in line and current_segment:
                match = re.search(r'OGRH_SEGMENT_PLAYER:\s+(.+)', line)
                if match:
                    data = match.group(1).split('&')
                    
                    if len(data) >= 6:
                        player_entry = {
                            'name': data[0],
                            'class': data[1],
                            'role': data[2],
                            'damage': int(data[3]) if data[3].isdigit() else 0,
                            'effectiveHealing': int(data[4]) if data[4].isdigit() else 0,
                            'totalHealing': int(data[5]) if data[5].isdigit() else 0
                        }
                        current_segment['players'].append(player_entry)
            
            # OGRH_SEGMENT_END: end marker
            elif 'OGRH_SEGMENT_END:' in line and current_segment:
                match = re.search(r'OGRH_SEGMENT_END:\s+(.+)', line)
                if match:
                    segment_id = match.group(1)
                    # Verify segment ID matches
                    if segment_id == current_segment['segmentId']:
                        segments.append(current_segment)
                        current_segment = None
    
    # Add last segment if not closed
    if current_segment:
        segments.append(current_segment)
    
    return segments


def output_importable_format(segments: List[Dict[str, Any]]) -> None:
    """Output segments in format for OGRH Roster CSV import"""
    
    print(f"\nFound {len(segments)} segment(s) in combat log\n")
    
    if not segments:
        print("No segments found. Make sure AutoRank was enabled when segments were created.")
        return
    
    for i, segment in enumerate(segments, 1):
        print("=" * 70)
        print(f"SEGMENT {i}: {segment['name']}")
        print("=" * 70)
        print(f"Timestamp: {segment['createdAt']}")
        print(f"Raid: {segment['raidName']} (Index: {segment['raidIndex']})")
        encounter_name = segment['encounterName'] if segment['encounterName'] else "N/A"
        print(f"Encounter: {encounter_name} (Index: {segment['encounterIndex']})")
        print(f"Combat Time: {segment['combatTime']:.2f}s")
        print(f"Players: {segment['playerCount']}")
        print()
        print("--- IMPORTABLE DATA (Copy everything between START and END) ---")
        print("START_SEGMENT_DATA")
        
        # Output metadata line
        print(f"SEGMENT_META|{segment['name']}|{segment['createdAt']}|{segment['raidName']}|"
              f"{segment['raidIndex']}|{segment['encounterName']}|{segment['encounterIndex']}|"
              f"{segment['combatTime']:.2f}")
        
        # Output player data
        for player in segment['players']:
            print(f"{player['name']}|{player['class']}|{player['role']}|"
                  f"{player['damage']}|{player['effectiveHealing']}|{player['totalHealing']}")
        
        print("END_SEGMENT_DATA")
        print()
    
    print("=" * 70)
    print("EXTRACTION COMPLETE")
    print("=" * 70)
    print()
    print("To import:")
    print("1. Copy the data between START_SEGMENT_DATA and END_SEGMENT_DATA")
    print("2. In-game, open /ogrh roster")
    print("3. Click 'Import Ranking Data'")
    print("4. Paste the copied data into the text box")
    print("5. The segment will be reconstructed and available in Pending Segments")


def main():
    # Parse command line arguments
    if len(sys.argv) > 1:
        combatlog_path = Path(sys.argv[1])
    else:
        combatlog_path = Path("WoWCombatLog.txt")
    
    # Check if file exists
    if not combatlog_path.exists():
        print(f"ERROR: Could not find combat log file: {combatlog_path}")
        print()
        print("Usage: python extract_segments.py [path_to_WoWCombatLog.txt]")
        print('Example: python extract_segments.py "C:\\Games\\TurtleWow\\Logs\\WoWCombatLog.txt"')
        sys.exit(1)
    
    print(f"Parsing combat log: {combatlog_path}")
    
    # Parse segments
    segments = parse_segments_from_combatlog(combatlog_path)
    
    # Output in importable format
    output_importable_format(segments)


if __name__ == '__main__':
    main()
