// Makes tearing a browser tab out into its own window behave, instead of
// springing back and then landing on top of everything.
//
// The bug, in one line: GlazeWM forces OS focus onto any window the instant
// it appears, and Chromium tears a tab off by creating the window and then
// running a nested modal drag loop on it, so that forced focus cancels the
// drag. The full diagnosis, with the file and line of every step, is in
// FLAGS.md FLAG-65; the short version is that the fix belongs upstream and
// cannot be done from outside GlazeWM.
//
// What can be done from outside is stopping GlazeWM from acting during the
// drag at all. ref/glazewm/packages/wm/src/wm.rs:146 gates the whole
// platform_sync flush, forced focus included, on the window manager not
// being paused, while the events themselves still run: the torn-off window
// is added to the tree during the pause and simply not touched. Unpausing
// then queues a redraw of the entire container tree
// (ref/glazewm/packages/wm/src/commands/general/toggle_pause.rs:11), so the
// new window is tiled properly the moment the drag ends. Pause for the drag,
// resume after it, and the tear-off works the way it does on Omarchy.
//
// Deciding when to do that without breaking anything else is the whole
// difficulty, and it comes down to one observation: when a tab is torn out,
// the window it came from STAYS PUT, and when a window is dragged by its
// title bar, it MOVES. So this watches for a press near the top of a window
// followed by cursor movement with the window itself not having moved, and
// only then pauses. Dragging a window to another tile, dragging a floating
// window somewhere, and resizing by an edge all move the window, so all
// three are left completely alone.
//
// Polling, not a hook. A WH_MOUSE_LL hook would be cheaper at idle, but the
// process already carries one low-level keyboard hook, and a second hook on
// the mouse is both the exact shape antivirus heuristics look for
// (docs/defender.md) and another callback against the LowLevelHooksTimeout
// deadline. GetAsyncKeyState on a background thread costs a syscall every
// 60ms while nothing is happening, and touches nothing anyone can see.

using System;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace Winmarchy.Chooser;

public static class DragGuard
{
    // How far down a window a press has to land to count as "on the title
    // bar or tab strip". A Chromium tab strip is about 40 pixels tall at
    // 96 DPI and a title bar about 22, so two title bars is a good proxy
    // that scales with the display, and the floor covers the case where the
    // metric comes back small. See StripHeight below for why the scaling is
    // done this way rather than from the monitor's DPI.
    private const int StripFloorPixels = 48;
    // How far the cursor must travel before a press counts as a drag. Well
    // above the system's own drag threshold (four pixels), so a plain click
    // never pauses anything, and well below the distance a tab has to travel
    // to leave its strip, so the pause is always in place first.
    private const int DragThresholdPixels = 16;
    // A drag cannot reasonably run longer than this. If one appears to, the
    // pause is released regardless: a stuck mouse button must never be able
    // to leave the window manager paused.
    private const int MaxHoldSeconds = 30;
    // Chromium finishes placing its new window just after the button comes
    // up. Resuming into that leaves the redraw racing the browser, so it
    // waits out the tail of the drag first.
    private const int SettleMilliseconds = 120;
    private const int IdlePollMilliseconds = 60;
    private const int DragPollMilliseconds = 15;
    private const int DisconnectedPollMilliseconds = 500;

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    // learn.microsoft.com/windows/win32/api/winuser/ for all five, and
    // learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getdpiforwindow
    // for the DPI call (Windows 10 1607 and later; this is Windows 11 only).
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(Point point);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    // learn.microsoft.com/windows/win32/inputdev/virtual-key-codes
    private const int VkLeftButton = 0x01;
    // GA_ROOT: walk up to the top level window that owns the point.
    private const uint GaRoot = 2;
    // SM_CYCAPTION: the height of a caption (title) bar.
    private const int SmCyCaption = 4;

    private static readonly PauseLink Link = new PauseLink();
    private static Thread? _thread;
    private static volatile bool _stopping;

    // Touched only by the poll thread.
    private static bool _buttonDown;
    private static Point _anchor;
    private static IntPtr _source = IntPtr.Zero;
    private static Rect _sourceRect;
    private static bool _candidate;
    private static long _pausedAtTicks;
    private static int _pauseCount;

    // Whether the guard is holding a pause: 1 if it is. An int rather than a
    // bool because shutdown resumes from the tray's thread while the poll
    // thread may be doing the same, and two resumes for one pause would
    // leave tiling paused, which is the one outcome this file exists to
    // prevent. Interlocked makes claiming the resume a single winner.
    private static int _pausedByUs;

