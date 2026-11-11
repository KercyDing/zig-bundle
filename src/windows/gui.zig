const std = @import("std");

const windows = std.os.windows;

const HRESULT = i32;
const rpc_e_changed_mode: HRESULT = @bitCast(@as(u32, 0x80010106));
const coinit_apartment_threaded: u32 = 2;

const td_information_icon: ?*const anyopaque = @ptrFromInt(32516);
const td_error_icon: ?*const anyopaque = @ptrFromInt(32513);
const tdcbf_ok: u32 = 1;
const tdcbf_cancel: u32 = 8;
const idok: c_int = 1;

const clsctx_inproc_server: u32 = 1;
const fos_pickfolders: u32 = 0x20;
const fos_forcefilesystem: u32 = 0x40;
const fos_pathmustexist: u32 = 0x800;
const fos_nochangedir: u32 = 0x8;
const sigdn_filesyspath: u32 = 0x80058000;

const clsid_file_open_dialog = windows.GUID{
    .Data1 = 0xDC1C5A9C,
    .Data2 = 0xE88A,
    .Data3 = 0x4DDE,
    .Data4 = .{ 0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7 },
};

const iid_file_open_dialog = windows.GUID{
    .Data1 = 0xD57C7288,
    .Data2 = 0xD4AD,
    .Data3 = 0x4768,
    .Data4 = .{ 0xBE, 0x02, 0x9D, 0x96, 0x95, 0x32, 0xD9, 0x60 },
};

const iid_shell_item = windows.GUID{
    .Data1 = 0x43826D1E,
    .Data2 = 0xE718,
    .Data3 = 0x42EE,
    .Data4 = .{ 0xBC, 0x55, 0xA1, 0xE2, 0x61, 0xC3, 0x7B, 0xFE },
};

const wm_command: u32 = 0x0111;
const wm_setfont: u32 = 0x0030;
const wm_paint: u32 = 0x000F;
const wm_close: u32 = 0x0010;
const wm_destroy: u32 = 0x0002;
const bs_autocheckbox: u32 = 0x0003;
const bm_setcheck: u32 = 0x00F1;
const bm_getcheck: u32 = 0x00F0;
const bst_checked: usize = 1;
const di_normal: c_int = 3;
const interpolation_high_quality_bicubic: c_int = 7;
const bn_clicked: u16 = 0;
const en_change: u16 = 0x0300;
const es_readonly: u32 = 0x0800;

const ws_child: u32 = 0x40000000;
const ws_visible: u32 = 0x10000000;
const ws_border: u32 = 0x00800000;
const ws_caption: u32 = 0x00C00000;
const ws_sysmenu: u32 = 0x00080000;
const ws_minimizebox: u32 = 0x00020000;
const ws_tabstop: u32 = 0x00010000;
const ws_group: u32 = 0x00020000;
const es_autohscroll: u32 = 0x0080;
const bs_defpushbutton: u32 = 0x00000001;
const sw_show: c_int = 5;
const gwlp_userdata: c_int = -21;
const sm_cxscreen: c_int = 0;
const sm_cyscreen: c_int = 1;
const default_face: usize = 16;
const makeintresource_arrow: ?*const anyopaque = @ptrFromInt(32512);
const makeintresource_appicon: ?*const anyopaque = @ptrFromInt(32512);

const image_icon: u32 = 1;
const lr_loadfromfile: u32 = 0x10;
const mb_ok: u32 = 0x0;
const mb_yesno: u32 = 0x4;
const mb_iconwarning: u32 = 0x30;
const idyes: c_int = 6;

const id_edit: usize = 1001;
const id_browse: usize = 1002;
const id_install: usize = 1003;
const id_cancel: usize = 1004;
const id_required: usize = 1005;
const id_available: usize = 1006;

const id_finish_run: usize = 2001;
const id_finish_desktop: usize = 2002;
const id_finish: usize = 2003;
const id_finish_cancel: usize = 2004;
const id_finish_start_menu: usize = 2005;
const id_complete_finish: usize = 3001;

const class_static = std.unicode.wtf8ToWtf16LeStringLiteral("STATIC");
const class_edit = std.unicode.wtf8ToWtf16LeStringLiteral("EDIT");
const class_button = std.unicode.wtf8ToWtf16LeStringLiteral("BUTTON");
const window_class = std.unicode.wtf8ToWtf16LeStringLiteral("ZigBundleSetup");
const finish_class = std.unicode.wtf8ToWtf16LeStringLiteral("ZigBundleFinish");
const complete_class = std.unicode.wtf8ToWtf16LeStringLiteral("ZigBundleUninstallComplete");

const POINT = extern struct {
    x: c_int,
    y: c_int,
};

const RECT = extern struct {
    left: c_int,
    top: c_int,
    right: c_int,
    bottom: c_int,
};

const PAINTSTRUCT = extern struct {
    hdc: ?*anyopaque,
    erase: c_int,
    paint: RECT,
    restore: c_int,
    inc_update: c_int,
    reserved: [32]u8,
};

const MSG = extern struct {
    hwnd: ?*anyopaque,
    message: u32,
    wparam: usize,
    lparam: isize,
    time: u32,
    point: POINT,
};

const WNDCLASSEXW = extern struct {
    size: u32,
    style: u32,
    wnd_proc: *const fn (?*anyopaque, u32, usize, isize) callconv(.winapi) isize,
    class_extra: c_int,
    window_extra: c_int,
    instance: ?*anyopaque,
    icon: ?*anyopaque,
    cursor: ?*anyopaque,
    background: ?*anyopaque,
    menu_name: ?windows.LPCWSTR,
    class_name: windows.LPCWSTR,
    small_icon: ?*anyopaque,
};

