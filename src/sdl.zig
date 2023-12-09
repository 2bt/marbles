const std = @import("std");
const fx = @import("fx.zig");
const game = @import("game.zig");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

pub fn main() !void {
    var seed: u32 = undefined;
    try std.os.getrandom(std.mem.asBytes(&seed));
    fx.init(seed);

    if (c.SDL_Init(c.SDL_INIT_EVERYTHING) != 0) return error.SdlError;
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "Marbles",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        fx.screen.w * 3,
        fx.screen.h * 3,
        0,
    ) orelse return error.SdlError;
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(
        window,
        -1,
        c.SDL_RENDERER_PRESENTVSYNC,
    ) orelse return error.SdlError;
    defer c.SDL_DestroyRenderer(renderer);
    _ = c.SDL_RenderSetLogicalSize(renderer, fx.screen.w, fx.screen.h);

    const tex = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_ABGR8888,
        c.SDL_TEXTUREACCESS_STREAMING,
        fx.screen.w,
        fx.screen.h,
    ) orelse return error.SdlError;
    defer c.SDL_DestroyTexture(tex);

    const key_state = c.SDL_GetKeyboardState(null) orelse return error.SdlError;

    try game.init();
    defer game.deinit();

    var running = true;
    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    running = false;
                },
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) running = false;
                },
                else => {},
            }
        }

        //fx.input.prev_touch_active = fx.input.touch_active;
        //fx.input.touch_active = touch_active;
        //fx.input.touch_x = touch_x;
        //fx.input.touch_y = touch_y;
        fx.input.prev_buttons = fx.input.buttons;
        fx.input.buttons = 0;
        if (key_state[c.SDL_SCANCODE_LEFT] > 0) fx.input.buttons |= @intFromEnum(fx.Input.Button.left);
        if (key_state[c.SDL_SCANCODE_RIGHT] > 0) fx.input.buttons |= @intFromEnum(fx.Input.Button.right);
        if (key_state[c.SDL_SCANCODE_UP] > 0) fx.input.buttons |= @intFromEnum(fx.Input.Button.up);
        if (key_state[c.SDL_SCANCODE_DOWN] > 0) fx.input.buttons |= @intFromEnum(fx.Input.Button.down);
        if (key_state[c.SDL_SCANCODE_X] > 0) fx.input.buttons |= @intFromEnum(fx.Input.Button.x);

        try game.update();

        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_UpdateTexture(tex, null, fx.screen.pixels.ptr, fx.screen.w * 4);
        _ = c.SDL_RenderCopy(renderer, tex, null, null);
        c.SDL_RenderPresent(renderer);
        //c.SDL_Delay(100);
    }
}
