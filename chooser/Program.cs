// Winmarchy chooser entry point.
// The chooser is an overlay, never a shell replacement: whatever happens
// here, Explorer is already running and the worst case is this process
// exiting. The fallback path (any unhandled exception or the 20 second
// health timeout) runs "winmarchy mode win11 -Repair" and exits 0 so the
// chooser can never be the reason the desktop is unreachable.

using System;
using System.Diagnostics;
using System.IO;
using System.Windows;

namespace Winmarchy.Chooser;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        bool renderTest = Array.IndexOf(args, "--render-test") >= 0;
        // --plain forces the WebView2-free chooser. Useful for checking that
        // the standby face renders on a machine where the rich one works.
        bool forcePlain = Array.IndexOf(args, "--plain") >= 0;
        // --show means a person asked for the chooser (tray, winmarchy
        // chooser), so the "do not ask at login" flag must not swallow it.
        bool forceShow = Array.IndexOf(args, "--show") >= 0;
        // --tray runs the notification area icon instead of the chooser.
        // Hosted here because this is a WinExe with no console for Windows
        // Terminal to keep open; see TrayApplet.cs for the why.
        if (Array.IndexOf(args, "--tray") >= 0)
        {
            return TrayApplet.Run();
        }
        Paths.Log("chooser: starting, base " + Paths.BaseDir);
        try
        {
            // Safety rule from the build brief Section 10: a non-empty undo
            // journal means an interrupted swap; repair before anything else.
            if (Paths.JournalPending())
            {
                RunWinmarchy("repair", waitForExit: true);
            }

            // The "don't ask at login" flag: honour it and go straight to the
            // last chosen mode without showing any UI.
            var state = WinmarchyState.Load();
            if (state.ChooserDisabled && !renderTest && !forcePlain && !forceShow)
            {
                Paths.Log("chooser: chooserDisabled is set, going straight to " + state.LastMode);
                if (state.LastMode == "omarchy")
                {
                    RunWinmarchy("mode omarchy", waitForExit: true);
                }
                return 0;
            }

            var app = new System.Windows.Application();
            // Explicit, because the rich chooser hands over to the plain one by
            // showing it and then closing itself: shutting down on the main
            // window closing would take the standby chooser with it.
            app.ShutdownMode = ShutdownMode.OnLastWindowClose;
            app.DispatcherUnhandledException += (_, e) =>
            {
                e.Handled = true;
                Fallback("dispatcher exception: " + e.Exception.Message);
                app.Shutdown(0);
            };

            Window window;
            if (forcePlain)
            {
                window = new FallbackWindow(state, "--plain was passed");
            }
            else
            {
                try
                {
                    window = new MainWindow(renderTest, state);
                }
                catch (Exception ex)
                {
                    // Typically a missing WebView2 assembly, which used to take
                    // the whole chooser down before it drew a single pixel.
                    Paths.Log("chooser: the WebView2 window could not be created: " + ex.Message);
                    if (renderTest)
                    {
                        throw;
                    }
                    window = new FallbackWindow(state, "WebView2 window creation failed: " + ex.Message);
                }
            }
            app.Run(window);
            return 0;
        }
        catch (Exception ex)
        {
            Fallback("unhandled exception: " + ex.Message);
            return 0;
        }
    }

    public static void Fallback(string reason)
    {
        try
        {
            Paths.Log("chooser fallback: " + reason);
            RunWinmarchy("mode win11 -Repair", waitForExit: true);
        }
        catch
        {
            // Nothing more can be done; Explorer is still the shell.
        }
    }

    public static int RunWinmarchy(string arguments, bool waitForExit)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + Paths.DispatcherScript + "\" " + arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        using var process = Process.Start(psi);
        if (process == null)
        {
            return -1;
        }
        if (waitForExit)
        {
            process.WaitForExit();
            return process.ExitCode;
        }
        return 0;
    }
}

