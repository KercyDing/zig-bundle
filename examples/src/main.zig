const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    std.debug.print("Hello from bundled app!\n", .{});
    try printResource(init.io, allocator, "assets/data.txt");
    try printResource(init.io, allocator, "assets/nested/config.json");

    if (std.Io.Dir.cwd().readFileAlloc(init.io, "assets/test.png", allocator, .limited(1024 * 1024))) |icon| {
        std.debug.print("assets/test.png: {d} bytes\n", .{icon.len});
    } else |_| {
        std.debug.print("assets/test.png: not found\n", .{});
    }

    std.debug.print("Press Enter to exit...", .{});
    var input_buffer: [128]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(init.io, &input_buffer);
    _ = stdin_reader.interface.takeDelimiterInclusive('\n') catch {};
}

fn printResource(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024)) catch {
        std.debug.print("{s}: not found\n", .{path});
        return;
    };

    std.debug.print("{s}: {s}\n", .{ path, std.mem.trimEnd(u8, data, "\r\n") });
}
