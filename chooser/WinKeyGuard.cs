// Stops a bare Windows key tap from opening the Start menu while Omarchy
// mode is on, so the key belongs entirely to the tiling layer, the way Super
// does on Omarchy itself. Combos are untouched: GlazeWM keeps every
// lwin+something binding, and in Windows 11 mode the key behaves exactly as
// stock.
//
// Mechanism: a low-level keyboard hook (SetWindowsHookExW, WH_KEYBOARD_LL,
// documented under learn.microsoft.com/windows/win32/api/winuser/) watches
// the Windows keys. The shell opens Start on the Windows key UP when no
// other key arrived since the down, so the guard SWALLOWS that bare up and
// replays it behind a mask key:
//
//     real Win up  ->  swallowed (the hook returns 1)
//     injected     ->  vkE8 down, vkE8 up, Win up
//
// Swallowing is what makes the ordering certain. SendInput only ever
// appends to the input queue, so a mask injected while the real up is in
// flight lands AFTER it (guard v1, too late) and one injected during the
// down lands BEFORE it (v2, so the up still looked bare). Neither could
// separate the down from the up. Removing the real up and replaying the
// whole sequence puts the mask between them by construction. It also works
// if the shell ignores injected input entirely: then it sees a down and no
// up at all, and a tap that never completes opens nothing.
//
// The Windows key can never stick: the replay is attempted FIRST, and the
// real up is only swallowed once SendInput has accepted it. Only the bare
// tap is touched; the moment any other key arrives the whole combo passes
// through untouched, which is what keeps every GlazeWM binding working.
//
// Living in the tray process gives the guard the right lifetime for free:
// it dies with the tray, and killing the tray (or "Hide this icon") returns
// the Windows key to stock behaviour instantly. Recoverability beats beauty.

using System;
using System.Runtime.InteropServices;
// The mode-watch timer must be the WinForms one: its ticks run on the tray's
// message loop thread, which is also the thread that owns the hook.
using Timer = System.Windows.Forms.Timer;

namespace Winmarchy.Chooser;

