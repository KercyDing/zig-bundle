const std = @import("std");

const resources = @import("../common/resources.zig");
const tar_gz = @import("../common/tar_gz.zig");

const Io = std.Io;

const magic = "ZBSETUP1".*;
const footer_size = 48;
const format_version: u32 = 1;
const compression_level: u4 = 6;

pub const Scope = enum { current_user, all_users };

pub const Config = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    scope: Scope,
    executable_name: []const u8,
    payload: []const resources.Entry,
    runtime_path: []const u8,
};

/// Layout: runtime | manifest | tar.gz payload | footer.
pub fn bundle(
    io: Io,
    file: Io.File,
    config: Config,
    allocator: std.mem.Allocator,
) !void {
    var items: std.ArrayList(tar_gz.Item) = .empty;
    defer items.deinit(allocator);

    for (config.payload) |entry| switch (entry.kind) {
        .dir => try items.append(allocator, .{
            .path = entry.archive_path,
            .kind = .dir,
            .mode = 0o755,
        }),
        .file => try items.append(allocator, .{
            .path = entry.archive_path,
            .kind = .file,
            .mode = switch (entry.executable) {
                true => 0o755,
                false => 0o644,
            },
            .content = .{ .file = entry.source_path },
        }),
    };

    var manifest: std.Io.Writer.Allocating = .init(allocator);
    defer manifest.deinit();

    const manifest_writer = &manifest.writer;

    try manifest_writer.print("name={s}\n", .{config.name});
    try manifest_writer.print("identifier={s}\n", .{config.identifier});
    try manifest_writer.print("version={s}\n", .{config.version});
    try manifest_writer.print("scope={s}\n", .{@tagName(config.scope)});
    try manifest_writer.print("exe={s}\n", .{config.executable_name});

    var out_buffer: [16 * 1024]u8 = undefined;
    var out = file.writer(io, &out_buffer);
    const writer = &out.interface;

    var runtime_file = try Io.Dir.cwd().openFile(io, config.runtime_path, .{});
    defer runtime_file.close(io);

    {
        var read_buffer: [16 * 1024]u8 = undefined;
        var runtime_reader = runtime_file.reader(io, &read_buffer);
        _ = try writer.sendFileAll(&runtime_reader, .unlimited);
    }

    const manifest_offset = out.logicalPos();
    try writer.writeAll(manifest.written());

    const payload_offset = out.logicalPos();
    try tar_gz.writeItemsTo(io, writer, items.items, compression_level);
    try writer.flush();

    const payload_size = out.logicalPos() - payload_offset;

    var footer: [footer_size]u8 = @splat(0);
    @memcpy(footer[0..8], &magic);

    std.mem.writeInt(u32, footer[8..12], format_version, .little);
    std.mem.writeInt(u32, footer[12..16], 0, .little);
    std.mem.writeInt(u64, footer[16..24], manifest_offset, .little);
    std.mem.writeInt(u64, footer[24..32], manifest.written().len, .little);
    std.mem.writeInt(u64, footer[32..40], payload_offset, .little);
    std.mem.writeInt(u64, footer[40..48], payload_size, .little);

    try writer.writeAll(&footer);
    try writer.flush();
}
