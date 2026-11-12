//! Windows setup.exe packaging via the system NSIS `makensis`.
const std = @import("std");

const files = @import("../common/files.zig");
const resources = @import("../common/resources.zig");

const Io = std.Io;

pub const Scope = enum { current_user, all_users };

pub const Config = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    publisher: []const u8 = "",
    copyright: []const u8 = "",
    scope: Scope,
    arch: []const u8,
    executable_name: []const u8,
    start_menu: bool = true,
    desktop: bool = false,
    launch: bool = true,
    payload: []const resources.Entry,
    icon_path: ?[]const u8 = null,
    icon_name: ?[]const u8 = null,
    makensis: ?[]const u8 = null,
    nsis_dir: ?[]const u8 = null,
};

/// Builds the installer with `makensis`.
pub fn bundle(
    io: Io,
    env_map: *const std.process.Environ.Map,
    config: Config,
    output_dir: []const u8,
    output_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    const tool = try findTool(io, allocator, env_map, config.makensis);
    const staging = try std.fmt.allocPrint(allocator, "{s}/.nsis-{s}", .{ output_dir, config.name });

    Io.Dir.cwd().deleteTree(io, staging) catch {};
    defer Io.Dir.cwd().deleteTree(io, staging) catch {};
    try Io.Dir.cwd().createDirPath(io, staging);

    const payload_dir = try std.fmt.allocPrint(allocator, "{s}/payload", .{staging});
    try Io.Dir.cwd().createDirPath(io, payload_dir);

    for (config.payload) |entry| {
        const dest = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ payload_dir, entry.archive_path });
        switch (entry.kind) {
            .dir => try Io.Dir.cwd().createDirPath(io, dest),
            .file => try files.copyFile(io, entry.source_path, dest, entry.executable),
        }
    }

    const icon_name = config.icon_name orelse "icon.ico";
    if (config.icon_path) |icon_path| {
        try files.copyFile(io, icon_path, try std.fmt.allocPrint(allocator, "{s}/{s}", .{ payload_dir, icon_name }), false);
        try files.copyFile(io, icon_path, try std.fmt.allocPrint(allocator, "{s}/icon.ico", .{staging}), false);
    }

    const script_path = try std.fmt.allocPrint(allocator, "{s}/installer.nsi", .{staging});
    try files.writeBytes(io, script_path, try renderScript(allocator, config, icon_name, output_path), false);

    Io.Dir.cwd().deleteFile(io, output_path) catch {};

    var child_environment: ?std.process.Environ.Map = null;
    defer if (child_environment) |*environment| environment.deinit();
    if (config.nsis_dir) |nsis_dir| {
        child_environment = try env_map.clone(allocator);
        try child_environment.?.put("NSISDIR", nsis_dir);
    }

    var child = std.process.spawn(io, .{
        .argv = &.{
            tool,
            "-INPUTCHARSET",
            "UTF8",
            "-V3",
            "installer.nsi",
        },
        .cwd = .{ .path = staging },
        .environ_map = if (child_environment) |*environment| environment else null,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.MakensisNotFound,
        else => return err,
    };

    const stdout = readAll(io, child.stdout.?, allocator) catch "";
    const stderr = readAll(io, child.stderr.?, allocator) catch "";
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) {
            std.debug.print("{s}{s}", .{ stdout, stderr });
            return error.MakensisFailed;
        },
        else => {
            std.debug.print("{s}{s}", .{ stdout, stderr });
            return error.MakensisFailed;
        },
    }

    _ = Io.Dir.cwd().statFile(io, output_path, .{}) catch return error.MakensisFailed;
}

