const std = @import("std");

const zig_bundle = @import("zig_bundle");

const Format = enum { zip, targz, deb };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const format = b.option(Format, "format", "Bundle format") orelse .zip;

    const exe = b.addExecutable(.{
        .name = "hello-bundle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const formats: zig_bundle.Formats = switch (format) {
        .zip => .{ .zip = .{} },
        .targz => .{ .tar_gz = .{} },
        .deb => .{ .deb = .{} },
    };

    b.installArtifact(exe);

    const bundled = zig_bundle.add(b, .{
        .app = .{
            .name = "HelloBundle",
            .identifier = "com.example.hellobundle",
            .version = "0.1.0",
            .publisher = "Example <example@example.com>",
            .description = "Example application for zig-bundle",
        },
        .input = .{
            .executable = exe,
            .icon = b.path("assets/icon.png"),
            .resources = &.{
                .{ .source = b.path("assets") },
            },
        },
        .formats = formats,
    });

    b.step("package", "Package the application").dependOn(&bundled.step);
}
