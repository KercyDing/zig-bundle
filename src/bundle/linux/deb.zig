//! Native Debian package writer.
const std = @import("std");

const icons = @import("../common/icons.zig");
const resources = @import("../common/resources.zig");
const tar_gz = @import("../common/tar_gz.zig");

const Io = std.Io;

pub const Options = struct {
    /// Runtime dependencies.
    depends: []const []const u8 = &.{},
    /// Pre-dependencies.
    pre_depends: []const []const u8 = &.{},
    /// Recommended packages.
    recommends: []const []const u8 = &.{},
    /// Suggested packages.
    suggests: []const []const u8 = &.{},
    /// Packages enhanced by this one.
    enhances: []const []const u8 = &.{},
    /// Conflicting packages.
    conflicts: []const []const u8 = &.{},
    /// Packages broken by this one.
    breaks: []const []const u8 = &.{},
    /// Packages replaced by this one.
    replaces: []const []const u8 = &.{},
    /// Virtual packages provided by this one.
    provides: []const []const u8 = &.{},
    /// Debian section.
    section: ?[]const u8 = "utils",
    /// Debian priority.
    priority: ?[]const u8 = "optional",
    /// Project homepage.
    homepage: ?[]const u8 = null,
    /// Multi-arch field value, e.g. `"same"` or `"foreign"`.
    multi_arch: ?[]const u8 = null,
    /// Configuration files outside `/etc`.
    conf_files: []const []const u8 = &.{},
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

pub const Config = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    /// Maintainer in `Name <email>` form.
    maintainer: ?[]const u8 = null,
    description: ?[]const u8 = null,
    /// Semicolon-separated desktop categories.
    categories: ?[]const u8 = null,
    /// License identifier or short name, written to the copyright file.
    license: ?[]const u8 = null,
    /// Copyright notice line; defaults to `Copyright <year> <maintainer>`.
    copyright: ?[]const u8 = null,
    executable_name: []const u8,
    payload: []const resources.Entry,
    icons: []const icons.Png = &.{},
    /// Upstream changelog to compress into `changelog.gz`; generated when null.
    changelog_path: ?[]const u8 = null,
    /// License file content appended to the copyright file.
    license_path: ?[]const u8 = null,
    /// Number of leading license file lines to skip.
    license_skip_lines: usize = 0,
    /// Additional files installed verbatim.
    assets: []const Asset = &.{},
    /// Directory containing maintainer scripts.
    maintainer_scripts_path: ?[]const u8 = null,
    /// Debian triggers file.
    triggers_path: ?[]const u8 = null,
    /// Entry timestamp in seconds since the Unix epoch.
    mtime: u64 = tar_gz.default_mtime,
    options: Options = .{},
};

/// Maps a Zig CPU architecture to the Debian architecture name.
pub fn archName(arch: std.Target.Cpu.Arch) ![]const u8 {
    return switch (arch) {
        .x86_64 => "amd64",
        .x86 => "i386",
        .aarch64 => "arm64",
        .arm, .armeb, .thumb, .thumbeb => "armhf",
        .riscv64 => "riscv64",
        else => error.UnsupportedArchitecture,
    };
}

