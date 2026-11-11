const std = @import("std");

pub const Format = enum { zip, tar_gz, deb, setup_exe };

/// Host platform a format can be produced on.
pub const Host = enum { any, macos, linux };

pub const Spec = struct {
    hosts: Host = .any,
    target_os: ?std.Target.Os.Tag = null,
    /// Some formats package host binaries and cannot cross architectures.
    host_arch_matches_target: bool = false,
};

pub fn spec(format: Format) Spec {
    return switch (format) {
        .zip, .tar_gz => .{},
        .deb => .{ .target_os = .linux },
        .setup_exe => .{ .target_os = .windows },
    };
}

pub const CheckError = error{ UnsupportedHost, UnsupportedTarget, ArchMismatch };

pub fn check(
    format: Format,
    host_os: std.Target.Os.Tag,
    host_arch: std.Target.Cpu.Arch,
    target_os: std.Target.Os.Tag,
    target_arch: std.Target.Cpu.Arch,
) CheckError!void {
    return checkSpec(spec(format), host_os, host_arch, target_os, target_arch);
}

pub fn hostName(host: Host) []const u8 {
    return switch (host) {
        .any => "any",
        .macos => "macOS",
        .linux => "Linux",
    };
}

fn checkSpec(
    format_spec: Spec,
    host_os: std.Target.Os.Tag,
    host_arch: std.Target.Cpu.Arch,
    target_os: std.Target.Os.Tag,
    target_arch: std.Target.Cpu.Arch,
) CheckError!void {
    switch (format_spec.hosts) {
        .any => {},
        .macos => if (host_os != .macos) return error.UnsupportedHost,
        .linux => if (host_os != .linux) return error.UnsupportedHost,
    }

    if (format_spec.target_os) |required| {
        if (target_os != required) return error.UnsupportedTarget;
    }

    if (format_spec.host_arch_matches_target and host_arch != target_arch) {
        return error.ArchMismatch;
    }
}

test "deb requires linux target" {
    try check(.deb, .windows, .x86_64, .linux, .x86_64);
    try std.testing.expectError(error.UnsupportedTarget, check(.deb, .windows, .x86_64, .windows, .x86_64));
}

test "setup.exe requires windows target" {
    try check(.setup_exe, .linux, .x86_64, .windows, .x86_64);
    try std.testing.expectError(
        error.UnsupportedTarget,
        check(.setup_exe, .windows, .x86_64, .linux, .x86_64),
    );
}

test "archives are universal" {
    try check(.zip, .windows, .x86_64, .macos, .aarch64);
    try check(.tar_gz, .linux, .aarch64, .windows, .x86);
}

test "host and arch constraints" {
    try std.testing.expectError(
        error.UnsupportedHost,
        checkSpec(.{ .hosts = .macos }, .windows, .x86_64, .macos, .x86_64),
    );
    try std.testing.expectError(
        error.ArchMismatch,
        checkSpec(.{ .host_arch_matches_target = true }, .linux, .x86_64, .linux, .aarch64),
    );
}
