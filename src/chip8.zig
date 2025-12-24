const std = @import("std");
const input = @import("input.zig");

pub const Chip8 = struct {
    memory: [memory_size]u8,
    pc: u16,
    display: [display_width * display_height]u8,
    v: [16]u8,
    i: u16,
    stack: [16]u16,
    sp: u16,
    delay_timer: u8,
    sound_timer: u8,
    rand_engine: std.Random.Xoshiro256,

    const memory_size = 0x1000;
    const start_address = 0x200;
    pub const display_width = 64;
    pub const display_height = 32;
    pub fn decodeAndExecute(self: *Chip8) void
    {
        const ir: u16 = (@as(u16, self.memory[self.pc]) << 8) | self.memory[self.pc + 1];
        self.pc += 2;
        const x: u4 = @intCast((ir & 0x0F00) >> 8);
        const y: u4 = @intCast((ir & 0x00F0) >> 4);
        const n: u4 = @intCast(ir & 0x000F);
        const nn: u8 = @intCast((ir & 0x00FF));
        const nnn: u12 = @intCast((ir & 0x0FFF));
        switch(ir & 0xF000)
        {
            0x0000 => {
                if(ir & 0xF == 0xE)
                {
                    self.sp -= 1;
                    self.pc = self.stack[self.sp];
                }
                else @memset(&self.display, 0);},
            0x1000 => {
                self.pc = nnn;
            },
            0x2000 => {
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = nnn;
            },
            0x3000 => {
                if(self.v[x] == nn) self.pc += 2;
            },
            0x4000 => {
                if(self.v[x] != nn) self.pc += 2;
            },
            0x5000 => {
                if(self.v[x] == self.v[y]) self.pc += 2;
            },
            0x6000 => {
                self.v[x] = nn;
            },
            0x7000 => {
                self.v[x] +%= nn;
            },
            0x8000 => {
                switch(ir & 0xF)
                {
                    0 => {
                        self.v[x] = self.v[y];
                    },
                    1 => {
                        self.v[x] |= self.v[y];
                    },
                    2 => {
                        self.v[x] &= self.v[y];
                    },
                    3 => {
                        self.v[x] ^= self.v[y];
                    },
                    4 => {
                        self.v[0xF] = @intFromBool(@as(u16, self.v[x] +% self.v[y]) > 0xFF);
                        self.v[x] +%= self.v[y];
                    },
                    5 => {
                        self.v[0xF] = @intFromBool(self.v[x] > self.v[y]);
                        self.v[x] = self.v[x] -% self.v[y];
                    },
                    6 => {
                        //quirk reminder
                        self.v[0xF] = self.v[x] & 1;
                        self.v[x] >>= 1;
                    },
                    7 => {
                        self.v[0xF] = @intFromBool(self.v[y] > self.v[x]);
                        self.v[x] = self.v[y] -% self.v[x];
                    },
                    0xE => {
                        //quirk reminder
                        self.v[0xF] = @intFromBool((self.v[x] & 0x80) > 0);
                        self.v[x] <<= 1;
                    },
                    else => {invalidOpcode();},
                }
            },
            0x9000 => {
                if(self.v[x] != self.v[y]) self.pc += 2;
            },
            0xA000 => {
                self.i = nnn;
            },
            0xB000 => {
                //quirk reminder
                self.pc = nnn + self.v[x];
            },
            0xC000 => {
                self.v[x] = self.rand_engine.random().int(u8);
            },
            0xD000 => {
                self.v[0xF] = 0;
                var yCoord: u16 = self.v[y] % display_height;
                for(0..n) |i|
                {
                    const sprite_row = self.memory[self.i + i];
                    var xCoord = self.v[x] % display_width;
                    for(0..8) |j|
                    {
                        const coord = xCoord + yCoord * display_width;
                        const pixel = (sprite_row & (@as(u8, @intCast(0x80)) >> @intCast(j))) > 0;
                        if(pixel)
                        {
                            if(self.display[coord] > 0)
                            {
                                self.display[coord] = 0;
                                self.v[0xF] = 1;
                            }
                            else self.display[coord] = 0xFF;
                        }
                        xCoord += 1;
                        if(xCoord > display_width) break;
                    }
                    yCoord += 1;
                    if(yCoord > display_height) break;
                }
                return;
            },
            0xE000 => {
                if(ir & 0xF == 0xE)
                {
                    if(input.keyPressed(self.v[x])) self.pc += 2;
                }
                else if(ir & 0xF == 1)
                {
                    if(!input.keyPressed(self.v[x])) self.pc += 2;
                }
            },
            0xF000 => {
                switch(ir & 0xF)
                {
                    0x3 => {
                        self.memory[self.i] = self.v[x] / 100;
                        self.memory[self.i + 1] = (self.v[x] % 100) / 10;
                        self.memory[self.i + 2] = self.v[x] % 10;
                    },
                    0x5 => {
                        if(ir & 0xF0 == 0x10) self.delay_timer = self.v[x]
                        else if(ir & 0xF0 == 0x50)
                        {
                            for(0..x +% 1) |i| self.memory[self.i + i] = self.v[i];
                        }
                        else if(ir & 0xF0 == 0x60)
                        {
                            for(0..x +% 1) |i| self.v[i] = self.memory[self.i + i];
                        }
                    },
                    0x7 => {
                        self.v[x] = self.delay_timer;
                    },
                    0x8 => {
                        self.sound_timer = self.v[x];
                    },
                    0x9 => {
                        //self.i = fontset_address[self.v[x]];
                    },
                    0xA => {
                        const key = input.anyKeyPressed() orelse {
                            self.pc -= 2;
                            return;
                        };
                        self.v[x] = key;
                    },
                    0xE => {
                        if(@as(u16, self.i + self.v[x]) >= memory_size) self.v[0xF] = 1;
                        self.i +%= self.v[x];
                    },
                    else => {invalidOpcode();},
                }
            },
            else => {invalidOpcode();},
        }
        return;
    }

    fn invalidOpcode() void
    {
        std.debug.print("Invalid opcode\n", .{});
    }
};

pub fn initializeInstance() ?Chip8
{
    var chip8: Chip8 = .{
        .memory = std.mem.zeroes([Chip8.memory_size]u8),
        .pc = Chip8.start_address,
        .display = std.mem.zeroes([Chip8.display_width * Chip8.display_height]u8),
        .v = undefined,
        .i = 0,
        .stack = undefined,
        .sp = 0,
        .delay_timer = 0,
        .sound_timer = 0,
        .rand_engine = undefined,
    };

    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
        std.log.err("Failed to initialize random engine seed: {s}", .{@errorName(err)});
        return null;
    };
    chip8.rand_engine = std.Random.DefaultPrng.init(seed);

    fillMem(getRomPathFromArgs() orelse return null, &chip8.memory) orelse return null;
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
