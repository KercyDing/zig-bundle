const std = @import("std");

const flate = std.compress.flate;
const Io = std.Io;

const magic = "ZBSETUP1".*;
const footer_size = 48;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var silent = false;
    var target_dir: ?[]const u8 = null;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next(); // executable name

    const Option = enum { silent, dir };
    while (args.next()) |arg| {
        const option = std.meta.stringToEnum(Option, std.mem.trimStart(u8, arg, "-")) orelse
            return error.UnknownArgument;
        switch (option) {
            .silent => silent = true,
            .dir => target_dir = args.next() orelse return error.MissingDirectory,
        }
    }

    const executable_path = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(executable_path);

    var self_file = try Io.Dir.cwd().openFile(io, executable_path, .{});
    defer self_file.close(io);

    const file_stat = try self_file.stat(io);
    if (file_stat.size < footer_size) return error.InvalidSetup;

    var footer: [footer_size]u8 = undefined;
    if (try self_file.readPositionalAll(io, &footer, file_stat.size - footer_size) != footer.len) {
        return error.InvalidSetup;
    }
    if (!std.mem.eql(u8, footer[0..8], &magic)) return error.InvalidSetup;
    if (std.mem.readInt(u32, footer[8..12], .little) != 1) return error.UnsupportedVersion;

    const manifest_offset = std.mem.readInt(u64, footer[16..24], .little);
    const manifest_size = std.mem.readInt(u64, footer[24..32], .little);
    const payload_offset = std.mem.readInt(u64, footer[32..40], .little);

    const manifest = try gpa.alloc(u8, manifest_size);
    defer gpa.free(manifest);
    if (try self_file.readPositionalAll(io, manifest, manifest_offset) != manifest.len) {
        return error.InvalidSetup;
    }

    const name = manifestValue(manifest, "name") orelse return error.InvalidManifest;
    const version = manifestValue(manifest, "version") orelse "";

    const Scope = enum { current_user, all_users };
    const scope = std.meta.stringToEnum(Scope, manifestValue(manifest, "scope") orelse "current_user") orelse
        return error.InvalidManifest;

    const install_dir = if (target_dir) |dir|
        try gpa.dupe(u8, dir)
    else blk: {
        const base = switch (scope) {
            .current_user => init.environ_map.get("LOCALAPPDATA") orelse return error.MissingLocalAppData,
            .all_users => init.environ_map.get("ProgramFiles") orelse return error.MissingProgramFiles,
        };
        break :blk try std.fs.path.join(gpa, &.{ base, name });
    };
    defer gpa.free(install_dir);

    var output_dir = try Io.Dir.cwd().createDirPathOpen(io, install_dir, .{});
    defer output_dir.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = self_file.reader(io, &read_buffer);
    try reader.seekTo(payload_offset);

    var gzip_buffer: [flate.max_window_len]u8 = undefined;
    var gzip = flate.Decompress.init(&reader.interface, .gzip, &gzip_buffer);
    try extractPayload(init.arena.allocator(), io, output_dir, &gzip.reader);

    if (!silent) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout = Io.File.stdout().writerStreaming(io, &stdout_buffer);
        try stdout.interface.print("Installed {s} {s} to {s}\n", .{ name, version, install_dir });
        try stdout.interface.flush();
    }
}

/// Extracts with overwrite semantics, unlike `std.tar.extract`.
fn extractPayload(
    allocator: std.mem.Allocator,
    io: Io,
    output_dir: Io.Dir,
    reader: *Io.Reader,
) !void {
    var file_name_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    var link_name_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    var iterator = std.tar.Iterator.init(reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });

    while (try iterator.next()) |file| {
        const path = try sanitizeArchivePath(allocator, file.name);

        switch (file.kind) {
            .directory => try output_dir.createDirPath(io, path),
            .file => {
                if (std.fs.path.dirname(path)) |parent| {
                    try output_dir.createDirPath(io, parent);
                }

                var output = try output_dir.createFile(io, path, .{ .truncate = true });
                defer output.close(io);

                var write_buffer: [16 * 1024]u8 = undefined;
                var writer = output.writer(io, &write_buffer);
                try iterator.streamRemaining(file, &writer.interface);
                try writer.interface.flush();
            },
            else => return error.UnsupportedArchiveEntry,
        }
    }
}

fn sanitizeArchivePath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const trimmed = std.mem.trimEnd(u8, name, "/\\");
    if (trimmed.len == 0) return error.InvalidPath;
    if (trimmed[0] == '/' or trimmed[0] == '\\') return error.InvalidPath;

    const normalized = try allocator.alloc(u8, trimmed.len);
    for (trimmed, normalized) |c, *out| {
        out.* = if (c == '\\') '/' else c;
    }

    var parts = std.mem.splitScalar(u8, normalized, '/');
    while (parts.next()) |part| {
        if (part.len == 0) return error.InvalidPath;
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidPath;
        if (std.mem.indexOfScalar(u8, part, ':') != null) return error.InvalidPath;
    }
    return normalized;
}

fn manifestValue(manifest: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |line| {
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (!std.mem.eql(u8, line[0..separator], key)) continue;
        return std.mem.trimEnd(u8, line[separator + 1 ..], "\r");
    }
    return null;
}
