// TODO(caleb):
// ========================
// *Death animations
// *HP and money icons
// *Money/hp animation ( just need a list of vecs + amt lost or gained ).
// *README ( how to play section )
// *Handle spawn data past round 60 ( freeplay mode )

const std = @import("std");
const rl = @import("raylib");
const rlm = @import("raylib-math");

const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const hashString = std.hash_map.hashString;

const target_fps = 60;
const tower_buy_area_sprite_scale = 0.8;
const tower_buy_area_towers_per_row = 1;
const default_font_size = 18;
const font_spacing = 2;
const board_width_in_tiles = 16;
const board_height_in_tiles = 16;
const sprite_width = 32;
const sprite_height = 32;
const anim_frames_speed = 7;
const color_off_black = rl.Color{ .r = 34, .g = 35, .b = 35, .a = 255 };
const color_off_white = rl.Color{ .r = 240, .g = 246, .b = 240, .a = 255 };
const initial_scale_factor = 4;

var scale_factor: f32 = initial_scale_factor;
var board_translation = rl.Vector2{ .x = 0, .y = 0 };
var money: i32 = 100;
var hp: i32 = 100;
var score: u32 = 0;
var round: u32 = 0;

const Tileset = struct {
    columns: u16,
    tex: rl.Texture,
    tile_name_to_id: AutoHashMap(u64, u16),

    pub inline fn isTrackTile(self: Tileset, target_tile_id: u16) bool {
        var result = false;
        if ((self.tile_name_to_id.get(hashString("track_start")).? == target_tile_id) or
            (self.tile_name_to_id.get(hashString("track")).? == target_tile_id))
        {
            result = true;
        }
        return result;
    }
};

const Map = struct {
    tile_indicies: ArrayList(u16),
    first_gid: u16,

    pub fn tileIDFromCoord(self: *Map, tile_x: u32, tile_y: u32) ?u32 {
        std.debug.assert(tile_y * board_width_in_tiles + tile_x < self.*.tile_indicies.items.len);
        const ts_id = self.tile_indicies.items[tile_y * board_width_in_tiles + tile_x];
        return if (@intCast(i32, ts_id) - @intCast(i32, self.*.first_gid) < 0) null else @intCast(u32, @intCast(i32, ts_id) - @intCast(i32, self.*.first_gid));
    }
};

const GameMode = enum {
    title_screen,
    running,
    game_over,
};

const Direction = enum(u32) {
    left = 0,
    up,
    down,
    right,
};

const EnemyData = struct {
    hp: u32,
    move_speed: f32,
    tile_id: u32,
    sprite_offset_x: u16,
    sprite_offset_y: u16,
    tile_steps_per_second: u8,
};

const EnemyKind = enum(u32) {
    gremlin_wiz_guy = 0,
    count,
};

const GroupSpawnData = struct {
    kind: EnemyKind,
    spawn_count: u32,
    time_between_spawns_ms: u16,
};

const RoundSpawns = struct {
    group_spawn_data: [@enumToInt(EnemyKind.count)]GroupSpawnData,
    unique_enemies_for_this_round: u8,
};

var enemies_data = [_]EnemyData{
    EnemyData{ // Gremlin wiz guy
        .hp = 1,
        .move_speed = 1.0,
        .tile_id = undefined,
        .sprite_offset_x = 10,
        .sprite_offset_y = 14,
        .tile_steps_per_second = 64,
    },
};

const Enemy = struct {
    kind: EnemyKind,
    direction: Direction,
    last_step_direction: Direction,
    hp: i32,
    pos: rl.Vector2,
    colliders: [2]rl.Rectangle,
    tile_steps_per_second: u8,
    tile_step_timer: u8,
    anim_frame: u8,
    anim_timer: u8,

    /// Updates collider positions rel to enemy pos.
    fn shiftColliders(self: *Enemy) void {
        var y_offset: f32 = sprite_height * scale_factor / 2;
        for (self.colliders) |*collider| {
            // TODO(caleb): Convention for sprite offsets when drawing? Possibly read this
            // in alongside other json data.

            const enemy_screen_space_pos = isoProject(self.pos.x, self.pos.y, 1);
            const collider_screen_space_pos = rl.Vector2{
                .x = enemy_screen_space_pos.x + (sprite_width * scale_factor - collider.width * scale_factor) / 2,
                .y = enemy_screen_space_pos.y + y_offset,
            };
            const collider_tile_space_pos = isoProjectInverted(collider_screen_space_pos.x, collider_screen_space_pos.y, 1);
            collider.x = collider_tile_space_pos.x;
            collider.y = collider_tile_space_pos.y;

            y_offset += collider.height * scale_factor;
        }
    }
    fn initColliders(self: *Enemy) void {
        // TODO(caleb): Get hitbox info from tileset json.

        self.colliders[0].width = 12; // ~Head
        self.colliders[0].height = 8;

        self.colliders[1].width = 14; // ~Body
        self.colliders[1].height = 8;

        self.shiftColliders();
    }
};

const tower_names = [_][*c]const u8{
    "Floating eye",
    "Placeholder 1",
    "Placeholder 2",
    "Placeholder 3",
    "Placeholder 4",
};

const tower_descs = [_][*c]const u8{
    "Some say it is an eye.",
    "Placeholder desc 1",
    "Placeholder desc 2",
    "Placeholder desc 3",
    "Placeholder desc 4",
};

const TowerKind = enum(u32) {
    floating_eye = 0,
    placeholder_1,
    placeholder_2,
    placeholder_3,
    placeholder_4,
};

const TowerData = struct {
    damage: u32,
    tile_id: u32,
    range: u16,
    sprite_offset_x: u16,
    sprite_offset_y: u16,
    fire_rate: u8,
    fire_speed: u8,
    cost: u16,
};

var towers_data = [_]TowerData{
    TowerData{ // floating eye
        .sprite_offset_x = 10,
        .sprite_offset_y = 1,
        .damage = 1,
        .range = 8,
        .tile_id = undefined,
        .fire_rate = 2,
        .fire_speed = 10,
        .cost = 50,
    },
    TowerData{ // placeholder 1
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
        .cost = 50,
    },
    TowerData{ // placeholder 2
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
        .cost = 50,
    },
    TowerData{ // placeholder 3
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
        .cost = 50,
    },
    TowerData{ // placeholder 4
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
        .cost = 50,
    },
};

const Tower = struct {
    kind: TowerKind,
    direction: Direction,
    tile_x: u16,
    tile_y: u16,
    fire_rate: u8,
    fire_rate_timer: u8,
    fire_speed: u8,
    anim_frame: u8,
    anim_timer: u8,
};

const Projectile = struct {
    direction: rl.Vector2,
    start: rl.Vector2,
    target: rl.Vector2,
    speed: f32,
    pos: rl.Vector2,
    damage: u32,
};

const DrawBufferEntry = struct {
    tile_pos: rl.Vector2,
    ts_id: u32,
};

const Input = struct {
    l_mouse_button_is_down: bool,
    mouse_pos: rl.Vector2,
};

inline fn boundsCheck(x: i32, y: i32) bool {
    if ((y < 0) or (y >= board_height_in_tiles) or
        (x < 0) or (x >= board_width_in_tiles))
    {
        return false;
    }
    return true;
}

inline fn clampf32(value: f32, min: f32, max: f32) f32 {
    return @max(min, @min(max, value));
}

inline fn screenSpaceBoardHeight() c_int {
    const result = @floatToInt(c_int, isoProjectBase(@intToFloat(f32, board_width_in_tiles), @intToFloat(f32, board_height_in_tiles), 0).y) + @divTrunc(sprite_height * @floatToInt(c_int, scale_factor), 2);
    return result;
}

