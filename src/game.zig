const std = @import("std");
const fx = @import("fx.zig");
const Rect = @import("Rect.zig").Rect;
const Font = @import("Font.zig").Font;
const Surface = @import("Surface.zig").Surface;

pub const SCREEN_WIDTH = 180;
pub const SCREEN_HEIGHT = 304;

const COL_COUNT = 8;
const ROW_COUNT = 10;

const TOP = 9.25;
const SPEED_X = 4.0 / 20.0;
const SPEED_Y = 4.0 / 16.0;

// resources
var font: Font = undefined;
var stage_surf: Surface = undefined;
var stuff_surf: Surface = undefined;

// state
var game_level: u32 = 4;
var game_score: usize = 0;
var game_state = GameState.normal;
var marble_counter: u32 = 0;
var levers: [COL_COUNT]Lever = [_]Lever{.{}} ** COL_COUNT;
var grid: [ROW_COUNT][COL_COUNT]GridMarble = undefined;
var stock: [2][COL_COUNT]StockMarble = undefined;
var flying_marbles = std.ArrayList(FlyingMarble).init(std.heap.page_allocator);
var crane_marble = StockMarble{ .type = .none, .weight = 0 };
var crane_col: i32 = 3;
var crane_x: f32 = 3;
var crane_anim: u32 = 99;
var crane_drop = false;
var particles = std.ArrayList(Particle).init(std.heap.page_allocator);
var shake: f32 = 0;

const GameState = enum { normal, over };

const MarbleType = enum(i32) {
    none = 0,
    red,
    blue,
    yellow,
    green,
};

const StockMarble = struct {
    type: MarbleType = undefined,
    weight: i32 = undefined,
    offset: f32 = 0,
    fn makeRandom() StockMarble {
        return .{
            .type = @enumFromInt(fx.random.intRangeAtMost(u32, 1, game_level)),
            .weight = @intCast(fx.random.intRangeAtMost(u32, 1, game_level)),
        };
    }
};

const GridMarble = struct {
    type: MarbleType = .none,
    weight: i32 = 0,
    offset: f32 = 0,
    state: State = .normal,
    dissolve_tick: u32 = 0,
    const State = enum { normal, dissolving };
};

const FlyingMarble = struct {
    type: MarbleType,
    weight: i32,
    x: f32,
    y: f32,
    dest_col: i32,
};

const Lever = struct {
    level: i32 = 1,
    offset: f32 = 0,
    weight: i32 = 0,
};

const Particle = struct {
    tick: u32 = 0,
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    sx: i32,
    sy: i32,
    sw: i32 = 8,
    sh: i32 = 8,
};

pub fn init() !void {
    font = try Font.load("font.bin");
    stage_surf = try Surface.load("stage.bin");
    stuff_surf = try Surface.load("stuff.bin");

    for (&grid) |*row| {
        for (row) |*m| m.* = .{};
    }

    // init stock
    for (&stock) |*row| {
        for (row) |*m| m.* = StockMarble.makeRandom();
    }
}

fn updateOffset(m: anytype) void {
    m.offset = std.math.clamp(0, m.offset - SPEED_Y, m.offset + SPEED_Y);
}

fn drawMarble(m: anytype, x: i32, y: i32) void {
    const marble_rect = Rect{
        .x = @intFromEnum(m.type) * 16,
        .y = 0,
        .w = 16,
        .h = 16,
    };
    var yy = y;
    if (@hasField(@TypeOf(m), "offset")) yy -= @as(i32, @intFromFloat(m.offset * 16));
    fx.screen.copy(stuff_surf, marble_rect, x, yy);
    const str = fx.format("{}", .{m.weight});
    fx.screen.printCentered(font, x + 8, yy + 5, str);
}

fn addMarbleToColumn(t: MarbleType, weight: i32, col: usize) !void {
    levers[col].weight += weight;
    var r: usize = @intCast(levers[col].level);
    while (grid[r][col].type != .none) r += 1;
    std.debug.assert(r < ROW_COUNT);
    grid[r][col] = .{ .type = t, .weight = weight };
}

fn addMarbleParticles(row: usize, col: usize, t: MarbleType) !void {
    const x = 12 + @as(f32, @floatFromInt(col * 20));
    const y = 208 - @as(f32, @floatFromInt(row * 16));
    for ([_]i32{ 0, 8 }) |dx| {
        for ([_]i32{ 0, 8 }) |dy| {
            try particles.append(.{
                .x = x + @as(f32, @floatFromInt(dx)),
                .y = y + @as(f32, @floatFromInt(dy)),
                .sx = dx + @intFromEnum(t) * 16,
                .sy = dy,
                .vx = (fx.random.float(f32) - 0.5) * 10,
                .vy = (fx.random.float(f32) - 0.5) * 10 - 2,
            });
        }
    }
}

