const std = @import("std");
const c = @cImport({@cInclude("SDL3/SDL.h");});
const chip8 = @import("chip8.zig");

pub fn main() !void
{
    if(c.SDL_Init(c.SDL_INIT_VIDEO) == false)
    {
        c.SDL_Log("Failed to initialize SDL: %s", c.SDL_GetError());
        return error.FailedToInitializeSDL;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("zig-8", 800, 600, c.SDL_WINDOW_RESIZABLE) orelse {
        c.SDL_Log("Failed to create window: %s", c.SDL_GetError());
        return error.FailedToCreateWindow;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, 0) orelse {
        c.SDL_Log("Failed to create renderer: %s", c.SDL_GetError());
        return error.FailedToCreateRenderer;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const c8 = chip8.initializeChip8() orelse return;
    _ = c8;

    var running = true;
    var event: c.SDL_Event = undefined;
    while(running)
    {
        while(c.SDL_PollEvent(&event))
        {
            switch(event.type)
            {
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                else => {},
            }
        }

        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderPresent(renderer);
    }
}
