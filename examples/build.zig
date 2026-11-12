const builtin = @import("builtin");
const std = @import("std");

const bundle = @import("bundle");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const format = b.option(bundle.Format, "format", "Bundle format") orelse .zip;
    const app_version = b.option([]const u8, "app-version", "Application version") orelse "0.1.0";

    const makensis: ?[]const u8 = if (format == .nsis and builtin.os.tag == .windows) blk: {
        const nsis = b.lazyDependency("nsis", .{}) orelse return;
        break :blk nsis.path("nsis-3.13/makensis.exe").getPath(b);
    } else null;

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
        .rpm => .{ .rpm = .{} },
        .appimage => .{ .appimage = .{} },
        .deb => .{ .deb = .{
            .homepage = "https://example.com/hello-bundle",
            .assets = &.{
                .{ .source = b.path("assets/hello-bundle.1"), .dest = "usr/share/man/man1/" },
                .{ .source = b.path("assets/nested/config.json"), .dest = "etc/hello-bundle/config.json" },
                .{ .source = b.path("assets/nested"), .dest = "usr/share/hello-bundle/" },
            },
        } },
        .nsis => .{ .nsis = .{
            .shortcuts = .{ .start_menu = true, .desktop = true },
            .makensis = makensis,
        } },
    };

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(b.path("."));
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "Run the example application").dependOn(&run_cmd.step);

    const bundled = bundle.add(b, .{
        .app = .{
            .name = "HelloBundle",
            .identifier = "com.example.hellobundle",
            .version = app_version,
            .publisher = "Example <example@example.com>",
            .copyright = "Copyright 2026 Example",
            .license = "MIT",
            .categories = "Utility;",
            .description = "Example application for zig-bundle\n\nDemonstrates every format supported by the library.",
        },
        .input = .{
            .executable = exe,
            .icons = .{
                .png = &.{b.path("icons")},
            },
            .resources = &.{
                .{ .source = b.path("assets") },
            },
        },
        .formats = formats,
        // Requires llvm-strip on PATH; disabled so cross-target builds work.
        .enable_llvm_strip = false,
    });

    b.step("bundle", "Bundle the application").dependOn(&bundled.step);
}