/// Builds a `.deb` from the shared payload.
pub fn bundle(
    io: Io,
    file: Io.File,
    config: Config,
    arch: []const u8,
    output_dir: []const u8,
    package_basename: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var data_items: std.ArrayList(tar_gz.Item) = .empty;
    defer data_items.deinit(allocator);

    for (config.payload) |entry| {
        const path = switch (entry.executable) {
            true => try std.fmt.allocPrint(allocator, "usr/bin/{s}", .{entry.archive_path}),
            false => try std.fmt.allocPrint(allocator, "usr/lib/{s}/{s}", .{ config.name, entry.archive_path }),
        };

        switch (entry.kind) {
            .dir => try data_items.append(allocator, .{ .path = path, .kind = .dir, .mode = 0o755 }),
            .file => try data_items.append(allocator, .{
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
        const path = try std.fmt.allocPrint(allocator, "usr/share/icons/hicolor/{d}x{d}/apps/{s}.png", .{
            icon.width,
            icon.height,
            config.executable_name,
        });
        try data_items.append(allocator, .{
            .path = path,
            .kind = .file,
            .mode = 0o644,
            .content = .{ .file = icon.path },
        });
    }

    const desktop = try renderDesktop(allocator, config, config.icons.len > 0);
    try data_items.append(allocator, .{
        .path = try std.fmt.allocPrint(allocator, "usr/share/applications/{s}.desktop", .{config.name}),
        .kind = .file,
        .mode = 0o644,
        .content = .{ .bytes = desktop },
    });

    for (config.assets) |asset| {
        try addAsset(io, allocator, asset, &data_items);
    }

    const package = try toKebabCase(allocator, config.name);
    const maintainer = config.maintainer orelse return error.MissingMaintainer;
    const doc_dir = try std.fmt.allocPrint(allocator, "usr/share/doc/{s}", .{package});

    const license_text = try loadLicense(io, allocator, config);
    const copyright = try renderCopyright(allocator, config, package, maintainer, config.mtime, license_text);
    try data_items.append(allocator, .{
        .path = try std.fmt.allocPrint(allocator, "{s}/copyright", .{doc_dir}),
        .kind = .file,
        .mode = 0o644,
        .content = .{ .bytes = copyright },
    });

    const changelog = try loadChangelog(io, allocator, config, package, maintainer);
    try data_items.append(allocator, .{
        .path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ doc_dir, changelogFileName(config.version) }),
        .kind = .file,
        .mode = 0o644,
        .content = .{ .bytes = changelog },
    });

    // dpkg does not create missing parents, so every ancestor directory must
    // be present in the archive.
    try addParentDirectories(allocator, &data_items);

    std.mem.sort(tar_gz.Item, data_items.items, {}, struct {
        fn lessThan(_: void, lhs: tar_gz.Item, rhs: tar_gz.Item) bool {
            return std.mem.lessThan(u8, lhs.path, rhs.path);
        }
    }.lessThan);

    var md5sums: std.Io.Writer.Allocating = .init(allocator);
    defer md5sums.deinit();

    var installed_size: u64 = 0;
    for (data_items.items) |item| {
        if (item.kind != .file) continue;

        const hashed: struct { size: u64, digest: [16]u8 } = switch (item.content) {
            .bytes => |bytes| .{ .size = bytes.len, .digest = md5Bytes(bytes) },
            .file => |path| blk: {
                const stat = try Io.Dir.cwd().statFile(io, path, .{});
                break :blk .{ .size = stat.size, .digest = try md5File(io, path) };
            },
        };

        installed_size += (hashed.size + 2047) / 1024;
        try md5sums.writer.printHex(&hashed.digest, .lower);
        try md5sums.writer.print("  {s}\n", .{item.path});
    }

    const control = try renderControl(allocator, config, package, maintainer, arch, installed_size);
    const conffiles = try renderConffiles(allocator, config.options.conf_files, data_items.items);

    var control_items: std.ArrayList(tar_gz.Item) = .empty;
    defer control_items.deinit(allocator);
    try control_items.append(allocator, .{ .path = "control", .kind = .file, .mode = 0o644, .content = .{ .bytes = control } });
    try control_items.append(allocator, .{ .path = "md5sums", .kind = .file, .mode = 0o644, .content = .{ .bytes = md5sums.written() } });
    if (conffiles) |bytes| {
        try control_items.append(allocator, .{ .path = "conffiles", .kind = .file, .mode = 0o644, .content = .{ .bytes = bytes } });
    }
    if (config.maintainer_scripts_path) |dir| {
        try addMaintainerScripts(io, allocator, dir, &control_items);
    }
    if (config.triggers_path) |path| {
        const bytes = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
        try control_items.append(allocator, .{ .path = "triggers", .kind = .file, .mode = 0o644, .content = .{ .bytes = bytes } });
    }

    const control_path = try std.fmt.allocPrint(allocator, "{s}/{s}.control.tar.gz", .{ output_dir, package_basename });
    const data_path = try std.fmt.allocPrint(allocator, "{s}/{s}.data.tar.gz", .{ output_dir, package_basename });
    defer {
        Io.Dir.cwd().deleteFile(io, control_path) catch {};
        Io.Dir.cwd().deleteFile(io, data_path) catch {};
    }

    {
        var control_file = try Io.Dir.cwd().createFile(io, control_path, .{ .truncate = true });
        defer control_file.close(io);
        try tar_gz.writeItems(io, control_file, control_items.items, config.mtime, 6);
    }
    {
        var data_file = try Io.Dir.cwd().createFile(io, data_path, .{ .truncate = true });
        defer data_file.close(io);
        try tar_gz.writeItems(io, data_file, data_items.items, config.mtime, 6);
    }

    try writeArchive(io, file, control_path, data_path, config.mtime);
}

fn addParentDirectories(
    allocator: std.mem.Allocator,
    items: *std.ArrayList(tar_gz.Item),
) !void {
    var dirs: std.StringHashMap(void) = .init(allocator);
    defer dirs.deinit();

    for (items.items) |item| {
        if (item.kind == .dir) try dirs.put(item.path, {});
    }

    // The list is appended to only after iteration: growing it inside the
    // loop would invalidate the slice being walked.
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

fn validateAssetPath(path: []const u8) !void {
    if (path.len == 0) return error.InvalidAssetDestination;

    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) return error.InvalidAssetDestination;
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) {
            return error.InvalidAssetDestination;
        }
    }
}

