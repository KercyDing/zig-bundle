const std = @import("std");

const flate = std.compress.flate;
const Io = std.Io;
const windows = std.os.windows;

const magic = "ZBSETUP1".*;
const footer_size = 48;

const HRESULT = i32;
const rpc_e_changed_mode: HRESULT = @bitCast(@as(u32, 0x80010106));
const clsctx_inproc_server: u32 = 1;
const coinit_apartment_threaded: u32 = 2;

const key_write: u32 = 0x20006;
const reg_sz: u32 = 1;
const reg_dword: u32 = 4;

const movfile_replace_existing: u32 = 0x1;
const movfile_delay_until_reboot: u32 = 0x4;

const sw_shownormal: c_int = 1;

const clsid_shell_link = windows.GUID{
    .Data1 = 0x00021401,
    .Data2 = 0,
    .Data3 = 0,
    .Data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 },
};

const iid_shell_link_w = windows.GUID{
    .Data1 = 0x000214F9,
    .Data2 = 0,
    .Data3 = 0,
    .Data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 },
};

const iid_persist_file = windows.GUID{
    .Data1 = 0x0000010B,
    .Data2 = 0,
    .Data3 = 0,
    .Data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 },
};

const Scope = enum { current_user, all_users };
const ShortcutKind = enum { start_menu, desktop };

const Manifest = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    publisher: []const u8,
    scope: Scope,
    executable_name: []const u8,
    start_menu: bool,
    desktop: bool,
    launch: bool,
    payload_offset: u64,
    payload_size: u64,
};

const IShellLinkW = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        QueryInterface: *const fn (*IShellLinkW, *const windows.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*IShellLinkW) callconv(.winapi) u32,
        Release: *const fn (*IShellLinkW) callconv(.winapi) u32,
        GetPath: *const anyopaque,
        GetIDList: *const anyopaque,
        SetIDList: *const anyopaque,
        GetDescription: *const anyopaque,
        SetDescription: *const fn (*IShellLinkW, [*:0]const u16) callconv(.winapi) HRESULT,
        GetWorkingDirectory: *const anyopaque,
        SetWorkingDirectory: *const fn (*IShellLinkW, [*:0]const u16) callconv(.winapi) HRESULT,
        GetArguments: *const anyopaque,
        SetArguments: *const fn (*IShellLinkW, [*:0]const u16) callconv(.winapi) HRESULT,
        GetHotkey: *const anyopaque,
        SetHotkey: *const anyopaque,
        GetShowCmd: *const anyopaque,
        SetShowCmd: *const fn (*IShellLinkW, c_int) callconv(.winapi) HRESULT,
        GetIconLocation: *const anyopaque,
        SetIconLocation: *const fn (*IShellLinkW, [*:0]const u16, c_int) callconv(.winapi) HRESULT,
        SetRelativePath: *const anyopaque,
        Resolve: *const anyopaque,
        SetPath: *const fn (*IShellLinkW, [*:0]const u16) callconv(.winapi) HRESULT,
    };
};

const IPersistFile = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        QueryInterface: *const fn (*IPersistFile, *const windows.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const anyopaque,
        Release: *const fn (*IPersistFile) callconv(.winapi) u32,
        GetClassID: *const anyopaque,
        IsDirty: *const anyopaque,
        Load: *const anyopaque,
        Save: *const fn (*IPersistFile, [*:0]const u16, c_int) callconv(.winapi) HRESULT,
        SaveCompleted: *const anyopaque,
        GetCurFile: *const anyopaque,
    };
};

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, coinit: u32) callconv(.winapi) HRESULT;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoCreateInstance(
    rclsid: *const windows.GUID,
    outer: ?*anyopaque,
    clsctx: u32,
    riid: *const windows.GUID,
    out: *?*anyopaque,
) callconv(.winapi) HRESULT;

extern "advapi32" fn RegCreateKeyExW(
    key: windows.HKEY,
    sub_key: windows.LPCWSTR,
    reserved: u32,
    class: ?windows.LPCWSTR,
    options: u32,
    sam: u32,
    security: ?*anyopaque,
    result: *windows.HKEY,
    disposition: ?*u32,
) callconv(.winapi) u32;
extern "advapi32" fn RegSetValueExW(
    key: windows.HKEY,
    value_name: windows.LPCWSTR,
    reserved: u32,
    value_type: u32,
    data: ?*const anyopaque,
    data_size: u32,
) callconv(.winapi) u32;
extern "advapi32" fn RegCloseKey(key: windows.HKEY) callconv(.winapi) u32;
extern "advapi32" fn RegDeleteTreeW(key: windows.HKEY, sub_key: windows.LPCWSTR) callconv(.winapi) u32;

