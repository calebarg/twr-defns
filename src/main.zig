const std = @import("std");
const rl = @import("raylib");
const rlm = @import("raylib-math");

const initial_scale_factor = 4;
var scale_factor: f32 = initial_scale_factor;
var origin = rl.Vector2{ .x = 0, .y = 0 };

const projectile_speed = 0.1;
const max_layers = 5;
const max_unique_track_tiles = 5;
const font_size = 15;
const font_spacing = 1;
const board_width_in_tiles = 16;
const board_height_in_tiles = 16;
const sprite_width = 32;
const sprite_height = 32;

// TODO(caleb):
// *ACTUALLY fix offsets for towers and enemies. Rn I just offset by half sprite's display height ( not ideal ) - bounding boxes?

const anim_frames_speed = 7;
const enemy_tile_step = 32;
const enemy_tps = enemy_tile_step * 3; // Enemy tiles per second
const tower_pps = 5; // Projectiles per second

const color_off_black = rl.Color{ .r = 34, .g = 35, .b = 35, .a = 255 };
const color_off_white = rl.Color{ .r = 240, .g = 246, .b = 240, .a = 255 };

const Tileset = struct {
    columns: u32,
    track_start_id: u32,
    tile_id_count: u8,
    track_tile_ids: [max_unique_track_tiles]u32, // This is silly..
    tex: rl.Texture,

    pub fn checkIsTrackTile(self: Tileset, target_tile_id: u32) bool {
        var track_tile_index: u8 = 0;
        while (track_tile_index < self.tile_id_count) : (track_tile_index += 1) {
            if (self.track_tile_ids[track_tile_index] == target_tile_id) {
                return true;
            }
        }
        return false;
    }
};

const Map = struct {
    tile_indicies: std.ArrayList(u32),
    first_gid: u32,

    pub fn tileIndexFromCoord(self: *Map, tile_x: u32, tile_y: u32) ?u32 {
        std.debug.assert(tile_y * board_width_in_tiles + tile_x < self.*.tile_indicies.items.len);
        const map_tile_index = self.*.tile_indicies.items[tile_y * board_width_in_tiles + tile_x];
        return if (@intCast(i32, map_tile_index) - @intCast(i32, self.*.first_gid) < 0) null else @intCast(u32, @intCast(i32, map_tile_index) - @intCast(i32, self.*.first_gid));
    }
};

const Direction = enum(u32) {
    left = 0,
    up,
    down,
    right,
};

const Enemy = struct {
    direction: Direction,
    last_step_direction: Direction,
    hp: i32,
    pos: rl.Vector2,
};

const tower_descs = [_][*c]const u8{
    "Eye of lauron",
    "Some say it is an eye.",
};

// TODO(caleb): Don't store anim_index inside tower. ( or damage ) ( tower level? )

const Tower = struct {
    direction: Direction,
    tile_x: u32, // TODO(caleb): pos
    tile_y: u32,
    anim_index: u32,
    range: u32,
    damage: u32,
};

const Projectile = struct {
    direction: rl.Vector2,
    target: rl.Vector2,
    speed: f32,
    pos: rl.Vector2,
    tower: *Tower, // NOTE(caleb): Carefull not to create dangling pointers here...
};

const DrawBufferEntry = struct {
    tile_pos: rl.Vector2,
    map_tile_index: u32,
};

inline fn boundsCheck(x: i32, y: i32) bool {
    if ((y < 0) or (y >= board_height_in_tiles) or
        (x < 0) or (x >= board_width_in_tiles))
    {
        return false;
    }
    return true;
}

inline fn movingBackwards(x: f32, y: f32, prev_x: f32, prev_y: f32) bool {
    return ((x == prev_x) and y == prev_y);
}

inline fn clampi32(value: i32, min: i32, max: i32) i32 {
    return @max(min, @min(max, value));
}

inline fn clampf32(value: f32, min: f32, max: f32) f32 {
    return @max(min, @min(max, value));
}

