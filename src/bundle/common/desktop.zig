//! Freedesktop desktop entry rendering shared by Linux formats.
const std = @import("std");

pub const Info = struct {
    name: []const u8,
    executable_name: []const u8,
    description: ?[]const u8 = null,
    categories: ?[]const u8 = null,
    has_icon: bool = false,
};

fn firstLine(text: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    return std.mem.trim(u8, text[0..end], " \t\r");
}

pub fn render(allocator: std.mem.Allocator, info: Info) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    errdefer allocating.deinit();
    const writer = &allocating.writer;

    try writer.writeAll("[Desktop Entry]\n");
    if (info.description) |description| {
        const comment = firstLine(description);
        if (comment.len > 0) try writer.print("Comment={s}\n", .{comment});
    }

    if (std.mem.indexOfAny(u8, info.executable_name, " \t") != null) {
        try writer.print("Exec=\"{s}\"\n", .{info.executable_name});
    } else {
        try writer.print("Exec={s}\n", .{info.executable_name});
    }
    try writer.print("StartupWMClass={s}\n", .{info.executable_name});
    if (info.has_icon) try writer.print("Icon={s}\n", .{info.executable_name});
    if (info.categories) |categories| {
        if (categories.len > 0) {
            try writer.print("Categories={s}", .{categories});
            if (categories[categories.len - 1] != ';') try writer.writeByte(';');
            try writer.writeByte('\n');
        }
    }
    try writer.print("Name={s}\n", .{info.name});
    try writer.writeAll("Terminal=false\nType=Application\n");

    return allocating.toOwnedSlice();
}