fn normalizeAssetDestination(allocator: std.mem.Allocator, dest: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, dest, "/\\");
    if (trimmed.len == 0) return error.InvalidAssetDestination;

    const normalized = try allocator.alloc(u8, trimmed.len);
    for (trimmed, normalized) |c, *out| out.* = if (c == '\\') '/' else c;
    try validateAssetPath(normalized);
    return normalized;
}

fn addAsset(
    io: Io,
    allocator: std.mem.Allocator,
    asset: Asset,
    items: *std.ArrayList(tar_gz.Item),
) !void {
    const source = std.mem.trimEnd(u8, asset.source_path, "/\\");
    const stat = try Io.Dir.cwd().statFile(io, source, .{});
    const dest_is_directory = std.mem.endsWith(u8, asset.dest, "/") or
        std.mem.endsWith(u8, asset.dest, "\\");
    const dest = try normalizeAssetDestination(allocator, asset.dest);

    switch (stat.kind) {
        .file => {
            const path = if (dest_is_directory)
                try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest, std.fs.path.basename(source) })
            else
                dest;
            if (dest_is_directory) try validateAssetPath(path);
            try appendAssetFile(io, allocator, source, path, asset.mode, items);
        },
        .directory => try addAssetDirectory(io, allocator, source, dest, asset.mode, items),
        else => return error.UnsupportedAssetType,
    }
}

fn isManPage(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "usr/share/man/");
}

