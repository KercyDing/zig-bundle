//! Native RPM package writer.
const std = @import("std");

const deb = @import("deb.zig");
const icons = @import("../common/icons.zig");
const resources = @import("../common/resources.zig");
const tar_gz = @import("../common/tar_gz.zig");

const Io = std.Io;

pub const Options = struct {
    release: []const u8 = "1",
    epoch: ?u32 = null,
    group: []const u8 = "Unspecified",
    url: ?[]const u8 = null,
    license: ?[]const u8 = null,
    requires: []const []const u8 = &.{},
    provides: []const []const u8 = &.{},
    conflicts: []const []const u8 = &.{},
    obsoletes: []const []const u8 = &.{},
};

/// Resolved additional file installed by the package.
pub const Asset = struct {
    /// Host path of the source file or directory.
    source_path: []const u8,
    /// Destination relative to the filesystem root.
    dest: []const u8,
    /// Permission bits for files; directories always use `0o755`.
    mode: u32 = 0o644,
};

pub const Scripts = struct {
    pre_install: ?[]const u8 = null,
    post_install: ?[]const u8 = null,
    pre_uninstall: ?[]const u8 = null,
    post_uninstall: ?[]const u8 = null,
};

pub const Config = struct {
    name: []const u8,
    version: []const u8,
    /// Maintainer or packager string.
    packager: ?[]const u8 = null,
    description: ?[]const u8 = null,
    license: ?[]const u8 = null,
    categories: ?[]const u8 = null,
    arch: []const u8,
    executable_name: []const u8,
    payload: []const resources.Entry,
    icons: []const icons.Png = &.{},
    assets: []const Asset = &.{},
    /// Directory containing `preinst`, `postinst`, `prerm` and `postrm`.
    maintainer_scripts_path: ?[]const u8 = null,
    mtime: u64 = tar_gz.default_mtime,
    options: Options = .{},
};

const Kind = enum { file, dir };

const Item = struct {
    path: []const u8,
    kind: Kind,
    mode: u32 = 0o644,
    content: union(enum) {
        file: []const u8,
        bytes: []const u8,
    } = .{ .bytes = "" },
};

/// Converts a SemVer prerelease into an RPM-compatible version.
pub fn packageVersion(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
    const converted = try allocator.alloc(u8, version.len);
    for (version, converted) |c, *out| {
        out.* = if (c == '-') '~' else c;
    }
    for (converted) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '+' and c != '~') {
            return error.InvalidVersion;
        }
    }
    return converted;
}

/// Validates an RPM release string.
pub fn validateRelease(release: []const u8) !void {
    if (release.len == 0) return error.InvalidRelease;
    for (release) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '+' and c != '~') {
            return error.InvalidRelease;
        }
    }
}

/// Maps a Zig CPU architecture to the RPM architecture name.
pub fn archName(arch: std.Target.Cpu.Arch) ![]const u8 {
    return switch (arch) {
        .x86_64 => "x86_64",
        .x86 => "i686",
        .aarch64 => "aarch64",
        .arm, .armeb, .thumb, .thumbeb => "armv7hl",
        .riscv64 => "riscv64",
        else => error.UnsupportedArchitecture,
    };
}

fn firstLine(text: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    return std.mem.trim(u8, text[0..end], " \t\r");
}