    public static void Install()
    {
        if (_thread != null)
        {
            return;
        }
        Link.Start();
        _thread = new Thread(PollLoop)
        {
            IsBackground = true,
            Name = "WinmarchyDragGuard",
        };
        _thread.Start();
        Paths.Log("drag guard: watching for tab tear-offs");
    }

    public static void Uninstall()
    {
        _stopping = true;
        // Whatever else happens on the way out, tiling does not stay paused.
        Resume("the guard is shutting down");
        Link.Stop();
    }

    private static void PollLoop()
    {
        while (!_stopping)
        {
            var wait = IdlePollMilliseconds;
            try
            {
                wait = Tick();
            }
            catch (Exception ex)
            {
                // A guard that throws must not take a pause to the grave
                // with it, and must not spin.
                Resume("the guard hit an error (" + ex.Message + ")");
                Reset();
                wait = DisconnectedPollMilliseconds;
            }
            Thread.Sleep(wait);
        }
    }

    /// One poll. Returns how long to wait before the next one.
    private static int Tick()
    {
        if (!Link.Connected)
        {
            // No GlazeWM means Windows 11 mode, or a swap in progress.
            // Nothing to pause, and nothing worth polling quickly for. A
            // pause outstanding at this point still has to be accounted
            // for, so that a GlazeWM that comes back still paused is put
            // right rather than left that way.
            Reset();
            Resume("GlazeWM went away mid-drag");
            return DisconnectedPollMilliseconds;
        }

        var down = (GetAsyncKeyState(VkLeftButton) & 0x8000) != 0;
        if (!down)
        {
            var wasPaused = Volatile.Read(ref _pausedByUs) == 1;
            Reset();
            if (wasPaused)
            {
                Thread.Sleep(SettleMilliseconds);
                Resume("the drag finished");
            }
            return IdlePollMilliseconds;
        }

        if (!_buttonDown)
        {
            // The press. Everything the decision needs is recorded now,
            // because by the time the drag is recognisable the window may
            // already have moved.
            _buttonDown = true;
            _candidate = false;
            _source = IntPtr.Zero;
            if (GetCursorPos(out _anchor))
            {
                _candidate = LandedOnAStrip(_anchor, out _source, out _sourceRect);
            }
            return DragPollMilliseconds;
        }

        if (Volatile.Read(ref _pausedByUs) == 1)
        {
            if (Stopwatch.GetTimestamp() - _pausedAtTicks > MaxHoldSeconds * Stopwatch.Frequency)
            {
                Resume("the button has been held for " + MaxHoldSeconds + " seconds");
                // And the press is finished with, or the next poll would see
                // a moved cursor over a still window and pause all over
                // again, every thirty seconds for as long as it is held.
                _candidate = false;
            }
            return DragPollMilliseconds;
        }

        if (!_candidate)
        {
            return DragPollMilliseconds;
        }

        Point now;
        if (!GetCursorPos(out now))
        {
            return DragPollMilliseconds;
        }
        var dx = now.X - _anchor.X;
        var dy = now.Y - _anchor.Y;
        if ((dx * dx) + (dy * dy) < DragThresholdPixels * DragThresholdPixels)
        {
            return DragPollMilliseconds;
        }

        // The discriminator. If the window has moved with the cursor, this
        // is someone dragging a window around, which is GlazeWM's business
        // and none of ours: give up on this press entirely rather than
        // pausing and having the window snap back when the redraw lands.
        Rect current;
        if (!GetWindowRect(_source, out current))
        {
            _candidate = false;
            return DragPollMilliseconds;
        }
        if (current.Left != _sourceRect.Left || current.Top != _sourceRect.Top
            || current.Right != _sourceRect.Right || current.Bottom != _sourceRect.Bottom)
        {
            _candidate = false;
            return DragPollMilliseconds;
        }

        Pause();
        return DragPollMilliseconds;
    }

    /// Whether a press landed in the top strip of a top level window: the
    /// tab strip on a browser, the title bar on everything else. Anything
    /// that tears a new window out of an existing one starts there.
    private static bool LandedOnAStrip(Point point, out IntPtr root, out Rect rect)
    {
        root = IntPtr.Zero;
        rect = default;
        var hit = WindowFromPoint(point);
        if (hit == IntPtr.Zero)
        {
            return false;
        }
        root = GetAncestor(hit, GaRoot);
        if (root == IntPtr.Zero)
        {
            root = hit;
        }
        if (!GetWindowRect(root, out rect))
        {
            return false;
        }
        return point.Y >= rect.Top && point.Y - rect.Top <= StripHeight();
    }

