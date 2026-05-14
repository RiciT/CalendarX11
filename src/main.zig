//imports
const std = @import("std");

const ul = @cImport({
    @cInclude("Ultralight/CAPI.h");
    @cInclude("AppCore/CAPI.h");
});

const xl = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/keysym.h");
});

//consts
const VITE_URL  = "http://localhost:5173";
const WIN_W: c_uint = 1280;
const WIN_H: c_uint = 720;
const WIN_TITLE = "Vite × Ultralight";

//shared state
var g_repaint = std.atomic.Value(bool).init(true);

//ultralight callbacks
fn cbFinishLoad(
    _: ?*anyopaque,
    _: ul.ULView,
    _: c_ulonglong, // frame_id
    is_main_frame: bool,
    _: ul.ULString, // url
) callconv(.c) void {
    if (is_main_frame) {
        g_repaint.store(true, .release);
        std.log.info("Vite page loaded successfully.", .{});
    }
}

//input translation helpers
fn xlBtnToUL(btn: c_uint) ul.ULMouseButton {
    return switch (btn) {
        1    => ul.kMouseButton_Left,
        2    => ul.kMouseButton_Middle,
        3    => ul.kMouseButton_Right,
        else => ul.kMouseButton_None,
    };
}

//ultralight modifier bit-flags
const UL_MOD_ALT   : u32 = 1 << 0;
const UL_MOD_CTRL  : u32 = 1 << 1;
const UL_MOD_META  : u32 = 1 << 2;
const UL_MOD_SHIFT : u32 = 1 << 3;

fn xlModToUL(state: c_uint) u32 {
    var m: u32 = 0;
    if (state & xl.ShiftMask   != 0) m |= UL_MOD_SHIFT;
    if (state & xl.ControlMask != 0) m |= UL_MOD_CTRL;
    if (state & xl.Mod1Mask    != 0) m |= UL_MOD_ALT;
    if (state & xl.Mod4Mask    != 0) m |= UL_MOD_META;
    return m;
}

//translate X11 keysym to a win virtual key code.
//ultralight uses the win VK table internally on all platforms.
fn xlKsToVK(ks: xl.KeySym) i32 {
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
fn fireKey(
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
        empty, empty, // text, unmodified_text (empty for raw events)
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
            0, 0,
            text, text,
            false, false, false,
        );
        ul.ulViewFireKeyEvent(view, ce);
        ul.ulDestroyKeyEvent(ce);
    }
}