extern "kernel32" fn MoveFileExW(
    existing: windows.LPCWSTR,
    new: ?windows.LPCWSTR,
    flags: u32,
) callconv(.winapi) c_int;

extern "shell32" fn ShellExecuteW(
    hwnd: ?*anyopaque,
    operation: ?windows.LPCWSTR,
    file: windows.LPCWSTR,
    parameters: ?windows.LPCWSTR,
    directory: ?windows.LPCWSTR,
    show: c_int,
) callconv(.winapi) ?*anyopaque;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var silent = false;
    var target_dir: ?[]const u8 = null;
    var uninstall = false;

    const Option = enum { silent, dir, uninstall };
    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next();

    while (args.next()) |arg| {
        const option = std.meta.stringToEnum(Option, std.mem.trimStart(u8, arg, "-")) orelse
            return error.UnknownArgument;
        switch (option) {
            .silent => silent = true,
            .dir => target_dir = args.next() orelse return error.MissingDirectory,
            .uninstall => uninstall = true,
        }
    }

    const executable_path = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(executable_path);

    const manifest = try readManifest(arena, io, executable_path);

    if (uninstall) {
        try uninstallApp(init, arena, executable_path, manifest, silent);
        return;
    }

    const install_dir = try chooseInstallDir(init, arena, manifest, target_dir, silent);
    try installApp(init, arena, executable_path, manifest, install_dir, silent);
}

fn readManifest(allocator: std.mem.Allocator, io: Io, executable_path: []const u8) !Manifest {
    var file = try Io.Dir.cwd().openFile(io, executable_path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    if (stat.size < footer_size) return error.InvalidSetup;

    var footer: [footer_size]u8 = undefined;
    if (try file.readPositionalAll(io, &footer, stat.size - footer_size) != footer.len) {
        return error.InvalidSetup;
    }
    if (!std.mem.eql(u8, footer[0..8], &magic)) return error.InvalidSetup;
    if (std.mem.readInt(u32, footer[8..12], .little) != 1) return error.UnsupportedVersion;

    const manifest_offset = std.mem.readInt(u64, footer[16..24], .little);
    const manifest_size = std.mem.readInt(u64, footer[24..32], .little);
    const payload_offset = std.mem.readInt(u64, footer[32..40], .little);
    const payload_size = std.mem.readInt(u64, footer[40..48], .little);

    if (payload_offset + payload_size + footer_size != stat.size) return error.InvalidSetup;

    const bytes = try allocator.alloc(u8, manifest_size);
    if (try file.readPositionalAll(io, bytes, manifest_offset) != bytes.len) {
        return error.InvalidSetup;
    }

    return .{
        .name = manifestValue(bytes, "name") orelse return error.InvalidManifest,
        .identifier = manifestValue(bytes, "identifier") orelse return error.InvalidManifest,
        .version = manifestValue(bytes, "version") orelse return error.InvalidManifest,
        .publisher = manifestValue(bytes, "publisher") orelse "",
        .scope = std.meta.stringToEnum(
            Scope,
            manifestValue(bytes, "scope") orelse "current_user",
        ) orelse return error.InvalidManifest,
        .executable_name = manifestValue(bytes, "exe") orelse return error.InvalidManifest,
        .start_menu = manifestBool(bytes, "start_menu", true),
        .desktop = manifestBool(bytes, "desktop", false),
        .launch = manifestBool(bytes, "launch", true),
        .payload_offset = payload_offset,
        .payload_size = payload_size,
    };
}

fn chooseInstallDir(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    manifest: Manifest,
    target_dir: ?[]const u8,
    silent: bool,
) ![]const u8 {
    if (target_dir) |dir| return allocator.dupe(u8, dir);

    const base = switch (manifest.scope) {
        .current_user => blk: {
            const local = init.environ_map.get("LOCALAPPDATA") orelse return error.MissingLocalAppData;
            break :blk try std.fs.path.join(allocator, &.{ local, "Programs" });
        },
        .all_users => init.environ_map.get("ProgramFiles") orelse return error.MissingProgramFiles,
    };
    const default_dir = try std.fs.path.join(allocator, &.{ base, manifest.name });
    if (silent) return default_dir;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    try stdout.interface.print("Install directory [{s}]: ", .{default_dir});
    try stdout.interface.flush();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin = Io.File.stdin().reader(init.io, &stdin_buffer);
    const line = stdin.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return default_dir,
        else => return err,
    };
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0) return default_dir;
    return allocator.dupe(u8, trimmed);
}

