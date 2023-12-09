const std = @import("std");
const Rect = @import("Rect.zig").Rect;
const Font = @import("Font.zig").Font;

pub const Surface = struct {
    w: i32,
    h: i32,
    pixels: []u32,
    pub fn init(w: i32, h: i32) !Surface {
        return .{
            .w = w,
            .h = h,
            .pixels = try std.heap.page_allocator.alloc(u32, @intCast(w * h)),
        };
    }

    const BitReader = struct {
        p: [*]const u8,
        i: u5,
        fn read(self: *BitReader, nbits: u5) u32 {
            var v: u32 = 0;
            var n = nbits;
            while (n > 0) {
                const b = @min(8 - self.i, n);
                n -= b;
                v <<= b;
                v |= (@as(u32, @intCast(self.p[0])) >> self.i) & ((@as(u32, 1) << b) - 1);
                self.i += b;
                if (self.i == 8) self.p += 1;
                self.i &= 7;
            }
            return v;
        }
    };

    pub fn load(comptime path: []const u8) !Surface {
        var reader = BitReader{ .p = @embedFile(path), .i = 0 };
        var surf = try init(
            @intCast(reader.read(16)),
            @intCast(reader.read(16)),
        );
        const color_count = reader.read(8);
        const bits_per_color = @as(u5, @intCast(32 - @clz(color_count)));
        // color table
        const colors = reader.p;
        reader.p += color_count * 4;

        const BITS_D = 9;
        const BITS_L1 = 5;
        const BITS_L2 = 12;
        const MIN_L = 2;

        var i: usize = 0;
        while (i < surf.pixels.len) {
            const d = reader.read(BITS_D);
            if (d == 0) {
                const c = reader.read(bits_per_color);
                @memcpy(@as([*]u8, @ptrCast(surf.pixels.ptr + i))[0..4], colors + c * 4);
                i += 1;
            } else {
                const bits: u5 = if (reader.read(1) == 0) BITS_L1 else BITS_L2;
                const end = i + MIN_L + reader.read(bits);
                while (i < end) {
                    surf.pixels[i] = surf.pixels[i - d];
                    i += 1;
                }
            }
        }
        return surf;
    }

    pub fn deinit(self: *Surface) void {
        std.heap.page_allocator.free(self.pixels);
    }
    pub fn clear(self: *Surface, color: u32) void {
        for (self.pixels) |*p| p.* = color;
    }
    pub fn copy(self: *Surface, s: Surface, r: Rect, x: i32, y: i32) void {
        var rx = r.x;
        var ry = r.y;
        var rw = r.w;
        var rh = r.h;
        var xx = x;
        var yy = y;
        if (xx < 0) {
            rw += xx;
            rx -= xx;
            xx = 0;
        }
        if (rw > self.w - xx) rw = self.w - xx;
        if (y < 0) {
            rh += y;
            ry -= y;
            yy = 0;
        }
        if (rh > self.h - yy) rh = self.h - yy;
        var q = s.pixels.ptr + @as(usize, @intCast(ry * s.w + rx));
        var p = self.pixels.ptr + @as(usize, @intCast(yy * self.w + xx));
        var iy: i32 = 0;
        while (iy < rh) : (iy += 1) {
            var ix: u32 = 0;
            while (ix < rw) : (ix += 1) {
                const c = q[ix];
                if (c & 0xff000000 != 0) p[ix] = c;
            }
            p += @as(usize, @intCast(self.w));
            q += @as(usize, @intCast(s.w));
        }
    }

    pub fn printCentered(self: *Surface, font: Font, x: i32, y: i32, string: []const u8) void {
        const o: i32 = @intCast(string.len);
        self.print(font, x - @divTrunc(o * font.dx, 2), y, string);
    }

    pub fn print(self: *Surface, font: Font, x: i32, y: i32, string: []const u8) void {
        var xx = x;
        var yy = y;
        for (string) |char| {
            switch (char) {
                '\n' => {
                    xx = x;
                    yy += font.dy;
                },
                else => {
                    xx += font.dx;
                },
                33...127 => {
                    self.copy(
                        font.surf,
                        .{
                            .x = (char - 32) % 16 * font.w,
                            .y = (char - 32) / 16 * font.h,
                            .w = font.w,
                            .h = font.h,
                        },
                        xx,
                        yy,
                    );
                    xx += font.dx;
                },
            }
        }
    }
};
