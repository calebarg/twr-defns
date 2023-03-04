const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
    @cInclude("stdlib.h");
    @cInclude("X11/Xlib.h");
    @cInclude("GL/glx.h");
});

const linux_display = c.Display;
const linux_window = c.Window;
const linux_glx_context = c.GLXContext;

const x_event = c.XEvent;
const x_key_event = c.XKeyEvent;
const x_window_attributes = c.XWindowAttributes;

const linux_state = struct
{
    Display: ?*linux_display,
    Window: linux_window,
    GC: linux_glx_context,

    EventMask: i64,
};

const button_state = struct
{
    WasDown: bool,
    IsDown: bool,
};


const controller = struct
{
    const RightIndex = 0;
    const LeftIndex = 1;
    const UpIndex = 2;
    const DownIndex = 3;

    Buttons: [4]button_state,
};

const game_input = struct
{
    Controller: controller,
    MouseX: u32,
    MouseY: u32,
    dTimeMS: f32,
};

const XKeyCodeEscape = 66;
const XKeyCodeEnter = 36;
const XKeyCodeSpace = 65;
const XKeyCodeW = 25;
const XKeyCodeA = 38;
const XKeyCodeS = 39;
const XKeyCodeD = 40;
const XKeyCodeUp = 111;
const XKeyCodeDown = 116;
const XKeyCodeLeft = 113;
const XKeyCodeRight = 114;

var Running: bool = false;

fn LinuxProcessButtonPress(XKey: x_key_event, BS: *button_state) callconv(.Inline) void
{
    if (XKey.type == c.KeyPress)
    {
        BS.*.IsDown = true;
    }
    else
    {
        BS.*.IsDown = false;
    }
}

fn LinuxProcessKey(XKey: x_key_event, Controller: *controller) void
{
    switch(XKey.keycode)
    {
        XKeyCodeEscape =>
        {
            Running = false;
        },
        XKeyCodeD =>
        {
            LinuxProcessButtonPress(XKey, &Controller.*.Buttons[controller.RightIndex]);
        },
        XKeyCodeA =>
        {
            LinuxProcessButtonPress(XKey, &Controller.*.Buttons[controller.LeftIndex]);
        },
        XKeyCodeW =>
        {
            LinuxProcessButtonPress(XKey, &Controller.*.Buttons[controller.UpIndex]);
        },
        XKeyCodeS =>
        {
            LinuxProcessButtonPress(XKey, &Controller.*.Buttons[controller.DownIndex]);
        },
        else => {},
    }
}

fn LinuxProcessEvents(LinuxState: *linux_state, Input: *game_input) void
{
    var WindowAttributes: x_window_attributes = undefined;
    _ = c.XGetWindowAttributes(LinuxState.*.Display, LinuxState.*.Window, &WindowAttributes);

    var Event: x_event = undefined;
    while (c.XCheckWindowEvent(LinuxState.*.Display,
            LinuxState.*.Window, LinuxState.*.EventMask, &Event) != 0)
    {
        switch (Event.type)
        {
            c.ConfigureNotify =>
            {
                c.glViewport(0, 0, @intCast(c_int, Event.xconfigure.width),
                    @intCast(c_int, Event.xconfigure.height));
            },
            c.DestroyNotify =>
            {
                Running = false;
            },
            c.KeyRelease, c.KeyPress =>
            {
                LinuxProcessKey(Event.xkey, &Input.*.Controller);
            },
            c.MotionNotify =>
            {
                Input.*.MouseX = @intCast(u32, Event.xmotion.x);
                Input.*.MouseY = @intCast(u32, Event.xmotion.y);
            },
            else => {},
        }
    }
}

fn LinuxGetTimeMS() callconv(.Inline) f32
{
    var Result: f32 = undefined;
    Result = @intToFloat(f32, @divTrunc(c.clock(), c.CLOCKS_PER_SEC) * 1000);
    return Result;
}

