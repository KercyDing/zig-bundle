const std = @import("std");

const resources = @import("resources.zig");

const flate = std.compress.flate;
const Io = std.Io;
const Entry = resources.Entry;

pub const Options = struct {
    /// Gzip level, clamped to 1-9.
    level: u4 = 6,
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
