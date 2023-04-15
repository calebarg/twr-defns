const std = @import("std");
const rl = @import("raylib");

const Tileset = struct {
    columns: u32,
    tex: rl.Texture,
};

const maxLayers = 5;
const scaleFactor = 3;
const mapWidthInTiles = 16;
const mapHeightInTiles = 16;
const spriteWidth = 32;
const spriteHeight = 32;
const screenWidth = mapWidthInTiles * spriteWidth * scaleFactor;
const screenHeight = mapHeightInTiles * spriteHeight * scaleFactor;

const animFramesSpeed = 4;
const tickSpeed = 1;

fn isoTransform(x: f32, y: f32) rl.Vector2 {
    const inputVec = rl.Vector2{.x = x, .y = y};
    var out: rl.Vector2 = undefined;

    const xTransVec = rl.Vector2{.x = @intToFloat(f32, spriteWidth * scaleFactor) * 0.5, .y = @intToFloat(f32, spriteHeight * scaleFactor) * 0.25 };
    const yTransVec = rl.Vector2{.x = -1 * @intToFloat(f32, spriteWidth * scaleFactor) * 0.5, .y = @intToFloat(f32, spriteHeight * scaleFactor) * 0.25 };

    out.x = inputVec.x * xTransVec.x + inputVec.y * yTransVec.x;
    out.y = inputVec.x * xTransVec.y + inputVec.y * yTransVec.y;

    return out;
}

pub fn main() !void {
    rl.InitWindow(screenWidth, screenHeight, "twr-defns");

//    rl.ToggleFullscreen();
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
    }

    // Load map data
    var mapTileIndicies: [maxLayers][mapWidthInTiles * mapHeightInTiles]u32 = undefined;
    var layerCount: usize = 0;
//    var pathPoints = std.ArrayList(rl.Vector2).init(ally);
//    defer pathPoints.deinit();
    {
        const mapDataF = try std.fs.cwd().openFile("assets/calebsprites/map1.tmj", .{});
        defer mapDataF.close();
        var mapDataJSON = try mapDataF.reader().readAllAlloc(ally, 1024 * 10);
        defer ally.free(mapDataJSON);

        parser.reset();
        var parsedMapData = try parser.parse(mapDataJSON);
        var layers = parsedMapData.root.Object.get("layers") orelse unreachable;
        layerCount = layers.Array.items.len;
        for (layers.Array.items) |layer, layerIndex|
        {
            const tileIndiciesData = layer.Object.get("data") orelse unreachable;
            for (tileIndiciesData.Array.items) |tileIndex, tileIndexIndex| {
                mapTileIndicies[layerIndex][tileIndexIndex] = @intCast(u32, tileIndex.Integer);
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

 //   var enemyPos = rl.Vector2{

    // TODO(caleb): Disable escape key to close... ( why is this on by default? )
    while (!rl.WindowShouldClose()) { // Detect window close button or ESC key
        if (!rl.IsSoundPlaying(sickJam)) {// and rl.IsMusicReady(sickJam)) {
            rl.PlaySound(sickJam);
        }

        animFramesCounter += 1;
        if (animFramesCounter >= @divTrunc(60, animFramesSpeed)) {
            animFramesCounter = 0;
            animCurrentFrame += 1;
            if (animCurrentFrame > 3) animCurrentFrame = 0; // NOTE(caleb): 3 is frames per animation - 1
        }

        tickFrameCounter += 1;
        if (tickFrameCounter >= @divTrunc(60, tickSpeed)) {
            tickFrameCounter = 0;
            // Advance to next tile?
        }

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLUE);

        var layerIndex: usize = 0;
        while (layerIndex < layerCount) : (layerIndex += 1) {
            var tileY: u32 = 0;
            while (tileY < mapHeightInTiles) : (tileY += 1) {
                var tileX: u32 = 0;
                while (tileX < mapWidthInTiles) : (tileX += 1) {
                    const mapTileIndex = mapTileIndicies[layerIndex][tileY * mapWidthInTiles + tileX];
                    if (mapTileIndex == 0) {
                        continue;
                    }
                    const targetTileRow = @divTrunc(mapTileIndex - 1, tileset.columns);
                    const targetTileColumn = @mod(mapTileIndex - 1, tileset.columns);

                    var destPos = isoTransform(@intToFloat(f32, tileX), @intToFloat(f32, tileY));

                    // Handle screen offset
                    destPos.x = (destPos.x + screenWidth / 2 - spriteWidth * scaleFactor / 2);
                    destPos.y = (destPos.y + screenHeight / 4);

//                    destPos.x += @intToFloat(f32, tileX * 30);
//                    destPos.y += @intToFloat(f32, tileY * 30);

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

                    rl.DrawTexturePro(tileset.tex, sourceRect, destRect, .{.x = 0, .y = 0}, 0, rl.WHITE);
                }
            }
        }

        const animTileIndex = animTileIndicies.items[0] + 4 + animCurrentFrame;
        std.debug.assert(animTileIndex != 0); // Has an anim?
        const targetTileRow = @divTrunc(animTileIndex - 1, tileset.columns);
        const targetTileColumn = @mod(animTileIndex - 1, tileset.columns);

        var destPos = isoTransform(@intToFloat(f32, 1), @intToFloat(f32, 9));

        // Handle screen offset
        destPos.x = (destPos.x + screenWidth / 2 - spriteWidth * scaleFactor / 2);
        destPos.y = (destPos.y + screenHeight / 4);

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

        rl.DrawFPS(0, 0); // where is fps?

        rl.EndDrawing();
    }

    rl.CloseWindow();
}
