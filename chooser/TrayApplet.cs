// The Winmarchy notification area icon, hosted in this WinExe.
//
// It lived in bin/tray.ps1 first, hosted by powershell.exe. That works, but on
// Windows 11 the default terminal is Windows Terminal, and Windows Terminal
// does not honour hidden-console requests the way classic conhost does
// (microsoft/terminal issues 12570 and 15311: ShowWindow(GetConsoleWindow(),
// SW_HIDE) no longer hides the window when Terminal is the host). The result
// was a terminal window sitting open for the whole session just to hold the
// tray icon. This executable is a WinExe: it has no console at all, so there
// is nothing to hide. tray.ps1 remains as the fallback for installs that
// skipped the chooser build, and both take the same named mutex so only one
// icon can ever exist.
//
// The menu deliberately mirrors Get-WinmarchyTrayMenuLabels in bin/tray.ps1;
// tests assert the two label sets cannot drift.

using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;
// System.Threading is only here for the mutex; the timer must be the
// WinForms one so its ticks run on the message loop thread.
using Timer = System.Windows.Forms.Timer;

namespace Winmarchy.Chooser;

public static class TrayApplet
{
    private static NotifyIcon? _icon;
    private static ContextMenuStrip? _menu;
    private static string _iconTheme = string.Empty;
    private static IntPtr _iconHandle = IntPtr.Zero;
    private static Timer? _wallpaperTimer;

    // Icon.FromHandle wraps the HICON without owning it, so the handle from
    // Bitmap.GetHicon must be destroyed by hand (documented behaviour).
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public static int Run()
    {
        // Same mutex name as bin/tray.ps1: whichever host starts first wins,
        // so an exe tray and a script tray can never both show an icon.
        using var mutex = new Mutex(true, @"Local\WinmarchyTray", out var createdNew);
        if (!createdNew)
        {
            Paths.Log("tray: already running, second copy exiting");
            return 0;
        }
        try
        {
            // Every entry point honours the undo journal (brief Section 10).
            if (Paths.JournalPending())
            {
                Program.RunWinmarchy("repair", waitForExit: true);
            }

            System.Windows.Forms.Application.EnableVisualStyles();
            _menu = new ContextMenuStrip();
            _menu.Opening += OnMenuOpening;
            _icon = new NotifyIcon
            {
                ContextMenuStrip = _menu,
                Text = "Winmarchy",
            };
            RefreshIcon(WinmarchyState.Load());
            _icon.Visible = true;
            // Windows opens a NotifyIcon's menu on right click only; a left
            // click that does nothing reads as broken.
            _icon.MouseUp += (_, e) =>
            {
                if (e.Button == MouseButtons.Left)
                {
                    _menu.Show(Control.MousePosition);
                }
            };
            // While Omarchy mode is on, a bare Windows key tap must not open
            // the Start menu; see WinKeyGuard.cs. Lives here because the
            // tray has the right lifetime: guard dies with the icon.
            WinKeyGuard.Install();

            // With a wallpaper folder configured, a fresh picture every half
            // hour, in either mode. The tick asks the dispatcher, which is a
            // quiet no-op when cycling is off, so the timer needs no state.
            _wallpaperTimer = new Timer { Interval = 30 * 60 * 1000 };
            _wallpaperTimer.Tick += (_, _) =>
            {
                var current = WinmarchyState.Load();
                if (!string.IsNullOrEmpty(current.WallpaperDir))
                {
                    Program.RunWinmarchy("wallpaper next", waitForExit: false);
                }
            };
            _wallpaperTimer.Start();

            Paths.Log("tray: icon shown (hosted by the chooser exe, no console)");
            System.Windows.Forms.Application.Run();
            return 0;
        }
        finally
        {
            WinKeyGuard.Uninstall();
            _wallpaperTimer?.Stop();
            if (_icon != null)
            {
                _icon.Visible = false;
                _icon.Dispose();
            }
            if (_iconHandle != IntPtr.Zero)
            {
                DestroyIcon(_iconHandle);
            }
            Paths.Log("tray: exited");
        }
    }

