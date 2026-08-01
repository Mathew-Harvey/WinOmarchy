// Winmarchy chooser window: borderless, fullscreen, topmost, hosting
// WebView2 with the split-screen UI. All UI logic lives in ui/app.js; this
// class captures the desktop screenshot, feeds the palette and last mode to
// the page, and acts on the page's choose/disable messages.

using System;
using System.Drawing.Imaging;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;

namespace Winmarchy.Chooser;

public partial class MainWindow : Window
{
    private readonly bool _renderTest;
    private readonly WinmarchyState _state;
    private readonly DispatcherTimer _healthTimer;
    private bool _healthy;
    private bool _choiceMade;

    public MainWindow(bool renderTest, WinmarchyState state)
    {
        _renderTest = renderTest;
        _state = state;
        InitializeComponent();

        if (_renderTest)
        {
            // Offscreen fixed-size render for the automated visual artefact.
            WindowStartupLocation = WindowStartupLocation.Manual;
            WindowState = WindowState.Normal;
            Left = -20000;
            Top = -20000;
            Width = 1600;
            Height = 900;
        }
        else
        {
            WindowState = WindowState.Maximized;
        }

        // Screenshot of the user's actual desktop, captured before the
        // window shows (Graphics.CopyFromScreen per the brief 7.1). Failure
        // is fine: the page falls back to a flat Win11-style panel.
        CaptureDesktopScreenshot();

        // 20 second health timeout: if WebView2 never renders, fall back.
        _healthTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(20) };
        _healthTimer.Tick += (_, _) =>
        {
            _healthTimer.Stop();
            if (!_healthy)
            {
                Program.Fallback("webview did not become healthy within 20 seconds");
                Close();
            }
        };
        _healthTimer.Start();

        Loaded += async (_, _) => await InitializeWebViewAsync();
    }

    private static void CaptureDesktopScreenshot()
    {
        try
        {
            var bounds = System.Windows.Forms.Screen.PrimaryScreen!.Bounds;
            using var bitmap = new System.Drawing.Bitmap(bounds.Width, bounds.Height);
            using var graphics = System.Drawing.Graphics.FromImage(bitmap);
            graphics.CopyFromScreen(bounds.X, bounds.Y, 0, 0, bitmap.Size);
            Directory.CreateDirectory(Paths.StateDir);
            bitmap.Save(Paths.ScreenshotFile, ImageFormat.Png);
        }
        catch (Exception ex)
        {
            Paths.Log("screenshot capture failed (CSS fallback panel will show): " + ex.Message);
        }
    }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            var dataDir = Path.Combine(Paths.StateDir, "webview-data");
            var environment = await CoreWebView2Environment.CreateAsync(null, dataDir);
            await WebView.EnsureCoreWebView2Async(environment);

            // Serve the ui folder and the state folder (for the screenshot)
            // over virtual hosts; documented WebView2 API
            // (CoreWebView2.SetVirtualHostNameToFolderMapping).
            WebView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                "winmarchy.ui", Paths.UiDir, CoreWebView2HostResourceAccessKind.Allow);
            WebView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                "winmarchy.state", Paths.StateDir, CoreWebView2HostResourceAccessKind.Allow);

            WebView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
            WebView.CoreWebView2.NavigationCompleted += OnNavigationCompleted;
            WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            WebView.CoreWebView2.Settings.IsZoomControlEnabled = false;

            WebView.Source = new Uri("https://winmarchy.ui/index.html");
        }
        catch (Exception ex)
        {
            Program.Fallback("webview initialisation failed: " + ex.Message);
            Close();
        }
    }

    private async void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        if (!e.IsSuccess)
        {
            Program.Fallback("webview navigation failed: " + e.WebErrorStatus);
            Close();
            return;
        }
        _healthy = true;
        _healthTimer.Stop();
        SendInitMessage();

        if (_renderTest)
        {
            // Give the page a moment to lay out, then write the artefact.
            await Task.Delay(1500);
            await WriteRenderTestArtefactAsync();
            Close();
        }
    }

    private void SendInitMessage()
    {
        var init = new JsonObject
        {
            ["type"] = "init",
            ["lastMode"] = _state.LastMode,
            ["theme"] = _state.Theme,
            ["renderTest"] = _renderTest,
            ["countdownSeconds"] = 5,
            ["screenshot"] = File.Exists(Paths.ScreenshotFile) ? "https://winmarchy.state/chooser-screenshot.png" : null,
            ["palette"] = LoadPalette(),
        };
        WebView.CoreWebView2.PostWebMessageAsJson(init.ToJsonString());
    }

    private JsonObject? LoadPalette()
    {
        try
        {
            var themePath = Path.Combine(Paths.ThemesDir, _state.Theme + ".json");
            if (!File.Exists(themePath))
            {
                return null;
            }
            var theme = JsonNode.Parse(File.ReadAllText(themePath));
            return theme?["colors"]?.AsObject().DeepClone().AsObject();
        }
        catch (Exception ex)
        {
            Paths.Log("palette load failed (page defaults will show): " + ex.Message);
            return null;
        }
    }

    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            var message = JsonNode.Parse(e.WebMessageAsJson);
            var type = message?["type"]?.GetValue<string>();
            if (type == "choose")
            {
                if (_choiceMade)
                {
                    return;
                }
                _choiceMade = true;
                var mode = message?["mode"]?.GetValue<string>() == "omarchy" ? "omarchy" : "win11";
                Paths.Log("chooser: user chose " + mode);
                Topmost = false;
                var exitCode = await Task.Run(() => Program.RunWinmarchy("mode " + mode, waitForExit: true));
                if (exitCode != 0)
                {
                    Program.Fallback("mode " + mode + " exited with " + exitCode);
                }
                Close();
            }
            else if (type == "chooserDisabled")
            {
                var value = message?["value"]?.GetValue<bool>() ?? false;
                WinmarchyState.SetChooserDisabled(value);
            }
        }
        catch (Exception ex)
        {
            Program.Fallback("web message handling failed: " + ex.Message);
            Close();
        }
    }

    private async Task WriteRenderTestArtefactAsync()
    {
        var artefactDir = Path.Combine(Paths.RootDir, "artifacts");
        Directory.CreateDirectory(artefactDir);
        var artefactPath = Path.Combine(artefactDir, "chooser.png");
        using var stream = File.Create(artefactPath);
        await WebView.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
        Paths.Log("render test artefact written to " + artefactPath);
    }
}