fn updateGrid() !void {
    var has_dissolving = [1]bool{false} ** COL_COUNT;

    // dissolve marbles
    var dissolve_count: usize = 0;
    var dissolve_weight: usize = 0;
    var c: usize = 0;
    while (c < COL_COUNT) : (c += 1) {
        var r: usize = @intCast(levers[c].level);
        var shift: usize = 0;
        while (r < ROW_COUNT and grid[r][c].type != .none) {
            var m = &grid[r][c];
            if (m.state != .dissolving) {
                r += 1;
                continue;
            }
            // inc dissolve tick
            m.dissolve_tick += 1;
            if (m.dissolve_tick < 30 or game_state == .over) {
                has_dissolving[c] = true;
                r += 1;
                continue;
            }

            // add particles
            try addMarbleParticles(r + shift, c, m.type);
            shift += 1;

            // remove marble
            dissolve_count += 1;
            dissolve_weight += @intCast(m.weight);
            levers[c].weight -= m.weight;
            var rr = r + 1;
            while (rr < ROW_COUNT) : (rr += 1) {
                grid[rr - 1][c] = grid[rr][c];
                grid[rr - 1][c].offset += 1;
            }
            grid[ROW_COUNT - 1][c] = .{};
        }
    }
    // inc score
    // TODO: better formula
    game_score += dissolve_weight * dissolve_count;
    shake += @as(f32, @floatFromInt(dissolve_count)) * 0.5;

    // adjust levers
    c = 0;
    while (c < COL_COUNT) : (c += 2) {
        if (has_dissolving[c] or has_dissolving[c + 1]) continue;
        const weight_diff = levers[c].weight - levers[c + 1].weight;
        const new_level = 1 - std.math.clamp(weight_diff, -1, 1);
        if (levers[c].level == new_level) continue;

        // send marble flying
        const col = if (levers[c].level > new_level) c else c + 1;
        const col_b = col ^ 1;
        const col_bi: i32 = @intCast(col_b);

        if (new_level == 0 or new_level == 2) {
            var r: usize = ROW_COUNT;
            while (r > 0) {
                r -= 1;
                const m = &grid[r][col_b];
                if (m.type != .none) {
                    try flying_marbles.append(.{
                        .type = m.type,
                        .weight = m.weight,
                        .dest_col = col_bi - weight_diff,
                        .y = @floatFromInt(r),
                        .x = @floatFromInt(col_b),
                    });
                    levers[col_b].weight -= m.weight;
                    m.* = .{};
                    break;
                }
            }
        }

        // rebalance columns
        while (levers[c].level != new_level) {
            // shift up ca marbles
            levers[col].level -= 1;
            levers[col].offset += 1;
            var r: usize = 0;
            while (r < ROW_COUNT - 1) : (r += 1) {
                grid[r][col] = grid[r + 1][col];
                grid[r][col].offset += 1;
            }
            grid[ROW_COUNT - 1][col] = .{};

            // shift up cb marbles
            levers[col_b].level += 1;
            levers[col_b].offset -= 1;
            r = ROW_COUNT;
            while (r > 1) {
                r -= 1;
                grid[r][col_b] = grid[r - 1][col_b];
                grid[r][col_b].offset -= 1;
            }
            grid[0][col_b] = .{};
        }
    }

    // game over
    c = 0;
    while (c < COL_COUNT) : (c += 1) {
        if (grid[8][c].type != .none) {
            game_state = .over;
            return;
        }
    }

    // find marbles in the middle of triplets
    const GridPosition = struct { col: usize, row: usize };
    var todo = std.AutoHashMap(GridPosition, void).init(std.heap.page_allocator);
    defer todo.deinit();
    for (grid, 0..) |row, j| {
        var i: usize = 1;
        while (i < COL_COUNT - 1) : (i += 1) {
            const m0 = row[i - 1];
            const m1 = row[i];
            const m2 = row[i + 1];
            if (m1.type == .none) continue;
            if (m0.state == .normal and
                m1.state == .normal and
                m2.state == .normal and
                m1.type == m0.type and
                m1.type == m2.type)
            {
                try todo.put(.{ .col = i, .row = j }, {});
            }
        }
    }
    var it = todo.keyIterator();
    while (it.next()) |p| {
        grid[p.row][p.col].state = .dissolving;
    }

    // spread dissolve state
    const local = struct {
        fn spread(m: *GridMarble, neighbor: GridMarble) void {
            if (neighbor.type == m.type and neighbor.state == .dissolving) {
                m.state = .dissolving;
                m.dissolve_tick = @max(m.dissolve_tick, neighbor.dissolve_tick);
            }
        }
    };
    var found = true;
    while (found) {
        found = false;
        for (&grid, 0..) |*row, j| {
            for (row, 0..) |*m, i| {
                if (m.type == .none) continue;
                if (m.state == .dissolving) continue;
                if (i > 0) local.spread(m, grid[j][i - 1]);
                if (i + 1 < COL_COUNT) local.spread(m, grid[j][i + 1]);
                if (j > 0) local.spread(m, grid[j - 1][i]);
                if (j + 1 < ROW_COUNT) local.spread(m, grid[j + 1][i]);
                if (m.state == .dissolving) found = true;
            }
        }
    }
}

