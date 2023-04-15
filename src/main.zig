const std = @import("std");
const rl = @import("raylib");

const Tileset = struct {
    columns: u32,
    tex: rl.Texture,
};

const scaleFactor = 3;
const mapWidthInTiles = 30;
const mapHeightInTiles = 20;
const screenWidth = mapWidthInTiles * 16 * scaleFactor;
const screenHeight = mapHeightInTiles * 16 * scaleFactor;

const framesSpeed = 5;

pub fn main() !void {
    rl.InitWindow(screenWidth, screenHeight, "twr-defns");
//    rl.ToggleFullscreen();
    rl.SetTargetFPS(60);

    var ally = std.heap.page_allocator;
    var parser = std.json.Parser.init(ally, false);
    defer parser.deinit();

    // Load tileset
    var tileset: Tileset = undefined;
    tileset.tex = rl.LoadTexture("assets/blowharder.png");
    defer rl.UnloadTexture(tileset.tex);
    {
        const tilesetF = try std.fs.cwd().openFile("assets/blowharder.tsj", .{});
        defer tilesetF.close();
        var rawTilesetJSON = try tilesetF.reader().readAllAlloc(ally, 1024 * 5); // 5kib should be enough
        defer ally.free(rawTilesetJSON);

        var parsedTilesetData = try parser.parse(rawTilesetJSON);

        const columnsValue = parsedTilesetData.root.Object.get("columns") orelse unreachable;
        tileset.columns = @intCast(u32, columnsValue.Integer);
    }

    // Load map data
    var mapTileIndicies: [mapWidthInTiles * mapHeightInTiles]u32 = undefined;
    var pathPoints = std.ArrayList(rl.Vector2).init(ally);
    defer pathPoints.deinit();
    {
        const mapDataF = try std.fs.cwd().openFile("assets/map1.tmj", .{});
        defer mapDataF.close();
        var mapDataJSON = try mapDataF.reader().readAllAlloc(ally, 1024 * 10);
        defer ally.free(mapDataJSON);

        parser.reset();
        var parsedMapData = try parser.parse(mapDataJSON);
        var layers = parsedMapData.root.Object.get("layers") orelse unreachable;

        std.debug.assert(layers.Array.items.len == 2);

        const tileIndiciesLayer = layers.Array.items[0];
        const tileIndiciesData = tileIndiciesLayer.Object.get("data") orelse unreachable;
        for (tileIndiciesData.Array.items) |tileIndex, tileIndexIndex| {
            mapTileIndicies[tileIndexIndex] = @intCast(u32, tileIndex.Integer);
        }

        const pathLayer = layers.Array.items[1];
        const pathObjects = pathLayer.Object.get("objects") orelse unreachable;
        for (pathObjects.Array.items) |pathPointValue| {
            const xValue = pathPointValue.Object.get("x") orelse unreachable;
            const yValue = pathPointValue.Object.get("y") orelse unreachable;
            try pathPoints.append(rl.Vector2{
                .x = switch (xValue) {
                    .Float => |value| @floatCast(f32, value),
                    .Integer => |value| @intToFloat(f32, value),
                    else => unreachable,
                },
                .y = switch (yValue) {
                    .Float => |value| @floatCast(f32, value),
                    .Integer => |value| @intToFloat(f32, value),
                    else => unreachable,
                },
            });
        }
    }

    // Store FIRST animation index for each sprite in tile set.
    // NOTE(caleb): There are 9 frames per index stored in this list. ( down anim, right anim, up anim )
    //  where each animation is 3 frames.
    var animTileIndicies = std.ArrayList(u32).init(ally);
    defer animTileIndicies.deinit();
    {
        const animDataF = try std.fs.cwd().openFile("assets/anims.tmj", .{});
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

    var currentFrame: u8 = 0;
    var framesCounter: u8 = 0;

    // TODO(caleb): Disable escape key to close... ( why is this on by default? )
    while (!rl.WindowShouldClose()) { // Detect window close button or ESC key

        // Update

        framesCounter += 1;
        if (framesCounter >= @divTrunc(60, framesSpeed)) {
            framesCounter = 0;
            currentFrame += 1;
            if (currentFrame > 2) currentFrame = 0;
        }

        // Draw

        rl.BeginDrawing();

        rl.ClearBackground(rl.WHITE);

        var tileY: u32 = 0;
        while (tileY < mapHeightInTiles) : (tileY += 1) {
            var tileX: u32 = 0;
            while (tileX < mapWidthInTiles) : (tileX += 1) {
                const mapTileIndex = mapTileIndicies[tileY * mapWidthInTiles + tileX];
                const targetTileRow = @divTrunc(mapTileIndex, tileset.columns);
                const targetTileColumn = @mod(mapTileIndex, tileset.columns) - 1;

                const sourceRect = rl.Rectangle{
                    .x = @intToFloat(f32, targetTileColumn * 16),
                    .y = @intToFloat(f32, targetTileRow * 16),
                    .width = 16,
                    .height = 16,
                };
                const destRect = rl.Rectangle{
                    .x = @intToFloat(f32, tileX * 16 * scaleFactor),
                    .y = @intToFloat(f32, tileY * 16 * scaleFactor),
                    .width = 16 * scaleFactor,
                    .height = 16 * scaleFactor,
                };

                rl.DrawTexturePro(tileset.tex, sourceRect, destRect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);
            }
        }

        const animTileIndex = animTileIndicies.items[21] + currentFrame + 3;
        const targetTileRow = @divTrunc(animTileIndex, tileset.columns);
        const targetTileColumn = @mod(animTileIndex, tileset.columns) - 1;

        const sourceRect = rl.Rectangle{
            .x = @intToFloat(f32, targetTileColumn * 16),
            .y = @intToFloat(f32, targetTileRow * 16),
            .width = 16,
            .height = 16,
        };
        const destRect = rl.Rectangle{
            .x = @intToFloat(f32, 5 * 16 * scaleFactor),
            .y = @intToFloat(f32, 5 * 16 * scaleFactor),
            .width = 16 * scaleFactor,
            .height = 16 * scaleFactor,
        };
        rl.DrawTexturePro(tileset.tex, sourceRect, destRect, .{ .x = 0, .y = 0 }, 0, rl.WHITE);

        rl.DrawFPS(0, 0);

        rl.EndDrawing();
    }

    // De-Initialization
    rl.CloseWindow(); // Close window and OpenGL context
}
