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

    It 'replays a Windows key up for every one it swallows, so the key cannot stick' {
        $guard = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'WinKeyGuard.cs'))
        $replay = ($guard -split 'ReplayMaskedWinUp\(uint winVkCode\)')[1]
        # Three events: mask down, mask up, and the Windows key up itself.
        $replay | Should -Match 'new Input\[3\]'
        $replay | Should -Match 'winVkCode'
        # Swallowing is conditional on the replay being accepted in full.
        $replay | Should -Match 'SendInput\(3, inputs, Marshal\.SizeOf<Input>\(\)\) == 3'
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
}
}
