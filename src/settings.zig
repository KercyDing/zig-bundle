//! Public configuration types accepted by `bundle.add`.
const std = @import("std");

const capabilities = @import("capabilities.zig");

/// Configuration accepted by `bundle.add`.
pub const Options = struct {
    /// Application metadata shared by every output format.
    app: App,
    /// Executable and additional files to bundle.
    input: Input,
    /// Formats to build. Defaults to a ZIP archive when omitted.
    formats: Formats = .{ .zip = .{} },
    /// Strip the bundled executable with the system `llvm-strip` before
    /// packaging. Applies to every format; requires LLVM tools on `PATH`.
    enable_llvm_strip: bool = false,
};

/// Application metadata shared by every output format.
pub const App = struct {
    /// Product name used for file names and metadata.
    name: []const u8,
    /// Reverse-DNS application identifier, e.g. `"com.example.app"`.
    identifier: []const u8,
    /// Semantic version, e.g. `"1.2.3"`.
    version: []const u8,
    /// Publisher or maintainer. Used as the Debian maintainer when
    /// `deb.maintainer` is unset; that value must be in `Name <email>` form.
    /// Other formats use it as-is.
    publisher: ?[]const u8 = null,
    /// Copyright notice used by package metadata, e.g.
    /// `"Copyright 2026 Example <example@example.com>"`.
    copyright: ?[]const u8 = null,
    /// License identifier, e.g. `"MIT"`.
    license: ?[]const u8 = null,
    /// Semicolon-separated desktop categories, e.g. `"Utility;"`.
    categories: ?[]const u8 = null,
    /// Short description used by package metadata. For Debian, the first line
    /// is the synopsis and the remaining lines form the extended description.
    description: ?[]const u8 = null,
};

/// Application icon sources.
pub const Icons = struct {
    /// PNG sources: files or directories scanned for `*.png`. Dimensions are
    /// read from each PNG header; Linux packages install them by size, and
    /// Windows packs them into an `.ico` when no dedicated ICO is provided.
    png: []const std.Build.LazyPath = &.{},
    /// Optional Windows icon used as-is.
    ico: ?std.Build.LazyPath = null,
};

/// Executable and additional files to bundle.
pub const Input = struct {
    /// Executable produced by the build.
    executable: *std.Build.Step.Compile,
    /// Application icons used by formats that support them.
    icons: Icons = .{},
    /// Additional files or directories copied into the bundle.
    resources: []const Resource = &.{},
};

/// File or directory copied into the bundle.
pub const Resource = struct {
    /// File or directory to copy. Directories are copied recursively.
    source: std.Build.LazyPath,
    /// Destination path relative to the bundle root.
    ///
    /// Defaults to the source base name. For directories, this is the directory
    /// created inside the bundle.
    dest: ?[]const u8 = null,
};

/// Options for each enabled bundle format.
pub const Formats = struct {
    /// ZIP archive.
    zip: ?ZipOptions = null,
    /// Gzip-compressed tar archive.
    tar_gz: ?TarGzOptions = null,
    /// Debian package. Requires a Linux target.
    deb: ?DebOptions = null,
    /// RPM package. Requires a Linux target.
    rpm: ?RpmOptions = null,
    /// Windows installer. Requires a Windows target.
    setup_exe: ?SetupExeOptions = null,
};

/// Supported bundle formats, for command-line selection.
pub const Format = std.meta.FieldEnum(Formats);

/// Compression algorithm used for ZIP entries.
pub const Compression = enum {
    /// Store entries without compression.
    store,
    /// Deflate-compress entries.
    deflate,
};

/// ZIP archive options.
pub const ZipOptions = struct {
    /// Compression algorithm.
    compression: Compression = .deflate,
    /// Deflate level, 1-9. Ignored when `compression` is `.store`.
    level: u4 = 6,
};

/// tar.gz archive options.
pub const TarGzOptions = struct {
    /// Gzip level, 1-9.
    level: u4 = 6,
};

