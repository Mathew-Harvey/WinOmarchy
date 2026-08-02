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
using System.IO;
using System.Runtime.InteropServices;

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

    // The mode is re-read from state.json at most once a second, so a swap
    // takes effect on the next keystroke without a filesystem read per key.
    private static bool _omarchyActive;
    private static long _modeCheckedAtTick;

    public static void Install()
    {
        if (_hook != IntPtr.Zero)
        {
            return;
        }
        // A module handle of zero is valid for WH_KEYBOARD_LL hooks in
        // managed code; the hook runs in this process's message loop.
        _hook = SetWindowsHookExW(WhKeyboardLl, Proc, IntPtr.Zero, 0);
        if (_hook == IntPtr.Zero)
        {
            Paths.Log("win key guard: hook failed to install (error " + Marshal.GetLastWin32Error() + "); the Windows key keeps its stock behaviour");
            return;
        }
        Paths.Log("win key guard: active (a bare Windows key tap opens nothing while Omarchy mode is on)");
    }

    public static void Uninstall()
    {
        if (_hook == IntPtr.Zero)
        {
            return;
        }
        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private static bool OmarchyModeActive()
    {
        var now = Environment.TickCount64;
        if (now - _modeCheckedAtTick > 1000)
        {
            _modeCheckedAtTick = now;
            try
            {
                // A real JSON parse, not a text sniff. The first version
                // searched the raw file for the substring "mode": "omarchy"
                // with one space, and Windows PowerShell 5.1's ConvertTo-Json
                // writes TWO spaces after the colon, so the guard never armed
                // on the real machine while passing everywhere PowerShell 7
                // had written the file (FLAG-36).
                _omarchyActive = WinmarchyState.Load().Mode == "omarchy";
            }
            catch
            {
                _omarchyActive = false;
            }
        }
        return _omarchyActive;
    }

    private static IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
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
                    // callback is queued BEHIND that in-flight up and lands
                    // too late, so Start opened anyway (the first version did
                    // exactly that; FLAG-36). Injected during the down, the
                    // unassigned key is seen while Win is held, the tap is
                    // cancelled up front, and every real combo still works
                    // because 0xE8 is bound to nothing.
                    if (isWinKey && (message == WmKeydown || message == WmSyskeydown) && OmarchyModeActive())
                    {
                        InjectUnassignedKey();
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
