const std = @import("std");
const rl = @import("raylib");
const rlm = @import("raylib-math");

const initial_scale_factor = 4;
var scale_factor: f32 = initial_scale_factor;
var board_translation = rl.Vector2{ .x = 0, .y = 0 };
var monies: i32 = 100;

const target_fps = 60;
const tower_buy_area_sprite_scale = 0.6;
const tower_buy_area_towers_per_row = 1;
const tba_font_size = 14;
const font_size = 18;
const font_spacing = 2;
const board_width_in_tiles = 16;
const board_height_in_tiles = 16;
const sprite_width = 32;
const sprite_height = 32;

// TODO(caleb):
// *Treat tiles as draw buffer entries. ( One way to do it would be moving tiles to an array list just like enemies, towers, bullets, etc...)

const anim_frames_speed = 7;

const color_off_black = rl.Color{ .r = 34, .g = 35, .b = 35, .a = 255 };
const color_off_white = rl.Color{ .r = 240, .g = 246, .b = 240, .a = 255 };

const Tileset = struct {
    columns: u32,
    track_start_id: u32,
    track_id: u32,
    tex: rl.Texture,

    pub inline fn isTrackTile(self: Tileset, target_tile_id: u32) bool {
        var result = false;
        if ((self.track_start_id == target_tile_id) or
            (self.track_id == target_tile_id))
        {
            result = true;
        }
        return result;
    }
};

const Map = struct {
    tile_indicies: std.ArrayList(u32),
    first_gid: u32,

    pub fn tileIDFromCoord(self: *Map, tile_x: u32, tile_y: u32) ?u32 {
        std.debug.assert(tile_y * board_width_in_tiles + tile_x < self.*.tile_indicies.items.len);
        const ts_id = self.tile_indicies.items[tile_y * board_width_in_tiles + tile_x];
        return if (@intCast(i32, ts_id) - @intCast(i32, self.*.first_gid) < 0) null else @intCast(u32, @intCast(i32, ts_id) - @intCast(i32, self.*.first_gid));
    }
};

const Direction = enum(u32) {
    left = 0,
    up,
    down,
    right,
};

// NOTE(caleb): Enemy data is read-only ( with exception of tile_id on init ). It is what is used
//  to determine how to initialize an Enemy.
const EnemyData = struct {
    hp: u32,
    move_speed: f32,
    tile_id: u32,

    // TODO(caleb): Sprite offset data should be saved as tileset json
    // and read into tileset struct. also applies to TowerData
    sprite_offset_x: u16,
    sprite_offset_y: u16,
    tile_steps_per_second: u8,
};

// Where enemy kind can act as an index into enemy data.
const EnemyKind = enum(u32) {
    gremlin_wiz_guy = 0,
};