fn renderScript(allocator: std.mem.Allocator, config: Config, icon_name: []const u8, output_path: []const u8) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    const root = switch (config.scope) {
        .current_user => "HKCU",
        .all_users => "HKLM",
    };
    const shell_context = switch (config.scope) {
        .current_user => "current",
        .all_users => "all",
    };
    const execution_level = switch (config.scope) {
        .current_user => "user",
        .all_users => "admin",
    };
    const default_dir_prefix = switch (config.scope) {
        .current_user => "$LOCALAPPDATA\\Programs\\",
        .all_users => if (std.mem.eql(u8, config.arch, "x86"))
            "$PROGRAMFILES\\"
        else
            "$PROGRAMFILES64\\",
    };
    const uninstall_key = try std.fmt.allocPrint(
        allocator,
        "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{s}",
        .{config.identifier},
    );
    const uninstall_key_escaped = try escape(allocator, uninstall_key);

    try writer.writeAll("Unicode true\n!include \"MUI2.nsh\"\n!include \"nsDialogs.nsh\"\n\n");
    try writer.print("!define START_MENU_DEFAULT {d}\n", .{@intFromBool(config.start_menu)});
    try writer.print("!define DESKTOP_DEFAULT {d}\n", .{@intFromBool(config.desktop)});
    try writer.writeAll("Var StartMenuCheckbox\nVar DesktopCheckbox\n");
    try writer.writeAll("!define MUI_ABORTWARNING\n");
    try writer.writeAll("!insertmacro MUI_PAGE_WELCOME\n");
    try writer.writeAll("!insertmacro MUI_PAGE_DIRECTORY\n");
    try writer.writeAll("!insertmacro MUI_PAGE_INSTFILES\n");
    if (config.launch) {
        try writer.writeAll("!define MUI_FINISHPAGE_RUN \"$INSTDIR\\");
        try writeEscaped(writer, config.executable_name);
        try writer.writeAll("\"\n");
    }
    try writer.writeAll("!define MUI_PAGE_CUSTOMFUNCTION_SHOW FinishPageShow\n");
    try writer.writeAll("!define MUI_PAGE_CUSTOMFUNCTION_LEAVE FinishPageLeave\n");
    try writer.writeAll("!insertmacro MUI_PAGE_FINISH\n");
    try writer.writeAll("!insertmacro MUI_UNPAGE_CONFIRM\n");
    try writer.writeAll("!insertmacro MUI_UNPAGE_INSTFILES\n");
    try writer.writeAll("!insertmacro MUI_LANGUAGE \"English\"\n\n");

    try writer.writeAll("Name \"");
    try writeEscaped(writer, config.name);
    try writer.writeAll("\"\nOutFile \"");
    try writeEscaped(writer, output_path);
    try writer.writeAll("\"\nBrandingText \"");
    try writeEscaped(writer, config.name);
    try writer.writeAll(" Setup\"\nInstallDir \"");
    try writer.writeAll(default_dir_prefix);
    try writeEscaped(writer, config.name);
    try writer.writeAll("\"\nInstallDirRegKey ");
    try writer.writeAll(root);
    try writer.writeAll(" \"");
    try writeEscaped(writer, uninstall_key);
    try writer.writeAll("\" \"InstallLocation\"\n");
    // NSIS is DPI-unaware by default, so Windows bitmap-scales the UI.
    try writer.writeAll("ManifestDPIAware true\n");
    try writer.print("RequestExecutionLevel {s}\n", .{execution_level});

    const reg_view = if (std.mem.eql(u8, config.arch, "x86")) "32" else "64";
    try writer.print("Function .onInit\n  SetRegView {s}\nFunctionEnd\n\n", .{reg_view});
    try writer.print("Function un.onInit\n  SetRegView {s}\nFunctionEnd\n\n", .{reg_view});

    if (versionInfo(allocator, config.version)) |version_info| {
        try writer.print("VIProductVersion \"{s}\"\n", .{version_info});
        try writer.writeAll("VIAddVersionKey \"ProductName\" \"");
        try writeEscaped(writer, config.name);
        try writer.writeAll("\"\nVIAddVersionKey \"ProductVersion\" \"");
        try writeEscaped(writer, config.version);
        try writer.writeAll("\"\nVIAddVersionKey \"FileVersion\" \"");
        try writeEscaped(writer, config.version);
        try writer.writeAll("\"\nVIAddVersionKey \"FileDescription\" \"");
        try writeEscaped(writer, config.name);
        try writer.writeAll(" Setup\"\n");
        if (config.publisher.len > 0) {
            try writer.writeAll("VIAddVersionKey \"CompanyName\" \"");
            try writeEscaped(writer, config.publisher);
            try writer.writeAll("\"\n");
        }
        if (config.copyright.len > 0) {
            try writer.writeAll("VIAddVersionKey \"LegalCopyright\" \"");
            try writeEscaped(writer, config.copyright);
            try writer.writeAll("\"\n");
        }
    }
    if (config.icon_path != null) {
        try writer.writeAll("Icon \"icon.ico\"\nUninstallIcon \"icon.ico\"\n");
    }
    try writer.writeByte('\n');

    try writer.writeAll("Section \"Install\"\n");
    try writer.print("  SetShellVarContext {s}\n", .{shell_context});
    try writer.writeAll("  SetOutPath \"$INSTDIR\"\n  File /r \"payload\\*.*\"\n");
    try writer.writeAll("  WriteUninstaller \"$INSTDIR\\uninstall.exe\"\n");

    if (config.start_menu or config.desktop) {
        try writer.writeAll("  IfSilent zb_shortcuts_create zb_shortcuts_done\nzb_shortcuts_create:\n");
        if (config.start_menu) {
            try writer.writeAll("  CreateShortCut \"$SMPROGRAMS\\");
            try writeEscaped(writer, config.name);
            try writer.writeAll(".lnk\" \"$INSTDIR\\");
            try writeEscaped(writer, config.executable_name);
            try writer.writeAll("\" \"\" \"$INSTDIR\\");
            try writeEscaped(writer, if (config.icon_path != null) icon_name else config.executable_name);
            try writer.writeAll("\" 0\n");
        }
        if (config.desktop) {
            try writer.writeAll("  CreateShortCut \"$DESKTOP\\");
            try writeEscaped(writer, config.name);
            try writer.writeAll(".lnk\" \"$INSTDIR\\");
            try writeEscaped(writer, config.executable_name);
            try writer.writeAll("\" \"\" \"$INSTDIR\\");
            try writeEscaped(writer, if (config.icon_path != null) icon_name else config.executable_name);
            try writer.writeAll("\" 0\n");
        }
        try writer.writeAll("  Goto zb_shortcuts_done\nzb_shortcuts_done:\n");
    }

    try writer.print("  WriteRegStr {s} \"{s}\" \"DisplayName\" \"", .{ root, uninstall_key_escaped });
    try writeEscaped(writer, config.name);
    try writer.writeAll("\"\n");
    try writer.print("  WriteRegStr {s} \"{s}\" \"DisplayVersion\" \"", .{ root, uninstall_key_escaped });
    try writeEscaped(writer, config.version);
    try writer.writeAll("\"\n");
    if (config.publisher.len > 0) {
        try writer.print("  WriteRegStr {s} \"{s}\" \"Publisher\" \"", .{ root, uninstall_key_escaped });
        try writeEscaped(writer, config.publisher);
        try writer.writeAll("\"\n");
    }
    try writer.print("  WriteRegStr {s} \"{s}\" \"InstallLocation\" \"$INSTDIR\"\n", .{ root, uninstall_key_escaped });
    if (config.icon_path != null) {
        try writer.print("  WriteRegStr {s} \"{s}\" \"DisplayIcon\" \"$INSTDIR\\", .{ root, uninstall_key_escaped });
        try writeEscaped(writer, icon_name);
        try writer.writeAll("\"\n");
    } else {
        try writer.print("  WriteRegStr {s} \"{s}\" \"DisplayIcon\" \"$INSTDIR\\", .{ root, uninstall_key_escaped });
        try writeEscaped(writer, config.executable_name);
        try writer.writeAll("\"\n");
    }
    try writer.print("  WriteRegStr {s} \"{s}\" \"UninstallString\" \"$\\\"$INSTDIR\\uninstall.exe$\\\"\"\n", .{ root, uninstall_key_escaped });
    try writer.print("  WriteRegStr {s} \"{s}\" \"QuietUninstallString\" \"$\\\"$INSTDIR\\uninstall.exe$\\\" /S\"\n", .{ root, uninstall_key_escaped });
    try writer.print("  WriteRegDWORD {s} \"{s}\" \"NoModify\" 1\n", .{ root, uninstall_key_escaped });
    try writer.print("  WriteRegDWORD {s} \"{s}\" \"NoRepair\" 1\n", .{ root, uninstall_key_escaped });
    try writer.writeAll("SectionEnd\n\n");

    try writer.writeAll("Section \"Uninstall\"\n");
    try writer.print("  SetShellVarContext {s}\n", .{shell_context});
    try writer.writeAll("  Delete \"$SMPROGRAMS\\");
    try writeEscaped(writer, config.name);
    try writer.writeAll(".lnk\"\n  Delete \"$DESKTOP\\");
    try writeEscaped(writer, config.name);
    try writer.writeAll(".lnk\"\n  Delete \"$INSTDIR\\uninstall.exe\"\n  RMDir /r \"$INSTDIR\"\n");
    try writer.print("  DeleteRegKey {s} \"{s}\"\n", .{ root, uninstall_key_escaped });
    try writer.writeAll("SectionEnd\n\n");

    const shortcut_icon = if (config.icon_path != null) icon_name else config.executable_name;

    try writer.writeAll(
        "Function FinishPageShow\n" ++
            "  ${NSD_CreateCheckbox} 120u 105u 195u 10u \"Create a Start Menu shortcut\"\n" ++
            "  Pop $StartMenuCheckbox\n" ++
            "  SetCtlColors $StartMenuCheckbox \"${MUI_TEXTCOLOR}\" \"${MUI_BGCOLOR}\"\n" ++
            "  SendMessage $StartMenuCheckbox 0x00F1 ${START_MENU_DEFAULT} 0\n" ++
            "  ${NSD_CreateCheckbox} 120u 120u 195u 10u \"Create a desktop shortcut\"\n" ++
            "  Pop $DesktopCheckbox\n" ++
            "  SetCtlColors $DesktopCheckbox \"${MUI_TEXTCOLOR}\" \"${MUI_BGCOLOR}\"\n" ++
            "  SendMessage $DesktopCheckbox 0x00F1 ${DESKTOP_DEFAULT} 0\n" ++
            "FunctionEnd\n\n" ++
            "Function FinishPageLeave\n" ++
            "  SendMessage $StartMenuCheckbox 0x00F0 0 0 $0\n" ++
            "  StrCmp $0 \"1\" zb_start_menu_create zb_start_menu_remove\n" ++
            "zb_start_menu_create:\n" ++
            "  CreateShortCut \"$SMPROGRAMS\\",
    );
    try writeEscaped(writer, config.name);
    try writer.writeAll(".lnk\" \"$INSTDIR\\");
    try writeEscaped(writer, config.executable_name);
    try writer.writeAll("\" \"\" \"$INSTDIR\\");
    try writeEscaped(writer, shortcut_icon);
    try writer.writeAll("\" 0\n  Goto zb_start_menu_done\n" ++
        "zb_start_menu_remove:\n" ++
        "  Delete \"$SMPROGRAMS\\");
    try writeEscaped(writer, config.name);
    try writer.writeAll(".lnk\"\n" ++
        "zb_start_menu_done:\n" ++
        "  SendMessage $DesktopCheckbox 0x00F0 0 0 $0\n" ++
        "  StrCmp $0 \"1\" zb_desktop_create zb_desktop_remove\n" ++
        "zb_desktop_create:\n" ++
        "  CreateShortCut \"$DESKTOP\\");
    try writeEscaped(writer, config.name);
    try writer.writeAll(".lnk\" \"$INSTDIR\\");
    try writeEscaped(writer, config.executable_name);
    try writer.writeAll("\" \"\" \"$INSTDIR\\");
    try writeEscaped(writer, shortcut_icon);
    try writer.writeAll("\" 0\n  Goto zb_desktop_done\n" ++
        "zb_desktop_remove:\n" ++
        "  Delete \"$DESKTOP\\");
    try writeEscaped(writer, config.name);
    try writer.writeAll(".lnk\"\n" ++
        "zb_desktop_done:\n" ++
        "FunctionEnd\n\n");

    return allocating.toOwnedSlice();
}

