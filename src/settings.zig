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
};

/// Application metadata shared by every output format.
pub const App = struct {
    /// Product name used for file names and metadata.
    name: []const u8,
    /// Reverse-DNS application identifier, e.g. `"com.example.app"`.
    identifier: []const u8,
    /// Semantic version, e.g. `"1.2.3"`.
    version: []const u8,
    /// Package maintainer. Falls back to the identifier.
    publisher: ?[]const u8 = null,
    /// Short description used by package metadata.
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

/// Debian package options.
pub const DebOptions = struct {
    /// Debian package dependencies, e.g. `"libc6 (>= 2.31)"`.
    depends: []const []const u8 = &.{},
    /// Debian section. Defaults to `"utils"`.
    section: ?[]const u8 = "utils",
    /// Debian priority. Defaults to `"optional"`.
    priority: ?[]const u8 = "optional",
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
    setup_exe: ?SetupExeOptions,
    /// Built by `step.add` when `setup_exe` is enabled.
    setup_runtime: ?std.Build.LazyPath = null,

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
            options.formats.setup_exe == null)
        {
            std.process.fatal("zig-bundle: at least one output format must be enabled", .{});
        }

        const target = (options.input.executable.root_module.resolved_target orelse b.graph.host).result;
        const host = b.graph.host.result;
        if (options.formats.zip != null) validateFormat(.zip, host, target);
        if (options.formats.tar_gz != null) validateFormat(.tar_gz, host, target);
        if (options.formats.deb != null) validateFormat(.deb, host, target);
        if (options.formats.setup_exe != null) validateFormat(.setup_exe, host, target);

        const resources = b.allocator.alloc(Resource, options.input.resources.len) catch @panic("OOM");
        for (options.input.resources, resources) |resource, *dest| {
            dest.* = .{
                .source = resource.source,
                .dest = if (resource.dest) |path| b.dupe(path) else null,
            };
        }

        const deb = if (options.formats.deb) |deb_options| blk: {
            const depends = b.allocator.alloc([]const u8, deb_options.depends.len) catch @panic("OOM");
            for (deb_options.depends, depends) |dependency, *dest| {
                dest.* = b.dupe(dependency);
            }
            break :blk DebOptions{
                .depends = depends,
                .section = if (deb_options.section) |section| b.dupe(section) else null,
                .priority = if (deb_options.priority) |priority| b.dupe(priority) else null,
            };
        } else null;

        return .{
            .name = b.dupe(app.name),
            .identifier = b.dupe(app.identifier),
            .version = b.dupe(app.version),
            .publisher = if (app.publisher) |publisher| b.dupe(publisher) else null,
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
            .setup_exe = options.formats.setup_exe,
        };
    }
};

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
    try std.testing.expect(options.formats.setup_exe == null);
}

test "deb options have metadata defaults" {
    const options: DebOptions = .{};

    try std.testing.expectEqualStrings("utils", options.section.?);
    try std.testing.expectEqualStrings("optional", options.priority.?);
}
