//imports
const std = @import("std");

const xl = @import("c.zig").xl;
const ul = @import("c.zig").ul;
const cfg = @import("cfg.zig");
const Xwin = @import("xwindow.zig").Win;
const Ultra = @import("ultralight.zig").Ultralight;

//entry point
pub fn main() !void {
    //x11
    var win = try Xwin.init();
    defer win.deinit();

    //ultralight cfg
    var ultra = try Ultra.init();
    defer ultra.deinit();

    var running = true;
    var ev: xl.XEvent = undefined;

    //spin until the page is fully loaded - no sleep so Ultralight can bootstrap as fast as possible - spin on first frame
    std.log.info("Waiting for first frame...", .{});
    var spin_ev: xl.XEvent = undefined;
    while (!ultra.g_ui_ready.load(.acquire)) {
        while (xl.XPending(win.dpy) > 0) {
            _ = xl.XNextEvent(win.dpy, &spin_ev);
            if (spin_ev.type == xl.ClientMessage and spin_ev.xclient.data.l[0] == @as(c_long, @intCast(win.wm_del))) {
                return; //win closed during load
            }
        }
        ul.ulUpdate(ultra.renderer);
        ul.ulViewSetNeedsPaint(ultra.view, true);
        ul.ulRender(ultra.renderer);
        ul.ulUpdate(ultra.renderer);
        ul.ulViewSetNeedsPaint(ultra.view, true);
        ul.ulRender(ultra.renderer);
        //blit whatever is in the surface so partial renders show through
        const surf = ul.ulViewGetSurface(ultra.view);
        if (surf != null) {
            const bmp = ul.ulBitmapSurfaceGetBitmap(surf);
            const px = ul.ulBitmapLockPixels(bmp);
            if (px) |p| {
                const row_bytes: usize = @intCast(ul.ulBitmapGetRowBytes(bmp));
                const r_mask = win.visual.*.red_mask;
                const g_mask = win.visual.*.green_mask;
                const b_mask = win.visual.*.blue_mask;
                var y: usize = 0;
                while (y < cfg.WIN_H) : (y += 1) {
                    const src_row = @as([*]const u8, @ptrCast(p)) + (y * row_bytes);
                    const dst_row = @as([*]u32, @ptrCast(@alignCast(win.buf_raw))) + (y * (win.stride / 4));
                    var x: usize = 0;
                    while (x < cfg.WIN_W) : (x += 1) {
                        const b: u32 = src_row[x * 4 + 0];
                        const g: u32 = src_row[x * 4 + 1];
                        const r: u32 = src_row[x * 4 + 2];
                        dst_row[x] = (r << @intCast(@ctz(r_mask))) |
                            (g << @intCast(@ctz(g_mask))) |
                            (b << @intCast(@ctz(b_mask)));
                    }
                }
            }
            ul.ulBitmapUnlockPixels(bmp);
            _ = xl.XPutImage(win.dpy, win.win, win.gc, win.img, 0, 0,
                0, 0, cfg.WIN_W, cfg.WIN_H);
            _ = xl.XFlush(win.dpy);
        }
        std.Thread.yield() catch {};
    }
    std.log.info("First frame ready, entering main loop.", .{});

    //main loop
    while (running) {
        //X11 dipatch
        while (xl.XPending(win.dpy) > 0) {
            _ = xl.XNextEvent(win.dpy, &ev);

            switch (ev.type) {
                xl.ClientMessage => {
                    //wm sent close button
                    if (ev.xclient.data.l[0] ==
                        @as(c_long, @intCast(win.wm_del)))
                        running = false;
                },

                xl.Expose => {
                    //handled by unconditional blit
                },

                xl.KeyPress => {
                    const ks = xl.XLookupKeysym(&ev.xkey, 0);
                    if (ks == xl.XK_Escape) {
                        running = false;
                        break;
                    }
                    Ultra.fireKey(ultra.view, ul.kKeyEventType_RawKeyDown, ev.xkey.state, ks, @intCast(ev.xkey.keycode));
                },

                xl.KeyRelease => {
                    const ks = xl.XLookupKeysym(&ev.xkey, 0);
                    Ultra.fireKey(ultra.view, ul.kKeyEventType_KeyUp, ev.xkey.state, ks, @intCast(ev.xkey.keycode));
                },

                xl.ButtonPress => {
                    const btn = ev.xbutton.button;
                    if (btn == 4 or btn == 5) {
                        //vertical scroll wheel
                        const dy: c_int = if (btn == 4) 40 else -40;
                        const se = ul.ulCreateScrollEvent(ul.kScrollEventType_ScrollByPixel, 0, dy);
                        ul.ulViewFireScrollEvent(ultra.view, se);
                        ul.ulDestroyScrollEvent(se);
                    } else if (btn == 6 or btn == 7) {
                        //horizontal scroll wheel
                        const dx: c_int = if (btn == 6) -40 else 40;
                        const se = ul.ulCreateScrollEvent(ul.kScrollEventType_ScrollByPixel, dx, 0);
                        ul.ulViewFireScrollEvent(ultra.view, se);
                        ul.ulDestroyScrollEvent(se);
                    } else {
                        const me = ul.ulCreateMouseEvent(ul.kMouseEventType_MouseDown, ev.xbutton.x, ev.xbutton.y, Ultra.xlBtnToUL(btn));
                        ul.ulViewFireMouseEvent(ultra.view, me);
                        ul.ulDestroyMouseEvent(me);
                    }
                },

                xl.ButtonRelease => {
                    const btn = ev.xbutton.button;
                    if (btn != 4 and btn != 5 and btn != 6 and btn != 7) {
                        const me = ul.ulCreateMouseEvent(ul.kMouseEventType_MouseUp, ev.xbutton.x, ev.xbutton.y, Ultra.xlBtnToUL(btn));
                        ul.ulViewFireMouseEvent(ultra.view, me);
                        ul.ulDestroyMouseEvent(me);
                    }
                },

                xl.MotionNotify => {
                    const me = ul.ulCreateMouseEvent(ul.kMouseEventType_MouseMoved, ev.xmotion.x, ev.xmotion.y, ul.kMouseButton_None);
                    ul.ulViewFireMouseEvent(ultra.view, me);
                    ul.ulDestroyMouseEvent(me);
                },

                xl.ConfigureNotify => {
                    //windor war resized for now dont handle it later
                    // ul.ulViewResize(view, new_w, new_h);
                },

                xl.FocusIn => {
                    ul.ulViewFocus(ultra.view);
                },

                xl.FocusOut => {
                    ul.ulViewUnfocus(ultra.view);
                },

                else => {},
            }
        }

        //ultralight tick
        ul.ulUpdate(ultra.renderer); //run timers, network callbacks, JS microtasks
        ul.ulViewSetNeedsPaint(ultra.view, true);
        ul.ulRender(ultra.renderer); //paint any views that are marked dirty
        //run twice so we catch any asyncs needed
        ul.ulUpdate(ultra.renderer);
        ul.ulViewSetNeedsPaint(ultra.view, true);
        ul.ulRender(ultra.renderer);

        //blit to X11
        const surf = ul.ulViewGetSurface(ultra.view);
        //prevent segfaults by checking if the surface exists yet
        //dont need to do it twice just simply do blit every frame
       if (surf != null) {
            ul.ulSurfaceClearDirtyBounds(surf);
            const bmp = ul.ulBitmapSurfaceGetBitmap(surf);
            const px = ul.ulBitmapLockPixels(bmp);
            if (px) |p| {
                const row_bytes: usize = @intCast(ul.ulBitmapGetRowBytes(bmp));
                const r_mask = win.visual.*.red_mask;
                const g_mask = win.visual.*.green_mask;
                const b_mask = win.visual.*.blue_mask;
                var y: usize = 0;
                while (y < cfg.WIN_H) : (y += 1) {
                    const src_row = @as([*]const u8, @ptrCast(p)) + (y * row_bytes);
                    const dst_row = @as([*]u32, @ptrCast(@alignCast(win.buf_raw))) + (y * (win.stride / 4));
                    var x: usize = 0;
                    while (x < cfg.WIN_W) : (x += 1) {
                        const b: u32 = src_row[x * 4 + 0];
                        const g: u32 = src_row[x * 4 + 1];
                        const r: u32 = src_row[x * 4 + 2];
                        dst_row[x] = (r << @intCast(@ctz(r_mask))) |
                            (g << @intCast(@ctz(g_mask))) |
                            (b << @intCast(@ctz(b_mask)));
                    }
                }
            }
            ul.ulBitmapUnlockPixels(bmp);
            _ = xl.XPutImage(win.dpy, win.win, win.gc, win.img, 0, 0,
                0, 0, cfg.WIN_W, cfg.WIN_H);
            _ = xl.XFlush(win.dpy);
        }

        //60 hz tick
        if (ultra.g_should_exit.load(.acquire)) running = false;
        std.Thread.sleep(16 * std.time.ns_per_ms);
    }
}