/// Additional file installed by a Debian package.
pub const Asset = struct {
    /// File or directory copied into the package.
    source: std.Build.LazyPath,
    /// Destination relative to the filesystem root. A trailing `/` copies the
    /// source basename into that directory.
    dest: []const u8,
    /// Permission bits for files; directories always use `0o755`.
    mode: u32 = 0o644,
};

/// Debian multi-arch field values.
pub const MultiArch = enum {
    /// Several architectures of the package can be installed simultaneously.
    same,
    /// The package can satisfy dependencies of other architectures.
    foreign,
};

/// Debian package options.
pub const DebOptions = struct {
    /// Debian package dependencies, e.g. `"libc6 (>= 2.31)"`.
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
    /// Debian section. Defaults to `"utils"`.
    section: ?[]const u8 = "utils",
    /// Debian priority. Defaults to `"optional"`.
    priority: ?[]const u8 = "optional",
    /// Project homepage.
    homepage: ?[]const u8 = null,
    /// Multi-arch field. Omitted when null.
    multi_arch: ?MultiArch = null,
    /// Debian revision appended to the version as `<version>-<revision>`.
    revision: ?[]const u8 = null,
    /// Maintainer in `Name <email>` form. Defaults to `app.publisher`.
    maintainer: ?[]const u8 = null,
    /// Copyright notice override for the Debian copyright file.
    copyright: ?[]const u8 = null,
    /// Plain-text upstream changelog installed as
    /// `/usr/share/doc/<package>/changelog.gz`; pre-compressed `.gz` files are
    /// kept as-is. A minimal entry is generated when null.
    changelog: ?std.Build.LazyPath = null,
    /// License file included in the copyright file.
    license_file: ?std.Build.LazyPath = null,
    /// Number of leading license file lines to skip.
    license_file_skip_lines: usize = 0,
    /// Additional files installed by the package.
    assets: []const Asset = &.{},
    /// Configuration files outside `/etc`; files under `/etc` are detected
    /// automatically.
    conf_files: []const []const u8 = &.{},
    /// Directory containing `preinst`, `postinst`, `prerm`, `postrm`, `config`
    /// and `templates`.
    maintainer_scripts: ?std.Build.LazyPath = null,
    /// Debian trigger definition installed as `control.tar.gz` `triggers`.
    triggers: ?std.Build.LazyPath = null,
};

/// RPM package options.
pub const RpmOptions = struct {
    /// RPM release. Defaults to `"1"`.
    release: []const u8 = "1",
    /// RPM epoch.
    epoch: ?u32 = null,
    /// RPM group. Defaults to `"Unspecified"`.
    group: []const u8 = "Unspecified",
    /// Project homepage written to the `URL` tag.
    url: ?[]const u8 = null,
    /// License override; defaults to `app.license`.
    license: ?[]const u8 = null,
    /// Runtime requirements, e.g. `"libc.so.6()(64bit)"` or `"foo >= 1.0"`.
    requires: []const []const u8 = &.{},
    /// Additional provides, in the same syntax as `requires`.
    provides: []const []const u8 = &.{},
    /// Conflicting packages.
    conflicts: []const []const u8 = &.{},
    /// Obsoleted packages.
    obsoletes: []const []const u8 = &.{},
    /// Additional files installed by the package.
    assets: []const Asset = &.{},
    /// Directory containing `preinst`, `postinst`, `prerm` and `postrm`.
    maintainer_scripts: ?std.Build.LazyPath = null,
};

/// Windows installer options.
pub const SetupExeOptions = struct {
    /// Per-user install by default; `all_users` requires elevation.
    install_scope: InstallScope = .current_user,
    /// Default shortcut choices shown on the finish page.
    shortcuts: Shortcuts = .{},
    /// Launch the application after installation.
    launch_app: bool = true,

    pub const InstallScope = enum {
        /// Install under `%LOCALAPPDATA%\Programs`.
        current_user,
        /// Install under `%ProgramFiles%`; requires elevation.
        all_users,
    };

    pub const Shortcuts = struct {
        /// Create a Start Menu shortcut.
        start_menu: bool = true,
        /// Create a desktop shortcut.
        desktop: bool = false,
    };
};

