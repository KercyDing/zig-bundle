//! Cross-platform application bundling for `build.zig`.
//!
//! ```zig
//! const bundled = @import("zig_bundle").add(b, .{
//!     .app = .{ .name = "MyApp", .identifier = "com.example.myapp", .version = "1.0.0" },
//!     .input = .{ .executable = exe },
//!     .formats = .{ .zip = .{} },
//! });
//! b.step("package", "Package application").dependOn(&bundled.step);
//! ```

const bundle = @import("bundle.zig");
const resources = @import("bundle/common/resources.zig");
const settings = @import("settings.zig");
const step = @import("step.zig");
const tar_gz = @import("bundle/common/tar_gz.zig");
const zip = @import("bundle/common/zip.zig");

pub const App = settings.App;
pub const Compression = settings.Compression;
pub const Formats = settings.Formats;
pub const Input = settings.Input;
pub const Options = settings.Options;
pub const Resource = settings.Resource;
pub const TarGzOptions = settings.TarGzOptions;
pub const ZipOptions = settings.ZipOptions;
pub const add = step.add;
pub const BundleStep = step.BundleStep;

test {
    const std = @import("std");

    std.testing.refAllDecls(bundle);
    std.testing.refAllDecls(resources);
    std.testing.refAllDecls(settings);
    std.testing.refAllDecls(step);
    std.testing.refAllDecls(tar_gz);
    std.testing.refAllDecls(zip);
}
