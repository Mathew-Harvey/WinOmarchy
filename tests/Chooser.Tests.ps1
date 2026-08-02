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
        # The two defects the first version shipped: a text sniff of the
        # state file that never matched 5.1's two-space JSON, and an
        # injection at key-up time that queued behind the in-flight up.
        $guard | Should -Match 'WinmarchyState\.Load\(\)'
        $guard | Should -Not -Match 'ReadAllText\(Paths\.StateFile\)'
        # Written with character classes so the 5.1 compat grep does not
        # mistake the C# operators inside this pattern for PowerShell ones.
        $guard | Should -Match ('WmKeydown [|]{2} message == WmSyskeydown\).{1,4}OmarchyModeActive')
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $applet | Should -Match 'WinKeyGuard\.Install\(\)'
        $applet | Should -Match 'WinKeyGuard\.Uninstall\(\)'
    }

    It 'cycles wallpapers from the tray on the configured interval, in both hosts' {
        # One-minute ticks with a counter, so a changed interval takes effect
        # within a minute rather than after the old interval runs out.
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'TrayApplet.cs'))
        $applet | Should -Match 'wallpaper next'
        $applet | Should -Match 'WallpaperIntervalMinutes'
        $applet | Should -Match '60 \* 1000'
        $script = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'bin' 'tray.ps1')))
        $script | Should -Match 'Get-WinmarchyWallpaperIntervalMinutes'
    }

    It 'can run on a newer .NET than it was built for' {
        # A net8.0 app with only a newer Desktop Runtime installed refuses to
        # start, and a WinExe failing that way is silent at login.
        $project = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Winmarchy.Chooser.csproj'))
        $project | Should -Match '<RollForward>LatestMajor</RollForward>'
    }
}
}
