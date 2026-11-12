//! Builds the staged payload from resolved executable, resources, and icons.
const std = @import("std");

const icons = @import("icons.zig");
const manifest = @import("../../manifest.zig");
const resources = @import("resources.zig");

const Io = std.Io;

pub const Staged = struct {
    payload: resources.Payload,
    png_icons: []icons.Png,
    ico_path: ?[]const u8,
    icns_path: ?[]const u8,
};

/// Resolves manifest paths into a payload.
pub fn prepare(
    io: Io,
    config: *const manifest.Manifest,
    paths: []const []const u8,
    allocator: std.mem.Allocator,
) !Staged {
    var payload: resources.Payload = .{};
    errdefer payload.deinit(allocator);

    payload.addFile(allocator, paths[config.executable], config.executable_name, true) catch |err| {
        return fail("invalid executable name '{s}': {t}", .{ config.executable_name, err });
    };

    for (config.resources) |resource| {
        const source_path = paths[resource.path];
        const base_name = std.fs.path.basename(std.mem.trimEnd(u8, source_path, "/\\"));
        const dest = resource.dest orelse base_name;

        const stat = Io.Dir.cwd().statFile(io, source_path, .{}) catch |err| {
            return fail("cannot read resource '{s}': {t}", .{ source_path, err });
        };

        switch (stat.kind) {
            .directory => payload.addDirectory(allocator, io, source_path, dest) catch |err| {
                return fail("cannot add resource '{s}': {t}", .{ source_path, err });
            },
            .file => payload.addFile(allocator, source_path, dest, false) catch |err| {
                return fail("cannot add resource '{s}': {t}", .{ source_path, err });
            },
            else => return fail("resource '{s}' is not a file or directory", .{source_path}),
        }
    }

    payload.sort();
    var index: usize = 1;
    while (index < payload.entries.items.len) : (index += 1) {
        const previous = payload.entries.items[index - 1];
        const current = payload.entries.items[index];
        if (std.mem.eql(u8, previous.archive_path, current.archive_path)) {
            return fail("duplicate bundle path '{s}'", .{current.archive_path});
        }
    }

    var png_icons: std.ArrayList(icons.Png) = .empty;
    for (config.png_icons) |path_index| {
        const path = paths[path_index];
        const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            return fail("cannot read icon source '{s}': {t}", .{ path, err });
        };

        switch (stat.kind) {
            .file => try addIconPng(io, allocator, path, &png_icons),
            .directory => {
                var dir = Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch |err| {
                    return fail("cannot read icon directory '{s}': {t}", .{ path, err });
                };
                defer dir.close(io);

                var found = false;
                var iterator = dir.iterate();
                while (try iterator.next(io)) |entry| {
                    if (entry.kind != .file) continue;
                    if (!std.ascii.eqlIgnoreCase(std.fs.path.extension(entry.name), ".png")) continue;

                    const child = try std.fs.path.join(allocator, &.{ path, entry.name });
                    try addIconPng(io, allocator, child, &png_icons);
                    found = true;
                }

                if (!found) {
                    return fail("no PNG icons found in '{s}'", .{path});
                }
            },
            else => return fail("icon source '{s}' is not a file or directory", .{path}),
        }
    }

    const ico_path: ?[]const u8 = if (config.ico) |path_index| blk: {
        const path = paths[path_index];
        _ = Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            return fail("cannot read icon '{s}': {t}", .{ path, err });
        };
        break :blk path;
    } else null;

    const icns_path: ?[]const u8 = if (config.icns) |path_index| blk: {
        const path = paths[path_index];
        _ = Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            return fail("cannot read icon '{s}': {t}", .{ path, err });
        };
        break :blk path;
    } else null;

    return .{
        .payload = payload,
        .png_icons = try png_icons.toOwnedSlice(allocator),
        .ico_path = ico_path,
        .icns_path = icns_path,
    };
}

fn addIconPng(
    io: Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    list: *std.ArrayList(icons.Png),
) !void {
    const info = icons.readPng(io, path) catch |err| {
        return fail("invalid icon '{s}': {t}", .{ path, err });
    };

    for (list.items) |existing| {
        if (existing.width == info.width and existing.height == info.height) return;
    }
    try list.append(allocator, info);
}

fn fail(comptime fmt: []const u8, args: anytype) error{BundleFailed} {
    std.debug.print("zig-bundle: " ++ fmt ++ "\n", args);
    return error.BundleFailed;
}
