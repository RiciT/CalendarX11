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
            const log_path = ul.ulCreateString("./ultralight.log");
            defer ul.ulDestroyString(log_path);
            ul.ulEnableDefaultLogger(log_path);
        }
        //ultralight renderer
        const config = ul.ulCreateConfig();
        {
            const rp = ul.ulCreateString("/home/br4mos/PERSONAL/Developing/CalendarX11/deps/ultralight/resources/");
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
            const url = ul.ulCreateString(cfg.VITE_URL);
            defer ul.ulDestroyString(url);
            ul.ulViewLoadURL(view, url);
        }

        std.log.info("Navigating to {s} …", .{cfg.VITE_URL});

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
        if (argument_count == 0) return ul.JSValueMakeUndefined(ctx);

        const js_str = ul.JSValueToStringCopy(ctx, arguments[0], null);
        defer ul.JSStringRelease(js_str);

        //event buffer - 8k should be much more than enough
        var buf: [8192]u8 = undefined;
        const written = ul.JSStringGetUTF8CString(js_str, &buf, buf.len);
        if (written == 0) return ul.JSValueMakeUndefined(ctx);
        const json = buf[0 .. written - 1]; //JSStringGetUTF8CString includes the \0

        //open or create events.jsonl, seek to end, append.
        const file = std.fs.cwd().openFile("events.jsonl", .{ .mode = .write_only }) catch
            std.fs.cwd().createFile("events.jsonl", .{}) catch {
            std.log.err("JS bridge: could not open/create events.jsonl", .{});
            return ul.JSValueMakeUndefined(ctx);
        };
        defer file.close();
        file.seekFromEnd(0) catch {};
        file.writeAll(json) catch {};
        file.writeAll("\n") catch {};

        std.log.info("JS bridge: event saved ({d} bytes).", .{json.len});
        return ul.JSValueMakeUndefined(ctx);
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

        //synthesise a Char event for printable ASCII on key-down.
        //extend this range (or use XLookupString) for non-ASCII / compose input.
        if (kind == ul.kKeyEventType_RawKeyDown and ks >= 0x20 and ks <= 0x7E) {
            var ch_buf = [2]u8{ @intCast(ks & 0xFF), 0 };
            const text = ul.ulCreateString(&ch_buf);
            defer ul.ulDestroyString(text);

            const ce = ul.ulCreateKeyEvent(
                ul.kKeyEventType_Char,
                xlModToUL(state),
                0,
                0,
                text,
                text,
                false,
                false,
                false,
            );
            ul.ulViewFireKeyEvent(view, ce);
            ul.ulDestroyKeyEvent(ce);
        }
    }
};
