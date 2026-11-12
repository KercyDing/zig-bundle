//! Native macOS application bundle layout.
const std = @import("std");

const files = @import("../common/files.zig");
const icons = @import("../common/icons.zig");
const manifest = @import("../../manifest.zig");
const resources = @import("../common/resources.zig");

const Io = std.Io;

pub const Config = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    executable_name: []const u8,
    payload: []const resources.Entry,
    icons: []const icons.Png = &.{},
    /// ICNS file copied as-is; takes precedence over generated icons.
    icns_path: ?[]const u8 = null,
    /// Extra keys appended to `Info.plist`.
    plist_entries: []const manifest.PlistEntry = &.{},
};

/// Writes a complete `.app` directory at `app_dir`.
pub fn bundle(io: Io, app_dir: []const u8, config: Config, allocator: std.mem.Allocator) !void {
    Io.Dir.cwd().deleteTree(io, app_dir) catch {};

    const contents = try std.Io.Dir.path.join(allocator, &.{ app_dir, "Contents" });
    const macos = try std.Io.Dir.path.join(allocator, &.{ contents, "MacOS" });
    const resources_dir = try std.Io.Dir.path.join(allocator, &.{ contents, "Resources" });
    try Io.Dir.cwd().createDirPath(io, macos);
    try Io.Dir.cwd().createDirPath(io, resources_dir);

    for (config.payload) |entry| {
        const dest = if (entry.executable)
            try std.Io.Dir.path.join(allocator, &.{ macos, entry.archive_path })
        else
            try std.Io.Dir.path.join(allocator, &.{ resources_dir, entry.archive_path });

        switch (entry.kind) {
            .dir => try Io.Dir.cwd().createDirPath(io, dest),
            .file => try files.copyFile(io, entry.source_path, dest, entry.executable),
        }
    }

    const icon_file: ?[]const u8 = if (config.icns_path) |icns_path| blk: {
        const dest = try std.Io.Dir.path.join(allocator, &.{ resources_dir, "icon.icns" });
        try files.copyFile(io, icns_path, dest, false);
        break :blk "icon.icns";
    } else if (icons.hasIcnsSource(config.icons)) blk: {
        const dest = try std.Io.Dir.path.join(allocator, &.{ resources_dir, "icon.icns" });
        var file = try Io.Dir.cwd().createFile(io, dest, .{ .truncate = true });
        defer file.close(io);
        try icons.writeIcns(io, file, config.icons);
        break :blk "icon.icns";
    } else if (config.icons.len > 0) {
        return error.MissingIcon;
    } else null;

    const plist = try renderInfoPlist(allocator, .{
        .name = config.name,
        .identifier = config.identifier,
        .version = config.version,
        .executable_name = config.executable_name,
        .icon_file = icon_file,
        .plist_entries = config.plist_entries,
    });
    try files.writeBytes(io, try std.Io.Dir.path.join(allocator, &.{ contents, "Info.plist" }), plist, false);
    try files.writeBytes(io, try std.Io.Dir.path.join(allocator, &.{ contents, "PkgInfo" }), "APPL????", false);
}

pub const Info = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    executable_name: []const u8,
    icon_file: ?[]const u8 = null,
    plist_entries: []const manifest.PlistEntry = &.{},
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

    for (info.plist_entries) |entry| {
        try writer.writeAll("  <key>");
        try writeXmlEscaped(writer, entry.key);
        try writer.writeAll("</key>\n");
        switch (entry.value) {
            .string => |value| {
                try writer.writeAll("  <string>");
                try writeXmlEscaped(writer, value);
                try writer.writeAll("</string>\n");
            },
            .boolean => |value| try writer.print("  <{s}/>\n", .{if (value) "true" else "false"}),
            .integer => |value| try writer.print("  <integer>{d}</integer>\n", .{value}),
        }
    }

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

test "provided icns is copied verbatim" {
    const io = std.testing.io;

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "custom.icns", .data = "custom icon" });

    const icns_path = try tmp.dir.realPathFileAlloc(io, "custom.icns", allocator);

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_len = try tmp.dir.realPath(io, &path_buffer);
    const app_dir = try std.Io.Dir.path.join(allocator, &.{ path_buffer[0..path_len], "Test.app" });

    try bundle(io, app_dir, .{
        .name = "Test",
        .identifier = "com.example.test",
        .version = "1.0.0",
        .executable_name = "test",
        .payload = &.{},
        .icns_path = icns_path,
    }, allocator);

    const copied_path = try std.Io.Dir.path.join(allocator, &.{ app_dir, "Contents", "Resources", "icon.icns" });
    const copied = try Io.Dir.cwd().readFileAlloc(io, copied_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("custom icon", copied);

    const plist_path = try std.Io.Dir.path.join(allocator, &.{ app_dir, "Contents", "Info.plist" });
    const plist = try Io.Dir.cwd().readFileAlloc(io, plist_path, allocator, .limited(16 * 1024));
    try std.testing.expect(std.mem.indexOf(u8, plist, "<string>icon.icns</string>") != null);
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

test "info plist includes extra entries" {
    const allocator = std.testing.allocator;

    const plist = try renderInfoPlist(allocator, .{
        .name = "App",
        .identifier = "com.example.app",
        .version = "1.0.0",
        .executable_name = "app",
        .plist_entries = &.{
            .{ .key = "LSUIElement", .value = .{ .boolean = true } },
            .{ .key = "LSMinimumSystemVersion", .value = .{ .string = "13.0" } },
            .{ .key = "BuildNumber", .value = .{ .integer = 7 } },
        },
    });
    defer allocator.free(plist);

    try std.testing.expect(std.mem.indexOf(u8, plist, "<key>LSUIElement</key>\n  <true/>") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "<key>LSMinimumSystemVersion</key>\n  <string>13.0</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "<key>BuildNumber</key>\n  <integer>7</integer>") != null);
}