fn updateEnemy(tileset: *Tileset, map: *Map, enemy: *Enemy) void {
    var move_amt = rl.Vector2{ .x = 0, .y = 0 };
    switch (enemy.*.direction) {
        .left => move_amt.x -= 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
        .up => move_amt.y -= 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
        .down => move_amt.y += 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
        .right => move_amt.x += 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
    }
    const next_tile_pos = rlm.Vector2Add(enemy.pos, move_amt);
    const target_tile_id = map.tile_indicies.items[@floatToInt(u32, next_tile_pos.y) * board_width_in_tiles + @floatToInt(u32, next_tile_pos.x)] - 1;
    if (tileset.isTrackTile(target_tile_id)) {
        var is_valid_move = true;

        // If moving down check 1 tile down ( we want to keep a tile rel y pos of 0 before turning )
        if (enemy.direction == Direction.down) {

            // If not in bounds than don't worry about checking tile.
            if (boundsCheck(@floatToInt(i32, @floor(next_tile_pos.x)), @floatToInt(i32, @floor(next_tile_pos.y)) + 1)) {
                const plus1_y_target_tile_id = map.tile_indicies.items[(@floatToInt(u32, @floor(next_tile_pos.y)) + 1) * board_width_in_tiles + @floatToInt(u32, @floor(next_tile_pos.x))] - 1;

                // Invalidate move
                if (!tileset.isTrackTile(plus1_y_target_tile_id) and next_tile_pos.y - @floor(next_tile_pos.y) > 0) {
                    // Align enemy pos y
                    enemy.pos.y = @floor(next_tile_pos.y);
                    is_valid_move = false;
                }
            }
        } else if (enemy.direction == Direction.right) {

            // Again not in bounds, don't worry about checking tile.
            if (boundsCheck(@floatToInt(i32, @floor(next_tile_pos.x)) + 1, @floatToInt(i32, @floor(next_tile_pos.y)))) {
                const plus1_x_target_tile_id = map.tile_indicies.items[@floatToInt(u32, @floor(next_tile_pos.y)) * board_width_in_tiles + @floatToInt(u32, @floor(next_tile_pos.x)) + 1] - 1;

                // Invalidate move
                if (!tileset.isTrackTile(plus1_x_target_tile_id) and next_tile_pos.x - @floor(next_tile_pos.x) > 0) {
                    // Align enemy pos x
                    enemy.pos.x = @floor(next_tile_pos.x);
                    is_valid_move = false;
                }
            }
        }

        if (is_valid_move) {
            enemy.pos = next_tile_pos;
            enemy.last_step_direction = enemy.direction;
            enemy.shiftColliders();
            return;
        }
    }

    // Choose new direction
    const current_direction = enemy.direction;
    enemy.direction = @intToEnum(Direction, @mod(@enumToInt(enemy.*.direction) + 1, @enumToInt(Direction.right) + 1));
    while (enemy.direction != current_direction) : (enemy.direction = @intToEnum(Direction, @mod(@enumToInt(enemy.direction) + 1, @enumToInt(Direction.right) + 1))) {
        var future_target_tile_id: ?u16 = null;
        switch (enemy.direction) {
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

        if ((future_target_tile_id != null) and tileset.isTrackTile(future_target_tile_id.?)) {
            break;
        }
    }

    std.debug.assert(enemy.direction != current_direction);
    updateEnemy(tileset, map, enemy);
}

inline fn iProjectionVector() rl.Vector2 {
    return rl.Vector2{ .x = @intToFloat(f32, sprite_width * @floatToInt(c_int, scale_factor)) * 0.5, .y = @intToFloat(f32, sprite_height * @floatToInt(c_int, scale_factor)) * 0.25 };
}

inline fn jProjectionVector() rl.Vector2 {
    return rl.Vector2{ .x = -1 * @intToFloat(f32, sprite_width * @floatToInt(c_int, scale_factor)) * 0.5, .y = @intToFloat(f32, sprite_height * @floatToInt(c_int, scale_factor)) * 0.25 };
}

fn isoProjectBase(x: f32, y: f32, z: f32) rl.Vector2 {
    const i_iso_trans = iProjectionVector();
    const j_iso_trans = jProjectionVector();
    const input = rl.Vector2{ .x = x - z, .y = y - z };
    var out = rl.Vector2{
        .x = input.x * i_iso_trans.x + input.y * j_iso_trans.x,
        .y = input.x * i_iso_trans.y + input.y * j_iso_trans.y,
    };
    return out;
}

fn isoProject(x: f32, y: f32, z: f32) rl.Vector2 {
    var out = isoProjectBase(x, y, z);

    const screen_offset = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - sprite_width * scale_factor / 2, .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, screenSpaceBoardHeight())) / 2 };

    out.x += screen_offset.x + board_translation.x;
    out.y += screen_offset.y + board_translation.y;

    return out;
}

fn isoProjectInverted(screen_space_x: f32, screen_space_y: f32, tile_space_z: f32) rl.Vector2 {
    const i_iso_trans = iProjectionVector();
    const j_iso_trans = jProjectionVector();

    const screen_offset = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - sprite_width * scale_factor / 2, .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, screenSpaceBoardHeight())) / 2 };

    const input = rl.Vector2{ .x = screen_space_x - screen_offset.x - board_translation.x, .y = screen_space_y - screen_offset.y - board_translation.y };

    const det = 1 / (i_iso_trans.x * j_iso_trans.y - j_iso_trans.x * i_iso_trans.y);
    const i_invert_iso_trans = rl.Vector2{ .x = j_iso_trans.y * det, .y = i_iso_trans.y * det * -1 };
    const j_invert_iso_trans = rl.Vector2{ .x = j_iso_trans.x * det * -1, .y = i_iso_trans.x * det };

    return rl.Vector2{
        .x = (input.x * i_invert_iso_trans.x + input.y * j_invert_iso_trans.x) + tile_space_z,
        .y = (input.x * i_invert_iso_trans.y + input.y * j_invert_iso_trans.y) + tile_space_z,
    };
}

inline fn startBGPoses() [4]rl.Vector2 {
    return [4]rl.Vector2{
        rl.Vector2{ .x = @intToFloat(f32, -rl.GetScreenWidth()), .y = @intToFloat(f32, -rl.GetScreenHeight()) },
        rl.Vector2{ .x = 0, .y = @intToFloat(f32, -rl.GetScreenHeight()) },
        rl.Vector2{ .x = @intToFloat(f32, -rl.GetScreenWidth()), .y = 0 },
        rl.Vector2{ .x = 0, .y = 0 },
    };
}

fn drawTile(tileset: *Tileset, tile_id: u16, dest_pos: rl.Vector2, this_scale_factor: f32, tint: rl.Color) void {
    const dest_rect = rl.Rectangle{
        .x = dest_pos.x,
        .y = dest_pos.y,
        .width = sprite_width * this_scale_factor,
        .height = sprite_height * this_scale_factor,
    };

    const target_tile_row = @divTrunc(tile_id, tileset.columns);
    const target_tile_column = @mod(tile_id, tileset.columns);
    const source_rect = rl.Rectangle{
        .x = @intToFloat(f32, target_tile_column * sprite_width),
        .y = @intToFloat(f32, target_tile_row * sprite_height),
        .width = sprite_width,
        .height = sprite_height,
    };

    rl.DrawTexturePro(tileset.tex, source_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, tint);
}

fn drawBoard(board_map: *Map, tileset: *Tileset, selected_tile_x: i32, selected_tile_y: i32, selected_tower: ?*Tower, tower_index_being_placed: i32) void {
    var tile_y: i32 = 0;
    while (tile_y < board_height_in_tiles) : (tile_y += 1) {
        var tile_x: i32 = 0;
        while (tile_x < board_width_in_tiles) : (tile_x += 1) {
            var dest_pos = isoProject(@intToFloat(f32, tile_x), @intToFloat(f32, tile_y), 0);
            if (tile_x == selected_tile_x and tile_y == selected_tile_y) {
                dest_pos.y -= 4 * scale_factor;
            }
            const tile_id = @intCast(u16, board_map.tileIDFromCoord(@intCast(u32, tile_x), @intCast(u32, tile_y)) orelse continue);
            var tile_color = rl.WHITE;
            if (selected_tower != null) {
                const range = towers_data[@enumToInt(selected_tower.?.kind)].range;
                if (std.math.absCast(tile_x - @intCast(i32, selected_tower.?.tile_x)) + std.math.absCast(tile_y - @intCast(i32, selected_tower.?.tile_y)) <= range) {
                    tile_color = rl.GRAY;
                }
            } else if (tower_index_being_placed >= 0) {
                const range = towers_data[@intCast(u32, tower_index_being_placed)].range;
                if (std.math.absCast(tile_x - @intCast(i32, selected_tile_x)) + std.math.absCast(tile_y - @intCast(i32, selected_tile_y)) <= range) {
                    tile_color = rl.GRAY;
                }
            }
            drawTile(tileset, tile_id, dest_pos, scale_factor, tile_color);
        }
    }
}

