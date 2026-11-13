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
        std.debug.print("usage: zig-bundle-runner [--list <prefix> <artifacts> | <manifest> <paths...> <output> <artifacts>]\n", .{});
        std.process.exit(1);
    }

    if (std.mem.eql(u8, args.items[0], "--list")) {
        if (args.items.len != 3) {
            std.debug.print("usage: zig-bundle-runner --list <prefix> <artifacts>\n", .{});
            std.process.exit(1);
        }
        try listArtifacts(init.io, allocator, args.items[1], args.items[2]);
        return;
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
        dest.* = if (std.Io.Dir.path.isAbsolute(path))
            path
        else
            try std.Io.Dir.path.join(allocator, &.{ cwd, path });
    }
    const raw_output_root = args.items[1 + count];
    const output_root = if (std.Io.Dir.path.isAbsolute(raw_output_root))
        raw_output_root
    else
        try std.Io.Dir.path.join(allocator, &.{ cwd, raw_output_root });
    if (args.items.len < 2 + count + 1) {
        std.debug.print("zig-bundle: missing artifacts path\n", .{});
        std.process.exit(1);
    }
    const artifacts_path = args.items[2 + count];

    const artifacts = bundle.project(init.io, init.environ_map, &parsed.value, paths, output_root, allocator) catch |err| switch (err) {
        error.BundleFailed => std.process.exit(1),
        else => {
            std.debug.print("zig-bundle: {t}\n", .{err});
            std.process.exit(1);
        },
    };

    var file = try std.Io.Dir.cwd().createFile(init.io, artifacts_path, .{ .truncate = true });
    defer file.close(init.io);
    var buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(init.io, &buffer);
    for (artifacts) |path| {
        const relative = try std.Io.Dir.path.relativeAlloc(allocator, cwd, init.environ_map, output_root, path);
        try writer.interface.print("{s}\n", .{relative});
    }
    try writer.interface.flush();
}

fn listArtifacts(io: std.Io, allocator: std.mem.Allocator, prefix: []const u8, path: []const u8) !void {
    const cwd = try std.process.currentPathAlloc(io, allocator);
    // The build runner prefixes relative path args with "./", and the install
    // prefix may already be cwd-relative, so the argument can be "././zig-out".
    // `join` keeps those components; `resolveAlloc` collapses them.
    const root = try std.Io.Dir.path.resolveAlloc(allocator, &.{ cwd, prefix });
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (first) {
            try out.print("zig-bundle: finished {d} bundle(s):\n", .{std.mem.count(u8, bytes, "\n")});
            first = false;
        }
        try out.print("  {s}\n", .{try std.Io.Dir.path.join(allocator, &.{ root, line })});
    }
    try out.flush();
}