/// Validated, normalized settings owned by a `BundleStep`.
pub const Settings = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    publisher: ?[]const u8,
    /// Copyright notice shared by package metadata.
    copyright: ?[]const u8,
    /// License identifier shared by package metadata.
    license: ?[]const u8,
    /// Semicolon-separated desktop categories.
    categories: ?[]const u8,
    description: ?[]const u8,
    executable: *std.Build.Step.Compile,
    /// Must be obtained via `getEmittedBin()` during configuration; the compile
    /// step only fills in the generated path if it was requested before it ran.
    executable_path: std.Build.LazyPath,
    icons: Icons,
    resources: []const Resource,
    zip: ?ZipOptions,
    tar_gz: ?TarGzOptions,
    deb: ?DebOptions,
    rpm: ?RpmOptions,
    setup_exe: ?SetupExeOptions,
    /// Strip the executable with `llvm-strip` before packaging.
    enable_llvm_strip: bool,
    /// Built by `step.add` when `setup_exe` is enabled.
    setup_runtime: ?std.Build.LazyPath = null,
    /// Produced by `step.add` when `enable_llvm_strip` is set.
    stripped_executable: ?std.Build.LazyPath = null,

    pub fn init(b: *std.Build, options: Options) Settings {
        const app = options.app;

        if (app.name.len == 0) {
            std.process.fatal("zig-bundle: app name must not be empty", .{});
        }
        for (app.name) |c| {
            if (c == 0 or c == '/' or c == '\\' or c == '\n' or c == '\r') {
                std.process.fatal("zig-bundle: app name '{s}' contains an invalid character", .{app.name});
            }
        }
        if (app.identifier.len == 0) {
            std.process.fatal("zig-bundle: app identifier must not be empty", .{});
        }
        for (app.identifier) |c| {
            if (c == 0 or c == '\n' or c == '\r') {
                std.process.fatal("zig-bundle: app identifier '{s}' contains an invalid character", .{app.identifier});
            }
        }
        _ = std.SemanticVersion.parse(app.version) catch {
            std.process.fatal("zig-bundle: invalid app version '{s}'", .{app.version});
        };

        if (options.formats.zip == null and
            options.formats.tar_gz == null and
            options.formats.deb == null and
            options.formats.rpm == null and
            options.formats.setup_exe == null)
        {
            std.process.fatal("zig-bundle: at least one output format must be enabled", .{});
        }

        if (options.formats.deb) |deb| {
            const maintainer = deb.maintainer orelse app.publisher orelse std.process.fatal(
                "zig-bundle: deb requires deb.maintainer or app.publisher in 'Name <email>' form",
                .{},
            );
            if (!isMaintainerAddress(maintainer)) {
                std.process.fatal(
                    "zig-bundle: deb maintainer '{s}' must be in 'Name <email>' form",
                    .{maintainer},
                );
            }
            if (deb.revision) |revision| {
                if (revision.len == 0) {
                    std.process.fatal("zig-bundle: deb revision must not be empty", .{});
                }
                for (revision) |c| {
                    if (!isVersionChar(c)) {
                        std.process.fatal(
                            "zig-bundle: deb revision '{s}' contains an invalid character",
                            .{revision},
                        );
                    }
                }
            }
        }

        const target = (options.input.executable.root_module.resolved_target orelse b.graph.host).result;
        const host = b.graph.host.result;
        if (options.formats.zip != null) validateFormat(.zip, host, target);
        if (options.formats.tar_gz != null) validateFormat(.tar_gz, host, target);
        if (options.formats.deb != null) validateFormat(.deb, host, target);
        if (options.formats.rpm != null) validateFormat(.rpm, host, target);
        if (options.formats.setup_exe != null) validateFormat(.setup_exe, host, target);

        const resources = b.allocator.alloc(Resource, options.input.resources.len) catch @panic("OOM");
        for (options.input.resources, resources) |resource, *dest| {
            dest.* = .{
                .source = resource.source,
                .dest = if (resource.dest) |path| b.dupe(path) else null,
            };
        }

        const rpm = if (options.formats.rpm) |rpm_options| blk: {
            const assets = b.allocator.alloc(Asset, rpm_options.assets.len) catch @panic("OOM");
            for (rpm_options.assets, assets) |asset, *dest| {
                dest.* = .{
                    .source = asset.source,
                    .dest = b.dupe(asset.dest),
                    .mode = asset.mode,
                };
            }
            break :blk RpmOptions{
                .release = b.dupe(rpm_options.release),
                .epoch = rpm_options.epoch,
                .group = b.dupe(rpm_options.group),
                .url = if (rpm_options.url) |url| b.dupe(url) else null,
                .license = if (rpm_options.license) |license| b.dupe(license) else null,
                .requires = dupeStrings(b, rpm_options.requires),
                .provides = dupeStrings(b, rpm_options.provides),
                .conflicts = dupeStrings(b, rpm_options.conflicts),
                .obsoletes = dupeStrings(b, rpm_options.obsoletes),
                .assets = assets,
                .maintainer_scripts = rpm_options.maintainer_scripts,
            };
        } else null;

        const deb = if (options.formats.deb) |deb_options| blk: {
            const assets = b.allocator.alloc(Asset, deb_options.assets.len) catch @panic("OOM");
            for (deb_options.assets, assets) |asset, *dest| {
                dest.* = .{
                    .source = asset.source,
                    .dest = b.dupe(asset.dest),
                    .mode = asset.mode,
                };
            }
            break :blk DebOptions{
                .depends = dupeStrings(b, deb_options.depends),
                .pre_depends = dupeStrings(b, deb_options.pre_depends),
                .recommends = dupeStrings(b, deb_options.recommends),
                .suggests = dupeStrings(b, deb_options.suggests),
                .enhances = dupeStrings(b, deb_options.enhances),
                .conflicts = dupeStrings(b, deb_options.conflicts),
                .breaks = dupeStrings(b, deb_options.breaks),
                .replaces = dupeStrings(b, deb_options.replaces),
                .provides = dupeStrings(b, deb_options.provides),
                .section = if (deb_options.section) |section| b.dupe(section) else null,
                .priority = if (deb_options.priority) |priority| b.dupe(priority) else null,
                .homepage = if (deb_options.homepage) |homepage| b.dupe(homepage) else null,
                .multi_arch = deb_options.multi_arch,
                .revision = if (deb_options.revision) |revision| b.dupe(revision) else null,
                .maintainer = if (deb_options.maintainer) |maintainer| b.dupe(maintainer) else null,
                .copyright = if (deb_options.copyright) |copyright| b.dupe(copyright) else null,
                .changelog = deb_options.changelog,
                .license_file = deb_options.license_file,
                .license_file_skip_lines = deb_options.license_file_skip_lines,
                .assets = assets,
                .conf_files = dupeStrings(b, deb_options.conf_files),
                .maintainer_scripts = deb_options.maintainer_scripts,
                .triggers = deb_options.triggers,
            };
        } else null;

        return .{
            .name = b.dupe(app.name),
            .identifier = b.dupe(app.identifier),
            .version = b.dupe(app.version),
            .publisher = if (app.publisher) |publisher| b.dupe(publisher) else null,
            .copyright = if (app.copyright) |copyright| b.dupe(copyright) else null,
            .license = if (app.license) |license| b.dupe(license) else null,
            .categories = if (app.categories) |categories| b.dupe(categories) else null,
            .description = if (app.description) |description| b.dupe(description) else null,
            .executable = options.input.executable,
            .executable_path = options.input.executable.getEmittedBin(),
            .icons = .{
                .png = blk: {
                    const png = b.allocator.alloc(std.Build.LazyPath, options.input.icons.png.len) catch @panic("OOM");
                    for (options.input.icons.png, png) |source, *dest| dest.* = source;
                    break :blk png;
                },
                .ico = options.input.icons.ico,
            },
            .resources = resources,
            .zip = options.formats.zip,
            .tar_gz = options.formats.tar_gz,
            .deb = deb,
            .rpm = rpm,
            .setup_exe = options.formats.setup_exe,
            .enable_llvm_strip = options.enable_llvm_strip,
        };
    }
};

