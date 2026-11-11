const std = @import("std");

const resources = @import("resources.zig");

const flate = std.compress.flate;
const Io = std.Io;
const Entry = resources.Entry;

pub const Compression = enum { store, deflate };

pub const Options = struct {
    compression: Compression = .deflate,
    /// Deflate level, clamped to 1-9.
    level: u4 = 6,
};

const local_header_signature: u32 = 0x04034b50;
const central_header_signature: u32 = 0x02014b50;
const end_of_central_directory_signature: u32 = 0x06054b50;

const version_needed: u16 = 20;
const version_made_by: u16 = (3 << 8) | 20; // Unix, ZIP 2.0
const utf8_flag: u16 = 0x0800;

// Fixed timestamp: 1980-01-01 00:00:00, keeps archives reproducible.
const dos_time: u16 = 0;
const dos_date: u16 = 0x0021;

const CentralEntry = struct {
    name: []const u8,
    method: u16,
    crc: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    offset: u32,
    mode: u32,
    directory: bool,
};

const Sizes = struct {
    crc: u32,
    uncompressed_size: u64,
};

pub fn write(
    io: Io,
    file: Io.File,
    entries: []const Entry,
    allocator: std.mem.Allocator,
    options: Options,
) !void {
    var file_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &file_buffer);

    var central: std.ArrayList(CentralEntry) = .empty;
    defer central.deinit(allocator);

    var chunk: [32 * 1024]u8 = undefined;
    var history: [flate.max_window_len]u8 = undefined;

    for (entries) |entry| {
        const offset = writer.logicalPos();
        if (offset > std.math.maxInt(u32)) return error.FileTooLarge;

        switch (entry.kind) {
            .dir => {
                const name = try std.fmt.allocPrint(allocator, "{s}/", .{entry.archive_path});
                if (name.len > std.math.maxInt(u16)) return error.NameTooLong;
                try writeLocalHeader(&writer.interface, name, 0);
                try writer.interface.flush();
                try central.append(allocator, .{
                    .name = name,
                    .method = 0,
                    .crc = 0,
                    .compressed_size = 0,
                    .uncompressed_size = 0,
                    .offset = @intCast(offset),
                    .mode = 0o40755,
                    .directory = true,
                });
            },
            .file => {
                const method: u16 = switch (options.compression) {
                    .store => 0,
                    .deflate => 8,
                };
                if (entry.archive_path.len > std.math.maxInt(u16)) return error.NameTooLong;

                try writeLocalHeader(&writer.interface, entry.archive_path, method);

                const data_start = writer.logicalPos();
                const sizes = switch (options.compression) {
                    .store => try storeFile(io, &writer.interface, entry.source_path, &chunk),
                    .deflate => try deflateFile(io, &writer.interface, entry.source_path, &chunk, &history, options.level),
                };

                try writer.interface.flush();
                const data_end = writer.logicalPos();
                const compressed_size = data_end - data_start;
                if (compressed_size > std.math.maxInt(u32) or sizes.uncompressed_size > std.math.maxInt(u32)) {
                    return error.FileTooLarge;
                }

                // Fill in the crc and sizes of the local header written above.
                try writer.seekTo(offset + 14);
                var patch: [12]u8 = undefined;
                std.mem.writeInt(u32, patch[0..4], sizes.crc, .little);
                std.mem.writeInt(u32, patch[4..8], @intCast(compressed_size), .little);
                std.mem.writeInt(u32, patch[8..12], @intCast(sizes.uncompressed_size), .little);
                try writer.interface.writeAll(&patch);
                try writer.seekTo(data_end);

                try central.append(allocator, .{
                    .name = entry.archive_path,
                    .method = method,
                    .crc = sizes.crc,
                    .compressed_size = @intCast(compressed_size),
                    .uncompressed_size = @intCast(sizes.uncompressed_size),
                    .offset = @intCast(offset),
                    .mode = switch (entry.executable) {
                        true => 0o100755,
                        false => 0o100644,
                    },
                    .directory = false,
                });
            },
        }
    }

    if (central.items.len > std.math.maxInt(u16)) return error.TooManyEntries;

    const central_offset = writer.logicalPos();
    for (central.items) |entry| {
        try writeCentralHeader(&writer.interface, entry);
    }
    const central_end = writer.logicalPos();
    const central_size = central_end - central_offset;
    if (central_offset > std.math.maxInt(u32) or central_size > std.math.maxInt(u32)) {
        return error.FileTooLarge;
    }

    try writeEndOfCentralDirectory(
        &writer.interface,
        @intCast(central.items.len),
        @intCast(central_size),
        @intCast(central_offset),
    );
    try writer.interface.flush();
}

