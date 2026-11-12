# zig-bundle

Cross-platform application bundling for `build.zig`.

Packaging logic is modeled after [tauri-bundler](https://github.com/tauri-apps/tauri/tree/dev/crates/tauri-bundler),
reimplemented in Zig and designed around `std.Build`.

## Requirements

- Zig 0.16.0 or newer.

## Supported formats

| Format | Output |
| --- | --- |
| `zip` | `<prefix>/bundle/zip/<name>-<version>-<arch>-<os>.zip` |
| `tar_gz` | `<prefix>/bundle/tar_gz/<name>-<version>-<arch>-<os>.tar.gz` |
| `deb` | `<prefix>/bundle/deb/<name>_<version>_<deb-arch>.deb` |
| `rpm` | `<prefix>/bundle/rpm/<name>-<version>-<release>.<rpm-arch>.rpm` |
| `setup_exe` | `<prefix>/bundle/setup_exe/<name>_<version>_<arch>-setup.exe` |

Archives contain the executable and configured resources at the archive root.
Timestamps are fixed so repeated builds produce identical archives.
`deb` and `rpm` require a Linux target and are generated natively without external tools.
`setup_exe` requires a Windows target and embeds a Zig-native installer runtime.
Format/host/target compatibility is validated while configuring the bundle, before any build steps run.
`<prefix>` is the Zig install prefix, which defaults to `zig-out` (override with `zig build --prefix <path>`).

## Usage

Add the dependency to `build.zig.zon`:

```bash
zig fetch --save=bundle git+https://github.com/KercyDing/zig-bundle#main
```

Configure the bundle in `build.zig`:

```zig
const std = @import("std");
const bundle = @import("bundle");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const format = b.option(bundle.Format, "format", "Bundle format") orelse .zip;

    const exe = b.addExecutable(.{
        .name = "MyApp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const formats: bundle.Formats = switch (format) {
        .zip => .{ .zip = .{} },
        .tar_gz => .{ .tar_gz = .{} },
        .deb => .{ .deb = .{} },
        .rpm => .{ .rpm = .{} },
        .setup_exe => .{ .setup_exe = .{
            .install_scope = .current_user,
            .shortcuts = .{ .start_menu = true, .desktop = true },
            .launch_app = true,
        } },
    };

    const bundled = bundle.add(b, .{
        .app = .{
            .name = "MyApp",
            .identifier = "com.example.myapp",
            .version = "1.0.0",
            .publisher = "Example <example@example.com>",
            .copyright = "Copyright 2026 Example",
            .license = "MIT",
            .categories = "Utility;",
            .description = "My example application",
        },
        .input = .{
            .executable = exe,
            .icons = .{
                // Files or directories; directories are scanned for *.png.
                .png = &.{ b.path("icons") },
            },
            .resources = &.{
                .{ .source = b.path("assets") },
                .{ .source = b.path("README.md"), .dest = "docs/README.md" },
            },
        },
        .formats = formats,
    });

    b.step("bundle", "Bundle application").dependOn(&bundled.step);
}
```

Select the format with `-Dformat`; the default is `zip`:

```bash
zig build bundle
zig build bundle -Dformat=deb -Dtarget=x86_64-linux-gnu
zig build bundle -Dformat=rpm -Dtarget=x86_64-linux-gnu
zig build bundle -Dformat=setup_exe -Dtarget=x86_64-windows-gnu
```

`formats` defaults to ZIP when omitted, and `bundle.Formats` can enable several formats at once by setting multiple fields:

```zig
.formats = .{
    .zip = .{},
    .tar_gz = .{},
},
```

Debian metadata defaults `maintainer` to `app.publisher`, `copyright` to
`app.copyright`, and generates a Debian-format changelog when none is supplied:

```zig
.deb = .{
    .homepage = "https://example.com",
    // Appended to the package version: 1.0.0-1.
    .revision = "1",
    .recommends = &.{ "xdg-utils" },
    // Included in the copyright file.
    .license_file = b.path("LICENSE"),
    // Installed as changelog.gz.
    .changelog = b.path("debian/changelog"),
    .assets = &.{
        // Installed as myapp.1.gz; man pages are compressed automatically.
        .{ .source = b.path("assets/myapp.1"), .dest = "usr/share/man/man1/" },
        .{ .source = b.path("config.toml"), .dest = "etc/myapp/config.toml" },
    },
},
```

`maintainer` and `copyright` override the app-level values. `depends` accepts
Debian relationship strings; static Zig binaries need no runtime dependencies,
while dynamically linked glibc builds generally need `libc6 (>= ...)`.
`pre_depends`, `suggests`, `enhances`, `conflicts`, `breaks`, `replaces`,
`provides`, and `multi_arch` (`.same` / `.foreign`) are also available.
Assets accept files or directories; a trailing `/` means the destination is a
directory. Files under `etc/` become conffiles automatically, and `conf_files`
adds paths outside `/etc`. `license_file` is appended to the copyright file;
`license_file_skip_lines` skips a license header. Pre-compressed `.gz`
changelogs are installed as-is. Man page assets under `usr/share/man` are
gzip-compressed automatically.

`maintainer_scripts` points to a directory containing `preinst`, `postinst`,
`prerm`, `postrm`, `config`, or `templates`; `triggers` installs a Debian
triggers file in the control archive.

Archives are reproducible and honor `SOURCE_DATE_EPOCH`; without it, entry
timestamps default to 1980-01-01.

RPM metadata mirrors the same payload and asset model:

```zig
.rpm = .{
    .release = "1",
    .epoch = 1,                 // optional
    .url = "https://example.com",
    .requires = &.{ "libc.so.6()(64bit)" },
    .provides = &.{"foo = 1"},
    .conflicts = &.{},
    .obsoletes = &.{},
    .assets = &.{
        .{ .source = b.path("assets/myapp.1"), .dest = "usr/share/man/man1/" },
        .{ .source = b.path("config.toml"), .dest = "etc/myapp/config.toml" },
    },
},
```

Files under `etc/` are marked as RPM config files and get automatic
`config(<name>)` provides/requires. Man pages under `usr/share/man` are
gzip-compressed automatically. Dependencies accept `name`, `name = version`,
and comparison operators. `maintainer_scripts` installs `preinst`, `postinst`,
`prerm`, and `postrm` as RPM scriptlets and adds the `/bin/sh` requirement.

Set top-level `.enable_llvm_strip = true` to strip the bundled executable with
the system `llvm-strip` for every format; the build fails with an installation
hint when the tool is not on `PATH`.

The installer is a GUI-subsystem executable with a native install-location window
(destination edit, Browse, disk space) and TaskDialog prompts. It supports
`--silent`, `--dir <path>`, and `--uninstall`. It installs to
`%LOCALAPPDATA%\Programs\<name>` (current user) or `%ProgramFiles%\<name>`
(all users, requires elevation), registers an uninstall entry, and copies
`uninstall.exe` into the install directory. If the selected folder is not empty,
Setup asks before overwriting existing files. The finish page lets the user
choose Start Menu and desktop shortcuts and whether to launch the application.

A complete example lives in [`examples/`](examples).

## Development

```bash
zig build test
```

With [Only](https://github.com/KercyDing/only):

```bash
only test
only fmt
only clean
only example run
only example zip
only example tar_gz
only example deb
only example rpm
only example setup_exe
```