var enemies_data = [_]EnemyData{
    EnemyData{ // Gremlin wiz guy
        .hp = 10,
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

    // Update collider positions rel to enemy pos.
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

// NOTE(caleb): Same idea here as with ^^^ EnemyData ^^^
const TowerData = struct {
    damage: u32,
    tile_id: u32,
    range: u16,
    sprite_offset_x: u16,
    sprite_offset_y: u16,
    fire_rate: u8,
    fire_speed: u8,
};

var towers_data = [_]TowerData{
    TowerData{ // floating eye
        .sprite_offset_x = 10,
        .sprite_offset_y = 1,
        .damage = 1,
        .range = 8,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 4,
    },
    TowerData{ // placeholder 1
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
    },
    TowerData{ // placeholder 2
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
    },
    TowerData{ // placeholder 3
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
    },
    TowerData{ // placeholder 4
        .sprite_offset_x = 4,
        .sprite_offset_y = 4,
        .damage = 1,
        .range = 4,
        .tile_id = undefined,
        .fire_rate = 1,
        .fire_speed = 1,
    },
};

const Tower = struct {
    kind: TowerKind,
    direction: Direction,
    tile_x: u32, // TODO(caleb): pos
    tile_y: u32,
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

fn updateEnemy(tileset: *Tileset, map: *Map, enemy: *Enemy) void {
    var move_amt = rl.Vector2{ .x = 0, .y = 0 };
    switch (enemy.*.direction) {
        .left => move_amt.x -= 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
        .up => move_amt.y -= 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
        .down => move_amt.y += 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
        .right => move_amt.x += 1 / @intToFloat(f32, enemy.tile_steps_per_second) * enemies_data[@enumToInt(enemy.kind)].move_speed,
    }


    const next_tile_pos = rlm.Vector2Add(enemy.pos, move_amt);
    if (next_tile_pos.y >= 11.0) {
        const asdf = true;
        _ = asdf;
    }

    if (!boundsCheck(@floatToInt(i32, @floor(next_tile_pos.x)), @floatToInt(i32, @floor(next_tile_pos.y)))) {
        return;
    }

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
        var future_target_tile_id: ?u32 = null;
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

fn boardHeight() c_int {
    const result = @floatToInt(c_int, isoProjectBase(@intToFloat(f32, board_width_in_tiles), @intToFloat(f32, board_height_in_tiles), 0).y) + @divTrunc(sprite_height * @floatToInt(c_int, scale_factor), 2);
    return result;
}

fn isoProject(x: f32, y: f32, z: f32) rl.Vector2 {
    var out = isoProjectBase(x, y, z);

    const screen_offset = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - sprite_width * scale_factor / 2, .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, boardHeight())) / 2 };

    out.x += screen_offset.x + board_translation.x;
    out.y += screen_offset.y + board_translation.y;

    return out;
}

fn isoProjectInverted(screen_space_x: f32, screen_space_y: f32, tile_space_z: f32) rl.Vector2 {
    const i_iso_trans = iProjectionVector();
    const j_iso_trans = jProjectionVector();

    const screen_offset = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()) / 2 - sprite_width * scale_factor / 2, .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, boardHeight())) / 2 };

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

