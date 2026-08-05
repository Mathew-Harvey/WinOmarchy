// The Winmarchy bar: the native replacement for yasb.
//
// Why it exists: yasb is Python plus Qt6, which is roughly 150 to 250MB
// resident and the busiest background process Winmarchy ran, for a bar with
// eight widgets. This draws the same bar from the same palette in a WinForms
// window, in tens of megabytes.
//
// It runs as its own process (Winmarchy.Chooser.exe --bar) rather than inside
// the tray. That is deliberate: the tray hosts the Windows key guard, whose
// hook must never be taken down by an unrelated crash, and a bar talking to a
// WebSocket and painting on a timer is the likelier thing to fall over. It
// also means the mode manager starts and stops the bar exactly where it
// started and stopped yasb.
//
// The icons are drawn with GDI primitives rather than typed as glyphs. A bar
// whose icons are empty boxes because a Nerd Font did not install is a
// failure mode this project has already hit once in the yasb stylesheet
// (FLAGS.md FLAG-15), and lines and arcs cannot go missing.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Timer = System.Windows.Forms.Timer;

namespace Winmarchy.Chooser;

public static class BarApp
{
    public static int Run()
    {
        // One bar per session, the same guard the tray uses.
        using var mutex = new Mutex(true, @"Local\WinmarchyBar", out var createdNew);
        if (!createdNew)
        {
            Paths.Log("bar: already running, second copy exiting");
            return 0;
        }
        try
        {
            Application.EnableVisualStyles();
            var ipc = new GlazewmIpc();
            var bars = new List<BarWindow>();
            // One bar per screen, so a second monitor is not left bare. The
            // workspace strip is not filtered per monitor in this version;
            // see FLAGS.md.
            foreach (var screen in Screen.AllScreens)
            {
                var bar = new BarWindow(screen, ipc);
                bars.Add(bar);
                bar.Show();
            }
            if (bars.Count == 0)
            {
                Paths.Log("bar: no screens reported, nothing to show");
                return 0;
            }
            ipc.Start();
            Paths.Log("bar: shown on " + bars.Count + " screen(s)");
            Application.Run();
            foreach (var bar in bars)
            {
                bar.Dispose();
            }
            ipc.Dispose();
            return 0;
        }
        catch (Exception ex)
        {
            Paths.Log("bar: failed to start: " + ex.Message);
            return 1;
        }
    }
}

public sealed class BarWindow : Form
{
    // Matches the height the yasb config reserved, so nothing about the
    // tiled area changes when the bar is swapped over.
    private const int BarHeight = 36;
    private const int SidePadding = 10;
    private const int ItemGap = 14;

    private readonly Screen _screen;
    private readonly GlazewmIpc _ipc;
    private readonly Timer _timer;

    private List<GlazewmWorkspace> _workspaces = new List<GlazewmWorkspace>();
    private bool _connected;
    private string _title = string.Empty;
    private string _clock = string.Empty;
    private int _cpu;
    private int _memory;
    private int _ticks;
    private string _signature = string.Empty;

    private Dictionary<string, string> _colours;
    private string _theme = string.Empty;
    private DateTime _themeStamp = DateTime.MinValue;
    private Font _font;

    // Click targets recorded while painting, so hit testing never has to
    // recompute the layout.
    private readonly List<KeyValuePair<Rectangle, Action>> _hits = new List<KeyValuePair<Rectangle, Action>>();

    public BarWindow(Screen screen, GlazewmIpc ipc)
    {
        _screen = screen;
        _ipc = ipc;

        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(screen.Bounds.Left, screen.Bounds.Top, screen.Bounds.Width, BarHeight);
        // Every pixel is repainted from the palette, and double buffering
        // keeps the once-a-second repaint from flickering.
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);

        var state = WinmarchyState.Load();
        _theme = state.Theme;
        _colours = Palette.Load(_theme);
        _font = BuildFont();

        _ipc.WorkspacesChanged += OnWorkspacesChanged;
        _ipc.ConnectedChanged += OnConnectedChanged;