/// Debian requires gzip-compressed man pages; compress uncompressed sources
/// and add the `.gz` suffix automatically.
fn appendAssetFile(
    io: Io,
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
    mode: u32,
    items: *std.ArrayList(tar_gz.Item),
) !void {
    if (isManPage(path) and !std.mem.endsWith(u8, path, ".gz")) {
        const dest = try std.fmt.allocPrint(allocator, "{s}.gz", .{path});
        if (std.mem.endsWith(u8, source, ".gz")) {
            try items.append(allocator, .{
                .path = dest,
                .kind = .file,
                .mode = mode,
                .content = .{ .file = source },
            });
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

    try items.append(allocator, .{
        .path = path,
        .kind = .file,
        .mode = mode,
        .content = .{ .file = source },
    });
}

fn addAssetDirectory(
    io: Io,
    allocator: std.mem.Allocator,
    source: []const u8,
    dest: []const u8,
    mode: u32,
    items: *std.ArrayList(tar_gz.Item),
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

fn addMaintainerScripts(
    io: Io,
    allocator: std.mem.Allocator,
    dir: []const u8,
    items: *std.ArrayList(tar_gz.Item),
) !void {
    const stat = try Io.Dir.cwd().statFile(io, dir, .{});
    if (stat.kind != .directory) return error.InvalidMaintainerScripts;

    const scripts = [_]struct { name: []const u8, mode: u32 }{
        .{ .name = "preinst", .mode = 0o755 },
        .{ .name = "postinst", .mode = 0o755 },
        .{ .name = "prerm", .mode = 0o755 },
        .{ .name = "postrm", .mode = 0o755 },
        .{ .name = "config", .mode = 0o755 },
        .{ .name = "templates", .mode = 0o644 },
    };

    for (scripts) |script| {
        const path = try std.fs.path.join(allocator, &.{ dir, script.name });
        const file_stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        if (file_stat.kind != .file) continue;

        const bytes = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
        try items.append(allocator, .{
            .path = script.name,
            .kind = .file,
            .mode = script.mode,
            .content = .{ .bytes = bytes },
        });
    }
}

fn loadLicense(io: Io, allocator: std.mem.Allocator, config: Config) !?[]const u8 {
    const path = config.license_path orelse return null;
    const source = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));

    var start: usize = 0;
    var skipped: usize = 0;
    while (skipped < config.license_skip_lines) : (skipped += 1) {
        const newline = std.mem.indexOfScalarPos(u8, source, start, '\n') orelse {
            start = source.len;
            break;
        };
        start = newline + 1;
    }
    return source[start..];
}

fn renderConffiles(
    allocator: std.mem.Allocator,
    configured: []const []const u8,
    items: []const tar_gz.Item,
) !?[]u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);

    for (configured) |path| {
        const normalized = std.mem.trimStart(u8, path, "/");
        if (normalized.len == 0) continue;
        try paths.append(allocator, try std.fmt.allocPrint(allocator, "/{s}", .{normalized}));
    }

    for (items) |item| {
        if (item.kind != .file) continue;
        if (!std.mem.startsWith(u8, item.path, "etc/")) continue;
        try paths.append(allocator, try std.fmt.allocPrint(allocator, "/{s}", .{item.path}));
    }

    if (paths.items.len == 0) return null;

    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    for (paths.items, 0..) |path, index| {
        if (index > 0 and std.mem.eql(u8, path, paths.items[index - 1])) continue;
        try output.appendSlice(allocator, path);
        try output.append(allocator, '\n');
    }
    return try output.toOwnedSlice(allocator);
}

fn md5Bytes(bytes: []const u8) [16]u8 {
    var hasher = std.crypto.hash.Md5.init(.{});
    hasher.update(bytes);
    var digest: [16]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn md5File(io: Io, path: []const u8) ![16]u8 {
    var file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    var chunk: [16 * 1024]u8 = undefined;

    var hasher = std.crypto.hash.Md5.init(.{});
    while (true) {
        const n = try reader.interface.readSliceShort(&chunk);
        if (n == 0) break;
        hasher.update(chunk[0..n]);
    }
    var digest: [16]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

pub fn toKebabCase(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var previous_lower_or_digit = false;
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (std.ascii.isUpper(c) and previous_lower_or_digit) try out.append(allocator, '-');
            try out.append(allocator, std.ascii.toLower(c));
            previous_lower_or_digit = std.ascii.isLower(c) or std.ascii.isDigit(c);
        } else if (out.items.len > 0 and out.items[out.items.len - 1] != '-') {
            try out.append(allocator, '-');
            previous_lower_or_digit = false;
        }
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') out.items.len -= 1;
    if (out.items.len == 0) return error.InvalidPackageName;
    return out.toOwnedSlice(allocator);
}

fn firstLine(text: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    return std.mem.trim(u8, text[0..end], " \t\r");
}

fn writeRelationship(writer: *Io.Writer, field: []const u8, values: []const []const u8) !void {
    if (values.len == 0) return;

    try writer.print("{s}: ", .{field});
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeAll(", ");
        try writer.writeAll(value);
    }
    try writer.writeByte('\n');
}

