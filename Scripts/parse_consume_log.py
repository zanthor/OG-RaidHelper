#!/usr/bin/env python3
"""
OG-RaidHelper Consume Tracker - WoWCombatLog Parser
Parses Logs/WoWCombatLog.txt for OGRH_CONSUME_PULL entries
Written by SuperWoW's CombatLogAdd() function
"""

import re
import json
import csv
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any
import argparse
from collections import defaultdict


def parse_combatlog_file(filepath: Path) -> List[Dict[str, Any]]:
    """
    Parse WoWCombatLog.txt for OGRH_CONSUME entries
    
    Format:
    MM/DD HH:MM:SS.mmm  OGRH_CONSUME_PULL: timestamp&date&time&raid&encounter&pullNumber&requester&groupSize
    MM/DD HH:MM:SS.mmm  OGRH_CONSUME_PLAYER: playerName&class&role&score&actualPoints&possiblePoints
    MM/DD HH:MM:SS.mmm  OGRH_CONSUME_PLAYER: ...
    MM/DD HH:MM:SS.mmm  OGRH_CONSUME_END: timestamp
    """
    
    logs = []
    current_entry = None
    
    with filepath.open('r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            
            # OGRH_CONSUME_PULL: header line
            if 'OGRH_CONSUME_PULL:' in line:
                match = re.search(r'(\d+/\d+ \d+:\d+:\d+\.\d+)\s+OGRH_CONSUME_PULL:\s+(.+)', line)
                if match:
                    log_timestamp = match.group(1)
                    data = match.group(2).split('&')
                    
                    if len(data) >= 8:
                        # Save previous entry if exists
                        if current_entry:
                            logs.append(current_entry)
                        
                        current_entry = {
                            'logTimestamp': log_timestamp,
                            'timestamp': int(data[0]) if data[0].isdigit() else 0,
                            'date': data[1],
                            'time': data[2],
                            'raid': data[3],
                            'encounter': data[4],
                            'pullNumber': int(data[5]) if data[5].isdigit() else 0,
                            'requester': data[6],
                            'groupSize': int(data[7]) if data[7].isdigit() else 0,
                            'players': []
                        }
            
            # OGRH_CONSUME_PLAYER: player data line
            elif 'OGRH_CONSUME_PLAYER:' in line and current_entry:
                match = re.search(r'OGRH_CONSUME_PLAYER:\s+(.+)', line)
                if match:
                    data = match.group(1).split('&')
                    
                    if len(data) >= 6:
                        player_entry = {
                            'name': data[0],
                            'class': data[1],
                            'role': data[2],
                            'score': int(data[3]) if data[3].isdigit() else 0,
                            'actualPoints': int(data[4]) if data[4].isdigit() else 0,
                            'possiblePoints': int(data[5]) if data[5].isdigit() else 0
                        }
                        current_entry['players'].append(player_entry)
            
            # OGRH_CONSUME_END: end marker
            elif 'OGRH_CONSUME_END:' in line and current_entry:
                logs.append(current_entry)
                current_entry = None
    
    # Add last entry if not closed
    if current_entry:
        logs.append(current_entry)
    
    return logs


def aggregate_by_player(logs: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """
    Aggregate all tracking records by player name
    Returns player statistics across all pulls
    """
    player_stats = defaultdict(lambda: {
        'pulls': 0,
        'totalScore': 0,
        'totalActualPoints': 0,
        'totalPossiblePoints': 0,
        'scores': [],
        'class': 'Unknown',
        'role': 'UNKNOWN',
        'raids': set(),
        'encounters': set()
    })
    
    for entry in logs:
        for player in entry['players']:
            name = player['name']
            stats = player_stats[name]
            
            stats['pulls'] += 1
            stats['totalScore'] += player['score']
            stats['totalActualPoints'] += player['actualPoints']
            stats['totalPossiblePoints'] += player['possiblePoints']
            stats['scores'].append(player['score'])
            stats['class'] = player['class']
            stats['role'] = player['role']
            stats['raids'].add(entry['raid'])
            stats['encounters'].add(entry['encounter'])
    
    # Calculate averages
    result = {}
    for name, stats in player_stats.items():
        avg_score = stats['totalScore'] / stats['pulls'] if stats['pulls'] > 0 else 0
        min_score = min(stats['scores']) if stats['scores'] else 0
        max_score = max(stats['scores']) if stats['scores'] else 0
        
        result[name] = {
            'name': name,
            'class': stats['class'],
            'role': stats['role'],
            'pulls': stats['pulls'],
            'avgScore': round(avg_score, 1),
            'minScore': min_score,
            'maxScore': max_score,
            'totalActualPoints': stats['totalActualPoints'],
            'totalPossiblePoints': stats['totalPossiblePoints'],
            'raids': sorted(list(stats['raids'])),
            'encounters': sorted(list(stats['encounters']))
        }
    
    return result


def aggregate_by_encounter(logs: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """
    Aggregate tracking records by raid encounter
    Returns encounter statistics
    """
    encounter_stats = defaultdict(lambda: {
        'pulls': 0,
        'totalPlayers': 0,
        'avgGroupSize': 0,
        'scores': [],
        'raid': '',
        'dates': set(),
        'requesters': set()
    })
    
    for entry in logs:
        key = f"{entry['raid']} - {entry['encounter']}"
        stats = encounter_stats[key]
        
        stats['pulls'] += 1
        stats['raid'] = entry['raid']
        stats['totalPlayers'] += entry['groupSize']
        stats['dates'].add(entry['date'])
        stats['requesters'].add(entry['requester'])
        
        # Calculate average score for this pull
        if entry['players']:
            pull_scores = [p['score'] for p in entry['players']]
            avg_pull_score = sum(pull_scores) / len(pull_scores)
            stats['scores'].append(avg_pull_score)
    
    # Calculate final stats
    result = {}
    for key, stats in encounter_stats.items():
        avg_group_size = stats['totalPlayers'] / stats['pulls'] if stats['pulls'] > 0 else 0
        avg_score = sum(stats['scores']) / len(stats['scores']) if stats['scores'] else 0
        
        result[key] = {
            'encounter': key,
            'raid': stats['raid'],
            'pulls': stats['pulls'],
            'avgGroupSize': round(avg_group_size, 1),
            'avgScore': round(avg_score, 1),
            'dates': sorted(list(stats['dates'])),
            'requesters': sorted(list(stats['requesters']))
        }
    
    return result


def export_to_json(logs: List[Dict[str, Any]], output_path: Path):
    """Export logs to JSON format"""
    with output_path.open('w', encoding='utf-8') as f:
        json.dump(logs, f, indent=2, ensure_ascii=False)
    print(f"✓ Exported {len(logs)} entries to {output_path}")


def export_to_csv(logs: List[Dict[str, Any]], output_path: Path):
    """Export logs to CSV format (one row per player per pull)"""
    if not logs:
        print("⚠ No data to export")
        return
    
    with output_path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        
        # Header
        writer.writerow([
            'LogTimestamp', 'Date', 'Time', 'Raid', 'Encounter', 
            'PullNumber', 'Requester', 'GroupSize',
            'PlayerName', 'Class', 'Role', 'Score', 'ActualPoints', 'PossiblePoints'
        ])
        
        # Data rows
        for entry in logs:
            for player in entry['players']:
                writer.writerow([
                    entry['logTimestamp'],
                    entry['date'],
                    entry['time'],
                    entry['raid'],
                    entry['encounter'],
                    entry['pullNumber'],
                    entry['requester'],
                    entry['groupSize'],
                    player['name'],
                    player['class'],
                    player['role'],
                    player['score'],
                    player['actualPoints'],
                    player['possiblePoints']
                ])
    
    print(f"✓ Exported {len(logs)} entries to {output_path}")


def export_player_aggregate_csv(player_stats: Dict[str, Dict[str, Any]], output_path: Path):
    """Export aggregated player statistics to CSV"""
    if not player_stats:
        print("⚠ No player data to export")
        return
    
    with output_path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        
        # Header
        writer.writerow([
            'PlayerName', 'Class', 'Role', 'Pulls', 
            'AvgScore', 'MinScore', 'MaxScore',
            'TotalActualPoints', 'TotalPossiblePoints',
            'Raids', 'Encounters'
        ])
        
        # Sort by average score descending
        sorted_players = sorted(player_stats.values(), key=lambda x: x['avgScore'], reverse=True)
        
        # Data rows
        for player in sorted_players:
            writer.writerow([
                player['name'],
                player['class'],
                player['role'],
                player['pulls'],
                player['avgScore'],
                player['minScore'],
                player['maxScore'],
                player['totalActualPoints'],
                player['totalPossiblePoints'],
                ', '.join(player['raids']),
                ', '.join(player['encounters'])
            ])
    
    print(f"✓ Exported {len(player_stats)} player statistics to {output_path}")


def export_encounter_aggregate_csv(encounter_stats: Dict[str, Dict[str, Any]], output_path: Path):
    """Export aggregated encounter statistics to CSV"""
    if not encounter_stats:
        print("⚠ No encounter data to export")
        return
    
    with output_path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        
        # Header
        writer.writerow([
            'Encounter', 'Raid', 'Pulls', 'AvgGroupSize', 'AvgScore', 'Dates', 'Requesters'
        ])
        
        # Sort by pull count descending
        sorted_encounters = sorted(encounter_stats.values(), key=lambda x: x['pulls'], reverse=True)
        
        # Data rows
        for encounter in sorted_encounters:
            writer.writerow([
                encounter['encounter'],
                encounter['raid'],
                encounter['pulls'],
                encounter['avgGroupSize'],
                encounter['avgScore'],
                ', '.join(encounter['dates']),
                ', '.join(encounter['requesters'])
            ])
    
    print(f"✓ Exported {len(encounter_stats)} encounter statistics to {output_path}")


def print_summary(logs: List[Dict[str, Any]]):
    """Print a summary of the parsed logs"""
    if not logs:
        print("No consume tracking data found.")
        return
    
    print(f"\n{'='*80}")
    print(f"OG-RaidHelper Consume Tracking Summary")
    print(f"{'='*80}")
    print(f"Total Pulls: {len(logs)}")
    
    # Date range
    dates = [entry['date'] for entry in logs if entry['date']]
    if dates:
        print(f"Date Range: {min(dates)} to {max(dates)}")
    
    # Raids and encounters
    raids = set(entry['raid'] for entry in logs)
    encounters = set(entry['encounter'] for entry in logs)
    print(f"Raids: {', '.join(sorted(raids))}")
    print(f"Encounters: {len(encounters)} unique encounters")
    
    # Player statistics
    all_players = set()
    all_scores = []
    for entry in logs:
        for player in entry['players']:
            all_players.add(player['name'])
            all_scores.append(player['score'])
    
    print(f"Unique Players: {len(all_players)}")
    if all_scores:
        avg_score = sum(all_scores) / len(all_scores)
        print(f"Average Score: {avg_score:.1f}% (min: {min(all_scores)}%, max: {max(all_scores)}%)")
    
    print(f"\n{'='*80}")
    
    # Recent pulls
    print(f"\nRecent Pulls (last 5):")
    print(f"{'-'*80}")
    for entry in logs[-5:]:
        print(f"{entry['date']} {entry['time']} | {entry['raid']} - {entry['encounter']}")
        print(f"  Pull #{entry['pullNumber']} by {entry['requester']} ({entry['groupSize']} players)")
        if entry['players']:
            avg_score = sum(p['score'] for p in entry['players']) / len(entry['players'])
            print(f"  Average Score: {avg_score:.1f}%")
        print()


def print_player_leaderboard(player_stats: Dict[str, Dict[str, Any]], top_n: int = 20):
    """Print top players by average score"""
    if not player_stats:
        print("No player statistics available.")
        return
    
    print(f"\n{'='*80}")
    print(f"Top {top_n} Players by Average Score")
    print(f"{'='*80}")
    print(f"{'Rank':<6} {'Player':<20} {'Class':<10} {'Role':<8} {'Pulls':<7} {'Avg':<7} {'Min':<7} {'Max':<7}")
    print(f"{'-'*80}")
    
    sorted_players = sorted(player_stats.values(), key=lambda x: x['avgScore'], reverse=True)
    
    for i, player in enumerate(sorted_players[:top_n], 1):
        print(f"{i:<6} {player['name']:<20} {player['class']:<10} {player['role']:<8} "
              f"{player['pulls']:<7} {player['avgScore']:<7.1f} {player['minScore']:<7} {player['maxScore']:<7}")


def main():
    parser = argparse.ArgumentParser(
        description='Parse OG-RaidHelper consume tracking logs from WoWCombatLog.txt'
    )
    parser.add_argument(
        'logfile',
        nargs='?',
        type=Path,
        default=Path('WoWCombatLog.txt'),
        help='Path to WoWCombatLog.txt (default: WoWCombatLog.txt in current folder)'
    )
    parser.add_argument(
        '-o', '--output',
        type=Path,
        help='Output directory for exports (default: current directory)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Export to JSON format'
    )
    parser.add_argument(
        '--csv',
        action='store_true',
        help='Export to CSV format'
    )
    parser.add_argument(
        '--aggregate',
        action='store_true',
        help='Export aggregated player and encounter statistics'
    )
    parser.add_argument(
        '--top',
        type=int,
        default=20,
        help='Number of top players to show in leaderboard (default: 20)'
    )
    parser.add_argument(
        '--quiet',
        action='store_true',
        help='Suppress summary output'
    )
    
    args = parser.parse_args()
    
    # Check if log file exists
    if not args.logfile.exists():
        print(f"✗ Error: Log file not found: {args.logfile}")
        return 1
    
    # Parse the log file
    print(f"Parsing {args.logfile}...")
    logs = parse_combatlog_file(args.logfile)
    
    if not logs:
        print("⚠ No OGRH_CONSUME entries found in log file.")
        return 0
    
    # Print summary unless quiet
    if not args.quiet:
        print_summary(logs)
    
    # Generate aggregated statistics
    player_stats = aggregate_by_player(logs)
    encounter_stats = aggregate_by_encounter(logs)
    
    if not args.quiet:
        print_player_leaderboard(player_stats, args.top)
    
    # Export if requested
    output_dir = args.output or Path('.')
    output_dir.mkdir(parents=True, exist_ok=True)
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    if args.json:
        export_to_json(logs, output_dir / f'consume_tracking_{timestamp}.json')
    
    if args.csv:
        export_to_csv(logs, output_dir / f'consume_tracking_{timestamp}.csv')
    
    if args.aggregate:
        export_player_aggregate_csv(player_stats, output_dir / f'consume_player_stats_{timestamp}.csv')
        export_encounter_aggregate_csv(encounter_stats, output_dir / f'consume_encounter_stats_{timestamp}.csv')
    
    # Default: export aggregates if no format specified
    if not (args.json or args.csv or args.aggregate):
        export_player_aggregate_csv(player_stats, output_dir / f'consume_player_stats_{timestamp}.csv')
        export_encounter_aggregate_csv(encounter_stats, output_dir / f'consume_encounter_stats_{timestamp}.csv')
    
    return 0


if __name__ == '__main__':
    exit(main())
