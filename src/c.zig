pub const ul = @cImport({
    @cInclude("Ultralight/CAPI.h");
    @cInclude("AppCore/CAPI.h");
});

pub const xl = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/keysym.h");
});
