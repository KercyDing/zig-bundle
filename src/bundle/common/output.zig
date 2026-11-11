//! Artifact paths and output file creation.
const std = @import("std");

const capabilities = @import("../../capabilities.zig");
const settings = @import("../../settings.zig");

const Io = std.Io;

/// Builds the output path for a format artifact.
pub fn artifactPath(
    io: Io,
    allocator: std.mem.Allocator,
    output_root: []const u8,
    format: capabilities.Format,
    config: *const settings.Settings,
    target_name: []const u8,
) ![]const u8 {
    const dir = try formatDir(io, allocator, output_root, format);

    const file_name = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}{s}", .{
        config.name,
        config.version,
        target_name,
        capabilities.extension(format),
    });
    return std.fs.path.join(allocator, &.{ dir, file_name });
}

/// Creates the directory for a format and returns it.
pub fn formatDir(
    io: Io,
    allocator: std.mem.Allocator,
    output_root: []const u8,
    format: capabilities.Format,
) ![]const u8 {
    const dir = try std.fs.path.join(allocator, &.{ output_root, @tagName(format) });
    try Io.Dir.cwd().createDirPath(io, dir);
    return dir;
}

/// Creates an artifact file, truncating an existing one.
pub fn create(io: Io, path: []const u8) !Io.File {
    // Truncate instead of delete+create: on Windows, deleting a freshly written
    // artifact can fail while a scanner still holds the file open.
    return Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
}
