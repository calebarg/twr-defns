const std = @import("std");
const rl = @import("raylib");

const maxLayers = 5;
const maxUniqueTrackTiles = 5;
const scaleFactor = 3;
const mapWidthInTiles = 16;
const mapHeightInTiles = 16;
const spriteWidth = 32;
const spriteHeight = 32;
const mapWidth = spriteWidth * mapWidthInTiles * scaleFactor;
const mapHeight = @floatToInt(c_int, isoTransform(@intToFloat(f32, mapWidthInTiles),
        @intToFloat(f32, mapHeightInTiles)).y);

// TODO(caleb):
// 1) Towers list and render from it instead of the map.
// 2) ACTUALLY fix offsets for towers and enemies??? I could just offset by half sprite height ( that seems ok for now )
// 3) Get towers rotating to face enemies.
// 4) Fix sprite render order.

const animFramesSpeed = 9;
const enemyTPS = 5; // Enemy tiles per second

const Tileset = struct {
    columns: u32,
    trackStartID: u32,
    tileIDCount: u8,
    trackTileIDs: [maxUniqueTrackTiles]u32,
    tex: rl.Texture,

    pub fn checkIsTrackTile(self: Tileset, targetTileID: u32) bool {
        var trackTileIndex: u8 = 0;
        while (trackTileIndex < self.tileIDCount) : (trackTileIndex += 1) {
            if (self.trackTileIDs[trackTileIndex] == targetTileID) {
                return true;
            }
        }
        return false;
    }
};

const Map = struct {
    tileIndicies: [maxLayers][mapWidthInTiles * mapHeightInTiles]u32,
};

const Direction = enum(u32) {
    left = 0,
    up,
    down,
    right,
};

const Enemy = struct {
    direction: Direction,
    pos: rl.Vector2,
    prevPos: rl.Vector2,
};

fn boundsCheck(x: i32, y: i32, dX: i32, dY: i32) callconv(.Inline) bool {
    if ((y + dY < 0) or (y + dY >= mapHeightInTiles) or
        (x + dX < 0) or (x + dX >= mapWidthInTiles)) {
       return false;
    }
    return true;
}

fn movingBackwards(x: f32, y: f32, prevX: f32, prevY: f32) callconv(.Inline) bool {
    return ((x == prevX) and y == prevY);
}

fn updateEnemy(tileset: *Tileset, map: *Map, enemy: *Enemy) void {
    var moveAmt = rl.Vector2{.x=0, .y=0};
    switch (enemy.*.direction) {
        .left => moveAmt.x -= 1,
        .up => moveAmt.y -= 1,
        .down => moveAmt.y += 1,
        .right => moveAmt.x += 1,
    }

    const tileX = @floatToInt(i32, @round(enemy.*.pos.x));
    const tileY = @floatToInt(i32, @round(enemy.*.pos.y));
    const tileDX = @floatToInt(i32, @round(moveAmt.x));
    const tileDY = @floatToInt(i32, @round(moveAmt.y));

    if (!boundsCheck(tileX, tileY, tileDX, tileDY)) {
        return;
    }

    const targetTileID = map.tileIndicies[0][@intCast(u32, tileY + tileDY) * mapWidthInTiles + @intCast(u32, tileX + tileDX)] - 1;
    if (tileset.checkIsTrackTile(targetTileID) and !movingBackwards(enemy.*.pos.x + moveAmt.x, enemy.pos.y + moveAmt.y, enemy.*.prevPos.x, enemy.*.prevPos.y)) {
        enemy.*.prevPos = enemy.*.pos;
        enemy.*.pos.x += moveAmt.x;
        enemy.*.pos.y += moveAmt.y;
    }
    else { // Choose new direction
        enemy.*.direction = @intToEnum(Direction, @mod(@enumToInt(enemy.*.direction) + 1, @enumToInt(Direction.right) + 1));
        updateEnemy(tileset, map, enemy);
    }
}

const iIsoTrans = rl.Vector2{ .x = @intToFloat(f32, spriteWidth * scaleFactor) * 0.5, .y = @intToFloat(f32, spriteHeight * scaleFactor) * 0.25 };
const jIsoTrans = rl.Vector2{ .x = -1 * @intToFloat(f32, spriteWidth * scaleFactor) * 0.5, .y = @intToFloat(f32, spriteHeight * scaleFactor) * 0.25 };