/// Builds an `.rpm` from the shared payload.
pub fn bundle(
    io: Io,
    file: Io.File,
    config: Config,
    allocator: std.mem.Allocator,
) !void {
    const package = try deb.toKebabCase(allocator, config.name);

    var items: std.ArrayList(Item) = .empty;
    defer items.deinit(allocator);

    for (config.payload) |entry| {
        const path = switch (entry.executable) {
            true => try std.fmt.allocPrint(allocator, "usr/bin/{s}", .{entry.archive_path}),
            false => try std.fmt.allocPrint(allocator, "usr/lib/{s}/{s}", .{ config.name, entry.archive_path }),
        };

        switch (entry.kind) {
            .dir => try items.append(allocator, .{ .path = path, .kind = .dir, .mode = 0o755 }),
            .file => try items.append(allocator, .{
                .path = path,
                .kind = .file,
                .mode = switch (entry.executable) {
                    true => 0o755,
                    false => 0o644,
                },
                .content = .{ .file = entry.source_path },
            }),
        }
    }

    for (config.icons) |icon| {
        try items.append(allocator, .{
            .path = try std.fmt.allocPrint(allocator, "usr/share/icons/hicolor/{d}x{d}/apps/{s}.png", .{
                icon.width,
                icon.height,
                config.executable_name,
            }),
            .kind = .file,
            .mode = 0o644,
            .content = .{ .file = icon.path },
        });
    }

    try items.append(allocator, .{
        .path = try std.fmt.allocPrint(allocator, "usr/share/applications/{s}.desktop", .{config.name}),
        .kind = .file,
        .mode = 0o644,
        .content = .{ .bytes = try renderDesktop(allocator, config) },
    });

    for (config.assets) |asset| {
        try addAsset(io, allocator, asset, &items);
    }

    try addParentDirectories(allocator, &items);

    std.mem.sort(Item, items.items, {}, struct {
        fn lessThan(_: void, lhs: Item, rhs: Item) bool {
            return std.mem.lessThan(u8, lhs.path, rhs.path);
        }
    }.lessThan);

    const contents = try allocator.alloc([]const u8, items.items.len);
    var installed_size: u64 = 0;
    for (items.items, contents) |item, *content| {
        content.* = switch (item.content) {
            .bytes => |bytes| bytes,
            .file => |path| try Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited),
        };
        if (content.len > std.math.maxInt(u32)) return error.PackageTooLarge;
        installed_size += content.len;
    }

    const cpio = try writeCpio(allocator, items.items, contents, config.mtime);
    const payload = try tar_gz.gzipBytes(allocator, cpio, 9);

    const scripts = try loadScripts(io, allocator, config.maintainer_scripts_path);
    const header = try buildHeader(allocator, config, package, items.items, contents, installed_size, payload, cpio, scripts);
    const signature = try buildSignature(allocator, header, payload.len);

    var writer_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &writer_buffer);
    try writeLead(&writer.interface, package);
    try writer.interface.writeAll(signature);
    const signature_padding = (8 - (signature.len % 8)) % 8;
    var padding: [8]u8 = @splat(0);
    try writer.interface.writeAll(padding[0..signature_padding]);
    try writer.interface.writeAll(header);
    try writer.interface.writeAll(payload);
    try writer.interface.flush();
}

fn renderDesktop(allocator: std.mem.Allocator, config: Config) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    try writer.writeAll("[Desktop Entry]\n");
    if (config.description) |description| {
        const comment = firstLine(description);
        if (comment.len > 0) try writer.print("Comment={s}\n", .{comment});
    }
    if (std.mem.indexOfAny(u8, config.executable_name, " \t") != null) {
        try writer.print("Exec=\"{s}\"\n", .{config.executable_name});
    } else {
        try writer.print("Exec={s}\n", .{config.executable_name});
    }
    try writer.print("StartupWMClass={s}\n", .{config.executable_name});
    if (config.icons.len > 0) try writer.print("Icon={s}\n", .{config.executable_name});
    if (config.categories) |categories| {
        if (categories.len > 0) {
            try writer.print("Categories={s}", .{categories});
            if (categories[categories.len - 1] != ';') try writer.writeByte(';');
            try writer.writeByte('\n');
        }
    }
    try writer.print("Name={s}\n", .{config.name});
    try writer.writeAll("Terminal=false\nType=Application\n");

    return allocating.toOwnedSlice();
}

fn normalizeAssetDestination(allocator: std.mem.Allocator, dest: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, dest, "/\\");
    if (trimmed.len == 0) return error.InvalidAssetDestination;

    const normalized = try allocator.alloc(u8, trimmed.len);
    for (trimmed, normalized) |c, *out| out.* = if (c == '\\') '/' else c;

    var parts = std.mem.splitScalar(u8, normalized, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) {
            return error.InvalidAssetDestination;
        }
    }
    return normalized;
}

fn isManPage(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "usr/share/man/");
}

fn appendAssetFile(
    io: Io,
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
    mode: u32,
    items: *std.ArrayList(Item),
) !void {
    if (isManPage(path) and !std.mem.endsWith(u8, path, ".gz")) {
        const dest = try std.fmt.allocPrint(allocator, "{s}.gz", .{path});
        if (std.mem.endsWith(u8, source, ".gz")) {
            try items.append(allocator, .{ .path = dest, .kind = .file, .mode = mode, .content = .{ .file = source } });
            return;
        }
        const data = try Io.Dir.cwd().readFileAlloc(io, source, allocator, .limited(16 * 1024 * 1024));
        try items.append(allocator, .{
            .path = dest,
            .kind = .file,
            .mode = mode,
            .content = .{ .bytes = try tar_gz.gzipBytes(allocator, data, 9) },
        });
        return;
    }
    try items.append(allocator, .{ .path = path, .kind = .file, .mode = mode, .content = .{ .file = source } });
}