fn LinuxWaitForWindowToMap(LinuxState: *linux_state) void
{
    var Event: c.XEvent = undefined;
    _ = c.XNextEvent(LinuxState.*.Display, &Event);
    while (Event.type != c.MapNotify)
    {
        _ = c.XNextEvent(LinuxState.*.Display, &Event);
    }
}

pub fn main() !void
{
    var LinuxState: linux_state = undefined;

    const BufferWidth: u32 = 640;
    const BufferHeight: u32 = 480;

    const DefaultDisplay: ?*u8 = c.getenv("DISPLAY");
    if (DefaultDisplay != null)
    {
        LinuxState.Display = c.XOpenDisplay(DefaultDisplay.?);
    }
    else
    {
        LinuxState.Display = c.XOpenDisplay(null);
    }

    if (LinuxState.Display != null)
    {
        var AttributeList = [_]c_int{ c.GLX_RGBA, c.None };
        const VisualInfo: ?*c.XVisualInfo = c.glXChooseVisual(LinuxState.Display,
                        c.DefaultScreen(LinuxState.Display), @ptrCast(?*c_int, &AttributeList));

        LinuxState.GC = c.glXCreateContext(LinuxState.Display, VisualInfo, null, c.GL_TRUE);
        if (LinuxState.GC == null)
        {
            std.debug.print("Failed to create glX context\n", .{});
            unreachable;
        }

        LinuxState.EventMask =
            c.StructureNotifyMask|c.KeyPressMask|c.KeyReleaseMask|c.PointerMotionMask;

        var SWA: c.XSetWindowAttributes = undefined;
        SWA.colormap = c.XCreateColormap(LinuxState.Display, c.RootWindow(LinuxState.Display,
                VisualInfo.?.screen), VisualInfo.?.visual, c.AllocNone);
        SWA.border_pixel = 0;
        SWA.event_mask = LinuxState.EventMask;

        LinuxState.Window = c.XCreateWindow(LinuxState.Display, c.RootWindow(LinuxState.Display, VisualInfo.?.screen),
            0, 0, BufferWidth, BufferHeight, 0, VisualInfo.?.depth,
            c.InputOutput,
            VisualInfo.?.visual, c.CWBorderPixel|c.CWColormap|c.CWEventMask, &SWA
        );

        _ = c.XMapWindow(LinuxState.Display, LinuxState.Window);
        LinuxWaitForWindowToMap(&LinuxState);
        _ = c.glXMakeCurrent(LinuxState.Display, LinuxState.Window, LinuxState.GC);

        var Input: game_input = undefined;
        var OldController: controller = undefined;

        var LastTimeMS: f32 = LinuxGetTimeMS();
        const FPS = 60;
        const TargetFrameTimeMS: f32 = 1000 / FPS;

        Running = true;
        while(Running)
        {
            const TimeNowMS = LinuxGetTimeMS();
            const TimeSinceLastFrameMS = TimeNowMS - LastTimeMS;

            if (TimeSinceLastFrameMS < TargetFrameTimeMS)
            {
                const TimeToSleepMS = (TargetFrameTimeMS - TimeSinceLastFrameMS);
                std.time.sleep(@floatToInt(u64, TimeToSleepMS * 1000 * 1000));
            }
            LastTimeMS = TimeNowMS;

            LinuxProcessEvents(&LinuxState, &Input);
            var ButtonIndex: u32 = 0;
            while (ButtonIndex < Input.Controller.Buttons.len) : (ButtonIndex += 1)
            {
                if (OldController.Buttons[ButtonIndex].IsDown)
                {
                    Input.Controller.Buttons[ButtonIndex].WasDown = true;
                }
                else
                {
                    Input.Controller.Buttons[ButtonIndex].WasDown = false;
                }
            }
            Input.dTimeMS = TimeSinceLastFrameMS;
            OldController = Input.Controller;

            // Draw
            c.glClearColor(1.0, 1.0, 1.0, 1.0);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
            c.glXSwapBuffers(LinuxState.Display, LinuxState.Window);
        }
    }
}