/// Writes `text` word-wrapped to 79 characters, prefixing the first line with
/// `first_prefix` and the remaining lines with `continuation_prefix`.
fn writeWrapped(writer: *Io.Writer, text: []const u8, first_prefix: []const u8, continuation_prefix: []const u8) !void {
    var rest = std.mem.trim(u8, text, " \t\r");
    var first = true;

    while (rest.len > 79) {
        var cut: usize = 79;
        while (cut > 0 and rest[cut] != ' ') : (cut -= 1) {}
        if (cut == 0) {
            cut = 79;
            // Never split a UTF-8 sequence.
            while (cut > 0 and (rest[cut] & 0xC0) == 0x80) : (cut -= 1) {}
        }

        const head = std.mem.trimEnd(u8, rest[0..cut], " \t");
        try writer.print("{s}{s}\n", .{ if (first) first_prefix else continuation_prefix, head });
        first = false;
        rest = std.mem.trimStart(u8, rest[cut..], " \t");
    }

    try writer.print("{s}{s}\n", .{ if (first) first_prefix else continuation_prefix, rest });
}

fn renderControl(
    allocator: std.mem.Allocator,
    config: Config,
    package: []const u8,
    maintainer: []const u8,
    arch: []const u8,
    installed_size: u64,
) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    try writer.print("Package: {s}\n", .{package});
    try writer.print("Version: {s}\n", .{config.version});
    try writer.print("Architecture: {s}\n", .{arch});
    if (config.options.multi_arch) |multi_arch| {
        try writer.print("Multi-Arch: {s}\n", .{multi_arch});
    }
    if (config.options.homepage) |homepage| {
        if (homepage.len > 0) try writer.print("Homepage: {s}\n", .{homepage});
    }
    if (config.options.section) |section| {
        if (section.len > 0) try writer.print("Section: {s}\n", .{section});
    }
    try writer.print("Priority: {s}\n", .{config.options.priority orelse "optional"});
    try writer.print("Maintainer: {s}\n", .{maintainer});
    try writer.print("Installed-Size: {d}\n", .{installed_size});

    try writeRelationship(writer, "Depends", config.options.depends);
    try writeRelationship(writer, "Pre-Depends", config.options.pre_depends);
    try writeRelationship(writer, "Recommends", config.options.recommends);
    try writeRelationship(writer, "Suggests", config.options.suggests);
    try writeRelationship(writer, "Enhances", config.options.enhances);
    try writeRelationship(writer, "Conflicts", config.options.conflicts);
    try writeRelationship(writer, "Breaks", config.options.breaks);
    try writeRelationship(writer, "Replaces", config.options.replaces);
    try writeRelationship(writer, "Provides", config.options.provides);

    const description = config.description orelse "";
    const synopsis = firstLine(description);
    try writeWrapped(writer, if (synopsis.len == 0) "(none)" else synopsis, "Description: ", " ");

    // Continuation lines form the extended description. Empty lines are
    // dropped: lintian treats an empty extended paragraph as a warning.
    var lines = std.mem.splitScalar(u8, description, '\n');
    _ = lines.next();
    var has_extended = false;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        try writeWrapped(writer, trimmed, " ", " ");
        has_extended = true;
    }
    if (!has_extended) try writeWrapped(writer, "(none)", " ", " ");

    return allocating.toOwnedSlice();
}

const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
// 1970-01-01 was a Thursday.
const weekday_names = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };

