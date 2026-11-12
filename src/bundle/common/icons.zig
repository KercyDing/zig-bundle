//! Icon parsing and ICO generation.
const std = @import("std");

const Io = std.Io;

pub const Png = struct {
    path: []const u8,
    width: u32,
    height: u32,
};

pub fn readPng(io: Io, path: []const u8) !Png {
    var file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const source = &reader.interface;

    const signature = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    var actual_signature: [signature.len]u8 = undefined;
    try readExact(source, &actual_signature);
    if (!std.mem.eql(u8, &actual_signature, &signature)) return error.InvalidPng;

    var width: u32 = 0;
    var height: u32 = 0;
    var seen_ihdr = false;
    var seen_idat = false;

    var data_buffer: [4096]u8 = undefined;
    while (true) {
        var chunk_header: [8]u8 = undefined;
        try readExact(source, &chunk_header);

        const length = std.mem.readInt(u32, chunk_header[0..4], .big);
        const chunk_type = chunk_header[4..8];
        for (chunk_type) |c| {
            if (!std.ascii.isAlphabetic(c)) return error.InvalidPng;
        }
        if (length > 64 * 1024 * 1024) return error.InvalidPng;
        if (!seen_ihdr and !std.mem.eql(u8, chunk_type, "IHDR")) return error.InvalidPng;
        if (std.mem.eql(u8, chunk_type, "IHDR") and length != 13) return error.InvalidPng;
        if (std.mem.eql(u8, chunk_type, "IEND") and length != 0) return error.InvalidPng;

        var crc = std.hash.Crc32.init();
        crc.update(chunk_type);

        var ihdr: [13]u8 = undefined;
        var ihdr_len: usize = 0;
        var remaining: usize = length;
        while (remaining > 0) {
            const n = @min(remaining, data_buffer.len);
            try readExact(source, data_buffer[0..n]);
            crc.update(data_buffer[0..n]);

            if (!seen_ihdr and std.mem.eql(u8, chunk_type, "IHDR")) {
                @memcpy(ihdr[ihdr_len..][0..n], data_buffer[0..n]);
                ihdr_len += n;
            }
            remaining -= n;
        }

        var actual_crc: [4]u8 = undefined;
        try readExact(source, &actual_crc);
        if (crc.final() != std.mem.readInt(u32, &actual_crc, .big)) return error.InvalidPng;

        if (!seen_ihdr) {
            width = std.mem.readInt(u32, ihdr[0..4], .big);
            height = std.mem.readInt(u32, ihdr[4..8], .big);
            if (width == 0 or height == 0) return error.InvalidPng;
            seen_ihdr = true;
        } else if (std.mem.eql(u8, chunk_type, "IHDR")) {
            return error.InvalidPng;
        } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
            seen_idat = true;
        } else if (std.mem.eql(u8, chunk_type, "IEND")) {
            var trailing: [1]u8 = undefined;
            const n = source.readSliceShort(&trailing) catch return error.InvalidPng;
            if (n != 0) return error.InvalidPng;
            break;
        }
    }

    if (!seen_idat) return error.InvalidPng;
    return .{ .path = path, .width = width, .height = height };
}

fn readExact(reader: *Io.Reader, buffer: []u8) !void {
    reader.readSliceAll(buffer) catch |err| switch (err) {
        error.EndOfStream => return error.InvalidPng,
        error.ReadFailed => return error.ReadFailed,
    };
}

/// Packs square PNG sources (up to 256x256) into a PNG-compressed ICO.
pub fn writeIco(
    io: Io,
    file: Io.File,
    pngs: []const Png,
    allocator: std.mem.Allocator,
) !void {
    var selected: std.ArrayList(Png) = .empty;
    defer selected.deinit(allocator);

    for (pngs) |png| {
        if (png.width != png.height) continue;
        if (png.width == 0 or png.width > 256) continue;

        var duplicate = false;
        for (selected.items) |existing| {
            if (existing.width == png.width) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) try selected.append(allocator, png);
    }

    std.mem.sort(Png, selected.items, {}, struct {
        fn lessThan(_: void, lhs: Png, rhs: Png) bool {
            return lhs.width < rhs.width;
        }
    }.lessThan);

    if (selected.items.len == 0) return error.NoUsableIcon;
    if (selected.items.len > std.math.maxInt(u16)) return error.TooManyIcons;

    var out_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &out_buffer);

    var header: [6]u8 = undefined;
    std.mem.writeInt(u16, header[0..2], 0, .little);
    std.mem.writeInt(u16, header[2..4], 1, .little);
    std.mem.writeInt(u16, header[4..6], @intCast(selected.items.len), .little);
    try writer.interface.writeAll(&header);

    var offset: u32 = 6 + 16 * @as(u32, @intCast(selected.items.len));
    for (selected.items) |png| {
        const stat = try Io.Dir.cwd().statFile(io, png.path, .{});
        if (stat.size > std.math.maxInt(u32)) return error.IconTooLarge;

        var entry: [16]u8 = undefined;
        entry[0] = if (png.width == 256) 0 else @intCast(png.width);
        entry[1] = if (png.height == 256) 0 else @intCast(png.height);
        entry[2] = 0;
        entry[3] = 0;
        std.mem.writeInt(u16, entry[4..6], 1, .little);
        std.mem.writeInt(u16, entry[6..8], 32, .little);
        std.mem.writeInt(u32, entry[8..12], @intCast(stat.size), .little);
        std.mem.writeInt(u32, entry[12..16], offset, .little);
        try writer.interface.writeAll(&entry);

        offset += @intCast(stat.size);
    }

    for (selected.items) |png| {
        var source = try Io.Dir.cwd().openFile(io, png.path, .{});
        defer source.close(io);

        var read_buffer: [16 * 1024]u8 = undefined;
        var reader = source.reader(io, &read_buffer);
        _ = try writer.interface.sendFileAll(&reader, .unlimited);
    }

    try writer.interface.flush();
}

