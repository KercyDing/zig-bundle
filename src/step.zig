//! Build step that stages resources and produces bundle artifacts.
const std = @import("std");

const bundle = @import("bundle.zig");
const settings = @import("settings.zig");

/// Configuration accepted by `add`; see `settings.Options`.
pub const Options = settings.Options;

/// Build step that produces the configured bundles.
pub const BundleStep = struct {
    /// Underlying build step. Depend on this to run the bundler.
    step: std.Build.Step,
    /// Normalized configuration owned by the step.
    settings: settings.Settings,
    /// Artifact paths produced by the last run.
    artifacts: []const []const u8 = &.{},

    /// Artifact paths produced by the last run.
    pub fn getArtifacts(self: *const BundleStep) []const []const u8 {
        return self.artifacts;
    }
};

/// Registers a bundle step and returns it. Depend on `bundled.step` to run it.
/// Formats and target compatibility are validated before the build starts.
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
    for (self.settings.icons.png) |icon| {
        icon.addStepDependencies(&self.step);
    }
    if (self.settings.icons.ico) |icon| {
        icon.addStepDependencies(&self.step);
    }
    if (self.settings.rpm) |rpm| {
        for (rpm.assets) |asset| asset.source.addStepDependencies(&self.step);
        if (rpm.maintainer_scripts) |scripts| scripts.addStepDependencies(&self.step);
    }
    if (self.settings.deb) |deb| {
        if (deb.changelog) |changelog| changelog.addStepDependencies(&self.step);
        if (deb.license_file) |license| license.addStepDependencies(&self.step);
        if (deb.maintainer_scripts) |scripts| scripts.addStepDependencies(&self.step);
        if (deb.triggers) |triggers| triggers.addStepDependencies(&self.step);
        for (deb.assets) |asset| asset.source.addStepDependencies(&self.step);
    }
    if (self.settings.enable_llvm_strip) {
        const llvm_strip = findLlvmStrip(b) orelse std.process.fatal(
            "zig-bundle: enable_llvm_strip requires 'llvm-strip' on PATH; install LLVM tools and retry",
            .{},
        );

        const strip = b.addSystemCommand(&.{ llvm_strip, "--strip-all", "-o" });
        const stripped = strip.addOutputFileArg("stripped-executable");
        strip.addFileArg(options.input.executable.getEmittedBin());

        self.step.dependOn(&strip.step);
        self.settings.stripped_executable = stripped;
    }

    return self;
}

/// Finds `llvm-strip` without resolving symlinks: distributions commonly
/// symlink it to `llvm-objcopy`, which selects strip behaviour from `argv[0]`.
fn findLlvmStrip(b: *std.Build) ?[]const u8 {
    const io = b.graph.io;
    const path = b.graph.environ_map.get("PATH") orelse return null;

    var dirs = std.mem.tokenizeScalar(u8, path, std.fs.path.delimiter);
    while (dirs.next()) |dir| {
        if (dir.len == 0) continue;

        for ([_][]const u8{ "llvm-strip", "llvm-strip.exe" }) |name| {
            const candidate = b.pathJoin(&.{ dir, name });
            std.Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch continue;
            return candidate;
        }
    }

    return null;
}

fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = options;
    const self: *BundleStep = @fieldParentPtr("step", step);
    self.artifacts = try bundle.project(step.owner, step, &self.settings);
}