fn versionInfo(allocator: std.mem.Allocator, version: []const u8) ?[]const u8 {
    const parsed = std.SemanticVersion.parse(version) catch return null;
    return std.fmt.allocPrint(allocator, "{d}.{d}.{d}.0", .{
        parsed.major,
        parsed.minor,
        parsed.patch,
    }) catch null;
}

fn escape(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    try writeEscaped(&allocating.writer, text);
    return allocating.toOwnedSlice();
}

fn writeEscaped(writer: *Io.Writer, text: []const u8) !void {
    for (text) |c| switch (c) {
        '$' => try writer.writeAll("$$"),
        '"' => try writer.writeAll("$\\\""),
        '\n' => try writer.writeAll("$\\r$\\n"),
        '\r' => {},
        '\t' => try writer.writeAll("$\\t"),
        else => try writer.writeByte(c),
    };
}

fn findTool(
    io: Io,
    allocator: std.mem.Allocator,
    env_map: *const std.process.Environ.Map,
    configured: ?[]const u8,
) ![]const u8 {
    const name = configured orelse "makensis";
    if (std.mem.indexOfScalar(u8, name, '/') != null or std.mem.indexOfScalar(u8, name, '\\') != null) {
        return name;
    }

    const path = env_map.get("PATH") orelse return error.MakensisNotFound;
    var dirs = std.mem.tokenizeScalar(u8, path, std.fs.path.delimiter);
    while (dirs.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fs.path.join(allocator, &.{ dir, name });
        Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch continue;
        return candidate;
    }
    return error.MakensisNotFound;
}

