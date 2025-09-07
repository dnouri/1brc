#!/usr/bin/env python3
"""Generate results.md from benchmark results."""

import sys
from datetime import datetime
import os

def main():
    if len(sys.argv) != 3:
        print("Usage: generate_results.py <results_file> <output_file>", file=sys.stderr)
        sys.exit(1)
    
    results_file = sys.argv[1]
    output_file = sys.argv[2]
    
    # Read results
    results = []
    if os.path.exists(results_file):
        with open(results_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    parts = line.split('|')
                    if len(parts) == 4:
                        results.append({
                            'name': parts[0],
                            'min': parts[1],
                            'mean': parts[2],
                            'max': parts[3]
                        })
    
    # Get system info
    java_version = os.popen("java -version 2>&1 | head -1").read().strip()
    cpu_info = os.popen("lscpu | grep 'Model name:' | cut -d':' -f2").read().strip()
    if not cpu_info:
        cpu_info = "Unknown"
    
    # Get test data size
    data_size = "Unknown"
    if os.path.exists("measurements.txt"):
        size_bytes = os.path.getsize("measurements.txt")
        size_mb = size_bytes / (1024 * 1024)
        # Count lines (approximate for large files)
        if size_mb < 100:  # Only count lines for smaller files
            with open("measurements.txt", 'r') as f:
                line_count = sum(1 for _ in f)
            data_size = f"{line_count:,} rows ({size_mb:.1f} MiB)"
        else:
            # Estimate based on typical row size
            gb = size_bytes / (1024 * 1024 * 1024)
            if gb > 1:
                data_size = f"~{int(size_mb * 66000):,} rows ({gb:.1f} GiB)"
            else:
                data_size = f"~{int(size_mb * 66000):,} rows ({size_mb:.1f} MiB)"
    
    # Generate markdown
    markdown = f"""# 1BRC Performance Results

**Date**: {datetime.now().strftime('%Y-%m-%d %H:%M')}  
**CPU**: {cpu_info}  
**Java**: {java_version if java_version else 'OpenJDK 17'}  
**Test Data**: {data_size}

| Implementation | Min (s) | Mean (s) | Max (s) |
|----------------|---------|----------|---------|
"""
    
    # Sort results by min time
    results.sort(key=lambda x: float(x['min']) if x['min'] != 'ERROR' else float('inf'))
    
    # Add results to table
    for r in results:
        markdown += f"| {r['name']} | {r['min']} | {r['mean']} | {r['max']} |\n"
    
    if not results:
        markdown += "| *No results yet* | - | - | - |\n"
    
    markdown += """
See `make help` for usage instructions.
"""
    
    # Write to file
    with open(output_file, 'w') as f:
        f.write(markdown)
    
    print(f"✓ Generated {output_file} with {len(results)} results")

if __name__ == "__main__":
    main()