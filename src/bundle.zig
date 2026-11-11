const std = @import("std");

const resources = @import("bundle/common/resources.zig");
const settings = @import("settings.zig");
const tar_gz = @import("bundle/common/tar_gz.zig");
const zip = @import("bundle/common/zip.zig");

const Io = std.Io;
const Settings = settings.Settings;

/// Builds every configured bundle and returns the artifact paths.
pub fn project(
    b: *std.Build,
    step: *std.Build.Step,
    config: *const Settings,
) ![]const []const u8 {
    const io = b.graph.io;

    var arena_state = std.heap.ArenaAllocator.init(b.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const target = config.executable.root_module.resolved_target orelse b.graph.host;
    const target_name = try std.fmt.allocPrint(arena, "{s}-{s}", .{
        @tagName(target.result.cpu.arch),
        @tagName(target.result.os.tag),
    });

    var payload: resources.Payload = .{};
    defer payload.deinit(arena);

    const executable_path = try resolveLazyPath(b, step, config.executable_path, arena);
    payload.addFile(arena, executable_path, config.executable.out_filename, true) catch |err| {
        return step.fail("invalid executable name '{s}': {t}", .{ config.executable.out_filename, err });
    };

    for (config.resources) |resource| {
        const source_path = try resolveLazyPath(b, step, resource.source, arena);
        const base_name = std.fs.path.basename(std.mem.trimEnd(u8, source_path, "/\\"));
        const dest = resource.dest orelse base_name;

        const stat = Io.Dir.cwd().statFile(io, source_path, .{}) catch |err| {
            return step.fail("cannot read resource '{s}': {t}", .{ source_path, err });
        };

        switch (stat.kind) {
            .directory => payload.addDirectory(arena, io, source_path, dest) catch |err| {
                return step.fail("cannot add resource '{s}': {t}", .{ source_path, err });
            },
            .file => payload.addFile(arena, source_path, dest, false) catch |err| {
                return step.fail("cannot add resource '{s}': {t}", .{ source_path, err });
            },
            else => return step.fail("resource '{s}' is not a file or directory", .{source_path}),
        }
    }

    payload.sort();
    var index: usize = 1;
    while (index < payload.entries.items.len) : (index += 1) {
        const previous = payload.entries.items[index - 1];
        const current = payload.entries.items[index];
        if (std.mem.eql(u8, previous.archive_path, current.archive_path)) {
            return step.fail("duplicate bundle path '{s}'", .{current.archive_path});
        }
    }

    var artifacts: std.ArrayList([]const u8) = .empty;
    errdefer artifacts.deinit(b.allocator);

    const output_root = b.getInstallPath(.prefix, "bundle");

    if (config.zip) |options| {
        const path = try artifactPath(io, arena, output_root, "zip", "zip", config, target_name);
        var file = try createOutputFile(io, path);
        defer file.close(io);
        zip.write(io, file, payload.entries.items, arena, .{
            .compression = switch (options.compression) {
                .store => .store,
                .deflate => .deflate,
            },
            .level = options.level,
        }) catch |err| {
            return step.fail("failed to create '{s}': {t}", .{ path, err });
        };
        try artifacts.append(b.allocator, b.dupe(path));
    }

    if (config.tar_gz) |options| {
        const path = try artifactPath(io, arena, output_root, "tar.gz", "tar.gz", config, target_name);
        var file = try createOutputFile(io, path);
        defer file.close(io);
        tar_gz.write(io, file, payload.entries.items, .{ .level = options.level }) catch |err| {
            return step.fail("failed to create '{s}': {t}", .{ path, err });
        };
        try artifacts.append(b.allocator, b.dupe(path));
    }

    if (artifacts.items.len == 0) {
        return step.fail("no bundle formats were configured", .{});
    }

    std.debug.print("zig-bundle: finished {d} bundle(s):\n", .{artifacts.items.len});
    for (artifacts.items) |path| {
        const stat = try Io.Dir.cwd().statFile(io, path, .{});
        std.debug.print("  {s} ({d:.2} MiB)\n", .{
            path,
            @as(f64, @floatFromInt(stat.size)) / (1024.0 * 1024.0),
        });
    }

    return artifacts.toOwnedSlice(b.allocator);
}

fn resolveLazyPath(
    b: *std.Build,
    step: *std.Build.Step,
    lazy_path: std.Build.LazyPath,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const path = try lazy_path.getPath4(b, step);
    if (std.fs.path.isAbsolute(path.sub_path)) return allocator.dupe(u8, path.sub_path);
    if (path.root_dir.path) |root| return std.fs.path.join(allocator, &.{ root, path.sub_path });
    return allocator.dupe(u8, path.sub_path);
}

fn artifactPath(
    io: Io,
    allocator: std.mem.Allocator,
    output_root: []const u8,
    directory: []const u8,
    extension: []const u8,
    config: *const Settings,
    target_name: []const u8,
) ![]const u8 {
    const dir = try std.fs.path.join(allocator, &.{ output_root, directory });
    try Io.Dir.cwd().createDirPath(io, dir);

    const file_name = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}.{s}", .{
        config.name,
        config.version,
        target_name,
        extension,
    });
    return std.fs.path.join(allocator, &.{ dir, file_name });
}

fn createOutputFile(io: Io, path: []const u8) !Io.File {
    Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    return Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
}
