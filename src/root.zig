//! Cross-platform application bundling for `build.zig`.
//!
//! ```zig
//! const bundled = @import("bundle").add(b, .{
//!     .app = .{ .name = "MyApp", .identifier = "com.example.myapp", .version = "1.0.0" },
//!     .input = .{ .executable = exe },
//!     .formats = .{ .zip = .{} },
//! });
//! b.step("bundle", "Bundle application").dependOn(bundled.step);
//! ```

const std = @import("std");

const app = @import("bundle/macos/app.zig");
const appimage = @import("bundle/linux/appimage.zig");
const build_manifest = @import("build_manifest.zig");
const bundle = @import("bundle.zig");
const capabilities = @import("capabilities.zig");
const deb = @import("bundle/linux/deb.zig");
const dmg = @import("bundle/macos/dmg.zig");
const manifest = @import("manifest.zig");
const nsis = @import("bundle/windows/nsis.zig");
const resources = @import("bundle/common/resources.zig");
const rpm = @import("bundle/linux/rpm.zig");
const settings = @import("settings.zig");
const step = @import("step.zig");
const tar_gz = @import("bundle/common/tar_gz.zig");
const zip = @import("bundle/common/zip.zig");

/// Registers the bundle build step.
pub fn addWithBuildZig(b: *std.Build, options: Options, comptime build_zig: type) *BundleStep {
    return step.add(b, options, build_zig);
}
/// Returns the default options for one format.
pub fn standardFormats(format: Format) Formats {
    return settings.standardFormats(format);
}
/// Application metadata shared by every output format.
pub const App = settings.App;
/// macOS application bundle options.
pub const AppBundleOptions = settings.AppBundleOptions;
/// AppImage options.
pub const AppImageOptions = settings.AppImageOptions;
/// Additional file installed by a Debian package.
pub const Asset = settings.Asset;
/// Compression algorithm used for ZIP entries.
pub const Compression = settings.Compression;
/// Debian package options.
pub const DebOptions = settings.DebOptions;
/// macOS disk image options.
pub const DmgOptions = settings.DmgOptions;
/// Bundle formats selectable from a build option.
pub const Format = settings.Format;
/// Options for each enabled bundle format.
pub const Formats = settings.Formats;
/// Executable and additional files to bundle.
pub const Input = settings.Input;
/// Debian multi-arch field values.
pub const MultiArch = settings.MultiArch;
/// Configuration accepted by `add`.
pub const Options = settings.Options;
/// File or directory copied into the bundle.
pub const Resource = settings.Resource;
/// RPM package options.
pub const RpmOptions = settings.RpmOptions;
/// Source of the NSIS toolchain.
pub const NsisSource = settings.NsisSource;
/// Windows installer options.
pub const NsisOptions = settings.NsisOptions;
/// tar.gz archive options.
pub const TarGzOptions = settings.TarGzOptions;
/// ZIP archive options.
pub const ZipOptions = settings.ZipOptions;
/// Build step that produces the configured bundles.
pub const BundleStep = step.BundleStep;

test {
    std.testing.refAllDecls(app);
    std.testing.refAllDecls(appimage);
    std.testing.refAllDecls(build_manifest);
    std.testing.refAllDecls(bundle);
    std.testing.refAllDecls(capabilities);
    std.testing.refAllDecls(deb);
    std.testing.refAllDecls(dmg);
    std.testing.refAllDecls(manifest);
    std.testing.refAllDecls(nsis);
    std.testing.refAllDecls(resources);
    std.testing.refAllDecls(rpm);
    std.testing.refAllDecls(settings);
    std.testing.refAllDecls(step);
    std.testing.refAllDecls(tar_gz);
    std.testing.refAllDecls(zip);
}