const IFileOpenDialog = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IFileOpenDialog) callconv(.winapi) u32,
        Show: *const fn (*IFileOpenDialog, ?*anyopaque) callconv(.winapi) HRESULT,
        SetFileTypes: *const anyopaque,
        SetFileTypeIndex: *const anyopaque,
        GetFileTypeIndex: *const anyopaque,
        Advise: *const anyopaque,
        Unadvise: *const anyopaque,
        SetOptions: *const fn (*IFileOpenDialog, u32) callconv(.winapi) HRESULT,
        GetOptions: *const anyopaque,
        SetDefaultFolder: *const anyopaque,
        SetFolder: *const fn (*IFileOpenDialog, *IShellItem) callconv(.winapi) HRESULT,
        GetFolder: *const anyopaque,
        GetCurrentSelection: *const anyopaque,
        SetFileName: *const anyopaque,
        GetFileName: *const anyopaque,
        SetTitle: *const fn (*IFileOpenDialog, windows.LPCWSTR) callconv(.winapi) HRESULT,
        SetOkButtonLabel: *const anyopaque,
        SetFileNameLabel: *const anyopaque,
        GetResult: *const fn (*IFileOpenDialog, *?*IShellItem) callconv(.winapi) HRESULT,
        AddPlace: *const anyopaque,
        SetDefaultExtension: *const anyopaque,
        Close: *const anyopaque,
        SetClientGuid: *const anyopaque,
        ClearClientData: *const anyopaque,
        SetFilter: *const anyopaque,
        GetResults: *const anyopaque,
        GetSelectedItems: *const anyopaque,
    };
};

const IShellItem = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IShellItem) callconv(.winapi) u32,
        BindToHandler: *const anyopaque,
        GetParent: *const anyopaque,
        GetDisplayName: *const fn (*IShellItem, u32, *?[*:0]u16) callconv(.winapi) HRESULT,
        GetAttributes: *const anyopaque,
        Compare: *const anyopaque,
        IsFolder: *const anyopaque,
        GetClassID: *const anyopaque,
    };
};

pub const PageMode = enum { install, uninstall };

const State = struct {
    allocator: std.mem.Allocator,
    default_dir: []const u8,
    required_bytes: u64,
    mode: PageMode = .install,
    edit: ?*anyopaque,
    browse_button: ?*anyopaque,
    install_button: ?*anyopaque,
    cancel_button: ?*anyopaque,
    required_label: ?*anyopaque,
    available_label: ?*anyopaque,
    dpi: c_int = 0,
    icon: ?*anyopaque = null,
    page_image: ?*anyopaque = null,
    result: ?[]const u8 = null,
};

const FinishState = struct {
    allocator: std.mem.Allocator,
    dpi: c_int,
    icon: ?*anyopaque,
    page_image: ?*anyopaque = null,
    run_check: ?*anyopaque,
    desktop_check: ?*anyopaque,
    start_menu_check: ?*anyopaque,
    run_app: bool = false,
    desktop_shortcut: bool = false,
    start_menu_shortcut: bool = false,
};

pub const FinishResult = struct {
    run_app: bool,
    desktop_shortcut: bool,
    start_menu_shortcut: bool,
};

const CompleteState = struct {
    dpi: c_int,
    icon: ?*anyopaque,
    page_image: ?*anyopaque = null,
};

