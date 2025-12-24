const std = @import("std");
const c = @cImport({@cInclude("SDL3/SDL.h");});

pub fn keyPressed(key: u8) bool
{
    return c.SDL_GetKeyboardState(null)[@intCast(keyToScancode(key))];
}

pub fn anyKeyPressed() ?u8
{
    for(0..0xF) |i| if(keyPressed(@intCast(i))) return @intCast(i);
    return null;
}

fn keyToScancode(key: u8) c_int
{
    switch(key)
    {
        0x0 => { return c.SDL_SCANCODE_X; },
        0x1 => { return c.SDL_SCANCODE_1; },
        0x2 => { return c.SDL_SCANCODE_2; },
        0x3 => { return c.SDL_SCANCODE_3; },
        0x4 => { return c.SDL_SCANCODE_Q; },
        0x5 => { return c.SDL_SCANCODE_W; },
        0x6 => { return c.SDL_SCANCODE_E; },
        0x7 => { return c.SDL_SCANCODE_A; },
        0x8 => { return c.SDL_SCANCODE_S; },
        0x9 => { return c.SDL_SCANCODE_D; },
        0xA => { return c.SDL_SCANCODE_Z; },
        0xB => { return c.SDL_SCANCODE_C; },
        0xC => { return c.SDL_SCANCODE_4; },
        0xD => { return c.SDL_SCANCODE_R; },
        0xE => { return c.SDL_SCANCODE_F; },
        0xF => { return c.SDL_SCANCODE_V; },
        else => { return 0; },
    }
}
