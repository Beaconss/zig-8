const std = @import("std");
const c = @cImport({@cInclude("SDL3/SDL.h");});
const chip8 = @import("chip8.zig");
const Chip8 = chip8.Chip8;

pub fn main() !void
{
    if(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) == false)
    {
        c.SDL_Log("Failed to initialize SDL: %s", c.SDL_GetError());
        return error.FailedToInitializeSDL;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("zig-8", Chip8.display_width * 15, Chip8.display_height * 15, c.SDL_WINDOW_RESIZABLE) orelse {
        c.SDL_Log("Failed to create window: %s", c.SDL_GetError());
        return error.FailedToCreateWindow;
    };
    defer c.SDL_DestroyWindow(window);
    _ = c.SDL_SetWindowPosition(window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);

    const renderer = c.SDL_CreateRenderer(window, 0) orelse {
        c.SDL_Log("Failed to create renderer: %s", c.SDL_GetError());
        return error.FailedToCreateRenderer;
    };
    defer c.SDL_DestroyRenderer(renderer);
    _ = c.SDL_SetRenderLogicalPresentation(renderer, Chip8.display_width, Chip8.display_height, c.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE);

    const screen_texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGB332, c.SDL_TEXTUREACCESS_STREAMING, Chip8.display_width, Chip8.display_height) orelse {
        c.SDL_Log("Failed to create texture: %s", c.SDL_GetError());
        return error.FailedToCreateTexture;
    };
    defer c.SDL_DestroyTexture(screen_texture);
    _ = c.SDL_SetTextureScaleMode(screen_texture, c.SDL_SCALEMODE_NEAREST);

    var c8 = Chip8.initialize() orelse return;
    defer c8.deInitialize();
    c8.loadRom(getRomPathFromArgs() orelse return) orelse return;

    const target_frametime = 1000000000.0 / 60.005;
    var running = true;
    var fps_limiter = true;
    var event: c.SDL_Event = undefined;
    while(running)
    {
        while(c.SDL_PollEvent(&event))
        {
            switch(event.type)
            {
                c.SDL_EVENT_KEY_DOWN => {
                    if(event.key.scancode == c.SDL_SCANCODE_SPACE) fps_limiter = !fps_limiter;
                },
                c.SDL_EVENT_DROP_FILE => {
                    _ = c8.loadRom(event.drop.data);
                },
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                else => {},
            }
        }

        const start = c.SDL_GetPerformanceCounter();

        c8.timerCycle();
        for(0..12) |_| //720 instructions per second
        {
            c.SDL_PumpEvents();
            c8.decodeAndExecute();
        }

        _ = c.SDL_UpdateTexture(screen_texture, null, &c8.display, Chip8.display_width);
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderTexture(renderer, screen_texture, null, null);
        _ = c.SDL_RenderPresent(renderer);

        if(fps_limiter)
        {
            const end = c.SDL_GetPerformanceCounter();
            const frametime = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(c.SDL_GetPerformanceFrequency())) * 1000000000.0;
            if(frametime < target_frametime) c.SDL_DelayPrecise(@intFromFloat(target_frametime - frametime));
        }
    }
}

fn getRomPathFromArgs() ?[*c]const u8
{
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator(); 

    var args = std.process.argsWithAllocator(allocator) catch |err| {
        std.log.err("Failed to read arg: {s}", .{@errorName(err)});
        return null;
    };
    defer args.deinit();
    const program_name = args.next() orelse return null;
    const rom_path = args.next() orelse {
        std.debug.print("Usage: {s} <filepath>\n", .{program_name});
        return null;
    };
    return rom_path;
}