fn addAsset(io: Io, allocator: std.mem.Allocator, asset: Asset, items: *std.ArrayList(Item)) !void {
    const source = std.mem.trimEnd(u8, asset.source_path, "/\\");
    const stat = try Io.Dir.cwd().statFile(io, source, .{});
    const dest_is_directory = std.mem.endsWith(u8, asset.dest, "/") or std.mem.endsWith(u8, asset.dest, "\\");
    const dest = try normalizeAssetDestination(allocator, asset.dest);

    switch (stat.kind) {
        .file => {
            const path = if (dest_is_directory)
                try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest, std.fs.path.basename(source) })
            else
                dest;
            try appendAssetFile(io, allocator, source, path, asset.mode, items);
        },
        .directory => try addAssetDirectory(io, allocator, source, dest, asset.mode, items),
        else => return error.UnsupportedAssetType,
    }
}

fn addAssetDirectory(
    io: Io,
    allocator: std.mem.Allocator,
    source: []const u8,
    dest: []const u8,
    mode: u32,
    items: *std.ArrayList(Item),
) !void {
    try items.append(allocator, .{ .path = dest, .kind = .dir, .mode = 0o755 });

    var dir = try Io.Dir.openDirAbsolute(io, source, .{ .iterate = true });
    defer dir.close(io);

    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        const child_source = try std.fs.path.join(allocator, &.{ source, entry.name });
        const child_dest = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest, entry.name });
        switch (entry.kind) {
            .directory => try addAssetDirectory(io, allocator, child_source, child_dest, mode, items),
            .file => try appendAssetFile(io, allocator, child_source, child_dest, mode, items),
            else => return error.UnsupportedAssetType,
        }
    }
}

fn addParentDirectories(allocator: std.mem.Allocator, items: *std.ArrayList(Item)) !void {
    var dirs: std.StringHashMap(void) = .init(allocator);
    defer dirs.deinit();

    for (items.items) |item| {
        if (item.kind == .dir) try dirs.put(item.path, {});
    }

    var pending: std.ArrayList([]const u8) = .empty;
    defer pending.deinit(allocator);

    for (items.items) |item| {
        var end = item.path.len;
        while (std.mem.lastIndexOfScalar(u8, item.path[0..end], '/')) |slash| {
            end = slash;
            const entry = try dirs.getOrPut(item.path[0..slash]);
            if (!entry.found_existing) try pending.append(allocator, item.path[0..slash]);
        }
    }

    for (pending.items) |path| {
        try items.append(allocator, .{ .path = path, .kind = .dir, .mode = 0o755 });
    }
}

fn writeCpioEntry(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    name: []const u8,
    mode: u32,
    data: []const u8,
    ino: u32,
    mtime: u32,
    is_dir: bool,
) !void {
    var header: [110]u8 = undefined;
    @memcpy(header[0..6], "070701");

    const fields = [_]u32{
        ino,
        mode,
        0,
        0,
        if (is_dir) 2 else 1,
        mtime,
        @intCast(data.len),
        0,
        0,
        0,
        0,
        @intCast(name.len + 1),
        0,
    };
    for (fields, 0..) |value, index| {
        writeHex8(header[6 + index * 8 ..][0..8], value);
    }

    try out.appendSlice(allocator, &header);
    try out.appendSlice(allocator, name);
    try out.append(allocator, 0);
    while (out.items.len % 4 != 0) try out.append(allocator, 0);
    try out.appendSlice(allocator, data);
    while (out.items.len % 4 != 0) try out.append(allocator, 0);
}

fn writeCpio(
    allocator: std.mem.Allocator,
    items: []const Item,
    contents: []const []const u8,
    timestamp: u64,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const mtime: u32 = @intCast(@min(timestamp, std.math.maxInt(u32)));
    for (items, contents, 0..) |item, content, index| {
        const path = try std.fmt.allocPrint(allocator, "./{s}", .{item.path});
        const mode = switch (item.kind) {
            .dir => @as(u32, 0o040755),
            .file => 0o100000 | item.mode,
        };
        try writeCpioEntry(&out, allocator, path, mode, content, @intCast(index + 1), mtime, item.kind == .dir);
    }
    try writeCpioEntry(&out, allocator, "TRAILER!!!", 0, "", 0, mtime, false);

    return out.toOwnedSlice(allocator);
}

fn writeHex8(field: []u8, value: u32) void {
    const digits = "0123456789abcdef";
    var v = value;
    var index: usize = 8;
    while (index > 0) {
        index -= 1;
        field[index] = digits[v & 0xf];
        v >>= 4;
    }
}

