//! Bundle orchestration and format dispatch.
const std = @import("std");

const capabilities = @import("capabilities.zig");
const deb = @import("bundle/linux/deb.zig");
const icons = @import("bundle/common/icons.zig");
const output = @import("bundle/common/output.zig");
const rpm = @import("bundle/linux/rpm.zig");
const staging = @import("bundle/common/staging.zig");
const settings = @import("settings.zig");
const setup_exe = @import("bundle/windows/setup_exe/root.zig");
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
    const mtime = tar_gz.parseSourceDateEpoch(b.graph.environ_map.get("SOURCE_DATE_EPOCH"));

    var arena_state = std.heap.ArenaAllocator.init(b.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const target = config.executable.root_module.resolved_target orelse b.graph.host;
    const target_name = try std.fmt.allocPrint(arena, "{s}-{s}", .{
        @tagName(target.result.cpu.arch),
        @tagName(target.result.os.tag),
    });

    const deb_arch: ?[]const u8 = if (config.deb != null)
        deb.archName(target.result.cpu.arch) catch {
            return step.fail("unsupported architecture for deb: {s}", .{@tagName(target.result.cpu.arch)});
        }
    else
        null;

    const rpm_arch: ?[]const u8 = if (config.rpm != null)
        rpm.archName(target.result.cpu.arch) catch {
            return step.fail("unsupported architecture for rpm: {s}", .{@tagName(target.result.cpu.arch)});
        }
    else
        null;

    var staged = try staging.prepare(b, step, config, arena);
    defer staged.payload.deinit(arena);
    const payload = staged.payload;
    const png_icons = staged.png_icons;
    const ico_path = staged.ico_path;

    var artifacts: std.ArrayList([]const u8) = .empty;
    errdefer artifacts.deinit(b.allocator);

    const output_root = b.getInstallPath(.prefix, "bundle");

    if (config.zip) |options| {
        const path = try output.artifactPath(io, arena, output_root, .zip, config, target_name);
        var file = try output.create(io, path);
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
        const path = try output.artifactPath(io, arena, output_root, .tar_gz, config, target_name);
        var file = try output.create(io, path);
        defer file.close(io);
        tar_gz.write(io, file, payload.entries.items, .{ .level = options.level, .mtime = mtime }) catch |err| {
            return step.fail("failed to create '{s}': {t}", .{ path, err });
        };
        try artifacts.append(b.allocator, b.dupe(path));
    }

    if (config.deb) |options| {
        const dir = try output.formatDir(io, arena, output_root, .deb);

        const deb_version = if (options.revision) |revision|
            try std.fmt.allocPrint(arena, "{s}-{s}", .{ config.version, revision })
        else
            config.version;

        const package_basename = try std.fmt.allocPrint(arena, "{s}_{s}_{s}", .{
            config.name,
            deb_version,
            deb_arch.?,
        });
        const file_name = try std.fmt.allocPrint(arena, "{s}{s}", .{
            package_basename,
            capabilities.extension(.deb),
        });
        const path = try std.fs.path.join(arena, &.{ dir, file_name });

        const changelog_path: ?[]const u8 = if (options.changelog) |changelog|
            try staging.resolveLazyPath(b, step, changelog, arena)
        else
            null;

        const license_path: ?[]const u8 = if (options.license_file) |license|
            try staging.resolveLazyPath(b, step, license, arena)
        else
            null;

        const maintainer_scripts_path: ?[]const u8 = if (options.maintainer_scripts) |scripts|
            try staging.resolveLazyPath(b, step, scripts, arena)
        else
            null;

        const triggers_path: ?[]const u8 = if (options.triggers) |triggers|
            try staging.resolveLazyPath(b, step, triggers, arena)
        else
            null;

        const deb_assets = try arena.alloc(deb.Asset, options.assets.len);
        for (options.assets, deb_assets) |asset, *dest| {
            dest.* = .{
                .source_path = try staging.resolveLazyPath(b, step, asset.source, arena),
                .dest = asset.dest,
                .mode = asset.mode,
            };
        }

        var file = try output.create(io, path);
        defer file.close(io);

        deb.bundle(io, file, .{
            .name = config.name,
            .identifier = config.identifier,
            .version = deb_version,
            .maintainer = options.maintainer orelse config.publisher,
            .description = config.description,
            .license = config.license,
            .categories = config.categories,
            .copyright = options.copyright orelse config.copyright,
            .executable_name = config.executable.out_filename,
            .payload = payload.entries.items,
            .icons = png_icons,
            .changelog_path = changelog_path,
            .license_path = license_path,
            .license_skip_lines = options.license_file_skip_lines,
            .assets = deb_assets,
            .maintainer_scripts_path = maintainer_scripts_path,
            .triggers_path = triggers_path,
            .mtime = mtime,
            .options = .{
                .depends = options.depends,
                .pre_depends = options.pre_depends,
                .recommends = options.recommends,
                .suggests = options.suggests,
                .enhances = options.enhances,
                .conflicts = options.conflicts,
                .breaks = options.breaks,
                .replaces = options.replaces,
                .provides = options.provides,
                .section = options.section,
                .priority = options.priority,
                .homepage = options.homepage,
                .multi_arch = if (options.multi_arch) |multi_arch| @tagName(multi_arch) else null,
                .conf_files = options.conf_files,
            },
        }, deb_arch.?, dir, package_basename, arena) catch |err| {
            return step.fail("failed to create '{s}': {t}", .{ path, err });
        };

        try artifacts.append(b.allocator, b.dupe(path));
    }

    if (config.rpm) |options| {
        const dir = try output.formatDir(io, arena, output_root, .rpm);
        const package = try deb.toKebabCase(arena, config.name);
        const package_version = rpm.packageVersion(arena, config.version) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return step.fail("invalid rpm version '{s}'", .{config.version}),
        };
        rpm.validateRelease(options.release) catch {
            return step.fail("invalid rpm release '{s}'", .{options.release});
        };
        const package_basename = try std.fmt.allocPrint(arena, "{s}-{s}-{s}.{s}.rpm", .{
            package,
            package_version,
            options.release,
            rpm_arch.?,
        });
        const path = try std.fs.path.join(arena, &.{ dir, package_basename });

        const rpm_assets = try arena.alloc(rpm.Asset, options.assets.len);
        for (options.assets, rpm_assets) |asset, *dest| {
            dest.* = .{
                .source_path = try staging.resolveLazyPath(b, step, asset.source, arena),
                .dest = asset.dest,
                .mode = asset.mode,
            };
        }

        var file = try output.create(io, path);
        defer file.close(io);

        rpm.bundle(io, file, .{
            .name = config.name,
            .version = package_version,
            .packager = config.publisher,
            .description = config.description,
            .license = config.license,
            .categories = config.categories,
            .arch = rpm_arch.?,
            .executable_name = config.executable.out_filename,
            .payload = payload.entries.items,
            .icons = png_icons,
            .assets = rpm_assets,
            .mtime = mtime,
            .options = .{
                .release = options.release,
                .epoch = options.epoch,
                .group = options.group,
                .url = options.url,
                .license = options.license,
                .requires = options.requires,
                .provides = options.provides,
                .conflicts = options.conflicts,
                .obsoletes = options.obsoletes,
            },
        }, arena) catch |err| {
            return step.fail("failed to create '{s}': {t}", .{ path, err });
        };

        try artifacts.append(b.allocator, b.dupe(path));
    }

    if (config.setup_exe) |options| {
        const runtime = config.setup_runtime orelse return step.fail("setup runtime was not built", .{});
        const runtime_path = try staging.resolveLazyPath(b, step, runtime, arena);

        const dir = try output.formatDir(io, arena, output_root, .setup_exe);

        const file_name = try std.fmt.allocPrint(arena, "{s}_{s}_{s}-setup{s}", .{
            config.name,
            config.version,
            @tagName(target.result.cpu.arch),
            capabilities.extension(.setup_exe),
        });
        const path = try std.fs.path.join(arena, &.{ dir, file_name });

        var file = try output.create(io, path);
        defer file.close(io);

        var setup_icon_path: ?[]const u8 = ico_path;
        var generated_icon_path: ?[]const u8 = null;
        const icon_name: ?[]const u8 = if (ico_path != null or png_icons.len > 0)
            try std.fmt.allocPrint(arena, "{s}.ico", .{config.name})
        else
            null;

        if (setup_icon_path == null and png_icons.len > 0) {
            const generated = try std.fmt.allocPrint(arena, "{s}.generated.ico", .{config.name});
            setup_icon_path = try std.fs.path.join(arena, &.{ dir, generated });
            generated_icon_path = setup_icon_path;
            {
                var icon_file = try Io.Dir.cwd().createFile(io, setup_icon_path.?, .{ .truncate = true });
                defer icon_file.close(io);
                icons.writeIco(io, icon_file, png_icons, arena) catch |err| {
                    return step.fail("cannot build Windows icon: {t}", .{err});
                };
            }
        }
        defer if (generated_icon_path) |generated_path| Io.Dir.cwd().deleteFile(io, generated_path) catch {};

        setup_exe.bundle(io, file, .{
            .name = config.name,
            .identifier = config.identifier,
            .version = config.version,
            .publisher = config.publisher orelse "",
            .scope = switch (options.install_scope) {
                .current_user => .current_user,
                .all_users => .all_users,
            },
            .executable_name = config.executable.out_filename,
            .start_menu = options.shortcuts.start_menu,
            .desktop = options.shortcuts.desktop,
            .launch = options.launch_app,
            .payload = payload.entries.items,
            .runtime_path = runtime_path,
            .icon_path = setup_icon_path,
            .icon_name = icon_name,
        }, arena) catch |err| {
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
