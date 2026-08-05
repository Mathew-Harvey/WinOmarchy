// The wallpaper fast path.
//
// bin/lib/common.ps1 owns the wallpaper rules and stays the definition every
// other caller uses. These are the same rules again in C#, and they exist for
// one reason: the wallpaper is the only Winmarchy action that fires on a
// timer, on a menu click and on a keybinding, and each one used to start
// powershell.exe, parse a 2600 line library and exit again to do a few
// milliseconds of work. On a weak machine that spawn is most of a second of
// CPU every time, for the life of the session.
//
// The duplication is deliberate and bounded. Only the picking rules live
// here; anything that mutates recorded state, writes the undo journal or
// repairs stays in PowerShell. Tests pin the two implementations against each
// other, and a failure here falls back to the dispatcher, so this can never
// be the reason the wallpaper stopped changing.

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

namespace Winmarchy.Chooser;

public enum WallpaperOutcome
{
    // The wallpaper changed.
    Changed,
    // Nothing to do, and nothing wrong: cycling is off, the folder has gone
    // away, or it holds no pictures. The PowerShell prints a sentence and
    // stops here too, so there is nothing to fall back to.
    NothingToDo,
    // Something failed. The caller runs the dispatcher instead, which does
    // the same job the slow way and reports properly.
    Failed,
}

public static class Wallpaper
{
    // SPI_SETDESKWALLPAPER = 0x0014, with fWinIni SPIF_UPDATEINIFILE (0x1)
    // and SPIF_SENDWININICHANGE (0x2): the same call and the same flags
    // Set-WinmarchyWallpaper makes.
    // learn.microsoft.com/windows/win32/api/winuser/nf-winuser-systemparametersinfow
    private const int SpiSetDeskWallpaper = 0x0014;
    private const int SpifUpdateAndNotify = 0x0003;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfoW(int uiAction, int uiParam, string pvParam, int fWinIni);

    // The formats the SPI_SETDESKWALLPAPER path accepts on Windows 11, the
    // same set Get-WinmarchyWallpaperCandidates matches.
    private static readonly string[] PictureExtensions = { ".jpg", ".jpeg", ".png", ".bmp" };

    private static readonly Random Picker = new Random();

    public static WallpaperOutcome Next()
    {
        var state = WinmarchyState.Load();
        if (string.IsNullOrEmpty(state.WallpaperDir))
        {
            // Cycling is off, which is the default and not worth a line.
            return WallpaperOutcome.NothingToDo;
        }
        if (!Directory.Exists(state.WallpaperDir))
        {
            // The same sentence Get-WinmarchyWallpaperFolder logs: an
            // unplugged drive or a renamed folder should be findable in the
            // log rather than looking like a dead keybinding.
            Paths.Log("wallpaper: folder " + state.WallpaperDir + " is not reachable; cycling paused");
            return WallpaperOutcome.NothingToDo;
        }
        try
        {
            var candidates = Candidates(state.WallpaperDir);
            if (candidates.Count == 0)
            {
                Paths.Log("wallpaper: no pictures (jpg, jpeg, png, bmp) under " + state.WallpaperDir);
                return WallpaperOutcome.NothingToDo;
            }
            var next = Pick(candidates, CurrentWallpaper());
            if (next == null)
            {
                return WallpaperOutcome.NothingToDo;
            }
            if (!SystemParametersInfoW(SpiSetDeskWallpaper, 0, next, SpifUpdateAndNotify))
            {
                Paths.Log("wallpaper: SystemParametersInfo failed for " + next
                    + " (error " + Marshal.GetLastWin32Error() + "); handing over to the dispatcher");
                return WallpaperOutcome.Failed;
            }
            Paths.Log("wallpaper: " + Path.GetFileName(next) + " (in process, no shell started)");
            return WallpaperOutcome.Changed;
        }
        catch (Exception ex)
        {
            Paths.Log("wallpaper: fast path failed (" + ex.Message + "); handing over to the dispatcher");
            return WallpaperOutcome.Failed;
        }
    }

    // Every usable picture under the folder, subfolders included, hidden
    // entries skipped and an unreadable folder skipping itself: the same
    // walk, in the same order of checks, as Get-WinmarchyWallpaperCandidates.
    public static List<string> Candidates(string folder)
    {
        var pictures = new List<string>();
        var pending = new Stack<string>();
        pending.Push(folder);
        while (pending.Count > 0)
        {
            var dir = pending.Pop();
            try
            {
                foreach (var entry in new DirectoryInfo(dir).GetFileSystemInfos())
                {
                    if ((entry.Attributes & FileAttributes.Hidden) != 0)
                    {
                        continue;
                    }
                    if (entry is DirectoryInfo child)
                    {
                        pending.Push(child.FullName);
                    }
                    else if (Array.IndexOf(PictureExtensions, entry.Extension.ToLowerInvariant()) >= 0)
                    {
                        pictures.Add(entry.FullName);
                    }
                }
            }
            catch
            {
                // A folder that cannot be read skips itself, exactly as the
                // PowerShell's -ErrorAction SilentlyContinue does.
            }
        }
        return pictures;
    }

    // Picks at random, avoiding the current picture whenever there is a
    // choice, so "next" always visibly changes something. Case insensitive
    // like the PowerShell comparison it mirrors, because Windows paths are.
    public static string? Pick(IReadOnlyList<string> candidates, string current)
    {
        if (candidates.Count == 0)
        {
            return null;
        }
        if (candidates.Count == 1)
        {
            return candidates[0];
        }
        var pool = new List<string>();
        foreach (var candidate in candidates)
        {
            if (!string.Equals(candidate, current, StringComparison.OrdinalIgnoreCase))
            {
                pool.Add(candidate);
            }
        }
        if (pool.Count == 0)
        {
            return candidates[Picker.Next(candidates.Count)];
        }
        return pool[Picker.Next(pool.Count)];
    }

    private static string CurrentWallpaper()
    {
        // The same value Get-WinmarchyCurrentWallpaper reads.
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop");
            return key?.GetValue("WallPaper") as string ?? string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }
}
