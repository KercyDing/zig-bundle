//! Native Debian package writer.
const std = @import("std");

const icons = @import("../common/icons.zig");
const resources = @import("../common/resources.zig");
const tar_gz = @import("../common/tar_gz.zig");

const Io = std.Io;

pub const Options = struct {
    depends: []const []const u8 = &.{},
    section: ?[]const u8 = "utils",
    priority: ?[]const u8 = "optional",
};

pub const Config = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    publisher: ?[]const u8 = null,
    description: ?[]const u8 = null,
    executable_name: []const u8,
    payload: []const resources.Entry,
    icons: []const icons.Png = &.{},
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

        installed_size += hashed.size;
        try md5sums.writer.printHex(&hashed.digest, .lower);
        try md5sums.writer.print("  {s}\n", .{item.path});
    }

    const control = try renderControl(allocator, config, arch, installed_size, config.options.depends);
    const control_items = [_]tar_gz.Item{
        .{ .path = "control", .kind = .file, .mode = 0o644, .content = .{ .bytes = control } },
        .{ .path = "md5sums", .kind = .file, .mode = 0o644, .content = .{ .bytes = md5sums.written() } },
    };

    const control_path = try std.fmt.allocPrint(allocator, "{s}/{s}.control.tar.gz", .{ output_dir, package_basename });
    const data_path = try std.fmt.allocPrint(allocator, "{s}/{s}.data.tar.gz", .{ output_dir, package_basename });
    defer {
        Io.Dir.cwd().deleteFile(io, control_path) catch {};
        Io.Dir.cwd().deleteFile(io, data_path) catch {};
    }

    {
        var control_file = try Io.Dir.cwd().createFile(io, control_path, .{ .truncate = true });
        defer control_file.close(io);
        try tar_gz.writeItems(io, control_file, &control_items, 6);
    }
    {
        var data_file = try Io.Dir.cwd().createFile(io, data_path, .{ .truncate = true });
        defer data_file.close(io);
        try tar_gz.writeItems(io, data_file, data_items.items, 6);
    }

    try writeArchive(io, file, control_path, data_path);
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

fn maintainer(config: Config) []const u8 {
    if (config.publisher) |publisher| return publisher;
    var parts = std.mem.splitScalar(u8, config.identifier, '.');
    _ = parts.next();
    return parts.next() orelse config.identifier;
}

fn renderControl(
    allocator: std.mem.Allocator,
    config: Config,
    arch: []const u8,
    installed_size: u64,
    dependencies: []const []const u8,
) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    const package = try toKebabCase(allocator, config.name);
    try writer.print("Package: {s}\n", .{package});
    try writer.print("Version: {s}\n", .{config.version});
    try writer.print("Architecture: {s}\n", .{arch});
    try writer.print("Installed-Size: {d}\n", .{installed_size / 1024});
    try writer.print("Maintainer: {s}\n", .{maintainer(config)});
    if (config.options.section) |section| {
        if (section.len > 0) try writer.print("Section: {s}\n", .{section});
    }
    try writer.print("Priority: {s}\n", .{config.options.priority orelse "optional"});

    if (dependencies.len > 0) {
        try writer.writeAll("Depends: ");
        for (dependencies, 0..) |dependency, index| {
            if (index > 0) try writer.writeAll(", ");
            try writer.writeAll(dependency);
        }
        try writer.writeByte('\n');
    }

    const description = if (config.description) |value| firstLine(value) else "";
    try writer.print("Description: {s}\n", .{if (description.len == 0) "(none)" else description});

    return allocating.toOwnedSlice();
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

fn writeArHeader(writer: *Io.Writer, name: []const u8, size: u64) !void {
    var header: [60]u8 = @splat(' ');

    if (name.len + 1 > 16) return error.NameTooLong;
    @memcpy(header[0..name.len], name);
    header[name.len] = '/';

    writeDecimalField(header[16..28], 0); // mtime
    writeDecimalField(header[28..34], 0); // uid
    writeDecimalField(header[34..40], 0); // gid
    writeOctalField(header[40..48], 0o100644); // mode
    writeDecimalField(header[48..58], size); // size

    header[58] = '`';
    header[59] = '\n';
    try writer.writeAll(&header);
}

fn writeArMemberFile(io: Io, writer: *Io.Writer, name: []const u8, path: []const u8) !void {
    const stat = try Io.Dir.cwd().statFile(io, path, .{});
    try writeArHeader(writer, name, stat.size);

    var file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    _ = try writer.sendFileAll(&reader, .unlimited);

    if (stat.size % 2 == 1) try writer.writeByte('\n');
}

fn writeArMemberBytes(writer: *Io.Writer, name: []const u8, bytes: []const u8) !void {
    try writeArHeader(writer, name, bytes.len);
    try writer.writeAll(bytes);
    if (bytes.len % 2 == 1) try writer.writeByte('\n');
}

/// Writes the final ar archive from the prepared control and data tarballs.
fn writeArchive(
    io: Io,
    file: Io.File,
    control_path: []const u8,
    data_path: []const u8,
) !void {
    var write_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &write_buffer);

    try file_writer.interface.writeAll("!<arch>\n");
    try writeArMemberBytes(&file_writer.interface, "debian-binary", "2.0\n");
    try writeArMemberFile(io, &file_writer.interface, "control.tar.gz", control_path);
    try writeArMemberFile(io, &file_writer.interface, "data.tar.gz", data_path);
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

test "maintainer fallback" {
    const config: Config = .{
        .name = "App",
        .identifier = "com.example.app",
        .version = "1.0.0",
        .executable_name = "app",
        .payload = &.{},
    };

    try std.testing.expectEqualStrings("example", maintainer(config));

    var with_publisher = config;
    with_publisher.publisher = "Acme";
    try std.testing.expectEqualStrings("Acme", maintainer(with_publisher));
}
