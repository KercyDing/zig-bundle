//! macOS disk image creation via the system `hdiutil`.
const std = @import("std");

const app = @import("app.zig");
const icons = @import("../common/icons.zig");
const resources = @import("../common/resources.zig");

const Io = std.Io;

pub const Config = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    executable_name: []const u8,
    payload: []const resources.Entry,
    icons: []const icons.Png = &.{},
    icns_path: ?[]const u8 = null,
};

/// Stages the `.app` with an `/Applications` symlink and writes a UDZO image.
pub fn bundle(
    io: Io,
    config: Config,
    output_dir: []const u8,
    output_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    const stage = try std.fs.path.join(allocator, &.{ output_dir, ".stage" });
    const app_dir = try std.fmt.allocPrint(allocator, "{s}/{s}.app", .{ stage, config.name });
    const applications = try std.fs.path.join(allocator, &.{ stage, "Applications" });

    Io.Dir.cwd().deleteTree(io, stage) catch {};
    defer {
        // Remove the symlink explicitly before pruning the stage tree.
        Io.Dir.cwd().deleteFile(io, applications) catch {};
        Io.Dir.cwd().deleteTree(io, stage) catch {};
    }

    try Io.Dir.cwd().createDirPath(io, stage);
    try app.bundle(io, app_dir, .{
        .name = config.name,
        .identifier = config.identifier,
        .version = config.version,
        .executable_name = config.executable_name,
        .payload = config.payload,
        .icons = config.icons,
        .icns_path = config.icns_path,
    }, allocator);
    try Io.Dir.cwd().symLink(io, "/Applications", applications, .{ .is_directory = true });

    var child = std.process.spawn(io, .{
        .argv = &.{
            "hdiutil",   "create",
            "-quiet",    "-volname",
            config.name, "-srcfolder",
            stage,       "-ov",
            "-format",   "UDZO",
            output_path,
        },
        .stdin = .ignore,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.HdiutilNotFound,
        else => return err,
    };

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.HdiutilFailed,
        else => return error.HdiutilFailed,
    }
}
