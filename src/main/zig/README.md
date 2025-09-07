# Zig Measurements Generator

Fast data generator for the 1BRC challenge.

## Build

```bash
zig build-exe -O ReleaseFast create_measurements.zig
```

## Usage

```bash
./create_measurements 1000000000  # Generate 1B rows
```

## Performance

- **1 million rows**: ~0.1 seconds
- **1 billion rows**: ~2 minutes

## Optimizations

- Xoroshiro128+ PRNG (faster than Mersenne Twister)
- 1MB buffered I/O to minimize syscalls
- Pre-allocated buffers, no allocations in hot path
- Station subset caching (10k stations like Python)
- Compile-time optimizations via ReleaseFast

## Requirements

- Zig 0.11.0+
- `data/weather_stations.csv` file