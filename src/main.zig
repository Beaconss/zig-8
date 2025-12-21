const std = @import("std");
const c = @cImport({@cInclude("SDL3/SDL.h");});

pub fn main() !void
{
    if(c.SDL_Init(c.SDL_INIT_VIDEO) == false)
    {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("zig-8", 800, 600, c.SDL_WINDOW_RESIZABLE) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    var running: bool = true;
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