extern "user32" fn RegisterClassExW(class: *const WNDCLASSEXW) callconv(.winapi) u16;
extern "user32" fn CreateWindowExW(
    ex_style: u32,
    class_name: windows.LPCWSTR,
    window_name: ?windows.LPCWSTR,
    style: u32,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    parent: ?*anyopaque,
    menu: ?*anyopaque,
    instance: ?*anyopaque,
    param: ?*anyopaque,
) callconv(.winapi) ?*anyopaque;
extern "user32" fn DestroyWindow(hwnd: ?*anyopaque) callconv(.winapi) c_int;
extern "user32" fn DefWindowProcW(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize;
extern "user32" fn ShowWindow(hwnd: ?*anyopaque, command: c_int) callconv(.winapi) c_int;
extern "user32" fn UpdateWindow(hwnd: ?*anyopaque) callconv(.winapi) c_int;
extern "user32" fn GetMessageW(message: *MSG, hwnd: ?*anyopaque, min: u32, max: u32) callconv(.winapi) c_int;
extern "user32" fn TranslateMessage(message: *const MSG) callconv(.winapi) c_int;
extern "user32" fn DispatchMessageW(message: *const MSG) callconv(.winapi) isize;
extern "user32" fn PostQuitMessage(code: c_int) callconv(.winapi) void;
extern "user32" fn SetWindowLongPtrW(hwnd: ?*anyopaque, index: c_int, value: isize) callconv(.winapi) isize;
extern "user32" fn GetWindowLongPtrW(hwnd: ?*anyopaque, index: c_int) callconv(.winapi) isize;
extern "user32" fn SendMessageW(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize;
extern "user32" fn SetWindowTextW(hwnd: ?*anyopaque, text: windows.LPCWSTR) callconv(.winapi) c_int;
extern "user32" fn GetWindowTextW(hwnd: ?*anyopaque, buffer: [*]u16, max: c_int) callconv(.winapi) c_int;
extern "user32" fn GetWindowTextLengthW(hwnd: ?*anyopaque) callconv(.winapi) c_int;
extern "user32" fn GetSystemMetrics(index: c_int) callconv(.winapi) c_int;
extern "user32" fn GetDpiForSystem() callconv(.winapi) u32;
extern "user32" fn BeginPaint(hwnd: ?*anyopaque, paint: *PAINTSTRUCT) callconv(.winapi) ?*anyopaque;
extern "user32" fn EndPaint(hwnd: ?*anyopaque, paint: *const PAINTSTRUCT) callconv(.winapi) c_int;
extern "user32" fn GetClientRect(hwnd: ?*anyopaque, rect: *RECT) callconv(.winapi) c_int;
extern "user32" fn EnableWindow(hwnd: ?*anyopaque, enable: c_int) callconv(.winapi) c_int;
extern "user32" fn FillRect(hdc: ?*anyopaque, rect: *const RECT, brush: ?*anyopaque) callconv(.winapi) c_int;
extern "user32" fn DrawIconEx(
    hdc: ?*anyopaque,
    x: c_int,
    y: c_int,
    icon: ?*anyopaque,
    width: c_int,
    height: c_int,
    step: c_int,
    flicker: ?*anyopaque,
    flags: c_int,
) callconv(.winapi) c_int;
const GdiplusStartupInput = extern struct {
    version: u32,
    debug_event_callback: ?*anyopaque,
    suppress_background_thread: c_int,
    suppress_external_codecs: c_int,
};

var gdiplus_token: usize = 0;

extern "gdiplus" fn GdiplusStartup(token: *usize, input: *const GdiplusStartupInput, output: ?*anyopaque) callconv(.winapi) u32;
extern "gdiplus" fn GdipLoadImageFromFile(filename: windows.LPCWSTR, image: *?*anyopaque) callconv(.winapi) u32;
extern "gdiplus" fn GdipCreateFromHDC(hdc: ?*anyopaque, graphics: *?*anyopaque) callconv(.winapi) u32;
extern "gdiplus" fn GdipSetInterpolationMode(graphics: ?*anyopaque, mode: c_int) callconv(.winapi) u32;
extern "gdiplus" fn GdipDrawImageRectI(graphics: ?*anyopaque, image: ?*anyopaque, x: c_int, y: c_int, width: c_int, height: c_int) callconv(.winapi) u32;
extern "gdiplus" fn GdipDeleteGraphics(graphics: ?*anyopaque) callconv(.winapi) u32;

fn ensureGdiplus() bool {
    if (gdiplus_token != 0) return true;

    var input = GdiplusStartupInput{
        .version = 1,
        .debug_event_callback = null,
        .suppress_background_thread = 0,
        .suppress_external_codecs = 0,
    };
    var token: usize = 0;
    if (GdiplusStartup(&token, &input, null) != 0) return false;
    gdiplus_token = token;
    return true;
}

pub fn loadImage(allocator: std.mem.Allocator, path: []const u8) ?*anyopaque {
    if (!ensureGdiplus()) return null;

    const path_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, path) catch return null;
    var image: ?*anyopaque = null;
    if (GdipLoadImageFromFile(path_w.ptr, &image) != 0) return null;
    return image;
}

fn drawImage(hdc: ?*anyopaque, image: ?*anyopaque, x: c_int, y: c_int, size: c_int) void {
    var graphics: ?*anyopaque = null;
    if (GdipCreateFromHDC(hdc, &graphics) != 0 or graphics == null) return;

    _ = GdipSetInterpolationMode(graphics, interpolation_high_quality_bicubic);
    _ = GdipDrawImageRectI(graphics, image, x, y, size, size);
    _ = GdipDeleteGraphics(graphics);
}

extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn DeleteObject(object: ?*anyopaque) callconv(.winapi) c_int;
extern "gdi32" fn CreateFontW(
    height: c_int,
    width: c_int,
    escapement: c_int,
    orientation: c_int,
    weight: c_int,
    italic: u32,
    underline: u32,
    strikeout: u32,
    charset: u32,
    out_precision: u32,
    clip_precision: u32,
    quality: u32,
    pitch_and_family: u32,
    face_name: windows.LPCWSTR,
) callconv(.winapi) ?*anyopaque;
extern "user32" fn SetProcessDPIAware() callconv(.winapi) c_int;
extern "user32" fn SetFocus(hwnd: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "user32" fn LoadIconW(instance: ?*anyopaque, name: ?*const anyopaque) callconv(.winapi) ?*anyopaque;
extern "user32" fn LoadImageW(
    instance: ?*anyopaque,
    name: ?*const anyopaque,
    type: u32,
    cx: c_int,
    cy: c_int,
    flags: u32,
) callconv(.winapi) ?*anyopaque;
extern "user32" fn LoadCursorW(instance: ?*anyopaque, name: ?*const anyopaque) callconv(.winapi) ?*anyopaque;
extern "user32" fn MessageBoxW(
    owner: ?*anyopaque,
    text: windows.LPCWSTR,
    caption: windows.LPCWSTR,
    flags: u32,
) callconv(.winapi) c_int;

extern "kernel32" fn GetModuleHandleW(name: ?windows.LPCWSTR) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetDiskFreeSpaceExW(
    directory: windows.LPCWSTR,
    free_available: *u64,
    total: ?*u64,
    total_free: ?*u64,
) callconv(.winapi) c_int;

extern "comctl32" fn TaskDialog(
    owner: ?*anyopaque,
    instance: ?*anyopaque,
    title: ?windows.LPCWSTR,
    instruction: ?windows.LPCWSTR,
    content: ?windows.LPCWSTR,
    buttons: u32,
    icon: ?*const anyopaque,
    button: ?*c_int,
) callconv(.winapi) HRESULT;

extern "shell32" fn SHCreateItemFromParsingName(
    path: windows.LPCWSTR,
    bind_ctx: ?*anyopaque,
    riid: *const windows.GUID,
    out: *?*anyopaque,
) callconv(.winapi) HRESULT;

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, coinit: u32) callconv(.winapi) HRESULT;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoTaskMemFree(ptr: ?*anyopaque) callconv(.winapi) void;
extern "ole32" fn CoCreateInstance(
    rclsid: *const windows.GUID,
    outer: ?*anyopaque,
    clsctx: u32,
    riid: *const windows.GUID,
    out: *?*anyopaque,
) callconv(.winapi) HRESULT;

pub fn loadIcon(allocator: std.mem.Allocator, path: []const u8) ?*anyopaque {
    const path_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, path) catch return null;
    return LoadImageW(null, @ptrCast(path_w.ptr), image_icon, 48, 48, lr_loadfromfile);
}

pub fn chooseInstallLocation(
    allocator: std.mem.Allocator,
    app_name: []const u8,
    app_version: []const u8,
    default_dir: []const u8,
    required_bytes: u64,
    app_icon: ?*anyopaque,
    app_image: ?*anyopaque,
) !?[]const u8 {
    return runPage(.install, allocator, app_name, app_version, default_dir, required_bytes, app_icon, app_image);
}

pub fn confirmOverwrite(allocator: std.mem.Allocator, install_dir: []const u8) bool {
    const content = std.fmt.allocPrint(
        allocator,
        "The folder is not empty:\n\n{s}\n\nExisting files may be overwritten. Install anyway?",
        .{install_dir},
    ) catch return false;
    const content_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, content) catch return false;
    const caption = std.unicode.wtf8ToWtf16LeStringLiteral("Folder not empty");

    return MessageBoxW(null, content_w.ptr, caption, mb_yesno | mb_iconwarning) == idyes;
}

