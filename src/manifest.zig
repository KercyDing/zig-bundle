//! Configuration passed from `build.zig` to the bundler runner.
const std = @import("std");

pub const Resource = struct {
    path: usize,
    /// Destination relative to the bundle root; defaults to the source basename.
    dest: ?[]const u8 = null,
};

pub const Asset = struct {
    path: usize,
    dest: []const u8,
    mode: u32 = 0o644,
};

pub const Compression = enum { store, deflate };

pub const Zip = struct {
    compression: Compression = .deflate,
    level: u4 = 6,
};

pub const TarGz = struct {
    level: u4 = 6,
};

pub const Deb = struct {
    depends: []const []const u8 = &.{},
    pre_depends: []const []const u8 = &.{},
    recommends: []const []const u8 = &.{},
    suggests: []const []const u8 = &.{},
    enhances: []const []const u8 = &.{},
    conflicts: []const []const u8 = &.{},
    breaks: []const []const u8 = &.{},
    replaces: []const []const u8 = &.{},
    provides: []const []const u8 = &.{},
    section: ?[]const u8 = "utils",
    priority: ?[]const u8 = "optional",
    homepage: ?[]const u8 = null,
    multi_arch: ?[]const u8 = null,
    revision: ?[]const u8 = null,
    maintainer: ?[]const u8 = null,
    copyright: ?[]const u8 = null,
    changelog: ?usize = null,
    license_file: ?usize = null,
    license_file_skip_lines: usize = 0,
    assets: []const Asset = &.{},
    conf_files: []const []const u8 = &.{},
    maintainer_scripts: ?usize = null,
    triggers: ?usize = null,
};

pub const Rpm = struct {
    release: []const u8 = "1",
    epoch: ?u32 = null,
    group: []const u8 = "Unspecified",
    url: ?[]const u8 = null,
    license: ?[]const u8 = null,
    requires: []const []const u8 = &.{},
    provides: []const []const u8 = &.{},
    conflicts: []const []const u8 = &.{},
    obsoletes: []const []const u8 = &.{},
    assets: []const Asset = &.{},
    maintainer_scripts: ?usize = null,
};

pub const AppImage = struct {
    appimagetool: ?[]const u8 = null,
};

pub const Nsis = struct {
    install_scope: enum { current_user, all_users } = .current_user,
    start_menu: bool = true,
    desktop: bool = false,
    launch_app: bool = true,
    makensis: ?usize = null,
};

pub const Formats = struct {
    zip: ?Zip = null,
    tar_gz: ?TarGz = null,
    deb: ?Deb = null,
    rpm: ?Rpm = null,
    appimage: ?AppImage = null,
    nsis: ?Nsis = null,
    app: bool = false,
    dmg: bool = false,
};

pub const Manifest = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    publisher: ?[]const u8 = null,
    copyright: ?[]const u8 = null,
    license: ?[]const u8 = null,
    categories: ?[]const u8 = null,
    description: ?[]const u8 = null,
    executable_name: []const u8,
    executable: usize,
    path_count: usize,
    resources: []const Resource = &.{},
    png_icons: []const usize = &.{},
    ico: ?usize = null,
    icns: ?usize = null,
    target_name: []const u8,
    target_arch: []const u8,
    deb_arch: ?[]const u8 = null,
    rpm_arch: ?[]const u8 = null,
    appimage_arch: ?[]const u8 = null,
    mtime: u64,
    formats: Formats,
};

/// Paths are passed separately to the runner in manifest order.
pub fn render(allocator: std.mem.Allocator, value: Manifest) ![]u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})});
}

pub fn parse(allocator: std.mem.Allocator, json: []const u8) !std.json.Parsed(Manifest) {
    return std.json.parseFromSlice(Manifest, allocator, json, .{});
}