fn drawBackground(screen_dim: rl.Vector2, background_offset: f32, debug_bg_scroll: bool, bg_poses: *[4]rl.Vector2, bg_tex: *rl.Texture, hor_osc_shader: *rl.Shader) void {
    _ = hor_osc_shader;
    _ = bg_tex;
    // const bg_source_rec = rl.Rectangle{
    //     .x = 0,
    //     .y = 0,
    //     .width = @intToFloat(f32, bg_tex.width),
    //     .height = -@intToFloat(f32, bg_tex.height),
    // };

    // rl.BeginShaderMode(hor_osc_shader.*);
    // for (bg_poses) |bg_pos| {
    //     const bg_dest_rec = rl.Rectangle{
    //         .x = bg_pos.x,
    //         .y = bg_pos.y,
    //         .width = screen_dim.x,
    //         .height = screen_dim.y,
    //     };
    //     rl.DrawTexturePro(bg_tex.*, bg_source_rec, bg_dest_rec, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
    // }
    // rl.EndShaderMode();
    rl.ClearBackground(color_off_white);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        // TODO(caleb): FIXME
        rl.DrawLineEx(rl.Vector2{ .x = -10, .y = @intToFloat(f32, i * 30 + @floatToInt(i32, background_offset) - 20) }, rl.Vector2{ .x = screen_dim.x + 10, .y = @intToFloat(f32, i * 30 - 110) + background_offset }, 15, color_off_);
    }
    if (debug_bg_scroll) {
        for (bg_poses) |bg_pos| {
            rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x + 30, .y = bg_pos.y }, 3, rl.RED);
            rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x - 30, .y = bg_pos.y }, 3, rl.RED);
            rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x, .y = bg_pos.y + 30 }, 3, rl.RED);
            rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x, .y = bg_pos.y - 30 }, 3, rl.RED);
        }
    }
}

fn drawSprites(fba: *FixedBufferAllocator, tileset: *Tileset, debug_hit_boxes: bool, debug_projectile: bool, towers: *ArrayList(Tower), alive_enemies: *ArrayList(Enemy), projectiles: *ArrayList(Projectile), selected_tile_x: i32, selected_tile_y: i32, tower_index_being_placed: i32, tba_anim_frame: u8) !void {
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
                .ts_id = towers_data[@enumToInt(tower.kind)].tile_id + @enumToInt(tower.direction) * 4 + tower.anim_frame,
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
                .ts_id = enemies_data[@enumToInt(enemy.kind)].tile_id + @enumToInt(enemy.direction) * 4 + enemy.anim_frame,
            };
            added_entries += 1;
        }

        for (new_entries[0..added_entries]) |new_entry| {
            var did_insert_entry = false;
            for (draw_list.items) |draw_list_entry, curr_entry_index| {
                if ((new_entry.tile_pos.y < draw_list_entry.tile_pos.y) and
                    (new_entry.tile_pos.x > draw_list_entry.tile_pos.x))
                {
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
        var dest_pos = isoProject(entry.tile_pos.x, entry.tile_pos.y, 1);
        if ((@floatToInt(i32, entry.tile_pos.x) == selected_tile_x) and
            (@floatToInt(i32, entry.tile_pos.y) == selected_tile_y))
        {
            dest_pos.y -= 4 * scale_factor;
        }
        drawTile(tileset, @intCast(u16, entry.ts_id), dest_pos, scale_factor, rl.WHITE);
    }

    if (debug_hit_boxes) {
        for (alive_enemies.items) |enemy| {
            for (enemy.colliders) |collider| {
                var dest_pos = isoProject(collider.x, collider.y, 1);
                const dest_rec = rl.Rectangle{
                    .x = dest_pos.x,
                    .y = dest_pos.y,
                    .width = collider.width * scale_factor,
                    .height = collider.height * scale_factor,
                };
                rl.DrawRectangleLinesEx(dest_rec, 1, rl.Color{ .r = 0, .g = 0, .b = 255, .a = 255 });
            }
        }
    }

    for (projectiles.items) |projectile| {
        var dest_pos = isoProject(projectile.pos.x, projectile.pos.y, 1);
        const dest_rect = rl.Rectangle{
            .x = dest_pos.x,
            .y = dest_pos.y,
            .width = 2 * scale_factor, // TODO(caleb): projectile size not just scaled 2x2
            .height = 2 * scale_factor,
        };
        rl.DrawRectanglePro(dest_rect, .{ .x = 0, .y = 0 }, 0, rl.Color{ .r = 34, .g = 35, .b = 35, .a = 255 });

        if (debug_projectile) {
            const start_pos = rl.Vector2{
                .x = projectile.start.x,
                .y = projectile.start.y,
            };
            var projected_start = isoProject(start_pos.x, start_pos.y, 1);
            var projected_end = isoProject(projectile.target.x, projectile.target.y, 1);
            rl.DrawLineV(projected_start, projected_end, rl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        }
    }

    if (tower_index_being_placed >= 0) {
        const tile_id = towers_data[@intCast(u32, tower_index_being_placed)].tile_id + @enumToInt(Direction.down) * 4 + tba_anim_frame;
        const dest_pos = isoProject(@intToFloat(f32, selected_tile_x), @intToFloat(f32, selected_tile_y), 1);
        drawTile(tileset, @intCast(u16, tile_id), dest_pos, scale_factor, rl.WHITE);
    }
}

fn drawDebugTextInfo(font: *rl.Font, towers: *ArrayList(Tower), projectiles: *ArrayList(Projectile), selected_tile_pos: rl.Vector2, screen_dim: rl.Vector2, debug_text_info: bool) !void {
    if (debug_text_info) {
        var strz_buffer: [256]u8 = undefined;
        var y_offset: f32 = 0;

        const fps_strz = try std.fmt.bufPrintZ(&strz_buffer, "FPS: {d}", .{rl.GetFPS()});
        y_offset += rl.MeasureTextEx(font.*, @ptrCast([*c]const u8, fps_strz), default_font_size, font_spacing).y;
        rl.DrawTextEx(font.*, @ptrCast([*c]const u8, fps_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset }, default_font_size, font_spacing, rl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 });

        const tower_count_strz = try std.fmt.bufPrintZ(&strz_buffer, "Tower count: {d}", .{towers.items.len});
        y_offset += rl.MeasureTextEx(font.*, @ptrCast([*c]const u8, tower_count_strz), default_font_size, font_spacing).y;
        rl.DrawTextEx(font.*, @ptrCast([*c]const u8, tower_count_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset }, default_font_size, font_spacing, rl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 });

        const mouse_tile_space_strz = try std.fmt.bufPrintZ(&strz_buffer, "Tile-space pos: ({d:.2}, {d:.2})", .{ selected_tile_pos.x, selected_tile_pos.y });
        y_offset += rl.MeasureTextEx(font.*, @ptrCast([*c]const u8, mouse_tile_space_strz), default_font_size, font_spacing).y;
        rl.DrawTextEx(font.*, @ptrCast([*c]const u8, mouse_tile_space_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset }, default_font_size, font_spacing, rl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 });

        const projectile_count_strz = try std.fmt.bufPrintZ(&strz_buffer, "Projectile count: {d}", .{projectiles.items.len});
        y_offset += rl.MeasureTextEx(font.*, @ptrCast([*c]const u8, projectile_count_strz), default_font_size, font_spacing).y;
        rl.DrawTextEx(font.*, @ptrCast([*c]const u8, projectile_count_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset }, default_font_size, font_spacing, rl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
    }
}

inline fn drawDebugOrigin(screen_mid: rl.Vector2, debug_origin: bool) void {
    if (debug_origin) {
        rl.DrawLineEx(screen_mid, rlm.Vector2Add(screen_mid, board_translation), 2, rl.Color{ .r = 0, .g = 255, .b = 0, .a = 255 });
    }
}

