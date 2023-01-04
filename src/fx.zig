const std = @import("std");
const game = @import("game.zig");
const Surface = @import("Surface.zig").Surface;

var prng: std.rand.DefaultPrng = undefined;

const format_private = struct {
    var buffer: [512]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var string = std.ArrayList(u8).init(fba.allocator());
    var writer = string.writer();
};

pub fn format(comptime fmt: []const u8, args: anytype) []const u8 {
    format_private.string.clearRetainingCapacity();
    format_private.writer.print(fmt, args) catch unreachable;
    return format_private.string.items;
}
pub fn log(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").cpu.arch == .wasm32) {
        const js = struct {
            extern fn print(ptr: [*]const u8, len: u32) void;
        };
        const str = format(fmt, args);
        js.print(str.ptr, str.len);
    } else {
        std.debug.print(fmt ++ "\n", args);
    }
}
pub var random: std.rand.Random = undefined;
pub var screen: Surface = undefined;

pub const Input = struct {
    buttons: u8,
    prev_buttons: u8,
    touch_active: bool,
    prev_touch_active: bool,
    touch_x: i32,
    touch_y: i32,
    pub const Button = enum(u8) {
        left = 1,
        right = 2,
        up = 4,
        down = 8,
        x = 16,
    };
    pub fn justPressed(self: @This(), button: Button) bool {
        const b = @enumToInt(button);
        return self.buttons & b > 0 and self.prev_buttons & b == 0;
    }
};

pub var input = Input{
    .buttons = 0,
    .prev_buttons = 0,
    .touch_active = false,
    .prev_touch_active = false,
    .touch_x = 0,
    .touch_y = 0,
};

pub fn init(seed: u32) void {
    prng = std.rand.DefaultPrng.init(seed);
    random = prng.random();
    screen = Surface.init(game.SCREEN_WIDTH, game.SCREEN_HEIGHT) catch undefined;
    screen.clear(0xff000000);
    game.init() catch |e| log("ERROR: {}", .{e});
}