fn installApp(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    executable_path: []const u8,
    manifest: Manifest,
    install_dir: []const u8,
    silent: bool,
) !void {
    const io = init.io;

    var output_dir = try Io.Dir.cwd().createDirPathOpen(io, install_dir, .{});
    defer output_dir.close(io);

    const install_path = try Io.Dir.cwd().realPathFileAlloc(io, install_dir, allocator);

    try extractPayload(allocator, io, output_dir, executable_path, manifest.payload_offset);

    const target_exe = try std.fs.path.join(allocator, &.{ install_path, manifest.executable_name });
    const uninstall_path = try std.fs.path.join(allocator, &.{ install_path, "uninstall.exe" });

    try copyFile(io, executable_path, uninstall_path);

    if (manifest.start_menu or manifest.desktop) {
        try createShortcuts(init, allocator, manifest, install_path, target_exe);
    }

    try writeUninstallRegistry(allocator, manifest, install_path, target_exe, uninstall_path);

    if (manifest.launch and !silent) {
        launchApp(allocator, target_exe, install_path);
    }

    if (!silent) {
        try print(init.io, "Installed {s} {s} to {s}\n", .{ manifest.name, manifest.version, install_dir });
    }
}

fn uninstallApp(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    executable_path: []const u8,
    manifest: Manifest,
    silent: bool,
) !void {
    const io = init.io;
    const install_dir = std.fs.path.dirname(executable_path) orelse return error.InvalidUninstaller;

    try removeShortcuts(init, allocator, manifest);
    removeUninstallRegistry(allocator, manifest);

    const temp_dir = init.environ_map.get("TEMP") orelse install_dir;
    const temp_path = try std.fmt.allocPrint(allocator, "{s}\\zig-bundle-uninstall-{x}.exe", .{
        temp_dir,
        windows.GetCurrentProcessId(),
    });

    if (moveFile(allocator, executable_path, temp_path)) {
        defer scheduleDelete(allocator, temp_path);
        try Io.Dir.cwd().deleteTree(io, install_dir);
    } else {
        try removeContents(allocator, io, install_dir, executable_path);
        scheduleDelete(allocator, executable_path);
    }

    if (!silent) {
        try print(io, "Uninstalled {s} {s}\n", .{ manifest.name, manifest.version });
    }
}

