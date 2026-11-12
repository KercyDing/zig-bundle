const std = @import("std");

const bundle = @import("bundle");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const format = b.option(bundle.Format, "format", "Bundle format") orelse .zip;
    const app_version = b.option([]const u8, "app-version", "Application version") orelse "0.1.0";
    const install_scope = b.option(bundle.NsisOptions.InstallScope, "scope", "NSIS install scope") orelse .current_user;
    const dmg_layout = b.option(bool, "dmg-layout", "Apply the example DMG layout") orelse true;

    const exe = b.addExecutable(.{
        .name = "hello-bundle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    var formats = bundle.standardFormats(format);
    if (formats.nsis) |*nsis| {
        nsis.install_scope = install_scope;
        nsis.shortcuts = .{ .start_menu = true, .desktop = true };
    }
    if (formats.dmg) |*dmg| {
        if (dmg_layout) {
            dmg.layout = .{
                .background = b.path("assets/dmg-background.png"),
                .window_size = .{ .width = 660, .height = 476 },
                .icon_size = 128,
                .app_position = .{ .x = 180, .y = 230 },
                .applications_position = .{ .x = 480, .y = 230 },
            };
        }
    }

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
                // macOS prefers this; other formats ignore it.
                .icns = b.path("icons/icon.icns"),
            },
            .resources = &.{
                .{ .source = b.path("assets") },
            },
        },
        .formats = formats,
        // Requires llvm-strip on PATH; disabled so cross-target builds work.
        .enable_llvm_strip = false,
    });

    b.step("bundle", "Bundle the application").dependOn(bundled.step);
}
