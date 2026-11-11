//! Deterministic tar.gz archive writer.
const std = @import("std");

const resources = @import("resources.zig");

const flate = std.compress.flate;
const Io = std.Io;
const Entry = resources.Entry;

pub const Options = struct {
    /// Gzip level, clamped to 1-9.
    level: u4 = 6,
};

pub const Kind = enum { file, dir };

/// Generic tar.gz entry used by formats that build a custom tree.
pub const Item = struct {
    path: []const u8,
    kind: Kind,
    mode: u32 = 0o644,
    content: Content = .{ .bytes = "" },

    pub const Content = union(enum) {
        file: []const u8,
        bytes: []const u8,
    };
};

// Fixed timestamp: 1970-01-01, keeps archives reproducible.
const mtime: u64 = 0;

pub fn write(
    io: Io,
    file: Io.File,
    entries: []const Entry,
    options: Options,
) !void {
    var file_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &file_buffer);

    var history: [flate.max_window_len]u8 = undefined;
    var compressor = try flate.Compress.init(&writer.interface, &history, .gzip, levelOptions(options.level));

    var tar_writer: std.tar.Writer = .{ .underlying_writer = &compressor.writer };

    var read_buffer: [16 * 1024]u8 = undefined;
    for (entries) |entry| switch (entry.kind) {
        .dir => try tar_writer.writeDir(entry.archive_path, .{
            .mode = 0o755,
            .mtime = mtime,
        }),
        .file => {
            var source = try Io.Dir.cwd().openFile(io, entry.source_path, .{});
            defer source.close(io);

            const stat = try source.stat(io);
            var reader = source.reader(io, &read_buffer);
            try tar_writer.writeFileStream(entry.archive_path, stat.size, &reader.interface, .{
                .mode = if (entry.executable) 0o755 else 0o644,
                .mtime = mtime,
            });
        },
    };

    try tar_writer.finishPedantically();
    try compressor.finish();
    try writer.interface.flush();
}

/// Writes a tar.gz from arbitrary in-memory or on-disk entries.
pub fn writeItems(
    io: Io,
    file: Io.File,
    items: []const Item,
    level: u4,
) !void {
    var file_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &file_buffer);
    try writeItemsTo(io, &writer.interface, items, level);
    try writer.interface.flush();
}

/// Writes a tar.gz into an existing writer, without flushing it.
pub fn writeItemsTo(
    io: Io,
    writer: *Io.Writer,
    items: []const Item,
    level: u4,
) !void {
    var history: [flate.max_window_len]u8 = undefined;
    var compressor = try flate.Compress.init(writer, &history, .gzip, levelOptions(level));

    var tar_writer: std.tar.Writer = .{ .underlying_writer = &compressor.writer };

    var read_buffer: [16 * 1024]u8 = undefined;
    for (items) |item| switch (item.kind) {
        .dir => try tar_writer.writeDir(item.path, .{
            .mode = item.mode,
            .mtime = mtime,
        }),
        .file => switch (item.content) {
            .bytes => |bytes| try tar_writer.writeFileBytes(item.path, bytes, .{
                .mode = item.mode,
                .mtime = mtime,
            }),
            .file => |path| {
                var source = try Io.Dir.cwd().openFile(io, path, .{});
                defer source.close(io);

                const stat = try source.stat(io);
                var reader = source.reader(io, &read_buffer);
                try tar_writer.writeFileStream(item.path, stat.size, &reader.interface, .{
                    .mode = item.mode,
                    .mtime = mtime,
                });
            },
        },
    };

    try tar_writer.finishPedantically();
    try compressor.finish();
}

fn levelOptions(level: u4) flate.Compress.Options {
    return switch (level) {
        0, 1 => .level_1,
        2 => .level_2,
        3 => .level_3,
        4 => .level_4,
        5 => .level_5,
        6 => .level_6,
        7 => .level_7,
        8 => .level_8,
        else => .level_9,
    };
}

test "compression level clamps" {
    try std.testing.expectEqual(std.compress.flate.Compress.Options.level_1, levelOptions(0));
    try std.testing.expectEqual(std.compress.flate.Compress.Options.level_9, levelOptions(15));
}
