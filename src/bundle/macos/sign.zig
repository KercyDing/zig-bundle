//! Code signing applied after a macOS bundle has been assembled.
//!
//! Zig links the executable with an ad-hoc signature that covers only the
//! Mach-O. Once `Contents/Info.plist` and `Contents/Resources` are added the
//! signature no longer describes the bundle, so macOS treats it as damaged and
//! TCC refuses to bind Screen Recording or Accessibility grants to it.

const builtin = @import("builtin");
const std = @import("std");

const Io = std.Io;

pub const Config = struct {
    /// `codesign` identity; "-" signs ad-hoc.
    identity: []const u8 = "-",
    /// Pass `--options runtime`. Required for notarization.
    runtime: bool = false,
    /// Pass `--timestamp`. Only Apple-issued identities support it.
    timestamp: bool = false,
    /// Entitlements property list applied to the bundle.
    entitlements: ?[]const u8 = null,
};

// Declared, so callers see the same error set on every host: platforms without
// `codesign` return early, which would otherwise erase these errors and break
// switches on `error.Codesign*` in cross-compiled builds.
pub const Error = error{ CodesignNotFound, CodesignFailed, OutOfMemory };

/// Signs `app_dir` and verifies the result. No-op without a macOS host.
pub fn apply(io: Io, app_dir: []const u8, config: Config, allocator: std.mem.Allocator) Error!void {
    if (builtin.os.tag != .macos) {
        std.debug.print("zig-bundle: skipping code signing for '{s}'; codesign requires a macOS host\n", .{app_dir});
        return;
    }

    var argv: std.ArrayList([]const u8) = .empty;
    argv.appendSlice(allocator, &.{ "codesign", "--force", "--sign", config.identity }) catch return error.OutOfMemory;
    if (config.runtime) argv.appendSlice(allocator, &.{ "--options", "runtime" }) catch return error.OutOfMemory;
    if (config.timestamp) argv.append(allocator, "--timestamp") catch return error.OutOfMemory;
    if (config.entitlements) |path| argv.appendSlice(allocator, &.{ "--entitlements", path }) catch return error.OutOfMemory;
    argv.append(allocator, app_dir) catch return error.OutOfMemory;
    try run(io, argv.items, "codesign", allocator);

    try run(io, &.{ "codesign", "--verify", "--strict", app_dir }, "codesign --verify", allocator);
}

/// Runs `codesign` with its output captured: a child that inherits this
/// process's stdio breaks the test runner's protocol when bundles are signed
/// from a test.
fn run(io: Io, argv: []const []const u8, what: []const u8, allocator: std.mem.Allocator) Error!void {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .pipe,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.CodesignNotFound,
        else => return error.CodesignFailed,
    };

    var buffer: [4096]u8 = undefined;
    var reader = child.stderr.?.reader(io, &buffer);
    const stderr = reader.interface.allocRemaining(allocator, .limited(64 * 1024)) catch return error.CodesignFailed;
    defer allocator.free(stderr);

    const term = child.wait(io) catch return error.CodesignFailed;
    switch (term) {
        .exited => |code| if (code != 0) {
            std.debug.print("zig-bundle: {s} failed ({d}):", .{ what, code });
            for (argv) |arg| std.debug.print(" {s}", .{arg});
            std.debug.print("\n", .{});
            if (stderr.len > 0) std.debug.print("{s}\n", .{std.mem.trimEnd(u8, stderr, "\n")});
            return error.CodesignFailed;
        },
        else => return error.CodesignFailed,
    }
}
