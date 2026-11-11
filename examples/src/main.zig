const std = @import("std");

pub fn main(init: std.process.Init) !void {
    std.debug.print("Hello from bundled app!\n", .{});
    try std.Io.sleep(init.io, .{ .nanoseconds = 3 * std.time.ns_per_s }, .awake);
}