public static class WinKeyGuard
{
    private const int WhKeyboardLl = 13;
    private const int WmKeydown = 0x0100;
    private const int WmKeyup = 0x0101;
    private const int WmSyskeydown = 0x0104;
    private const int WmSyskeyup = 0x0105;
    private const int VkLwin = 0x5B;
    private const int VkRwin = 0x5C;
    private const int VkUnassigned = 0xE8;
    private const uint LlkhfInjected = 0x10;

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint type;
        public InputUnion u;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KeybdInput ki;
        [FieldOffset(0)] public MouseInputPad mi;
    }

    // Padding member so the union is at least the size of MOUSEINPUT, which
    // is what SendInput expects the INPUT union to span.
    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInputPad
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeybdInput
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookExW(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint cInputs, Input[] pInputs, int cbSize);

    private static IntPtr _hook = IntPtr.Zero;
    // Static, not local: the delegate must outlive the native hook or the
    // garbage collector frees the callback under it and the process dies.
    private static readonly HookProc Proc = Callback;

    // Maintained by the timer below, read by the hook. Volatile because the
    // two never share a lock: the hook must only ever read a ready-made flag.
    private static volatile bool _omarchyActive;
    private static Timer? _modeTimer;
    // Whether the Windows key is currently held, so a release with no press
    // behind it (the key was already down when the guard armed) is left
    // alone. Touched only by the hook, on one thread.
    private static bool _winDown;
    // Incremented by the hook, reported by the timer, so the log carries
    // evidence of the guard actually firing without the hook ever logging.
    private static int _maskedTaps;
    private static int _reportedTaps;
    // The state file's timestamp at the last successful read, so the
    // once-a-second timer only re-parses state.json when a swap actually
    // rewrote it. The tray runs for the whole session; on a slow machine a
    // parse per second is the kind of idle cost that adds up to a warm fan.
    private static DateTime _stateStamp = DateTime.MinValue;
    private static bool _stateStampActive;

    // Set by the tray's timer, acted on by the hook thread. Volatile because
    // the two never share a lock, exactly like the armed flag above.
    private static volatile bool _rehookRequested;
    private static volatile bool _stopping;

    public static void Install()
    {
        if (_hook != IntPtr.Zero)
        {
            return;
        }

        // Warm the marshalling path before the first real keystroke ever
        // reaches the callback, so no first-call JIT cost lands inside it.
        var warm = Marshal.AllocHGlobal(Marshal.SizeOf<KbdLlHookStruct>());
        try
        {
            Marshal.StructureToPtr(new KbdLlHookStruct(), warm, false);
            var _ = Marshal.PtrToStructure<KbdLlHookStruct>(warm);
        }
        finally
        {
            Marshal.FreeHGlobal(warm);
        }

        // The mode lives on this timer, OUTSIDE the hook, and that is load
        // bearing: Windows gives a low-level hook callback a hard time
        // budget (the LowLevelHooksTimeout described under
        // learn.microsoft.com/windows/win32/winmsg/lowlevelkeyboardproc),
        // and a callback that overruns can have its hook silently removed,
        // after which every tap opens Start again with nothing in any log.
        // Earlier versions read and parsed state.json inside the callback;
        // one slow cold read there could kill the guard for the whole
        // session (FLAG-38). The callback now touches nothing but this flag.
        // This timer belongs to the CALLER's thread, the tray's, and does all
        // the reading, writing and logging there.
        _modeTimer = new Timer { Interval = 1000 };
        _modeTimer.Tick += (_, _) => RefreshMode();
        _modeTimer.Start();
        RefreshMode();

        // The hook itself gets a thread of its own, which exists to pump
        // messages and run the callback and does nothing else, ever.
        // A WH_KEYBOARD_LL callback is delivered on the thread that installed
        // the hook, so before this it shared the tray's message loop with the
        // notification icon, its menu, the wallpaper timer and the heartbeat
        // write that happens every single second. Any of those running long
        // made every keystroke in the system queue behind them, against a
        // deadline whose penalty is the hook being silently removed. Nothing
        // can queue in front of the callback now (FLAGS.md FLAG-54).
        var thread = new Thread(HookThreadMain)
        {
            IsBackground = true,
            Name = "WinmarchyKeyGuard",
            // Above the tray's own work, since the whole system's input waits
            // on this callback returning.
            Priority = ThreadPriority.AboveNormal,
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }

    private static void HookThreadMain()
    {
        // A module handle of zero is valid for WH_KEYBOARD_LL hooks in
        // managed code; the hook runs on this thread's message loop.
        _hook = SetWindowsHookExW(WhKeyboardLl, Proc, IntPtr.Zero, 0);
        if (_hook == IntPtr.Zero)
        {
            Paths.Log("win key guard: hook failed to install (error " + Marshal.GetLastWin32Error() + "); the Windows key keeps its stock behaviour");
            return;
        }
        Paths.Log("win key guard: hook installed on its own thread; arms and disarms with the mode");

        // The only work this thread does besides the callback: re-establish
        // the hook when the mode timer asks, and stand down on shutdown.
        // Deliberately no file access, no parsing and no logging on a tick.
        var maintenance = new Timer { Interval = 250 };
        maintenance.Tick += (_, _) =>
        {
            if (_stopping)
            {
                maintenance.Stop();
                if (_hook != IntPtr.Zero)
                {
                    UnhookWindowsHookEx(_hook);
                    _hook = IntPtr.Zero;
                }
                System.Windows.Forms.Application.ExitThread();
                return;
            }
            if (_rehookRequested)
            {
                _rehookRequested = false;
                if (_hook != IntPtr.Zero)
                {
                    UnhookWindowsHookEx(_hook);
                }
                _hook = SetWindowsHookExW(WhKeyboardLl, Proc, IntPtr.Zero, 0);
                if (_hook == IntPtr.Zero)
                {
                    Paths.Log("win key guard: RE-HOOK FAILED (error " + Marshal.GetLastWin32Error() + "); the Windows key will open Start");
                }
            }
        };
        maintenance.Start();
        System.Windows.Forms.Application.Run();
    }

    public static void Uninstall()
    {
        // The hook belongs to its own thread and is released there: the
        // callback may be mid-flight, and that thread owns the handle. This
        // just asks, and the maintenance tick stands the thread down.
        _modeTimer?.Stop();
        _stopping = true;
    }

    private static void RefreshMode()
    {
        WriteHeartbeat();
        bool active;
        try
        {
            // A real JSON parse, not a text sniff: the first version
            // searched the raw file for "mode": "omarchy" with one space,
            // and Windows PowerShell 5.1's ConvertTo-Json writes two spaces
            // after the colon, so the guard never armed on the real machine
            // (FLAG-36). The parse only happens when the file's write stamp
            // moved: a mode swap always rewrites state.json, and a missing
            // file reports a constant sentinel stamp, so "unchanged" always
            // means "same answer as last time".
            var stamp = System.IO.File.GetLastWriteTimeUtc(Paths.StateFile);
            if (stamp == _stateStamp)
            {
                active = _stateStampActive;
            }
            else
            {
                active = WinmarchyState.Load().Mode == "omarchy";
                _stateStamp = stamp;
                _stateStampActive = active;
            }
        }
        catch
        {
            active = false;
        }
        if (active != _omarchyActive)
        {
            _omarchyActive = active;
            Paths.Log(active
                ? "win key guard: armed (omarchy mode; a bare Windows key tap opens nothing)"
                : "win key guard: disarmed (the Windows key is stock again)");
            if (active)
            {
                // A fresh hook at the moment it matters: if anything removed
                // the old one along the way, arming re-establishes it. The
                // hook belongs to its own thread, so this asks rather than
                // acts; that thread picks the request up within a tick.
                _rehookRequested = true;
            }
        }
        var taps = _maskedTaps;
        if (taps != _reportedTaps)
        {
            _reportedTaps = taps;
            Paths.Log("win key guard: masked " + taps + " Windows key release(s) so far this session");
        }
    }

    private static void WriteHeartbeat()
    {
        // One small JSON file, rewritten every tick, read by winmarchy
        // doctor. Five rounds of "the key still opens Start" were spent
        // unable to tell a dead guard from a disarmed one from a firing one;
        // this file answers all three in a single doctor run: a stale tick
        // means dead, armed says whether the mode reached the guard, and
        // maskedTaps counts the taps it actually intercepted. Runs on the
        // timer thread, never in the hook.
        try
        {
            var json = "{\"pid\": " + Environment.ProcessId
                + ", \"armed\": " + (_omarchyActive ? "true" : "false")
                + ", \"maskedTaps\": " + _maskedTaps
                + ", \"tickUtc\": \"" + DateTime.UtcNow.ToString("o") + "\"}";
            System.IO.File.WriteAllText(System.IO.Path.Combine(Paths.StateDir, "winkey-guard.json"), json);
        }
        catch
        {
            // A missed heartbeat write must never hurt the guard itself.
        }
    }

    private static IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        // NOTHING slow in here, ever: no file reads, no parsing, no logging.
        // See the LowLevelHooksTimeout note in Install.
        if (nCode >= 0 && _omarchyActive)
        {
            try
            {
                var info = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
                // Our own injected key is skipped so the guard cannot loop.
                if ((info.flags & LlkhfInjected) == 0)
                {
                    var message = (int)wParam;
                    var isWinKey = info.vkCode == VkLwin || info.vkCode == VkRwin;
                    var isDown = message == WmKeydown || message == WmSyskeydown;
                    var isUp = message == WmKeyup || message == WmSyskeyup;

                    if (isDown)
                    {
                        if (isWinKey)
                        {
                            _winDown = true;
                        }
                    }
                    else if (isUp && isWinKey && _winDown)
                    {
                        // EVERY Windows key release is masked, not just the
                        // ones that looked like a bare tap. The earlier
                        // version only masked a release with no other key
                        // seen in between, which is unknowable from here:
                        // GlazeWM runs its own low-level hook and SWALLOWS
                        // the keys it binds, so on lwin+space, lwin+1 and
                        // lwin+2 this hook saw the second key while Windows
                        // never did. That left Windows watching a Win press
                        // and a Win release with nothing between them, which
                        // is precisely its rule for opening Start, so every
                        // GlazeWM binding opened the Start menu (FLAG-50).
                        //
                        // Masking unconditionally is safe because Windows
                        // acts on a Win combo at the SECOND key's down
                        // (Win+E opens Explorer as E goes down); nothing but
                        // the bare-tap Start trigger keys off the release.
                        _winDown = false;
                        if (ReplayMaskedWinUp(info.vkCode))
                        {
                            // Swallow the real up: the replay above already
                            // queued the mask and a fresh up behind it.
                            _maskedTaps = _maskedTaps + 1;
                            return (IntPtr)1;
                        }
                    }
                    else if (isUp && isWinKey)
                    {
                        _winDown = false;
                    }
                }
            }
            catch
            {
                // A hook callback must never throw into the system; on any
                // trouble the key passes through untouched.
            }
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    // Built once and reused. The callback runs inside the system's input
    // path under a deadline, so it allocates nothing: a three element array
    // per keystroke is garbage the collector would eventually have to stop
    // and sweep, and a collection landing inside the callback is one of the
    // few things that can push it past LowLevelHooksTimeout. Only the last
    // entry's key code ever changes, and only the hook thread touches it.
    private static readonly Input[] ReplayBuffer = BuildReplayBuffer();
    private static readonly int InputSize = Marshal.SizeOf<Input>();

    private static Input[] BuildReplayBuffer()
    {
        // vkE8 down, vkE8 up, then the Windows key up. 0xE8 is unassigned in
        // the winuser.h virtual key table, so nothing can act on it; its only
        // job is to sit between the down and the up.
        var inputs = new Input[3];
        inputs[0].type = 1; // INPUT_KEYBOARD
        inputs[0].u.ki.wVk = VkUnassigned;
        inputs[1].type = 1;
        inputs[1].u.ki.wVk = VkUnassigned;
        inputs[1].u.ki.dwFlags = 2; // KEYEVENTF_KEYUP
        inputs[2].type = 1;
        inputs[2].u.ki.dwFlags = 2; // KEYEVENTF_KEYUP
        return inputs;
    }

    private static bool ReplayMaskedWinUp(uint winVkCode)
    {
        ReplayBuffer[2].u.ki.wVk = (ushort)winVkCode;
        // Only report success when the whole sequence was accepted. A partial
        // or failed send must leave the real up alone, or the Windows key
        // would be left logically held down with no way back.
        return SendInput(3, ReplayBuffer, InputSize) == 3;
    }
}