pub fn uninstallPage(
    allocator: std.mem.Allocator,
    app_name: []const u8,
    app_version: []const u8,
    install_dir: []const u8,
    app_icon: ?*anyopaque,
    app_image: ?*anyopaque,
) !bool {
    return (try runPage(.uninstall, allocator, app_name, app_version, install_dir, 0, app_icon, app_image)) != null;
}

fn runPage(
    mode: PageMode,
    allocator: std.mem.Allocator,
    app_name: []const u8,
    app_version: []const u8,
    default_dir: []const u8,
    required_bytes: u64,
    app_icon: ?*anyopaque,
    app_image: ?*anyopaque,
) !?[]const u8 {
    _ = SetProcessDPIAware();

    const instance = GetModuleHandleW(null);
    const icon = app_icon orelse LoadIconW(null, makeintresource_appicon);
    _ = RegisterClassExW(&.{
        .size = @sizeOf(WNDCLASSEXW),
        .style = 0,
        .wnd_proc = windowProc,
        .class_extra = 0,
        .window_extra = 0,
        .instance = instance,
        .icon = icon,
        .cursor = LoadCursorW(null, makeintresource_arrow),
        .background = @ptrFromInt(default_face),
        .menu_name = null,
        .class_name = window_class,
        .small_icon = icon,
    });

    var state = State{
        .allocator = allocator,
        .default_dir = default_dir,
        .required_bytes = required_bytes,
        .mode = mode,
        .edit = null,
        .browse_button = null,
        .install_button = null,
        .cancel_button = null,
        .required_label = null,
        .available_label = null,
    };

    const dpi: c_int = blk: {
        const system_dpi = GetDpiForSystem();
        break :blk if (system_dpi == 0) 96 else @intCast(system_dpi);
    };
    state.dpi = dpi;
    state.icon = app_icon;
    state.page_image = app_image;

    const normal_font = createFont(dpi, 9, 400);
    const heading_font = createFont(dpi, 12, 600);

    const title = if (mode == .uninstall)
        try std.fmt.allocPrint(allocator, "{s} Uninstall", .{app_name})
    else
        try std.fmt.allocPrint(allocator, "{s} Setup", .{app_name});
    const title_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, title);
    const screen_width = GetSystemMetrics(sm_cxscreen);
    const screen_height = GetSystemMetrics(sm_cyscreen);
    const window_width = scale(600, dpi);
    const window_height = scale(440, dpi);

    const hwnd = CreateWindowExW(
        0,
        window_class,
        title_w.ptr,
        ws_caption | ws_sysmenu | ws_minimizebox,
        @divTrunc(screen_width - window_width, 2),
        @divTrunc(screen_height - window_height, 2),
        window_width,
        window_height,
        null,
        null,
        instance,
        null,
    ) orelse return error.WindowCreateFailed;

    _ = SetWindowLongPtrW(hwnd, gwlp_userdata, @bitCast(@intFromPtr(&state)));

    const heading = if (mode == .uninstall)
        try std.fmt.allocPrint(allocator, "Uninstall {s}", .{app_name})
    else
        try std.fmt.allocPrint(allocator, "Choose Install Location", .{});
    const heading_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, heading);
    const description = if (mode == .uninstall)
        try std.fmt.allocPrint(
            allocator,
            "{s} will be uninstalled from the following folder. Click Uninstall to start the uninstallation.",
            .{app_name},
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "Setup will install {s} {s} in the following folder. To install in a different folder, click Browse and select another folder. Click Install to start the installation.",
            .{ app_name, app_version },
        );
    const description_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, description);
    const destination = if (mode == .uninstall)
        std.unicode.wtf8ToWtf16LeStringLiteral("Uninstalling from:")
    else
        std.unicode.wtf8ToWtf16LeStringLiteral("Destination Folder");
    const browse = std.unicode.wtf8ToWtf16LeStringLiteral("Browse...");
    const action = if (mode == .uninstall)
        std.unicode.wtf8ToWtf16LeStringLiteral("Uninstall")
    else
        std.unicode.wtf8ToWtf16LeStringLiteral("Install");
    const cancel = std.unicode.wtf8ToWtf16LeStringLiteral("Cancel");

    _ = createControl(hwnd, class_static, heading_w.ptr, ws_child | ws_visible, scale(24, dpi), scale(20, dpi), scale(480, dpi), scale(28, dpi), 0, heading_font);

    if (mode == .uninstall) {
        const subtitle = try std.fmt.allocPrint(allocator, "Remove {s} from your computer.", .{app_name});
        const subtitle_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, subtitle);
        _ = createControl(hwnd, class_static, subtitle_w.ptr, ws_child | ws_visible, scale(24, dpi), scale(50, dpi), scale(480, dpi), scale(20, dpi), 0, normal_font);
    }

    const description_y: c_int = if (mode == .uninstall) 80 else 58;
    _ = createControl(hwnd, class_static, description_w.ptr, ws_child | ws_visible, scale(24, dpi), scale(description_y, dpi), scale(480, dpi), scale(60, dpi), 0, normal_font);

    const label_width: c_int = if (mode == .uninstall) 130 else 300;
    const edit_x: c_int = if (mode == .uninstall) 160 else 24;
    const edit_y: c_int = if (mode == .uninstall) 123 else 146;
    const edit_width: c_int = if (mode == .uninstall) 400 else 430;
    _ = createControl(hwnd, class_static, destination, ws_child | ws_visible, scale(24, dpi), scale(126, dpi), scale(label_width, dpi), scale(20, dpi), 0, normal_font);

    const edit_style = ws_child | ws_visible | ws_border | es_autohscroll |
        (if (mode == .uninstall) es_readonly else ws_tabstop);
    state.edit = createControl(hwnd, class_edit, null, edit_style, scale(edit_x, dpi), scale(edit_y, dpi), scale(edit_width, dpi), scale(21, dpi), id_edit, normal_font);
    if (mode == .install) {
        state.browse_button = createControl(hwnd, class_button, browse, ws_child | ws_visible | ws_tabstop, scale(462, dpi), scale(145, dpi), scale(96, dpi), scale(23, dpi), id_browse, normal_font);
        state.required_label = createControl(hwnd, class_static, null, ws_child | ws_visible, scale(24, dpi), scale(286, dpi), scale(360, dpi), scale(20, dpi), id_required, normal_font);
        state.available_label = createControl(hwnd, class_static, null, ws_child | ws_visible, scale(24, dpi), scale(310, dpi), scale(360, dpi), scale(20, dpi), id_available, normal_font);
    }
    state.install_button = createControl(hwnd, class_button, action, ws_child | ws_visible | ws_tabstop | ws_group | bs_defpushbutton, scale(370, dpi), scale(340, dpi), scale(96, dpi), scale(30, dpi), id_install, normal_font);
    state.cancel_button = createControl(hwnd, class_button, cancel, ws_child | ws_visible | ws_tabstop, scale(474, dpi), scale(340, dpi), scale(96, dpi), scale(30, dpi), id_cancel, normal_font);

    const default_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, default_dir);
    _ = SetWindowTextW(state.edit, default_w.ptr);
    updateSpaceInfo(&state);

    _ = ShowWindow(hwnd, sw_show);
    _ = UpdateWindow(hwnd);
    _ = SetFocus(state.edit);

    var message: MSG = undefined;
    while (GetMessageW(&message, null, 0, 0) > 0) {
        _ = TranslateMessage(&message);
        _ = DispatchMessageW(&message);
    }

    return state.result;
}