fn writeRfc2822(writer: *Io.Writer, timestamp: u64) !void {
    const seconds: std.time.epoch.EpochSeconds = .{ .secs = timestamp };
    const epoch_day = seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = seconds.getDaySeconds();
    const weekday = weekday_names[@intCast((epoch_day.day + 3) % 7)];

    try writer.print("{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} +0000", .{
        weekday,
        month_day.day_index + 1,
        month_names[@intCast(month_day.month.numeric() - 1)],
        year_day.year,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

fn renderCopyright(
    allocator: std.mem.Allocator,
    config: Config,
    package: []const u8,
    maintainer: []const u8,
    timestamp: u64,
    license_text: ?[]const u8,
) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    const seconds: std.time.epoch.EpochSeconds = .{ .secs = timestamp };
    const year = seconds.getEpochDay().calculateYearDay().year;

    try writer.print("Package: {s}\n", .{package});
    try writer.print("Upstream-Name: {s}\n", .{config.name});
    try writer.print("Upstream-Contact: {s}\n", .{maintainer});
    if (config.copyright) |notice| {
        try writer.print("{s}\n", .{notice});
    } else {
        try writer.print("Copyright {d} {s}\n", .{ year, maintainer });
    }
    try writer.print("License: {s}\n", .{config.license orelse "not specified"});

    if (license_text) |text| {
        if (text.len > 0) {
            try writer.writeByte('\n');
            try writer.writeAll(text);
            if (text[text.len - 1] != '\n') try writer.writeByte('\n');
        }
    }

    return allocating.toOwnedSlice();
}

/// Native packages use `changelog.gz`; versions with a Debian revision use
/// `changelog.Debian.gz`.
fn changelogFileName(version: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, version, '-') == null)
        "changelog.gz"
    else
        "changelog.Debian.gz";
}

fn loadChangelog(
    io: Io,
    allocator: std.mem.Allocator,
    config: Config,
    package: []const u8,
    maintainer: []const u8,
) ![]u8 {
    if (config.changelog_path) |path| {
        const source = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
        // Keep pre-compressed changelogs as-is.
        if (std.mem.endsWith(u8, path, ".gz")) return source;
        return tar_gz.gzipBytes(allocator, source, 9);
    }

    var allocating: std.Io.Writer.Allocating = .init(allocator);
    defer allocating.deinit();
    const writer = &allocating.writer;

    try writer.print("{s} ({s}) unstable; urgency=medium\n\n", .{ package, config.version });
    try writer.print("  * Release {s}.\n\n", .{config.version});
    try writer.print(" -- {s}  ", .{maintainer});
    try writeRfc2822(writer, config.mtime);
    try writer.writeByte('\n');

    return tar_gz.gzipBytes(allocator, allocating.written(), 9);
}

fn renderDesktop(allocator: std.mem.Allocator, config: Config, has_icon: bool) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    try writer.writeAll("[Desktop Entry]\n");
    if (config.description) |description| {
        const comment = firstLine(description);
        if (comment.len > 0) try writer.print("Comment={s}\n", .{comment});
    }

    const needs_quotes = std.mem.indexOfAny(u8, config.executable_name, " \t") != null;
    if (needs_quotes) {
        try writer.print("Exec=\"{s}\"\n", .{config.executable_name});
    } else {
        try writer.print("Exec={s}\n", .{config.executable_name});
    }
    try writer.print("StartupWMClass={s}\n", .{config.executable_name});
    if (has_icon) try writer.print("Icon={s}\n", .{config.executable_name});
    if (config.categories) |categories| {
        if (categories.len > 0) {
            try writer.print("Categories={s}", .{categories});
            if (categories[categories.len - 1] != ';') try writer.writeByte(';');
            try writer.writeByte('\n');
        }
    }
    try writer.print("Name={s}\n", .{config.name});
    try writer.writeAll("Terminal=false\n");
    try writer.writeAll("Type=Application\n");

    return allocating.toOwnedSlice();
}

fn writeDecimalField(field: []u8, value: u64) void {
    @memset(field, ' ');
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    @memcpy(field[0..text.len], text);
}

fn writeOctalField(field: []u8, value: u64) void {
    @memset(field, ' ');
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{o}", .{value}) catch unreachable;
    @memcpy(field[0..text.len], text);
}

fn writeArHeader(writer: *Io.Writer, name: []const u8, size: u64, mtime: u64) !void {
    var header: [60]u8 = @splat(' ');

    if (name.len + 1 > 16) return error.NameTooLong;
    @memcpy(header[0..name.len], name);
    header[name.len] = '/';

    writeDecimalField(header[16..28], mtime);
    writeDecimalField(header[28..34], 0); // uid
    writeDecimalField(header[34..40], 0); // gid
    writeOctalField(header[40..48], 0o100644); // mode
    writeDecimalField(header[48..58], size); // size

    header[58] = '`';
    header[59] = '\n';
    try writer.writeAll(&header);
}