const TagType = enum(u32) { int16 = 3, int32 = 4, string = 6, bin = 7, string_array = 8, i18n = 9 };

const Data = union(enum) {
    string: []const u8,
    i18n: []const u8,
    strings: []const []const u8,
    i32: []const u32,
    i16: []const u16,
    bin: []const u8,
};

const Record = struct {
    tag: u32,
    kind: TagType,
    data: Data,
};

const HeaderBuilder = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(Record) = .empty,

    fn addString(self: *HeaderBuilder, tag: u32, value: []const u8) !void {
        try self.records.append(self.allocator, .{ .tag = tag, .kind = .string, .data = .{ .string = value } });
    }

    fn addI18n(self: *HeaderBuilder, tag: u32, value: []const u8) !void {
        try self.records.append(self.allocator, .{ .tag = tag, .kind = .i18n, .data = .{ .i18n = value } });
    }

    fn addStrings(self: *HeaderBuilder, tag: u32, values: []const []const u8) !void {
        if (values.len == 0) return;
        try self.records.append(self.allocator, .{ .tag = tag, .kind = .string_array, .data = .{ .strings = values } });
    }

    fn addInt32(self: *HeaderBuilder, tag: u32, values: []const u32) !void {
        if (values.len == 0) return;
        try self.records.append(self.allocator, .{ .tag = tag, .kind = .int32, .data = .{ .i32 = values } });
    }

    fn addInt16(self: *HeaderBuilder, tag: u32, values: []const u16) !void {
        if (values.len == 0) return;
        try self.records.append(self.allocator, .{ .tag = tag, .kind = .int16, .data = .{ .i16 = values } });
    }

    fn addBin(self: *HeaderBuilder, tag: u32, bytes: []const u8) !void {
        try self.records.append(self.allocator, .{ .tag = tag, .kind = .bin, .data = .{ .bin = bytes } });
    }

    fn count(data: Data) u32 {
        return switch (data) {
            .string, .i18n => 1,
            .strings => |values| @intCast(values.len),
            .i32 => |values| @intCast(values.len),
            .i16 => |values| @intCast(values.len),
            .bin => |bytes| @intCast(bytes.len),
        };
    }

    fn alignment(kind: TagType) u32 {
        return switch (kind) {
            .int16 => 2,
            .int32 => 4,
            else => 0,
        };
    }

    fn appendData(data: Data, store: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        switch (data) {
            .string => |value| {
                try store.appendSlice(allocator, value);
                try store.append(allocator, 0);
            },
            .i18n => |value| {
                try store.appendSlice(allocator, value);
                try store.append(allocator, 0);
            },
            .strings => |values| for (values) |value| {
                try store.appendSlice(allocator, value);
                try store.append(allocator, 0);
            },
            .i32 => |values| for (values) |value| {
                var buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &buf, value, .big);
                try store.appendSlice(allocator, &buf);
            },
            .i16 => |values| for (values) |value| {
                var buf: [2]u8 = undefined;
                std.mem.writeInt(u16, &buf, value, .big);
                try store.appendSlice(allocator, &buf);
            },
            .bin => |bytes| try store.appendSlice(allocator, bytes),
        }
    }

    fn serialize(self: *HeaderBuilder, region_tag: u32) ![]u8 {
        std.mem.sort(Record, self.records.items, {}, struct {
            fn lessThan(_: void, lhs: Record, rhs: Record) bool {
                return lhs.tag < rhs.tag;
            }
        }.lessThan);

        var store: std.ArrayList(u8) = .empty;
        defer store.deinit(self.allocator);

        const Index = struct { tag: u32, kind: TagType, offset: u32, count: u32 };
        var indexes: std.ArrayList(Index) = .empty;
        defer indexes.deinit(self.allocator);

        for (self.records.items) |record| {
            const value_alignment = alignment(record.kind);
            while (value_alignment > 0 and store.items.len % value_alignment != 0) try store.append(self.allocator, 0);
            const offset: u32 = @intCast(store.items.len);
            try appendData(record.data, &store, self.allocator);
            try indexes.append(self.allocator, .{
                .tag = record.tag,
                .kind = record.kind,
                .offset = offset,
                .count = count(record.data),
            });
        }

        const region_offset: u32 = @intCast(store.items.len);
        var region_data: [16]u8 = undefined;
        std.mem.writeInt(u32, region_data[0..4], region_tag, .big);
        std.mem.writeInt(u32, region_data[4..8], @intFromEnum(TagType.bin), .big);
        std.mem.writeInt(i32, region_data[8..12], -@as(i32, @intCast((self.records.items.len + 1) * 16)), .big);
        std.mem.writeInt(u32, region_data[12..16], 16, .big);
        try store.appendSlice(self.allocator, &region_data);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        try out.appendSlice(self.allocator, &.{ 0x8e, 0xad, 0xe8, 0x01 });
        try out.appendSlice(self.allocator, &.{ 0, 0, 0, 0 });
        try appendU32(&out, self.allocator, @intCast(indexes.items.len + 1));
        try appendU32(&out, self.allocator, @intCast(store.items.len));

        try appendU32(&out, self.allocator, region_tag);
        try appendU32(&out, self.allocator, @intFromEnum(TagType.bin));
        try appendU32(&out, self.allocator, region_offset);
        try appendU32(&out, self.allocator, 16);

        for (indexes.items) |entry| {
            try appendU32(&out, self.allocator, entry.tag);
            try appendU32(&out, self.allocator, @intFromEnum(entry.kind));
            try appendU32(&out, self.allocator, entry.offset);
            try appendU32(&out, self.allocator, entry.count);
        }
        try out.appendSlice(self.allocator, store.items);
        return out.toOwnedSlice(self.allocator);
    }
};

