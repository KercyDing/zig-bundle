# zig-bundle

Cross-platform application bundling for `build.zig`.

Packaging logic is modeled after [tauri-bundler](https://github.com/tauri-apps/tauri/tree/dev/crates/tauri-bundler),
reimplemented in Zig and designed around `std.Build`.

## Requirements

- Zig 0.17.0 or newer.

## Supported formats

| Format | Output | Host | Target | External tool |
| --- | --- | --- | --- | --- |
| `zip` | `<prefix>/bundle/zip/<name>-<version>-<arch>-<os>.zip` | any | any | — |
| `tar_gz` | `<prefix>/bundle/tar_gz/<name>-<version>-<arch>-<os>.tar.gz` | any | any | — |
| `deb` | `<prefix>/bundle/deb/<name>_<version>_<deb-arch>.deb` | any | Linux | — |
| `rpm` | `<prefix>/bundle/rpm/<name>-<version>-<release>.<rpm-arch>.rpm` | any | Linux | — |
| `appimage` | `<prefix>/bundle/appimage/<name>-<version>-<arch>.AppImage` | Linux | Linux | `appimagetool` |
| `nsis` | `<prefix>/bundle/nsis/<name>_<version>_<arch>-setup.exe` | any | Windows | `makensis` |
| `app` | `<prefix>/bundle/app/<name>.app` | any | macOS | — |
| `dmg` | `<prefix>/bundle/dmg/<name>_<version>_<arch>.dmg` | macOS | macOS | `hdiutil` |

`<prefix>` is the Zig install prefix, `zig-out` by default. Override it with
`zig build --prefix <path>`.

Format, host, and target compatibility is validated while configuring the
bundle, before any build step runs. `zip` and `tar_gz` package the common
payload only: the executable and configured resources at the archive root.
They do not implicitly include a `.app`.

## Dependency

Pin a release:

```bash
zig fetch --save=bundle git+https://github.com/KercyDing/zig-bundle#v0.1.1
```

Track `main` for the latest changes; it may contain breaking changes:

```bash
zig fetch --save=bundle git+https://github.com/KercyDing/zig-bundle#main
```

## Quick start

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
                .png = &.{b.path("icons")},
                // Optional macOS icon, used as-is instead of generating one.
                // .icns = b.path("icons/icon.icns"),
            },
            .resources = &.{
                .{ .source = b.path("assets") },
                .{ .source = b.path("README.md"), .dest = "docs/README.md" },
            },
        },
        .formats = bundle.standardFormats(format),
    });

    b.step("bundle", "Bundle application").dependOn(bundled.step);
}
```

`bundle.standardFormats(format)` maps a `bundle.Format` to its default options.
Customize individual formats afterwards if needed.

Select a format with `-Dformat`; the default is `zip`:

```bash
zig build bundle
zig build bundle -Dformat=deb -Dtarget=x86_64-linux-gnu
zig build bundle -Dformat=rpm -Dtarget=x86_64-linux-gnu
zig build bundle -Dformat=appimage -Dtarget=x86_64-linux-gnu
zig build bundle -Dformat=nsis -Dtarget=x86_64-windows-gnu
zig build bundle -Dformat=app
zig build bundle -Dformat=dmg
```

## Common configuration

### Application metadata

`app.name`, `app.identifier`, and `app.version` are required. `version` must be
a semantic version. Optional fields feed the formats that support them:

- `publisher`: Debian maintainer fallback and Windows installer publisher.
- `copyright`: package metadata and Windows installer metadata.
- `license`: package metadata; not embedded in archives.
- `categories`: Linux desktop categories, e.g. `"Utility;"`.
- `description`: short package description.

### Inputs and icons

```zig
.input = .{
    .executable = exe,
    .resources = &.{
        .{ .source = b.path("assets") },
        .{ .source = b.path("README.md"), .dest = "docs/README.md" },
    },
    .icons = .{
        .png = &.{ b.path("icons") },
        .ico = b.path("icons/app.ico"),
        .icns = b.path("icons/app.icns"),
    },
},
```

- Resources may be files or directories. `dest` defaults to the source base
  name; paths are relative to the bundle root.
- PNG icons may be files or directories. Dimensions are read from the PNG
  header. Linux installs them under `hicolor`; Windows packs them into an ICO
  when no `.ico` is supplied; macOS generates an ICNS from square sources.
- `.ico` is used by the Windows installer as-is.
- `.icns` is used by macOS as-is. It takes precedence over generated icons and
  is ignored by other formats.

### Multiple formats

Set several fields in `formats` to build them in one invocation:

```zig
// On a macOS target.
.formats = .{
    .zip = .{},
    .app = .{},
    .dmg = .{},
},
```

Every enabled format is validated against the same target, so platform-specific
formats cannot be mixed across targets. `app` produces `MyApp.app/`; a
simultaneously enabled `zip` still contains only the common payload, not the
`.app`.

### Reproducible output

Archives use fixed timestamps and honor `SOURCE_DATE_EPOCH`. Without it, entry
timestamps default to 1980-01-01.

### Stripping

Set `enable_llvm_strip` on the top-level `bundle.add` options:

```zig
const bundled = bundle.add(b, .{
    // ...
    .enable_llvm_strip = true,
});
```

The bundled executable is stripped with the system `llvm-strip` for every
format. The build fails with an installation hint when the tool is not on
`PATH`.

## Format reference

### ZIP and tar.gz

```zig
.formats = .{
    .zip = .{ .compression = .deflate, .level = 6 },
    .tar_gz = .{ .level = 6 },
},
```

`zip.compression` is `.deflate` or `.store`; `level` is 1–9.

### Debian

`deb` requires a Linux target and is written natively, without external tools.

```zig
.deb = .{
    .homepage = "https://example.com",
    // Appended to the package version: 1.0.0-1.
    .revision = "1",
    .maintainer = "Example <example@example.com>",
    .recommends = &.{"xdg-utils"},
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

- `maintainer` defaults to `app.publisher`; `copyright` defaults to
  `app.copyright`.
- Dependency fields: `depends`, `pre_depends`, `recommends`, `suggests`,
  `enhances`, `conflicts`, `breaks`, `replaces`, `provides`.
- `multi_arch` accepts `.same` or `.foreign`.
- `section` defaults to `"utils"`; `priority` defaults to `"optional"`.
- Assets accept files or directories. A trailing `/` means the destination is
  a directory. Files under `etc/` become conffiles automatically;
  `conf_files` adds paths outside `/etc`.
- `license_file_skip_lines` skips a license header. Pre-compressed `.gz`
  changelogs are installed as-is.
- `maintainer_scripts` points to a directory containing `preinst`, `postinst`,
  `prerm`, `postrm`, `config`, or `templates`.
- `triggers` installs a Debian triggers file in the control archive.

Static Zig binaries need no runtime dependencies. Dynamically linked glibc
builds generally need `libc6 (>= ...)`.

### RPM

```zig
.rpm = .{
    .release = "1",
    .epoch = 1,
    .url = "https://example.com",
    .requires = &.{"libc.so.6()(64bit)"},
    .provides = &.{"foo = 1"},
    .conflicts = &.{},
    .obsoletes = &.{},
    .assets = &.{
        .{ .source = b.path("assets/myapp.1"), .dest = "usr/share/man/man1/" },
        .{ .source = b.path("config.toml"), .dest = "etc/myapp/config.toml" },
    },
},
```

- Files under `etc/` become RPM config files and get automatic
  `config(<name>)` provides/requires.
- Man pages under `usr/share/man` are compressed automatically.
- Dependencies accept `name`, `name = version`, and comparison operators.
- `maintainer_scripts` installs `preinst`, `postinst`, `prerm`, and `postrm`
  as RPM scriptlets and adds the `/bin/sh` requirement.

### AppImage

```zig
.appimage = .{
    // Defaults to searching PATH.
    .appimagetool = "/path/to/appimagetool",
},
```

`appimage` requires a Linux host and target. It generates an AppDir and invokes
`appimagetool`. The tool must be executable. AppImages distributed without FUSE
are handled by setting `APPIMAGE_EXTRACT_AND_RUN=1` for the child process.

### Windows installer

`nsis` requires a Windows target. The bundled NSIS toolchain is used by default,
so no local installation is required:

```zig
.nsis = .{
    .install_scope = .current_user,
    .shortcuts = .{ .start_menu = true, .desktop = true },
    .launch_app = true,
    // .bundled (default) | .system | .dir("/path/to/nsis")
    .source = .bundled,
},
```

It supports NSIS silent mode and a custom directory as the last argument:

```bash
MyApp-setup.exe /S /D=C:\Program Files\MyApp
```

The installer:

- installs under `%LOCALAPPDATA%\Programs\<name>` for the current user, or the
  architecture-appropriate `Program Files` with elevation for all users;
- registers an uninstall entry;
- creates Start Menu and desktop shortcuts;
- lets the user toggle shortcuts and launch the app on the finish page.

### macOS app

`app` requires a macOS target and can be produced from any host. The output is a
native `.app` directory:

```text
MyApp.app/
└── Contents/
    ├── Info.plist
    ├── PkgInfo
    ├── MacOS/MyApp
    └── Resources/
```

`Info.plist`, `PkgInfo`, and `icon.icns` are generated natively. ICNS is built
from square PNG icons without `iconutil` or `sips`; include 512x512 and
1024x1024 sources for complete coverage. A configured `icons.icns` is copied
instead.

Extra `Info.plist` keys can be added when needed:

```zig
.app = .{
    .plist_entries = &.{
        plistBool("LSUIElement", true),
        plistString("LSMinimumSystemVersion", "13.0"),
        plistString("NSScreenCaptureUsageDescription", "Captures the screen to recognize text."),
    },
},
```

The bundle is code signed after it has been assembled. Zig links the executable
with an ad-hoc signature that covers only the Mach-O, so without this step the
bundle's signature no longer describes `Contents/`: macOS treats the app as
damaged and TCC refuses to bind Screen Recording or Accessibility grants to it.

`sign` defaults to `.{}`, which signs ad-hoc. Signing requires a macOS host;
other hosts skip it and print a warning. Use a stable identity when the app
needs TCC permissions, because those grants are keyed to the signature and an
ad-hoc identity changes with every build:

```zig
.app = .{
    .sign = .{
        .identity = "Developer ID Application: Example (TEAM123456)",
        .runtime = true,   // required for notarization
        .timestamp = true, // Apple-issued identities only
        .entitlements = b.path("kocr.entitlements"),
    },
},
```

The `dmg` format stages its own copy of the app and takes the same `sign`
option. Signing is not notarization: run `notarytool` on the finished artifact.

### macOS DMG

`dmg` requires a macOS host and macOS target. It stages the `.app` with an
`/Applications` symlink and invokes `hdiutil`.

```zig
.dmg = .{
    // Defaults to app.name.
    .volume_name = "MyApp",
    // .udzo (default), .udbz, or .ulfo.
    .compression = .udzo,
    // Add an /Applications symlink.
    .applications_link = true,
    // Optional Finder layout.
    .layout = .{
        .background = b.path("assets/dmg.png"),
        .window_size = .{ .width = 660, .height = 476 },
        .icon_size = 96,
        .app_position = .{ .x = 180, .y = 230 },
        .applications_position = .{ .x = 480, .y = 230 },
    },
},
```

When `layout` is set, the DMG is created as a read-write image, mounted, adjusted
through Finder AppleScript, then converted to the requested format. This
requires a Finder session, so it is intended for desktop macOS use.

`dmg` contains the app; it does not implicitly enable the `app` output. Enable
both if you also want the unpacked directory:

```zig
.formats = .{ .app = .{}, .dmg = .{} },
```

The background image is copied into `.background/` and hidden from Finder. Finder
window size, icon size, and icon positions are optional; the values above are the
defaults.

## Example

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

# Examples
only example run
only example app
only example nsis
```

Other formats are available through the same example targets; see [`Onlyfile`](Onlyfile).
