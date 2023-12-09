const Surface = @import("Surface.zig").Surface;

pub const Font = struct {
    surf: Surface,
    w: i32,
    h: i32,
    dx: i32,
    dy: i32,

    pub fn load(comptime path: []const u8) !Font {
        const surf = try Surface.load(path);
        const w = @divTrunc(surf.w, 16);
        const h = @divTrunc(surf.h, 6);
        return Font{
            .surf = surf,
            .w = w,
            .h = h,
            .dx = 6, // XXX
            .dy = h,
        };
    }
};
