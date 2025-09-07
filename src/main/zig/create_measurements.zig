const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const fmt = std.fmt;
const process = std.process;
const time = std.time;
const Random = std.Random;

const MAX_STATIONS = 10000;
const BATCH_SIZE = 10000;
const WRITE_BUFFER_SIZE = 1024 * 1024; // 1MB write buffer

const Station = struct {
    name: []const u8,
};

const Xoroshiro128 = struct {
    s: [2]u64,

    pub fn init(seed: u64) Xoroshiro128 {
        var s = Xoroshiro128{ .s = .{ seed, seed ^ 0xDEADBEEF } };
        // Warm up the generator
        _ = s.next();
        _ = s.next();
        return s;
    }

    pub fn next(self: *Xoroshiro128) u64 {
        const s0 = self.s[0];
        var s1 = self.s[1];
        const result = s0 +% s1;

        s1 ^= s0;
        self.s[0] = rotl(s0, 24) ^ s1 ^ (s1 << 16);
        self.s[1] = rotl(s1, 37);

        return result;
    }

    fn rotl(x: u64, k: u6) u64 {
        return (x << k) | (x >> @as(u6, @intCast(64 - @as(u7, k))));
    }

    pub fn random(self: *Xoroshiro128) Random {
        return Random.init(self, fill);
    }

    fn fill(self: *Xoroshiro128, buf: []u8) void {
        var i: usize = 0;
        while (i + 8 <= buf.len) : (i += 8) {
            const val = self.next();
            @memcpy(buf[i..][0..8], &mem.toBytes(val));
        }
        if (i < buf.len) {
            const val = self.next();
            const bytes = mem.toBytes(val);
            @memcpy(buf[i..], bytes[0 .. buf.len - i]);
        }
    }
};

fn readWeatherStations(allocator: mem.Allocator) ![]Station {
    const file = try fs.cwd().openFile("data/weather_stations.csv", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);
    
    _ = try file.read(contents);

    var stations = std.ArrayList(Station).init(allocator);
    defer stations.deinit();

    var lines = mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        
        if (mem.indexOfScalar(u8, line, ';')) |idx| {
            const name = try allocator.dupe(u8, line[0..idx]);
            try stations.append(Station{ .name = name });
        }
    }

    return try stations.toOwnedSlice();
}

fn formatBytes(bytes: u64) void {
    const units = [_][]const u8{ "B", "KiB", "MiB", "GiB" };
    var size = @as(f64, @floatFromInt(bytes));
    var unit_idx: usize = 0;
    
    while (size >= 1024.0 and unit_idx < units.len - 1) : (unit_idx += 1) {
        size /= 1024.0;
    }
    
    std.debug.print("{d:.1} {s}", .{ size, units[unit_idx] });
}

fn formatElapsedTime(nanos: u64) void {
    const seconds = @as(f64, @floatFromInt(nanos)) / 1_000_000_000.0;
    
    if (seconds < 60) {
        std.debug.print("{d:.3} seconds", .{seconds});
    } else if (seconds < 3600) {
        const minutes = @as(u64, @intFromFloat(seconds / 60));
        const secs = @as(u64, @intFromFloat(seconds)) % 60;
        std.debug.print("{} minutes {} seconds", .{ minutes, secs });
    } else {
        const hours = @as(u64, @intFromFloat(seconds / 3600));
        const remainder = @as(u64, @intFromFloat(seconds)) % 3600;
        const minutes = remainder / 60;
        const secs = remainder % 60;
        if (minutes == 0) {
            std.debug.print("{} hours {} seconds", .{ hours, secs });
        } else {
            std.debug.print("{} hours {} minutes {} seconds", .{ hours, minutes, secs });
        }
    }
}

fn estimateFileSize(stations: []const Station, num_rows: u64) void {
    var total_name_bytes: u64 = 0;
    for (stations) |station| {
        total_name_bytes += station.name.len;
    }
    
    const avg_name_bytes = @as(f64, @floatFromInt(total_name_bytes)) / @as(f64, @floatFromInt(stations.len));
    const avg_temp_bytes = 4.4; // Average temperature string length
    const avg_line_length = avg_name_bytes + avg_temp_bytes + 2; // +2 for ';' and '\n'
    
    const estimated_size = @as(u64, @intFromFloat(@as(f64, @floatFromInt(num_rows)) * avg_line_length));
    
    std.debug.print("Estimated max file size is: ", .{});
    formatBytes(estimated_size);
    std.debug.print(".\n", .{});
}

