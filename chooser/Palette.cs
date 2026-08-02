// Palette loading for the chooser, shared by the WebView2 UI (which posts the
// colours to the page) and the plain WPF fallback chooser (which applies them
// to brushes directly). One loader so the two chooser faces can never drift.

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json.Nodes;

namespace Winmarchy.Chooser;

public static class Palette
{
    // The tokyo-night values from themes/tokyo-night.json, used only when the
    // theme file cannot be read at all. Having them here means the fallback
    // chooser is never unstyled.
    private static readonly Dictionary<string, string> Defaults = new()
    {
        ["background"] = "#1a1b26",
        ["darker_background"] = "#16161e",
        ["lighter_background"] = "#24283b",
        ["foreground"] = "#c0caf5",
        ["bright_foreground"] = "#ffffff",
        ["muted"] = "#565f89",
        ["accent"] = "#7aa2f7",
        ["border"] = "#414868",
        ["red"] = "#f7768e",
        ["green"] = "#9ece6a",
    };

    public static JsonObject? LoadJson(string themeName)
    {
        try
        {
            var themePath = Path.Combine(Paths.ThemesDir, themeName + ".json");
            if (!File.Exists(themePath))
            {
                Paths.Log("palette: no theme file at " + themePath);
                return null;
            }
            var theme = JsonNode.Parse(File.ReadAllText(themePath));
            return theme?["colors"]?.AsObject().DeepClone().AsObject();
        }
        catch (Exception ex)
        {
            Paths.Log("palette load failed (defaults will show): " + ex.Message);
            return null;
        }
    }

    // Flat name to hex map with every key guaranteed present, so callers can
    // index it without null checks.
    public static Dictionary<string, string> Load(string themeName)
    {
        var colours = new Dictionary<string, string>(Defaults);
        var json = LoadJson(themeName);
        if (json == null)
        {
            return colours;
        }
        foreach (var pair in json)
        {
            try
            {
                var value = pair.Value?.GetValue<string>();
                if (!string.IsNullOrEmpty(value))
                {
                    colours[pair.Key] = value!;
                }
            }
            catch
            {
                // A non-string colour entry is simply ignored.
            }
        }
        return colours;
    }
}