/// Extracts with overwrite semantics, unlike `std.tar.extract`.
fn extractPayload(
    allocator: std.mem.Allocator,
    io: Io,
    output_dir: Io.Dir,
    executable_path: []const u8,
    payload_offset: u64,
) !void {
    var self_file = try Io.Dir.cwd().openFile(io, executable_path, .{});
    defer self_file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = self_file.reader(io, &read_buffer);
    try reader.seekTo(payload_offset);

    var gzip_buffer: [flate.max_window_len]u8 = undefined;
    var gzip = flate.Decompress.init(&reader.interface, .gzip, &gzip_buffer);

    var file_name_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    var link_name_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    var iterator = std.tar.Iterator.init(&gzip.reader, .{
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

fn createShortcuts(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    manifest: Manifest,
    install_dir: []const u8,
    target_exe: []const u8,
) !void {
    if (manifest.start_menu) {
        const link_path = try shortcutPath(init, allocator, manifest, .start_menu);
        try ensureParent(init.io, link_path);
        try createShortcut(allocator, link_path, target_exe, install_dir, manifest.name);
    }

    if (manifest.desktop) {
        const link_path = try shortcutPath(init, allocator, manifest, .desktop);
        try ensureParent(init.io, link_path);
        try createShortcut(allocator, link_path, target_exe, install_dir, manifest.name);
    }
}

fn shortcutPath(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    manifest: Manifest,
    kind: ShortcutKind,
) ![]const u8 {
    const base = switch (manifest.scope) {
        .current_user => switch (kind) {
            .start_menu => init.environ_map.get("APPDATA") orelse return error.MissingAppData,
            .desktop => init.environ_map.get("USERPROFILE") orelse return error.MissingUserProfile,
        },
        .all_users => switch (kind) {
            .start_menu => init.environ_map.get("ProgramData") orelse return error.MissingProgramData,
            .desktop => init.environ_map.get("PUBLIC") orelse return error.MissingPublic,
        },
    };

    const dir = switch (kind) {
        .start_menu => try std.fs.path.join(allocator, &.{
            base, "Microsoft", "Windows", "Start Menu", "Programs",
        }),
        .desktop => try std.fs.path.join(allocator, &.{ base, "Desktop" }),
    };
    try Io.Dir.cwd().createDirPath(init.io, dir);

    const file_name = try std.fmt.allocPrint(allocator, "{s}.lnk", .{manifest.name});
    return std.fs.path.join(allocator, &.{ dir, file_name });
}

fn removeShortcuts(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    manifest: Manifest,
) !void {
    if (manifest.start_menu) {
        const link_path = try shortcutPath(init, allocator, manifest, .start_menu);
        Io.Dir.cwd().deleteFile(init.io, link_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }

    if (manifest.desktop) {
        const link_path = try shortcutPath(init, allocator, manifest, .desktop);
        Io.Dir.cwd().deleteFile(init.io, link_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
}

fn createShortcut(
    allocator: std.mem.Allocator,
    link_path: []const u8,
    target: []const u8,
    working_dir: []const u8,
    description: []const u8,
) !void {
    const init_result = CoInitializeEx(null, coinit_apartment_threaded);
    const should_uninitialize = init_result >= 0;
    defer if (should_uninitialize) CoUninitialize();
    if (init_result < 0 and init_result != rpc_e_changed_mode) return error.ComFailed;

    var link: ?*IShellLinkW = null;
    if (CoCreateInstance(
        &clsid_shell_link,
        null,
        clsctx_inproc_server,
        &iid_shell_link_w,
        @ptrCast(&link),
    ) < 0 or link == null) return error.ComFailed;
    defer _ = link.?.vtable.Release(link.?);

    const target_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, target);
    const working_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, working_dir);
    const description_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, description);
    const link_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, link_path);

    if (link.?.vtable.SetPath(link.?, target_w.ptr) < 0) return error.ComFailed;
    if (link.?.vtable.SetWorkingDirectory(link.?, working_w.ptr) < 0) return error.ComFailed;
    if (link.?.vtable.SetDescription(link.?, description_w.ptr) < 0) return error.ComFailed;
    if (link.?.vtable.SetIconLocation(link.?, target_w.ptr, 0) < 0) return error.ComFailed;

    var persist: ?*IPersistFile = null;
    if (link.?.vtable.QueryInterface(link.?, &iid_persist_file, @ptrCast(&persist)) < 0 or persist == null) {
        return error.ComFailed;
    }
    defer _ = persist.?.vtable.Release(persist.?);

    if (persist.?.vtable.Save(persist.?, link_w.ptr, 1) < 0) return error.ComFailed;
}

fn writeUninstallRegistry(
    allocator: std.mem.Allocator,
    manifest: Manifest,
    install_dir: []const u8,
    target_exe: []const u8,
    uninstall_path: []const u8,
) !void {
    const root = switch (manifest.scope) {
        .current_user => windows.HKEY_CURRENT_USER,
        .all_users => windows.HKEY_LOCAL_MACHINE,
    };

    const sub_key = try std.fmt.allocPrint(
        allocator,
        "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{s}",
        .{manifest.identifier},
    );
    const sub_key_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, sub_key);

    var key: windows.HKEY = undefined;
    if (RegCreateKeyExW(root, sub_key_w.ptr, 0, null, 0, key_write, null, &key, null) != 0) {
        return error.RegistryFailed;
    }
    defer _ = RegCloseKey(key);

    try setRegistryString(allocator, key, "DisplayName", manifest.name);
    try setRegistryString(allocator, key, "DisplayVersion", manifest.version);
    if (manifest.publisher.len > 0) {
        try setRegistryString(allocator, key, "Publisher", manifest.publisher);
    }
    try setRegistryString(allocator, key, "InstallLocation", install_dir);
    try setRegistryString(allocator, key, "DisplayIcon", target_exe);

    const uninstall_command = try std.fmt.allocPrint(allocator, "\"{s}\" --uninstall", .{uninstall_path});
    try setRegistryString(allocator, key, "UninstallString", uninstall_command);

    const quiet_command = try std.fmt.allocPrint(allocator, "\"{s}\" --uninstall --silent", .{uninstall_path});
    try setRegistryString(allocator, key, "QuietUninstallString", quiet_command);

    try setRegistryDword(allocator, key, "NoModify", 1);
    try setRegistryDword(allocator, key, "NoRepair", 1);
}

fn removeUninstallRegistry(allocator: std.mem.Allocator, manifest: Manifest) void {
    const root = switch (manifest.scope) {
        .current_user => windows.HKEY_CURRENT_USER,
        .all_users => windows.HKEY_LOCAL_MACHINE,
    };

    const sub_key = std.fmt.allocPrint(
        allocator,
        "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{s}",
        .{manifest.identifier},
    ) catch return;
    const sub_key_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, sub_key) catch return;
    _ = RegDeleteTreeW(root, sub_key_w.ptr);
}