fn appendU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .big);
    try out.appendSlice(allocator, &buf);
}

fn sha256Hex(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &hex);
}

fn sha1Hex(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var digest: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &hex);
}

const Dependency = struct {
    name: []const u8,
    flags: u32,
    version: []const u8,
};

fn parseDependency(text: []const u8) Dependency {
    const trimmed = std.mem.trim(u8, text, " \t");
    const operators = [_]struct { text: []const u8, flags: u32 }{
        .{ .text = ">=", .flags = 0x8 | 0x4 },
        .{ .text = "<=", .flags = 0x8 | 0x2 },
        .{ .text = "=", .flags = 0x8 },
        .{ .text = ">", .flags = 0x4 },
        .{ .text = "<", .flags = 0x2 },
    };
    for (operators) |op| {
        if (std.mem.indexOf(u8, trimmed, op.text)) |index| {
            return .{
                .name = std.mem.trim(u8, trimmed[0..index], " \t"),
                .flags = op.flags,
                .version = std.mem.trim(u8, trimmed[index + op.text.len ..], " \t"),
            };
        }
    }
    return .{ .name = trimmed, .flags = 0, .version = "" };
}

fn buildDependencies(
    allocator: std.mem.Allocator,
    config: Config,
    package: []const u8,
    version: []const u8,
    release: []const u8,
    epoch: ?u32,
    has_config: bool,
    scripts: Scripts,
) !struct { provides: []Dependency, requires: []Dependency, conflicts: []Dependency, obsoletes: []Dependency } {
    const evr = if (epoch) |e|
        try std.fmt.allocPrint(allocator, "{d}:{s}-{s}", .{ e, version, release })
    else
        try std.fmt.allocPrint(allocator, "{s}-{s}", .{ version, release });

    var provides: std.ArrayList(Dependency) = .empty;
    var requires: std.ArrayList(Dependency) = .empty;

    try provides.append(allocator, .{ .name = package, .flags = 0x8, .version = evr });

    const rpmlib = [_]struct { name: []const u8, version: []const u8 }{
        .{ .name = "CompressedFileNames", .version = "3.0.4-1" },
        .{ .name = "FileDigests", .version = "4.6.0-1" },
        .{ .name = "PayloadFilesHavePrefix", .version = "4.0-1" },
    };
    for (rpmlib) |entry| {
        try requires.append(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "rpmlib({s})", .{entry.name}),
            .flags = 0x1000000 | 0x8 | 0x2,
            .version = entry.version,
        });
    }

    if (has_config) {
        const config_name = try std.fmt.allocPrint(allocator, "config({s})", .{package});
        try provides.append(allocator, .{ .name = config_name, .flags = 0x10000000 | 0x8, .version = evr });
        try requires.append(allocator, .{ .name = config_name, .flags = 0x10000000 | 0x8, .version = evr });
    }

    const script_phases = [_]struct { script: ?[]const u8, flag: u32 }{
        .{ .script = scripts.pre_install, .flag = 1 << 9 },
        .{ .script = scripts.post_install, .flag = 1 << 10 },
        .{ .script = scripts.pre_uninstall, .flag = 1 << 11 },
        .{ .script = scripts.post_uninstall, .flag = 1 << 12 },
    };
    for (script_phases) |phase| {
        if (phase.script != null) {
            try requires.append(allocator, .{ .name = "/bin/sh", .flags = (1 << 8) | phase.flag, .version = "" });
        }
    }

    for (config.options.provides) |entry| try provides.append(allocator, parseDependency(entry));
    for (config.options.requires) |entry| try requires.append(allocator, parseDependency(entry));

    var conflicts: std.ArrayList(Dependency) = .empty;
    var obsoletes: std.ArrayList(Dependency) = .empty;
    for (config.options.conflicts) |entry| try conflicts.append(allocator, parseDependency(entry));
    for (config.options.obsoletes) |entry| try obsoletes.append(allocator, parseDependency(entry));

    const lessThan = struct {
        fn lessThan(_: void, lhs: Dependency, rhs: Dependency) bool {
            if (!std.mem.eql(u8, lhs.name, rhs.name)) return std.mem.lessThan(u8, lhs.name, rhs.name);
            if (!std.mem.eql(u8, lhs.version, rhs.version)) return std.mem.lessThan(u8, lhs.version, rhs.version);
            return lhs.flags < rhs.flags;
        }
    }.lessThan;
    std.mem.sort(Dependency, provides.items, {}, lessThan);
    std.mem.sort(Dependency, requires.items, {}, lessThan);
    std.mem.sort(Dependency, conflicts.items, {}, lessThan);
    std.mem.sort(Dependency, obsoletes.items, {}, lessThan);

    return .{
        .provides = try provides.toOwnedSlice(allocator),
        .requires = try requires.toOwnedSlice(allocator),
        .conflicts = try conflicts.toOwnedSlice(allocator),
        .obsoletes = try obsoletes.toOwnedSlice(allocator),
    };
}

