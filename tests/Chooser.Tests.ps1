# Pester tests for the chooser's health checks and for the rule that came out
# of a real failure: the chooser must never be able to show nothing.
#
# The C# cannot be exercised headlessly on Linux, so the source-level
# assertions below stand in for it. They are deliberately about the shape of
# the failure handling, not about wording: every WebView2 failure path has to
# reach the plain chooser rather than closing the window.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    $script:chooserDir = Join-Path $script:repoRoot 'chooser'
    $script:savedHome = $env:WINMARCHY_HOME
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
}

Describe 'Chooser' {
    BeforeEach {
        $env:WINMARCHY_HOME = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
    }

Describe 'Payload check' {
    It 'reports both pieces missing on a machine with no chooser' {
        $payload = Test-WinmarchyChooserPayload
        $payload.Ok | Should -BeFalse
        $payload.Missing | Should -Contain 'Winmarchy.Chooser.exe'
        $payload.Missing | Should -Contain 'ui\index.html'
    }

    It 'reports the ui folder alone when the publish dropped it' {
        Write-WinmarchyTextFile -Path (Get-WinmarchyChooserExePath) -Content 'exe'
        $payload = Test-WinmarchyChooserPayload
        $payload.Ok | Should -BeFalse
        $payload.Missing | Should -Be @('ui\index.html')
    }

    It 'passes when the exe and the page are both there' {
        Write-WinmarchyTextFile -Path (Get-WinmarchyChooserExePath) -Content 'exe'
        Write-WinmarchyTextFile -Path (Join-Path (Join-Path (Get-WinmarchyChooserDir) 'ui') 'index.html') -Content '<html></html>'
        (Test-WinmarchyChooserPayload).Ok | Should -BeTrue
    }
}

Describe 'Launch' {
    It 'explains what is missing instead of starting a chooser that cannot draw' {
        Mock Test-WinmarchyIsWindows { $true }
        { Start-WinmarchyChooser } | Should -Throw '*Winmarchy.Chooser.exe*'
    }
}

Describe 'Never shows nothing' {
    It 'ships a plain chooser with no WebView2 in it' {
        $xaml = Join-Path $script:chooserDir 'FallbackWindow.xaml'
        $code = Join-Path $script:chooserDir 'FallbackWindow.xaml.cs'
        Test-Path $xaml | Should -BeTrue
        Test-Path $code | Should -BeTrue
        # The namespace, not the word: both files mention WebView2 in prose,
        # explaining why they exist.
        [System.IO.File]::ReadAllText($xaml) | Should -Not -Match 'Microsoft\.Web\.WebView2'
        [System.IO.File]::ReadAllText($code) | Should -Not -Match 'Microsoft\.Web\.WebView2'
    }

    It 'routes every WebView2 failure to the plain chooser' {
        $source = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'MainWindow.xaml.cs'))
        # Creation failure, navigation failure, renderer crash and the health
        # timeout: four ways for the rich chooser to fail, four hand-overs.
        ([regex]::Matches($source, 'HandOverToPlainChooser\(')).Count | Should -BeGreaterOrEqual 5
    }

    It 'falls back to the plain chooser when the WebView2 window cannot be built at all' {
        $source = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Program.cs'))
        $source | Should -Match 'new FallbackWindow'
        # OnLastWindowClose, because the rich chooser shows the plain one and
        # then closes itself; the default would take both down.
        $source | Should -Match 'ShutdownMode\.OnLastWindowClose'
    }

    It 'gives the login countdown 20 seconds, in both faces' {
        # 5 seconds auto-continued to the last mode before the user had taken
        # their hand off the keyboard, which read as "no chooser appeared at
        # login". Input still cancels it instantly.
        $main = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'MainWindow.xaml.cs'))
        $main | Should -Match '\["countdownSeconds"\]\s*=\s*20'
        $plain = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'FallbackWindow.xaml.cs'))
        $plain | Should -Match '_secondsLeft\s*=\s*20'
    }

    It 'logs a countdown expiry differently from a click' {
        # Both used to log "user chose", which made the auto-continue at
        # login indistinguishable from a real choice in the log.
        $appJs = [System.IO.File]::ReadAllText((Join-Path (Join-Path $script:chooserDir 'ui') 'app.js'))
        $appJs | Should -Match "auto:\s*auto\s*===\s*true"
        $main = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'MainWindow.xaml.cs'))
        $main | Should -Match 'countdown expired'
        $plain = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'FallbackWindow.xaml.cs'))
        $plain | Should -Match 'countdown expired'
    }

    It 'hosts the tray with no console when asked' {
        $program = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Program.cs'))
        $program | Should -Match 'TrayApplet\.Run\(\)'
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $applet | Should -Match 'NotifyIcon'
    }

    It 'guards the Windows key only while Omarchy mode is on, and dies with the tray' {
        # The guard is a low-level keyboard hook in the tray host: a bare
        # Windows key tap must not open the Start menu in Omarchy mode, and
        # killing the tray must return the key to stock instantly.
        $guard = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'WinKeyGuard.cs'))
        $guard | Should -Match 'WH_KEYBOARD_LL|WhKeyboardLl'
        $guard | Should -Match 'omarchy'
        $guard | Should -Match 'SendInput'
        # The defects earlier versions shipped, each pinned so it cannot
        # return: a text sniff of the state file that never matched 5.1's
        # two-space JSON; file reads INSIDE the hook callback, which can blow
        # the LowLevelHooksTimeout and get the hook silently removed; and a
        # mask injected on the down or the up, neither of which can land
        # BETWEEN them, because SendInput only ever appends to the queue.
        $guard | Should -Match 'WinmarchyState\.Load\(\)'
        $guard | Should -Not -Match 'ReadAllText\(Paths\.StateFile\)'
        $guard | Should -Match 'volatile bool _omarchyActive'
        $callback = ($guard -split 'private static IntPtr Callback')[1]
        $callback | Should -Not -Match 'WinmarchyState'
        $callback | Should -Not -Match 'Paths\.Log'
        # The bare up is swallowed and the whole sequence replayed, which is
        # the only ordering that puts the mask between the down and the up.
        $guard | Should -Match 'ReplayMaskedWinUp'
        $callback | Should -Match 'return \(IntPtr\)1;'
    }

    It 'masks every Windows key release, not only the ones that looked bare' {
        # The bug this pins: GlazeWM runs its own low-level hook and swallows
        # the keys it binds, so on lwin+space, lwin+1 and lwin+2 this hook saw
        # the second key while Windows never did. Windows then saw a press and
        # a release with nothing between them, which is its rule for opening
        # Start, and every GlazeWM binding opened the Start menu. Whether a
        # downstream hook ate a key is unknowable from inside a hook, so the
        # release is masked unconditionally (FLAGS.md FLAG-50).
        $guard = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'WinKeyGuard.cs'))
        $guard | Should -Not -Match '_otherKeySeen' -Because 'a hook cannot tell whether Windows saw the other key'
        $guard | Should -Not -Match 'bareTap'
        $callback = ($guard -split 'private static IntPtr Callback')[1]
        # The release path calls the replay with no combo condition in front
        # of it.
        $callback | Should -Match 'if \(ReplayMaskedWinUp\(info\.vkCode\)\)'
    }

    It 'runs the hook on a thread of its own, where nothing can queue in front of it' {
        # A WH_KEYBOARD_LL callback is delivered on the thread that installed
        # the hook. That used to be the tray's UI thread, shared with the
        # notification icon, its menu, the wallpaper timer and a heartbeat
        # file write every single second: any of those running long made every
        # keystroke in the system wait behind them, against a deadline whose
        # penalty is the hook being silently removed (FLAGS.md FLAG-54).
        $guard = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'WinKeyGuard.cs'))
        $guard | Should -Match 'new Thread\(HookThreadMain\)'
        $guard | Should -Match 'WinmarchyKeyGuard'
        # Bounded to that method: everything after it in the file is the
        # tray-thread work this one must stay clear of.
        $thread = (($guard -split 'private static void HookThreadMain')[1] -split 'public static void Uninstall')[0]
        $thread | Should -Match 'SetWindowsHookExW'
        $thread | Should -Match 'Application\.Run\(\)'
        # The maintenance tick on that thread must stay free of the I/O that
        # the tray's timer does, or the isolation is undone.
        $thread | Should -Not -Match 'WriteHeartbeat'
        $thread | Should -Not -Match 'WinmarchyState\.Load'
    }

    It 'allocates nothing on the keystroke path' {
        # A three element array per keystroke is garbage the collector would
        # eventually stop the world to sweep, and a collection landing inside
        # the callback is one of the few things that can overrun the deadline.
        $guard = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'WinKeyGuard.cs'))
        $replay = ($guard -split 'private static bool ReplayMaskedWinUp')[1]
        $replay | Should -Not -Match 'new Input\[3\]'
        $replay | Should -Match 'ReplayBuffer'
        $guard | Should -Match 'static readonly Input\[\] ReplayBuffer'
    }

    It 'replays a Windows key up for every one it swallows, so the key cannot stick' {
        $guard = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'WinKeyGuard.cs'))
        # Three events: mask down, mask up, and the Windows key up itself.
        # Built once now rather than per keystroke, so the shape is asserted
        # where it is built.
        $buffer = ($guard -split 'private static Input\[\] BuildReplayBuffer')[1]
        $buffer | Should -Match 'new Input\[3\]'
        $replay = ($guard -split 'private static bool ReplayMaskedWinUp\(uint winVkCode\)')[1]
        $replay | Should -Match 'winVkCode'
        # Swallowing is conditional on the replay being accepted in full.
        $replay | Should -Match 'SendInput\(3, ReplayBuffer, InputSize\) == 3'
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $applet | Should -Match 'WinKeyGuard\.Install\(\)'
        $applet | Should -Match 'WinKeyGuard\.Uninstall\(\)'
    }

    It 'cycles wallpapers from the tray on the configured interval, in both hosts' {
        # One-minute ticks with a counter, so a changed interval takes effect
        # within a minute rather than after the old interval runs out.
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        # The tick asks for the change in process now; the test above pins
        # that no shell is started for it.
        $applet | Should -Match 'WallpaperNextInBackground'
        $applet | Should -Match 'WallpaperIntervalMinutes'
        $applet | Should -Match '60 \* 1000'
        $script = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'bin' 'tray.ps1')))
        $script | Should -Match 'Get-WinmarchyWallpaperIntervalMinutes'
    }

    It 'changes the wallpaper in process, with no shell started anywhere on the path' {
        # The wallpaper is the only Winmarchy action that fires on a timer, a
        # click and a keybinding, and each one used to start powershell.exe
        # and parse a 2600 line library to do a few milliseconds of work.
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $applet | Should -Not -Match '"wallpaper next"' -Because 'the tray must not shell out for a job it can do itself'
        $applet | Should -Match 'WallpaperNextInBackground'
        $wallpaperCs = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Wallpaper.cs'))
        # SPI_SETDESKWALLPAPER with SPIF_UPDATEINIFILE plus SPIF_SENDWININICHANGE,
        # the same call Set-WinmarchyWallpaper makes.
        $wallpaperCs | Should -Match 'SystemParametersInfoW'
        $wallpaperCs | Should -Match '0x0014'
        $wallpaperCs | Should -Match '0x0003'
    }

    It 'agrees with the PowerShell on exactly which files count as pictures' {
        # A set comparison rather than a spot check, so adding a format to one
        # implementation and not the other fails here in either direction.
        $wallpaperCs = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Wallpaper.cs'))
        $commonPs = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1'))))

        $csList = [regex]::Match($wallpaperCs, 'PictureExtensions\s*=\s*\{([^}]*)\}').Groups[1].Value
        $csExtensions = @([regex]::Matches($csList, '"(\.[a-z]+)"') | ForEach-Object { $_.Groups[1].Value })
        $psList = [regex]::Match($commonPs, '\$extensions\s*=\s*@\(([^)]*)\)').Groups[1].Value
        $psExtensions = @([regex]::Matches($psList, "'(\.[a-z]+)'") | ForEach-Object { $_.Groups[1].Value })

        $csExtensions.Count | Should -BeGreaterThan 0
        $psExtensions.Count | Should -BeGreaterThan 0
        (($csExtensions | Sort-Object) -join ',') | Should -Be (($psExtensions | Sort-Object) -join ',')
    }

    It 'keeps the picking rules the PowerShell keeps: recurse, skip hidden, never repeat' {
        $wallpaperCs = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Wallpaper.cs'))
        $wallpaperCs | Should -Match 'Stack<string>' -Because 'the walk recurses through subfolders'
        $wallpaperCs | Should -Match 'FileAttributes\.Hidden'
        # Case insensitive, because the PowerShell comparison it mirrors is,
        # and Windows paths are.
        $wallpaperCs | Should -Match 'StringComparison\.OrdinalIgnoreCase'
    }

    It 'refuses the shortcut on a dirty journal, and falls back when it fails' {
        # Both rules matter more than the speed: a pending journal means an
        # interrupted swap, which every invocation must repair first (brief
        # Section 10), and a failed fast path has to reach the slow one
        # rather than silently doing nothing.
        $program = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Program.cs'))
        $fastPath = ($program -split 'public static int WallpaperNext\(\)')[1]
        $fastPath | Should -Match 'JournalPending'
        $fastPath | Should -Match 'WallpaperOutcome\.Failed'
        ([regex]::Matches($fastPath, 'RunWinmarchy\("wallpaper next"')).Count | Should -Be 2
    }

    It 'scans off the message loop, so a slow folder cannot freeze the icon or the guard' {
        # The tray icon, its menu and the Windows key guard's mode timer all
        # share this thread; the old route got that for free by spawning a
        # detached process.
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $background = ($applet -split 'private static void WallpaperNextInBackground')[1]
        $background | Should -Match 'Task\.Run'
        $background | Should -Match 'Program\.WallpaperNext\(\)'
    }

    It 'speaks the GlazeWM IPC protocol the reference clients speak' {
        # Every string here is verified in ref/, because a wrong one shows as
        # an empty workspace strip with nothing in any log: the port and the
        # message envelope from ref/glazewm/packages/wm-common/src/ipc.rs,
        # the two messages and the re-query-on-event behaviour from the
        # working client at
        # ref/yasb/src/core/widgets/services/glazewm/client.py.
        $ipc = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'GlazewmIpc.cs'))
        $ipc | Should -Match 'ws://127\.0\.0\.1:6123'
        $ipc | Should -Match 'sub -e workspace_activated workspace_deactivated workspace_updated focus_changed focused_container_moved'
        $ipc | Should -Match 'query monitors'
        $ipc | Should -Match 'event_subscription'
        $ipc | Should -Match 'client_response'
        $ipc | Should -Match 'command focus --workspace '
        # The fields the workspace strip reads off each container.
        foreach ($field in @('hasFocus', 'isDisplayed', 'displayName', 'workspace')) {
            $ipc | Should -Match $field
        }
    }

    It 'treats a missing GlazeWM as normal rather than as an error' {
        # In Windows 11 mode there is no GlazeWM at all, so a bar that logged
        # every failed connection would fill the log with noise about a
        # working machine.
        $ipc = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'GlazewmIpc.cs'))
        $ipc | Should -Match 'ReconnectMilliseconds'
        $ipc | Should -Not -Match 'Paths\.Log'
    }

    It 'reserves its strip as an app bar, the way yasb did' {
        # Without the app bar contract GlazeWM tiles behind the bar instead
        # of below it. Documented at
        # learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shappbarmessage
        $bar = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'BarWindow.cs'))
        $bar | Should -Match 'SHAppBarMessage'
        $bar | Should -Match 'AbmNew'
        $bar | Should -Match 'AbmQueryPos'
        $bar | Should -Match 'AbmSetPos'
        $bar | Should -Match 'AbmRemove'
        # Registered when the handle exists, and given back on close, or the
        # reserved strip outlives the bar and the desktop shrinks for good.
        $bar | Should -Match 'OnHandleCreated'
        $bar | Should -Match 'OnFormClosing'
    }

    It 'never steals focus from the window being worked in' {
        $bar = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'BarWindow.cs'))
        $bar | Should -Match 'ShowWithoutActivation'
        $bar | Should -Match 'MaNoActivate'
    }

    It 'keeps the bar height yasb reserved, so the tiled area does not move' {
        $bar = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'BarWindow.cs'))
        $barHeight = [regex]::Match($bar, 'BarHeight\s*=\s*(\d+)').Groups[1].Value
        $yasbConfig = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'yasb' 'config.yaml'))))
        $yasbHeight = [regex]::Match($yasbConfig, 'height:\s*(\d+)').Groups[1].Value
        $barHeight | Should -Be $yasbHeight
    }

    It 'draws its icons instead of typing them, so a missing font cannot empty the bar' {
        # The Nerd Font going missing has already cost this project once
        # (FLAGS.md FLAG-15); lines and arcs cannot render as boxes.
        $bar = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'BarWindow.cs'))
        $bar | Should -Match 'DrawMenuIcon'
        $bar | Should -Match 'DrawPowerIcon'
        $bar | Should -Match 'DrawVolumeIcon'
        # And it still asks for the themed font first, with the stock UI font
        # behind it.
        $bar | Should -Match 'JetBrainsMono Nerd Font'
        $bar | Should -Match 'Segoe UI'
    }

    It 'repaints only when something visible changed' {
        # This runs once a second for the whole session on a machine chosen
        # for being slow.
        $bar = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'BarWindow.cs'))
        $repaint = ($bar -split 'private void Repaint\(\)')[1]
        $repaint | Should -Match 'if \(signature == _signature\)'
        $repaint | Should -Match 'return;'
    }

    It 'runs as its own process, so a bar crash cannot take the key guard down' {
        $program = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Program.cs'))
        $program | Should -Match '"--bar"'
        $program | Should -Match 'BarApp\.Run\(\)'
        # The tray keeps the guard; the bar must not be started inside it.
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $applet | Should -Not -Match 'BarApp'
    }

    It 'wears the Winmarchy mark, in the exe and on the Start menu shortcuts' {
        $csproj = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Winmarchy.Chooser.csproj'))
        $csproj | Should -Match '<ApplicationIcon>winmarchy\.ico</ApplicationIcon>'
        $iconPath = Join-Path $script:chooserDir 'winmarchy.ico'
        Test-Path $iconPath | Should -BeTrue
        # A real icon file: the header is reserved 0, type 1, then the count
        # of images, and it must carry the small sizes Explorer and the
        # taskbar actually ask for.
        $bytes = [System.IO.File]::ReadAllBytes($iconPath)
        $bytes[0] | Should -Be 0
        $bytes[1] | Should -Be 0
        $bytes[2] | Should -Be 1
        $bytes[3] | Should -Be 0
        $imageCount = [int]$bytes[4] + ([int]$bytes[5] * 256)
        $imageCount | Should -BeGreaterThan 3
        $widths = @()
        for ($i = 0; $i -lt $imageCount; $i++) {
            $entry = 6 + (16 * $i)
            $width = [int]$bytes[$entry]
            if ($width -eq 0) { $width = 256 }
            $widths = $widths + $width
        }
        $widths | Should -Contain 16
        $widths | Should -Contain 32
        $widths | Should -Contain 256

        # The shortcuts run through powershell.exe, so without an explicit
        # icon they all wear the PowerShell one.
        $installText = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'install.ps1'))
        $installText | Should -Match 'IconLocation'
        $installText | Should -Match 'winmarchy\.ico'
    }

    It 'only re-parses the state file when a swap actually rewrote it' {
        # The tray runs for the whole session and its mode timer fires once
        # a second; parsing unchanged JSON every tick is pure idle cost on a
        # slow machine. The write-stamp shortcut lives in RefreshMode, and
        # the heartbeat must stay unconditional, before the shortcut, so
        # doctor can still tell a dead guard from an idle one.
        $guard = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'WinKeyGuard.cs'))
        $refresh = ($guard -split 'private static void RefreshMode')[1]
        $refresh | Should -Match 'GetLastWriteTimeUtc'
        $heartbeatIndex = $refresh.IndexOf('WriteHeartbeat()')
        $stampIndex = $refresh.IndexOf('GetLastWriteTimeUtc')
        $heartbeatIndex | Should -BeGreaterThan -1
        $stampIndex | Should -BeGreaterThan $heartbeatIndex
        # The parse itself is still a real JSON load when the stamp moved.
        $refresh | Should -Match 'WinmarchyState\.Load\(\)'
    }

    It 'can run on a newer .NET than it was built for' {
        # A net8.0 app with only a newer Desktop Runtime installed refuses to
        # start, and a WinExe failing that way is silent at login.
        $project = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Winmarchy.Chooser.csproj'))
        $project | Should -Match '<RollForward>LatestMajor</RollForward>'
    }

    It 'never leaves tiling paused, on any path out of a pause' {
        # The one rule the drag guard is built around: a window manager left
        # paused looks exactly like a broken one, and the user never asked
        # for it. Four ways out of a pause, and all four have to resume.
        $drag = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'DragGuard.cs'))
        # The button coming up.
        $tick = ($drag -split 'private static int Tick')[1]
        $tick = ($tick -split 'private static bool LandedOnAStrip')[0]
        $tick | Should -Match 'Resume\('
        # The cap on a single hold, so a stuck button cannot strand it.
        $tick | Should -Match 'MaxHoldSeconds'
        # An exception in the poll loop.
        $loop = ($drag -split 'private static void PollLoop')[1]
        $loop = ($loop -split 'private static int Tick')[0]
        $loop | Should -Match 'catch \(Exception'
        $loop | Should -Match 'Resume\('
        # The tray shutting down.
        $uninstall = ($drag -split 'public static void Uninstall')[1]
        $uninstall = ($uninstall -split 'private static void PollLoop')[0]
        $uninstall | Should -Match 'Resume\('
        # And the resume itself verifies rather than assuming, then says so
        # loudly enough to act on if it truly could not.
        $resume = ($drag -split 'private static void Resume')[1]
        $resume | Should -Match 'Link\.Paused'
        $resume | Should -Match 'Link\.RefreshPaused\(\)'
        $resume | Should -Match 'lwin\+p'
        # Two of those four paths can run at once, on different threads, and
        # a second resume for one pause would pause tiling again. Exactly one
        # caller gets to act.
        $resume | Should -Match 'Interlocked\.Exchange\(ref _pausedByUs, 0\)'
        # A pause the user made by hand is left exactly as found.
        $pause = ($drag -split 'private static void Pause')[1]
        $pause = ($pause -split 'private static void Resume')[0]
        $pause | Should -Match 'if \(Link\.Paused\)'
    }

    It 'leaves a drag that moves its window alone' {
        # The check that keeps this feature from being a net loss. While
        # paused GlazeWM does not track a moving window, so the unpause
        # redraw puts it back: pausing during a window drag would break
        # moving windows by mouse, floating ones worst of all. A tab
        # tear-off leaves its source window stationary and a window drag
        # does not, so the rectangle at the press has to still match.
        $drag = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'DragGuard.cs'))
        $tick = ($drag -split 'private static int Tick')[1]
        $tick = ($tick -split 'private static bool LandedOnAStrip')[0]
        $tick | Should -Match 'GetWindowRect\(_source, out current\)'
        $tick | Should -Match 'current\.Left != _sourceRect\.Left'
        # Failing the check abandons the press rather than pausing anyway.
        $tick | Should -Match '_candidate = false'
    }

    It 'watches the mouse without adding a second input hook' {
        # A WH_MOUSE_LL hook would be cheaper at idle and was rejected on
        # purpose: this process already carries one system-wide input hook,
        # a second is exactly the profile docs/defender.md is about, and it
        # would run against the same LowLevelHooksTimeout deadline that has
        # already cost this project two rounds of debugging.
        $drag = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'DragGuard.cs'))
        $drag | Should -Not -Match 'SetWindowsHookEx'
        $drag | Should -Match 'GetAsyncKeyState'
        # And it costs nothing at all in Windows 11 mode, where there is no
        # GlazeWM to pause.
        $drag | Should -Match 'DisconnectedPollMilliseconds'
        # The behaviour is named in the antivirus notes, not just the code.
        $defender = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'docs' 'defender.md')))
        $defender | Should -Match 'GetAsyncKeyState'
        $defender | Should -Match 'DragGuard\.cs'
    }

    It 'speaks the pause half of the GlazeWM protocol the reference server defines' {
        # Verified in ref/glazewm rather than guessed: the port and envelope
        # from packages/wm-common/src/ipc.rs, the event name from the
        # SubscribableEvent list in packages/wm-common/src/app_command.rs
        # (clap rename_all snake_case, so PauseChanged is pause_changed),
        # and wm-toggle-pause as the ONLY pause command in InvokeCommand,
        # which is why the state is subscribed to rather than assumed.
        $drag = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'DragGuard.cs'))
        $drag | Should -Match 'ws://127\.0\.0\.1:6123'
        $drag | Should -Match 'sub -e pause_changed'
        $drag | Should -Match 'query paused'
        $drag | Should -Match 'command wm-toggle-pause'
        $drag | Should -Match 'event_subscription'
        $drag | Should -Match 'client_response'
        # The event payload's own field names, camelCase per the WmEvent
        # serde attributes.
        $drag | Should -Match 'eventType'
        $drag | Should -Match 'isPaused'
    }

    It 'hangs the drag guard off the tray, so it dies with the icon' {
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $applet | Should -Match 'DragGuard\.Install\(\)'
        $applet | Should -Match 'DragGuard\.Uninstall\(\)'
        # The manual escape hatch stays bound, because it is the last resort
        # if the guard ever fails to resume.
        $config = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))))
        $config | Should -Match "commands: \['wm-toggle-pause'\]"
        $config | Should -Match "bindings: \['lwin\+p'\]"
    }
}
}
