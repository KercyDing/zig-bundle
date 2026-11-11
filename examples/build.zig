const std = @import("std");

const bundle = @import("bundle");

const Format = enum { zip, tar_gz, deb, setup_exe };

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

    const formats: bundle.Formats = switch (format) {
        .zip => .{ .zip = .{} },
        .tar_gz => .{ .tar_gz = .{} },
        .deb => .{ .deb = .{} },
        .setup_exe => .{ .setup_exe = .{
            .shortcuts = .{ .start_menu = true, .desktop = true },
        } },
    };

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "Run the example application").dependOn(&run_cmd.step);

    const bundled = bundle.add(b, .{
        .app = .{
            .name = "HelloBundle",
            .identifier = "com.example.hellobundle",
            .version = "0.1.0",
            .publisher = "Example <example@example.com>",
            .description = "Example application for zig-bundle",
        },
        .input = .{
            .executable = exe,
            .icons = .{
                .png = &.{b.path("assets/icons")},
            },
            .resources = &.{
                .{ .source = b.path("assets") },
            },
        },
        .formats = formats,
    });

    b.step("package", "Package the application").dependOn(&bundled.step);
}