fn readScript(io: Io, allocator: std.mem.Allocator, dir: []const u8, name: []const u8) !?[]const u8 {
    const path = try std.fs.path.join(allocator, &.{ dir, name });
    const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    if (stat.kind != .file) return null;
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
}

fn loadScripts(io: Io, allocator: std.mem.Allocator, dir_path: ?[]const u8) !Scripts {
    const dir = dir_path orelse return .{};
    const stat = try Io.Dir.cwd().statFile(io, dir, .{});
    if (stat.kind != .directory) return error.InvalidMaintainerScripts;

    return .{
        .pre_install = try readScript(io, allocator, dir, "preinst"),
        .post_install = try readScript(io, allocator, dir, "postinst"),
        .pre_uninstall = try readScript(io, allocator, dir, "prerm"),
        .post_uninstall = try readScript(io, allocator, dir, "postrm"),
    };
}

fn buildHeader(
    allocator: std.mem.Allocator,
    config: Config,
    package: []const u8,
    items: []const Item,
    contents: []const []const u8,
    installed_size: u64,
    payload: []const u8,
    cpio: []const u8,
    scripts: Scripts,
) ![]u8 {
    const release = config.options.release;
    const epoch = config.options.epoch;

    var dirs: std.StringHashMap(u32) = .init(allocator);
    defer dirs.deinit();
    var dir_names: std.ArrayList([]const u8) = .empty;
    defer dir_names.deinit(allocator);

    var base_names: std.ArrayList([]const u8) = .empty;
    defer base_names.deinit(allocator);
    var dir_indexes: std.ArrayList(u32) = .empty;
    defer dir_indexes.deinit(allocator);
    var file_sizes: std.ArrayList(u32) = .empty;
    defer file_sizes.deinit(allocator);
    var file_modes: std.ArrayList(u16) = .empty;
    defer file_modes.deinit(allocator);
    var file_rdevs: std.ArrayList(u16) = .empty;
    defer file_rdevs.deinit(allocator);
    var file_mtimes: std.ArrayList(u32) = .empty;
    defer file_mtimes.deinit(allocator);
    var file_digests: std.ArrayList([]const u8) = .empty;
    defer file_digests.deinit(allocator);
    var file_linktos: std.ArrayList([]const u8) = .empty;
    defer file_linktos.deinit(allocator);
    var file_flags: std.ArrayList(u32) = .empty;
    defer file_flags.deinit(allocator);
    var file_users: std.ArrayList([]const u8) = .empty;
    defer file_users.deinit(allocator);
    var file_groups: std.ArrayList([]const u8) = .empty;
    defer file_groups.deinit(allocator);
    var file_devices: std.ArrayList(u32) = .empty;
    defer file_devices.deinit(allocator);
    var file_inodes: std.ArrayList(u32) = .empty;
    defer file_inodes.deinit(allocator);
    var file_langs: std.ArrayList([]const u8) = .empty;
    defer file_langs.deinit(allocator);
    var file_verify_flags: std.ArrayList(u32) = .empty;
    defer file_verify_flags.deinit(allocator);

    const mtime: u32 = @intCast(@min(config.mtime, std.math.maxInt(u32)));
    var has_config = false;
    if (installed_size > std.math.maxInt(u32)) return error.PackageTooLarge;

    for (items, contents, 0..) |item, content, index| {
        const full = try std.fmt.allocPrint(allocator, "/{s}", .{item.path});
        const slash = std.mem.lastIndexOfScalar(u8, full, '/').?;
        const dir = full[0 .. slash + 1];
        const base = full[slash + 1 ..];

        const entry = try dirs.getOrPut(dir);
        if (!entry.found_existing) {
            entry.value_ptr.* = @intCast(dir_names.items.len);
            try dir_names.append(allocator, try allocator.dupe(u8, dir));
        }

        try base_names.append(allocator, try allocator.dupe(u8, base));
        try dir_indexes.append(allocator, entry.value_ptr.*);
        try file_sizes.append(allocator, @intCast(content.len));
        try file_modes.append(allocator, switch (item.kind) {
            .dir => 0o040755,
            .file => @as(u16, 0o100000) | @as(u16, @intCast(item.mode)),
        });
        try file_rdevs.append(allocator, 0);
        try file_mtimes.append(allocator, mtime);
        try file_digests.append(allocator, switch (item.kind) {
            .dir => "",
            .file => try sha256Hex(allocator, content),
        });
        try file_linktos.append(allocator, "");
        const config_file = item.kind == .file and std.mem.startsWith(u8, item.path, "etc/");
        if (config_file) has_config = true;
        try file_flags.append(allocator, if (config_file) 1 else 0);
        try file_users.append(allocator, "root");
        try file_groups.append(allocator, "root");
        try file_devices.append(allocator, 1);
        try file_inodes.append(allocator, @intCast(index + 1));
        try file_langs.append(allocator, "");
        try file_verify_flags.append(allocator, 0xffffffff);
    }

    const deps = try buildDependencies(allocator, config, package, config.version, release, epoch, has_config, scripts);

    const description = config.description orelse "";
    const summary = firstLine(description);
    const license = config.options.license orelse config.license orelse "Unspecified";

    var builder: HeaderBuilder = .{ .allocator = allocator };
    defer builder.records.deinit(allocator);

    try builder.addStrings(100, &.{"C"});
    try builder.addString(1000, package);
    try builder.addString(1001, config.version);
    try builder.addString(1002, release);
    if (epoch) |e| try builder.addInt32(1003, &.{e});
    try builder.addI18n(1004, if (summary.len == 0) package else summary);
    try builder.addI18n(1005, description);
    try builder.addInt32(1006, &.{mtime});
    try builder.addString(1007, "localhost");
    try builder.addInt32(1009, &.{@intCast(installed_size)});
    try builder.addString(1014, license);
    if (config.packager) |packager| try builder.addString(1015, packager);
    try builder.addI18n(1016, config.options.group);
    if (config.options.url) |url| try builder.addString(1020, url);
    try builder.addString(1021, "linux");
    try builder.addString(1022, config.arch);
    try builder.addInt32(1028, file_sizes.items);
    try builder.addInt16(1030, file_modes.items);
    try builder.addInt16(1033, file_rdevs.items);
    try builder.addInt32(1034, file_mtimes.items);
    try builder.addStrings(1035, file_digests.items);
    try builder.addStrings(1036, file_linktos.items);
    try builder.addInt32(1037, file_flags.items);
    try builder.addStrings(1039, file_users.items);
    try builder.addStrings(1040, file_groups.items);
    try builder.addString(1044, "(none)");
    try builder.addInt32(1045, file_verify_flags.items);
    try builder.addStrings(1047, try dependencyNames(deps.provides, allocator));
    try builder.addInt32(1048, try dependencyFlags(deps.requires, allocator));
    try builder.addStrings(1049, try dependencyNames(deps.requires, allocator));
    try builder.addStrings(1050, try dependencyVersions(deps.requires, allocator));
    try builder.addInt32(1053, try dependencyFlags(deps.conflicts, allocator));
    try builder.addStrings(1054, try dependencyNames(deps.conflicts, allocator));
    try builder.addStrings(1055, try dependencyVersions(deps.conflicts, allocator));
    try builder.addString(1064, "4.16.0");
    try builder.addStrings(1090, try dependencyNames(deps.obsoletes, allocator));
    try builder.addInt32(1095, file_devices.items);
    try builder.addInt32(1096, file_inodes.items);
    try builder.addStrings(1097, file_langs.items);
    try builder.addInt32(1112, try dependencyFlags(deps.provides, allocator));
    try builder.addStrings(1113, try dependencyVersions(deps.provides, allocator));
    try builder.addInt32(1114, try dependencyFlags(deps.obsoletes, allocator));
    try builder.addStrings(1115, try dependencyVersions(deps.obsoletes, allocator));
    try builder.addInt32(1116, dir_indexes.items);
    try builder.addStrings(1117, base_names.items);
    try builder.addStrings(1118, dir_names.items);
    try builder.addString(1124, "cpio");
    try builder.addString(1125, "gzip");
    try builder.addString(1126, "9");
    try builder.addString(1132, try std.fmt.allocPrint(allocator, "{s}-linux", .{config.arch}));
    try builder.addInt32(5011, &.{8});
    try builder.addString(5062, "utf-8");
    try builder.addStrings(5092, &.{try sha256Hex(allocator, payload)});
    try builder.addStrings(5097, &.{try sha256Hex(allocator, cpio)});

    if (scripts.pre_install) |script| try builder.addString(1023, script);
    if (scripts.post_install) |script| try builder.addString(1024, script);
    if (scripts.pre_uninstall) |script| try builder.addString(1025, script);
    if (scripts.post_uninstall) |script| try builder.addString(1026, script);

    return builder.serialize(63);
}

