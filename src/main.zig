const std = @import("std");
const rl = @import("raylib");

const maxLayers = 5;
const maxUniqueTrackTiles = 5;
const scaleFactor = 3;
const mapWidthInTiles = 16;
const mapHeightInTiles = 16;
const spriteWidth = 32;
const spriteHeight = 32;
const screenWidth = mapWidthInTiles * spriteWidth * scaleFactor;
const screenHeight = mapHeightInTiles * spriteHeight * scaleFactor;

const animFramesSpeed = 4;
const tickSpeed = 1;

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
    layerCount: u8,
    tileIndicies: [maxLayers][mapWidthInTiles * mapHeightInTiles]u32,
};

const EnemyDir = enum(u32) {
    left = 0,
    up,
    down,
    right,
};

fn boundsCheck(x: i32, y: i32, dX: i32, dY: i32) callconv(.Inline) bool {
    if ((y + dY < 0) or (y + dY >= mapHeightInTiles) or
        (x + dX < 0) or (x + dX >= mapWidthInTiles)) {
       return false;
    }
    return true;
}

fn movingBackwards(x: i32, y: i32, prevX: i32, prevY: i32) callconv(.Inline) bool {
    return ((x == prevX) and y == prevY);
}

fn updateEnemy(tileset: *Tileset, map: *Map, enemyPos: *rl.Vector2, prevEnemyPos: *rl.Vector2, enemyDir: *EnemyDir) void {
    const enemyX = @floatToInt(i32, enemyPos.*.x);
    const enemyY = @floatToInt(i32, enemyPos.*.y);
    const prevEnemyX = @floatToInt(i32, prevEnemyPos.*.x);
    const prevEnemyY = @floatToInt(i32, prevEnemyPos.*.y);

    var dX: i32 = 0;
    var dY: i32 = 0;
    switch (enemyDir.*) {
        .left => dX -= 1,
        .up => dY -= 1,
        .down => dY += 1,
        .right => dX += 1,
    }

    if (!boundsCheck(enemyX, enemyY, dX, dY)) {
        return;
    }

    const targetTileID = map.tileIndicies[0][@intCast(u32, enemyY + dY) * mapWidthInTiles + @intCast(u32, enemyX + dX)] - 1;
    if (tileset.checkIsTrackTile(targetTileID) and !movingBackwards(enemyX + dX, enemyY + dY, prevEnemyX, prevEnemyY)) {
        prevEnemyPos.* = enemyPos.*;
        enemyPos.x += @intToFloat(f32, dX);
        enemyPos.y += @intToFloat(f32, dY);
    }
    else { // Choose new direction
        enemyDir.* = @intToEnum(EnemyDir, @mod(@enumToInt(enemyDir.*) + 1, @enumToInt(EnemyDir.right) + 1));
        updateEnemy(tileset, map, enemyPos, prevEnemyPos, enemyDir);
    }
}

const iIsoTrans = rl.Vector2{ .x = @intToFloat(f32, spriteWidth * scaleFactor) * 0.5, .y = @intToFloat(f32, spriteHeight * scaleFactor) * 0.25 };
const jIsoTrans = rl.Vector2{ .x = -1 * @intToFloat(f32, spriteWidth * scaleFactor) * 0.5, .y = @intToFloat(f32, spriteHeight * scaleFactor) * 0.25 };
//const screenOffset = rl.Vector2{.x = screenWidth / 2 - spriteWidth * scaleFactor / 2, .y = 0};
const screenOffset = rl.Vector2{.x=0, .y=0};

fn isoTransform(x: f32, y: f32) rl.Vector2 {
    const inputVec = rl.Vector2{ .x = x, .y = y };
    var out: rl.Vector2 = undefined;

    out.x = inputVec.x * iIsoTrans.x + inputVec.y * jIsoTrans.x;
    out.y = inputVec.x * iIsoTrans.y + inputVec.y * jIsoTrans.y;

    out.x += screenOffset.x;
    out.y += screenOffset.y;

    return out;
}