fn dupeStrings(b: *std.Build, values: []const []const u8) []const []const u8 {
    const result = b.allocator.alloc([]const u8, values.len) catch @panic("OOM");
    for (values, result) |value, *dest| dest.* = b.dupe(value);
    return result;
}

fn isVersionChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '+' or c == '~';
}

fn isMaintainerAddress(value: []const u8) bool {
    const open = std.mem.indexOfScalar(u8, value, '<') orelse return false;
    const close = std.mem.lastIndexOfScalar(u8, value, '>') orelse return false;
    if (close != value.len - 1 or close <= open) return false;

    const name = std.mem.trim(u8, value[0..open], " \t");
    const email = value[open + 1 .. close];
    if (name.len == 0 or email.len == 0) return false;

    const at = std.mem.indexOfScalar(u8, email, '@') orelse return false;
    return at > 0 and at + 1 < email.len and std.mem.indexOfScalar(u8, email[at + 1 ..], '.') != null;
}

fn validateFormat(format: capabilities.Format, host: std.Target, target: std.Target) void {
    capabilities.check(format, host.os.tag, host.cpu.arch, target.os.tag, target.cpu.arch) catch |err| switch (err) {
        error.UnsupportedHost => std.process.fatal(
            "zig-bundle: format '{s}' requires a {s} host (host is {s})",
            .{ @tagName(format), capabilities.hostName(capabilities.spec(format).hosts), @tagName(host.os.tag) },
        ),
        error.UnsupportedTarget => {
            const required = capabilities.spec(format).target_os.?;
            std.process.fatal(
                "zig-bundle: format '{s}' requires a {s} target (target is {s}-{s})",
                .{ @tagName(format), @tagName(required), @tagName(target.cpu.arch), @tagName(target.os.tag) },
            );
        },
        error.ArchMismatch => std.process.fatal(
            "zig-bundle: format '{s}' requires matching host and target architectures (host is {s}, target is {s})",
            .{ @tagName(format), @tagName(host.cpu.arch), @tagName(target.cpu.arch) },
        ),
    };
}