fn isoTransform(x: f32, y: f32) rl.Vector2 {
    const inputVec = rl.Vector2{ .x = x, .y = y };
    var out: rl.Vector2 = undefined;

    out.x = inputVec.x * iIsoTrans.x + inputVec.y * jIsoTrans.x;
    out.y = inputVec.x * iIsoTrans.y + inputVec.y * jIsoTrans.y;

    return out;
}

fn isoTransformWithScreenOffset(x: f32, y: f32) rl.Vector2 {
    var out = isoTransform(x, y);

    const screenOffset = rl.Vector2{.x = @intToFloat(f32, rl.GetScreenWidth()) /  2 - spriteWidth * scaleFactor / 2,
        .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, mapHeight)) / 2};

    out.x += screenOffset.x;
    out.y += screenOffset.y;

    return out;
}

fn isoInvert(x: f32, y: f32) rl.Vector2 {
    const screenOffset = rl.Vector2{.x = @intToFloat(f32, rl.GetScreenWidth()) /  2  - spriteWidth * scaleFactor / 2,
        .y = (@intToFloat(f32, rl.GetScreenHeight()) - @intToFloat(f32, mapHeight)) / 2};
    const inputVec = rl.Vector2{ .x = x - screenOffset.x, .y = y - screenOffset.y };
    var out: rl.Vector2 = undefined;

    const det = 1 / (iIsoTrans.x * jIsoTrans.y - jIsoTrans.x * iIsoTrans.y);
    const iInvTrans = rl.Vector2{.x = jIsoTrans.y * det, .y = iIsoTrans.y * det * -1};
    const jInvTrans = rl.Vector2{.x = jIsoTrans.x * det * -1, .y = iIsoTrans.x * det};

    out.x = inputVec.x * iInvTrans.x + inputVec.y * jInvTrans.x;
    out.y = inputVec.x * iInvTrans.y + inputVec.y * jInvTrans.y;

    return out;
}

