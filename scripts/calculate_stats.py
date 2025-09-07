#!/usr/bin/env python3
"""Calculate min and mean from timing results."""

import sys
import statistics

def main():
    if len(sys.argv) != 2:
        print("Usage: calculate_stats.py <timing_file>", file=sys.stderr)
        sys.exit(1)
    
    with open(sys.argv[1], 'r') as f:
        lines = f.readlines()
    
    # First line is implementation name
    impl_name = lines[0].strip()
    
    # Rest are timing values
    times = []
    for line in lines[1:]:
        line = line.strip()
        if line:
            try:
                times.append(float(line))
            except ValueError:
                pass  # Skip non-numeric lines
    
    if not times:
        print(f"{impl_name}|ERROR|ERROR|ERROR", file=sys.stdout)
        return
    
    min_time = min(times)
    mean_time = statistics.mean(times)
    max_time = max(times)
    
    # Output format: implementation|min|mean|max
    print(f"{impl_name}|{min_time:.3f}|{mean_time:.3f}|{max_time:.3f}")

if __name__ == "__main__":
    main()