//! Cross-platform application bundling for `build.zig`.
//!
//! ```zig
//! const bundled = @import("bundle").add(b, .{
//!     .app = .{ .name = "MyApp", .identifier = "com.example.myapp", .version = "1.0.0" },
//!     .input = .{ .executable = exe },
//!     .formats = .{ .zip = .{} },
//! });
//! b.step("bundle", "Bundle application").dependOn(&bundled.step);
//! ```

const bundle = @import("bundle.zig");
const capabilities = @import("capabilities.zig");
const deb = @import("bundle/linux/deb.zig");
const resources = @import("bundle/common/resources.zig");
const settings = @import("settings.zig");
const setup_exe = @import("bundle/windows/setup_exe/root.zig");
const step = @import("step.zig");
const tar_gz = @import("bundle/common/tar_gz.zig");
const zip = @import("bundle/common/zip.zig");

/// Application metadata shared by every output format.
pub const App = settings.App;
/// Compression algorithm used for ZIP entries.
pub const Compression = settings.Compression;
/// Debian package options.
pub const DebOptions = settings.DebOptions;
/// Bundle formats selectable from a build option.
pub const Format = settings.Format;
/// Options for each enabled bundle format.
pub const Formats = settings.Formats;
/// Executable and additional files to bundle.
pub const Input = settings.Input;
/// Configuration accepted by `add`.
pub const Options = settings.Options;
/// File or directory copied into the bundle.
pub const Resource = settings.Resource;
/// Windows installer options.
pub const SetupExeOptions = settings.SetupExeOptions;
/// tar.gz archive options.
pub const TarGzOptions = settings.TarGzOptions;
/// ZIP archive options.
pub const ZipOptions = settings.ZipOptions;
/// Registers the bundle build step.
pub const add = step.add;
/// Build step that produces the configured bundles.
pub const BundleStep = step.BundleStep;

test {
    const std = @import("std");

    std.testing.refAllDecls(bundle);
    std.testing.refAllDecls(capabilities);
    std.testing.refAllDecls(deb);
    std.testing.refAllDecls(resources);
    std.testing.refAllDecls(settings);
    std.testing.refAllDecls(setup_exe);
    std.testing.refAllDecls(step);
    std.testing.refAllDecls(tar_gz);
    std.testing.refAllDecls(zip);
}