pub fn uninstallComplete(
    allocator: std.mem.Allocator,
    app_name: []const u8,
    app_icon: ?*anyopaque,
    app_image: ?*anyopaque,
) !void {
    _ = SetProcessDPIAware();

    const instance = GetModuleHandleW(null);
    const icon = app_icon orelse LoadIconW(null, makeintresource_appicon);
    _ = RegisterClassExW(&.{
        .size = @sizeOf(WNDCLASSEXW),
        .style = 0,
        .wnd_proc = completeProc,
        .class_extra = 0,
        .window_extra = 0,
        .instance = instance,
        .icon = icon,
        .cursor = LoadCursorW(null, makeintresource_arrow),
        .background = @ptrFromInt(default_face),
        .menu_name = null,
        .class_name = complete_class,
        .small_icon = icon,
    });

    const dpi: c_int = blk: {
        const system_dpi = GetDpiForSystem();
        break :blk if (system_dpi == 0) 96 else @intCast(system_dpi);
    };

    var state = CompleteState{
        .dpi = dpi,
        .icon = app_icon,
        .page_image = app_image,
    };

    const title = try std.fmt.allocPrint(allocator, "{s} Uninstall", .{app_name});
    const title_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, title);
    const screen_width = GetSystemMetrics(sm_cxscreen);
    const screen_height = GetSystemMetrics(sm_cyscreen);
    const window_width = scale(480, dpi);
    const window_height = scale(280, dpi);

    const hwnd = CreateWindowExW(
        0,
        complete_class,
        title_w.ptr,
        ws_caption | ws_sysmenu | ws_minimizebox,
        @divTrunc(screen_width - window_width, 2),
        @divTrunc(screen_height - window_height, 2),
        window_width,
        window_height,
        null,
        null,
        instance,
        null,
    ) orelse return error.WindowCreateFailed;

    _ = SetWindowLongPtrW(hwnd, gwlp_userdata, @bitCast(@intFromPtr(&state)));

    const normal_font = createFont(dpi, 9, 400);
    const heading_font = createFont(dpi, 14, 600);

    const heading = std.unicode.wtf8ToWtf16LeStringLiteral("Uninstall Complete");
    const message = try std.fmt.allocPrint(allocator, "{s} has been uninstalled from your computer.", .{app_name});
    const message_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, message);
    const click_finish = std.unicode.wtf8ToWtf16LeStringLiteral("Click Finish to close.");
    const finish = std.unicode.wtf8ToWtf16LeStringLiteral("Finish");

    _ = createControl(hwnd, class_static, heading, ws_child | ws_visible, scale(24, dpi), scale(20, dpi), scale(360, dpi), scale(30, dpi), 0, heading_font);
    _ = createControl(hwnd, class_static, message_w.ptr, ws_child | ws_visible, scale(24, dpi), scale(62, dpi), scale(360, dpi), scale(40, dpi), 0, normal_font);
    _ = createControl(hwnd, class_static, click_finish, ws_child | ws_visible, scale(24, dpi), scale(96, dpi), scale(360, dpi), scale(20, dpi), 0, normal_font);
    _ = createControl(hwnd, class_button, finish, ws_child | ws_visible | ws_tabstop | ws_group | bs_defpushbutton, scale(354, dpi), scale(210, dpi), scale(96, dpi), scale(30, dpi), id_complete_finish, normal_font);

    _ = ShowWindow(hwnd, sw_show);
    _ = UpdateWindow(hwnd);
    _ = SetFocus(hwnd);

    var message_loop: MSG = undefined;
    while (GetMessageW(&message_loop, null, 0, 0) > 0) {
        _ = TranslateMessage(&message_loop);
        _ = DispatchMessageW(&message_loop);
    }
}

fn getCompleteState(hwnd: ?*anyopaque) ?*CompleteState {
    const value = GetWindowLongPtrW(hwnd, gwlp_userdata);
    if (value == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(value)));
}