        _timer = new Timer { Interval = 1000 };
        _timer.Tick += (_, _) => Sample();
        _timer.Start();
        Sample();
    }

    private static Font BuildFont()
    {
        // The bar's own font, matching what the yasb stylesheet asked for,
        // with the stock UI font behind it when that is not installed.
        try
        {
            var font = new Font("JetBrainsMono Nerd Font", 9f, FontStyle.Regular, GraphicsUnit.Point);
            if (string.Equals(font.Name, "JetBrainsMono Nerd Font", StringComparison.OrdinalIgnoreCase))
            {
                return font;
            }
            font.Dispose();
        }
        catch
        {
            // Fall through to the stock font.
        }
        return new Font("Segoe UI", 9f, FontStyle.Regular, GraphicsUnit.Point);
    }

    // A bar must never take the focus away from the window the user is
    // working in, so it neither activates when shown nor when clicked.
    // learn.microsoft.com/dotnet/api/system.windows.forms.form.showwithoutactivation
    protected override bool ShowWithoutActivation => true;

    private const int WmMouseActivate = 0x0021;
    private const int MaNoActivate = 3;

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmMouseActivate)
        {
            // learn.microsoft.com/windows/win32/inputdev/wm-mouseactivate
            m.Result = (IntPtr)MaNoActivate;
            return;
        }
        base.WndProc(ref m);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        RegisterAppBar();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        RemoveAppBar();
        base.OnFormClosing(e);
    }

    private void OnWorkspacesChanged(List<GlazewmWorkspace> workspaces)
    {
        // Arrives on the IPC thread; everything below touches the window.
        try
        {
            if (IsDisposed || !IsHandleCreated)
            {
                return;
            }
            BeginInvoke(new Action(() =>
            {
                _workspaces = workspaces;
                Repaint();
            }));
        }
        catch
        {
            // A window torn down between the check and the call is not an
            // error worth reporting.
        }
    }

    private void OnConnectedChanged(bool connected)
    {
        try
        {
            if (IsDisposed || !IsHandleCreated)
            {
                return;
            }
            BeginInvoke(new Action(() =>
            {
                _connected = connected;
                if (!connected)
                {
                    _workspaces = new List<GlazewmWorkspace>();
                }
                Repaint();
            }));
        }
        catch
        {
            // As above.
        }
    }

    private void Sample()
    {
        _ticks++;
        _clock = DateTime.Now.ToString("ddd dd MMM HH:mm");
        // The same intervals the yasb config used: CPU every two seconds,
        // memory every five, because neither moves fast enough to be worth
        // more on a machine with little to spare.
        if (_ticks % 2 == 0)
        {
            _cpu = SystemStats.CpuPercent();
        }
        if (_ticks % 5 == 0)
        {
            _memory = SystemStats.MemoryPercent();
        }
        _title = ForegroundWindowTitle();
        ReloadThemeIfChanged();
        Repaint();
    }

    private void ReloadThemeIfChanged()
    {
        // The theme engine rewrites state.json when the palette changes, so
        // the bar recolours itself without a restart, the way yasb's
        // watch_stylesheet did. Only the write stamp is read each second.
        try
        {
            var stamp = System.IO.File.GetLastWriteTimeUtc(Paths.StateFile);
            if (stamp == _themeStamp)
            {
                return;
            }
            _themeStamp = stamp;
            var theme = WinmarchyState.Load().Theme;
            if (theme == _theme)
            {
                return;
            }
            _theme = theme;
            _colours = Palette.Load(theme);
            _signature = string.Empty;
        }
        catch
        {
            // Keep the colours already loaded.
        }
    }

    // Repaint only when something visible actually changed: this runs every
    // second for the life of the session.
    private void Repaint()
    {
        var signature = string.Join("|", new[]
        {
            _clock, _title, _cpu.ToString(), _memory.ToString(), _theme,
            _connected ? "on" : "off", WorkspaceSignature(),
        });
        if (signature == _signature)
        {
            return;
        }
        _signature = signature;
        Invalidate();
    }

    private string WorkspaceSignature()
    {
        var parts = new List<string>();
        foreach (var workspace in _workspaces)
        {
            parts.Add(workspace.DisplayName + (workspace.HasFocus ? "*" : string.Empty)
                + (workspace.WindowCount > 0 ? "+" : string.Empty));
        }
        return string.Join(",", parts);
    }

    private Color Colour(string key)
    {
        try
        {
            return ColorTranslator.FromHtml(_colours[key]);
        }
        catch
        {
            return Color.Gray;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var graphics = e.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        _hits.Clear();

        var background = Colour("background");
        var foreground = Colour("foreground");
        var muted = Colour("muted");
        var accent = Colour("accent");
        graphics.Clear(background);

        // Every brush this paint needs is made once and disposed with the
        // method. Allocating one inside a draw call leaks a GDI object per
        // repaint, which on a long session is exactly the kind of drip this
        // bar exists to avoid.
        using var foreBrush = new SolidBrush(foreground);
        using var mutedBrush = new SolidBrush(muted);
        using var accentBrush = new SolidBrush(accent);
        using var backgroundBrush = new SolidBrush(background);
        using var offlineBrush = new SolidBrush(Colour("red"));

        // Left: the menu button, the workspace strip, then the window title.
        var x = SidePadding;
        var menuRect = new Rectangle(x, 0, 22, Height);
        DrawMenuIcon(graphics, accentBrush, menuRect);
        _hits.Add(new KeyValuePair<Rectangle, Action>(menuRect, OpenMenu));
        x = menuRect.Right + ItemGap;

        foreach (var workspace in _workspaces)
        {
            var label = string.IsNullOrEmpty(workspace.DisplayName) ? workspace.Name : workspace.DisplayName;
            var size = graphics.MeasureString(label, _font);
            var width = (int)Math.Ceiling(size.Width) + 14;
            var rect = new Rectangle(x, 6, width, Height - 12);
            if (workspace.HasFocus)
            {
                graphics.FillRectangle(accentBrush, rect);
                DrawCentred(graphics, label, backgroundBrush, rect);
            }
            else
            {
                var populated = workspace.WindowCount > 0;
                using var edge = new Pen(populated ? muted : Colour("darker_background"), 1);
                graphics.DrawRectangle(edge, rect);
                DrawCentred(graphics, label, populated ? foreBrush : mutedBrush, rect);
            }
            var target = workspace.Name;
            _hits.Add(new KeyValuePair<Rectangle, Action>(rect, () => _ipc.FocusWorkspace(target)));
            x = rect.Right + 6;
        }

        // Right hand group, laid out from the right edge inwards.
        var right = Width - SidePadding;
        var powerRect = new Rectangle(right - 20, 0, 20, Height);
        DrawPowerIcon(graphics, new Pen(foreground, 1.6f), powerRect);
        _hits.Add(new KeyValuePair<Rectangle, Action>(powerRect, OpenPowerMenu));
        right = powerRect.Left - ItemGap;

        var volumeRect = new Rectangle(right - 20, 0, 20, Height);
        DrawVolumeIcon(graphics, foreBrush, new Pen(foreground, 1.4f), volumeRect);
        _hits.Add(new KeyValuePair<Rectangle, Action>(volumeRect, OpenVolumeMixer));
        right = volumeRect.Left - ItemGap;

        right = DrawRightText(graphics, "RAM " + _memory + "%", foreBrush, right);
        right = DrawRightText(graphics, "CPU " + _cpu + "%", foreBrush, right);

        // Centre: the clock, which owns the middle of the bar.
        var clockSize = graphics.MeasureString(_clock, _font);
        var clockRect = new Rectangle((int)((Width - clockSize.Width) / 2), 0, (int)Math.Ceiling(clockSize.Width), Height);
        DrawCentred(graphics, _clock, foreBrush, clockRect);

        // The title fills what is left between the workspaces and the
        // numbers, and is trimmed rather than allowed to collide with them.
        var titleWidth = clockRect.Left - ItemGap - x;
        if (titleWidth > 40)
        {
            var title = _connected ? _title : "GlazeWM offline";
            var titleRect = new Rectangle(x, 0, titleWidth, Height);
            using var format = new StringFormat
            {
                Trimming = StringTrimming.EllipsisCharacter,
                FormatFlags = StringFormatFlags.NoWrap,
                LineAlignment = StringAlignment.Center,
            };
            graphics.DrawString(title, _font, _connected ? mutedBrush : offlineBrush, titleRect, format);
        }
    }

    private int DrawRightText(Graphics graphics, string text, Brush brush, int right)
    {
        var size = graphics.MeasureString(text, _font);
        var width = (int)Math.Ceiling(size.Width);
        var rect = new Rectangle(right - width, 0, width, Height);
        DrawCentred(graphics, text, brush, rect);
        return rect.Left - ItemGap;
    }

    private void DrawCentred(Graphics graphics, string text, Brush brush, Rectangle rect)
    {
        using var format = new StringFormat
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center,
            FormatFlags = StringFormatFlags.NoWrap,
        };
        graphics.DrawString(text, _font, brush, rect, format);
    }

    private static void DrawMenuIcon(Graphics graphics, Brush brush, Rectangle rect)
    {
        // Three bars, the universal menu shape, drawn rather than typed.
        var width = 16;
        var left = rect.Left + (rect.Width - width) / 2;
        var top = rect.Top + rect.Height / 2 - 6;
        for (var i = 0; i < 3; i++)
        {
            graphics.FillRectangle(brush, left, top + i * 5, width, 2);
        }
    }

    private static void DrawPowerIcon(Graphics graphics, Pen pen, Rectangle rect)
    {
        using (pen)
        {
            var size = 12;
            var left = rect.Left + (rect.Width - size) / 2;
            var top = rect.Top + (rect.Height - size) / 2;
            // An arc open at the top with a stem through the gap.
            graphics.DrawArc(pen, left, top, size, size, -60, 300);
            graphics.DrawLine(pen, left + size / 2, top - 1, left + size / 2, top + size / 2 - 1);
        }
    }

    private static void DrawVolumeIcon(Graphics graphics, Brush brush, Pen pen, Rectangle rect)
    {
        using (pen)
        {
            var centreY = rect.Top + rect.Height / 2;
            var left = rect.Left + 3;
            // Speaker body plus cone.
            graphics.FillRectangle(brush, left, centreY - 3, 4, 6);
            graphics.FillPolygon(brush, new[]
            {
                new Point(left + 4, centreY - 3),
                new Point(left + 9, centreY - 7),
                new Point(left + 9, centreY + 7),
                new Point(left + 4, centreY + 3),
            });
            graphics.DrawArc(pen, left + 9, centreY - 5, 8, 10, -60, 120);
        }
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        foreach (var hit in _hits)
        {
            if (hit.Key.Contains(e.Location))
            {
                try
                {
                    hit.Value();
                }
                catch (Exception ex)
                {
                    Paths.Log("bar: click failed: " + ex.Message);
                }
                return;
            }
        }
        base.OnMouseClick(e);
    }

    private static void OpenMenu()
    {
        Program.RunWinmarchy("menu popup", waitForExit: false);
    }

    private static void OpenVolumeMixer()
    {
        // The live level is not read yet (FLAGS.md), so the button opens the
        // Windows volume mixer, whose URI is documented at
        // learn.microsoft.com/windows/apps/develop/launch/launch-settings-app
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "ms-settings:apps-volume",
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            Paths.Log("bar: could not open the volume mixer: " + ex.Message);
        }
    }

    private void OpenPowerMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Lock", null, (_, _) => Run("rundll32.exe", "user32.dll,LockWorkStation"));
        menu.Items.Add("Sleep", null, (_, _) => Run("rundll32.exe", "powrprof.dll,SetSuspendState 0,1,0"));
        menu.Items.Add("Sign out", null, (_, _) => Run("shutdown.exe", "/l"));
        menu.Items.Add("Restart", null, (_, _) => Run("shutdown.exe", "/r /t 0"));
        menu.Items.Add("Shut down", null, (_, _) => Run("shutdown.exe", "/s /t 0"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Back to Windows 11", null, (_, _) => Program.RunWinmarchy("mode win11", waitForExit: false));
        menu.Show(Control.MousePosition);
    }

    private static void Run(string fileName, string arguments)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
            });
        }
        catch (Exception ex)
        {
            Paths.Log("bar: " + fileName + " failed: " + ex.Message);
        }
    }

    // ---------------------------------------------------------------------
    // App bar registration, so the window manager tiles below the bar rather
    // than behind it. This is the same contract yasb's windows_app_bar
    // option fulfilled.
    // learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shappbarmessage
    // ---------------------------------------------------------------------

    private const uint AbmNew = 0x00000000;
    private const uint AbmRemove = 0x00000001;
    private const uint AbmQueryPos = 0x00000002;
    private const uint AbmSetPos = 0x00000003;
    private const uint AbeTop = 1;
    private static readonly uint AppBarCallback = RegisterWindowMessage("WinmarchyBarMessage");
    private bool _appBarRegistered;

    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public NativeRect rc;
        public IntPtr lParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [DllImport("shell32.dll", SetLastError = true)]
    private static extern IntPtr SHAppBarMessage(uint dwMessage, ref AppBarData pData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string lpString);

    private void RegisterAppBar()
    {
        try
        {
            var data = new AppBarData
            {
                cbSize = Marshal.SizeOf<AppBarData>(),
                hWnd = Handle,
                uCallbackMessage = AppBarCallback,
                uEdge = AbeTop,
            };
            if (SHAppBarMessage(AbmNew, ref data) == IntPtr.Zero)
            {
                Paths.Log("bar: the shell refused the app bar registration; windows may overlap the bar");
                return;
            }
            _appBarRegistered = true;

            // Ask for the full width of this screen at the top edge, let the
            // shell adjust the rectangle, then claim it.
            data.rc = new NativeRect
            {
                left = _screen.Bounds.Left,
                top = _screen.Bounds.Top,
                right = _screen.Bounds.Right,
                bottom = _screen.Bounds.Top + BarHeight,
            };
            SHAppBarMessage(AbmQueryPos, ref data);
            data.rc.bottom = data.rc.top + BarHeight;
            SHAppBarMessage(AbmSetPos, ref data);
            Bounds = new Rectangle(data.rc.left, data.rc.top, data.rc.right - data.rc.left, data.rc.bottom - data.rc.top);
        }
        catch (Exception ex)
        {
            Paths.Log("bar: app bar registration failed: " + ex.Message);
        }
    }

    private void RemoveAppBar()
    {
        if (!_appBarRegistered)
        {
            return;
        }
        try
        {
            var data = new AppBarData
            {
                cbSize = Marshal.SizeOf<AppBarData>(),
                hWnd = Handle,
            };
            SHAppBarMessage(AbmRemove, ref data);
            _appBarRegistered = false;
        }
        catch (Exception ex)
        {
            Paths.Log("bar: app bar removal failed: " + ex.Message);
        }
    }

    // ---------------------------------------------------------------------

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    private string ForegroundWindowTitle()
    {
        try
        {
            var handle = GetForegroundWindow();
            if (handle == IntPtr.Zero || handle == Handle)
            {
                return _title;
            }
            var builder = new System.Text.StringBuilder(256);
            var length = GetWindowTextW(handle, builder, builder.Capacity);
            if (length <= 0)
            {
                return string.Empty;
            }
            return builder.ToString();
        }
        catch
        {
            return string.Empty;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _ipc.WorkspacesChanged -= OnWorkspacesChanged;
            _ipc.ConnectedChanged -= OnConnectedChanged;
            _timer?.Stop();
            _timer?.Dispose();
            _font?.Dispose();
        }
        base.Dispose(disposing);
    }
}
