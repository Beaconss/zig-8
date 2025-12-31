const std = @import("std");
const c = @cImport({@cInclude("SDL3/SDL.h");});

pub const Chip8 = struct {
    memory: [memory_size]u8,
    pc: u16,
    display: [display_width * display_height]u8,
    v: [16]u8, //registers
    i: u16,
    stack: [16]u16,
    sp: u16,
    delay_timer: u8,
    sound_timer: u8,
    key_pressed: ?u8, //used in 0xFX0A
    beep_sound: *c.SDL_AudioStream,
    rand_engine: std.Random.Xoshiro256,

    pub fn initialize() ?Chip8
    {
        var chip8: Chip8 = .{
            .memory = undefined,
            .pc = Chip8.start_address,
            .display = undefined,
            .v = undefined,
            .i = 0,
            .stack = undefined,
            .sp = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .key_pressed = null,
            .beep_sound = blk: {
                const spec: c.SDL_AudioSpec = .{.format = c.SDL_AUDIO_F32, .channels = 1, .freq = 44100};
                const stream = c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, fillAudio, null) orelse {
                    c.SDL_Log("Failed to create audio stream, %s", c.SDL_GetError());
                    return null;
                };
                break: blk stream;
            },
            .rand_engine = blk: {
                var seed: u64 = undefined;
                std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
                    std.log.err("Failed to initialize random engine seed: {s}", .{@errorName(err)});
                    return null;
                };
                const prng= std.Random.DefaultPrng.init(seed);
                break: blk prng;
            },
        };
        @memset(&chip8.memory, 0);
        @memset(&chip8.display, 0);
        @memset(&chip8.v, 0);
        @memset(&chip8.stack, 0);

        for(0..fontset.len) |i| chip8.memory[i] = fontset[i];
        return chip8;
    }

    pub fn deInitialize(self: *Chip8) void
    {
        c.SDL_DestroyAudioStream(self.beep_sound);
    }

    pub fn loadRom(self: *Chip8, rom_path: [*c]const u8) ?void
    {
        self.reset();
        const file = std.fs.cwd().openFileZ(rom_path, .{}) catch |err| {
            std.log.err("Failed to open file: {s}", .{@errorName(err)});
            return null;
        };
        defer file.close();

        var buffer: [Chip8.memory_size]u8 = undefined;
        var file_reader = file.reader(&buffer);
        for(Chip8.start_address..Chip8.memory_size) |i|
        {
            const byte = file_reader.interface.peekByte() catch break;
            self.memory[i] = byte;
            file_reader.interface.toss(1);
        }
        return;
    }

    pub fn timerCycle(self: *Chip8) void
    {
        if(self.delay_timer > 0) self.delay_timer -= 1;
        if(self.sound_timer > 0)
        {
            self.sound_timer -= 1;
            if(self.sound_timer == 0) _ = c.SDL_PauseAudioStreamDevice(self.beep_sound);
        }
    }

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
                        self.v[0xF] = 0;
                    },
                    2 => {
                        self.v[x] &= self.v[y];
                        self.v[0xF] = 0;
                    },
                    3 => {
                        self.v[x] ^= self.v[y];
                        self.v[0xF] = 0;
                    },
                    4 => {
                        const old_vx = self.v[x];
                        self.v[x] +%= self.v[y];
                        self.v[0xF] = @intFromBool((@as(u16, old_vx) +% @as(u16, self.v[y])) > 0xFF);
                    },
                    5 => {
                        const old_vx = self.v[x];
                        self.v[x] -%= self.v[y];
                        self.v[0xF] = @intFromBool(old_vx >= self.v[y]);
                    },
                    6 => {
                        //quirk reminder
                        self.v[x] = self.v[y];
                        const bit_out = self.v[x] & 1;
                        self.v[x] >>= 1;
                        self.v[0xF] = bit_out;
                    },
                    7 => {
                        const old_vx = self.v[x];
                        self.v[x] = self.v[y] -% self.v[x];
                        self.v[0xF] = @intFromBool(self.v[y] >= old_vx);
                    },
                    0xE => {
                        //quirk reminder
                        self.v[x] = self.v[y];
                        const bit_out = @intFromBool((self.v[x] & 0x80) > 0);
                        self.v[x] <<= 1;
                        self.v[0xF] = bit_out;
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
                self.pc = nnn + self.v[0];
            },
            0xC000 => {
                self.v[x] = self.rand_engine.random().int(u8) & nn;
            },
            0xD000 => {
                self.v[0xF] = 0;
                var yCoord: u16 = self.v[y] % display_height;
                for(0..n) |i|
                {
                    if(yCoord >= display_height) break;
                    const sprite_row = self.memory[self.i + i];
                    var xCoord = self.v[x] % display_width;
                    for(0..8) |j|
                    {
                        if(xCoord >= display_width) break;
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
                    }
                    yCoord += 1;
                }
                return;
            },
            0xE000 => {
                if(ir & 0xF == 0xE)
                {
                    if(keyPressed(self.v[x] & 0xF)) self.pc += 2;
                }
                else if(ir & 0xF == 1)
                {
                    if(!keyPressed(self.v[x] & 0xF)) self.pc += 2;
                }
            },
            0xF000 => {
                switch(ir & 0xFF)
                {
                    0x07 => {
                        self.v[x] = self.delay_timer;
                    },
                    0x0A => {
                        if(self.key_pressed == null)
                        {
                            self.key_pressed = anyKeyPressed();
                            if(self.key_pressed == null) self.pc -= 2;
                            return;
                        }
                        else if(keyPressed(self.key_pressed orelse unreachable))
                        {
                            self.pc -= 2;
                            return;
                        }
                        self.v[x] = self.key_pressed orelse unreachable;
                        self.key_pressed = null;
                    },
                    0x15 => {
                        self.delay_timer = self.v[x];
                    },
                    0x18 => {
                        self.sound_timer = self.v[x];
                        if(self.sound_timer > 0) _ = c.SDL_ResumeAudioStreamDevice(self.beep_sound)
                        else _ = c.SDL_PauseAudioStreamDevice(self.beep_sound);
                    },
                    0x1E => {
                        self.i +%= self.v[x];
                    },
                    0x29 => {
                        self.i = fontset_addresses[self.v[x] & 0xF];
                    },
                    0x33 => {
                        self.memory[self.i] = self.v[x] / 100;
                        self.memory[self.i + 1] = (self.v[x] % 100) / 10;
                        self.memory[self.i + 2] = self.v[x] % 10;
                    },
                    0x55 => {
                        const upto: u8 = x;
                        for(0..upto + 1) |i|
                        {
                            self.memory[self.i] = self.v[i];
                            self.i += 1;
                        }
                    },
                    0x65 => {
                        const upto: u8 = x;
                        for(0..upto + 1) |i|
                        {
                            self.v[i] = self.memory[self.i];
                            self.i += 1;
                        }
                    },
                    else => {invalidOpcode();},
                }
            },
            else => {invalidOpcode();},
        }
        return;
    }

    pub const display_width = 64;
    pub const display_height = 32;

    fn reset(self: *Chip8) void
    {
        for(Chip8.start_address..Chip8.memory_size) |i| self.memory[i] = 0;
        self.pc = Chip8.start_address;
        @memset(&self.display, 0);
        @memset(&self.v, 0);
        self.i = 0;
        @memset(&self.stack, 0);
        self.sp = 0;
        self.delay_timer = 0;
        self.sound_timer = 0;
        self.key_pressed = null;
    }

    fn invalidOpcode() void
    {
        std.debug.print("Invalid opcode\n", .{});
    }

    fn fillAudio(_: ?*anyopaque, stream: ?*c.SDL_AudioStream, needed_amount: c_int, _: c_int) callconv(.c) void
    {
        const oscillator = struct {
            var step: f32 = 0.0;
            var samples: [4096]f32 = undefined;
            const step_size = (2 * std.math.pi) / (44100.0 / 440.0);
            const volume = 0.6;
        };
        for(0..@intCast(needed_amount)) |i|
        {
            oscillator.samples[i] = @sin(oscillator.step) * oscillator.volume;
            oscillator.step += oscillator.step_size;
        }
        _ = c.SDL_PutAudioStreamData(stream, &oscillator.samples, needed_amount * 4);
    }

    fn keyPressed(key: u8) bool
    {
        return c.SDL_GetKeyboardState(null)[@intCast(keys[key])];
    }

    fn anyKeyPressed() ?u8
    {
        for(0..keys.len) |i| if(keyPressed(@intCast(i))) return @intCast(i);
        return null;
    }

    const audio_frequency = 44100;
 
    const memory_size = 0x1000;
    const start_address = 0x200;
    const fontset = [_]u8 {
        0xF0, 0x90, 0x90, 0x90, 0xF0, //0
        0x20, 0x60, 0x20, 0x20, 0x70, //1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, //2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, //3
        0x90, 0x90, 0xF0, 0x10, 0x10, //4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, //5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, //6
        0xF0, 0x10, 0x20, 0x40, 0x40, //7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, //8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, //9
        0xF0, 0x90, 0xF0, 0x90, 0x90, //A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, //B
        0xF0, 0x80, 0x80, 0x80, 0xF0, //C
        0xE0, 0x90, 0x90, 0x90, 0xE0, //D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, //E
        0xF0, 0x80, 0xF0, 0x80, 0x80, //F
    };
    const fontset_addresses = [_]u8 {
        0x0, 0x5, 0xA, 0xF, 0x14, 0x19, 0x1E, 0x23,
        0x28, 0x2D, 0x32, 0x37, 0x3C, 0x41, 0x46, 0x4B,
    };

    const keys = [_]c_int  {
        c.SDL_SCANCODE_X, c.SDL_SCANCODE_1, c.SDL_SCANCODE_2, c.SDL_SCANCODE_3,
        c.SDL_SCANCODE_Q, c.SDL_SCANCODE_W, c.SDL_SCANCODE_E, c.SDL_SCANCODE_A,
        c.SDL_SCANCODE_S, c.SDL_SCANCODE_D, c.SDL_SCANCODE_Z, c.SDL_SCANCODE_C,
        c.SDL_SCANCODE_4, c.SDL_SCANCODE_R, c.SDL_SCANCODE_F, c.SDL_SCANCODE_V
    };
};