fn completeProc(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    const state = getCompleteState(hwnd) orelse return DefWindowProcW(hwnd, message, wparam, lparam);

    switch (message) {
        wm_command => {
            const notification: u16 = @truncate(wparam >> 16);
            const id: u16 = @truncate(wparam);
            if (notification == bn_clicked and id == id_complete_finish) {
                _ = DestroyWindow(hwnd);
            }
            return 0;
        },
        wm_paint => {
            var paint: PAINTSTRUCT = undefined;
            const hdc = BeginPaint(hwnd, &paint);
            if (hdc != null) {
                var client: RECT = undefined;
                _ = GetClientRect(hwnd, &client);

                const icon_size = scale(48, state.dpi);
                const x = client.right - scale(24, state.dpi) - icon_size;
                if (state.page_image) |image| {
                    drawImage(hdc, image, x, scale(20, state.dpi), icon_size);
                } else if (state.icon) |icon| {
                    _ = DrawIconEx(hdc, x, scale(20, state.dpi), icon, icon_size, icon_size, 0, null, di_normal);
                }
                _ = EndPaint(hwnd, &paint);
            }
            return 0;
        },
        wm_close => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        wm_destroy => {
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcW(hwnd, message, wparam, lparam),
    }
}

pub fn finishPage(
    allocator: std.mem.Allocator,
    app_name: []const u8,
    app_version: []const u8,
    default_run: bool,
    default_desktop: bool,
    default_start_menu: bool,
    app_icon: ?*anyopaque,
    app_image: ?*anyopaque,
) !FinishResult {
    _ = SetProcessDPIAware();

    const instance = GetModuleHandleW(null);
    const icon = app_icon orelse LoadIconW(null, makeintresource_appicon);
    _ = RegisterClassExW(&.{
        .size = @sizeOf(WNDCLASSEXW),
        .style = 0,
        .wnd_proc = finishProc,
        .class_extra = 0,
        .window_extra = 0,
        .instance = instance,
        .icon = icon,
        .cursor = LoadCursorW(null, makeintresource_arrow),
        .background = @ptrFromInt(default_face),
        .menu_name = null,
        .class_name = finish_class,
        .small_icon = icon,
    });

    const dpi: c_int = blk: {
        const system_dpi = GetDpiForSystem();
        break :blk if (system_dpi == 0) 96 else @intCast(system_dpi);
    };
    const normal_font = createFont(dpi, 9, 400);
    const heading_font = createFont(dpi, 14, 600);

    var state = FinishState{
        .allocator = allocator,
        .dpi = dpi,
        .icon = icon,
        .page_image = app_image,
        .run_check = null,
        .desktop_check = null,
        .start_menu_check = null,
    };

    const title = try std.fmt.allocPrint(allocator, "{s} Setup", .{app_name});
    const title_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, title);
    const screen_width = GetSystemMetrics(sm_cxscreen);
    const screen_height = GetSystemMetrics(sm_cyscreen);
    const window_width = scale(600, dpi);
    const window_height = scale(440, dpi);

    const hwnd = CreateWindowExW(
        0,
        finish_class,
        title_w.ptr,
        ws_caption | ws_sysmenu | ws_minimizebox,
        @divTrunc(screen_width - window_width, 2),
        @divTrunc(screen_height - window_height, 2),
        window_width,
        window_height,
        null,
        null,
        instance,
        null,
    ) orelse return error.WindowCreateFailed;

    _ = SetWindowLongPtrW(hwnd, gwlp_userdata, @bitCast(@intFromPtr(&state)));

    const heading = try std.fmt.allocPrint(allocator, "Completing {s} Setup", .{app_name});
    const heading_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, heading);
    const installed = try std.fmt.allocPrint(allocator, "{s} {s} has been installed on your computer.", .{
        app_name,
        app_version,
    });
    const installed_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, installed);
    const click_finish = std.unicode.wtf8ToWtf16LeStringLiteral("Click Finish to close Setup.");
    const run_label = try std.fmt.allocPrint(allocator, "Run {s}", .{app_name});
    const run_label_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, run_label);
    const desktop_label = std.unicode.wtf8ToWtf16LeStringLiteral("Create a desktop shortcut");
    const start_menu_label = std.unicode.wtf8ToWtf16LeStringLiteral("Create a Start Menu shortcut");
    const finish = std.unicode.wtf8ToWtf16LeStringLiteral("Finish");
    const cancel = std.unicode.wtf8ToWtf16LeStringLiteral("Cancel");

    _ = createControl(hwnd, class_static, heading_w.ptr, ws_child | ws_visible, scale(180, dpi), scale(24, dpi), scale(390, dpi), scale(30, dpi), 0, heading_font);
    _ = createControl(hwnd, class_static, installed_w.ptr, ws_child | ws_visible, scale(180, dpi), scale(70, dpi), scale(390, dpi), scale(20, dpi), 0, normal_font);
    _ = createControl(hwnd, class_static, click_finish, ws_child | ws_visible, scale(180, dpi), scale(96, dpi), scale(390, dpi), scale(20, dpi), 0, normal_font);

    state.run_check = createControl(hwnd, class_button, run_label_w.ptr, ws_child | ws_visible | ws_tabstop | bs_autocheckbox, scale(180, dpi), scale(146, dpi), scale(320, dpi), scale(24, dpi), id_finish_run, normal_font);
    state.desktop_check = createControl(hwnd, class_button, desktop_label, ws_child | ws_visible | ws_tabstop | bs_autocheckbox, scale(180, dpi), scale(180, dpi), scale(320, dpi), scale(24, dpi), id_finish_desktop, normal_font);
    state.start_menu_check = createControl(hwnd, class_button, start_menu_label, ws_child | ws_visible | ws_tabstop | bs_autocheckbox, scale(180, dpi), scale(214, dpi), scale(320, dpi), scale(24, dpi), id_finish_start_menu, normal_font);

    _ = SendMessageW(state.run_check, bm_setcheck, if (default_run) bst_checked else 0, 0);
    _ = SendMessageW(state.desktop_check, bm_setcheck, if (default_desktop) bst_checked else 0, 0);
    _ = SendMessageW(state.start_menu_check, bm_setcheck, if (default_start_menu) bst_checked else 0, 0);
    if (!default_run) {
        _ = EnableWindow(state.run_check, 0);
    }

    _ = createControl(hwnd, class_button, finish, ws_child | ws_visible | ws_tabstop | ws_group | bs_defpushbutton, scale(380, dpi), scale(360, dpi), scale(90, dpi), scale(30, dpi), id_finish, normal_font);
    _ = createControl(hwnd, class_button, cancel, ws_child | ws_visible | ws_tabstop, scale(480, dpi), scale(360, dpi), scale(90, dpi), scale(30, dpi), id_finish_cancel, normal_font);

    _ = ShowWindow(hwnd, sw_show);
    _ = UpdateWindow(hwnd);
    _ = SetFocus(hwnd);

    var message: MSG = undefined;
    while (GetMessageW(&message, null, 0, 0) > 0) {
        _ = TranslateMessage(&message);
        _ = DispatchMessageW(&message);
    }

    return .{
        .run_app = state.run_app,
        .desktop_shortcut = state.desktop_shortcut,
        .start_menu_shortcut = state.start_menu_shortcut,
    };
}

