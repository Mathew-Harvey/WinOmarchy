// The Winmarchy system menu, drawn natively.
//
// It used to be a terminal: lwin+escape started Alacritty, which started
// PowerShell, which ran fzf, to show a list of eighteen fixed items. Three
// processes and a visible wait every time. This is the same list in a window
// the already-running chooser executable opens, and it removes fzf from the
// set of programs Winmarchy needs at all.
//
// The split is deliberate and matches the tray's: this file owns only what
// the list LOOKS like. Every action stays in bin/menu.ps1, reached through
// "winmarchy menu-action <label>", so there is one implementation of what an
// entry does. A test asserts the two label lists cannot drift apart.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace Winmarchy.Chooser;

public static class MenuApp
{
    public static int Run()
    {
        try
        {
            Application.EnableVisualStyles();
            Application.Run(new MenuWindow());
            return 0;
        }
        catch (Exception ex)
        {
            Paths.Log("menu: failed to open: " + ex.Message);
            return 1;
        }
    }
}

public sealed class MenuWindow : Form
{
    private readonly TextBox _filter;
    private readonly ListBox _list;
    private readonly List<string> _entries;
    private readonly Font _font;
    private readonly Color _background;
    private readonly Color _foreground;
    private readonly Color _accent;
    private readonly Color _muted;

    // The same entries, in the same order, as Get-WinmarchySystemMenuEntries
    // in bin/menu.ps1. Tests pin the two lists together.
    public static List<string> BuildEntries(WinmarchyState state)
    {
        var swapLabel = state.Mode == "omarchy" ? "Swap to Windows 11 mode" : "Swap to Omarchy mode";
        var chooserLabel = state.ChooserDisabled
            ? "Chooser at login: off (toggle)"
            : "Chooser at login: on (toggle)";
        return new List<string>
        {
            "Theme menu",
            "Next theme",
            "Next wallpaper",
            "Keybindings",
            "Tutorial",
            "System stats (btop)",
            "Git TUI (lazygit)",
            "Files",
            swapLabel,
            "Reload GlazeWM",
            "Edit GlazeWM config",
            "Edit yasb config",
            chooserLabel,
            "Lock",
            "Sleep",
            "Restart",
            "Shutdown",
            "Sign out",
        };
    }

    public MenuWindow()
    {
        var state = WinmarchyState.Load();
        _entries = BuildEntries(state);

        var colours = Palette.Load(state.Theme);
        _background = Safe(colours, "background", Color.FromArgb(26, 27, 38));
        _foreground = Safe(colours, "foreground", Color.White);
        _accent = Safe(colours, "accent", Color.CornflowerBlue);
        _muted = Safe(colours, "muted", Color.Gray);
        _font = BuildFont();

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = _background;
        ClientSize = new Size(520, 420);
        KeyPreview = true;

        _filter = new TextBox
        {
            Dock = DockStyle.Top,
            BorderStyle = BorderStyle.None,
            BackColor = _background,
            ForeColor = _foreground,
            Font = new Font(_font.FontFamily, 12f),
            Margin = new Padding(12),
        };
        _filter.TextChanged += (_, _) => ApplyFilter();

        _list = new ListBox
        {
            Dock = DockStyle.Fill,
            BorderStyle = BorderStyle.None,
            BackColor = _background,
            ForeColor = _foreground,
            Font = _font,
            DrawMode = DrawMode.OwnerDrawFixed,
            ItemHeight = 26,
            IntegralHeight = false,
        };
        _list.DrawItem += OnDrawItem;
        _list.DoubleClick += (_, _) => RunSelection();

        // A little breathing room around both, without a layout panel.
        var padding = new Panel { Dock = DockStyle.Fill, Padding = new Padding(14, 10, 14, 12), BackColor = _background };
        padding.Controls.Add(_list);
        padding.Controls.Add(_filter);
        Controls.Add(padding);

        ApplyFilter();
    }

    private static Color Safe(Dictionary<string, string> colours, string key, Color fallback)
    {
        try
        {
            return ColorTranslator.FromHtml(colours[key]);
        }
        catch
        {
            return fallback;
        }
    }

    private static Font BuildFont()
    {
        try
        {
            var font = new Font("JetBrainsMono Nerd Font", 10.5f);
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
        return new Font("Segoe UI", 10.5f);
    }

    private void ApplyFilter()
    {
        // Plain case-insensitive substring matching, which is what a
        // seventeen item list needs; fzf's ranking would be ceremony here.
        var needle = _filter.Text.Trim();
        _list.BeginUpdate();
        _list.Items.Clear();
        foreach (var entry in _entries)
        {
            if (needle.Length == 0 || entry.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                _list.Items.Add(entry);
            }
        }
        if (_list.Items.Count > 0)
        {
            _list.SelectedIndex = 0;
        }
        _list.EndUpdate();
    }

    private void OnDrawItem(object? sender, DrawItemEventArgs e)
    {
        if (e.Index < 0)
        {
            return;
        }
        var text = (string)_list.Items[e.Index];
        var selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
        using var back = new SolidBrush(selected ? _accent : _background);
        e.Graphics.FillRectangle(back, e.Bounds);
        using var fore = new SolidBrush(selected ? _background : _foreground);
        e.Graphics.DrawString(text, _font, fore, e.Bounds.Left + 8, e.Bounds.Top + 4);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape)
        {
            Close();
            return;
        }
        if (e.KeyCode == Keys.Enter)
        {
            RunSelection();
            return;
        }
        // The arrows belong to the list even while the filter box has focus,
        // so the whole menu is usable without ever leaving the keyboard.
        if (e.KeyCode == Keys.Down || e.KeyCode == Keys.Up)
        {
            if (_list.Items.Count == 0)
            {
                return;
            }
            var next = _list.SelectedIndex + (e.KeyCode == Keys.Down ? 1 : -1);
            if (next < 0) { next = _list.Items.Count - 1; }
            if (next >= _list.Items.Count) { next = 0; }
            _list.SelectedIndex = next;
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }

    protected override void OnDeactivate(EventArgs e)
    {
        // Clicking away closes it, the way a launcher popup should.
        base.OnDeactivate(e);
        Close();
    }

    private void RunSelection()
    {
        if (_list.SelectedItem == null)
        {
            return;
        }
        var label = (string)_list.SelectedItem;
        // Close FIRST: several entries open a window of their own, and the
        // menu should already be gone by the time they do.
        Close();
        // The action lives in bin/menu.ps1. Quoted because labels carry
        // spaces and brackets.
        Program.RunWinmarchy("menu-action \"" + label + "\"", waitForExit: false);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _font?.Dispose();
        }
        base.Dispose(disposing);
    }
}
