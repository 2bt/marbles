const fx = @import("fx.zig");
const game = @import("game.zig");

export fn pixels() [*]u32 {
    return fx.screen.pixels.ptr;
}
export fn width() i32 {
    return fx.screen.w;
}
export fn height() i32 {
    return fx.screen.h;
}
export fn init(seed: u32) void {
    fx.init(seed);
    game.init() catch |e| fx.log("ERROR: {}", .{e});
}
export fn update(buttons: u8, touch_active: bool, touch_x: i32, touch_y: i32) void {
    fx.input.prev_buttons = fx.input.buttons;
    fx.input.prev_touch_active = fx.input.touch_active;
    fx.input.buttons = buttons;
    fx.input.touch_active = touch_active;
    fx.input.touch_x = touch_x;
    fx.input.touch_y = touch_y;
    game.update() catch |e| fx.log("ERROR: {}", .{e});
}