fn finishProc(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    const state = getFinishState(hwnd) orelse return DefWindowProcW(hwnd, message, wparam, lparam);

    switch (message) {
        wm_command => {
            const notification: u16 = @truncate(wparam >> 16);
            const id: u16 = @truncate(wparam);
            if (notification == bn_clicked) {
                switch (id) {
                    id_finish => {
                        state.run_app = SendMessageW(state.run_check, bm_getcheck, 0, 0) == 1;
                        state.desktop_shortcut = SendMessageW(state.desktop_check, bm_getcheck, 0, 0) == 1;
                        state.start_menu_shortcut = SendMessageW(state.start_menu_check, bm_getcheck, 0, 0) == 1;
                        _ = DestroyWindow(hwnd);
                    },
                    id_finish_cancel => _ = DestroyWindow(hwnd),
                    else => {},
                }
            }
            return 0;
        },
        wm_paint => {
            var paint: PAINTSTRUCT = undefined;
            const hdc = BeginPaint(hwnd, &paint);
            if (hdc != null) {
                var client: RECT = undefined;
                _ = GetClientRect(hwnd, &client);

                const panel = RECT{
                    .left = 0,
                    .top = 0,
                    .right = scale(160, state.dpi),
                    .bottom = client.bottom,
                };
                const brush = CreateSolidBrush(rgb(20, 40, 90));
                if (brush != null) {
                    _ = FillRect(hdc, &panel, brush);
                    _ = DeleteObject(brush);
                }

                const icon_size = scale(72, state.dpi);
                const x = @divTrunc(scale(160, state.dpi) - icon_size, 2);
                const y = @divTrunc(client.bottom - icon_size, 2);
                if (state.page_image) |image| {
                    drawImage(hdc, image, x, y, icon_size);
                } else {
                    _ = DrawIconEx(hdc, x, y, state.icon, icon_size, icon_size, 0, null, di_normal);
                }
                _ = EndPaint(hwnd, &paint);
            }
            return 0;
        },
        wm_close => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        wm_destroy => {
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcW(hwnd, message, wparam, lparam),
    }
}

fn getFinishState(hwnd: ?*anyopaque) ?*FinishState {
    const value = GetWindowLongPtrW(hwnd, gwlp_userdata);
    if (value == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(value)));
}

fn rgb(red: u32, green: u32, blue: u32) u32 {
    return red | (green << 8) | (blue << 16);
}

pub fn showInfo(allocator: std.mem.Allocator, title: []const u8, content: []const u8) void {
    _ = taskDialog(allocator, title, "Information", content, tdcbf_ok, td_information_icon);
}

pub fn showError(allocator: std.mem.Allocator, title: []const u8, content: []const u8) void {
    _ = taskDialog(allocator, title, "Error", content, tdcbf_ok, td_error_icon);
}

