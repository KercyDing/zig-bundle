//! Example GUI application built with nanoui.
const std = @import("std");

const nanoui = @import("nanoui");
const ui = nanoui.ui;

const Counter = struct {
    count: i64 = 0,

    fn view(self: *Counter, c: *ui.Context) void {
        const col = ui.div(c).column().sizeFull().center().gap(16);
        defer col.end();

        ui.text(c, "Hello from zig-bundle", .{ .size = 28, .weight = .bold });
        ui.textf(c, .{ .size = 56, .weight = .bold }, "{d}", .{self.count});
        if (ui.button(c, "Increment", .{ .variant = .primary }).clicked) self.count += 1;
    }
};

pub fn main(init: std.process.Init) !void {
    const app = try nanoui.App.create(init, .{ .name = "HelloBundle" });
    defer app.destroy();

    var state: Counter = .{};
    _ = try app.newWindow(.{
        .title = "HelloBundle",
        .content = .{ .view = .init(&state, Counter.view) },
    });
    try app.run();
}