fn updateEnemy(tileset: *Tileset, map: *Map, enemy: *Enemy) void {
    var move_amt = rl.Vector2{ .x = 0, .y = 0 };
    switch (enemy.*.direction) {
        .left => move_amt.x -= 1 / @intToFloat(f32, enemy_tile_step),
        .up => move_amt.y -= 1 / @intToFloat(f32, enemy_tile_step),
        .down => move_amt.y += 1 / @intToFloat(f32, enemy_tile_step),
        .right => move_amt.x += 1 / @intToFloat(f32, enemy_tile_step),
    }

    const next_tile_pos = rlm.Vector2Add(enemy.pos, move_amt);

    if (!boundsCheck(@floatToInt(i32, @floor(next_tile_pos.x)), @floatToInt(i32, @floor(next_tile_pos.y)))) {
        return;
    }

    const target_tile_id = map.tile_indicies.items[@floatToInt(u32, next_tile_pos.y) * board_width_in_tiles + @floatToInt(u32, next_tile_pos.x)] - 1;
    if (tileset.checkIsTrackTile(target_tile_id)) {
        var is_valid_move = true;

        // If moving down check 1 tile down ( we want to keep a tile rel y pos of 0 before turning )
        if (enemy.direction == Direction.down) {

            // If not in bounds than don't worry about checking tile.
            if (boundsCheck(@floatToInt(i32, @floor(next_tile_pos.x)), @floatToInt(i32, @floor(next_tile_pos.y)) + 1)) {
                const plus1_y_target_tile_id = map.tile_indicies.items[(@floatToInt(u32, @floor(next_tile_pos.y)) + 1) * board_width_in_tiles + @floatToInt(u32, @floor(next_tile_pos.x))] - 1;

                // Invalidate move
                if (!tileset.checkIsTrackTile(plus1_y_target_tile_id) and next_tile_pos.y - @floor(next_tile_pos.y) > 0) {
                    is_valid_move = false;
                }
            }
        }
        else if (enemy.direction == Direction.right) {

            // If not in bounds than don't worry about checking tile.
            if (boundsCheck(@floatToInt(i32, @floor(next_tile_pos.x)) + 1, @floatToInt(i32, @floor(next_tile_pos.y)))) {
                const plus1_x_target_tile_id = map.tile_indicies.items[@floatToInt(u32, @floor(next_tile_pos.y)) * board_width_in_tiles + @floatToInt(u32, @floor(next_tile_pos.x)) + 1] - 1;

                // Invalidate move
                if (!tileset.checkIsTrackTile(plus1_x_target_tile_id) and next_tile_pos.x - @floor(next_tile_pos.x) > 0) {
                    is_valid_move = false;
                }
            }
        }

        if (is_valid_move) {
            enemy.pos = next_tile_pos;
            enemy.last_step_direction = enemy.direction;
            return;
        }
    }

    // Choose new direction
    const current_direction = enemy.direction;
    enemy.direction = @intToEnum(Direction, @mod(@enumToInt(enemy.*.direction) + 1, @enumToInt(Direction.right) + 1));
    while(enemy.direction != current_direction) : (enemy.direction = @intToEnum(Direction, @mod(@enumToInt(enemy.direction) + 1, @enumToInt(Direction.right) + 1))) {
        var future_target_tile_id: ?u32 = null;
        switch(enemy.direction) {
            .right => {
                if (boundsCheck(@floatToInt(i32, enemy.pos.x) + 1, @floatToInt(i32, enemy.pos.y)) and enemy.last_step_direction != Direction.left) {
                    future_target_tile_id = map.tile_indicies.items[@floatToInt(u32, enemy.pos.y) * board_width_in_tiles + @floatToInt(u32, enemy.pos.x) + 1] - 1;
                }
            },
            .left => {
                if (boundsCheck(@floatToInt(i32, enemy.pos.x) - 1, @floatToInt(i32, enemy.pos.y)) and enemy.last_step_direction != Direction.right) {
                    future_target_tile_id = map.tile_indicies.items[@floatToInt(u32, enemy.pos.y) * board_width_in_tiles + @floatToInt(u32, enemy.pos.x) - 1] - 1;
                }
            },
           .up => {
                if (boundsCheck(@floatToInt(i32, enemy.pos.x), @floatToInt(i32, enemy.pos.y) - 1) and enemy.last_step_direction != Direction.down) {
                    future_target_tile_id = map.tile_indicies.items[(@floatToInt(u32, enemy.pos.y) - 1) * board_width_in_tiles + @floatToInt(u32, enemy.pos.x)] - 1;
                }
            },
           .down => {
                if (boundsCheck(@floatToInt(i32, enemy.pos.x), @floatToInt(i32, enemy.pos.y) + 1) and enemy.last_step_direction != Direction.up) {
                    future_target_tile_id = map.tile_indicies.items[(@floatToInt(u32, enemy.pos.y) + 1) * board_width_in_tiles + @floatToInt(u32, enemy.pos.x)] - 1;
                }
            },
        }

        if ((future_target_tile_id != null) and tileset.checkIsTrackTile(future_target_tile_id.?)) {
            break;
        }
    }

    std.debug.assert(enemy.direction != current_direction);
    updateEnemy(tileset, map, enemy);
}

