const std = @import("std");

const zig_bundle = @import("zig_bundle");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip debug symbols") orelse false;

    const exe = b.addExecutable(.{
        .name = "hello-bundle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }),
    });

    const bundled = zig_bundle.add(b, .{
        .app = .{
            .name = "HelloBundle",
            .identifier = "com.example.hellobundle",
            .version = "0.1.0",
        },
        .input = .{
            .executable = exe,
            .resources = &.{
                .{ .source = b.path("assets") },
            },
        },
        .formats = .{
            .zip = .{},
            .tar_gz = .{},
        },
    });

    b.step("package", "Package the application").dependOn(&bundled.step);
}
