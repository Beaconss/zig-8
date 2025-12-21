const std = @import("std");

pub fn build(b: *std.Build) void
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-8",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
    const sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = .ReleaseFast,
    });
    exe.linkLibrary(sdl.artifact("SDL3"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run zig-8");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
}
