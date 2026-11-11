const builtin = @import("builtin");
const std = @import("std");

const root = @import("src/root.zig");

// This file is imported directly by consumer build scripts via
// `@import("bundle")`, so it re-exports the public configuration API.
pub const add = root.add;

pub const App = root.App;
pub const BundleStep = root.BundleStep;
pub const Compression = root.Compression;
pub const DebOptions = root.DebOptions;
pub const Format = root.Format;
pub const Formats = root.Formats;
pub const Input = root.Input;
pub const Options = root.Options;
pub const Resource = root.Resource;
pub const SetupExeOptions = root.SetupExeOptions;
pub const TarGzOptions = root.TarGzOptions;
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