test "nsis script keeps expansion variables" {
    const config: Config = .{
        .name = "App",
        .identifier = "com.example.app",
        .version = "1.0.0",
        .scope = .current_user,
        .arch = "x86_64",
        .executable_name = "app.exe",
        .payload = &.{},
    };

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const script = try renderScript(arena_state.allocator(), config, "app.ico", "/tmp/App-setup.exe");

    try std.testing.expect(std.mem.indexOf(u8, script, "InstallDir \"$LOCALAPPDATA\\Programs\\App\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "$$LOCALAPPDATA") == null);
}

test "nsis script enables dpi awareness" {
    const config: Config = .{
        .name = "App",
        .identifier = "com.example.app",
        .version = "1.0.0",
        .scope = .current_user,
        .arch = "x86_64",
        .executable_name = "app.exe",
        .payload = &.{},
    };

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const script = try renderScript(arena_state.allocator(), config, "app.ico", "/tmp/App-setup.exe");
    try std.testing.expect(std.mem.indexOf(u8, script, "ManifestDPIAware true") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "VIProductVersion \"1.0.0.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "BrandingText \"App Setup\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "SetRegView 64") != null);
}

test "nsis finish page offers shortcut choices" {
    const config: Config = .{
        .name = "App",
        .identifier = "com.example.app",
        .version = "1.0.0",
        .scope = .current_user,
        .arch = "x86_64",
        .executable_name = "app.exe",
        .payload = &.{},
    };

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const script = try renderScript(arena_state.allocator(), config, "app.ico", "/tmp/App-setup.exe");
    try std.testing.expect(std.mem.indexOf(u8, script, "MUI_PAGE_CUSTOMFUNCTION_SHOW FinishPageShow") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "Create a Start Menu shortcut") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "Create a desktop shortcut") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "IfSilent zb_shortcuts_create zb_shortcuts_done") != null);
}

fn readAll(io: Io, file: Io.File, allocator: std.mem.Allocator) ![]u8 {
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return reader.interface.allocRemaining(allocator, .limited(1024 * 1024));
}