fn dependencyNames(deps: []const Dependency, allocator: std.mem.Allocator) ![]const []const u8 {
    const names = try allocator.alloc([]const u8, deps.len);
    for (deps, names) |dep, *name| name.* = dep.name;
    return names;
}

fn dependencyVersions(deps: []const Dependency, allocator: std.mem.Allocator) ![]const []const u8 {
    const versions = try allocator.alloc([]const u8, deps.len);
    for (deps, versions) |dep, *version| version.* = dep.version;
    return versions;
}

fn dependencyFlags(deps: []const Dependency, allocator: std.mem.Allocator) ![]const u32 {
    const flags = try allocator.alloc(u32, deps.len);
    for (deps, flags) |dep, *flag| flag.* = dep.flags;
    return flags;
}

fn buildSignature(allocator: std.mem.Allocator, header: []const u8, payload_len: usize) ![]u8 {
    var builder: HeaderBuilder = .{ .allocator = allocator };
    defer builder.records.deinit(allocator);

    try builder.addString(269, try sha1Hex(allocator, header));
    try builder.addString(273, try sha256Hex(allocator, header));
    try builder.addInt32(1000, &.{@intCast(header.len + payload_len)});

    const bytes = try builder.serialize(62);
    return bytes;
}

fn writeLead(writer: *Io.Writer, name: []const u8) !void {
    var lead: [96]u8 = @splat(0);
    const magic = [_]u8{ 0xed, 0xab, 0xee, 0xdb };
    @memcpy(lead[0..4], &magic);
    lead[4] = 3;
    lead[5] = 0;
    std.mem.writeInt(u16, lead[6..8], 0, .big);
    const name_len = @min(name.len, 65);
    @memcpy(lead[10..][0..name_len], name[0..name_len]);
    std.mem.writeInt(u16, lead[76..78], 1, .big);
    std.mem.writeInt(u16, lead[78..80], 5, .big);
    try writer.writeAll(&lead);
}

