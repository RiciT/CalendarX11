const std = @import("std");
const xl = @import("c.zig").xl;
const cfg = @import("cfg.zig");

pub const Win = struct {
    dpy: *xl.Display,
    win: xl.Window,
    screen: c_int,
    visual: *xl.Visual,
    gc: xl.GC,
    wm_del: xl.Atom,

    stride: usize,
    buf_len: usize,
    buf_raw: [*]u8,
    img: [*c]xl.XImage,

    //create window
    pub fn init() !Win {
        const dpy = xl.XOpenDisplay(null) orelse {
            std.log.err("XOpenDisplay failed – is $DISPLAY set?", .{});
            return error.NoDisplay;
        };
        defer _ = xl.XCloseDisplay(dpy); //runs last declared first: LIFO

        const scr = xl.XDefaultScreen(dpy);
        const root = xl.XRootWindow(dpy, scr);
        const depth = xl.XDefaultDepth(dpy, scr);
        const visual = xl.XDefaultVisual(dpy, scr);
        var wa = std.mem.zeroes(xl.XSetWindowAttributes);
        wa.background_pixel = xl.XBlackPixel(dpy, scr);
        wa.border_pixel = xl.XBlackPixel(dpy, scr);
        wa.bit_gravity = xl.NorthWestGravity;
        wa.colormap = xl.XCreateColormap(dpy, root, visual, xl.AllocNone);

        const win = xl.XCreateWindow(dpy, root, 0, 0, cfg.WIN_W, cfg.WIN_H, 0, depth, xl.InputOutput, visual, xl.CWBackPixel | xl.CWBorderPixel | xl.CWBitGravity | xl.CWColormap, &wa);

        //create wm hints
        var size_hints = std.mem.zeroes(xl.XSizeHints);
        size_hints.width = @intCast(cfg.WIN_W);
        size_hints.height = @intCast(cfg.WIN_H);
        xl.XSetWMNormalHints(dpy, win, &size_hints);
        _ = xl.XStoreName(dpy, win, cfg.WIN_TITLE);

        const class_hint = xl.XAllocClassHint();
        if (class_hint != null) {
            class_hint.*.res_name = @ptrCast(@constCast("xcalendar").ptr);
            class_hint.*.res_class = @ptrCast(@constCast("Xcalendar").ptr);
            _ = xl.XSetClassHint(dpy, win, class_hint);
            _ = xl.XFree(class_hint);
        }

        _ = xl.XSelectInput(
            dpy,
            win,
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
        const stride: usize = @as(usize, cfg.WIN_W) * 4;
        const buf_len: usize = stride * @as(usize, cfg.WIN_H);

        const buf_raw = std.c.malloc(buf_len) orelse return error.OutOfMemory;
        @memset(@as([*]u8, @ptrCast(buf_raw))[0..buf_len], 0);

        const img = xl.XCreateImage(
            dpy,
            visual,
            @intCast(depth),
            xl.ZPixmap,
            0, //offset
            @ptrCast(buf_raw), //data – XDestroyImage takes ownership
            cfg.WIN_W,
            cfg.WIN_H,
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

        return Win{
            .dpy = dpy,
            .win = win,
            .screen = scr,
            .visual = visual,
            .gc = gc,
            .wm_del = wm_del,
            .stride = stride,
            .buf_len = buf_len,
            .buf_raw = @ptrCast(buf_raw),
            .img = img,
        };
    }

    pub fn deinit(self: *Win) void {
        _ = xl.XDestroyWindow(self.dpy, self.win);
        _ = xl.XCloseDisplay(self.dpy);
    }
};