pub fn main() !void {
    const board_width = sprite_width * board_width_in_tiles * @floatToInt(c_int, scale_factor);
    rl.SetConfigFlags(rl.ConfigFlags.FLAG_MSAA_4X_HINT);
    rl.InitWindow(board_width, boardHeight(), "twr-defns");
    rl.SetWindowState(rl.ConfigFlags.FLAG_WINDOW_RESIZABLE);
    rl.SetWindowState(rl.ConfigFlags.FLAG_VSYNC_HINT);
    rl.SetTargetFPS(target_fps);
    rl.SetTraceLogLevel(@enumToInt(rl.TraceLogLevel.LOG_WARNING));

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();
    rl.SetMasterVolume(1);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var ally = arena.allocator();
    var parser = std.json.Parser.init(ally, false);
    defer parser.deinit();

    var push_buffer = try ally.alloc(u8, 1024 * 10); // 10kb should be enough.
    defer ally.free(push_buffer);
    var fba = std.heap.FixedBufferAllocator.init(push_buffer);

    // Bring in all the assets
    var window_icon = rl.LoadImage("assets/icon.png");
    defer rl.UnloadImage(window_icon);
    rl.SetWindowIcon(window_icon);

    var jam = rl.LoadMusicStream("assets/grasslands.wav");
    jam.looping = true;
    defer rl.UnloadMusicStream(jam);
    rl.PlayMusicStream(jam);

    const shoot_sound = rl.LoadSound("assets/shoot.wav");
    rl.SetSoundVolume(shoot_sound, 0.5);
    defer rl.UnloadSound(shoot_sound);

    const hit_sound = rl.LoadSound("assets/hit.wav");
    rl.SetSoundVolume(hit_sound, 0.5);
    defer rl.UnloadSound(hit_sound);

    const dead_sound = rl.LoadSound("assets/ded.wav");
    rl.SetSoundVolume(dead_sound, 0.5);
    defer rl.UnloadSound(dead_sound);

    const font = rl.LoadFont("assets/PICO-8_mono.ttf");
    defer rl.UnloadFont(font);

    var bg_tex = rl.LoadTexture("assets/bg.png");
    defer rl.UnloadTexture(bg_tex);

    var hor_osc_shader = rl.LoadShader(0, // Probably not important
        rl.TextFormat("src/hor_osc.fs", @intCast(c_int, 330)) // gls version
    );
    defer rl.UnloadShader(hor_osc_shader);

    rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "render_width"), &@intToFloat(f32, rl.GetScreenWidth()), @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));
    rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "render_height"), &@intToFloat(f32, rl.GetScreenHeight()), @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));

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
        var enemy_id_count: u32 = 0;
        var tower_id_count: u32 = 0;
        for (tile_data.Array.items) |tile| {
            var tile_id = tile.Object.get("id") orelse unreachable;
            var tile_type = tile.Object.get("type") orelse unreachable;

            if (std.mem.eql(u8, tile_type.String, "track")) {
                tileset.track_id = @intCast(u32, tile_id.Integer);
            } else if (std.mem.eql(u8, tile_type.String, "track_start")) {
                tileset.track_start_id = @intCast(u32, tile_id.Integer);
            } else if (std.mem.eql(u8, tile_type.String, "enemy")) {
                std.debug.assert(enemy_id_count < enemies_data.len);
                enemies_data[enemy_id_count].tile_id = @intCast(u32, tile_id.Integer);
                enemy_id_count += 1;
            } else if (std.mem.eql(u8, tile_type.String, "tower")) {
                std.debug.assert(tower_id_count < towers_data.len);
                towers_data[tower_id_count].tile_id = @intCast(u32, tile_id.Integer);
                tower_id_count += 1;
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

    var debug_projectile = false;
    var debug_origin = false;
    var debug_bg_scroll = false;
    var debug_hit_boxes = false;
    var debug_text_info = false;

    var bg_poses = startBGPoses();

    var prev_frame_screen_dim = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()), .y = @intToFloat(f32, rl.GetScreenHeight()) };
    var prev_frame_input = Input{ .l_mouse_button_is_down = false };

    var selected_tower: ?*Tower = null;
    var is_placing_tower = false;
    var tower_index_being_placed: u32 = undefined;

    var tba_anim_frame: u8 = 0;
    var tba_anim_timer: u8 = 0;

    var enemy_start_tile_y: u32 = 0;
    var enemy_start_tile_x: u32 = 0;
    {
        var found_enemy_start_tile = false;
        outer: while (enemy_start_tile_y < board_height_in_tiles) : (enemy_start_tile_y += 1) {
            enemy_start_tile_x = 0;
            while (enemy_start_tile_x < board_width_in_tiles) : (enemy_start_tile_x += 1) {
                const ts_id = board_map.tileIDFromCoord(enemy_start_tile_x, enemy_start_tile_y) orelse continue;
                if ((ts_id) == tileset.track_start_id) {
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
    while (enemies_spawned < 100) : (enemies_spawned += 1) {
        var new_enemy: Enemy = undefined;
        new_enemy.kind = EnemyKind.gremlin_wiz_guy;
        new_enemy.direction = Direction.left;
        new_enemy.last_step_direction = Direction.left;
        new_enemy.pos = rl.Vector2{ .x = @intToFloat(f32, enemy_start_tile_x), .y = @intToFloat(f32, enemy_start_tile_y) };
        new_enemy.hp = @intCast(i32, enemies_data[@enumToInt(EnemyKind.gremlin_wiz_guy)].hp);
        new_enemy.tile_steps_per_second = enemies_data[@enumToInt(EnemyKind.gremlin_wiz_guy)].tile_steps_per_second;
        new_enemy.tile_step_timer = 0;
        new_enemy.anim_frame = 0;
        new_enemy.anim_timer = 0;
        new_enemy.initColliders();

        try alive_enemies.append(new_enemy);
    }

    // TODO(caleb): Disable escape key to close... ( why is this on by default? )
    while (!rl.WindowShouldClose()) { // Detect window close button or ESC key

        // -------------------- UPDATE --------------------

        rl.UpdateMusicStream(jam);

        // Tower buy area frame counter
        // NOTE(caleb): Wrap anim logic in a function if I get any more things that
        //  need animations.
        tba_anim_timer += 1;
        if (tba_anim_timer >= @divTrunc(target_fps, anim_frames_speed)) {
            tba_anim_timer = 0;
            tba_anim_frame += 1;
            if (tba_anim_frame > 3) tba_anim_frame = 0; // NOTE(caleb): 3 is frames per animation - 1
                                                        // where all sprites have 4 anims per facing direction.
        }

        // F1 to enable debugging
        if (rl.IsKeyPressed(rl.KeyboardKey.KEY_F1)) {
            debug_projectile = !debug_projectile;
            debug_origin = !debug_origin;
            debug_bg_scroll = !debug_bg_scroll;
            debug_hit_boxes = !debug_hit_boxes;
            debug_text_info = !debug_text_info;
        }

        const screen_dim = rl.Vector2{ .x = @intToFloat(f32, rl.GetScreenWidth()), .y = @intToFloat(f32, rl.GetScreenHeight()) };

        // Scale board depending on mouse wheel change
        scale_factor = clampf32(scale_factor + rl.GetMouseWheelMove(), 1, 10);

        // Get mouse position
        const mouse_pos = rl.GetMousePosition();
        var selected_tile_pos = isoProjectInverted(mouse_pos.x - sprite_width * scale_factor / 2, mouse_pos.y, 0);
        const selected_tile_x = @floatToInt(i32, @floor(selected_tile_pos.x));
        const selected_tile_y = @floatToInt(i32, @floor(selected_tile_pos.y));

        if (rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_MIDDLE)) {
            // Update board_translation by last frame's mouse delta
            board_translation = rlm.Vector2Add(board_translation, rl.GetMouseDelta());
        }

        // Purchasing a tower?
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

        if ((!is_placing_tower) and
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
                        is_placing_tower = true;
                        selected_tower = null;
                        tower_index_being_placed = selected_row * tower_buy_area_towers_per_row + selected_col;
                        break :outer;
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

        if (is_placing_tower and rl.IsMouseButtonReleased(rl.MouseButton.MOUSE_BUTTON_LEFT)) {
            is_placing_tower = false;

            if ((selected_tile_x < board_width_in_tiles) and (selected_tile_y < board_height_in_tiles) and
                (selected_tile_x >= 0) and (selected_tile_y >= 0))
            {
                const tile_index = board_map.tile_indicies.items[@intCast(u32, selected_tile_y * board_width_in_tiles + selected_tile_x)];
                if (!tileset.isTrackTile(tile_index) and !clicked_on_a_tower) {
                    selected_tower = null;
                    const new_tower = Tower{
                        .kind = @intToEnum(TowerKind, tower_index_being_placed),
                        .direction = Direction.down,
                        .tile_x = @intCast(u32, selected_tile_x),
                        .tile_y = @intCast(u32, selected_tile_y),
                        .fire_rate = towers_data[tower_index_being_placed].fire_rate,
                        .fire_speed = towers_data[tower_index_being_placed].fire_speed,
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
                }
            }
        }

        // Update each tower
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

                    // Enemy distance < tower range
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

                        const tower_pos = rl.Vector2{ .x = @intToFloat(f32, tower.tile_x), .y = @intToFloat(f32, tower.tile_y)};

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

//                        rl.PlaySound(shoot_sound);

                        break;
                    }
                }
            }
        }

        // Enemy updates
        for (alive_enemies.items) |*enemy| {
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

                updateEnemy(&tileset, &board_map, enemy);

                // Update n times when stepping > target_fps times per frame.
                var fraction_of_frame = target_fps / @intToFloat(f32, enemy.tile_steps_per_second);
                while (fraction_of_frame < 1) : (fraction_of_frame += target_fps / @intToFloat(f32, enemy.tile_steps_per_second)) {
                    updateEnemy(&tileset, &board_map, enemy);
                }
            }
        }

        {
            var projectile_index: i32 = 0;
            outer: while (projectile_index < projectiles.items.len) : (projectile_index += 1) {
                var projectile = &projectiles.items[@intCast(u32, projectile_index)];
                var projected_projectile_pos = isoProject(projectile.pos.x, projectile.pos.y, 1);

                // Remove projectile if it is far enough away from the board.
                if ((@floor(projectile.pos.x) > board_width_in_tiles * 2) or
                    (@floor(projectile.pos.y) > board_height_in_tiles * 2) or
                    (projectile.pos.x < -board_width_in_tiles) or (projectile.pos.y < -board_height_in_tiles))
                {
                    _ = projectiles.orderedRemove(@intCast(u32, projectile_index));
                    projectile_index -= 1;
                    continue;
                }

                // Projectile hit enemy
                for (alive_enemies.items) |*enemy| { // ( spatial partitioning? ) frames are still fine
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
        }

        {
            // TODO(caleb): Remove after death anim is done playing.
            var enemy_index: i32 = 0;
            while (enemy_index < dead_enemies.items.len) : (enemy_index += 1) {
                _ = dead_enemies.orderedRemove(@intCast(u32, enemy_index));
            }
        }

        {
            var enemy_index: i32 = 0;
            while (enemy_index < alive_enemies.items.len) : (enemy_index += 1) {
                const enemy = alive_enemies.items[@intCast(u32, enemy_index)];
                if (enemy.hp <= 0) {
                    // Handle death stuff now
                    rl.PlaySound(dead_sound);

                    monies += @intCast(i32, @enumToInt(enemy.kind)) + 1;

                    // Don't read from enemy below this line.
                    try dead_enemies.append(alive_enemies.orderedRemove(@intCast(u32, enemy_index)));
                    enemy_index -= 1;
                }
            }
        }

        if (rlm.Vector2Equals(prev_frame_screen_dim, screen_dim) == 0) {
            bg_poses = startBGPoses();

            // Inform shader of width and height changes.
            rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "renderWidth"), &screen_dim.x, @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));
            rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "renderHeight"), &screen_dim.y, @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));
        }

        // Horizontal oscillation of bg for this frame.
        const time_in_seconds = @floatCast(f32, rl.GetTime());
        rl.SetShaderValue(hor_osc_shader, rl.GetShaderLocation(hor_osc_shader, "time_in_seconds"), &time_in_seconds, @enumToInt(rl.ShaderUniformDataType.SHADER_UNIFORM_FLOAT));

        const bg_pos_move = rl.Vector2{ .x = @round(@cos(time_in_seconds / 100)), .y = @round(@sin(time_in_seconds / 100) * 5)};
        for (bg_poses) |*bg_pos| {
            bg_pos.* = rlm.Vector2Add(bg_pos.*, bg_pos_move);
            if (bg_pos.x > screen_dim.x) {
                bg_pos.x = -screen_dim.x + (bg_pos.x - screen_dim.x);
            } else if (bg_pos.x < -screen_dim.x) {
                bg_pos.x = screen_dim.x - (-screen_dim.x - bg_pos.x);
            }
            if (bg_pos.y > screen_dim.y) {
                bg_pos.y = -screen_dim.y + (bg_pos.y - screen_dim.y);
            } else if (bg_pos.y < -screen_dim.y) {
                bg_pos.y = screen_dim.y - (-screen_dim.y - bg_pos.y);
            }
        }

        // Record prev frame input and screen dim.
        prev_frame_input.l_mouse_button_is_down = rl.IsMouseButtonDown(rl.MouseButton.MOUSE_BUTTON_LEFT);
        prev_frame_screen_dim = screen_dim;

        // -------------------- DRAW --------------------

        rl.BeginDrawing();

        // Background image
        {
            const bg_source_rec = rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @intToFloat(f32, bg_tex.width),
                .height = -@intToFloat(f32, bg_tex.height),
            };

            rl.BeginShaderMode(hor_osc_shader);
            for (bg_poses) |bg_pos| {
                const bg_aest_rec = rl.Rectangle{
                    .x = bg_pos.x,
                    .y = bg_pos.y,
                    .width = screen_dim.x,
                    .height = screen_dim.y,
                };
                rl.DrawTexturePro(bg_tex, bg_source_rec, bg_aest_rec, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
            }
            rl.EndShaderMode();

            if (debug_bg_scroll) {
                for (bg_poses) |bg_pos| {
                    rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x + 30, .y = bg_pos.y }, 3, rl.RED);
                    rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x - 30, .y = bg_pos.y }, 3, rl.RED);
                    rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x, .y = bg_pos.y + 30 }, 3, rl.RED);
                    rl.DrawLineEx(bg_pos, rl.Vector2{ .x = bg_pos.x, .y = bg_pos.y - 30 }, 3, rl.RED);
                }
            }
        }

        var tile_y: i32 = 0;
        while (tile_y < board_height_in_tiles) : (tile_y += 1) {
            var tile_x: i32 = 0;
            while (tile_x < board_width_in_tiles) : (tile_x += 1) {
                const ts_id = board_map.tileIDFromCoord(@intCast(u32, tile_x), @intCast(u32, tile_y)) orelse continue;
                var dest_pos = isoProject(@intToFloat(f32, tile_x), @intToFloat(f32, tile_y), 0);
                if (tile_x == selected_tile_x and tile_y == selected_tile_y) {
                    dest_pos.y -= 4 * scale_factor;
                }

                const dest_rect = rl.Rectangle{
                    .x = dest_pos.x,
                    .y = dest_pos.y,
                    .width = sprite_width * scale_factor,
                    .height = sprite_height * scale_factor,
                };

                const target_tile_row = @divTrunc(ts_id, tileset.columns);
                const target_tile_column = @mod(ts_id, tileset.columns);
                const source_rect = rl.Rectangle{
                    .x = @intToFloat(f32, target_tile_column * sprite_width),
                    .y = @intToFloat(f32, target_tile_row * sprite_height),
                    .width = sprite_width,
                    .height = sprite_height,
                };

                var tile_rgb: u8 = 255;
                if (selected_tower != null) {
                    const range = towers_data[@enumToInt(selected_tower.?.kind)].range;
                    if (std.math.absCast(tile_x - @intCast(i32, selected_tower.?.tile_x)) + std.math.absCast(tile_y - @intCast(i32, selected_tower.?.tile_y)) <= range) {
                        tile_rgb = 128;
                    }
                } else if (is_placing_tower) {
                    const range = towers_data[tower_index_being_placed].range;
                    if (std.math.absCast(tile_x - @intCast(i32, selected_tile_x)) + std.math.absCast(tile_y - @intCast(i32, selected_tile_y)) <= range) {
                        tile_rgb = 128;
                    }
                }
                rl.DrawTexturePro(tileset.tex, source_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, rl.Color{.r = tile_rgb, .g = tile_rgb, .b = tile_rgb, .a = 255});
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
            const target_tile_row = @divTrunc(entry.ts_id, tileset.columns);
            const target_tile_column = @mod(entry.ts_id, tileset.columns);
            const source_rect = rl.Rectangle{
                .x = @intToFloat(f32, target_tile_column * sprite_width),
                .y = @intToFloat(f32, target_tile_row * sprite_height),
                .width = sprite_width,
                .height = sprite_height,
            };

            var dest_pos = isoProject(entry.tile_pos.x, entry.tile_pos.y, 1);

            if ((@floatToInt(i32, entry.tile_pos.x) == selected_tile_x) and
                (@floatToInt(i32, entry.tile_pos.y) == selected_tile_y))
            {
                dest_pos.y -= 4 * scale_factor;
            }

            const dest_rect = rl.Rectangle{
                .x = dest_pos.x,
                .y = dest_pos.y,
                .width = sprite_width * scale_factor,
                .height = sprite_height * scale_factor,
            };

            rl.DrawTexturePro(tileset.tex, source_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
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
                    rl.DrawRectangleLinesEx(dest_rec, 1, rl.Color{.r = 0, .g = 0, .b = 255, .a = 255 });
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

        if (is_placing_tower) {
            const ts_id = towers_data[tower_index_being_placed].tile_id + @enumToInt(Direction.down) * 4 + tba_anim_frame;
            const target_tile_row = @divTrunc(ts_id, tileset.columns);
            const target_tile_column = @mod(ts_id, tileset.columns);
            const source_rect = rl.Rectangle{
                .x = @intToFloat(f32, target_tile_column * sprite_width),
                .y = @intToFloat(f32, target_tile_row * sprite_height),
                .width = sprite_width,
                .height = sprite_height,
            };

            const projected_pos = isoProject(@intToFloat(f32, selected_tile_x), @intToFloat(f32, selected_tile_y), 1);
            const dest_rect = rl.Rectangle{
                .x = projected_pos.x,
                .y = projected_pos.y,
                .width = sprite_width * scale_factor,
                .height = sprite_height * scale_factor,
            };
            rl.DrawTexturePro(tileset.tex, source_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);

        }

        // Draw tower buy area
        {
            var strz_buffer: [256]u8 = undefined;
            rl.DrawRectangleRec(buy_area_rec, color_off_white);

            var row_index: u32 = 0;
            while (row_index < tower_buy_area_rows) : (row_index += 1) {
                var col_index: u32 = 0;
                const towers_for_this_row = @min(tower_buy_area_towers_per_row, towers_data.len - row_index * tower_buy_area_towers_per_row);
                while (col_index < towers_for_this_row) : (col_index += 1) {
                    const ts_id = towers_data[row_index * towers_for_this_row + col_index].tile_id + @enumToInt(Direction.down) * 4 + tba_anim_frame;
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
                    rl.DrawTexturePro(tileset.tex, source_rect, tower_buy_item_rec, .{ .x = 0, .y = 0 }, 0, rl.WHITE);

                    const cost_bottom_pad_px = 2;
                    const cost_strz = try std.fmt.bufPrintZ(&strz_buffer, "${d}", .{200});
                    const cost_strz_dim = rl.MeasureTextEx(font, @ptrCast([*c]const u8, cost_strz), tba_font_size, font_spacing);
                    const cost_strz_pos = rl.Vector2{
                        .x = buy_area_rec.x + @intToFloat(f32, col_index) * tower_buy_item_dim.x + (tower_buy_item_dim.x - cost_strz_dim.x) / 2,
                        .y = buy_area_rec.y + @intToFloat(f32, row_index) * tower_buy_item_dim.y + (tower_buy_item_dim.y - cost_strz_dim.y - cost_bottom_pad_px),
                    };
                    rl.DrawRectangleV(cost_strz_pos, cost_strz_dim, rl.Color{.r = color_off_white.r, .g = color_off_white.g, .b = color_off_white.b, .a = 210});
                    rl.DrawTextEx(font, @ptrCast([*c]const u8, cost_strz), cost_strz_pos, tba_font_size, font_spacing, color_off_black);
                    rl.DrawRectangleLinesEx(tower_buy_item_rec, 2, color_off_black);
                }
            }
        }

        { // Draw money amt
            var strz_buffer: [256]u8 = undefined;
            const money_strz = try std.fmt.bufPrintZ(&strz_buffer, "Money: ${d}", .{monies});
            const money_strz_dim = rl.MeasureTextEx(font, @ptrCast([*c]const u8, money_strz), font_size, font_spacing);

            const money_rec = rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = money_strz_dim.x + 3,
                .height = money_strz_dim.y + 6,
            };
            rl.DrawRectangleRec(money_rec, color_off_white);
            rl.DrawTextEx(font, @ptrCast([*c]const u8, money_strz), rl.Vector2{ .x = 3, .y = 3}, font_size, font_spacing, color_off_black);
            rl.DrawRectangleLinesEx(money_rec, 2, color_off_black);
        }

        if (debug_text_info) {
            var strz_buffer: [256]u8 = undefined;
            var y_offset: f32 = 0;

            const fps_strz = try std.fmt.bufPrintZ(&strz_buffer, "FPS: {d}", .{rl.GetFPS()});
            y_offset += rl.MeasureTextEx(font, @ptrCast([*c]const u8, fps_strz), font_size, font_spacing).y;
            rl.DrawTextEx(font, @ptrCast([*c]const u8, fps_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset}, font_size, font_spacing, rl.Color{.r = 255, .g = 0, .b = 0, .a = 255});

            const tower_count_strz = try std.fmt.bufPrintZ(&strz_buffer, "Tower count: {d}", .{towers.items.len});
            y_offset += rl.MeasureTextEx(font, @ptrCast([*c]const u8, tower_count_strz), font_size, font_spacing).y;
            rl.DrawTextEx(font, @ptrCast([*c]const u8, tower_count_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset}, font_size, font_spacing, rl.Color{.r = 255, .g = 0, .b = 0, .a = 255});

            const mouse_tile_space_strz = try std.fmt.bufPrintZ(&strz_buffer, "Tile-space pos: ({d:.2}, {d:.2})", .{selected_tile_pos.x, selected_tile_pos.y});
            y_offset += rl.MeasureTextEx(font, @ptrCast([*c]const u8, mouse_tile_space_strz), font_size, font_spacing).y;
            rl.DrawTextEx(font, @ptrCast([*c]const u8, mouse_tile_space_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset}, font_size, font_spacing, rl.Color{.r = 255, .g = 0, .b = 0, .a = 255});

            const projectile_count_strz = try std.fmt.bufPrintZ(&strz_buffer, "Projectile count: {d}", .{projectiles.items.len});
            y_offset += rl.MeasureTextEx(font, @ptrCast([*c]const u8, projectile_count_strz), font_size, font_spacing).y;
            rl.DrawTextEx(font, @ptrCast([*c]const u8, projectile_count_strz), rl.Vector2{ .x = 0, .y = screen_dim.y - y_offset}, font_size, font_spacing, rl.Color{.r = 255, .g = 0, .b = 0, .a = 255});
        }

        // Draw tower info
        //if (selected_tower != null) {
        //    var tower_info_buffer: [256]u8 = undefined;
        //    const tower_tile_pos_strz = try std.fmt.bufPrintZ(&tower_info_buffer, "Tile pos: ({d}, {d})", .{selected_tower.?.tile_x, selected_tower.?.tile_y});
        //    rl.DrawTextEx(font, @ptrCast([*c]const u8, tower_tile_pos_strz), rl.Vector2{ .x = 0, .y = 0 }, font_size, font_spacing, rl.Color{.r = 0, .g = 255, .b = 0, .a = 255});
        //}

        if (debug_origin) {
            const screen_mid = rl.Vector2{
                .x = screen_dim.x / 2,
                .y = screen_dim.y / 2,
            };
            rl.DrawLineEx(screen_mid, rlm.Vector2Add(screen_mid, board_translation), 2, rl.Color{ .r = 0, .g = 255, .b = 0, .a = 255 });
        }

        rl.EndDrawing();
    }

    rl.CloseWindow();
}