fn vector2LineAngle(start: rl.Vector2, end: rl.Vector2) f32 {
    const dot = start.x * end.x + start.y * end.y; // Dot product

    var dot_clamp = if (dot < -1.0) -1.0 else dot; // Clamp
    if (dot_clamp > 1.0) dot_clamp = 1.0;

    return std.math.acos(dot_clamp);
}

inline fn iProjectionVector() rl.Vector2 {
    return rl.Vector2{ .x = @intToFloat(f32, sprite_width * @floatToInt(c_int, scale_factor)) * 0.5, .y = @intToFloat(f32, sprite_height * @floatToInt(c_int, scale_factor)) * 0.25 };
}

inline fn jProjectionVector() rl.Vector2 {
    return rl.Vector2{ .x = -1 * @intToFloat(f32, sprite_width * @floatToInt(c_int, scale_factor)) * 0.5, .y = @intToFloat(f32, sprite_height * @floatToInt(c_int, scale_factor)) * 0.25 };
}

fn isoTransform(x: f32, y: f32, z: f32) rl.Vector2 {
    const i_isometric_trans = iProjectionVector();
    const j_isometric_trans = jProjectionVector();
    const input = rl.Vector2{ .x = x + z, .y = y + z };
    var out = rl.Vector2{
        .x = input.x * i_isometric_trans.x + input.y * j_isometric_trans.x,
        .y = input.x * i_isometric_trans.y + input.y * j_isometric_trans.y,
    };
    return out;
}

fn boardDim() rl.Vector2 {
    const last_tile_pos = isoTransformWithScreenOffset(@intToFloat(f32, board_width_in_tiles - 1),
             @intToFloat(f32, board_height_in_tiles - 1), 0);
    return rl.Vector2{
        .x = last_tile_pos.x,
        .y = last_tile_pos.y,// + @intToFloat(f32, sprite_height) * scale_factor / 2,
    };
}

fn boardHeight() c_int {
    const result = @floatToInt(c_int, isoTransform(@intToFloat(f32, board_width_in_tiles), @intToFloat(f32, board_height_in_tiles), 0).y) + @divTrunc(sprite_height * @floatToInt(c_int, scale_factor), 2);
    return result;
}

fn isoTransformWithScreenOffset(x: f32, y: f32, z: f32) rl.Vector2 {
    var out = isoTransform(x, y, z);

    const screen_offset = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - sprite_width * scale_factor / 2, .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, boardHeight())) / 2 };

    out.x += screen_offset.x + origin.x;
    out.y += screen_offset.y + origin.y;

    return out;
}

fn isoProjectProjectile(pos: rl.Vector2) rl.Vector2 {
    var result = isoTransformWithScreenOffset(pos.x, pos.y, 0);
    result.x += sprite_width * scale_factor / 2;
    return result;
}

fn isoProjectSprite(pos: rl.Vector2) rl.Vector2 {
    var result = isoTransformWithScreenOffset(pos.x, pos.y, 0);
    result.y -= sprite_height * scale_factor / 2;
    return result;
}

fn isoInvert(x: f32, y: f32) rl.Vector2 {
    const i_isometric_trans = iProjectionVector();
    const j_isometric_trans = jProjectionVector();

    const screen_offset = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - sprite_width * scale_factor / 2, .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, boardHeight())) / 2 };

    const input = rl.Vector2{ .x = x - screen_offset.x - origin.x, .y = y - screen_offset.y - origin.y };

    const det = 1 / (i_isometric_trans.x * j_isometric_trans.y - j_isometric_trans.x * i_isometric_trans.y);
    const i_invert_isometric_trans = rl.Vector2{ .x = j_isometric_trans.y * det, .y = i_isometric_trans.y * det * -1 };
    const j_invert_isometric_trans = rl.Vector2{ .x = j_isometric_trans.x * det * -1, .y = i_isometric_trans.x * det };

    return rl.Vector2{
        .x = input.x * i_invert_isometric_trans.x + input.y * j_invert_isometric_trans.x,
        .y = input.x * i_invert_isometric_trans.y + input.y * j_invert_isometric_trans.y,
    };
}

//fn towerFromTileCoords(tile_x: i32, tile_y: i32) ?*Tower {
//}