inline fn drawStatusBar(font: *rl.Font) !void {
    var strz_buffer: [256]u8 = undefined;
    var info_box_width: f32 = 0;
    const xy_pad_in_pixels = 10;

    var money_strz = try std.fmt.bufPrintZ(&strz_buffer, "MONEY:${d}", .{money});
    const byte_offset = std.zig.c_builtins.__builtin_strlen(@ptrCast([*c]const u8, money_strz)) + 1;
    const money_strz_dim = rl.MeasureTextEx(font.*, @ptrCast([*c]const u8, money_strz), default_font_size, font_spacing);
    info_box_width += money_strz_dim.x;

    const hp_strz = try std.fmt.bufPrintZ(strz_buffer[byte_offset..], "HP:{d}", .{hp});
    const hp_strz_dim = rl.MeasureTextEx(font.*, @ptrCast([*c]const u8, hp_strz), default_font_size, font_spacing);
    info_box_width += hp_strz_dim.x;

    const info_rec = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = info_box_width + xy_pad_in_pixels * 3,
        .height = hp_strz_dim.y + xy_pad_in_pixels * 2,
    };
    rl.DrawRectangleRec(info_rec, color_off_white);
    rl.DrawRectangleLinesEx(info_rec, 2, color_off_black);
    rl.DrawTextEx(font.*, @ptrCast([*c]const u8, money_strz), rl.Vector2{ .x = xy_pad_in_pixels, .y = xy_pad_in_pixels }, default_font_size, font_spacing, color_off_black);
    rl.DrawTextEx(font.*, @ptrCast([*c]const u8, hp_strz), rl.Vector2{ .x = money_strz_dim.x + xy_pad_in_pixels + xy_pad_in_pixels, .y = xy_pad_in_pixels }, default_font_size, font_spacing, color_off_black);
}

inline fn resetGameState(towers: *ArrayList(Tower), alive_enemies: *ArrayList(Enemy), dead_enemies: *ArrayList(Enemy)) void {
    towers.clearRetainingCapacity();
    alive_enemies.clearRetainingCapacity();
    dead_enemies.clearRetainingCapacity();
    money = 100;
    hp = 100;
    score = 0;
    round = 0;
}

