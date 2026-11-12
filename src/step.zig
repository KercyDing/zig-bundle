//! Build step that stages resources and produces bundle artifacts.
const builtin = @import("builtin");
const std = @import("std");

const build_manifest = @import("build_manifest.zig");
const manifest = @import("manifest.zig");
const settings = @import("settings.zig");

/// Configuration accepted by `add`; see `settings.Options`.
pub const Options = settings.Options;

/// Build step that produces the configured bundles.
pub const BundleStep = struct {
    /// Underlying build step. Depend on this to run the bundler.
    step: *std.Build.Step,
    /// Normalized configuration owned by the step.
    settings: settings.Settings,
};

/// Registers a bundle step and returns it. Depend on `bundled.step` to run it.
/// Formats and target compatibility are validated before the build starts.
pub fn add(b: *std.Build, options: Options, comptime build_zig: type) *BundleStep {
    const self = b.allocator.create(BundleStep) catch @panic("OOM");
    self.* = .{
        .step = undefined,
        .settings = settings.Settings.init(b, options),
    };

    if (self.settings.nsis) |nsis| {
        switch (nsis.source.kind) {
            .bundled => if (nsisDependencyName()) |name| {
                const lib = b.dependencyFromBuildZig(build_zig, .{});
                if (lib.builder.lazyDependency(name, .{})) |dep| {
                    self.settings.nsis_tool = dep.path(if (builtin.os.tag == .windows) "makensis.exe" else "makensis");
                }
            },
            .system => {},
            .dir => {
                const dir = nsis.source.path.?;
                const tool_name = if (builtin.os.tag == .windows) "makensis.exe" else "makensis";
                const tool = std.fs.path.join(b.allocator, &.{ dir, tool_name }) catch @panic("OOM");
                self.settings.nsis_tool = .{ .cwd_relative = tool };
            },
        }
    }

    if (self.settings.enable_llvm_strip) {
        const llvm_strip = findLlvmStrip(b) orelse std.process.fatal(
            "zig-bundle: enable_llvm_strip requires 'llvm-strip' on PATH; install LLVM tools and retry",
            .{},
        );

        const strip = b.addSystemCommand(&.{ llvm_strip, "--strip-all", "-o" });
        const stripped = strip.addOutputFileArg("stripped-executable");
        strip.addFileArg(options.input.executable.getEmittedBin());

        self.settings.stripped_executable = stripped;
    }

    const prepared = build_manifest.prepare(b, &self.settings) catch |err| {
        std.process.fatal("zig-bundle: failed to prepare bundle manifest: {t}", .{err});
    };
    const json = manifest.render(b.allocator, prepared.manifest) catch @panic("OOM");

    const lib = b.dependencyFromBuildZig(build_zig, .{});
    const runner_module = b.createModule(.{
        .root_source_file = lib.path("src/runner.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    const runner = b.addExecutable(.{
        .name = "zig-bundle-runner",
        .root_module = runner_module,
    });
    const run = b.addRunArtifact(runner);
    run.stdio = .inherit;

    const write_files = b.addWriteFiles();
    run.addFileArg(write_files.add("bundle.json", json));

    for (prepared.paths) |path| {
        if (isDirectory(b, path)) {
            run.addDirectoryArg(path);
        } else {
            run.addFileArg(path);
        }
    }

    const output_dir = run.addOutputDirectoryArg("bundle");
    const install = b.addInstallDirectory(.{
        .source_dir = output_dir,
        .install_dir = .{ .custom = "bundle" },
        .install_subdir = "",
    });

    self.step = &install.step;
    return self;
}

fn isDirectory(b: *std.Build, lazy_path: std.Build.LazyPath) bool {
    const io = b.graph.io;
    const path = switch (lazy_path) {
        .src_path => |sp| sp.owner.root.joinString(b.allocator, sp.sub_path) catch return false,
        .cwd_relative => |p| b.dupe(p),
        .dependency => |dep| dep.dependency.builder.root.joinString(b.allocator, dep.sub_path) catch return false,
        .generated, .relative => return false,
    };
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .directory;
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
