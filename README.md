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
| `setup_exe` | `<prefix>/bundle/setup_exe/<name>_<version>_<arch>-setup.exe` |

Archives contain the executable and configured resources at the archive root.
Timestamps are fixed so repeated builds produce identical archives.
`deb` requires a Linux target and is generated natively without external tools.
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
            .description = "My example application",
        },
        .input = .{
            .executable = exe,
            .icon = b.path("assets/icon.png"),
            .resources = &.{
                .{ .source = b.path("assets") },
                .{ .source = b.path("README.md"), .dest = "docs/README.md" },
            },
        },
        .formats = .{
            .zip = .{},
            .tar_gz = .{},
        },
    });

    b.step("package", "Package application").dependOn(&bundled.step);
}
```

For Linux targets, enable the Debian package:

```zig
.formats = .{
    .tar_gz = .{},
    .deb = .{},
},
```

Run:

```bash
zig build package
```

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
only example zip
only example tar_gz
only example deb
only example setup_exe
```