fn generateMeasurements(_: mem.Allocator, stations: []const Station, num_rows: u64) !void {
    const start_time = time.nanoTimestamp();
    
    // Pre-select 10k stations for efficiency
    var rng = Xoroshiro128.init(@as(u64, @intCast(time.timestamp())));
    var random = rng.random();
    
    const station_subset_size = @min(10000, stations.len);
    var station_subset: [MAX_STATIONS]Station = undefined;
    
    // Fill subset with random stations
    for (0..station_subset_size) |i| {
        const idx = random.uintLessThan(usize, stations.len);
        station_subset[i] = stations[idx];
    }
    
    const file = try fs.cwd().createFile("measurements.txt", .{});
    defer file.close();
    
    // Use buffered writer for better I/O performance
    var buffered_writer = io.bufferedWriter(file.writer());
    const writer = buffered_writer.writer();
    
    const chunks = num_rows / BATCH_SIZE;
    var progress: u64 = 0;
    
    std.debug.print("Building test data...\n", .{});
    
    // Pre-allocate line buffer
    var line_buf: [256]u8 = undefined;
    
    for (0..chunks) |chunk| {
        for (0..BATCH_SIZE) |_| {
            const station_idx = random.uintLessThan(usize, station_subset_size);
            const station = station_subset[station_idx];
            
            // Generate temperature between -99.9 and 99.9
            const temp_raw = random.float(f64) * 199.8 - 99.9;
            
            // Format line efficiently
            const line = try fmt.bufPrint(&line_buf, "{s};{d:.1}\n", .{ station.name, temp_raw });
            try writer.writeAll(line);
        }
        
        // Update progress bar
        const new_progress = ((chunk + 1) * 100) / chunks;
        if (new_progress != progress) {
            progress = new_progress;
            const bars = progress / 2;
            
            std.debug.print("\r[", .{});
            for (0..bars) |_| {
                std.debug.print("=", .{});
            }
            for (bars..50) |_| {
                std.debug.print(" ", .{});
            }
            std.debug.print("] {}%", .{progress});
        }
    }
    
    // Handle remaining rows
    const remaining = num_rows % BATCH_SIZE;
    for (0..remaining) |_| {
        const station_idx = random.uintLessThan(usize, station_subset_size);
        const station = station_subset[station_idx];
        
        const temp_raw = random.float(f64) * 199.8 - 99.9;
        const line = try fmt.bufPrint(&line_buf, "{s};{d:.1}\n", .{ station.name, temp_raw });
        try writer.writeAll(line);
    }
    
    try buffered_writer.flush();
    std.debug.print("\n", .{});
    
    const end_time = time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    // Get actual file size
    const stat = try file.stat();
    
    std.debug.print("Test data successfully written to 1brc/data/measurements.txt\n", .{});
    std.debug.print("Actual file size: ", .{});
    formatBytes(stat.size);
    std.debug.print("\n", .{});
    std.debug.print("Elapsed time: ", .{});
    formatElapsedTime(elapsed);
    std.debug.print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);
    
    if (args.len != 2) {
        std.debug.print("Usage: {s} <positive integer number of records to create>\n", .{args[0]});
        std.debug.print("       You can use underscore notation for large numbers.\n", .{});
        std.debug.print("       For example: 1_000_000_000 for one billion\n", .{});
        return;
    }
    
    const num_rows_str = mem.replaceOwned(u8, allocator, args[1], "_", "") catch args[1];
    defer if (num_rows_str.ptr != args[1].ptr) allocator.free(num_rows_str);
    
    const num_rows = fmt.parseInt(u64, num_rows_str, 10) catch {
        std.debug.print("Error: Invalid number of rows\n", .{});
        return;
    };
    
    if (num_rows == 0) {
        std.debug.print("Error: Number of rows must be positive\n", .{});
        return;
    }
    
    const stations = try readWeatherStations(allocator);
    defer {
        for (stations) |station| {
            allocator.free(station.name);
        }
        allocator.free(stations);
    }
    
    estimateFileSize(stations, num_rows);
    try generateMeasurements(allocator, stations, num_rows);
    std.debug.print("Test data build complete.\n", .{});
}