//entry point
pub fn main() !void {

    //x11
    const dpy = xl.XOpenDisplay(null) orelse {
        std.log.err("XOpenDisplay failed – is $DISPLAY set?", .{});
        return error.NoDisplay;
    };
    defer _ = xl.XCloseDisplay(dpy); //runs last declared first: LIFO

    const scr = xl.XDefaultScreen(dpy);
    const root = xl.XRootWindow(dpy, scr);
    const depth = xl.XDefaultDepth(dpy, scr);
    const visual = xl.XDefaultVisual(dpy, scr);

    const win = xl.XCreateSimpleWindow(
        dpy, root,
        0, 0, WIN_W, WIN_H,
        0, // border width
        xl.XBlackPixel(dpy, scr), //border colour
        xl.XBlackPixel(dpy, scr), //background colour (Ultralight paints it)
    );
    _ = xl.XStoreName(dpy, win, WIN_TITLE);
    _ = xl.XSelectInput(dpy, win,
        xl.ExposureMask |
        xl.StructureNotifyMask |
        xl.KeyPressMask |
        xl.KeyReleaseMask |
        xl.ButtonPressMask |
        xl.ButtonReleaseMask |
        xl.PointerMotionMask,
    );
    _ = xl.XMapWindow(dpy, win);

    //intercept the window-manager close button.
    var wm_del = xl.XInternAtom(dpy, "WM_DELETE_WINDOW", xl.False);
    _ = xl.XSetWMProtocols(dpy, win, &wm_del, 1);

    _ = xl.XFlush(dpy);

    const gc = xl.XCreateGC(dpy, win, 0, null);
    defer _ = xl.XFreeGC(dpy, gc);

    //pixel buffer
    //we hand the raw pointer to XCreateImage; XDestroyImage will free it, so
    //we must allocate it with malloc (C heap), not the Zig allocator.
    const stride: usize = @as(usize, WIN_W) * 4;
    const buf_len: usize = stride * @as(usize, WIN_H);

    const buf_raw = std.c.malloc(buf_len) orelse return error.OutOfMemory;
    @memset(@as([*]u8, @ptrCast(buf_raw))[0..buf_len], 0);

    const img = xl.XCreateImage(
        dpy, visual,
        @intCast(depth),
        xl.ZPixmap,
        0, //offset
        @ptrCast(buf_raw), //data – XDestroyImage takes ownership
        WIN_W, WIN_H,
        32, //bitmap_pad: align rows to 32-bit words
        @intCast(stride), //bytes_per_line
    ) orelse return error.XCreateImageFailed;
    //XDestroyImage frees both the XImage struct and img->data
    defer {
        //prevent X11 from freeing the buffer with C's free()
        img.*.data = null;

        //destroy the XImage struct
        if (img.*.f.destroy_image) |destroy_fn| {
            _ = destroy_fn(img);
        }
    }

    //enable platform subsystems provided by AppCore BEFORE creating the renderer
    ul.ulEnablePlatformFontLoader();
    {
        const fs_path = ul.ulCreateString("./");
        defer ul.ulDestroyString(fs_path);
        ul.ulEnablePlatformFileSystem(fs_path);
    }

    {
        const log_path = ul.ulCreateString("./ultralight.log");
        defer ul.ulDestroyString(log_path);
        ul.ulEnableDefaultLogger(log_path);
    }
    //ultralight renderer
    const cfg = ul.ulCreateConfig();
    defer ul.ulDestroyConfig(cfg);
    {
        const rp = ul.ulCreateString("resources/");
        defer ul.ulDestroyString(rp);
        ul.ulConfigSetResourcePathPrefix(cfg, rp);
    }

    const renderer = ul.ulCreateRenderer(cfg);
    defer ul.ulDestroyRenderer(renderer);

    //ultralight view
    const vcfg = ul.ulCreateViewConfig();
    defer ul.ulDestroyViewConfig(vcfg);
    ul.ulViewConfigSetInitialDeviceScale(vcfg, 1.0);
    ul.ulViewConfigSetIsTransparent(vcfg, false);

    const view = ul.ulCreateView(renderer, WIN_W, WIN_H, vcfg, null);
    defer ul.ulDestroyView(view);

    ul.ulViewSetFinishLoadingCallback(view, cbFinishLoad, null);
    ul.ulViewFocus(view);

    //navigate to the Vite dev server.
    {
        const url = ul.ulCreateString(VITE_URL);
        defer ul.ulDestroyString(url);
        ul.ulViewLoadURL(view, url);
    }

    std.log.info("Navigating to {s} …", .{VITE_URL});


    var running = true;
    var ev: xl.XEvent = undefined;

    //main loop
    while (running) {

        //X11 dipatch
        while (xl.XPending(dpy) > 0) {
            _ = xl.XNextEvent(dpy, &ev);

            switch (ev.@"type") {

                xl.ClientMessage => {
                    //wm sent close button
                    if (ev.xclient.data.l[0] ==
                            @as(c_long, @intCast(wm_del)))
                        running = false;
                },

                xl.Expose => {
                    //win became visible, uncovered
                    g_repaint.store(true, .release);
                },

                xl.KeyPress => {
                    const ks = xl.XLookupKeysym(&ev.xkey, 0);
                    if (ks == xl.XK_Escape) { running = false; break; }
                    fireKey(view, ul.kKeyEventType_RawKeyDown,
                            ev.xkey.state, ks,
                            @intCast(ev.xkey.keycode));
                },

                xl.KeyRelease => {
                    const ks = xl.XLookupKeysym(&ev.xkey, 0);
                    fireKey(view, ul.kKeyEventType_KeyUp,
                            ev.xkey.state, ks,
                            @intCast(ev.xkey.keycode));
                },

                xl.ButtonPress => {
                    const btn = ev.xbutton.button;
                    if (btn == 4 or btn == 5) {
                        //vertical scroll wheel
                        const dy: c_int = if (btn == 4) 40 else -40;
                        const se = ul.ulCreateScrollEvent(
                            ul.kScrollEventType_ScrollByPixel, 0, dy);
                        ul.ulViewFireScrollEvent(view, se);
                        ul.ulDestroyScrollEvent(se);
                    } else if (btn == 6 or btn == 7) {
                        //horizontal scroll wheel
                        const dx: c_int = if (btn == 6) -40 else 40;
                        const se = ul.ulCreateScrollEvent(
                            ul.kScrollEventType_ScrollByPixel, dx, 0);
                        ul.ulViewFireScrollEvent(view, se);
                        ul.ulDestroyScrollEvent(se);
                    } else {
                        const me = ul.ulCreateMouseEvent(
                            ul.kMouseEventType_MouseDown,
                            ev.xbutton.x, ev.xbutton.y,
                            xlBtnToUL(btn));
                        ul.ulViewFireMouseEvent(view, me);
                        ul.ulDestroyMouseEvent(me);
                    }
                },

                xl.ButtonRelease => {
                    const btn = ev.xbutton.button;
                    if (btn != 4 and btn != 5 and btn != 6 and btn != 7) {
                        const me = ul.ulCreateMouseEvent(
                            ul.kMouseEventType_MouseUp,
                            ev.xbutton.x, ev.xbutton.y,
                            xlBtnToUL(btn));
                        ul.ulViewFireMouseEvent(view, me);
                        ul.ulDestroyMouseEvent(me);
                    }
                },

                xl.MotionNotify => {
                    const me = ul.ulCreateMouseEvent(
                        ul.kMouseEventType_MouseMoved,
                        ev.xmotion.x, ev.xmotion.y,
                        ul.kMouseButton_None);
                    ul.ulViewFireMouseEvent(view, me);
                    ul.ulDestroyMouseEvent(me);
                },

                xl.ConfigureNotify => {
                    //windor war resized for now dont handle it later
                    // ul.ulViewResize(view, new_w, new_h);
                },

                else => {},
            }
        }

        //ultralight tick
        ul.ulUpdate(renderer); //run timers, network callbacks, JS microtasks
        ul.ulRender(renderer); //paint any views that are marked dirty

        //blit to X11
        const surf = ul.ulViewGetSurface(view);
        //prevent segfaults by checking if the surface exists yet
        if (surf != null) {
            const dirty = ul.ulSurfaceGetDirtyBounds(surf);

            if (dirty.right > dirty.left or g_repaint.load(.acquire)) {
                g_repaint.store(false, .release);
                ul.ulSurfaceClearDirtyBounds(surf);

                //copy the Ultralight bgra bitmap into the XImage buffer.
                const bmp = ul.ulBitmapSurfaceGetBitmap(surf);
                const px = ul.ulBitmapLockPixels(bmp);

                if (px) |p| {
                    const row_bytes: usize = @intCast(ul.ulBitmapGetRowBytes(bmp));

                    //copy row-by-row to prevent out-of-bounds panics
                    var y: usize = 0;
                    while (y < WIN_H) : (y += 1) {
                        const src_row = @as([*]const u8, @ptrCast(p))[y * row_bytes .. y * row_bytes + stride];
                        const dst_row = @as([*]u8, @ptrCast(buf_raw))[y * stride .. y * stride + stride];
                        @memcpy(dst_row, src_row);
                    }
                }
                ul.ulBitmapUnlockPixels(bmp);

                _ = xl.XPutImage(dpy, win, gc, img,
                    0, 0, // src x, y
                    0, 0, // dst x, y
                    WIN_W, WIN_H);
                _ = xl.XFlush(dpy);
            }
        }

        const dirty = ul.ulSurfaceGetDirtyBounds(surf);

        if (dirty.right > dirty.left or g_repaint.load(.acquire)) {
            g_repaint.store(false, .release);
            ul.ulSurfaceClearDirtyBounds(surf);

            //copy the Ultralight bgra bitmap into the XImage buffer.
            const bmp = ul.ulBitmapSurfaceGetBitmap(surf);
            const px = ul.ulBitmapLockPixels(bmp);
            if (px) |p| {
                const row_bytes: usize = @intCast(ul.ulBitmapGetRowBytes(bmp));
                const total: usize = row_bytes * @as(usize, WIN_H);
                const dst = @as([*]u8, @ptrCast(buf_raw))[0..total];
                const src = @as([*]const u8, @ptrCast(p))[0..total];
                @memcpy(dst, src);
            }
            ul.ulBitmapUnlockPixels(bmp);

            _ = xl.XPutImage(dpy, win, gc, img,
                0, 0, // src x, y
                0, 0, // dst x, y
                WIN_W, WIN_H);
            _ = xl.XFlush(dpy);
        }

        //60 hz tick
        std.Thread.sleep(16 * std.time.ns_per_ms);
    }
}
