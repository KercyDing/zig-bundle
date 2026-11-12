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
| `appimage` | `<prefix>/bundle/appimage/<name>-<version>-<arch>.AppImage` |
| `nsis` | `<prefix>/bundle/nsis/<name>_<version>_<arch>-setup.exe` |
| `app` | `<prefix>/bundle/app/<name>.app` |
| `dmg` | `<prefix>/bundle/dmg/<name>_<version>_<arch>.dmg` |

Archives contain the executable and configured resources at the archive root.
Timestamps are fixed so repeated builds produce identical archives.
`deb` and `rpm` require a Linux target and are generated natively without external tools.
`appimage` requires a Linux host and target and invokes `appimagetool`.
`nsis` requires a Windows target and invokes NSIS `makensis`; the bundled toolchain is used by default.
`app` requires a macOS target and writes a native `.app` directory; it can be produced from any host.
`dmg` requires a macOS host and target and invokes `hdiutil`.
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
        .appimage => .{ .appimage = .{} },
        .nsis => .{ .nsis = .{
            .install_scope = .current_user,
            .shortcuts = .{ .start_menu = true, .desktop = true },
            .launch_app = true,
        } },
        .app => .{ .app = .{} },
        .dmg => .{ .dmg = .{} },
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
zig build bundle -Dformat=appimage -Dtarget=x86_64-linux-gnu
zig build bundle -Dformat=nsis -Dtarget=x86_64-windows-gnu
zig build bundle -Dformat=app
zig build bundle -Dformat=dmg
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

AppImage generates an AppDir and invokes `appimagetool`:

```zig
.appimage = .{
    // Defaults to searching PATH.
    .appimagetool = "/path/to/appimagetool",
},
```

The tool must be executable; AppImages distributed without FUSE are handled by
setting `APPIMAGE_EXTRACT_AND_RUN=1` for the child process.

macOS app bundles put the executable in `Contents/MacOS` and resources in
`Contents/Resources`. `Info.plist`, `PkgInfo`, and `icon.icns` are generated
natively; ICNS is built from the configured square PNG icons without
`iconutil` or `sips`, so include 512x512 and 1024x1024 sources for complete
icon coverage. DMGs contain the `.app` and an `/Applications` symlink and are
written as UDZO images by `hdiutil`.

Set top-level `.enable_llvm_strip = true` to strip the bundled executable with
the system `llvm-strip` for every format; the build fails with an installation
hint when the tool is not on `PATH`.

The Windows installer is generated by NSIS. `nsis.source` selects the
toolchain:

```zig
.nsis = .{ .source = .bundled },     // bundled NSIS 3.13 (default)
.nsis = .{ .source = .system },      // search makensis on PATH
.nsis = .{ .source = .dir("/path/to/nsis") },
```

The bundled toolchain is resolved per host OS/architecture from lazy
dependencies, so no local NSIS installation is required. The installer
supports NSIS silent mode `/S` and a custom directory as the last argument:

```bash
MyApp-setup.exe /S /D=C:\Program Files\MyApp
```

It installs to `%LOCALAPPDATA%\Programs\<name>` (current user) or the
architecture-appropriate `Program Files` (all users, requires elevation),
registers an uninstall entry, and creates Start Menu/desktop shortcuts. The
finish page lets the user toggle Start Menu, desktop, and run choices.

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
only example appimage
only example nsis
only example app
only example dmg
```
