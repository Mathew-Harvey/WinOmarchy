// The chooser's second face: a plain WPF window with no WebView2 anywhere in
// it. It exists because of the rule that the chooser must never be the reason
// the desktop looks broken. If WebView2 is missing, blocked, or fails to
// render, the old behaviour was to log a line and exit, which the user saw as
// "nothing happened at login". This window shows instead, so a failure of the
// pretty path degrades to the plain path rather than to silence.

using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
// The project enables WinForms (only for Screen.PrimaryScreen in MainWindow),
// so Brush and KeyEventArgs are ambiguous under implicit usings. These aliases
// pin both to WPF.
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;
using Key = System.Windows.Input.Key;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;

namespace Winmarchy.Chooser;

public partial class FallbackWindow : Window
{
    private readonly WinmarchyState _state;
    private readonly DispatcherTimer _countdown;
    // Matches the rich chooser's 20 second window; any input stops it.
    private int _secondsLeft = 20;
    private bool _countdownRunning = true;
    private bool _choiceMade;
    private bool _autoCommitted;
    private string _selected;

    private Brush _accentBrush = Brushes.SteelBlue;
    private Brush _borderBrush = Brushes.DimGray;

    public FallbackWindow(WinmarchyState state, string reason)
    {
        _state = state;
        _selected = state.LastMode == "omarchy" ? "omarchy" : "win11";
        InitializeComponent();

        ApplyPalette();
        ReasonText.Text = "The rich chooser could not start (" + reason
            + "), so this plain one is standing in. Everything below works the same. "
            + "Run \"winmarchy doctor\" for the details.";
        Paths.Log("chooser: showing the plain WPF chooser because " + reason);

        UpdateSelection();

        Win11Card.MouseLeftButtonUp += (_, _) => { _selected = "win11"; Commit(); };
        OmarchyCard.MouseLeftButtonUp += (_, _) => { _selected = "omarchy"; Commit(); };
        Win11Card.MouseEnter += (_, _) => { StopCountdown(); _selected = "win11"; UpdateSelection(); };
        OmarchyCard.MouseEnter += (_, _) => { StopCountdown(); _selected = "omarchy"; UpdateSelection(); };
        KeyDown += OnKeyDown;
        Loaded += (_, _) =>
        {
            Activate();
            Root.Focus();
        };

        _countdown = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _countdown.Tick += OnCountdownTick;
        _countdown.Start();
        UpdateCountdownText();
    }

    private void ApplyPalette()
    {
        var colours = Palette.Load(_state.Theme);
        _accentBrush = BrushFrom(colours, "accent");
        _borderBrush = BrushFrom(colours, "border");
        var background = BrushFrom(colours, "background");
        var card = BrushFrom(colours, "darker_background");
        var surface = BrushFrom(colours, "lighter_background");
        var foreground = BrushFrom(colours, "foreground");
        var bright = BrushFrom(colours, "bright_foreground");
        var muted = BrushFrom(colours, "muted");

        Background = background;
        TitleText.Foreground = bright;
        SubtitleText.Foreground = muted;
        CountdownText.Foreground = muted;
        DontAskBox.Foreground = muted;
        ReasonText.Foreground = muted;

        Win11Card.Background = card;
        OmarchyCard.Background = card;
        Win11Title.Foreground = foreground;
        OmarchyTitle.Foreground = foreground;
        Win11Body.Foreground = muted;
        OmarchyBody.Foreground = muted;
        Win11Taskbar.Background = card;
        OmarchyBar.Background = card;
        OmarchyTileFocused.BorderBrush = _accentBrush;
        OmarchyTileFocused.Background = background;
        OmarchyTileB.Background = background;
        OmarchyTileC.Background = background;
        OmarchyTileB.BorderBrush = _borderBrush;
        OmarchyTileC.BorderBrush = _borderBrush;

        Win11Preview.Background = surface;
        OmarchyPreview.Background = surface;
    }

    private static Brush BrushFrom(Dictionary<string, string> colours, string key)
    {
        try
        {
            var converted = ColorConverter.ConvertFromString(colours[key]);
            if (converted is Color colour)
            {
                var brush = new SolidColorBrush(colour);
                brush.Freeze();
                return brush;
            }
        }
        catch (Exception ex)
        {
            Paths.Log("palette colour " + key + " unusable: " + ex.Message);
        }
        return Brushes.Gray;
    }

    private void UpdateSelection()
    {
        Win11Card.BorderBrush = _selected == "win11" ? _accentBrush : _borderBrush;
        OmarchyCard.BorderBrush = _selected == "omarchy" ? _accentBrush : _borderBrush;
        Win11Card.Opacity = _selected == "win11" ? 1.0 : 0.62;
        OmarchyCard.Opacity = _selected == "omarchy" ? 1.0 : 0.62;
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            _selected = "win11";
            Commit();
            return;
        }
        if (e.Key == Key.Enter || e.Key == Key.Space)
        {
            Commit();
            return;
        }
        if (e.Key == Key.Left || e.Key == Key.Right || e.Key == Key.Tab)
        {
            StopCountdown();
            _selected = _selected == "win11" ? "omarchy" : "win11";
            UpdateSelection();
            e.Handled = true;
            return;
        }
        StopCountdown();
    }

    private void OnCountdownTick(object? sender, EventArgs e)
    {
        _secondsLeft--;
        if (_secondsLeft <= 0)
        {
            _selected = _state.LastMode == "omarchy" ? "omarchy" : "win11";
            _autoCommitted = true;
            Commit();
            return;
        }
        UpdateCountdownText();
    }

    private void UpdateCountdownText()
    {
        if (!_countdownRunning)
        {
            CountdownText.Text = string.Empty;
            return;
        }
        var target = _state.LastMode == "omarchy" ? "Omarchy" : "Windows 11";
        CountdownText.Text = "Continuing to " + target + " in " + _secondsLeft + " seconds";
    }

    private void StopCountdown()
    {
        if (!_countdownRunning)
        {
            return;
        }
        _countdownRunning = false;
        _countdown.Stop();
        UpdateCountdownText();
    }

    private async void Commit()
    {
        if (_choiceMade)
        {
            return;
        }
        _choiceMade = true;
        _countdown.Stop();
        try
        {
            if (DontAskBox.IsChecked == true)
            {
                WinmarchyState.SetChooserDisabled(true);
            }
            if (_autoCommitted)
            {
                Paths.Log("chooser (plain): countdown expired with no input, continuing to " + _selected);
            }
            else
            {
                Paths.Log("chooser (plain): user chose " + _selected);
            }
            Topmost = false;
            CountdownText.Text = "Starting " + (_selected == "omarchy" ? "Omarchy" : "Windows 11") + "...";
            var exitCode = await System.Threading.Tasks.Task.Run(
                () => Program.RunWinmarchy("mode " + _selected, waitForExit: true));
            if (exitCode != 0)
            {
                Program.Fallback("mode " + _selected + " exited with " + exitCode);
            }
        }
        catch (Exception ex)
        {
            Program.Fallback("plain chooser commit failed: " + ex.Message);
        }
        Close();
    }
}
