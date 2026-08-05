// The GlazeWM IPC client behind the bar's workspace buttons.
//
// Every part of this protocol is verified against two sources rather than
// guessed at, because a wrong message string here shows as an empty bar with
// nothing in any log:
//
//   - The server: ref/glazewm/packages/wm-common/src/ipc.rs gives
//     DEFAULT_IPC_PORT = 6123 and the ServerMessage shape (a "messageType"
//     tag, snake_case, of either "client_response" or "event_subscription",
//     with camelCase payload fields). ref/glazewm/packages/wm/src/ipc_server.rs
//     binds 127.0.0.1:6123 and accepts WebSocket clients (accept_async).
//   - A working client: ref/yasb/src/core/widgets/services/glazewm/client.py,
//     which sends exactly the two messages below on connect, treats any
//     event as "something moved, re-query", and reads monitors, their
//     workspace children and each workspace's name, displayName, hasFocus,
//     isDisplayed and children.
//
// The connection is expected to be absent much of the time: in Windows 11
// mode there is no GlazeWM at all, and during a swap it comes and goes. So a
// failure to connect is normal, never logged as an error, and simply retried.

using System;
using System.Collections.Generic;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace Winmarchy.Chooser;

public sealed class GlazewmWorkspace
{
    public string Name = string.Empty;
    public string DisplayName = string.Empty;
    public bool HasFocus;
    public bool IsDisplayed;
    public int WindowCount;
}

public sealed class GlazewmIpc : IDisposable
{
    // Verbatim from the yasb client's initial_messages, which is the set of
    // events that change what a workspace strip should show.
    private const string SubscribeMessage =
        "sub -e workspace_activated workspace_deactivated workspace_updated focus_changed focused_container_moved";
    private const string QueryMonitors = "query monitors";
    private const int ReconnectMilliseconds = 4000;

    private readonly Uri _uri = new Uri("ws://127.0.0.1:6123");
    private readonly CancellationTokenSource _cancel = new CancellationTokenSource();
    private ClientWebSocket? _socket;

    // Raised on a background thread; the bar marshals to its UI thread.
    public event Action<List<GlazewmWorkspace>>? WorkspacesChanged;
    public event Action<bool>? ConnectedChanged;

    public void Start()
    {
        Task.Run(() => RunAsync(_cancel.Token));
    }

    private async Task RunAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                using var socket = new ClientWebSocket();
                await socket.ConnectAsync(_uri, token).ConfigureAwait(false);
                _socket = socket;
                ConnectedChanged?.Invoke(true);
                await SendAsync(socket, SubscribeMessage, token).ConfigureAwait(false);
                await SendAsync(socket, QueryMonitors, token).ConfigureAwait(false);
                await ReadLoopAsync(socket, token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch
            {
                // No GlazeWM running is the normal case in Windows 11 mode,
                // so this is silent by design: the bar shows its offline
                // state and the loop tries again.
            }
            finally
            {
                _socket = null;
                ConnectedChanged?.Invoke(false);
            }
            try
            {
                await Task.Delay(ReconnectMilliseconds, token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    private async Task ReadLoopAsync(ClientWebSocket socket, CancellationToken token)
    {
        var buffer = new byte[8192];
        var message = new StringBuilder();
        while (socket.State == WebSocketState.Open && !token.IsCancellationRequested)
        {
            message.Clear();
            WebSocketReceiveResult result;
            do
            {
                result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), token).ConfigureAwait(false);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    return;
                }
                message.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
            }
            while (!result.EndOfMessage);
            HandleMessage(socket, message.ToString(), token);
        }
    }

    private void HandleMessage(ClientWebSocket socket, string json, CancellationToken token)
    {
        try
        {
            var node = JsonNode.Parse(json);
            if (node == null)
            {
                return;
            }
            var messageType = node["messageType"]?.GetValue<string>();
            if (messageType == "event_subscription")
            {
                // An event only says something moved. Re-query rather than
                // trying to apply the event, which is what the yasb client
                // does and keeps this client free of event-shape knowledge.
                _ = SendAsync(socket, QueryMonitors, token);
                return;
            }
            if (messageType != "client_response")
            {
                return;
            }
            if (node["clientMessage"]?.GetValue<string>() != QueryMonitors)
            {
                return;
            }
            var monitors = node["data"]?["monitors"]?.AsArray();
            if (monitors == null)
            {
                return;
            }
            WorkspacesChanged?.Invoke(ReadWorkspaces(monitors));
        }
        catch
        {
            // A message this client does not understand is not a reason to
            // drop the connection.
        }
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
                    DisplayName = child["displayName"]?.GetValue<string>() ?? name,
                    HasFocus = child["hasFocus"]?.GetValue<bool>() ?? false,
                    IsDisplayed = child["isDisplayed"]?.GetValue<bool>() ?? false,
                    WindowCount = child["children"]?.AsArray()?.Count ?? 0,
                });
            }
        }
        return workspaces;
    }

    // Clicking a workspace button. Fire and forget: the resulting state
    // change arrives back as an event, which re-queries.
    public void FocusWorkspace(string name)
    {
        var socket = _socket;
        if (socket == null || socket.State != WebSocketState.Open)
        {
            return;
        }
        _ = SendAsync(socket, "command focus --workspace " + name, _cancel.Token);
    }

    private static async Task SendAsync(ClientWebSocket socket, string message, CancellationToken token)
    {
        try
        {
            var bytes = Encoding.UTF8.GetBytes(message);
            await socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, token)
                .ConfigureAwait(false);
        }
        catch
        {
            // A send that fails means the connection has gone; the read loop
            // ends on its own and the outer loop reconnects.
        }
    }

    public void Dispose()
    {
        try
        {
            _cancel.Cancel();
            _cancel.Dispose();
        }
        catch
        {
            // Shutdown must never throw.
        }
    }
}
