//! Native macOS application bundle layout.
const std = @import("std");

const files = @import("../common/files.zig");
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
};

/// Writes a complete `.app` directory at `app_dir`.
pub fn bundle(io: Io, app_dir: []const u8, config: Config, allocator: std.mem.Allocator) !void {
    Io.Dir.cwd().deleteTree(io, app_dir) catch {};

    const contents = try std.fs.path.join(allocator, &.{ app_dir, "Contents" });
    const macos = try std.fs.path.join(allocator, &.{ contents, "MacOS" });
    const resources_dir = try std.fs.path.join(allocator, &.{ contents, "Resources" });
    try Io.Dir.cwd().createDirPath(io, macos);
    try Io.Dir.cwd().createDirPath(io, resources_dir);

    for (config.payload) |entry| {
        const dest = if (entry.executable)
            try std.fs.path.join(allocator, &.{ macos, entry.archive_path })
        else
            try std.fs.path.join(allocator, &.{ resources_dir, entry.archive_path });

        switch (entry.kind) {
            .dir => try Io.Dir.cwd().createDirPath(io, dest),
            .file => try files.copyFile(io, entry.source_path, dest, entry.executable),
        }
    }

    const has_icon = icons.hasIcnsSource(config.icons);
    if (!has_icon and config.icons.len > 0) return error.MissingIcon;

    if (has_icon) {
        const icon_path = try std.fs.path.join(allocator, &.{ resources_dir, "icon.icns" });
        var icon_file = try Io.Dir.cwd().createFile(io, icon_path, .{ .truncate = true });
        defer icon_file.close(io);
        try icons.writeIcns(io, icon_file, config.icons);
    }

    const plist = try renderInfoPlist(allocator, .{
        .name = config.name,
        .identifier = config.identifier,
        .version = config.version,
        .executable_name = config.executable_name,
        .icon_file = if (has_icon) "icon.icns" else null,
    });
    try files.writeBytes(io, try std.fs.path.join(allocator, &.{ contents, "Info.plist" }), plist, false);
    try files.writeBytes(io, try std.fs.path.join(allocator, &.{ contents, "PkgInfo" }), "APPL????", false);
}

pub const Info = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    executable_name: []const u8,
    icon_file: ?[]const u8 = null,
};

/// Renders the `Info.plist` property list.
pub fn renderInfoPlist(allocator: std.mem.Allocator, info: Info) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    const writer = &out.writer;
    try writer.writeAll(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\
    );

    try writeString(writer, "CFBundleDevelopmentRegion", "en");
    try writeString(writer, "CFBundleDisplayName", info.name);
    try writeString(writer, "CFBundleExecutable", info.executable_name);
    if (info.icon_file) |icon_file| try writeString(writer, "CFBundleIconFile", icon_file);
    try writeString(writer, "CFBundleIdentifier", info.identifier);
    try writeString(writer, "CFBundleInfoDictionaryVersion", "6.0");
    try writeString(writer, "CFBundleName", info.name);
    try writeString(writer, "CFBundlePackageType", "APPL");
    try writeString(writer, "CFBundleShortVersionString", info.version);
    try writeString(writer, "CFBundleVersion", info.version);
    try writer.writeAll("  <key>NSHighResolutionCapable</key>\n  <true/>\n");

    try writer.writeAll("</dict>\n</plist>\n");
    return out.toOwnedSlice();
}

fn writeString(writer: *Io.Writer, key: []const u8, value: []const u8) !void {
    try writer.writeAll("  <key>");
    try writeXmlEscaped(writer, key);
    try writer.writeAll("</key>\n  <string>");
    try writeXmlEscaped(writer, value);
    try writer.writeAll("</string>\n");
}

fn writeXmlEscaped(writer: *Io.Writer, value: []const u8) !void {
    for (value) |c| switch (c) {
        '&' => try writer.writeAll("&amp;"),
        '<' => try writer.writeAll("&lt;"),
        '>' => try writer.writeAll("&gt;"),
        '"' => try writer.writeAll("&quot;"),
        '\'' => try writer.writeAll("&apos;"),
        0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => {},
        else => try writer.writeByte(c),
    };
}

test "info plist escapes values" {
    const allocator = std.testing.allocator;

    const plist = try renderInfoPlist(allocator, .{
        .name = "A&B",
        .identifier = "com.example.a<b",
        .version = "1.0.0",
        .executable_name = "A&B",
        .icon_file = "icon.icns",
    });
    defer allocator.free(plist);

    try std.testing.expect(std.mem.indexOf(u8, plist, "<string>A&amp;B</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "<string>com.example.a&lt;b</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "<key>CFBundleIconFile</key>") != null);
}

test "info plist omits the icon key when no icon is available" {
    const allocator = std.testing.allocator;

    const plist = try renderInfoPlist(allocator, .{
        .name = "App",
        .identifier = "com.example.app",
        .version = "1.0.0",
        .executable_name = "app",
    });
    defer allocator.free(plist);

    try std.testing.expect(std.mem.indexOf(u8, plist, "CFBundleIconFile") == null);
}