fn storeFile(
    io: Io,
    writer: *Io.Writer,
    source_path: []const u8,
    chunk: []u8,
) !Sizes {
    var file = try Io.Dir.cwd().openFile(io, source_path, .{});
    defer file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);

    var crc = std.hash.Crc32.init();
    var size: u64 = 0;
    while (true) {
        const n = try reader.interface.readSliceShort(chunk);
        if (n == 0) break;
        crc.update(chunk[0..n]);
        try writer.writeAll(chunk[0..n]);
        size += n;
    }
    return .{ .crc = crc.final(), .uncompressed_size = size };
}

fn deflateFile(
    io: Io,
    writer: *Io.Writer,
    source_path: []const u8,
    chunk: []u8,
    history: []u8,
    level: u4,
) !Sizes {
    var file = try Io.Dir.cwd().openFile(io, source_path, .{});
    defer file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    var compressor = try flate.Compress.init(writer, history, .raw, levelOptions(level));

    var crc = std.hash.Crc32.init();
    var size: u64 = 0;
    while (true) {
        const n = try reader.interface.readSliceShort(chunk);
        if (n == 0) break;
        crc.update(chunk[0..n]);
        try compressor.writer.writeAll(chunk[0..n]);
        size += n;
    }
    try compressor.finish();
    return .{ .crc = crc.final(), .uncompressed_size = size };
}

fn writeLocalHeader(writer: *Io.Writer, name: []const u8, method: u16) !void {
    var header: [30]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], local_header_signature, .little);
    std.mem.writeInt(u16, header[4..6], version_needed, .little);
    std.mem.writeInt(u16, header[6..8], utf8_flag, .little);
    std.mem.writeInt(u16, header[8..10], method, .little);
    std.mem.writeInt(u16, header[10..12], dos_time, .little);
    std.mem.writeInt(u16, header[12..14], dos_date, .little);
    @memset(header[14..26], 0); // crc, compressed size, uncompressed size
    std.mem.writeInt(u16, header[26..28], @intCast(name.len), .little);
    std.mem.writeInt(u16, header[28..30], 0, .little);
    try writer.writeAll(&header);
    try writer.writeAll(name);
}

fn writeCentralHeader(writer: *Io.Writer, entry: CentralEntry) !void {
    var header: [46]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], central_header_signature, .little);
    std.mem.writeInt(u16, header[4..6], version_made_by, .little);
    std.mem.writeInt(u16, header[6..8], version_needed, .little);
    std.mem.writeInt(u16, header[8..10], utf8_flag, .little);
    std.mem.writeInt(u16, header[10..12], entry.method, .little);
    std.mem.writeInt(u16, header[12..14], dos_time, .little);
    std.mem.writeInt(u16, header[14..16], dos_date, .little);
    std.mem.writeInt(u32, header[16..20], entry.crc, .little);
    std.mem.writeInt(u32, header[20..24], entry.compressed_size, .little);
    std.mem.writeInt(u32, header[24..28], entry.uncompressed_size, .little);
    std.mem.writeInt(u16, header[28..30], @intCast(entry.name.len), .little);
    std.mem.writeInt(u16, header[30..32], 0, .little); // extra field length
    std.mem.writeInt(u16, header[32..34], 0, .little); // comment length
    std.mem.writeInt(u16, header[34..36], 0, .little); // disk number
    std.mem.writeInt(u16, header[36..38], 0, .little); // internal attributes
    // External attributes: Unix mode plus the MS-DOS directory bit.
    const external_attributes: u32 = (entry.mode << 16) | (if (entry.directory) @as(u32, 0x10) else 0);
    std.mem.writeInt(u32, header[38..42], external_attributes, .little);
    std.mem.writeInt(u32, header[42..46], entry.offset, .little);
    try writer.writeAll(&header);
    try writer.writeAll(entry.name);
}

fn writeEndOfCentralDirectory(
    writer: *Io.Writer,
    entry_count: u16,
    central_size: u32,
    central_offset: u32,
) !void {
    var header: [22]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], end_of_central_directory_signature, .little);
    std.mem.writeInt(u16, header[4..6], 0, .little);
    std.mem.writeInt(u16, header[6..8], 0, .little);
    std.mem.writeInt(u16, header[8..10], entry_count, .little);
    std.mem.writeInt(u16, header[10..12], entry_count, .little);
    std.mem.writeInt(u32, header[12..16], central_size, .little);
    std.mem.writeInt(u32, header[16..20], central_offset, .little);
    std.mem.writeInt(u16, header[20..22], 0, .little);
    try writer.writeAll(&header);
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