    private static void OnMenuOpening(object? sender, CancelEventArgs e)
    {
        if (_menu == null || _icon == null)
        {
            return;
        }
        var state = WinmarchyState.Load();
        var inOmarchy = state.Mode == "omarchy";
        var modeLabel = inOmarchy ? "Omarchy" : "Windows 11";
        var swapLabel = inOmarchy ? "Swap to Windows 11 mode" : "Swap to Omarchy mode";

        _menu.Items.Clear();
        var header = new ToolStripMenuItem("Winmarchy: " + modeLabel + " (" + state.Theme + ")")
        {
            Enabled = false,
        };
        _menu.Items.Add(header);
        _menu.Items.Add(new ToolStripSeparator());
        AddAction(swapLabel, () => RunDispatcherHidden(inOmarchy ? "mode win11" : "mode omarchy"));
        AddAction("Show the chooser", ShowChooser);
        _menu.Items.Add(new ToolStripSeparator());
        AddAction("Theme menu", () => RunDispatcherVisible("menu theme"));
        AddAction("Next theme", () => RunDispatcherHidden("theme next"));
        AddAction("Next wallpaper", () => RunDispatcherHidden("wallpaper next"));
        AddAction("Keybindings", () => RunDispatcherVisible("keys"));
        AddAction("Tutorial", () => RunDispatcherHidden("tutorial"));
        _menu.Items.Add(new ToolStripSeparator());
        AddAction("Restore Windows 11 (repair)", () => RunDispatcherHidden("mode win11 -Repair"));
        AddAction("Hide this icon", () =>
        {
            _icon.Visible = false;
            System.Windows.Forms.Application.Exit();
        });

        RefreshIcon(state);
        _icon.Text = "Winmarchy: " + modeLabel;
        e.Cancel = false;
    }

    private static void AddAction(string label, Action action)
    {
        var item = new ToolStripMenuItem(label);
        item.Click += (_, _) =>
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                Paths.Log("tray: " + label + " failed: " + ex.Message);
                MessageBox.Show(label + " failed: " + ex.Message, "Winmarchy");
            }
        };
        _menu!.Items.Add(item);
    }

    private static void RunDispatcherHidden(string arguments)
    {
        Paths.Log("tray: running " + arguments);
        // CreateNoWindow, not a hidden window: no console is ever allocated,
        // so Windows Terminal has nothing to take over.
        Program.RunWinmarchy(arguments, waitForExit: false);
    }

    private static void RunDispatcherVisible(string arguments)
    {
        // The menu and the keybinding overlay ARE console programs; they get
        // a real, visible terminal on purpose.
        Paths.Log("tray: running (visible) " + arguments);
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + Paths.DispatcherScript + "\" " + arguments,
            UseShellExecute = true,
        };
        Process.Start(psi);
    }

    private static void ShowChooser()
    {
        var exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe))
        {
            exe = Path.Combine(Paths.BaseDir, "Winmarchy.Chooser.exe");
        }
        Paths.Log("tray: launching the chooser");
        Process.Start(new ProcessStartInfo { FileName = exe, Arguments = "--show", UseShellExecute = true });
    }

    private static void RefreshIcon(WinmarchyState state)
    {
        // Repainted only when the theme changed: each paint mints an HICON
        // that has to be destroyed by hand.
        if (_icon == null || state.Theme == _iconTheme)
        {
            return;
        }
        try
        {
            var colours = Palette.Load(state.Theme);
            var background = ColorTranslator.FromHtml(colours["background"]);
            var accent = ColorTranslator.FromHtml(colours["accent"]);
            var muted = ColorTranslator.FromHtml(colours["muted"]);

            using var bitmap = new Bitmap(32, 32);
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                graphics.Clear(System.Drawing.Color.Transparent);
                using (var backBrush = new SolidBrush(background))
                {
                    graphics.FillRectangle(backBrush, 1, 1, 30, 30);
                }
                using (var edgePen = new Pen(muted, 2))
                {
                    graphics.DrawRectangle(edgePen, 1, 1, 29, 29);
                }
                using (var accentBrush = new SolidBrush(accent))
                {
                    // Left tile full height, two stacked on the right: the
                    // layout the window manager actually produces.
                    graphics.FillRectangle(accentBrush, 6, 6, 9, 20);
                    graphics.FillRectangle(accentBrush, 18, 6, 8, 9);
                    graphics.FillRectangle(accentBrush, 18, 17, 8, 9);
                }
            }
            var handle = bitmap.GetHicon();
            _icon.Icon = System.Drawing.Icon.FromHandle(handle);
            if (_iconHandle != IntPtr.Zero)
            {
                DestroyIcon(_iconHandle);
            }
            _iconHandle = handle;
            _iconTheme = state.Theme;
        }
        catch (Exception ex)
        {
            Paths.Log("tray: icon paint failed, using the system default: " + ex.Message);
            _icon.Icon = SystemIcons.Application;
            _iconTheme = state.Theme;
        }
    }
}