test "rpm version converts prerelease" {
    const version = try packageVersion(std.testing.allocator, "1.0.0-beta.1");
    defer std.testing.allocator.free(version);
    try std.testing.expectEqualStrings("1.0.0~beta.1", version);
}

test "rpm release validation" {
    try validateRelease("1");
    try validateRelease("2.el9");
    try std.testing.expectError(error.InvalidRelease, validateRelease("1-2"));
    try std.testing.expectError(error.InvalidRelease, validateRelease(""));
}

test "dependency operators" {
    const greater = parseDependency("foo >= 1.0");
    try std.testing.expectEqualStrings("foo", greater.name);
    try std.testing.expectEqual(@as(u32, 0xC), greater.flags);
    try std.testing.expectEqualStrings("1.0", greater.version);

    const less = parseDependency("bar <= 2");
    try std.testing.expectEqual(@as(u32, 0xA), less.flags);

    const plain = parseDependency("baz");
    try std.testing.expectEqual(@as(u32, 0), plain.flags);
    try std.testing.expectEqualStrings("", plain.version);
}

test "rpm architecture names" {
    try std.testing.expectEqualStrings("x86_64", try archName(.x86_64));
    try std.testing.expectEqualStrings("aarch64", try archName(.aarch64));
    try std.testing.expectEqualStrings("i686", try archName(.x86));
    try std.testing.expectError(error.UnsupportedArchitecture, archName(.wasm32));
}
