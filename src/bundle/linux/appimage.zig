//! AppImage packaging via the system `appimagetool`.
const std = @import("std");

const desktop_entry = @import("../common/desktop.zig");
const files = @import("../common/files.zig");
const icons = @import("../common/icons.zig");
const resources = @import("../common/resources.zig");

const Io = std.Io;

pub const Config = struct {
    name: []const u8,
    version: []const u8,
    executable_name: []const u8,
    description: ?[]const u8 = null,
    categories: ?[]const u8 = null,
    arch: []const u8,
    payload: []const resources.Entry,
    icons: []const icons.Png = &.{},
    appimagetool: ?[]const u8 = null,
};

/// Maps a Zig CPU architecture to the AppImage architecture name.
pub fn archName(arch: std.Target.Cpu.Arch) ![]const u8 {
    return switch (arch) {
        .x86_64 => "x86_64",
        .x86 => "i686",
        .aarch64 => "aarch64",
        .arm, .armeb, .thumb, .thumbeb => "armhf",
        .riscv64 => "riscv64",
        else => error.UnsupportedArchitecture,
    };
}

/// Builds an AppDir and runs `appimagetool` to produce the final image.
pub fn bundle(
    io: Io,
    env_map: *const std.process.Environ.Map,
    config: Config,
    output_dir: []const u8,
    output_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    const tool = try findTool(io, allocator, env_map, config.appimagetool);
    const app_dir = try std.fs.path.join(allocator, &.{ output_dir, config.name });

    Io.Dir.cwd().deleteTree(io, app_dir) catch {};
    defer Io.Dir.cwd().deleteTree(io, app_dir) catch {};

    try Io.Dir.cwd().createDirPath(io, app_dir);

    for (config.payload) |entry| {
        const dest = switch (entry.executable) {
            true => try std.fmt.allocPrint(allocator, "{s}/usr/bin/{s}", .{ app_dir, entry.archive_path }),
            false => try std.fmt.allocPrint(allocator, "{s}/usr/lib/{s}/{s}", .{ app_dir, config.name, entry.archive_path }),
        };

        switch (entry.kind) {
            .dir => try Io.Dir.cwd().createDirPath(io, dest),
            .file => try files.copyFile(io, entry.source_path, dest, entry.executable),
        }
    }

    for (config.icons) |icon| {
        const dest = try std.fmt.allocPrint(allocator, "{s}/usr/share/icons/hicolor/{d}x{d}/apps/{s}.png", .{
            app_dir,
            icon.width,
            icon.height,
            config.executable_name,
        });
        try files.copyFile(io, icon.path, dest, false);
    }

    const root_icon = blk: {
        var best: ?icons.Png = null;
        for (config.icons) |icon| {
            if (icon.width != icon.height) continue;
            if (best == null or icon.width > best.?.width) best = icon;
        }
        break :blk best orelse return error.MissingIcon;
    };

    const root_icon_path = try std.fmt.allocPrint(allocator, "{s}/{s}.png", .{ app_dir, config.executable_name });
    try files.copyFile(io, root_icon.path, root_icon_path, false);
    try files.copyFile(io, root_icon.path, try std.fmt.allocPrint(allocator, "{s}/.DirIcon", .{app_dir}), false);

    const desktop = try desktop_entry.render(allocator, .{
        .name = config.name,
        .executable_name = config.executable_name,
        .description = config.description,
        .categories = config.categories,
        .has_icon = true,
    });
    const desktop_rel = try std.fmt.allocPrint(allocator, "{s}.desktop", .{config.name});
    try files.writeBytes(io, try std.fmt.allocPrint(allocator, "{s}/{s}", .{ app_dir, desktop_rel }), desktop, false);
    try files.writeBytes(io, try std.fmt.allocPrint(allocator, "{s}/usr/share/applications/{s}", .{ app_dir, desktop_rel }), desktop, false);

    const app_run = try std.fmt.allocPrint(allocator,
        \\#!/bin/sh
        \\HERE="${{APPDIR:-$(dirname "$(readlink -f "$0")")}}"
        \\exec "$HERE/usr/bin/{s}" "$@"
        \\
    , .{config.executable_name});
    try files.writeBytes(io, try std.fmt.allocPrint(allocator, "{s}/AppRun", .{app_dir}), app_run, true);

    Io.Dir.cwd().deleteFile(io, output_path) catch {};

    var child_env = std.process.Environ.Map.init(allocator);
    defer child_env.deinit();
    for (env_map.keys(), env_map.values()) |key, value| try child_env.put(key, value);
    try child_env.put("APPIMAGE_EXTRACT_AND_RUN", "1");
    try child_env.put("ARCH", config.arch);

    var child = std.process.spawn(io, .{
        .argv = &.{ tool, "--no-appstream", app_dir, output_path },
        .environ_map = &child_env,
        .stdin = .ignore,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.AppImageToolNotFound,
        else => return err,
    };

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.AppImageToolFailed,
        else => return error.AppImageToolFailed,
    }
}

fn findTool(
    io: Io,
    allocator: std.mem.Allocator,
    env_map: *const std.process.Environ.Map,
    configured: ?[]const u8,
) ![]const u8 {
    const name = configured orelse "appimagetool";
    if (std.mem.indexOfScalar(u8, name, '/') != null) {
        Io.Dir.cwd().access(io, name, .{ .execute = true }) catch return error.AppImageToolNotFound;
        return name;
    }

    const path = env_map.get("PATH") orelse return error.AppImageToolNotFound;
    var dirs = std.mem.tokenizeScalar(u8, path, std.fs.path.delimiter);
    while (dirs.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fs.path.join(allocator, &.{ dir, name });
        Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch continue;
        return candidate;
    }
    return error.AppImageToolNotFound;
}

test "appimage architecture names" {
    try std.testing.expectEqualStrings("x86_64", try archName(.x86_64));
    try std.testing.expectEqualStrings("aarch64", try archName(.aarch64));
    try std.testing.expectEqualStrings("i686", try archName(.x86));
    try std.testing.expectError(error.UnsupportedArchitecture, archName(.wasm32));
}