    /// The depth of the strip, in the same coordinate space the cursor and
    /// the window rectangle come back in.
    ///
    /// GetDpiForWindow would give the display's real scaling, but the two
    /// would then disagree whenever this process is not per-monitor DPI
    /// aware, because GetCursorPos and GetWindowRect are virtualised to 96
    /// DPI for a process that is not, while the monitor's DPI is not. This
    /// project ships no manifest saying which of those it is, so the safe
    /// scaling is one that lives in the same space as the coordinates:
    /// GetSystemMetrics reports in the caller's own DPI awareness context,
    /// so it virtualises exactly when they do.
    private static int StripHeight()
    {
        var caption = GetSystemMetrics(SmCyCaption) * 2;
        if (caption < StripFloorPixels)
        {
            return StripFloorPixels;
        }
        return caption;
    }

    private static void Reset()
    {
        _buttonDown = false;
        _candidate = false;
        _source = IntPtr.Zero;
    }

    private static void Pause()
    {
        if (Link.Paused)
        {
            // Already paused by hand with lwin+p. Leave it exactly as found:
            // the drag will work anyway, and resuming something the user
            // paused would be worse than doing nothing.
            _candidate = false;
            return;
        }
        if (!Link.Toggle())
        {
            _candidate = false;
            return;
        }
        Interlocked.Exchange(ref _pausedByUs, 1);
        _pausedAtTicks = Stopwatch.GetTimestamp();
        _pauseCount++;
        Paths.Log("drag guard: tiling paused for a drag (" + _pauseCount + " so far this session)");
    }

    /// Puts tiling back, and checks that it went back. Every exit from a
    /// pause comes through here, because a window manager left paused looks
    /// exactly like a broken one and the user never asked for it.
    private static void Resume(string why)
    {
        // One winner. Shutdown resumes from the tray's thread and the poll
        // thread may be doing the same, and two resumes for one pause would
        // put tiling straight back into the state this is undoing.
        if (Interlocked.Exchange(ref _pausedByUs, 0) == 0)
        {
            return;
        }
        for (var attempt = 0; attempt < 3; attempt++)
        {
            if (!Link.Connected)
            {
                // GlazeWM has gone. Nothing is left paused, because a fresh
                // one starts unpaused; the note covers the other case, where
                // this same one comes back with the pause still on it.
                Link.NoteStrandedPause();
                Paths.Log("drag guard: GlazeWM went away while tiling was paused; it will be resumed if it comes back");
                return;
            }
            if (!Link.Paused)
            {
                Paths.Log("drag guard: tiling resumed because " + why);
                return;
            }
            Link.Toggle();
            // And ask what actually happened. Toggle assumes it worked, so
            // without this the check above would only ever be reading back
            // the guard's own optimism.
            Link.RefreshPaused();
            Thread.Sleep(150);
        }
        Paths.Log("drag guard: COULD NOT RESUME TILING; press lwin+p to turn it back on");
    }
}

/// The socket to GlazeWM that the guard pauses over.
///
/// Deliberately long lived rather than a connection per pause: the pause has
/// to land within a frame or two of the cursor crossing the threshold, and a
/// fresh WebSocket handshake at that moment would be the one slow thing on
/// the whole path. Keeping it open also means the paused state arrives as an
/// event, so the guard never has to ask and wait for an answer.
///
/// Protocol verified the same way as GlazewmIpc.cs: the port and the message
/// envelope from ref/glazewm/packages/wm-common/src/ipc.rs, the event name
/// from the SubscribableEvent list in
/// ref/glazewm/packages/wm-common/src/app_command.rs (snake_case, so
/// PauseChanged subscribes as pause_changed), and the query and its untagged
/// boolean payload from ClientResponseData::Paused in
/// ref/glazewm/packages/wm/src/ipc_server.rs.
public sealed class PauseLink
{
    private const string SubscribeMessage = "sub -e pause_changed";
    private const string QueryPaused = "query paused";
    private const string TogglePause = "command wm-toggle-pause";
    private const int ReconnectMilliseconds = 4000;

    private readonly Uri _uri = new Uri("ws://127.0.0.1:6123");
    private readonly CancellationTokenSource _cancel = new CancellationTokenSource();
    private ClientWebSocket? _socket;
    private volatile bool _connected;
    private volatile bool _paused;
    // Set when the socket died while the guard held a pause. On the next
    // connection the paused state is checked and cleared if it survived.
    private volatile bool _stranded;

    public bool Connected
    {
        get { return _connected; }
    }

    public bool Paused
    {
        get { return _paused; }
    }

    public void NoteStrandedPause()
    {
        _stranded = true;
    }

