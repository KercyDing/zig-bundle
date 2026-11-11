//! Bundle payload entries and recursive resource staging.
const std = @import("std");

const Io = std.Io;

pub const Kind = enum { file, dir };

/// One entry in the bundle payload.
pub const Entry = struct {
    /// Path inside the archive, always using `/` separators.
    archive_path: []const u8,
    /// Absolute host path of the source file.
    source_path: []const u8,
    kind: Kind,
    /// Main executable gets the executable bit in Unix archives.
    executable: bool = false,
};

/// Ordered set of files and directories that make up the application payload.
pub const Payload = struct {
    entries: std.ArrayList(Entry) = .empty,

    pub fn deinit(self: *Payload, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn addFile(
        self: *Payload,
        allocator: std.mem.Allocator,
        source_path: []const u8,
        dest: []const u8,
        executable: bool,
    ) !void {
        try self.entries.append(allocator, .{
            .archive_path = try sanitizePath(allocator, dest),
            .source_path = try allocator.dupe(u8, source_path),
            .kind = .file,
            .executable = executable,
        });
    }

    /// Adds a directory tree. `dest` is the directory name inside the archive.
    pub fn addDirectory(
        self: *Payload,
        allocator: std.mem.Allocator,
        io: Io,
        source_path: []const u8,
        dest: []const u8,
    ) !void {
        const archive_path = try sanitizePath(allocator, dest);
        try self.entries.append(allocator, .{
            .archive_path = archive_path,
            .source_path = try allocator.dupe(u8, source_path),
            .kind = .dir,
        });

        var dir = try Io.Dir.openDirAbsolute(io, source_path, .{ .iterate = true });
        defer dir.close(io);

        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            const child_source = try std.fs.path.join(allocator, &.{ source_path, entry.name });
            const child_dest = try childArchivePath(allocator, archive_path, entry.name);
            switch (entry.kind) {
                .directory => try self.addDirectory(allocator, io, child_source, child_dest),
                .file => {
                    try self.entries.append(allocator, .{
                        .archive_path = child_dest,
                        .source_path = child_source,
                        .kind = .file,
                    });
                },
                .sym_link => return error.SymlinkNotSupported,
                else => return error.UnsupportedFileType,
            }
        }
    }

    /// Sorts entries so archive output is deterministic.
    pub fn sort(self: *Payload) void {
        std.mem.sort(Entry, self.entries.items, {}, struct {
            fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
                return std.mem.lessThan(u8, lhs.archive_path, rhs.archive_path);
            }
        }.lessThan);
    }
};

/// Validates a bundle-relative path and normalizes separators to `/`.
pub fn sanitizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const trimmed = std.mem.trimEnd(u8, path, "/\\");
    if (trimmed.len == 0) return error.InvalidPath;
    if (trimmed[0] == '/' or trimmed[0] == '\\') return error.InvalidPath;
    if (std.fs.path.isAbsolute(trimmed)) return error.InvalidPath;

    const normalized = try allocator.alloc(u8, trimmed.len);
    errdefer allocator.free(normalized);
    for (trimmed, normalized) |c, *out| {
        if (c == 0) return error.InvalidPath;
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

fn childArchivePath(allocator: std.mem.Allocator, base: []const u8, name: []const u8) ![]const u8 {
    if (name.len == 0 or std.mem.indexOfAny(u8, name, "/\\:") != null) return error.InvalidPath;
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, name });
}

test "sanitizePath normalizes separators" {
    const allocator = std.testing.allocator;
    const path = try sanitizePath(allocator, "assets\\data\\file.txt");
    defer allocator.free(path);
    try std.testing.expectEqualStrings("assets/data/file.txt", path);
}

test "sanitizePath rejects escaping paths" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidPath, sanitizePath(allocator, "../secret"));
    try std.testing.expectError(error.InvalidPath, sanitizePath(allocator, "a/../b"));
    try std.testing.expectError(error.InvalidPath, sanitizePath(allocator, "C:/windows"));
    try std.testing.expectError(error.InvalidPath, sanitizePath(allocator, "/absolute"));
    try std.testing.expectError(error.InvalidPath, sanitizePath(allocator, ""));
}