fn windowProc(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    const state = getState(hwnd) orelse return DefWindowProcW(hwnd, message, wparam, lparam);

    switch (message) {
        wm_command => {
            const notification: u16 = @truncate(wparam >> 16);
            const control: ?*anyopaque = if (lparam == 0)
                null
            else
                @ptrFromInt(@as(usize, @bitCast(lparam)));

            if (notification == bn_clicked) {
                if (control == state.install_button) {
                    installClicked(hwnd, state);
                } else if (control == state.browse_button) {
                    browseClicked(hwnd, state);
                } else if (control == state.cancel_button) {
                    _ = DestroyWindow(hwnd);
                }
            } else if (notification == en_change and control == state.edit) {
                updateSpaceInfo(state);
            }
            return 0;
        },
        wm_paint => {
            var paint: PAINTSTRUCT = undefined;
            const hdc = BeginPaint(hwnd, &paint);
            if (hdc != null) {
                var client: RECT = undefined;
                _ = GetClientRect(hwnd, &client);

                const icon_size = scale(48, state.dpi);
                const x = client.right - scale(24, state.dpi) - icon_size;
                if (state.page_image) |image| {
                    drawImage(hdc, image, x, scale(20, state.dpi), icon_size);
                } else if (state.icon) |icon| {
                    _ = DrawIconEx(hdc, x, scale(20, state.dpi), icon, icon_size, icon_size, 0, null, di_normal);
                }
                _ = EndPaint(hwnd, &paint);
            }
            return 0;
        },
        wm_close => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        wm_destroy => {
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcW(hwnd, message, wparam, lparam),
    }
}

fn installClicked(hwnd: ?*anyopaque, state: *State) void {
    const path = readEditText(state) catch null;
    if (state.mode == .uninstall) {
        state.result = path orelse state.default_dir;
        _ = DestroyWindow(hwnd);
        return;
    }

    if (path == null or path.?.len == 0) {
        const text = std.unicode.wtf8ToWtf16LeStringLiteral("Please choose an installation directory.");
        const caption = std.unicode.wtf8ToWtf16LeStringLiteral("Install");
        _ = MessageBoxW(hwnd, text, caption, mb_ok | mb_iconwarning);
        return;
    }

    state.result = path;
    _ = DestroyWindow(hwnd);
}

fn browseClicked(hwnd: ?*anyopaque, state: *State) void {
    const current = readEditText(state) catch null;
    const selected = browseForFolder(hwnd, state.allocator, current orelse state.default_dir) catch null;
    if (selected) |path| {
        const path_w = std.unicode.wtf8ToWtf16LeAllocZ(state.allocator, path) catch return;
        _ = SetWindowTextW(state.edit, path_w.ptr);
        updateSpaceInfo(state);
    }
}

fn updateSpaceInfo(state: *State) void {
    if (state.required_label == null or state.available_label == null) return;

    const path = readEditText(state) catch null;
    const target = path orelse state.default_dir;
    const required_mb = (state.required_bytes + 1024 * 1024 - 1) / (1024 * 1024);

    const required_text = std.fmt.allocPrint(state.allocator, "Space required: {d} MB", .{required_mb}) catch return;
    const required_w = std.unicode.wtf8ToWtf16LeAllocZ(state.allocator, required_text) catch return;
    _ = SetWindowTextW(state.required_label, required_w.ptr);

    var available_mb: u64 = 0;
    var available_known = false;
    if (pathRoot(state.allocator, target)) |root| {
        const root_w = std.unicode.wtf8ToWtf16LeAllocZ(state.allocator, root) catch null;
        if (root_w) |wide| {
            var free_bytes: u64 = 0;
            if (GetDiskFreeSpaceExW(wide.ptr, &free_bytes, null, null) != 0) {
                available_mb = free_bytes / (1024 * 1024);
                available_known = true;
            }
        }
    }

    if (available_known) {
        const available_text = std.fmt.allocPrint(state.allocator, "Space available: {d} MB", .{available_mb}) catch return;
        const available_w = std.unicode.wtf8ToWtf16LeAllocZ(state.allocator, available_text) catch return;
        _ = SetWindowTextW(state.available_label, available_w.ptr);
    } else {
        const available_w = std.unicode.wtf8ToWtf16LeStringLiteral("Space available: unknown");
        _ = SetWindowTextW(state.available_label, available_w);
    }
}

fn readEditText(state: *State) !?[]const u8 {
    const length = GetWindowTextLengthW(state.edit);
    if (length <= 0) return null;

    const buffer = try state.allocator.alloc(u16, @intCast(length + 1));
    const copied = GetWindowTextW(state.edit, buffer.ptr, length + 1);
    if (copied <= 0) return null;

    return try std.unicode.wtf16LeToWtf8Alloc(state.allocator, buffer[0..@intCast(copied)]);
}

fn createControl(
    parent: ?*anyopaque,
    class_name: windows.LPCWSTR,
    text: ?windows.LPCWSTR,
    style: u32,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    id: usize,
    font: ?*anyopaque,
) ?*anyopaque {
    const control = CreateWindowExW(
        0,
        class_name,
        text,
        style,
        x,
        y,
        width,
        height,
        parent,
        @ptrFromInt(id),
        GetModuleHandleW(null),
        null,
    );
    if (control != null and font != null) {
        _ = SendMessageW(control, wm_setfont, @intFromPtr(font.?), 1);
    }
    return control;
}

fn createFont(dpi: c_int, points: c_int, weight: c_int) ?*anyopaque {
    const height = -@divTrunc(points * dpi, 72);
    return CreateFontW(
        height,
        0,
        0,
        0,
        weight,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        std.unicode.wtf8ToWtf16LeStringLiteral("Segoe UI"),
    );
}

fn scale(value: c_int, dpi: c_int) c_int {
    return @divTrunc(value * dpi, 96);
}

fn getState(hwnd: ?*anyopaque) ?*State {
    const value = GetWindowLongPtrW(hwnd, gwlp_userdata);
    if (value == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(value)));
}

fn pathRoot(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') {
        const root = allocator.alloc(u8, 3) catch return null;
        root[0] = path[0];
        root[1] = ':';
        root[2] = '\\';
        return root;
    }
    if (std.fs.path.isAbsolute(path)) return path;
    return null;
}

fn taskDialog(
    allocator: std.mem.Allocator,
    title: []const u8,
    instruction: []const u8,
    content: []const u8,
    buttons: u32,
    icon: ?*const anyopaque,
) c_int {
    const title_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, title) catch return 0;
    const instruction_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, instruction) catch return 0;
    const content_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, content) catch return 0;

    var button: c_int = 0;
    const result = TaskDialog(null, null, title_w.ptr, instruction_w.ptr, content_w.ptr, buttons, icon, &button);
    if (result >= 0) return button;

    const flags: u32 = if ((buttons & tdcbf_cancel) != 0) 0x1 | 0x20 else 0x40;
    return MessageBoxW(null, content_w.ptr, title_w.ptr, flags);
}

fn browseForFolder(
    owner: ?*anyopaque,
    allocator: std.mem.Allocator,
    default_dir: []const u8,
) !?[]const u8 {
    const init_result = CoInitializeEx(null, coinit_apartment_threaded);
    const should_uninitialize = init_result >= 0;
    defer if (should_uninitialize) CoUninitialize();
    if (init_result < 0 and init_result != rpc_e_changed_mode) return null;

    var dialog: ?*IFileOpenDialog = null;
    if (CoCreateInstance(
        &clsid_file_open_dialog,
        null,
        clsctx_inproc_server,
        &iid_file_open_dialog,
        @ptrCast(&dialog),
    ) < 0 or dialog == null) return null;
    defer _ = dialog.?.vtable.Release(dialog.?);

    _ = dialog.?.vtable.SetOptions(dialog.?, fos_pickfolders | fos_forcefilesystem | fos_pathmustexist | fos_nochangedir);

    const title_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, "Select installation directory");
    _ = dialog.?.vtable.SetTitle(dialog.?, title_w.ptr);

    if (default_dir.len > 0) {
        const default_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, default_dir);
        var folder: ?*IShellItem = null;
        if (SHCreateItemFromParsingName(default_w.ptr, null, &iid_shell_item, @ptrCast(&folder)) >= 0 and folder != null) {
            _ = dialog.?.vtable.SetFolder(dialog.?, folder.?);
            _ = folder.?.vtable.Release(folder.?);
        }
    }

    if (dialog.?.vtable.Show(dialog.?, owner) < 0) return null;

    var result: ?*IShellItem = null;
    if (dialog.?.vtable.GetResult(dialog.?, @ptrCast(&result)) < 0 or result == null) return null;
    defer _ = result.?.vtable.Release(result.?);

    var path_w: ?[*:0]u16 = null;
    if (result.?.vtable.GetDisplayName(result.?, sigdn_filesyspath, &path_w) < 0 or path_w == null) return null;
    defer CoTaskMemFree(path_w);

    return try std.unicode.wtf16LeToWtf8Alloc(allocator, std.mem.span(path_w.?));
}