// Path resolution for both layouts: deployed
// (%LOCALAPPDATA%\winmarchy\chooser\Winmarchy.Chooser.exe with bin/ and
// themes/ as siblings of chooser/) and a repo run (chooser build output,
// with the repo root a few levels up).
public static class Paths
{
    public static string BaseDir => AppContext.BaseDirectory;

    public static string RootDir
    {
        get
        {
            var dir = new DirectoryInfo(BaseDir);
            while (dir != null)
            {
                if (File.Exists(Path.Combine(dir.FullName, "bin", "winmarchy.ps1")))
                {
                    return dir.FullName;
                }
                dir = dir.Parent;
            }
            // Deployed default.
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(localAppData, "winmarchy");
        }
    }

    public static string DispatcherScript => Path.Combine(RootDir, "bin", "winmarchy.ps1");
    public static string ThemesDir => Path.Combine(RootDir, "themes");
    public static string UiDir => Path.Combine(BaseDir, "ui");

    public static string StateDir
    {
        get
        {
            var overrideHome = Environment.GetEnvironmentVariable("WINMARCHY_HOME");
            if (!string.IsNullOrEmpty(overrideHome))
            {
                return Path.Combine(overrideHome, "state");
            }
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(localAppData, "winmarchy", "state");
        }
    }

    public static string StateFile => Path.Combine(StateDir, "state.json");
    public static string ScreenshotFile => Path.Combine(StateDir, "chooser-screenshot.png");

    public static bool JournalPending()
    {
        var journal = Path.Combine(StateDir, "journal.jsonl");
        try
        {
            return File.Exists(journal) && new FileInfo(journal).Length > 0;
        }
        catch
        {
            return false;
        }
    }

    public static void Log(string message)
    {
        try
        {
            var logDir = Path.Combine(Directory.GetParent(StateDir)!.FullName, "log");
            Directory.CreateDirectory(logDir);
            var line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " [CHOOSER] " + message + Environment.NewLine;
            File.AppendAllText(Path.Combine(logDir, "winmarchy.log"), line);
        }
        catch
        {
            // Logging must never take the chooser down.
        }
    }
}

// Reads and writes %LOCALAPPDATA%\winmarchy\state\state.json through
// JsonNode so keys this app does not know about survive a round trip.
public sealed class WinmarchyState
{
    public string Mode = "win11";
    public string LastMode = "win11";
    public string Theme = "tokyo-night";
    public string WallpaperDir = "";
    public bool ChooserDisabled;

    public static WinmarchyState Load()
    {
        var state = new WinmarchyState();
        try
        {
            if (File.Exists(Paths.StateFile))
            {
                var node = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(Paths.StateFile));
                if (node != null)
                {
                    state.Mode = node["mode"]?.GetValue<string>() ?? state.Mode;
                    state.LastMode = node["lastMode"]?.GetValue<string>() ?? state.LastMode;
                    state.Theme = node["theme"]?.GetValue<string>() ?? state.Theme;
                    state.WallpaperDir = node["wallpaperDir"]?.GetValue<string>() ?? "";
                    state.ChooserDisabled = node["chooserDisabled"]?.GetValue<bool>() ?? false;
                }
            }
        }
        catch (Exception ex)
        {
            Paths.Log("state read failed, using defaults: " + ex.Message);
        }
        return state;
    }

    public static void SetChooserDisabled(bool value)
    {
        try
        {
            System.Text.Json.Nodes.JsonNode? node = null;
            if (File.Exists(Paths.StateFile))
            {
                node = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(Paths.StateFile));
            }
            node ??= new System.Text.Json.Nodes.JsonObject();
            node["chooserDisabled"] = value;
            Directory.CreateDirectory(Paths.StateDir);
            File.WriteAllText(Paths.StateFile, node.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex)
        {
            Paths.Log("state write failed: " + ex.Message);
        }
    }
}
