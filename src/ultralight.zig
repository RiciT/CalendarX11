const std = @import("std");

const ul = @import("c.zig").ul;
const xl = @import("c.zig").xl;
const cfg = @import("cfg.zig");

//shared state
var g_should_exit = std.atomic.Value(bool).init(false);
var g_page_ready = std.atomic.Value(bool).init(false);
var g_ui_ready = std.atomic.Value(bool).init(false);

pub const Ultralight = struct {
    config: ul.ULConfig,
    renderer: ul.ULRenderer,
    view_config: ul.ULViewConfig,
    view: ul.ULView,
    g_should_exit: *std.atomic.Value(bool),
    g_page_ready: *std.atomic.Value(bool),
    g_ui_ready: *std.atomic.Value(bool),

    pub fn init() !Ultralight {
        //enable platform subsystems provided by AppCore BEFORE creating the renderer
        ul.ulEnablePlatformFontLoader();
        {
            const fs_path = ul.ulCreateString("/");
            defer ul.ulDestroyString(fs_path);
            ul.ulEnablePlatformFileSystem(fs_path);
        }

        {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
            defer allocator.free(exe_dir);

            const UL_LOG_DIR = try std.fs.path.joinZ(allocator, &[_][]const u8{ exe_dir, "ultralight.log" });
            defer allocator.free(UL_LOG_DIR);

            const log_path = ul.ulCreateString(UL_LOG_DIR);
            defer ul.ulDestroyString(log_path);
            ul.ulEnableDefaultLogger(log_path);
        }

        //ultralight renderer
        const config = ul.ulCreateConfig();
        {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
            defer allocator.free(exe_dir);

            const RP = try std.fs.path.joinZ(allocator, &[_][]const u8{ exe_dir, "resources/" });
            defer allocator.free(RP);

            const rp = ul.ulCreateString(RP.ptr);
            defer ul.ulDestroyString(rp);
            ul.ulConfigSetResourcePathPrefix(config, rp);
        }

        const renderer = ul.ulCreateRenderer(config);

        //ultralight view
        const vcfg = ul.ulCreateViewConfig();
        ul.ulViewConfigSetInitialDeviceScale(vcfg, 1.0);
        ul.ulViewConfigSetIsTransparent(vcfg, false);

        const view = ul.ulCreateView(renderer, cfg.WIN_W, cfg.WIN_H, vcfg, null);

        ul.ulViewSetFinishLoadingCallback(view, cbFinishLoad, null);
        ul.ulViewSetDOMReadyCallback(view, cbDOMReady, null);
        ul.ulViewFocus(view);

        //navigate to the Vite dev server.
        {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
            defer allocator.free(exe_dir);

            const VITE_URL = try std.fs.path.joinZ(allocator, &[_][]const u8{ "file:///", exe_dir, "dist/index.html" });
            defer allocator.free(VITE_URL);

            const url = ul.ulCreateString(VITE_URL.ptr);
            defer ul.ulDestroyString(url);
            ul.ulViewLoadURL(view, url);

            std.log.info("Navigating to {s}...", .{VITE_URL});
        }

        return Ultralight{
            .config = config,
            .renderer = renderer,
            .view_config = vcfg,
            .view = view,
            .g_should_exit = &g_should_exit,
            .g_page_ready = &g_page_ready,
            .g_ui_ready = &g_ui_ready,
        };
    }

    pub fn deinit(self: *Ultralight) void {
        ul.ulDestroyView(self.view);
        ul.ulDestroyViewConfig(self.view_config);
        ul.ulDestroyRenderer(self.renderer);
        ul.ulDestroyConfig(self.config);
    }

    //ultralight callbacks
    fn cbFinishLoad(
        _: ?*anyopaque,
        _: ul.ULView,
        _: c_ulonglong, // frame_id
        is_main_frame: bool,
        _: ul.ULString, // url
    ) callconv(.c) void {
        if (is_main_frame) {
            g_page_ready.store(true, .release);
            std.log.info("Vite page loaded successfully.", .{});
        }
    }

    //fires when the DOM is ready
    fn cbDOMReady(
        _: ?*anyopaque,
        view: ul.ULView,
        _: c_ulonglong,
        is_main_frame: bool,
        _: ul.ULString,
    ) callconv(.c) void {
        if (!is_main_frame) return;
        std.log.info("DOM ready - injecting bridge...", .{});

        const ctx = ul.ulViewLockJSContext(view);
        defer ul.ulViewUnlockJSContext(view);

        const global = ul.JSContextGetGlobalObject(ctx);

        const save_name = ul.JSStringCreateWithUTF8CString("__saveEvent");
        defer ul.JSStringRelease(save_name);
        ul.JSObjectSetProperty(
            ctx, global, save_name,
            ul.JSObjectMakeFunctionWithCallback(ctx, save_name, saveEventCB),
            0, null, // attributes=none, no exception out-param
        );

        const exit_name = ul.JSStringCreateWithUTF8CString("__exitApp");
        defer ul.JSStringRelease(exit_name);
        ul.JSObjectSetProperty(
            ctx, global, exit_name,
            ul.JSObjectMakeFunctionWithCallback(ctx, exit_name, exitAppCB),
            0, null,
        );

        const ready_name = ul.JSStringCreateWithUTF8CString("__notifyReady");
        defer ul.JSStringRelease(ready_name);
        ul.JSObjectSetProperty(
            ctx, global, ready_name,
            ul.JSObjectMakeFunctionWithCallback(ctx, ready_name, notifyReadyCB), 0, null,
        );

        std.log.info("JS bridge: __saveEvent and __exitApp injected.", .{});
    }

    //window.__saveEvent(jsonString)
    //appends one JSON object - a single line - to events.jsonl in the cwd.
    fn saveEventCB(
        ctx: ul.JSContextRef,
        _: ul.JSObjectRef,
        _: ul.JSObjectRef,
        argument_count: usize,
        arguments: [*c]const ul.JSValueRef,
        _: [*c]ul.JSValueRef,
    ) callconv(.c) ul.JSValueRef {
        //there cannot be 'try'-s in a callconv function so we need to export it to an inner function
        saveInnerEvent(ctx, argument_count, arguments) catch |err| {
            std.log.err("JS Bridge: saveEvent failed: {}", .{err});
        };
        return ul.JSValueMakeUndefined(ctx);
    }

    fn saveInnerEvent(ctx: ul.JSContextRef, argument_count: usize, arguments: [*c]const ul.JSValueRef) !void {
        if (argument_count == 0) return;

        const js_str = ul.JSValueToStringCopy(ctx, arguments[0], null);
        defer ul.JSStringRelease(js_str);

        //event buffer - 8k should be much more than enough
        var buf: [8192]u8 = undefined;
        const written = ul.JSStringGetUTF8CString(js_str, &buf, buf.len);
        if (written == 0) return;
        const json = buf[0 .. written - 1]; //JSStringGetUTF8CString includes the \0

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(exe_dir);

        const path = try std.fs.path.joinZ(allocator, &[_][]const u8{ exe_dir, "events.jsonl" });
        defer allocator.free(path);

        const file = std.fs.openFileAbsoluteZ(path, .{ .mode = .write_only }) catch
            try std.fs.createFileAbsoluteZ(path, .{});
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(json);
        try file.writeAll("\n");

        std.log.info("JS bridge: event saved ({d} bytes).", .{json.len});
    }

    //window.__exitApp()
    //signals the main loop to stop on the next tick.
    fn exitAppCB(
        ctx: ul.JSContextRef,
        _: ul.JSObjectRef,
        _: ul.JSObjectRef,
        _: usize,
        _: [*c]const ul.JSValueRef,
        _: [*c]ul.JSValueRef,
    ) callconv(.c) ul.JSValueRef {
        g_should_exit.store(true, .release);
        std.log.info("JS bridge: exit requested.", .{});
        return ul.JSValueMakeUndefined(ctx);
    }

    fn notifyReadyCB(
        ctx: ul.JSContextRef,
        _: ul.JSObjectRef,
        _: ul.JSObjectRef,
        _: usize,
        _: [*c]const ul.JSValueRef,
        _: [*c]ul.JSValueRef,
    ) callconv(.c) ul.JSValueRef {
        g_ui_ready.store(true, .release);
        std.log.info("JS Bridge: first frame ready", .{});
        return ul.JSValueMakeUndefined(ctx);
    }

    //input translation helpers
    pub fn xlBtnToUL(btn: c_uint) ul.ULMouseButton {
        return switch (btn) {
            1 => ul.kMouseButton_Left,
            2 => ul.kMouseButton_Middle,
            3 => ul.kMouseButton_Right,
            else => ul.kMouseButton_None,
        };
    }

    //ultralight modifier bit-flags
    const UL_MOD_ALT: u32 = 1 << 0;
    const UL_MOD_CTRL: u32 = 1 << 1;
    const UL_MOD_META: u32 = 1 << 2;
    const UL_MOD_SHIFT: u32 = 1 << 3;

    fn xlModToUL(state: c_uint) u32 {
        var m: u32 = 0;
        if (state & xl.ShiftMask != 0) m |= UL_MOD_SHIFT;
        if (state & xl.ControlMask != 0) m |= UL_MOD_CTRL;
        if (state & xl.Mod1Mask != 0) m |= UL_MOD_ALT;
        if (state & xl.Mod4Mask != 0) m |= UL_MOD_META;
        return m;
    }

    //translate X11 keysym to a win virtual key code.
    //ultralight uses the win VK table internally on all platforms.
    pub fn xlKsToVK(ks: xl.KeySym) i32 {
        return switch (ks) {
            xl.XK_BackSpace => 0x08,
            xl.XK_Tab => 0x09,
            xl.XK_Return => 0x0D,
            xl.XK_Shift_L, xl.XK_Shift_R => 0x10,
            xl.XK_Control_L, xl.XK_Control_R => 0x11,
            xl.XK_Alt_L, xl.XK_Alt_R => 0x12,
            xl.XK_Pause => 0x13,
            xl.XK_Caps_Lock => 0x14,
            xl.XK_Escape => 0x1B,
            xl.XK_space => 0x20,
            xl.XK_Prior => 0x21, // Page Up
            xl.XK_Next => 0x22, // Page Down
            xl.XK_End => 0x23,
            xl.XK_Home => 0x24,
            xl.XK_Left => 0x25,
            xl.XK_Up => 0x26,
            xl.XK_Right => 0x27,
            xl.XK_Down => 0x28,
            xl.XK_Insert => 0x2D,
            xl.XK_Delete => 0x2E,
            xl.XK_0...xl.XK_9 => @intCast(ks - xl.XK_0 + 0x30),
            xl.XK_a...xl.XK_z => @intCast(ks - xl.XK_a + 0x41),
            xl.XK_A...xl.XK_Z => @intCast(ks - xl.XK_A + 0x41),
            xl.XK_F1...xl.XK_F12 => @intCast(ks - xl.XK_F1 + 0x70),
            xl.XK_KP_0...xl.XK_KP_9 => @intCast(ks - xl.XK_KP_0 + 0x60),
            xl.XK_KP_Enter => 0x0D,
            xl.XK_KP_Add => 0x6B,
            xl.XK_KP_Subtract => 0x6D,
            xl.XK_KP_Multiply => 0x6A,
            xl.XK_KP_Divide => 0x6F,
            xl.XK_KP_Decimal => 0x6E,
            else => 0,
        };
    }

    //fire a RawKeyDown or KeyUp event, then (on key-down) synthesise a char event
    //for printable ASCII so that <input> elements actually receive text.
    pub fn fireKey(
        view: ul.ULView,
        kind: ul.ULKeyEventType,
        state: c_uint,
        ks: xl.KeySym,
        native: i32,
    ) void {
        const empty = ul.ulCreateString("");
        defer ul.ulDestroyString(empty);

        const ke = ul.ulCreateKeyEvent(
            kind,
            xlModToUL(state),
            xlKsToVK(ks),
            native,
            empty,
            empty, // text, unmodified_text (empty for raw events)
            false, // is_keypad
            false, // is_auto_repeat
            false, // is_system_key
        );
        ul.ulViewFireKeyEvent(view, ke);
        ul.ulDestroyKeyEvent(ke);
    }

    //separate firechar to handle - shift/ctrl and etc
    pub fn fireChar(view: ul.ULView, text: [*]const u8, len:usize) void {
        var buf: [64]u8 = undefined;
        if (len == 0 or len >= buf.len) return;
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;
        const ul_text = ul.ulCreateString(&buf);
        defer ul.ulDestroyString(ul_text);
        const ce = ul.ulCreateKeyEvent(
            ul.kKeyEventType_Char,
            0, 0, 0,
            ul_text, ul_text,
            false, false, false,
        );
        ul.ulViewFireKeyEvent(view, ce);
        ul.ulDestroyKeyEvent(ce);
    }
};