fn setRegistryString(allocator: std.mem.Allocator, key: windows.HKEY, name: []const u8, value: []const u8) !void {
    const name_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, name);
    const value_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, value);
    const size: u32 = @intCast((value_w.len + 1) * 2);
    if (RegSetValueExW(key, name_w.ptr, 0, reg_sz, @ptrCast(value_w.ptr), size) != 0) {
        return error.RegistryFailed;
    }
}

fn setRegistryDword(allocator: std.mem.Allocator, key: windows.HKEY, name: []const u8, value: u32) !void {
    const name_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, name);
    if (RegSetValueExW(key, name_w.ptr, 0, reg_dword, @ptrCast(&value), 4) != 0) {
        return error.RegistryFailed;
    }
}

fn copyFile(io: Io, from: []const u8, to: []const u8) !void {
    var source = try Io.Dir.cwd().openFile(io, from, .{});
    defer source.close(io);

    var destination = try Io.Dir.cwd().createFile(io, to, .{ .truncate = true });
    defer destination.close(io);

    var read_buffer: [64 * 1024]u8 = undefined;
    var reader = source.reader(io, &read_buffer);
    var write_buffer: [64 * 1024]u8 = undefined;
    var writer = destination.writer(io, &write_buffer);

    _ = try writer.interface.sendFileAll(&reader, .unlimited);
    try writer.interface.flush();
}

fn removeContents(
    allocator: std.mem.Allocator,
    io: Io,
    dir_path: []const u8,
    skip_path: []const u8,
) !void {
    var dir = try Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        const child = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        switch (entry.kind) {
            .directory => {
                try removeContents(allocator, io, child, skip_path);
                Io.Dir.cwd().deleteDir(io, child) catch {};
            },
            .file => {
                if (!std.mem.eql(u8, child, skip_path)) {
                    Io.Dir.cwd().deleteFile(io, child) catch |err| switch (err) {
                        error.FileNotFound => {},
                        else => return err,
                    };
                }
            },
            else => {},
        }
    }
}

fn moveFile(allocator: std.mem.Allocator, from: []const u8, to: []const u8) bool {
    const from_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, from) catch return false;
    const to_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, to) catch return false;
    return MoveFileExW(from_w.ptr, to_w.ptr, movfile_replace_existing) != 0;
}

fn scheduleDelete(allocator: std.mem.Allocator, path: []const u8) void {
    const path_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, path) catch return;
    _ = MoveFileExW(path_w.ptr, null, movfile_delay_until_reboot);
}

fn launchApp(allocator: std.mem.Allocator, target_exe: []const u8, working_dir: []const u8) void {
    const file_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, target_exe) catch return;
    const directory_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, working_dir) catch return;
    const result = ShellExecuteW(null, null, file_w.ptr, null, directory_w.ptr, sw_shownormal);
    _ = result;
}

fn ensureParent(io: Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        try Io.Dir.cwd().createDirPath(io, parent);
    }
}

fn print(io: Io, comptime format: []const u8, arguments: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &buffer);
    try stdout.interface.print(format, arguments);
    try stdout.interface.flush();
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

fn manifestBool(manifest: []const u8, key: []const u8, default: bool) bool {
    const value = manifestValue(manifest, key) orelse return default;
    return std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true");
}