pub fn update() !void {
    // screen shake
    shake *= 0.94;
    const shake_x: i32 = @intFromFloat(fx.random.floatNorm(f32) * shake);
    const shake_y: i32 = @intFromFloat(fx.random.floatNorm(f32) * shake);

    // update crane
    if (crane_anim < 99) crane_anim += 1;
    if (game_state == .normal) {

        // button input
        if (fx.input.justPressed(.left)) crane_col -= 1;
        if (fx.input.justPressed(.right)) crane_col += 1;
        if (fx.input.justPressed(.down)) crane_drop = true;
        crane_col = std.math.clamp(crane_col, 0, COL_COUNT - 1);

        // touch input
        if (fx.input.touch_active) {
            const i = @divFloor(fx.input.touch_x - 10, 20);
            if (i >= 0 and i < levers.len) {
                if (!fx.input.prev_touch_active and crane_col == i) {
                    crane_drop = true;
                } else {
                    crane_col = i;
                }
            }
        }

        // drop marble
        if (crane_drop and @as(f32, @floatFromInt(crane_col)) == crane_x) {
            crane_drop = false;

            // set flying
            marble_counter += 1;
            if (crane_marble.type != .none) {
                try flying_marbles.append(.{
                    .type = crane_marble.type,
                    .weight = crane_marble.weight,
                    .dest_col = crane_col,
                    .y = TOP,
                    .x = @as(f32, @floatFromInt(crane_col)),
                });
            }
            crane_anim = 0;

            // restock
            const col: usize = @intCast(crane_col);
            crane_marble = stock[0][col];
            stock[0][col] = stock[1][col];
            stock[1][col] = StockMarble.makeRandom();
            // offsets
            stock[0][col].offset = 1;
            stock[1][col].offset = 1;
            crane_marble.offset = 1.25;
        }
    }
    crane_x = std.math.clamp(
        @as(f32, @floatFromInt(crane_col)),
        crane_x - SPEED_X,
        crane_x + SPEED_X,
    );

    // update flying marbles
    {
        var i: usize = 0;
        while (i < flying_marbles.items.len) {
            var f = &flying_marbles.items[i];

            const dx = @as(f32, @floatFromInt(f.dest_col));

            if (f.x != dx and f.y < TOP) {
                f.y = @min(f.y + SPEED_Y, TOP);
            } else if (f.dest_col < 0) {
                f.x -= SPEED_X;
                if (f.x < -3) {
                    f.x = COL_COUNT + 2;
                    f.dest_col += COL_COUNT;
                    // TODO: change marble
                }
            } else if (f.dest_col >= COL_COUNT) {
                f.x += SPEED_X;
                if (f.x > COL_COUNT + 2) {
                    f.x = -3;
                    f.dest_col -= COL_COUNT;
                    // TODO: change marble
                }
            } else if (f.x != dx) {
                f.x = std.math.clamp(dx, f.x - SPEED_X, f.x + SPEED_X);
            } else {
                std.debug.assert(f.x == dx);
                f.y -= SPEED_Y;
                const col: usize = @intCast(f.dest_col);
                var r: usize = @intCast(levers[col].level);
                while (r < ROW_COUNT) : (r += 1) {
                    if (grid[r][col].type == .none) break;
                }
                if (f.y < @as(f32, @floatFromInt(r))) {
                    try addMarbleToColumn(f.type, f.weight, col);
                    _ = flying_marbles.swapRemove(i);
                    continue;
                }
            }
            i += 1;
        }
    }

    try updateGrid();

    // update offsets
    updateOffset(&crane_marble);
    for (&levers) |*l| updateOffset(l);
    for (&grid) |*row| {
        for (row) |*m| updateOffset(m);
    }
    for (&stock) |*row| {
        for (row) |*m| updateOffset(m);
    }

    // update particles
    var i: usize = 0;
    while (i < particles.items.len) {
        var p = &particles.items[i];
        p.tick += 1;
        if (p.tick > 100) {
            _ = particles.swapRemove(i);
            continue;
        }
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.4; // gravity
        i += 1;
    }

    ////////////////////////////////////////////////////////////
    // draw ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////

    fx.screen.copy(
        stage_surf,
        .{
            .x = 0,
            .y = 0,
            .w = stage_surf.w,
            .h = stage_surf.h,
        },
        shake_x,
        shake_y,
    );

    // draw marbles
    for (grid, 0..) |row, r| {
        const ri: i32 = @intCast(r);
        for (row, 0..) |m, c| {
            const ci: i32 = @intCast(c);
            if (m.type == .none) continue;
            drawMarble(
                m,
                shake_x + 12 + ci * 20,
                shake_y + 208 - ri * 16,
            );
        }
    }

    // draw stock
    for (stock, 0..) |row, r| {
        const ri: i32 = @intCast(r);
        for (row, 0..) |m, c| {
            const ci: i32 = @intCast(c);
            if (m.type == .none) continue;
            drawMarble(
                m,
                shake_x + 12 + ci * 20,
                shake_y + 40 - ri * 16,
            );
        }
    }

    for (levers, 0..) |l, c| {
        const ci: i32 = @intCast(c);
        // lever
        fx.screen.copy(
            stuff_surf,
            .{
                .x = @intCast(c % 2 * 16),
                .y = 40,
                .w = 16,
                .h = 48,
            },
            shake_x + 12 + ci * 20,
            shake_y + 216 - l.level * 16 - @as(i32, @intFromFloat(l.offset * 16)),
        );
    }

    // draw dissolve effect
    for (grid, 0..) |row, r| {
        const ri: i32 = @intCast(r);
        for (row, 0..) |m, c| {
            const ci: i32 = @intCast(c);
            if (m.type == .none) continue;
            if (m.state != .dissolving) continue;
            if (m.dissolve_tick > 0 and @mod(m.dissolve_tick, 12) > 4) {
                const dissolve_rect = Rect{
                    .x = 0,
                    .y = 88,
                    .w = 32,
                    .h = 32,
                };
                fx.screen.copy(
                    stuff_surf,
                    dissolve_rect,
                    4 + ci * 20,
                    200 - ri * 16,
                );
            }
        }
    }

    // flying marbles
    for (flying_marbles.items) |f| {
        drawMarble(
            f,
            shake_x + 12 + @as(i32, @intFromFloat(f.x * 20)),
            shake_y + 208 - @as(i32, @intFromFloat(f.y * 16)),
        );
    }

    // over draw top and bottom
    fx.screen.copy(
        stage_surf,
        .{
            .x = 10,
            .y = 8,
            .w = 160,
            .h = 16,
        },
        shake_x + 10,
        shake_y + 8,
    );
    fx.screen.copy(
        stage_surf,
        .{
            .x = 10,
            .y = 232,
            .w = 160,
            .h = 32,
        },
        shake_x + 10,
        shake_y + 232,
    );

    // draw crane
    const frame: i32 = switch (crane_anim) {
        0...1 => 1,
        2...3 => 2,
        4...5 => 1,
        else => 0,
    };
    const crane_rect = Rect{
        .x = frame * 40,
        .y = 16,
        .w = 32,
        .h = 24,
    };
    fx.screen.copy(
        stuff_surf,
        crane_rect,
        shake_x + @as(i32, @intFromFloat(4 + crane_x * 20)),
        shake_y + 56,
    );
    if (crane_marble.type != .none) {
        drawMarble(
            crane_marble,
            shake_x + @as(i32, @intFromFloat(12 + crane_x * 20)),
            shake_y + 60,
        );
    }

    // weight labels
    var col: usize = 0;
    while (col < COL_COUNT) : (col += 2) {
        const ci: i32 = @intCast(col);
        const w = @abs(levers[col].weight - levers[col ^ 1].weight);
        const str = fx.format("{}", .{w});
        fx.screen.printCentered(
            font,
            shake_x + 30 + ci * 20,
            shake_y + 241,
            str,
        );
    }

    // particles
    for (particles.items) |p| {
        fx.screen.copy(
            stuff_surf,
            .{
                .x = p.sx,
                .y = p.sy,
                .w = p.sw,
                .h = p.sh,
            },
            shake_x + @as(i32, @intFromFloat(p.x)),
            shake_y + @as(i32, @intFromFloat(p.y)),
        );
    }

    // level & score
    fx.screen.print(font, 8, 10, fx.format("{}/{}", .{ marble_counter, game_level }));
    fx.screen.print(font, 124, 10, fx.format("{:8}", .{game_score}));

    // game over
    if (game_state == .over) {
        fx.screen.print(font, 63, 10, "GAME OVER");
    }
}

pub fn deinit() void {
    flying_marbles.deinit();
    particles.deinit();
}
