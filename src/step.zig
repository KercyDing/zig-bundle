//! Build step that stages resources and produces bundle artifacts.
const builtin = @import("builtin");
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
pub fn add(b: *std.Build, options: Options, comptime build_zig: type) *BundleStep {
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

    if (self.settings.nsis) |nsis| {
        switch (nsis.source.kind) {
            .bundled => if (nsisDependencyName()) |name| {
                const lib = b.dependencyFromBuildZig(build_zig, .{});
                if (lib.builder.lazyDependency(name, .{})) |dep| {
                    if (builtin.os.tag == .windows) {
                        self.settings.nsis_tool = dep.path("makensis.exe").getPath(lib.builder);
                        self.settings.nsis_data_dir = std.fs.path.dirname(self.settings.nsis_tool.?) orelse null;
                    } else {
                        self.settings.nsis_tool = dep.path("makensis").getPath(lib.builder);
                    }
                }
            },
            .system => {},
            .dir => {
                const dir = nsis.source.path.?;
                const tool_name = if (builtin.os.tag == .windows) "makensis.exe" else "makensis";
                self.settings.nsis_tool = std.fs.path.join(b.allocator, &.{ dir, tool_name }) catch @panic("OOM");
                self.settings.nsis_data_dir = b.dupe(dir);
            },
        }
    }

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

fn nsisDependencyName() ?[]const u8 {
    return switch (builtin.os.tag) {
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => "nsis_windows_x64",
            .aarch64 => "nsis_windows_arm64",
            else => null,
        },
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => "nsis_linux_x64",
            .aarch64 => "nsis_linux_arm64",
            else => null,
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "nsis_macos_x64",
            .aarch64 => "nsis_macos_arm64",
            else => null,
        },
        else => null,
    };
}

fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = options;
    const self: *BundleStep = @fieldParentPtr("step", step);
    self.artifacts = try bundle.project(step.owner, step, &self.settings);
}