pub fn main() !void {
    const board_width = sprite_width * board_width_in_tiles * @floatToInt(c_int, scale_factor);
    rl.InitWindow(board_width, boardHeight(), "twr-defns");
    rl.SetWindowState(rl.ConfigFlags.FLAG_WINDOW_RESIZABLE);
    rl.SetWindowState(rl.ConfigFlags.FLAG_VSYNC_HINT);
    rl.SetWindowMinSize(board_width, boardHeight());
    rl.SetTargetFPS(60);

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();
    rl.SetMasterVolume(1);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var ally = arena.allocator();
    var parser = std.json.Parser.init(ally, false);
    defer parser.deinit();

    var push_buffer = try ally.alloc(u8, 1024 * 10);
    defer ally.free(push_buffer);
    var fba = std.heap.FixedBufferAllocator.init(push_buffer);

    var jam = rl.LoadMusicStream("assets/grasslands.wav");
    jam.looping = true;
    defer rl.UnloadMusicStream(jam);
    rl.PlayMusicStream(jam); // NOTE(caleb): start playing here?

    // Font
    var font = rl.LoadFont("assets/PICO-8_mono.ttf");
    defer rl.UnloadFont(font);

    // Load tileset
    var tileset: Tileset = undefined;
    tileset.tex = rl.LoadTexture("assets/isosheet.png");
    defer rl.UnloadTexture(tileset.tex);
    {
        const tileset_file = try std.fs.cwd().openFile("assets/isosheet.tsj", .{});
        defer tileset_file.close();
        var raw_tileset_json = try tileset_file.reader().readAllAlloc(ally, 1024 * 5); // 5kib should be enough
        defer ally.free(raw_tileset_json);

        var parsed_tileset_data = try parser.parse(raw_tileset_json);

        const columns_value = parsed_tileset_data.root.Object.get("columns") orelse unreachable;
        tileset.columns = @intCast(u32, columns_value.Integer);

        const tile_data = parsed_tileset_data.root.Object.get("tiles") orelse unreachable;
        tileset.tile_id_count = @intCast(u8, tile_data.Array.items.len);
        for (tile_data.Array.items) |tile, tile_index| {
            const tile_id = tile.Object.get("id") orelse unreachable;
            const tile_type = tile.Object.get("type") orelse unreachable;

            if (std.mem.eql(u8, tile_type.String, "track")) {
                tileset.track_tile_ids[tile_index] = @intCast(u32, tile_id.Integer);
            } else if (std.mem.eql(u8, tile_type.String, "track_start")) {
                tileset.track_tile_ids[tile_index] = @intCast(u32, tile_id.Integer);
                tileset.track_start_id = @intCast(u32, tile_id.Integer);
            } else {
                unreachable;
            }
        }
    }

    var board_map: Map = undefined;
    board_map.tile_indicies = std.ArrayList(u32).init(ally);
    defer board_map.tile_indicies.deinit();
    {
        const map_file = try std.fs.cwd().openFile("assets/map1.tmj", .{});
        defer map_file.close();
        var map_json = try map_file.reader().readAllAlloc(ally, 1024 * 10);
        defer ally.free(map_json);

        parser.reset();
        var parsed_map = try parser.parse(map_json);
        const layers = parsed_map.root.Object.get("layers") orelse unreachable;
        std.debug.assert(layers.Array.items.len == 1);
        const layer = layers.Array.items[0];
        const tile_data = layer.Object.get("data") orelse unreachable;
        for (tile_data.Array.items) |tile_index| {
            try board_map.tile_indicies.append(@intCast(u32, tile_index.Integer));
        }

        var tilesets = parsed_map.root.Object.get("tilesets") orelse unreachable;
        std.debug.assert(tilesets.Array.items.len == 1);
        const first_gid = tilesets.Array.items[0].Object.get("firstgid") orelse unreachable;
        board_map.first_gid = @intCast(u32, first_gid.Integer);
    }

    // Store FIRST animation index for each sprite in tile set.
    // NOTE(caleb): There are 4 animations stored per index in this list. ( up-left, up-right, down-left, down-right)
    //  where each animation is 4 frames in length.
    var anim_map: Map = undefined;
    anim_map.tile_indicies = std.ArrayList(u32).init(ally);
    defer anim_map.tile_indicies.deinit();
    {
        const anim_file = try std.fs.cwd().openFile("assets/anims.tmj", .{});
        defer anim_file.close();
        var raw_anim_json = try anim_file.reader().readAllAlloc(ally, 1024 * 5); // 5kib should be enough
        defer ally.free(raw_anim_json);

        parser.reset();
        var parsed_anim = try parser.parse(raw_anim_json);
        var layers = parsed_anim.root.Object.get("layers") orelse unreachable;
        std.debug.assert(layers.Array.items.len == 1);
        const layer = layers.Array.items[0];
        var anim_data = layer.Object.get("data") orelse unreachable;
        for (anim_data.Array.items) |tile_index| {
            try anim_map.tile_indicies.append(@intCast(u32, tile_index.Integer));
        }

        var tilesets = parsed_anim.root.Object.get("tilesets") orelse unreachable;
        std.debug.assert(tilesets.Array.items.len == 1);
        const first_gid = tilesets.Array.items[0].Object.get("firstgid") orelse unreachable;
        anim_map.first_gid = @intCast(u32, first_gid.Integer);
    }

    var debug_projectile = false;
    var debug_origin = false;

    var selected_tower: ?*Tower = null;

    var anim_current_frame: u8 = 0;
    var anim_frames_counter: u8 = 0;
    var enemy_tps_frame_counter: u32 = 0;
    var tower_pps_frame_counter: u32 = 0;

    var enemy_start_tile_y: u32 = 0;
    var enemy_start_tile_x: u32 = 0;
    {
        var found_enemy_start_tile = false;
        outer: while (enemy_start_tile_y < board_height_in_tiles) : (enemy_start_tile_y += 1) {
            enemy_start_tile_x = 0;
            while (enemy_start_tile_x < board_width_in_tiles) : (enemy_start_tile_x += 1) {
                const map_tile_index = board_map.tileIndexFromCoord(enemy_start_tile_x, enemy_start_tile_y) orelse continue;
                if ((map_tile_index) == tileset.track_start_id) {
                    found_enemy_start_tile = true;
                    break :outer;
                }
            }
        }
        std.debug.assert(found_enemy_start_tile);
    }

    var towers = std.ArrayList(Tower).init(ally);
    defer towers.deinit();

    var alive_enemies = std.ArrayList(Enemy).init(ally);
    defer alive_enemies.deinit();

    var dead_enemies = std.ArrayList(Enemy).init(ally);
    defer dead_enemies.deinit();

    var projectiles = std.ArrayList(Projectile).init(ally);
    defer projectiles.deinit();

    // TODO(caleb): spawn timer... also waves.
    var enemies_spawned: u32 = 0;
    while (enemies_spawned < 10) : (enemies_spawned += 1) {
        const newEnemy = Enemy{
            .direction = Direction.left,
            .last_step_direction = Direction.left,
            .pos = rl.Vector2{ .x = @intToFloat(f32, enemy_start_tile_x), .y = @intToFloat(f32, enemy_start_tile_y) },
            .hp = 50,
        };
        try alive_enemies.append(newEnemy);
    }

    // TODO(caleb): Disable escape key to close... ( why is this on by default? )
    while (!rl.WindowShouldClose()) { // Detect window close button or ESC key
        rl.UpdateMusicStream(jam);

        anim_frames_counter += 1;
        if (anim_frames_counter >= @divTrunc(60, anim_frames_speed)) {
            anim_frames_counter = 0;
            anim_current_frame += 1;
            if (anim_current_frame > 3) anim_current_frame = 0; // NOTE(caleb): 3 is frames per animation - 1
        }

        enemy_tps_frame_counter += 1;
        if (enemy_tps_frame_counter >= @divTrunc(60, enemy_tps)) {
            enemy_tps_frame_counter = 0;

            for (alive_enemies.items) |*enemy| {
                updateEnemy(&tileset, &board_map, enemy);
            }

            var fraction_of_frame = 60 / @intToFloat(f32, enemy_tps);
            while (fraction_of_frame < 1) : (fraction_of_frame += 60 / @intToFloat(f32, enemy_tps))
            {
                for (alive_enemies.items) |*enemy| {
                    updateEnemy(&tileset, &board_map, enemy);
                }
            }
        }

        // F1 to enable debugging
        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_F1)) {
            debug_projectile = !debug_projectile;
            debug_origin = !debug_origin;
        }

        // Scale board depending on mouse wheel change
        scale_factor = clampf32(scale_factor + rl.GetMouseWheelMove(), 1, 10);

        // Get mouse position
        var mouse_pos = rl.GetMousePosition();
        var selected_tile_pos = isoInvert(@round(mouse_pos.x), @round(mouse_pos.y));
        const selected_tile_x = @floatToInt(i32, selected_tile_pos.x);
        const selected_tile_y = @floatToInt(i32, selected_tile_pos.y);

        if (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_MIDDLE)) {
            // Update origin by last frames mouse delta
            origin = rlm.Vector2Add(origin, rl.GetMouseDelta());
        }

        // Try place tower on selected tile
        if (rl.IsMouseButtonPressed(rl.MouseButton.MOUSE_BUTTON_LEFT) and
            (selected_tile_x < board_width_in_tiles) and (selected_tile_y < board_height_in_tiles) and
            (selected_tile_x >= 0) and (selected_tile_y >= 0))
        {
            const tile_index = board_map.tile_indicies.items[@intCast(u32, selected_tile_y * board_width_in_tiles + selected_tile_x)];
            if (!tileset.checkIsTrackTile(tile_index)) {

                // OK now considered valid to place a tower but is this tile occupied?
                var hasTower = false;
                for (towers.items) |*tower| {
                    if ((tower.tile_x == @intCast(u32, selected_tile_x)) and
                        (tower.tile_y == @intCast(u32, selected_tile_y)))
                    {
                        hasTower = true;
                        selected_tower = tower;

                        break;
                    }
                }

                if (!hasTower) {
                    selected_tower = null;
                    const new_tower = Tower{
                        .direction = Direction.down,
                        .tile_x = @intCast(u32, selected_tile_x),
                        .tile_y = @intCast(u32, selected_tile_y),

                        // TODO(caleb): decide tower type...
                        .anim_index = anim_map.tile_indicies.items[1],
                        .range = 4,
                        .damage = 1,
                    };
                    var did_insert_tower = false;
                    for (towers.items) |tower, tower_index| {
                        if (tower.tile_y >= new_tower.tile_y) {
                            try towers.insert(tower_index, new_tower);
                            did_insert_tower = true;
                            break;
                        }
                    }
                    if (!did_insert_tower) {
                        try towers.append(new_tower);
                    }
                }
            }
        }

        tower_pps_frame_counter += 1; // do this a per tower basis
        if (tower_pps_frame_counter >= @divTrunc(60, tower_pps)) {
            tower_pps_frame_counter = 0;

            // Update each tower
            for (towers.items) |*tower| {
                const tower_x = @intCast(i32, tower.tile_x);
                const tower_y = @intCast(i32, tower.tile_y);

                for (alive_enemies.items) |*enemy| {
                    const enemy_tile_x = @floatToInt(i32, @round(enemy.pos.x));
                    const enemy_tile_y = @floatToInt(i32, @round(enemy.pos.y));

                    // Enemy distance < tower range
                    if ((enemy_tile_x - tower_x) * (enemy_tile_x - tower_x) +
                        (enemy_tile_y - tower_y) * (enemy_tile_y - tower_y) <=
                        (@intCast(i32, tower.range * tower.range)))
                    {
                        if (enemy_tile_y < tower.tile_y and enemy_tile_x == tower.tile_x) {
                            tower.direction = Direction.up;
                        } else if (enemy_tile_x > tower.tile_x) {
                            tower.direction = Direction.right;
                        } else if (enemy_tile_y > tower.tile_y and enemy_tile_x == tower.tile_x) {
                            tower.direction = Direction.down;
                        } else if (enemy_tile_x < tower.tile_x) {
                            tower.direction = Direction.left;
                        }

                        const tower_pos = rl.Vector2{ .x = @intToFloat(f32, tower.tile_x), .y = @intToFloat(f32, tower.tile_y) };
                        const new_projectile = Projectile{
                            .direction = rlm.Vector2Normalize(rlm.Vector2Subtract(enemy.pos, tower_pos)),
                            .target = enemy.pos,
                            .pos = tower_pos,
                            .speed = projectile_speed,
                            .tower = tower,
                        };
                        try projectiles.append(new_projectile);

                        break;
                    }
                }
            }
        }

        {
            var projectile_index: i32 = 0;
            outer: while (projectile_index < projectiles.items.len) : (projectile_index += 1) {
                var projectile = &projectiles.items[@intCast(u32, projectile_index)];
                var projected_pos = isoProjectProjectile(projectile.pos);

                // Is this projectile off the screen or coliding with an enemy?
                if ((@floor(projectile.pos.x) > board_width_in_tiles * 2) or
                    (@floor(projectile.pos.y) > board_height_in_tiles * 2) or
                    (projectile.pos.x < board_width_in_tiles * -1) or (projectile.pos.y < board_height_in_tiles * -1))
                {
                    _ = projectiles.orderedRemove(@intCast(u32, projectile_index));
                    projectile_index -= 1;
                    continue;
                }

                for (alive_enemies.items) |*enemy| { // This could get bad... ( spatial partitioning? )
                    const projected_enemy_pos = isoProjectSprite(enemy.pos);
                    if ((projected_pos.x >= projected_enemy_pos.x) and
                        (projected_pos.x <= projected_enemy_pos.x + sprite_width * scale_factor) and
                        (projected_pos.y >= projected_enemy_pos.y) and
                        (projected_pos.y <= projected_enemy_pos.y + sprite_height * scale_factor))
                    {
                        _ = projectiles.orderedRemove(@intCast(u32, projectile_index));
                        projectile_index -= 1;
                        enemy.hp -= @intCast(i32, projectile.tower.damage);
                        continue :outer;
                    }

                    projectile.pos = rlm.Vector2Add(projectile.pos, rlm.Vector2Scale(projectile.direction, projectile.speed));
                }
            }
        }

        {
            var enemy_index: i32 = 0;
            while (enemy_index < alive_enemies.items.len) : (enemy_index += 1) {
                if (alive_enemies.items[@intCast(u32, enemy_index)].hp <= 0) {
                    try dead_enemies.append(alive_enemies.orderedRemove(@intCast(u32, enemy_index)));
                    enemy_index -= 1;
                }
            }
        }

        rl.BeginDrawing();
        rl.ClearBackground(rl.Color{ .r = 240, .g = 246, .b = 240, .a = 255 });

        var tile_y: i32 = 0;
        while (tile_y < board_height_in_tiles) : (tile_y += 1) {
            var tile_x: i32 = 0;
            while (tile_x < board_width_in_tiles) : (tile_x += 1) {
                const map_tile_index = board_map.tileIndexFromCoord(@intCast(u32, tile_x), @intCast(u32, tile_y)) orelse continue;
                var dest_pos = isoTransformWithScreenOffset(@intToFloat(f32, tile_x), @intToFloat(f32, tile_y), 0);
                if (tile_x == selected_tile_x and tile_y == selected_tile_y) {
                    dest_pos.y -= 10;
                }

                const dest_rect = rl.Rectangle{
                    .x = dest_pos.x,
                    .y = dest_pos.y,
                    .width = sprite_width * scale_factor,
                    .height = sprite_height * scale_factor,
                };

                const target_tile_row = @divTrunc(map_tile_index, tileset.columns);
                const target_tile_column = @mod(map_tile_index, tileset.columns);
                const source_rect = rl.Rectangle{
                    .x = @intToFloat(f32, target_tile_column * sprite_width),
                    .y = @intToFloat(f32, target_tile_row * sprite_height),
                    .width = sprite_width,
                    .height = sprite_height,
                };

                rl.DrawTexturePro(tileset.tex, source_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
            }
        }

        fba.reset();
        var draw_list = std.ArrayList(DrawBufferEntry).init(fba.allocator());

        var entry_index: u32 = 0;
        while (entry_index < towers.items.len + alive_enemies.items.len) : (entry_index += 1) {
            var added_entries: u8 = 0;
            var new_entries: [3]DrawBufferEntry = undefined;

            if (towers.items.len > entry_index) {
                const tower = towers.items[entry_index];
                new_entries[added_entries] = DrawBufferEntry{
                    .tile_pos = rl.Vector2{
                        .x = @intToFloat(f32, tower.tile_x),
                        .y = @intToFloat(f32, tower.tile_y),
                    },
                    .map_tile_index = tower.anim_index + @enumToInt(tower.direction) * 4 + anim_current_frame,
                };
                added_entries += 1;
            }

            if (alive_enemies.items.len > entry_index) {
                const enemy = alive_enemies.items[entry_index];
                new_entries[added_entries] = DrawBufferEntry{
                    .tile_pos = rl.Vector2{
                        .x = enemy.pos.x,
                        .y = enemy.pos.y,
                    },
                    .map_tile_index = anim_map.tile_indicies.items[0] + @enumToInt(enemy.direction) * 4 + anim_current_frame,
                };
                added_entries += 1;
            }

            for (new_entries[0..added_entries]) |new_entry| {
                var did_insert_entry = false;
                for (draw_list.items) |draw_list_entry, curr_entry_index| {
                    if (new_entry.tile_pos.y < draw_list_entry.tile_pos.y) {
                        try draw_list.insert(curr_entry_index, new_entry);
                        did_insert_entry = true;
                        break;
                    }
                }
                if (!did_insert_entry) {
                    try draw_list.append(new_entry);
                }
            }
        }

        for (draw_list.items) |entry| {
            const target_tile_row = @divTrunc(entry.map_tile_index - anim_map.first_gid, tileset.columns);
            const target_tile_column = @mod(entry.map_tile_index - anim_map.first_gid, tileset.columns);
            const source_rect = rl.Rectangle{
                .x = @intToFloat(f32, target_tile_column * sprite_width),
                .y = @intToFloat(f32, target_tile_row * sprite_height),
                .width = sprite_width,
                .height = sprite_height,
            };

            var dest_pos = isoProjectSprite(entry.tile_pos);

            if ((@floatToInt(i32, entry.tile_pos.x) == selected_tile_x) and
                (@floatToInt(i32, entry.tile_pos.y) == selected_tile_y))
            {
                dest_pos.y -= 10;
            }

            const dest_rect = rl.Rectangle{
                .x = dest_pos.x,
                .y = dest_pos.y,
                .width = sprite_width * scale_factor,
                .height = sprite_height * scale_factor,
            };

            rl.DrawTexturePro(tileset.tex, source_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
        }

        for (projectiles.items) |projectile| {
            var dest_pos = isoProjectProjectile(projectile.pos);
            const dest_rect = rl.Rectangle{
                .x = dest_pos.x,
                .y = dest_pos.y,
                .width = 2 * scale_factor,
                .height = 2 * scale_factor,
            };
            rl.DrawRectanglePro(dest_rect, .{ .x = 0, .y = 0 }, 0, rl.Color{ .r = 34, .g = 35, .b = 35, .a = 255 });

            if (debug_projectile) {
                const tower_pos = rl.Vector2{
                    .x = @intToFloat(f32, projectile.tower.*.tile_x),
                    .y = @intToFloat(f32, projectile.tower.*.tile_y),
                };
                var projected_start = isoProjectProjectile(tower_pos);
                var projected_end = isoProjectProjectile(projectile.target);
                rl.DrawLineV(projected_start, projected_end, rl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
            }
        }

        if (selected_tower != null) {
            const map_tile_index = selected_tower.?.anim_index + @enumToInt(selected_tower.?.direction) * 4 + anim_current_frame;
            const target_tile_row = @divTrunc(map_tile_index - anim_map.first_gid, tileset.columns);
            const target_tile_column = @mod(map_tile_index - anim_map.first_gid, tileset.columns);
            const source_rect = rl.Rectangle{
                .x = @intToFloat(f32, target_tile_column * sprite_width),
                .y = @intToFloat(f32, target_tile_row * sprite_height),
                .width = sprite_width,
                .height = sprite_height,
            };

            const text_dim_a = rl.MeasureTextEx(font, "Name: ", font_size, font_spacing);
            const text_dim_b = rl.MeasureTextEx(font, tower_descs[0], font_size, font_spacing);
            const text_dim_c = rl.MeasureTextEx(font, "Desc: ", font_size, font_spacing);
            const text_dim_d = rl.MeasureTextEx(font, tower_descs[1], font_size, font_spacing);

            const text_width = @max(rlm.Vector2Add(text_dim_a, text_dim_b).x,
                rlm.Vector2Add(text_dim_c, text_dim_d).x);

            const pad = 3;
            const dest_rect = rl.Rectangle{
                .x = @intToFloat(f32, rl.GetScreenWidth() - @floatToInt(c_int, text_width) - pad - @floatToInt(c_int, sprite_width * initial_scale_factor * 0.30)),
                .y = pad,
                .width = sprite_width * initial_scale_factor * 0.30,
                .height = sprite_height * initial_scale_factor * 0.30,
            };
            rl.DrawTexturePro(tileset.tex, source_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
            rl.DrawRectangleLinesEx(dest_rect, 2, color_off_black);

            rl.DrawTextEx(font, "Name: ", rl.Vector2{ .x = dest_rect.width + dest_rect.x + pad, .y = pad }, font_size, font_spacing, color_off_black);
            rl.DrawTextEx(font, tower_descs[0], rl.Vector2{ .x = dest_rect.width + dest_rect.x + pad + text_dim_a.x, .y = pad }, font_size, 1, color_off_black);
            rl.DrawTextEx(font, "Desc: ", rl.Vector2{ .x = dest_rect.width + dest_rect.x + pad, .y = pad * 2 + text_dim_c.y }, font_size, font_spacing, color_off_black);
            rl.DrawTextEx(font, tower_descs[1], rl.Vector2{ .x = dest_rect.width + dest_rect.x + pad + text_dim_c.x, .y = pad * 2 + text_dim_c.y }, font_size, 1, color_off_black);
        }

        if (debug_origin) {
            const screen_mid = rl.Vector2{
                .x = @intToFloat(f32, rl.GetScreenWidth()) / 2,
                .y = @intToFloat(f32, rl.GetScreenHeight()) / 2,
            };
            rl.DrawLineEx(screen_mid, rlm.Vector2Add(screen_mid, origin), 2, rl.Color{ .r = 0, .g = 255, .b = 0, .a = 255 });
        }

        rl.EndDrawing();
    }

    rl.CloseWindow();
}