fn isoInvert(x: f32, y: f32) rl.Vector2 {
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
    rl.InitWindow(screenWidth, screenHeight, "twr-defns");

        rl.ToggleFullscreen();
    rl.SetTargetFPS(60);

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();
    rl.SetMasterVolume(0);
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
    {
        const mapDataF = try std.fs.cwd().openFile("assets/calebsprites/map1.tmj", .{});
        defer mapDataF.close();
        var mapDataJSON = try mapDataF.reader().readAllAlloc(ally, 1024 * 10);
        defer ally.free(mapDataJSON);

        parser.reset();
        var parsedMapData = try parser.parse(mapDataJSON);
        var layers = parsedMapData.root.Object.get("layers") orelse unreachable;
        map.layerCount = @intCast(u8, layers.Array.items.len);
        for (layers.Array.items) |layer, layerIndex| {
            const tileIndiciesData = layer.Object.get("data") orelse unreachable;
            for (tileIndiciesData.Array.items) |tileIndex, tileIndexIndex| {
                map.tileIndicies[layerIndex][tileIndexIndex] = @intCast(u32, tileIndex.Integer);
            }
        }

        //        const pathLayer = layers.Array.items[1];
        //        const pathObjects = pathLayer.Object.get("objects") orelse unreachable;
        //        for (pathObjects.Array.items) |pathPointValue| {
        //            const xValue = pathPointValue.Object.get("x") orelse unreachable;
        //            const yValue = pathPointValue.Object.get("y") orelse unreachable;
        //            try pathPoints.append(rl.Vector2{
        //                .x = switch (xValue) {
        //                    .Float => |value| @floatCast(f32, value),
        //                    .Integer => |value| @intToFloat(f32, value),
        //                    else => unreachable,
        //                },
        //                .y = switch (yValue) {
        //                    .Float => |value| @floatCast(f32, value),
        //                    .Integer => |value| @intToFloat(f32, value),
        //                    else => unreachable,
        //                },
        //            });
        //        }
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
    var tickFrameCounter: u8 = 0;

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

    var enemyDir = EnemyDir.down;
    var enemyPos = rl.Vector2{ .x = @intToFloat(f32, startTileX), .y = @intToFloat(f32, startTileY) };
    var prevEnemyPos = enemyPos;

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

        // Move enemy
        tickFrameCounter += 1;
        if (tickFrameCounter >= @divTrunc(60, tickSpeed)) {
            tickFrameCounter = 0;
            updateEnemy(&tileset, &map, &enemyPos, &prevEnemyPos, &enemyDir);
        }

        // Get mouse position
        var mousePos = rl.GetMousePosition();
        var selectedTilePos = isoInvert(@round(mousePos.x), @round(mousePos.y));
        const selectedTileX = @floatToInt(i32, selectedTilePos.x);// + 2; // TODO(caleb): BAD FIXME!
        const selectedTileY = @floatToInt(i32, selectedTilePos.y);// + 1;

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLUE);

        var layerIndex: u8 = 0;
        while (layerIndex < map.layerCount) : (layerIndex += 1) {
            var tileY: u32 = 0;
            while (tileY < mapHeightInTiles) : (tileY += 1) {
                var tileX: u32 = 0;
                while (tileX < mapWidthInTiles) : (tileX += 1) {
                    const mapTileIndex = map.tileIndicies[layerIndex][tileY * mapWidthInTiles + tileX];
                    if (mapTileIndex == 0) {
                        continue;
                    }
                    const targetTileRow = @divTrunc(mapTileIndex - 1, tileset.columns);
                    const targetTileColumn = @mod(mapTileIndex - 1, tileset.columns);

                    var destPos = isoTransform(@intToFloat(f32, tileX), @intToFloat(f32, tileY));

                    if (tileX == selectedTileX and tileY == selectedTileY) {
                        destPos.y -= 5;
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

        const animTileIndex = animTileIndicies.items[0] + @enumToInt(enemyDir) * 4 + animCurrentFrame;
        std.debug.assert(animTileIndex != 0); // Has an anim?
        const targetTileRow = @divTrunc(animTileIndex - 1, tileset.columns);
        const targetTileColumn = @mod(animTileIndex - 1, tileset.columns);

        // NOTE(caleb): Since this tile is "on top" of other tiles translate by - 1
        var destPos = isoTransform(enemyPos.x - 1, enemyPos.y - 1);

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
        rl.EndDrawing();
    }

    rl.CloseWindow();
}
