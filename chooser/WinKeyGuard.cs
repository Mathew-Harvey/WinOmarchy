// Stops a bare Windows key tap from opening the Start menu while Omarchy
// mode is on, so the key belongs entirely to the tiling layer, the way Super
// does on Omarchy itself. Combos are untouched: GlazeWM keeps every
// lwin+something binding, and in Windows 11 mode the key behaves exactly as
// stock.
//
// Mechanism: a low-level keyboard hook (SetWindowsHookExW, WH_KEYBOARD_LL,
// documented under learn.microsoft.com/windows/win32/api/winuser/) watches
// the Windows keys. When one goes down and comes back up with no other key
// in between, and the recorded mode is omarchy, a press of the unassigned
// virtual key 0xE8 (documented as unassigned in the winuser.h VK table) is
// injected via SendInput before the key-up passes through. The shell then
// sees Win+unassigned rather than a bare tap and does not open Start. This
// is the long-standing technique AutoHotkey users apply for the same
// problem; nothing is swallowed, so no key can ever stick.
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
    // Incremented by the hook, reported by the timer, so the log carries
    // evidence of the guard actually firing without the hook ever logging.
    private static int _maskedTaps;
    private static int _reportedTaps;

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
        _modeTimer = new Timer { Interval = 1000 };
        _modeTimer.Tick += (_, _) => RefreshMode();
        _modeTimer.Start();
        RefreshMode();

        // A module handle of zero is valid for WH_KEYBOARD_LL hooks in
        // managed code; the hook runs in this process's message loop.
        _hook = SetWindowsHookExW(WhKeyboardLl, Proc, IntPtr.Zero, 0);
        if (_hook == IntPtr.Zero)
        {
            Paths.Log("win key guard: hook failed to install (error " + Marshal.GetLastWin32Error() + "); the Windows key keeps its stock behaviour");
            return;
        }
        Paths.Log("win key guard: hook installed; arms and disarms with the mode");
    }

    public static void Uninstall()
    {
        _modeTimer?.Stop();
        if (_hook == IntPtr.Zero)
        {
            return;
        }
        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private static void RefreshMode()
    {
        bool active;
        try
        {
            // A real JSON parse, not a text sniff: the first version
            // searched the raw file for "mode": "omarchy" with one space,
            // and Windows PowerShell 5.1's ConvertTo-Json writes two spaces
            // after the colon, so the guard never armed on the real machine
            // (FLAG-36).
            active = WinmarchyState.Load().Mode == "omarchy";
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
            if (active && _hook != IntPtr.Zero)
            {
                // A fresh hook at the moment it matters: if anything removed
                // the old one along the way, arming re-establishes it.
                UnhookWindowsHookEx(_hook);
                _hook = SetWindowsHookExW(WhKeyboardLl, Proc, IntPtr.Zero, 0);
            }
        }
        var taps = _maskedTaps;
        if (taps != _reportedTaps)
        {
            _reportedTaps = taps;
            Paths.Log("win key guard: masked " + taps + " bare tap(s) so far this session");
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
                    // Inject on the DOWN, not the up. The shell opens Start
                    // when a Win key-up arrives with no other key seen since
                    // the down; an injection made during the up's own hook
                    // callback queues BEHIND that in-flight up and lands too
                    // late (the first version did exactly that; FLAG-36).
                    // Injected during the down, the unassigned key is seen
                    // while Win is held, the tap is cancelled up front, and
                    // every real combo still works because 0xE8 is bound to
                    // nothing.
                    if (isWinKey && (message == WmKeydown || message == WmSyskeydown))
                    {
                        InjectUnassignedKey();
                        _maskedTaps = _maskedTaps + 1;
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

    private static void InjectUnassignedKey()
    {
        var inputs = new Input[2];
        inputs[0].type = 1; // INPUT_KEYBOARD
        inputs[0].u.ki.wVk = VkUnassigned;
        inputs[1].type = 1;
        inputs[1].u.ki.wVk = VkUnassigned;
        inputs[1].u.ki.dwFlags = 2; // KEYEVENTF_KEYUP
        SendInput(2, inputs, Marshal.SizeOf<Input>());
    }
}
