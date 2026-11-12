//! Converts build-time settings into the runner manifest.
const std = @import("std");

const manifest = @import("manifest.zig");
const settings = @import("settings.zig");
const tar_gz = @import("bundle/common/tar_gz.zig");

pub const Prepared = struct {
    manifest: manifest.Manifest,
    paths: []const std.Build.LazyPath,
};

pub fn prepare(b: *std.Build, config: *const settings.Settings) !Prepared {
    var paths: std.ArrayList(std.Build.LazyPath) = .empty;
    errdefer paths.deinit(b.allocator);

    const target = (config.executable.root_module.resolved_target orelse b.graph.host).result;
    const target_name = try std.fmt.allocPrint(b.allocator, "{s}-{s}", .{
        @tagName(target.cpu.arch),
        @tagName(target.os.tag),
    });

    const deb_arch: ?[]const u8 = if (config.deb != null)
        debArch(target.cpu.arch)
    else
        null;
    const rpm_arch: ?[]const u8 = if (config.rpm != null)
        rpmArch(target.cpu.arch)
    else
        null;
    const appimage_arch: ?[]const u8 = if (config.appimage != null)
        appimageArch(target.cpu.arch)
    else
        null;

    const executable_path = config.stripped_executable orelse config.executable_path;
    const executable = try addPath(b.allocator, &paths, executable_path);

    const resources = try b.allocator.alloc(manifest.Resource, config.resources.len);
    for (config.resources, resources) |resource, *dest| {
        dest.* = .{
            .path = try addPath(b.allocator, &paths, resource.source),
            .dest = resource.dest,
        };
    }

    const png_icons = try b.allocator.alloc(usize, config.icons.png.len);
    for (config.icons.png, png_icons) |icon, *dest| {
        dest.* = try addPath(b.allocator, &paths, icon);
    }

    const ico: ?usize = if (config.icons.ico) |icon| try addPath(b.allocator, &paths, icon) else null;
    const icns: ?usize = if ((config.app_bundle != null or config.dmg != null) and config.icons.icns != null)
        try addPath(b.allocator, &paths, config.icons.icns.?)
    else
        null;

    const zip = if (config.zip) |options| manifest.Zip{
        .compression = switch (options.compression) {
            .store => .store,
            .deflate => .deflate,
        },
        .level = options.level,
    } else null;

    const tar_gz_options = if (config.tar_gz) |options| manifest.TarGz{ .level = options.level } else null;

    const deb = if (config.deb) |options| blk: {
        const assets = try b.allocator.alloc(manifest.Asset, options.assets.len);
        for (options.assets, assets) |asset, *dest| {
            dest.* = .{
                .path = try addPath(b.allocator, &paths, asset.source),
                .dest = asset.dest,
                .mode = asset.mode,
            };
        }

        break :blk manifest.Deb{
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
            .multi_arch = if (options.multi_arch) |value| @tagName(value) else null,
            .revision = options.revision,
            .maintainer = options.maintainer,
            .copyright = options.copyright,
            .changelog = if (options.changelog) |path| try addPath(b.allocator, &paths, path) else null,
            .license_file = if (options.license_file) |path| try addPath(b.allocator, &paths, path) else null,
            .license_file_skip_lines = options.license_file_skip_lines,
            .assets = assets,
            .conf_files = options.conf_files,
            .maintainer_scripts = if (options.maintainer_scripts) |path| try addPath(b.allocator, &paths, path) else null,
            .triggers = if (options.triggers) |path| try addPath(b.allocator, &paths, path) else null,
        };
    } else null;

    const rpm = if (config.rpm) |options| blk: {
        const assets = try b.allocator.alloc(manifest.Asset, options.assets.len);
        for (options.assets, assets) |asset, *dest| {
            dest.* = .{
                .path = try addPath(b.allocator, &paths, asset.source),
                .dest = asset.dest,
                .mode = asset.mode,
            };
        }

        break :blk manifest.Rpm{
            .release = options.release,
            .epoch = options.epoch,
            .group = options.group,
            .url = options.url,
            .license = options.license,
            .requires = options.requires,
            .provides = options.provides,
            .conflicts = options.conflicts,
            .obsoletes = options.obsoletes,
            .assets = assets,
            .maintainer_scripts = if (options.maintainer_scripts) |path| try addPath(b.allocator, &paths, path) else null,
        };
    } else null;

    const appimage = if (config.appimage) |options| manifest.AppImage{
        .appimagetool = options.appimagetool,
    } else null;

    const app = if (config.app_bundle) |options| blk: {
        const entries = try b.allocator.alloc(manifest.PlistEntry, options.plist_entries.len);
        for (options.plist_entries, entries) |entry, *dest| {
            dest.* = .{
                .key = entry.key,
                .value = switch (entry.value) {
                    .string => |value| .{ .string = value },
                    .boolean => |value| .{ .boolean = value },
                    .integer => |value| .{ .integer = value },
                },
            };
        }
        break :blk manifest.App{ .plist_entries = entries };
    } else null;

    const dmg = if (config.dmg) |options| manifest.Dmg{
        .volume_name = options.volume_name,
        .compression = switch (options.compression) {
            .udzo => .udzo,
            .udbz => .udbz,
            .ulfo => .ulfo,
        },
        .applications_link = options.applications_link,
        .layout = if (options.layout) |layout| manifest.DmgLayout{
            .background = if (layout.background) |path| try addPath(b.allocator, &paths, path) else null,
            .window_width = layout.window_size.width,
            .window_height = layout.window_size.height,
            .icon_size = layout.icon_size,
            .app_x = layout.app_position.x,
            .app_y = layout.app_position.y,
            .applications_x = layout.applications_position.x,
            .applications_y = layout.applications_position.y,
        } else null,
    } else null;

    const nsis = if (config.nsis) |options| manifest.Nsis{
        .install_scope = switch (options.install_scope) {
            .current_user => .current_user,
            .all_users => .all_users,
        },
        .start_menu = options.shortcuts.start_menu,
        .desktop = options.shortcuts.desktop,
        .launch_app = options.launch_app,
        .makensis = if (config.nsis_tool) |tool| try addPath(b.allocator, &paths, tool) else null,
    } else null;

    return .{
        .manifest = .{
            .name = config.name,
            .identifier = config.identifier,
            .version = config.version,
            .publisher = config.publisher,
            .copyright = config.copyright,
            .license = config.license,
            .categories = config.categories,
            .description = config.description,
            .executable_name = config.executable.out_filename,
            .executable = executable,
            .path_count = paths.items.len,
            .resources = resources,
            .png_icons = png_icons,
            .ico = ico,
            .icns = icns,
            .target_name = target_name,
            .target_arch = @tagName(target.cpu.arch),
            .deb_arch = deb_arch,
            .rpm_arch = rpm_arch,
            .appimage_arch = appimage_arch,
            .mtime = tar_gz.parseSourceDateEpoch(b.graph.environ_map.get("SOURCE_DATE_EPOCH")),
            .formats = .{
                .zip = zip,
                .tar_gz = tar_gz_options,
                .deb = deb,
                .rpm = rpm,
                .appimage = appimage,
                .nsis = nsis,
                .app = app,
                .dmg = dmg,
            },
        },
        .paths = try paths.toOwnedSlice(b.allocator),
    };
}

fn addPath(allocator: std.mem.Allocator, paths: *std.ArrayList(std.Build.LazyPath), path: std.Build.LazyPath) !usize {
    try paths.append(allocator, path);
    return paths.items.len - 1;
}

fn debArch(arch: std.Target.Cpu.Arch) []const u8 {
    return @import("bundle/linux/deb.zig").archName(arch) catch std.process.fatal(
        "zig-bundle: unsupported architecture for deb: {s}",
        .{@tagName(arch)},
    );
}

fn rpmArch(arch: std.Target.Cpu.Arch) []const u8 {
    return @import("bundle/linux/rpm.zig").archName(arch) catch std.process.fatal(
        "zig-bundle: unsupported architecture for rpm: {s}",
        .{@tagName(arch)},
    );
}

fn appimageArch(arch: std.Target.Cpu.Arch) []const u8 {
    return @import("bundle/linux/appimage.zig").archName(arch) catch std.process.fatal(
        "zig-bundle: unsupported architecture for appimage: {s}",
        .{@tagName(arch)},
    );
}
