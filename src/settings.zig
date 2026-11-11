const std = @import("std");

/// Configuration accepted by `bundle.add`.
pub const Options = struct {
    app: App,
    input: Input,
    formats: Formats,
};

/// Application metadata shared by every output format.
pub const App = struct {
    /// Product name used for file names and metadata.
    name: []const u8,
    /// Reverse-DNS application identifier.
    identifier: []const u8,
    /// Semantic version, e.g. `"1.2.3"`.
    version: []const u8,
};

pub const Input = struct {
    /// Executable produced by the build.
    executable: *std.Build.Step.Compile,
    /// Additional files or directories copied into the bundle.
    resources: []const Resource = &.{},
};

pub const Resource = struct {
    /// File or directory to copy. Directories are copied recursively.
    source: std.Build.LazyPath,
    /// Destination path relative to the bundle root.
    ///
    /// Defaults to the source base name. For directories, this is the directory
    /// created inside the bundle.
    dest: ?[]const u8 = null,
};

pub const Formats = struct {
    zip: ?ZipOptions = null,
    tar_gz: ?TarGzOptions = null,
};

pub const Compression = enum { store, deflate };

pub const ZipOptions = struct {
    compression: Compression = .deflate,
    /// Deflate level, 1-9. Ignored when `compression` is `.store`.
    level: u4 = 6,
};

pub const TarGzOptions = struct {
    /// Gzip level, 1-9.
    level: u4 = 6,
};

/// Validated, normalized settings owned by a `BundleStep`.
pub const Settings = struct {
    name: []const u8,
    identifier: []const u8,
    version: []const u8,
    executable: *std.Build.Step.Compile,
    /// Must be obtained via `getEmittedBin()` during configuration; the compile
    /// step only fills in the generated path if it was requested before it ran.
    executable_path: std.Build.LazyPath,
    resources: []const Resource,
    zip: ?ZipOptions,
    tar_gz: ?TarGzOptions,

    pub fn init(b: *std.Build, options: Options) Settings {
        const app = options.app;

        if (app.name.len == 0) {
            std.process.fatal("zig-bundle: app name must not be empty", .{});
        }
        for (app.name) |c| {
            if (c == 0 or c == '/' or c == '\\') {
                std.process.fatal("zig-bundle: app name '{s}' must not contain path separators", .{app.name});
            }
        }
        if (app.identifier.len == 0) {
            std.process.fatal("zig-bundle: app identifier must not be empty", .{});
        }
        _ = std.SemanticVersion.parse(app.version) catch {
            std.process.fatal("zig-bundle: invalid app version '{s}'", .{app.version});
        };

        if (options.formats.zip == null and options.formats.tar_gz == null) {
            std.process.fatal("zig-bundle: at least one output format must be enabled", .{});
        }

        const resources = b.allocator.alloc(Resource, options.input.resources.len) catch @panic("OOM");
        for (options.input.resources, resources) |resource, *dest| {
            dest.* = .{
                .source = resource.source,
                .dest = if (resource.dest) |path| b.dupe(path) else null,
            };
        }

        return .{
            .name = b.dupe(app.name),
            .identifier = b.dupe(app.identifier),
            .version = b.dupe(app.version),
            .executable = options.input.executable,
            .executable_path = options.input.executable.getEmittedBin(),
            .resources = resources,
            .zip = options.formats.zip,
            .tar_gz = options.formats.tar_gz,
        };
    }
};
