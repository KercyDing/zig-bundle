const std = @import("std");

const bundle = @import("bundle.zig");
const settings = @import("settings.zig");

pub const Options = settings.Options;

/// Build step that produces the configured bundles.
pub const BundleStep = struct {
    step: std.Build.Step,
    settings: settings.Settings,
    artifacts: []const []const u8 = &.{},

    /// Artifact paths produced by the last run.
    pub fn getArtifacts(self: *const BundleStep) []const []const u8 {
        return self.artifacts;
    }
};

/// Registers a bundle step and returns it. Depend on `bundled.step` to run it.
pub fn add(b: *std.Build, options: Options) *BundleStep {
    const self = b.allocator.create(BundleStep) catch @panic("OOM");
    self.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "bundle",
            .owner = b,
            .makeFn = make,
        }),
        .settings = settings.Settings.init(b, options),
    };

    self.step.dependOn(&options.input.executable.step);
    for (self.settings.resources) |resource| {
        resource.source.addStepDependencies(&self.step);
    }
    if (self.settings.icon) |icon| {
        icon.addStepDependencies(&self.step);
    }

    if (self.settings.setup_exe != null) {
        const target = options.input.executable.root_module.resolved_target orelse b.graph.host;
        const write_files = b.addWriteFiles();
        const runtime_source = write_files.add("setup_runtime.zig", @embedFile("windows/setup_runtime.zig"));
        _ = write_files.add("gui.zig", @embedFile("windows/gui.zig"));
        const runtime_manifest = write_files.add("setup.manifest", @embedFile("windows/setup.manifest"));
        const runtime = b.addExecutable(.{
            .name = "zig-bundle-setup",
            .root_module = b.createModule(.{
                .root_source_file = runtime_source,
                .target = target,
                .optimize = .ReleaseSmall,
                .strip = true,
            }),
            .win32_manifest = runtime_manifest,
        });
        runtime.subsystem = .windows;
        runtime.root_module.linkSystemLibrary("comctl32", .{});
        runtime.root_module.linkSystemLibrary("gdi32", .{});
        self.step.dependOn(&runtime.step);
        self.settings.setup_runtime = runtime.getEmittedBin();
    }

    return self;
}

fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = options;
    const self: *BundleStep = @fieldParentPtr("step", step);
    self.artifacts = try bundle.project(step.owner, step, &self.settings);
}
