//! Builds the staged payload from the executable, resources, and icons.
const std = @import("std");

const icons = @import("icons.zig");
const resources = @import("resources.zig");
const settings = @import("../../settings.zig");

const Io = std.Io;

pub const Staged = struct {
    payload: resources.Payload,
    png_icons: []icons.Png,
    ico_path: ?[]const u8,
};

/// Resolves the executable, resources, and icons into a payload.
pub fn prepare(
    b: *std.Build,
    step: *std.Build.Step,
    config: *const settings.Settings,
    arena: std.mem.Allocator,
) !Staged {
    const io = b.graph.io;

    var payload: resources.Payload = .{};
    errdefer payload.deinit(arena);

    const executable_path = try resolveLazyPath(b, step, config.executable_path, arena);
    payload.addFile(arena, executable_path, config.executable.out_filename, true) catch |err| {
        return step.fail("invalid executable name '{s}': {t}", .{ config.executable.out_filename, err });
    };

    for (config.resources) |resource| {
        const source_path = try resolveLazyPath(b, step, resource.source, arena);
        const base_name = std.fs.path.basename(std.mem.trimEnd(u8, source_path, "/\\"));
        const dest = resource.dest orelse base_name;

        const stat = Io.Dir.cwd().statFile(io, source_path, .{}) catch |err| {
            return step.fail("cannot read resource '{s}': {t}", .{ source_path, err });
        };

        switch (stat.kind) {
            .directory => payload.addDirectory(arena, io, source_path, dest) catch |err| {
                return step.fail("cannot add resource '{s}': {t}", .{ source_path, err });
            },
            .file => payload.addFile(arena, source_path, dest, false) catch |err| {
                return step.fail("cannot add resource '{s}': {t}", .{ source_path, err });
            },
            else => return step.fail("resource '{s}' is not a file or directory", .{source_path}),
        }
    }

    payload.sort();
    var index: usize = 1;
    while (index < payload.entries.items.len) : (index += 1) {
        const previous = payload.entries.items[index - 1];
        const current = payload.entries.items[index];
        if (std.mem.eql(u8, previous.archive_path, current.archive_path)) {
            return step.fail("duplicate bundle path '{s}'", .{current.archive_path});
        }
    }

    var png_icons: std.ArrayList(icons.Png) = .empty;
    for (config.icons.png) |lazy_path| {
        const path = try resolveLazyPath(b, step, lazy_path, arena);
        const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            return step.fail("cannot read icon source '{s}': {t}", .{ path, err });
        };

        switch (stat.kind) {
            .file => try addIconPng(io, arena, path, &png_icons, step),
            .directory => {
                var dir = Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch |err| {
                    return step.fail("cannot read icon directory '{s}': {t}", .{ path, err });
                };
                defer dir.close(io);

                var found = false;
                var iterator = dir.iterate();
                while (try iterator.next(io)) |entry| {
                    if (entry.kind != .file) continue;
                    if (!std.ascii.eqlIgnoreCase(std.fs.path.extension(entry.name), ".png")) continue;

                    const child = try std.fs.path.join(arena, &.{ path, entry.name });
                    try addIconPng(io, arena, child, &png_icons, step);
                    found = true;
                }

                if (!found) {
                    return step.fail("no PNG icons found in '{s}'", .{path});
                }
            },
            else => return step.fail("icon source '{s}' is not a file or directory", .{path}),
        }
    }

    const ico_path: ?[]const u8 = if (config.icons.ico) |lazy_path|
        try resolveLazyPath(b, step, lazy_path, arena)
    else
        null;
    if (ico_path) |path| {
        _ = Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            return step.fail("cannot read icon '{s}': {t}", .{ path, err });
        };
    }

    return .{
        .payload = payload,
        .png_icons = try png_icons.toOwnedSlice(arena),
        .ico_path = ico_path,
    };
}

pub fn resolveLazyPath(
    b: *std.Build,
    step: *std.Build.Step,
    lazy_path: std.Build.LazyPath,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const path = try lazy_path.getPath4(b, step);
    if (std.fs.path.isAbsolute(path.sub_path)) return allocator.dupe(u8, path.sub_path);
    if (path.root_dir.path) |root| return std.fs.path.join(allocator, &.{ root, path.sub_path });
    return allocator.dupe(u8, path.sub_path);
}

fn addIconPng(
    io: Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    list: *std.ArrayList(icons.Png),
    step: *std.Build.Step,
) !void {
    const info = icons.readPng(io, path) catch |err| {
        return step.fail("invalid icon '{s}': {t}", .{ path, err });
    };

    for (list.items) |existing| {
        if (existing.width == info.width and existing.height == info.height) return;
    }
    try list.append(allocator, info);
}
