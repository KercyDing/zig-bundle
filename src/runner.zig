//! Bundling entry point executed by the build graph.
const std = @import("std");

const bundle = @import("bundle.zig");
const manifest = @import("manifest.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer iterator.deinit();
    _ = iterator.next();

    var args: std.ArrayList([]const u8) = .empty;
    while (iterator.next()) |arg| {
        try args.append(allocator, arg);
    }

    if (args.items.len < 2) {
        std.debug.print("usage: zig-bundle-runner <manifest> <paths...> <output>\n", .{});
        std.process.exit(1);
    }

    const manifest_path = args.items[0];
    const json = try std.Io.Dir.cwd().readFileAlloc(init.io, manifest_path, allocator, .limited(16 * 1024 * 1024));
    var parsed = try manifest.parse(allocator, json);
    defer parsed.deinit();

    const count = parsed.value.path_count;
    if (args.items.len < 2 + count) {
        std.debug.print("zig-bundle: expected {d} input paths\n", .{count});
        std.process.exit(1);
    }

    const raw_paths = args.items[1 .. 1 + count];
    const cwd = try std.process.currentPathAlloc(init.io, allocator);
    const paths = try allocator.alloc([]const u8, raw_paths.len);
    for (raw_paths, paths) |path, *dest| {
        dest.* = if (std.fs.path.isAbsolute(path))
            path
        else
            try std.fs.path.join(allocator, &.{ cwd, path });
    }
    const raw_output_root = args.items[1 + count];
    const output_root = if (std.fs.path.isAbsolute(raw_output_root))
        raw_output_root
    else
        try std.fs.path.join(allocator, &.{ cwd, raw_output_root });

    _ = bundle.project(init.io, init.environ_map, &parsed.value, paths, output_root, allocator) catch |err| switch (err) {
        error.BundleFailed => std.process.exit(1),
        else => {
            std.debug.print("zig-bundle: {t}\n", .{err});
            std.process.exit(1);
        },
    };
}
