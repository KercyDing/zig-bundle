//! macOS disk image creation via the system `hdiutil`.
const std = @import("std");

const app = @import("app.zig");
const files = @import("../common/files.zig");
const icons = @import("../common/icons.zig");
const manifest = @import("../../manifest.zig");
const resources = @import("../common/resources.zig");

const Io = std.Io;

pub const Compression = enum { udzo, udbz, ulfo };

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const Position = struct {
    x: i32,
    y: i32,
};

pub const Layout = struct {
    background: ?[]const u8 = null,
    window_size: Size,
    icon_size: u32,
    app_position: Position,
    applications_position: Position,
};

pub const Config = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    executable_name: []const u8,
    payload: []const resources.Entry,
    icons: []const icons.Png = &.{},
    icns_path: ?[]const u8 = null,
    plist_entries: []const manifest.PlistEntry = &.{},
    volume_name: ?[]const u8 = null,
    compression: Compression = .udzo,
    applications_link: bool = true,
    layout: ?Layout = null,
};

/// Stages the `.app`, optionally applies a Finder layout, and writes a DMG.
pub fn bundle(
    io: Io,
    config: Config,
    output_dir: []const u8,
    output_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    const stage = try std.Io.Dir.path.join(allocator, &.{ output_dir, ".stage" });
    const app_dir = try std.fmt.allocPrint(allocator, "{s}/{s}.app", .{ stage, config.name });
    const applications = try std.Io.Dir.path.join(allocator, &.{ stage, "Applications" });

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
        .plist_entries = config.plist_entries,
    }, allocator);
    if (config.applications_link) {
        try Io.Dir.cwd().symLink(io, "/Applications", applications, .{ .is_directory = true });
    }
    const volume_name = config.volume_name orelse config.name;
    const format = switch (config.compression) {
        .udzo => "UDZO",
        .udbz => "UDBZ",
        .ulfo => "ULFO",
    };

    if (config.layout != null) {
        try bundleMounted(io, config, volume_name, format, stage, output_dir, output_path, allocator);
    } else {
        try run(io, &.{
            "hdiutil",   "create",
            "-quiet",    "-volname",
            volume_name, "-srcfolder",
            stage,       "-ov",
            "-format",   format,
            output_path,
        });
    }
}

fn bundleMounted(
    io: Io,
    config: Config,
    volume_name: []const u8,
    format: []const u8,
    stage: []const u8,
    output_dir: []const u8,
    output_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var background_name: ?[]const u8 = null;
    if (config.layout) |layout| {
        if (layout.background) |background| {
            const name = std.Io.Dir.path.basename(background);
            const dir = try std.Io.Dir.path.join(allocator, &.{ stage, ".background" });
            try Io.Dir.cwd().createDirPath(io, dir);
            try files.copyFile(io, background, try std.Io.Dir.path.join(allocator, &.{ dir, name }), false);
            try run(io, &.{ "chflags", "hidden", dir });
            background_name = name;
        }
    }

    const image = try std.Io.Dir.path.join(allocator, &.{ output_dir, ".layout.dmg" });
    Io.Dir.cwd().deleteFile(io, image) catch {};
    defer Io.Dir.cwd().deleteFile(io, image) catch {};

    try run(io, &.{
        "hdiutil",   "create",
        "-quiet",    "-volname",
        volume_name, "-srcfolder",
        stage,       "-fs",
        "HFS+",      "-format",
        "UDRW",      "-ov",
        image,
    });
    const mount = try attach(io, image, allocator);
    var mounted = true;
    defer if (mounted) run(io, &.{ "hdiutil", "detach", "-quiet", mount }) catch {};
    if (config.layout) |layout| {
        const mounted_name = std.Io.Dir.path.basename(mount);
        const script_path = try std.Io.Dir.path.join(allocator, &.{ output_dir, ".layout.applescript" });
        defer Io.Dir.cwd().deleteFile(io, script_path) catch {};
        try files.writeBytes(io, script_path, try renderAppleScript(allocator, config, layout, mounted_name, background_name), false);
        try runInherit(io, &.{ "osascript", script_path });
    }
    try run(io, &.{ "hdiutil", "detach", "-quiet", mount });
    mounted = false;
    try run(io, &.{ "hdiutil", "convert", "-quiet", image, "-format", format, "-ov", "-o", output_path });
}

fn renderAppleScript(
    allocator: std.mem.Allocator,
    config: Config,
    layout: Layout,
    volume_name: []const u8,
    background_name: ?[]const u8,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll("tell application \"Finder\"\n  tell disk \"");
    try writeEscaped(w, volume_name);
    try w.writeAll("\"\n    open\n    delay 2\n    set current view of container window to icon view\n");
    try w.writeAll("    set toolbar visible of container window to false\n");
    try w.writeAll("    set statusbar visible of container window to false\n");
    try w.print("    set the bounds of container window to {{100, 100, {d}, {d}}}\n", .{
        100 + @as(i64, layout.window_size.width),
        100 + @as(i64, layout.window_size.height),
    });
    try w.writeAll("    set arrangement of icon view options of container window to not arranged\n");
    try w.print("    set icon size of icon view options of container window to {d}\n", .{layout.icon_size});
    if (background_name) |name| {
        try w.writeAll("    set background picture of icon view options of container window to file \".background:");
        try writeEscaped(w, name);
        try w.writeAll("\"\n");
    }
    try w.writeAll("    set position of item \"");
    try writeEscaped(w, config.name);
    try w.writeAll(".app\" of container window to {");
    try w.print("{d}, {d}", .{ layout.app_position.x, layout.app_position.y });
    try w.writeAll("}\n");
    if (config.applications_link) {
        try w.writeAll("    set position of item \"Applications\" of container window to {");
        try w.print("{d}, {d}", .{ layout.applications_position.x, layout.applications_position.y });
        try w.writeAll("}\n");
    }
    try w.writeAll("    delay 1\n  end tell\nend tell\n");
    return out.toOwnedSlice();
}

fn writeEscaped(w: *Io.Writer, text: []const u8) !void {
    for (text) |c| switch (c) {
        '\\' => try w.writeAll("\\\\"),
        '"' => try w.writeAll("\\\""),
        else => try w.writeByte(c),
    };
}

fn attach(io: Io, image: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var child = std.process.spawn(io, .{
        .argv = &.{ "hdiutil", "attach", "-nobrowse", "-readwrite", image },
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.DmgToolNotFound,
        else => return err,
    };

    var buffer: [4096]u8 = undefined;
    var reader = child.stdout.?.reader(io, &buffer);
    const stdout = try reader.interface.allocRemaining(allocator, .limited(1024 * 1024));
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.DmgToolFailed,
        else => return error.DmgToolFailed,
    }

    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "/Volumes/")) |index| {
            return std.mem.trim(u8, line[index..], " \t\r");
        }
    }
    return error.DmgToolFailed;
}

fn runInherit(io: Io, argv: []const []const u8) !void {
    var child = std.process.spawn(io, .{ .argv = argv }) catch |err| switch (err) {
        error.FileNotFound => return error.DmgToolNotFound,
        else => return err,
    };
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.DmgToolFailed,
        else => return error.DmgToolFailed,
    }
}

fn run(io: Io, argv: []const []const u8) !void {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.DmgToolNotFound,
        else => return err,
    };

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) {
            std.debug.print("zig-bundle: DMG tool failed ({d}):", .{code});
            for (argv) |arg| std.debug.print(" {s}", .{arg});
            std.debug.print("\n", .{});
            return error.DmgToolFailed;
        },
        else => return error.DmgToolFailed,
    }
}