pub fn main() !void {
    rl.SetConfigFlags(rl.ConfigFlags.FLAG_MSAA_4X_HINT);
    rl.InitWindow(sprite_width * board_width_in_tiles * @floatToInt(c_int, scale_factor), screenSpaceBoardHeight(), "twr-defns");
    rl.SetWindowState(rl.ConfigFlags.FLAG_WINDOW_RESIZABLE);
    rl.SetWindowState(rl.ConfigFlags.FLAG_VSYNC_HINT);
    rl.SetExitKey(rl.KeyboardKey.KEY_NULL);
    rl.SetTargetFPS(target_fps);
    rl.SetTraceLogLevel(@enumToInt(rl.TraceLogLevel.LOG_ERROR));

    const window_icon = rl.LoadImage("assets/icon.png");
    rl.SetWindowIcon(window_icon);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var ally = arena.allocator();
    var push_buffer = try ally.alloc(u8, 1024 * 10); // 10kb should be enough.
    var fba = std.heap.FixedBufferAllocator.init(push_buffer);

    rl.InitAudioDevice();
    var music = rl.LoadMusicStream("assets/grasslands.wav");
    rl.SetMasterVolume(0.1);
    rl.SetMusicVolume(music, 0.3);
    rl.PlayMusicStream(music);

    const shoot_sound = rl.LoadSound("assets/shoot.wav");
    const hit_sound = rl.LoadSound("assets/hit.wav");
    const dead_sound = rl.LoadSound("assets/ded.wav");
    rl.SetSoundVolume(shoot_sound, 0.5);
    rl.SetSoundVolume(hit_sound, 0.2);
    rl.SetSoundVolume(dead_sound, 0.2);

    var font = rl.LoadFont("assets/PICO-8_mono.ttf");
    var bg_tex = rl.LoadTexture("assets/bg.png");
    var splash_text_tex = rl.LoadTexture("assets/splash_text.png");
    var tileset_tex = rl.LoadTexture("assets/isosheet.png");
    var hor_osc_shader = rl.LoadShader(0, rl.TextFormat("src/hor_osc.fs", @intCast(c_int, 330)));
    rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "render_width"), &@intToFloat(f32, rl.GetScreenWidth()), @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));
    rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "render_height"), &@intToFloat(f32, rl.GetScreenHeight()), @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));

    var parser = std.json.Parser.init(ally, false);
    defer parser.deinit();

    var tileset: Tileset = undefined;
    tileset.tex = tileset_tex;
    tileset.tile_name_to_id = AutoHashMap(u64, u16).init(ally);
    {
        const tileset_file = try std.fs.cwd().openFile("assets/isosheet.tsj", .{});
        defer tileset_file.close();
        var raw_tileset_json = try tileset_file.reader().readAllAlloc(ally, 1024 * 5); // 5kib should be enough
        defer ally.free(raw_tileset_json);

        var parsed_tileset_data = try parser.parse(raw_tileset_json);

        const columns_value = parsed_tileset_data.root.Object.get("columns") orelse unreachable;
        tileset.columns = @intCast(u16, columns_value.Integer);

        const tile_data = parsed_tileset_data.root.Object.get("tiles") orelse unreachable;
        var enemy_id_count: u32 = 0;
        var tower_id_count: u32 = 0;
        for (tile_data.Array.items) |tile| {
            var tile_id = tile.Object.get("id") orelse unreachable;
            var tile_type = tile.Object.get("type") orelse unreachable;

            if (std.mem.eql(u8, tile_type.String, "enemy")) {
                std.debug.assert(enemy_id_count < enemies_data.len);
                enemies_data[enemy_id_count].tile_id = @intCast(u32, tile_id.Integer);
                enemy_id_count += 1;
            } else if (std.mem.eql(u8, tile_type.String, "tower")) {
                std.debug.assert(tower_id_count < towers_data.len);
                towers_data[tower_id_count].tile_id = @intCast(u32, tile_id.Integer);
                tower_id_count += 1;
            } else {
                try tileset.tile_name_to_id.put(hashString(tile_type.String), @intCast(u16, tile_id.Integer));
            }
        }
    }

    var board_map: Map = undefined;
    board_map.tile_indicies = ArrayList(u16).init(ally);
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
            try board_map.tile_indicies.append(@intCast(u16, tile_index.Integer));
        }

        var tilesets = parsed_map.root.Object.get("tilesets") orelse unreachable;
        std.debug.assert(tilesets.Array.items.len == 1);
        const first_gid = tilesets.Array.items[0].Object.get("firstgid") orelse unreachable;
        board_map.first_gid = @intCast(u16, first_gid.Integer);
    }

    var round_spawn_data: [60]RoundSpawns = undefined;
    {
        const round_info_file = try std.fs.cwd().openFile("assets/round_info.json", .{});
        defer round_info_file.close();
        var round_info_json = try round_info_file.reader().readAllAlloc(ally, 1024 * 10);
        defer ally.free(round_info_json);

        parser.reset();
        var parsed_round_info = try parser.parse(round_info_json);
        const round_spawn_data_property = parsed_round_info.root.Object.get("round_spawn_data") orelse unreachable;
        for (round_spawn_data_property.Array.items) |group_spawn_data, group_spawn_data_index| {
            for (group_spawn_data.Array.items) |group_spawn_data_entry, group_spawn_data_entry_index| {
                const kind = group_spawn_data_entry.Object.get("kind") orelse unreachable;
                const spawn_count = group_spawn_data_entry.Object.get("spawn_count") orelse unreachable;
                const time_between_spawns_ms = group_spawn_data_entry.Object.get("time_between_spawns_ms") orelse unreachable;

                round_spawn_data[group_spawn_data_index].group_spawn_data[group_spawn_data_entry_index] = GroupSpawnData{
                    .kind = @intToEnum(EnemyKind, @intCast(u32, kind.Integer)),
                    .spawn_count = @intCast(u32, spawn_count.Integer),
                    .time_between_spawns_ms = @intCast(u16, time_between_spawns_ms.Integer),
                };
            }
            round_spawn_data[group_spawn_data_index].unique_enemies_for_this_round = @intCast(u8, group_spawn_data.Array.items.len);
        }
    }

    var game_mode = GameMode.title_screen;

    var debug_projectile = false;
    var debug_origin = false;
    var debug_bg_scroll = false;
    var debug_hit_boxes = false;
    var debug_text_info = false;

    var towers = std.ArrayList(Tower).init(ally);
    defer towers.deinit();
    var alive_enemies = std.ArrayList(Enemy).init(ally);
    defer alive_enemies.deinit();
    var dead_enemies = std.ArrayList(Enemy).init(ally);
    defer dead_enemies.deinit();
    var projectiles = std.ArrayList(Projectile).init(ally);
    defer projectiles.deinit();

    var bg_offset: f32 = 0;
    var splash_text_pos = rl.Vector2{
        .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - @intToFloat(f32, splash_text_tex.width) * initial_scale_factor / 2.0,
        .y = -@intToFloat(f32, splash_text_tex.height) * initial_scale_factor,
    };
    var bg_poses = startBGPoses();
    var hot_button_index: i32 = -1;
    var prev_frame_screen_dim = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()), .y = @intToFloat(f32, rl.GetScreenHeight()) };
    var prev_frame_input = Input{ .l_mouse_button_is_down = false, .mouse_pos = rl.Vector2{ .x = 0, .y = 0 } };
    var last_time_ms = rl.GetTime() * 1000;

    var round_in_progress = false;
    var selected_tower: ?*Tower = null;
    var tower_index_being_placed: i32 = -1;

    var tba_anim_frame: u8 = 0;
    var tba_anim_timer: u8 = 0;
    var this_round_gsd: [@enumToInt(EnemyKind.count)]GroupSpawnData = undefined;
    for (this_round_gsd) |*gsd_entry| {
        gsd_entry.time_between_spawns_ms = 0;
        gsd_entry.spawn_count = 0;
    }

    var enemy_start_tile_y: u32 = 0;
    var enemy_start_tile_x: u32 = 0;
    {
        const track_start_id = tileset.tile_name_to_id.get(hashString("track_start")) orelse unreachable;
        var found_enemy_start_tile = false;
        outer: while (enemy_start_tile_y < board_height_in_tiles) : (enemy_start_tile_y += 1) {
            enemy_start_tile_x = 0;
            while (enemy_start_tile_x < board_width_in_tiles) : (enemy_start_tile_x += 1) {
                const ts_id = board_map.tileIDFromCoord(enemy_start_tile_x, enemy_start_tile_y) orelse continue;
                if ((ts_id) == track_start_id) {
                    found_enemy_start_tile = true;
                    break :outer;
                }
            }
        }
        std.debug.assert(found_enemy_start_tile);
    }

    game_loop: while (!rl.WindowShouldClose()) {
        rl.UpdateMusicStream(music);

        const screen_dim = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()), .y = @intToFloat(f32, rl.GetScreenHeight()) };
        const screen_mid = rl.Vector2{
            .x = screen_dim.x / 2,
            .y = screen_dim.y / 2,
        };
        const mouse_pos = rl.GetMousePosition();
        scale_factor = clampf32(scale_factor + rl.GetMouseWheelMove(), 1, 10);
        var selected_tile_pos = isoProjectInverted(mouse_pos.x - sprite_width * scale_factor / 2, mouse_pos.y, 0);
        const selected_tile_x = @floatToInt(i32, @floor(selected_tile_pos.x));
        const selected_tile_y = @floatToInt(i32, @floor(selected_tile_pos.y));

        if (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_MIDDLE))
            board_translation = rlm.Vector2Add(board_translation, rl.GetMouseDelta());

        if (rlm.Vector2Equals(prev_frame_screen_dim, screen_dim) == 0) {
            bg_poses = startBGPoses();
            splash_text_pos = rl.Vector2{
                .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - @intToFloat(f32, splash_text_tex.width) * initial_scale_factor / 2.0,
                .y = -@intToFloat(f32, splash_text_tex.height) * initial_scale_factor,
            };
            rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "render_width"), &screen_dim.x, @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));
            rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "render_height"), &screen_dim.y, @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));
        }
        const time_in_seconds = @floatCast(f32, rl.GetTime());
        rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "time_in_seconds"), &time_in_seconds, @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));

        bg_offset = @intToFloat(f32, @floatToInt(u32, bg_offset + 0.25) % 30);
        // for (bg_poses) |*bg_pos| {
        //     bg_pos.* = rlm.Vector2Add(bg_pos.*, bg_pos_move);
        //     if (bg_pos.x > screen_dim.x) {
        //         bg_pos.x = -screen_dim.x + (bg_pos.x - screen_dim.x);
        //     } else if (bg_pos.x < -screen_dim.x) {
        //         bg_pos.x = screen_dim.x - (-screen_dim.x - bg_pos.x);
        //     }
        //     if (bg_pos.y > screen_dim.y) {
        //         bg_pos.y = -screen_dim.y + (bg_pos.y - screen_dim.y);
        //     } else if (bg_pos.y < -screen_dim.y) {
        //         bg_pos.y = screen_dim.y - (-screen_dim.y - bg_pos.y);
        //     }
        // }

        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_F1)) {
            debug_projectile = !debug_projectile;
            debug_origin = !debug_origin;
            debug_bg_scroll = !debug_bg_scroll;
            debug_hit_boxes = !debug_hit_boxes;
            debug_text_info = !debug_text_info;
        }

        switch (game_mode) {
            .title_screen => {
                // Title-screen update -------------------------------------------------------------------------
                const fall_speed_scalar = 4;
                const splash_rec = rl.Rectangle{
                    .x = splash_text_pos.x,
                    .y = splash_text_pos.y,
                    .width = @intToFloat(f32, splash_text_tex.width) * initial_scale_factor,
                    .height = @intToFloat(f32, splash_text_tex.height) * initial_scale_factor,
                };
                var splash_text_in_mid = false;
                var y_offset: f32 = 0;
                if (splash_text_pos.y + @intToFloat(f32, splash_text_tex.height) * initial_scale_factor / 2 <= screen_mid.y - @intToFloat(f32, splash_text_tex.height)) {
                    splash_text_pos.y += 100 * fall_speed_scalar / target_fps;
                } else {
                    splash_text_in_mid = true;
                    y_offset = @sin(time_in_seconds * 10) * 10;
                }

                var button_dest_recs: [2]rl.Rectangle = undefined;
                for (button_dest_recs) |*rec, rec_index| {
                    rec.x = splash_rec.x + sprite_width * initial_scale_factor * @intToFloat(f32, rec_index) +
                        (splash_rec.width - sprite_width * initial_scale_factor * @intToFloat(f32, button_dest_recs.len)) / 2;
                    rec.y = splash_rec.y + splash_rec.height;
                    rec.width = sprite_width * initial_scale_factor;
                    rec.height = sprite_height * initial_scale_factor;

                    if ((rl.CheckCollisionPointRec(mouse_pos, rec.*)) and
                        (!prev_frame_input.l_mouse_button_is_down) and
                        (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT)))
                    {
                        hot_button_index = @intCast(i32, rec_index);
                    } else if (@intCast(i32, rec_index) == hot_button_index and !rl.CheckCollisionPointRec(mouse_pos, rec.*)) {
                        hot_button_index = -1;
                    }

                    if (@intCast(i32, rec_index) == hot_button_index) {
                        rec.x += sprite_width * initial_scale_factor * 0.1 / 2.0;
                        rec.y += sprite_height * initial_scale_factor * 0.1 / 2.0;
                        rec.width *= 0.9;
                        rec.height *= 0.9;
                    }

                    if (@intCast(i32, rec_index) == hot_button_index and rl.IsMouseButtonReleased(rl.MouseButton.MOUSE_BUTTON_LEFT)) {
                        if (rec_index == 0) { // Play button
                            resetGameState(&towers, &alive_enemies, &dead_enemies);
                            game_mode = GameMode.running;
                        } else if (rec_index == 1) { // Quit button
                            break :game_loop;
                        }
                    }
                }

                prev_frame_input.mouse_pos = mouse_pos;
                prev_frame_input.l_mouse_button_is_down = rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT);
                prev_frame_screen_dim = screen_dim;

                // Title-screen render -------------------------------------------------------------------------
                rl.BeginDrawing();
                drawBackground(screen_dim, bg_offset, debug_bg_scroll, &bg_poses, &bg_tex, &hor_osc_shader);
                drawBoard(&board_map, &tileset, -1, -1, null, -1);
                rl.DrawTextureEx(splash_text_tex, rl.Vector2{ .x = splash_text_pos.x, .y = splash_text_pos.y + y_offset }, 0, initial_scale_factor, rl.WHITE);
                if (splash_text_in_mid) {
                    drawTile(&tileset, tileset.tile_name_to_id.get(hashString("play_button")).?, rl.Vector2{ .x = button_dest_recs[0].x, .y = button_dest_recs[0].y }, initial_scale_factor, rl.WHITE);
                    drawTile(&tileset, tileset.tile_name_to_id.get(hashString("quit_button")).?, rl.Vector2{ .x = button_dest_recs[1].x, .y = button_dest_recs[1].y }, initial_scale_factor, rl.WHITE);
                }
                rl.EndDrawing();
            },
            .game_over => {
                // Game over update -------------------------------------------------------------------------
                var strz_buffer: [256]u8 = undefined;
                const game_over_font_size = 18;
                const game_over_strz = try std.fmt.bufPrintZ(&strz_buffer, "GAME OVER! -- SCORE: {d}", .{score});
                const game_over_strz_dim = rl.MeasureTextEx(font, @ptrCast([*c]const u8, game_over_strz), game_over_font_size, font_spacing);
                const start_y = screen_mid.y + @sin(time_in_seconds * 10) * 5;
                const game_over_strz_pos = rl.Vector2{ .x = screen_mid.x - game_over_strz_dim.x / 2, .y = start_y };
                const game_over_popup_rec = rl.Rectangle{
                    .x = screen_mid.x - game_over_strz_dim.x / 2 - (sprite_width * initial_scale_factor * 3 - game_over_strz_dim.x) / 2,
                    .y = game_over_strz_pos.y,
                    .width = sprite_width * initial_scale_factor * 3,
                    .height = game_over_strz_dim.y + sprite_height * initial_scale_factor,
                };

                var button_dest_recs: [3]rl.Rectangle = undefined;
                for (button_dest_recs) |*rec, rec_index| {
                    rec.x = game_over_popup_rec.x + sprite_width * initial_scale_factor * @intToFloat(f32, rec_index);
                    rec.y = game_over_strz_pos.y + game_over_strz_dim.y;
                    rec.width = sprite_width * initial_scale_factor;
                    rec.height = sprite_height * initial_scale_factor;

                    if ((rl.CheckCollisionPointRec(mouse_pos, rec.*)) and
                        (!prev_frame_input.l_mouse_button_is_down) and
                        (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT)))
                    {
                        hot_button_index = @intCast(i32, rec_index);
                    } else if (@intCast(i32, rec_index) == hot_button_index and !rl.CheckCollisionPointRec(mouse_pos, rec.*)) {
                        hot_button_index = -1;
                    }

                    if (@intCast(i32, rec_index) == hot_button_index) {
                        rec.x += sprite_width * initial_scale_factor * 0.1 / 2.0;
                        rec.y += sprite_height * initial_scale_factor * 0.1 / 2.0;
                        rec.width *= 0.9;
                        rec.height *= 0.9;
                    }

                    if (@intCast(i32, rec_index) == hot_button_index and rl.IsMouseButtonReleased(rl.MouseButton.MOUSE_BUTTON_LEFT)) {
                        if (rec_index == 0) {
                            resetGameState(&towers, &alive_enemies, &dead_enemies);
                            game_mode = GameMode.running;
                        } else if (rec_index == 1) {
                            resetGameState(&towers, &alive_enemies, &dead_enemies);
                            game_mode = GameMode.title_screen;
                            splash_text_pos = rl.Vector2{
                                .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - @intToFloat(f32, splash_text_tex.width) * initial_scale_factor / 2.0,
                                .y = -@intToFloat(f32, splash_text_tex.height) * initial_scale_factor,
                            };
                        } else if (rec_index == 2) {
                            break :game_loop;
                        }
                    }
                }

                prev_frame_input.mouse_pos = mouse_pos;
                prev_frame_input.l_mouse_button_is_down = rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT);
                prev_frame_screen_dim = screen_dim;

                // Game over render -------------------------------------------------------------------------
                rl.BeginDrawing();
                drawBackground(screen_dim, bg_offset, debug_bg_scroll, &bg_poses, &bg_tex, &hor_osc_shader);
                drawBoard(&board_map, &tileset, selected_tile_x, selected_tile_y, selected_tower, tower_index_being_placed);
                try drawSprites(&fba, &tileset, debug_hit_boxes, debug_projectile, &towers, &alive_enemies, &projectiles, selected_tile_x, selected_tile_y, tower_index_being_placed, tba_anim_frame);
                try drawDebugTextInfo(&font, &towers, &projectiles, selected_tile_pos, screen_dim, debug_text_info);
                drawDebugOrigin(screen_mid, debug_origin);
                try drawStatusBar(&font);
                rl.DrawTextEx(font, @ptrCast([*c]const u8, game_over_strz), game_over_strz_pos, game_over_font_size, font_spacing, color_off_black);
                drawTile(&tileset, tileset.tile_name_to_id.get(hashString("retry_button")).?, rl.Vector2{ .x = button_dest_recs[0].x, .y = button_dest_recs[0].y }, initial_scale_factor, rl.WHITE);
                drawTile(&tileset, tileset.tile_name_to_id.get(hashString("menu_button")).?, rl.Vector2{ .x = button_dest_recs[1].x, .y = button_dest_recs[1].y }, initial_scale_factor, rl.WHITE);
                drawTile(&tileset, tileset.tile_name_to_id.get(hashString("quit_button")).?, rl.Vector2{ .x = button_dest_recs[2].x, .y = button_dest_recs[2].y }, initial_scale_factor, rl.WHITE);
                rl.EndDrawing();
            },
            .running => {
                const dtime_ms = @floatCast(f32, rl.GetTime() * 1000 - last_time_ms);

                // Towers -------------------------------------------------------------------------
                for (towers.items) |*tower| {
                    tower.anim_timer += 1;
                    if (tower.anim_timer >= @divTrunc(target_fps, anim_frames_speed)) {
                        tower.anim_timer = 0;
                        tower.anim_frame += 1;
                        if (tower.anim_frame > 3)
                            tower.anim_frame = 0;
                    }
                    tower.fire_rate_timer += 1;
                    if (tower.fire_rate_timer >= @divTrunc(target_fps, tower.fire_rate)) {
                        tower.fire_rate_timer = 0;
                        for (alive_enemies.items) |*enemy| {
                            const enemy_tile_x = @floatToInt(i32, @floor(enemy.pos.x));
                            const enemy_tile_y = @floatToInt(i32, @floor(enemy.pos.y));
                            if (std.math.absCast(enemy_tile_x - @intCast(i32, tower.tile_x)) + std.math.absCast(enemy_tile_y - @intCast(i32, tower.tile_y)) <= towers_data[@enumToInt(tower.kind)].range) {
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
                                var screen_space_start = isoProject(tower_pos.x, tower_pos.y, 0);
                                screen_space_start.x += sprite_width * scale_factor / 2;
                                screen_space_start.y -= sprite_height * scale_factor / 4; // TODO(caleb): Use sprite offsets here
                                const tile_space_start = isoProjectInverted(screen_space_start.x, screen_space_start.y, 1);

                                var screen_space_target = isoProject(enemy.pos.x, enemy.pos.y, 0);
                                screen_space_target.x += sprite_width * scale_factor / 2;
                                const tile_space_target = isoProjectInverted(screen_space_target.x, screen_space_target.y, 1);

                                const new_projectile = Projectile{
                                    .direction = rlm.Vector2Normalize(rlm.Vector2Subtract(tile_space_target, tile_space_start)),
                                    .target = tile_space_target,
                                    .start = tile_space_start,
                                    .pos = tile_space_start,
                                    .speed = @intToFloat(f32, tower.fire_speed) / target_fps,
                                    .damage = towers_data[@enumToInt(tower.kind)].damage,
                                };
                                try projectiles.append(new_projectile);
                                break;
                            }
                        }
                    }
                }

                var clicked_on_a_tower = false;
                if (rl.IsMouseButtonReleased(rl.MouseButton.MOUSE_BUTTON_LEFT)) {
                    if ((selected_tile_x < board_width_in_tiles) and (selected_tile_y < board_height_in_tiles) and
                        (selected_tile_x >= 0) and (selected_tile_y >= 0))
                    {
                        for (towers.items) |*tower| {
                            if ((tower.tile_x == @intCast(u32, selected_tile_x)) and
                                (tower.tile_y == @intCast(u32, selected_tile_y)))
                            {
                                clicked_on_a_tower = true;
                                selected_tower = tower;
                                break;
                            }
                        }
                    }
                    if (!clicked_on_a_tower) {
                        selected_tower = null;
                    }
                }

                if (tower_index_being_placed >= 0 and rl.IsMouseButtonReleased(rl.MouseButton.MOUSE_BUTTON_LEFT)) {
                    if ((selected_tile_x < board_width_in_tiles) and (selected_tile_y < board_height_in_tiles) and
                        (selected_tile_x >= 0) and (selected_tile_y >= 0))
                    {
                        const tile_index = board_map.tile_indicies.items[@intCast(u32, selected_tile_y * board_width_in_tiles + selected_tile_x)];
                        if (!tileset.isTrackTile(tile_index) and !clicked_on_a_tower and money >=
                            @intCast(i32, towers_data[@intCast(u32, tower_index_being_placed)].cost))
                        {
                            selected_tower = null;
                            const new_tower = Tower{
                                .kind = @intToEnum(TowerKind, tower_index_being_placed),
                                .direction = Direction.down,
                                .tile_x = @intCast(u16, selected_tile_x),
                                .tile_y = @intCast(u16, selected_tile_y),
                                .fire_rate = towers_data[@intCast(u32, tower_index_being_placed)].fire_rate,
                                .fire_speed = towers_data[@intCast(u32, tower_index_being_placed)].fire_speed,
                                .fire_rate_timer = 0,
                                .anim_frame = 0,
                                .anim_timer = 0,
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
                            money -= @intCast(i32, towers_data[@intCast(u32, tower_index_being_placed)].cost);
                        }
                    }
                    tower_index_being_placed = -1;
                }

                // Projectiles -------------------------------------------------------------------------
                var projectile_index: i32 = 0;
                outer: while (projectile_index < projectiles.items.len) : (projectile_index += 1) {
                    var projectile = &projectiles.items[@intCast(u32, projectile_index)];
                    var projected_projectile_pos = isoProject(projectile.pos.x, projectile.pos.y, 1);
                    if ((@floor(projectile.pos.x) > board_width_in_tiles * 2) or
                        (@floor(projectile.pos.y) > board_height_in_tiles * 2) or
                        (projectile.pos.x < -board_width_in_tiles) or (projectile.pos.y < -board_height_in_tiles))
                    {
                        _ = projectiles.orderedRemove(@intCast(u32, projectile_index));
                        projectile_index -= 1;
                        continue;
                    }
                    for (alive_enemies.items) |*enemy| {
                        for (enemy.colliders) |collider| {
                            const projected_collider_pos = isoProject(collider.x, collider.y, 1);
                            const projected_collider_rec = rl.Rectangle{
                                .x = projected_collider_pos.x,
                                .y = projected_collider_pos.y,
                                .width = collider.width * scale_factor,
                                .height = collider.height * scale_factor,
                            };
                            const projected_projectile_rec = rl.Rectangle{
                                .x = projected_projectile_pos.x,
                                .y = projected_projectile_pos.y,
                                .width = 2 * scale_factor,
                                .height = 2 * scale_factor,
                            };
                            if (rl.CheckCollisionRecs(projected_projectile_rec, projected_collider_rec)) {
                                enemy.hp -= @intCast(i32, projectile.damage);
                                _ = projectiles.orderedRemove(@intCast(u32, projectile_index));
                                projectile_index -= 1;
                                rl.PlaySound(hit_sound);
                                continue :outer;
                            }
                        }
                    }

                    projectile.pos = rlm.Vector2Add(projectile.pos, rlm.Vector2Scale(projectile.direction, projectile.speed));
                }

                // Enemies -------------------------------------------------------------------------
                if (round_in_progress) {
                    std.debug.assert(round > 0);
                    const rsd = round_spawn_data[(round - 1) % round_spawn_data.len];
                    for (rsd.group_spawn_data[0..rsd.unique_enemies_for_this_round]) |gsd_entry, gsd_index| {
                        this_round_gsd[gsd_index].time_between_spawns_ms += @floatToInt(u16, dtime_ms);
                        if ((this_round_gsd[gsd_index].time_between_spawns_ms >= gsd_entry.time_between_spawns_ms) and
                            (this_round_gsd[gsd_index].spawn_count < gsd_entry.spawn_count))
                        {
                            var new_enemy: Enemy = undefined;
                            new_enemy.kind = gsd_entry.kind;
                            new_enemy.direction = Direction.left; // TODO(caleb): Choose a start direction smartly?
                            new_enemy.last_step_direction = Direction.left;
                            new_enemy.pos = rl.Vector2{ .x = @intToFloat(f32, enemy_start_tile_x), .y = @intToFloat(f32, enemy_start_tile_y) };
                            new_enemy.hp = @intCast(i32, enemies_data[@enumToInt(gsd_entry.kind)].hp);
                            new_enemy.tile_steps_per_second = enemies_data[@enumToInt(gsd_entry.kind)].tile_steps_per_second;
                            new_enemy.tile_step_timer = 0;
                            new_enemy.anim_frame = 0;
                            new_enemy.anim_timer = 0;
                            new_enemy.initColliders();
                            try alive_enemies.append(new_enemy);

                            this_round_gsd[gsd_index].time_between_spawns_ms = 0;
                            this_round_gsd[gsd_index].spawn_count += 1;
                        }
                    }
                }

                var alive_enemy_index: i32 = 0;
                while (alive_enemy_index < alive_enemies.items.len) : (alive_enemy_index += 1) {
                    var enemy = &alive_enemies.items[@intCast(u32, alive_enemy_index)];
                    if (enemy.hp <= 0) { // Handle death stuff now
                        rl.PlaySound(dead_sound);
                        money += @intCast(i32, @enumToInt(enemy.kind)) + 1;
                        try dead_enemies.append(alive_enemies.orderedRemove(@intCast(u32, alive_enemy_index)));
                        alive_enemy_index -= 1;
                        continue;
                    } else if (!boundsCheck(@floatToInt(i32, @floor(enemy.pos.x)), @floatToInt(i32, @floor(enemy.pos.y)))) { // End of track
                        _ = alive_enemies.orderedRemove(@intCast(u32, alive_enemy_index));
                        hp = @max(0, hp - enemy.hp);
                        alive_enemy_index -= 1;
                        continue;
                    }

                    enemy.anim_timer += 1;
                    if (enemy.anim_timer >= @divTrunc(target_fps, anim_frames_speed)) {
                        enemy.anim_timer = 0;
                        enemy.anim_frame += 1;
                        if (enemy.anim_frame > 3)
                            enemy.anim_frame = 0;
                    }
                    enemy.tile_step_timer += 1;
                    if (enemy.tile_step_timer >= @divTrunc(target_fps, enemy.tile_steps_per_second)) {
                        enemy.tile_step_timer = 0;
                        var i: f32 = 0; // Update n times this frame if needed.
                        while (i < 1) : (i += target_fps / @intToFloat(f32, enemy.tile_steps_per_second))
                            updateEnemy(&tileset, &board_map, enemy);
                    }
                }
                var dead_enemy_index: i32 = 0;
                while (dead_enemy_index < dead_enemies.items.len) : (dead_enemy_index += 1) {
                    // TODO(caleb): Remove after death anim is done playing.
                    _ = dead_enemies.orderedRemove(@intCast(u32, dead_enemy_index));
                }

                // Round  -------------------------------------------------------------------------
                var round_start_rec = rl.Rectangle{
                    .x = screen_dim.x - sprite_width * initial_scale_factor,
                    .y = screen_dim.y - sprite_height * initial_scale_factor,
                    .width = sprite_height * initial_scale_factor,
                    .height = sprite_height * initial_scale_factor,
                };
                if (!round_in_progress) {
                    if ((rl.CheckCollisionPointRec(mouse_pos, round_start_rec)) and
                        (!prev_frame_input.l_mouse_button_is_down) and
                        (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT)))
                    {
                        hot_button_index = 1; // NOTE(caleb): This can be set to anything
                    } else if (!rl.CheckCollisionPointRec(mouse_pos, round_start_rec)) {
                        hot_button_index = -1;
                    }
                    if (hot_button_index != -1) {
                        round_start_rec.x += sprite_width * initial_scale_factor * 0.1 / 2.0;
                        round_start_rec.y += sprite_height * initial_scale_factor * 0.1 / 2.0;
                        round_start_rec.width *= 0.9;
                        round_start_rec.height *= 0.9;
                    }
                    if (hot_button_index != -1 and rl.IsMouseButtonReleased(rl.MouseButton.MOUSE_BUTTON_LEFT)) { // Begin next round
                        hot_button_index = -1;
                        round_in_progress = true;
                        round += 1;
                    }
                } else if (round_in_progress) {
                    std.debug.assert(round > 0);
                    const rsd = round_spawn_data[(round - 1) % round_spawn_data.len];
                    var everything_was_spawned = true;
                    for (this_round_gsd) |gsd_entry, gsd_index| {
                        if (gsd_entry.spawn_count < rsd.group_spawn_data[gsd_index].spawn_count) {
                            everything_was_spawned = false;
                            break;
                        }
                    }
                    if (everything_was_spawned and alive_enemies.items.len == 0) { // End round
                        round_in_progress = false;
                    }
                }

                // Tower buy area -------------------------------------------------------------------------
                const tower_buy_item_dim = rl.Vector2{
                    .x = sprite_width * initial_scale_factor * tower_buy_area_sprite_scale,
                    .y = sprite_height * initial_scale_factor * tower_buy_area_sprite_scale,
                };
                const tower_buy_area_rows = @floatToInt(u32, @ceil(@intToFloat(f32, towers_data.len) / tower_buy_area_towers_per_row));
                const buy_area_rec = rl.Rectangle{
                    .x = screen_dim.x - tower_buy_item_dim.x * tower_buy_area_towers_per_row,
                    .y = 0,
                    .width = tower_buy_item_dim.x * tower_buy_area_towers_per_row,
                    .height = tower_buy_item_dim.y * @intToFloat(f32, tower_buy_area_rows),
                };

                tba_anim_timer += 1;
                if (tba_anim_timer >= @divTrunc(target_fps, anim_frames_speed)) {
                    tba_anim_timer = 0;
                    tba_anim_frame += 1;
                    if (tba_anim_frame > 3) tba_anim_frame = 0;
                }

                if ((tower_index_being_placed < 0) and
                    (rl.CheckCollisionPointRec(mouse_pos, buy_area_rec)) and
                    (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT)) and
                    (!prev_frame_input.l_mouse_button_is_down))
                {
                    var selected_row: u32 = 0;
                    var selected_col: u32 = 0;
                    outer: while (selected_row < tower_buy_area_rows) : (selected_row += 1) {
                        selected_col = 0;
                        const towers_for_this_row = @min(tower_buy_area_towers_per_row, towers_data.len - selected_row * tower_buy_area_towers_per_row);
                        while (selected_col < towers_for_this_row) : (selected_col += 1) {
                            const tower_buy_item_rec = rl.Rectangle{
                                .x = buy_area_rec.x + @intToFloat(f32, selected_col) * tower_buy_item_dim.x,
                                .y = buy_area_rec.y + @intToFloat(f32, selected_row) * tower_buy_item_dim.y,
                                .width = tower_buy_item_dim.x,
                                .height = tower_buy_item_dim.y,
                            };

                            if (rl.CheckCollisionPointRec(mouse_pos, tower_buy_item_rec)) {
                                selected_tower = null;
                                tower_index_being_placed = @intCast(i32, selected_row * tower_buy_area_towers_per_row + selected_col);
                                break :outer;
                            }
                        }
                    }
                }

                // Misc updates -------------------------------------------------------------------------
                if (hp <= 0) game_mode = GameMode.game_over;
                prev_frame_input.l_mouse_button_is_down = rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT);
                prev_frame_screen_dim = screen_dim;
                last_time_ms = rl.GetTime() * 1000;

                // Render -------------------------------------------------------------------------
                rl.BeginDrawing();
                drawBackground(screen_dim, bg_offset, debug_bg_scroll, &bg_poses, &bg_tex, &hor_osc_shader);
                drawBoard(&board_map, &tileset, selected_tile_x, selected_tile_y, selected_tower, tower_index_being_placed);
                try drawSprites(&fba, &tileset, debug_hit_boxes, debug_projectile, &towers, &alive_enemies, &projectiles, selected_tile_x, selected_tile_y, tower_index_being_placed, tba_anim_frame);

                rl.DrawRectangleRec(buy_area_rec, color_off_white);
                var row_index: u32 = 0;
                while (row_index < tower_buy_area_rows) : (row_index += 1) {
                    var col_index: u32 = 0;
                    const towers_for_this_row = @min(tower_buy_area_towers_per_row, towers_data.len - row_index * tower_buy_area_towers_per_row);
                    while (col_index < towers_for_this_row) : (col_index += 1) {
                        const tower_data = towers_data[row_index * towers_for_this_row + col_index];
                        const ts_id = tower_data.tile_id + @enumToInt(Direction.down) * 4 + tba_anim_frame;
                        const target_tile_row = @divTrunc(ts_id, tileset.columns);
                        const target_tile_column = @mod(ts_id, tileset.columns);
                        const source_rect = rl.Rectangle{
                            .x = @intToFloat(f32, target_tile_column * sprite_width),
                            .y = @intToFloat(f32, target_tile_row * sprite_height),
                            .width = sprite_width,
                            .height = sprite_height,
                        };
                        const tower_buy_item_rec = rl.Rectangle{
                            .x = buy_area_rec.x + @intToFloat(f32, col_index) * tower_buy_item_dim.x,
                            .y = buy_area_rec.y + @intToFloat(f32, row_index) * tower_buy_item_dim.y,
                            .width = tower_buy_item_dim.x,
                            .height = tower_buy_item_dim.y,
                        };
                        const tint = if (@intCast(i32, tower_data.cost) > money) rl.GRAY else rl.WHITE;
                        rl.DrawTexturePro(tileset.tex, source_rect, tower_buy_item_rec, .{ .x = 0, .y = 0 }, 0, tint);

                        // TODO(caleb): Show cost ( possibly other info as well ) on hover.
                        // const cost_bottom_pad_px = 2;
                        // const cost_strz = try std.fmt.bufPrintZ(&strz_buffer, "${d}", .{tower_data.cost});
                        // const cost_strz_dim = rl.MeasureTextEx(font, @ptrCast([*c]const u8, cost_strz), default_font_size, font_spacing);
                        // const cost_strz_pos = rl.Vector2{
                        //     .x = buy_area_rec.x + @intToFloat(f32, col_index) * tower_buy_item_dim.x + (tower_buy_item_dim.x - cost_strz_dim.x) / 2,
                        //     .y = buy_area_rec.y + @intToFloat(f32, row_index) * tower_buy_item_dim.y + (tower_buy_item_dim.y - cost_strz_dim.y - cost_bottom_pad_px),
                        // };
                        // rl.DrawRectangleV(rl.Vector2{ .x = tower_buy_item_rec.x, .y = tower_buy_item_rec.y - cost_strz_dim.y }, rl.Vector2{ .x = tower_buy_item_rec.width, .y = cost_strz_dim.y }, tint);
                        // rl.DrawTextEx(font, @ptrCast([*c]const u8, cost_strz), cost_strz_pos, default_font_size, font_spacing, color_off_black);
                        rl.DrawRectangleLinesEx(tower_buy_item_rec, 2, color_off_black);
                    }
                }

                const round_start_button_tint = if (round_in_progress) rl.GRAY else rl.WHITE;
                drawTile(&tileset, tileset.tile_name_to_id.get(hashString("play_button")).?, rl.Vector2{ .x = round_start_rec.x, .y = round_start_rec.y }, initial_scale_factor, round_start_button_tint);
                try drawStatusBar(&font);
                try drawDebugTextInfo(&font, &towers, &projectiles, selected_tile_pos, screen_dim, debug_text_info);
                drawDebugOrigin(screen_mid, debug_origin);
                rl.EndDrawing();
            },
        }
    }

    rl.CloseWindow();
}
