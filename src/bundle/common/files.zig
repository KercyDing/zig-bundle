//! File copying and writing helpers shared by layout formats.
const std = @import("std");

const Io = std.Io;

pub fn filePermissions(executable: bool) Io.File.Permissions {
    if (comptime Io.File.Permissions.has_executable_bit) {
        return Io.File.Permissions.fromMode(if (executable) 0o755 else 0o644);
    }
    return if (executable) Io.File.Permissions.executable_file else Io.File.Permissions.default_file;
}

/// Copies a host file to `dest`, creating parent directories.
pub fn copyFile(io: Io, source: []const u8, dest: []const u8, executable: bool) !void {
    try Io.Dir.cwd().copyFile(source, Io.Dir.cwd(), dest, io, .{
        .permissions = filePermissions(executable),
        .make_path = true,
    });
}

/// Writes bytes to `path`, creating parent directories.
pub fn writeBytes(io: Io, path: []const u8, bytes: []const u8, executable: bool) !void {
    if (std.Io.Dir.path.dirname(path)) |dir| try Io.Dir.cwd().createDirPath(io, dir);
    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = bytes,
        .flags = .{ .permissions = filePermissions(executable), .truncate = true },
    });
}