fn writeArMemberFile(io: Io, writer: *Io.Writer, name: []const u8, path: []const u8, mtime: u64) !void {
    const stat = try Io.Dir.cwd().statFile(io, path, .{});
    try writeArHeader(writer, name, stat.size, mtime);

    var file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    _ = try writer.sendFileAll(&reader, .unlimited);

    if (stat.size % 2 == 1) try writer.writeByte('\n');
}

fn writeArMemberBytes(writer: *Io.Writer, name: []const u8, bytes: []const u8, mtime: u64) !void {
    try writeArHeader(writer, name, bytes.len, mtime);
    try writer.writeAll(bytes);
    if (bytes.len % 2 == 1) try writer.writeByte('\n');
}

/// Writes the final ar archive from the prepared control and data tarballs.
fn writeArchive(
    io: Io,
    file: Io.File,
    control_path: []const u8,
    data_path: []const u8,
    mtime: u64,
) !void {
    var write_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &write_buffer);

    try file_writer.interface.writeAll("!<arch>\n");
    try writeArMemberBytes(&file_writer.interface, "debian-binary", "2.0\n", mtime);
    try writeArMemberFile(io, &file_writer.interface, "control.tar.gz", control_path, mtime);
    try writeArMemberFile(io, &file_writer.interface, "data.tar.gz", data_path, mtime);
    try file_writer.interface.flush();
}

test "kebab case" {
    const allocator = std.testing.allocator;

    const hello = try toKebabCase(allocator, "HelloBundle");
    defer allocator.free(hello);
    try std.testing.expectEqualStrings("hello-bundle", hello);

    const spaced = try toKebabCase(allocator, "My App_v2");
    defer allocator.free(spaced);
    try std.testing.expectEqualStrings("my-app-v2", spaced);
}

test "debian architecture" {
    try std.testing.expectEqualStrings("amd64", try archName(.x86_64));
    try std.testing.expectEqualStrings("arm64", try archName(.aarch64));
    try std.testing.expectEqualStrings("i386", try archName(.x86));
    try std.testing.expectError(error.UnsupportedArchitecture, archName(.wasm32));
}

test "kebab case collapses separators" {
    const allocator = std.testing.allocator;

    const name = try toKebabCase(allocator, "My--App__v2");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("my-app-v2", name);
}

test "kebab case rejects empty" {
    try std.testing.expectError(error.InvalidPackageName, toKebabCase(std.testing.allocator, "__"));
}

fn testConfig() Config {
    return .{
        .name = "App",
        .identifier = "com.example.app",
        .version = "1.0.0",
        .maintainer = "Example <example@example.com>",
        .executable_name = "app",
        .payload = &.{},
    };
}

test "description includes extended text" {
    const allocator = std.testing.allocator;

    var config = testConfig();
    config.description = "Synopsis\n\nBody line";

    const control = try renderControl(allocator, config, "app", config.maintainer.?, "amd64", 0);
    defer allocator.free(control);

    try std.testing.expect(std.mem.indexOf(u8, control, "Description: Synopsis\n Body line\n") != null);
}

test "description falls back to an extended line" {
    const allocator = std.testing.allocator;

    const control = try renderControl(allocator, testConfig(), "app", "Example <example@example.com>", "amd64", 0);
    defer allocator.free(control);

    try std.testing.expect(std.mem.indexOf(u8, control, "Description: (none)\n (none)\n") != null);
}

test "writeWrapped keeps lines within 79 columns" {
    var allocating: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer allocating.deinit();

    const text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau";
    try writeWrapped(&allocating.writer, text, "", " ");

    var lines = std.mem.splitScalar(u8, allocating.written(), '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        try std.testing.expect(line.len <= 79);
    }
}