pub fn main() !void {
    rl.InitWindow(mapWidth, mapHeight, "twr-defns");
    rl.SetWindowState(rl.ConfigFlags.FLAG_WINDOW_RESIZABLE);
    rl.SetWindowState(rl.ConfigFlags.FLAG_VSYNC_HINT);
    rl.SetWindowMinSize(mapWidth, mapHeight);
    rl.SetTargetFPS(60);

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();
    rl.SetMasterVolume(1);
    //    bool IsAudioDeviceReady(void);

    var ally = std.heap.page_allocator;
    var parser = std.json.Parser.init(ally, false);
    defer parser.deinit();

    // Load tileset
    var tileset: Tileset = undefined;
    tileset.tex = rl.LoadTexture("assets/calebsprites/isosheet.png");
    defer rl.UnloadTexture(tileset.tex);
    {
        const tilesetF = try std.fs.cwd().openFile("assets/calebsprites/isosheet.tsj", .{});
        defer tilesetF.close();
        var rawTilesetJSON = try tilesetF.reader().readAllAlloc(ally, 1024 * 5); // 5kib should be enough
        defer ally.free(rawTilesetJSON);

        var parsedTilesetData = try parser.parse(rawTilesetJSON);

        const columnsValue = parsedTilesetData.root.Object.get("columns") orelse unreachable;
        tileset.columns = @intCast(u32, columnsValue.Integer);

        const tileData = parsedTilesetData.root.Object.get("tiles") orelse unreachable;
        tileset.tileIDCount = @intCast(u8, tileData.Array.items.len);
        for (tileData.Array.items) |tile, tileIndex| {
            const tileID = tile.Object.get("id") orelse unreachable;
            const tileType = tile.Object.get("type") orelse unreachable;

            if (std.mem.eql(u8, tileType.String, "track")) {
                tileset.trackTileIDs[tileIndex] = @intCast(u32, tileID.Integer);
            } else if (std.mem.eql(u8, tileType.String, "track_start")) {
                tileset.trackTileIDs[tileIndex] = @intCast(u32, tileID.Integer);
                tileset.trackStartID = @intCast(u32, tileID.Integer);
            } else {
                unreachable;
            }
        }
    }

    // Load map data
    var map: Map = undefined;
    for (map.tileIndicies) |*layer| {
        for (layer.*) |*tileIndex| {
            tileIndex.* = 0;
        }
    }

    {
        const mapDataF = try std.fs.cwd().openFile("assets/calebsprites/map1.tmj", .{});
        defer mapDataF.close();
        var mapDataJSON = try mapDataF.reader().readAllAlloc(ally, 1024 * 10);
        defer ally.free(mapDataJSON);

        parser.reset();
        var parsedMapData = try parser.parse(mapDataJSON);
        var layers = parsedMapData.root.Object.get("layers") orelse unreachable;
        for (layers.Array.items) |layer, layerIndex| {
            const tileIndiciesData = layer.Object.get("data") orelse unreachable;
            for (tileIndiciesData.Array.items) |tileIndex, tileIndexIndex| {
                map.tileIndicies[layerIndex][tileIndexIndex] = @intCast(u32, tileIndex.Integer);
            }
        }
    }

    // Store FIRST animation index for each sprite in tile set.
    // NOTE(caleb): There are 4 animations stored per index in this list. ( up-left, up-right, down-left, down-right)
    //  where each animation is 4 frames in length.
    var animTileIndicies = std.ArrayList(u32).init(ally);
    defer animTileIndicies.deinit();
    {
        const animDataF = try std.fs.cwd().openFile("assets/calebsprites/anims.tmj", .{});
        defer animDataF.close();
        var rawAnimDataJSON = try animDataF.reader().readAllAlloc(ally, 1024 * 5); // 5kib should be enough
        defer ally.free(rawAnimDataJSON);

        parser.reset();
        var parsedAnimData = try parser.parse(rawAnimDataJSON);
        var layers = parsedAnimData.root.Object.get("layers") orelse unreachable;
        for (layers.Array.items) |layer| {
            var layerData = layer.Object.get("data") orelse unreachable;
            for (layerData.Array.items) |tileIndexValue| {
                try animTileIndicies.append(@intCast(u32, tileIndexValue.Integer));
            }
            break;
        }
    }

    const sickJam = rl.LoadSound("assets/bigjjam.wav");
    defer rl.UnloadSound(sickJam);

    var animCurrentFrame: u8 = 0;
    var animFramesCounter: u8 = 0;
    var enemyTPSFrameCounter: u8 = 0;

    // Find start tile.
    // NOTE(caleb): Spawn tile should allways be on layer 0
    var startTileY: u32 = 0;
    var startTileX: u32 = 0;
    var foundStartTile = false;
    outer: while (startTileY < mapHeightInTiles) : (startTileY += 1) {
        startTileX = 0;
        while (startTileX < mapWidthInTiles) : (startTileX += 1) {
            const mapTileIndex = map.tileIndicies[0][startTileY * mapWidthInTiles + startTileX];
            if (mapTileIndex == 0) {
                continue;
            }
            if ((mapTileIndex - 1) == tileset.trackStartID) {
                foundStartTile = true;
                break :outer;
            }
        }
    }
    std.debug.assert(foundStartTile);

    var aliveEnemies = std.ArrayList(Enemy).init(ally);
    defer aliveEnemies.deinit();

    // TODO(caleb): Disable escape key to close... ( why is this on by default? )
    while (!rl.WindowShouldClose()) { // Detect window close button or ESC key
        if (!rl.IsSoundPlaying(sickJam)) { // and rl.IsMusicReady(sickJam)) {
            rl.PlaySound(sickJam);
        }

        animFramesCounter += 1;
        if (animFramesCounter >= @divTrunc(60, animFramesSpeed)) {
            animFramesCounter = 0;
            animCurrentFrame += 1;
            if (animCurrentFrame > 3) animCurrentFrame = 0; // NOTE(caleb): 3 is frames per animation - 1
        }

        enemyTPSFrameCounter += 1;
        if (enemyTPSFrameCounter >= @divTrunc(60, enemyTPS)) {
            enemyTPSFrameCounter = 0;

            // Update enemies

            for (aliveEnemies.items) |*enemy| {
                updateEnemy(&tileset, &map, enemy);
            }

            if (aliveEnemies.items.len < 1) {
                const newEnemy = Enemy{
                    .direction = Direction.left,
                    .pos = rl.Vector2{ .x = @intToFloat(f32, startTileX), .y = @intToFloat(f32, startTileY) },
                    .prevPos = rl.Vector2{ .x = @intToFloat(f32, startTileX), .y = @intToFloat(f32, startTileY) },
                };
                try aliveEnemies.append(newEnemy);
            }
        }

        // Get mouse position
        var mousePos = rl.GetMousePosition();
        var selectedTilePos = isoInvert(@round(mousePos.x), @round(mousePos.y));
        const selectedTileX = @floatToInt(i32, selectedTilePos.x);
        const selectedTileY = @floatToInt(i32, selectedTilePos.y);

        // Place tower on selected tile
        if (rl.IsMouseButtonPressed(rl.MouseButton.MOUSE_BUTTON_LEFT) and selectedTileX < mapWidthInTiles and selectedTileY < mapHeightInTiles and selectedTileX >= 0 and selectedTileY >= 0) {
            map.tileIndicies[1][@intCast(u32, selectedTileY) * mapWidthInTiles + @intCast(u32, selectedTileX)] = animTileIndicies.items[1];
        }

        rl.BeginDrawing();
        rl.ClearBackground(rl.Color{.r=77, .g=128, .b=201, .a=255});

        // Draw
        for (map.tileIndicies) |layer, layerIndex| { // Do I actually need multi map layers??

            // Draw enemies on layer 1
            if (layerIndex == 1)
            {
                var enemyIndex = @intCast(i32, aliveEnemies.items.len) - 1;
                while (enemyIndex >= 0) : (enemyIndex -= 1)  {
                    const animTileIndex = animTileIndicies.items[0] + @enumToInt(aliveEnemies.items[@intCast(u32, enemyIndex)].direction) * 4 + animCurrentFrame;
                    std.debug.assert(animTileIndex != 0); // Has an anim?
                    const targetTileRow = @divTrunc(animTileIndex - 1, tileset.columns);
                    const targetTileColumn = @mod(animTileIndex - 1, tileset.columns);

                    var destPos = isoTransformWithScreenOffset(aliveEnemies.items[@intCast(u32, enemyIndex)].pos.x, aliveEnemies.items[@intCast(u32, enemyIndex)].pos.y);

                    destPos.y -= spriteHeight * scaleFactor / 2;

                    const destRect = rl.Rectangle{
                        .x = destPos.x,
                        .y = destPos.y,
                        .width = spriteWidth * scaleFactor,
                        .height = spriteHeight * scaleFactor,
                    };
                    const sourceRect = rl.Rectangle{
                        .x = @intToFloat(f32, targetTileColumn * spriteWidth),
                        .y = @intToFloat(f32, targetTileRow * spriteHeight),
                        .width = spriteWidth,
                        .height = spriteHeight,
                    };

                    rl.DrawTexturePro(tileset.tex, sourceRect, destRect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
                }
            }

            // Draw map
            var tileY: i32 = 0;
            while (tileY < mapHeightInTiles) : (tileY += 1) {
                var tileX: i32 = 0;
                while (tileX < mapWidthInTiles) : (tileX += 1) {
                    const mapTileIndex = layer[@intCast(u32, tileY) * mapWidthInTiles + @intCast(u32, tileX)];
                    if (mapTileIndex == 0) {
                        continue;
                    }
                    const targetTileRow = @divTrunc(mapTileIndex - 1, tileset.columns);
                    const targetTileColumn = @mod(mapTileIndex - 1, tileset.columns);

                    var destPos = isoTransformWithScreenOffset(@intToFloat(f32, tileX),
                        @intToFloat(f32, tileY));

                    if (tileX == selectedTileX and tileY == selectedTileY) {
                        destPos.y -= 10;
                    }

                    const destRect = rl.Rectangle{
                        .x = destPos.x,
                        .y = destPos.y,
                        .width = spriteWidth * scaleFactor,
                        .height = spriteHeight * scaleFactor,
                    };

                    const sourceRect = rl.Rectangle{
                        .x = @intToFloat(f32, targetTileColumn * spriteWidth),
                        .y = @intToFloat(f32, targetTileRow * spriteHeight),
                        .width = spriteWidth,
                        .height = spriteHeight,
                    };

                    rl.DrawTexturePro(tileset.tex, sourceRect, destRect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
                }
            }
        }

        rl.EndDrawing();
    }

    rl.CloseWindow();
}
