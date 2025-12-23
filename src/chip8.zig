const std = @import("std");

pub const Chip8 = struct {
    memory: [memory_size]u8,
    pc: u16,
    display: [display_x_size * display_y_size]u8,
    v: [16]u8,
    i: u16,
    stack: [16]u16,
    sp: u16,
    delay_timer: u8,
    sound_timer: u8,

    const memory_size = 0x1000;
    const start_address = 0x200;
    pub const display_x_size = 64;
    pub const display_y_size = 32;
    pub fn decodeAndExecute(self: *Chip8) bool
    {
        const ir: u16 = (@as(u16, self.memory[self.pc]) << 8) | self.memory[self.pc + 1];
        self.pc += 2;
        if(self.pc >= self.memory.len) self.pc = start_address;
        const x: u4 = @intCast((ir & 0xF0) >> 4);
        const y: u4 = @intCast((ir & 0xF00) >> 8);
        const n: u4 = @intCast((ir & 0xF000) >> 12);
        const nn: u8 = @intCast((ir & 0xFF00) >> 8);
        const nnn: u12 = @intCast((ir & 0xFFF0) >> 4);
        switch(ir & 0xF000)
        {
            0x0 => {
                @memset(&self.display, 0);
            },
            0x1000 => {
                self.pc = nnn;
            },
            0x6000 => {
                self.v[x] = nn;
            },
            0x7000 => {
                self.v[x] +%= nn;
            },
            0xA000 => {
                self.i = nnn;
            },
            0xD000 => {
                self.v[0xF] = 0;
                const xCoord = self.v[x] % display_x_size;
                const yCoord = self.v[y] % display_y_size;
                var coord: u16 = xCoord + yCoord * display_y_size;
                for(0..n) |i|
                {
                    const sprite_row: u8 = self.memory[self.i + i];
                    for(0..8) |j|
                    {
                        if(((j + coord) - display_x_size * i) > (display_x_size - 1)) break;
                        const pixel: bool = (sprite_row & (@as(u8, 1) << @intCast(j))) > 0;
                        if(self.display[j] == 0xFF and pixel == true)
                        {
                            self.display[j] = 0;
                            self.v[0xF] = 1;
                        }
                        else if(self.display[j] == 0 and pixel == false) self.display[j] = 0xFF;
                    }
                    coord += display_y_size;
                    if(coord > self.display.len) break;
                }
                return true;
            },
            else => {}
        }
        return false;
    }
};

pub fn initializeChip8() ?Chip8
{
    var chip8: Chip8 = .{
        .memory = std.mem.zeroes([Chip8.memory_size]u8),
        .pc = Chip8.start_address,
        .display = std.mem.zeroes([Chip8.display_x_size * Chip8.display_y_size]u8),
        .v = undefined,
        .i = 0,
        .stack = undefined,
        .sp = 0,
        .delay_timer = 0,
        .sound_timer = 0,
    };
    fillMem(getRomPathFromArgs() orelse return null, &chip8.memory) orelse return null;
    //for(chip8.memory) |a| std.debug.print("{x} ", .{a});
    return chip8;
}

fn getRomPathFromArgs() ?[]const u8
{
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator(); 

    var args = std.process.argsWithAllocator(allocator) catch |err| {
        std.log.err("Failed to read arg: {s}", .{@errorName(err)});
        return null;
    };
    defer args.deinit();
    _ = args.next();
    const rom_path = args.next() orelse {
        std.debug.print("Put rom path as second cli argument\n", .{});
        return null;
    };
    return rom_path;
}

fn fillMem(rom_path: []const u8, memory: *[Chip8.memory_size]u8) ?void
{
    const file = std.fs.cwd().openFile(rom_path, .{}) catch |err| {
        std.log.err("Failed to open file: {s}", .{@errorName(err)});
        return null;
    };
    defer file.close();

    var buffer: [Chip8.memory_size]u8 = undefined;
    var file_reader = file.reader(&buffer);
    for(Chip8.start_address..Chip8.memory_size) |i|
    {
        const byte = file_reader.interface.peekByte() catch break;
        memory.*[i] = byte;
        file_reader.interface.toss(1);
    }
    return;
}
