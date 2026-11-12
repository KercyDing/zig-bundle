const builtin = @import("builtin");
const std = @import("std");

const root = @import("src/root.zig");

// This file is imported directly by consumer build scripts via
// `@import("bundle")`, so it re-exports the public configuration API.
/// Registers the bundle build step.
pub const add = root.add;

/// Application metadata shared by every output format.
pub const App = root.App;
/// Build step that produces the configured bundles.
pub const BundleStep = root.BundleStep;
/// Compression algorithm used for ZIP entries.
pub const Compression = root.Compression;
/// Debian package options.
pub const DebOptions = root.DebOptions;
/// Bundle formats selectable from a build option.
pub const Format = root.Format;
/// Options for each enabled bundle format.
pub const Formats = root.Formats;
/// Executable and additional files to bundle.
pub const Input = root.Input;
/// Debian multi-arch field values.
pub const MultiArch = root.MultiArch;
/// Configuration accepted by `add`.
pub const Options = root.Options;
/// File or directory copied into the bundle.
pub const Resource = root.Resource;
/// Windows installer options.
pub const SetupExeOptions = root.SetupExeOptions;
/// tar.gz archive options.
pub const TarGzOptions = root.TarGzOptions;
/// ZIP archive options.
pub const ZipOptions = root.ZipOptions;

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

comptime {
    const minimum = std.SemanticVersion.parse("0.16.0") catch unreachable;

    if (builtin.zig_version.order(minimum) == .lt) {
        @compileError(std.fmt.comptimePrint(
            \\Your version of Zig is too old.
            \\Minimum required version: 0.16.0
        , .{}));
    }
}
