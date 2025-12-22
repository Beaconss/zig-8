const std = @import("std");

const memory_size: u32 = 0x1000;

pub const Chip8 = struct {
    memory: [memory_size]u8,
};

pub fn initializeChip8() ?Chip8
{
    var chip8: Chip8 = .{
        .memory = undefined,
    };
    const path = getRomPathFromArgs() orelse return null;
    fillMem(path, &chip8.memory) orelse return null;
    return chip8;
}

fn getRomPathFromArgs() ?[]const u8
{
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator(); 

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const rom_path = args.next() orelse {
        std.debug.print("Put rom path as second cli argument\n", .{});
        return null;
    };
    return rom_path;
}

fn fillMem(rom_path: []const u8, memory: []u8) ?void
{
    const file = std.fs.cwd().openFile(rom_path, .{}) catch |err| {
        std.log.err("Failed to open file: {s}", .{@errorName(err)});
        return null;
    };
    defer file.close();

    var file_reader = file.reader(memory);
    var reader = &file_reader.interface;

    reader.discardAll(0x200) catch |err| {
        if(err == error.EndOfStream) std.debug.print("File too small\n", .{});
        return null;
    };
    reader.fillMore() catch return null;

    return;
}