const icns_entries = [_]struct { size: u32, kind: [4]u8 }{
    .{ .size = 16, .kind = .{ 'i', 'c', 'p', '4' } },
    .{ .size = 32, .kind = .{ 'i', 'c', 'p', '5' } },
    .{ .size = 64, .kind = .{ 'i', 'c', 'p', '6' } },
    .{ .size = 128, .kind = .{ 'i', 'c', '0', '7' } },
    .{ .size = 256, .kind = .{ 'i', 'c', '0', '8' } },
    .{ .size = 512, .kind = .{ 'i', 'c', '0', '9' } },
    .{ .size = 1024, .kind = .{ 'i', 'c', '1', '0' } },
};

/// Returns whether at least one PNG can be embedded in an ICNS container.
pub fn hasIcnsSource(pngs: []const Png) bool {
    for (pngs) |png| {
        if (png.width != png.height) continue;
        for (icns_entries) |entry| {
            if (entry.size == png.width) return true;
        }
    }
    return false;
}

/// Packs square PNG sources into an ICNS container. Sizes without a matching
/// source are omitted; all sizes macOS uses are written when available.
pub fn writeIcns(io: Io, file: Io.File, pngs: []const Png) !void {
    var selected: [icns_entries.len]Png = undefined;
    var sizes: [icns_entries.len]u64 = undefined;
    var count: usize = 0;

    for (icns_entries) |entry| {
        for (pngs) |png| {
            if (png.width != entry.size or png.height != entry.size) continue;

            const stat = try Io.Dir.cwd().statFile(io, png.path, .{});
            selected[count] = png;
            sizes[count] = stat.size;
            count += 1;
            break;
        }
    }

    if (count == 0) return error.NoUsableIcon;

    var total: u64 = 8;
    for (sizes[0..count]) |size| total += 8 + size;
    if (total > std.math.maxInt(u32)) return error.IconTooLarge;

    var out_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &out_buffer);

    var header: [8]u8 = undefined;
    @memcpy(header[0..4], "icns");
    std.mem.writeInt(u32, header[4..8], @intCast(total), .big);
    try writer.interface.writeAll(&header);

    for (icns_entries[0..count], selected[0..count], sizes[0..count]) |entry, png, size| {
        var chunk_header: [8]u8 = undefined;
        @memcpy(chunk_header[0..4], &entry.kind);
        std.mem.writeInt(u32, chunk_header[4..8], @intCast(8 + size), .big);
        try writer.interface.writeAll(&chunk_header);

        var source = try Io.Dir.cwd().openFile(io, png.path, .{});
        defer source.close(io);

        var read_buffer: [16 * 1024]u8 = undefined;
        var reader = source.reader(io, &read_buffer);
        _ = try writer.interface.sendFileAll(&reader, .unlimited);
    }

    try writer.interface.flush();
}

test "icns writes big-endian chunk lengths" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "icon16.png", .data = "abc" });

    const png_path = try tmp.dir.realPathFileAlloc(io, "icon16.png", allocator);
    defer allocator.free(png_path);

    {
        var file = try tmp.dir.createFile(io, "icon.icns", .{});
        defer file.close(io);
        try writeIcns(io, file, &.{.{ .path = png_path, .width = 16, .height = 16 }});
    }

    const bytes = try tmp.dir.readFileAlloc(io, "icon.icns", allocator, .limited(1024));
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 19), bytes.len);
    try std.testing.expectEqualStrings("icns", bytes[0..4]);
    try std.testing.expectEqual(@as(u32, 19), std.mem.readInt(u32, bytes[4..8], .big));
    try std.testing.expectEqualStrings("icp4", bytes[8..12]);
    try std.testing.expectEqual(@as(u32, 11), std.mem.readInt(u32, bytes[12..16], .big));
    try std.testing.expectEqualStrings("abc", bytes[16..19]);
}