    public void Start()
    {
        Task.Run(() => RunAsync(_cancel.Token));
    }

    public void Stop()
    {
        try
        {
            _cancel.Cancel();
            _cancel.Dispose();
        }
        catch
        {
            // Shutdown must never throw.
        }
    }

    /// Sends the one command this link has any business sending. Fire and
    /// forget: the caller never blocks on the answer.
    ///
    /// The local state is flipped straight away rather than waiting for the
    /// pause_changed event to come back. Waiting reads correctly but behaves
    /// badly: a short drag can finish before the event for its own pause has
    /// arrived, at which point a caller checking the state would see "not
    /// paused", skip the resume, and leave tiling paused for good. The event
    /// still arrives and still overwrites this, so a toggle that did not
    /// land corrects itself.
    public bool Toggle()
    {
        var socket = _socket;
        if (socket == null || socket.State != WebSocketState.Open)
        {
            return false;
        }
        _ = SendAsync(socket, TogglePause, _cancel.Token);
        _paused = !_paused;
        return true;
    }

    /// Asks for the paused state again, so the next read is GlazeWM's answer
    /// rather than the assumption Toggle made.
    public void RefreshPaused()
    {
        var socket = _socket;
        if (socket == null || socket.State != WebSocketState.Open)
        {
            return;
        }
        _ = SendAsync(socket, QueryPaused, _cancel.Token);
    }

    private async Task RunAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                using var socket = new ClientWebSocket();
                await socket.ConnectAsync(_uri, token).ConfigureAwait(false);
                _socket = socket;
                await SendAsync(socket, SubscribeMessage, token).ConfigureAwait(false);
                await SendAsync(socket, QueryPaused, token).ConfigureAwait(false);
                _connected = true;
                await ReadLoopAsync(socket, token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch
            {
                // No GlazeWM running is the normal case in Windows 11 mode,
                // so this is silent by design and simply retried.
            }
            finally
            {
                _socket = null;
                _connected = false;
            }
            try
            {
                await Task.Delay(ReconnectMilliseconds, token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    private async Task ReadLoopAsync(ClientWebSocket socket, CancellationToken token)
    {
        var buffer = new byte[8192];
        var message = new StringBuilder();
        while (socket.State == WebSocketState.Open && !token.IsCancellationRequested)
        {
            message.Clear();
            WebSocketReceiveResult result;
            do
            {
                result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), token).ConfigureAwait(false);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    return;
                }
                message.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
            }
            while (!result.EndOfMessage);
            HandleMessage(socket, message.ToString(), token);
        }
    }

    private void HandleMessage(ClientWebSocket socket, string json, CancellationToken token)
    {
        try
        {
            var node = JsonNode.Parse(json);
            if (node == null)
            {
                return;
            }
            var messageType = node["messageType"]?.GetValue<string>();
            if (messageType == "event_subscription")
            {
                var data = node["data"];
                if (data?["eventType"]?.GetValue<string>() != "pause_changed")
                {
                    return;
                }
                var isPaused = data["isPaused"]?.GetValue<bool>();
                if (isPaused.HasValue)
                {
                    _paused = isPaused.Value;
                }
                return;
            }
            if (messageType != "client_response")
            {
                return;
            }
            if (node["clientMessage"]?.GetValue<string>() != QueryPaused)
            {
                return;
            }
            var payload = node["data"];
            if (payload == null)
            {
                return;
            }
            bool paused;
            try
            {
                paused = payload.GetValue<bool>();
            }
            catch
            {
                var nested = payload["paused"]?.GetValue<bool>();
                if (!nested.HasValue)
                {
                    return;
                }
                paused = nested.Value;
            }
            _paused = paused;
            if (_stranded)
            {
                // The socket died mid-drag with a pause outstanding and this
                // is the same GlazeWM back again, still paused. Put it back
                // the way the user had it.
                _stranded = false;
                if (paused)
                {
                    Paths.Log("drag guard: found tiling still paused after a reconnect, resuming it");
                    _ = SendAsync(socket, TogglePause, token);
                    _paused = false;
                }
            }
        }
        catch
        {
            // A message this client does not understand is not a reason to
            // drop the connection.
        }
    }

    private static async Task SendAsync(ClientWebSocket socket, string message, CancellationToken token)
    {
        try
        {
            var bytes = Encoding.UTF8.GetBytes(message);
            await socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, token)
                .ConfigureAwait(false);
        }
        catch
        {
            // A send that fails means the connection has gone; the read loop
            // ends on its own and the outer loop reconnects.
        }
    }
}