test "options default to a ZIP bundle" {
    const options: Options = .{
        .app = .{ .name = "Default", .identifier = "com.example.default", .version = "1.0.0" },
        .input = .{ .executable = undefined },
    };

    try std.testing.expect(options.formats.zip != null);
    try std.testing.expect(options.formats.tar_gz == null);
    try std.testing.expect(options.formats.deb == null);
    try std.testing.expect(options.formats.rpm == null);
    try std.testing.expect(options.formats.setup_exe == null);
}

test "maintainer address validation" {
    try std.testing.expect(isMaintainerAddress("Example <example@example.com>"));
    try std.testing.expect(!isMaintainerAddress("Example"));
    try std.testing.expect(!isMaintainerAddress("Example <example>"));
    try std.testing.expect(!isMaintainerAddress("<example@example.com>"));
    try std.testing.expect(!isMaintainerAddress("Example <example@example.com> "));
}

test "deb options have metadata defaults" {
    const options: DebOptions = .{};

    try std.testing.expectEqualStrings("utils", options.section.?);
    try std.testing.expectEqualStrings("optional", options.priority.?);
}

test "llvm strip defaults to disabled" {
    const options: Options = .{
        .app = .{ .name = "Default", .identifier = "com.example.default", .version = "1.0.0" },
        .input = .{ .executable = undefined },
    };

    try std.testing.expect(!options.enable_llvm_strip);
}

test "format matches capabilities" {
    inline for (std.meta.fields(Format)) |field| {
        try std.testing.expect(@hasField(capabilities.Format, field.name));
    }
    inline for (std.meta.fields(capabilities.Format)) |field| {
        try std.testing.expect(@hasField(Format, field.name));
    }
}

test "setup exe defaults" {
    const options: SetupExeOptions = .{};

    try std.testing.expectEqual(SetupExeOptions.InstallScope.current_user, options.install_scope);
    try std.testing.expect(options.shortcuts.start_menu);
    try std.testing.expect(!options.shortcuts.desktop);
    try std.testing.expect(options.launch_app);
}