test "conffiles are sorted and deduplicated" {
    const items = [_]tar_gz.Item{
        .{ .path = "etc/z.conf", .kind = .file },
        .{ .path = "usr/bin/app", .kind = .file },
        .{ .path = "etc/app.conf", .kind = .file },
    };

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const conffiles = (try renderConffiles(arena_state.allocator(), &.{ "etc/app.conf", "/opt/app.conf" }, &items)).?;
    try std.testing.expectEqualStrings(
        "/etc/app.conf\n/etc/z.conf\n/opt/app.conf\n",
        conffiles,
    );
}

test "asset paths reject traversal" {
    try std.testing.expectError(error.InvalidAssetDestination, validateAssetPath("../etc/passwd"));
    try std.testing.expectError(error.InvalidAssetDestination, validateAssetPath("usr//bin"));
    try std.testing.expectError(error.InvalidAssetDestination, validateAssetPath(""));
    try validateAssetPath("usr/share/app/file.txt");
}

test "asset destination normalizes separators" {
    const dest = try normalizeAssetDestination(std.testing.allocator, "usr\\share\\app\\");
    defer std.testing.allocator.free(dest);

    try std.testing.expectEqualStrings("usr/share/app", dest);
}

test "control relationship fields" {
    const allocator = std.testing.allocator;

    var config = testConfig();
    config.options = .{
        .depends = &.{"libc6"},
        .recommends = &.{ "a", "b" },
        .homepage = "https://example.com",
        .multi_arch = "foreign",
    };

    const control = try renderControl(allocator, config, "app", config.maintainer.?, "amd64", 1);
    defer allocator.free(control);

    try std.testing.expect(std.mem.indexOf(u8, control, "Multi-Arch: foreign\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, control, "Homepage: https://example.com\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, control, "Depends: libc6\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, control, "Recommends: a, b\n") != null);
}

test "desktop categories are terminated" {
    var config = testConfig();
    config.categories = "Utility;Development";

    const desktop = try renderDesktop(std.testing.allocator, config, false);
    defer std.testing.allocator.free(desktop);

    try std.testing.expect(std.mem.indexOf(u8, desktop, "Categories=Utility;Development;\n") != null);
}

test "man pages are detected" {
    try std.testing.expect(isManPage("usr/share/man/man1/app.1"));
    try std.testing.expect(isManPage("usr/share/man/fr/man1/app.1"));
    try std.testing.expect(!isManPage("usr/share/doc/app/manual.txt"));
}

test "changelog name follows native version" {
    try std.testing.expectEqualStrings("changelog.gz", changelogFileName("1.0.0"));
    try std.testing.expectEqualStrings("changelog.Debian.gz", changelogFileName("1.0.0-1"));
    try std.testing.expectEqualStrings("changelog.Debian.gz", changelogFileName("1.0.0-beta"));
}

test "rfc 2822 date" {
    var allocating: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer allocating.deinit();

    try writeRfc2822(&allocating.writer, 315532800);
    try std.testing.expectEqualStrings("Tue, 01 Jan 1980 00:00:00 +0000", allocating.written());
}

test "adds every parent directory" {
    const allocator = std.testing.allocator;

    var items: std.ArrayList(tar_gz.Item) = .empty;
    defer items.deinit(allocator);

    try items.append(allocator, .{ .path = "usr/bin/app", .kind = .file, .content = .{ .bytes = "x" } });
    try items.append(allocator, .{ .path = "usr/share/applications/app.desktop", .kind = .file, .content = .{ .bytes = "x" } });
    try items.append(allocator, .{ .path = "usr/lib/App/data/nested", .kind = .dir });

    try addParentDirectories(allocator, &items);

    const expected = [_][]const u8{
        "usr",
        "usr/bin",
        "usr/lib",
        "usr/lib/App",
        "usr/lib/App/data",
        "usr/share",
        "usr/share/applications",
    };
    for (expected) |dir| {
        var found = false;
        for (items.items) |item| {
            if (item.kind == .dir and std.mem.eql(u8, item.path, dir)) found = true;
        }
        try std.testing.expect(found);
    }
}
