// Bringing every window back before Omarchy mode ends.
//
// GlazeWM hides the windows of inactive workspaces by cloaking them. Nothing
// reliably uncloaks them on the way out: the watchdog process restores
// windows only when the WM died UNEXPECTEDLY
// (ref/glazewm/packages/wm-watcher/src/main.rs logs "Skipping watcher
// cleanup" on a clean exit), and the WM's own exit path runs shutdown
// commands and flushes events without touching window visibility
// (ref/glazewm/packages/wm/src/wm.rs, cleanup). So a swap back to Windows 11
// could leave everything on workspaces 2 to 9 invisible, with no taskbar
// button and no way to reach it (FLAGS.md FLAG-61).
//
// The obvious fix, uncloaking the windows ourselves, is not available: GlazeWM
// does it through an UNDOCUMENTED shell COM interface whose vtable it matches
// by hand (platform_impl/windows/com.rs), which rule 8 forbids writing from
// memory, and copying that layout out of a GPL-3.0 project into this MIT one
// is not on either. So this asks GlazeWM to do the moving, using the two
// commands the shipped keybindings already use: "focus --workspace <name>"
// and "move --workspace <name>".

using System;
using System.Collections.Generic;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace Winmarchy.Chooser;

public static class GlazewmConsolidate
{
    // Generous enough for a real desktop, bounded so a miscount cannot spin.
    private const int MaxMovesPerWorkspace = 40;
    private const int SettleMilliseconds = 60;

    public static int Run()
    {
        try
        {
            var moved = RunAsync().GetAwaiter().GetResult();
            Paths.Log("consolidate: brought " + moved + " window(s) back to the visible workspace");
            return 0;
        }
        catch (Exception ex)
        {
            // Never fatal: the swap must continue whatever happens here.
            Paths.Log("consolidate: could not gather the windows (" + ex.Message + "); the swap continues");
            return 0;
        }
    }

    private static async Task<int> RunAsync()
    {
        using var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri("ws://127.0.0.1:6123"), cancel.Token).ConfigureAwait(false);

        var workspaces = await QueryWorkspacesAsync(socket, cancel.Token).ConfigureAwait(false);
        if (workspaces.Count == 0)
        {
            return 0;
        }

        // Everything lands on the workspace that is on screen, so the user
        // sees their windows exactly where they were looking.
        var target = workspaces[0].Name;
        foreach (var workspace in workspaces)
        {
            if (workspace.HasFocus)
            {
                target = workspace.Name;
            }
        }

        var moved = 0;
        foreach (var workspace in workspaces)
        {
            if (workspace.Name == target || workspace.WindowCount == 0)
            {
                continue;
            }
            // A window can only be moved once it is the focused one, so the
            // workspace is brought up and then drained.
            await SendAsync(socket, "command focus --workspace " + workspace.Name, cancel.Token).ConfigureAwait(false);
            await Task.Delay(SettleMilliseconds, cancel.Token).ConfigureAwait(false);
            var toMove = Math.Min(workspace.WindowCount, MaxMovesPerWorkspace);
            for (var i = 0; i < toMove; i++)
            {
                await SendAsync(socket, "command move --workspace " + target, cancel.Token).ConfigureAwait(false);
                await Task.Delay(SettleMilliseconds, cancel.Token).ConfigureAwait(false);
                moved++;
            }
        }

        // Back to where the user was, so the swap does not also move them.
        await SendAsync(socket, "command focus --workspace " + target, cancel.Token).ConfigureAwait(false);
        await Task.Delay(SettleMilliseconds, cancel.Token).ConfigureAwait(false);
        return moved;
    }

    private static async Task<List<GlazewmWorkspace>> QueryWorkspacesAsync(ClientWebSocket socket, CancellationToken token)
    {
        await SendAsync(socket, "query monitors", token).ConfigureAwait(false);
        var buffer = new byte[16384];
        // The server also pushes events, so read until the reply to the query
        // itself arrives rather than trusting the first message.
        for (var attempt = 0; attempt < 10; attempt++)
        {
            var message = new StringBuilder();
            WebSocketReceiveResult result;
            do
            {
                result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), token).ConfigureAwait(false);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    return new List<GlazewmWorkspace>();
                }
                message.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
            }
            while (!result.EndOfMessage);

            var node = JsonNode.Parse(message.ToString());
            if (node?["clientMessage"]?.GetValue<string>() != "query monitors")
            {
                continue;
            }
            var monitors = node["data"]?["monitors"]?.AsArray();
            if (monitors == null)
            {
                return new List<GlazewmWorkspace>();
            }
            return ReadWorkspaces(monitors);
        }
        return new List<GlazewmWorkspace>();
    }

    private static List<GlazewmWorkspace> ReadWorkspaces(JsonArray monitors)
    {
        var workspaces = new List<GlazewmWorkspace>();
        foreach (var monitor in monitors)
        {
            var children = monitor?["children"]?.AsArray();
            if (children == null)
            {
                continue;
            }
            foreach (var child in children)
            {
                if (child?["type"]?.GetValue<string>() != "workspace")
                {
                    continue;
                }
                var name = child["name"]?.GetValue<string>() ?? string.Empty;
                workspaces.Add(new GlazewmWorkspace
                {
                    Name = name,
                    DisplayName = name,
                    HasFocus = child["hasFocus"]?.GetValue<bool>() ?? false,
                    IsDisplayed = child["isDisplayed"]?.GetValue<bool>() ?? false,
                    // Every descendant window, not just the direct children:
                    // a split container holds its own, and those are exactly
                    // the ones most at risk of being left behind.
                    WindowCount = CountWindows(child),
                });
            }
        }
        return workspaces;
    }

    private static int CountWindows(JsonNode container)
    {
        var children = container["children"]?.AsArray();
        if (children == null)
        {
            return 0;
        }
        var count = 0;
        foreach (var child in children)
        {
            if (child == null)
            {
                continue;
            }
            var type = child["type"]?.GetValue<string>();
            if (type == "window")
            {
                count++;
            }
            else if (type == "split")
            {
                count += CountWindows(child);
            }
        }
        return count;
    }

    private static async Task SendAsync(ClientWebSocket socket, string message, CancellationToken token)
    {
        var bytes = Encoding.UTF8.GetBytes(message);
        await socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, token)
            .ConfigureAwait(false);
    }
}
