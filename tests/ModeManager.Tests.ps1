# Pester tests for the Winmarchy mode manager (Phase 3).
# Every operating-system effector is mocked, so the state machine, journal
# discipline, rollback and repair paths run headlessly on any platform.

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    . (Join-Path $repoRoot (Join-Path 'bin' 'mode.ps1'))
    . (Join-Path $repoRoot (Join-Path 'bin' 'theme-set.ps1'))
    $script:repoRoot = $repoRoot
    $script:savedHome = $env:WINMARCHY_HOME
    $script:savedProfile = $env:WINMARCHY_USERPROFILE
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
    $env:WINMARCHY_USERPROFILE = $script:savedProfile
}

Describe 'Mode manager' {
    BeforeEach {
        # TestDrive persists across the tests inside a block, so every test
        # gets its own random subtree to stop state leaking between tests.
        $testRoot = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $env:WINMARCHY_HOME = Join-Path $testRoot 'home'
        $env:WINMARCHY_USERPROFILE = Join-Path $testRoot 'profile'
    }

Describe 'enter-omarchy' {
    BeforeEach {
        Mock Get-WinmarchyCurrentWallpaper { 'C:\Windows\Web\Wallpaper\Windows\img0.jpg' }
        Mock Get-WinmarchyAppsTheme { [pscustomobject]@{ AppsUseLightTheme = 1; SystemUsesLightTheme = 1 } }
        Mock Test-WinmarchyProcessRunning { $false }
        Mock Start-WinmarchyGlazewm { }
        Mock Start-WinmarchyYasb { }
        Mock Start-WinmarchyFlowLauncher { }
        Mock Get-WinmarchyTaskbarAutoHide { $false }
        Mock Set-WinmarchyTaskbarAutoHide { }
        Mock Get-WinmarchyDesktopIconsVisible { $true }
        Mock Set-WinmarchyDesktopIcons { }
        Mock Set-WinmarchyTheme { }
    }

    It 'captures baseline, journals, starts everything and commits on health' {
        Mock Wait-WinmarchyOmarchyHealthy { $true }

        Enter-WinmarchyOmarchyMode

        $state = Get-WinmarchyState
        $state.mode | Should -Be 'omarchy'
        $state.lastMode | Should -Be 'omarchy'
        $state.savedWallpaper | Should -Be 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
        $state.savedAppsUseLightTheme | Should -Be 1
        Test-WinmarchyJournalPending | Should -BeFalse

        Should -Invoke Start-WinmarchyGlazewm -Times 1 -Exactly
        Should -Invoke Start-WinmarchyYasb -Times 1 -Exactly
        Should -Invoke Start-WinmarchyFlowLauncher -Times 1 -Exactly
        Should -Invoke Set-WinmarchyTaskbarAutoHide -Times 1 -Exactly -ParameterFilter { $Enabled -eq $true }
        Should -Invoke Set-WinmarchyDesktopIcons -Times 1 -Exactly -ParameterFilter { $Visible -eq $false }
        # The theme must be applied with the Omarchy-only surfaces forced,
        # because state.mode still reads win11 until the commit.
        Should -Invoke Set-WinmarchyTheme -Times 1 -Exactly -ParameterFilter { [bool]$AsOmarchy }
    }

    It 'skips steps whose target state already holds' {
        Mock Wait-WinmarchyOmarchyHealthy { $true }
        Mock Test-WinmarchyProcessRunning { $true }
        Mock Get-WinmarchyTaskbarAutoHide { $true }
        Mock Get-WinmarchyDesktopIconsVisible { $false }

        Enter-WinmarchyOmarchyMode

        Should -Invoke Start-WinmarchyGlazewm -Times 0 -Exactly
        Should -Invoke Start-WinmarchyYasb -Times 0 -Exactly
        Should -Invoke Set-WinmarchyTaskbarAutoHide -Times 0 -Exactly
        Should -Invoke Set-WinmarchyDesktopIcons -Times 0 -Exactly
        (Get-WinmarchyState).mode | Should -Be 'omarchy'
    }

    It 'rolls back to win11 when the health check fails, leaving the journal for repair' {
        Mock Wait-WinmarchyOmarchyHealthy { $false }
        Mock Enter-WinmarchyWin11Mode { }

        Enter-WinmarchyOmarchyMode -ErrorAction SilentlyContinue

        Should -Invoke Enter-WinmarchyWin11Mode -Times 1 -Exactly
        (Get-WinmarchyState).mode | Should -Be 'win11'
        # The journal was written before the mutations; rollback is mocked, so
        # the entries must still be pending, proving journal-before-action.
        Test-WinmarchyJournalPending | Should -BeTrue
        $actions = @()
        foreach ($entry in @(Get-WinmarchyJournalEntries)) { $actions = $actions + $entry.action }
        $actions | Should -Contain 'glazewm-started'
        $actions | Should -Contain 'taskbar-autohide'
        $actions | Should -Contain 'icons-hidden'
    }

    It 'does not recapture the wallpaper when one is already saved' {
        Mock Wait-WinmarchyOmarchyHealthy { $true }
        Set-WinmarchyStateValue -Name 'savedWallpaper' -Value 'C:\already\saved.jpg'
        Set-WinmarchyStateValue -Name 'savedAppsUseLightTheme' -Value 0
        Set-WinmarchyStateValue -Name 'savedSystemUsesLightTheme' -Value 0

        Enter-WinmarchyOmarchyMode

        Should -Invoke Get-WinmarchyCurrentWallpaper -Times 0 -Exactly
        (Get-WinmarchyState).savedWallpaper | Should -Be 'C:\already\saved.jpg'
    }
}

Describe 'enter-win11' {
    BeforeEach {
        Mock Stop-WinmarchyGlazewm { }
        Mock Stop-WinmarchyYasb { }
        Mock Set-WinmarchyTaskbarAutoHide { }
        Mock Set-WinmarchyDesktopIcons { }
        Mock Set-WinmarchyWallpaper { }
        Mock Set-WinmarchyAppsTheme { }
    }

    It 'is a no-op when already in a clean win11 state' {
        Mock Test-WinmarchyProcessRunning { $false }
        Mock Get-WinmarchyTaskbarAutoHide { $false }
        Mock Get-WinmarchyDesktopIconsVisible { $true }

        Enter-WinmarchyWin11Mode

        Should -Invoke Stop-WinmarchyGlazewm -Times 0 -Exactly
        Should -Invoke Stop-WinmarchyYasb -Times 0 -Exactly
        Should -Invoke Set-WinmarchyTaskbarAutoHide -Times 0 -Exactly
        Should -Invoke Set-WinmarchyDesktopIcons -Times 0 -Exactly
        Should -Invoke Set-WinmarchyWallpaper -Times 0 -Exactly
        (Get-WinmarchyState).mode | Should -Be 'win11'
    }

    It 'tears down a full omarchy state and restores the captured baseline' {
        Mock Test-WinmarchyProcessRunning { $true }
        Mock Get-WinmarchyTaskbarAutoHide { $true }
        Mock Get-WinmarchyDesktopIconsVisible { $false }
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'
        Set-WinmarchyStateValue -Name 'savedWallpaper' -Value 'C:\orig\wall.jpg'
        Set-WinmarchyStateValue -Name 'savedAppsUseLightTheme' -Value 1
        Set-WinmarchyStateValue -Name 'savedSystemUsesLightTheme' -Value 1

        Enter-WinmarchyWin11Mode

        Should -Invoke Stop-WinmarchyGlazewm -Times 1 -Exactly
        Should -Invoke Stop-WinmarchyYasb -Times 1 -Exactly
        Should -Invoke Set-WinmarchyTaskbarAutoHide -Times 1 -Exactly -ParameterFilter { $Enabled -eq $false }
        Should -Invoke Set-WinmarchyDesktopIcons -Times 1 -Exactly -ParameterFilter { $Visible -eq $true }
        Should -Invoke Set-WinmarchyWallpaper -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\orig\wall.jpg' }
        Should -Invoke Set-WinmarchyAppsTheme -Times 1 -Exactly -ParameterFilter { $AppsUseLightTheme -eq 1 }
        (Get-WinmarchyState).mode | Should -Be 'win11'
        Test-WinmarchyJournalPending | Should -BeFalse
        # The captured baseline is cleared on restore so the next omarchy
        # entry recaptures the user's then-current settings.
        $null -eq (Get-WinmarchyState).savedWallpaper | Should -BeTrue
        $null -eq (Get-WinmarchyState).savedAppsUseLightTheme | Should -BeTrue
    }

    It 'restores Windows Terminal and Cursor on the way out' {
        Mock Test-WinmarchyProcessRunning { $true }
        Mock Get-WinmarchyTaskbarAutoHide { $true }
        Mock Get-WinmarchyDesktopIconsVisible { $false }
        Mock Get-WtSettingsPath { 'C:\fake\settings.json' }
        Mock Restore-WtSettingsFile { $true }
        Mock Get-WinmarchyCursorSettingsPath { 'C:\fake\cursor.json' }
        Mock Restore-CursorSettingsFile { $true }
        Mock Get-WinmarchyAlacrittyConfigPath { 'C:\fake\alacritty.toml' }
        Mock Restore-AlacrittyConfigFile { $true }
        Set-WinmarchyStateValue -Name 'savedWtColorScheme' -Value 'Campbell'
        Set-WinmarchyStateValue -Name 'savedWtFontFace' -Value 'Cascadia Mono'
        Set-WinmarchyStateValue -Name 'savedCursorHadColours' -Value $false

        Enter-WinmarchyWin11Mode

        Should -Invoke Restore-WtSettingsFile -Times 1 -Exactly -ParameterFilter { $OriginalColorScheme -eq 'Campbell' -and $OriginalFontFace -eq 'Cascadia Mono' }
        Should -Invoke Restore-CursorSettingsFile -Times 1 -Exactly
        Should -Invoke Restore-AlacrittyConfigFile -Times 1 -Exactly
    }

    It 'keeps the captured terminal baseline so the next swap can restore again' {
        Mock Get-WtSettingsPath { $null }
        Mock Get-WinmarchyCursorSettingsPath { $null }
        Mock Get-WinmarchyAlacrittyConfigPath { $null }
        Mock Test-WinmarchyProcessRunning { $false }
        Mock Get-WinmarchyTaskbarAutoHide { $false }
        Mock Get-WinmarchyDesktopIconsVisible { $true }
        Set-WinmarchyStateValue -Name 'savedWtColorScheme' -Value 'Campbell'
        Set-WinmarchyStateValue -Name 'savedWtCaptured' -Value $true

        Enter-WinmarchyWin11Mode

        # The wallpaper baseline is cleared (recaptured next time), but the
        # terminal baseline is the pre-Winmarchy truth and must survive.
        (Get-WinmarchyState).savedWtColorScheme | Should -Be 'Campbell'
        (Get-WinmarchyState).savedWtCaptured | Should -BeTrue
        $null -eq (Get-WinmarchyState).savedWallpaper | Should -BeTrue
    }

    It 'continues past a failing step and still restores the rest' {
        Mock Test-WinmarchyProcessRunning { $true }
        Mock Get-WinmarchyTaskbarAutoHide { $true }
        Mock Get-WinmarchyDesktopIconsVisible { $false }
        Mock Stop-WinmarchyGlazewm { throw 'glazewm refused to die' }
        Set-WinmarchyStateValue -Name 'savedWallpaper' -Value 'C:\orig\wall.jpg'

        Enter-WinmarchyWin11Mode -WarningVariable captured -WarningAction SilentlyContinue

        Should -Invoke Stop-WinmarchyYasb -Times 1 -Exactly
        Should -Invoke Set-WinmarchyTaskbarAutoHide -Times 1 -Exactly
        Should -Invoke Set-WinmarchyDesktopIcons -Times 1 -Exactly
        Should -Invoke Set-WinmarchyWallpaper -Times 1 -Exactly
        (Get-WinmarchyState).mode | Should -Be 'win11'
        @($captured).Count | Should -BeGreaterThan 0
    }
}

Describe 'repair' {
    BeforeEach {
        Mock Stop-WinmarchyGlazewm { }
        Mock Stop-WinmarchyYasb { }
        Mock Set-WinmarchyTaskbarAutoHide { }
        Mock Set-WinmarchyDesktopIcons { }
        Mock Set-WinmarchyWallpaper { }
        Mock Set-WinmarchyAppsTheme { }
        Mock Enter-WinmarchyWin11Mode { }
        Mock Enter-WinmarchyOmarchyMode { }
    }

    It 'replays pending journal entries in reverse with recorded previous values' {
        Add-WinmarchyJournalEntry -Action 'glazewm-started'
        Add-WinmarchyJournalEntry -Action 'taskbar-autohide' -Data @{ previous = $false }
        Add-WinmarchyJournalEntry -Action 'icons-hidden' -Data @{ previous = $true }

        Invoke-WinmarchyRepair

        Should -Invoke Stop-WinmarchyGlazewm -Times 1 -Exactly
        Should -Invoke Set-WinmarchyTaskbarAutoHide -Times 1 -Exactly -ParameterFilter { $Enabled -eq $false }
        Should -Invoke Set-WinmarchyDesktopIcons -Times 1 -Exactly -ParameterFilter { $Visible -eq $true }
        Test-WinmarchyJournalPending | Should -BeFalse
        Should -Invoke Enter-WinmarchyWin11Mode -Times 1 -Exactly
    }

    It 'survives unknown journal actions, torn lines and a failing undo' {
        Add-WinmarchyJournalEntry -Action 'some-future-action' -Data @{ previous = 'x' }
        Add-WinmarchyJournalEntry -Action 'taskbar-autohide' -Data @{ previous = $false }
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText((Get-WinmarchyJournalPath), '{"action":"torn', $encoding)
        Mock Set-WinmarchyTaskbarAutoHide { throw 'undo failed' }

        Invoke-WinmarchyRepair

        Test-WinmarchyJournalPending | Should -BeFalse
        Should -Invoke Enter-WinmarchyWin11Mode -Times 1 -Exactly
    }

    It 're-asserts omarchy when that is the recorded mode' {
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'

        Invoke-WinmarchyRepair

        Should -Invoke Enter-WinmarchyOmarchyMode -Times 1 -Exactly
        Should -Invoke Enter-WinmarchyWin11Mode -Times 0 -Exactly
    }
}

Describe 'theme application to real files' {
    BeforeEach {
        $profileDir = $env:WINMARCHY_USERPROFILE
        $glazeDir = Join-Path $profileDir (Join-Path '.glzr' 'glazewm')
        $null = New-Item -ItemType Directory -Path $glazeDir -Force
        Copy-Item (Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))) (Join-Path $glazeDir 'config.yaml')
        Mock Test-WinmarchyProcessRunning { $false }
        Mock Get-WtSettingsPath { $null }
        Mock Get-WinmarchyCursorSettingsPath { $null }
        Mock Get-WinmarchyAlacrittyConfigPath { $null }
        Mock Set-WinmarchyAppsTheme { }
        Mock Set-WinmarchyWallpaper { }
        Mock New-WinmarchyWallpaperImage { }
    }

    It 'in win11 mode touches only the Winmarchy configs, never Windows itself' {
        Set-WinmarchyTheme -Name 'gruvbox'

        # Winmarchy's own configuration is prepared, ready for next time.
        $stylesPath = Join-Path (Get-WinmarchyYasbConfigDir) 'styles.css'
        Test-Path $stylesPath | Should -BeTrue
        $styles = [System.IO.File]::ReadAllText($stylesPath)
        $styles.Contains('#7daea3') | Should -BeTrue
        $styles.Contains('{{') | Should -BeFalse

        $glazeText = [System.IO.File]::ReadAllText((Get-WinmarchyGlazewmConfigPath))
        $glazeText | Should -Match "color: '#7daea3' # winmarchy:focused-border"
        $glazeText | Should -Match "color: '#665c54' # winmarchy:other-border"

        (Get-WinmarchyState).theme | Should -Be 'gruvbox'

        # Nothing the user sees in Windows 11 mode is touched.
        Should -Invoke Set-WinmarchyWallpaper -Times 0 -Exactly
        Should -Invoke Set-WinmarchyAppsTheme -Times 0 -Exactly
    }

    It 'in omarchy mode also themes Cursor' {
        $cursorPath = Join-Path $env:WINMARCHY_USERPROFILE 'cursor-settings.json'
        [System.IO.File]::WriteAllText($cursorPath, '{ "editor.fontSize": 14 }', (New-Object System.Text.UTF8Encoding($false)))
        Mock Get-WinmarchyCursorSettingsPath { $cursorPath }
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'

        Set-WinmarchyTheme -Name 'gruvbox'

        $cursor = [System.IO.File]::ReadAllText($cursorPath) | ConvertFrom-Json
        $cursor.'workbench.colorCustomizations'.'editor.background' | Should -Be '#282828'
        # Unrelated Cursor settings survive.
        $cursor.'editor.fontSize' | Should -Be 14
        # The pre-Winmarchy state is captured for the restore.
        (Get-WinmarchyState).savedCursorHadColours | Should -BeFalse
        Should -Invoke Set-WinmarchyWallpaper -Times 1 -Exactly
    }

    It 'writes the Alacritty config in omarchy mode and removes it on the way out' {
        $alacrittyPath = Join-Path $env:WINMARCHY_USERPROFILE 'alacritty.toml'
        Mock Get-WinmarchyAlacrittyConfigPath { $alacrittyPath }
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'

        Set-WinmarchyTheme -Name 'gruvbox'

        Test-Path $alacrittyPath | Should -BeTrue
        $config = [System.IO.File]::ReadAllText($alacrittyPath)
        $config | Should -Match 'background = "#282828"'
        # Omarchy's mapping: ANSI black is the background, bright black muted.
        $config | Should -Match 'black = "#282828"'
        $config | Should -Match 'black = "#665c54"'
        $config.Contains('{{') | Should -BeFalse

        # No pre-existing config, so the restore removes ours entirely.
        (Restore-AlacrittyConfigFile -Path $alacrittyPath) | Should -BeTrue
        Test-Path $alacrittyPath | Should -BeFalse
    }

    It 'backs up and restores an Alacritty config the user already had' {
        $alacrittyPath = Join-Path $env:WINMARCHY_USERPROFILE 'alacritty-existing.toml'
        $original = "[window]`nopacity = 0.5`n"
        [System.IO.File]::WriteAllText($alacrittyPath, $original, (New-Object System.Text.UTF8Encoding($false)))

        $result = Update-AlacrittyConfigFile -Path $alacrittyPath -Theme (Get-WinmarchyTheme -Name 'nord')
        $result.BackupCreated | Should -BeTrue
        [System.IO.File]::ReadAllText($alacrittyPath) | Should -Match '#2e3440'

        (Restore-AlacrittyConfigFile -Path $alacrittyPath) | Should -BeTrue
        [System.IO.File]::ReadAllText($alacrittyPath) | Should -Be $original
    }

    It 'puts Cursor back exactly as it was on the way out' {
        $cursorPath = Join-Path $env:WINMARCHY_USERPROFILE 'cursor-roundtrip.json'
        $before = '{ "editor.fontSize": 14, "workbench.colorCustomizations": { "editor.background": "#ffffff" } }'
        [System.IO.File]::WriteAllText($cursorPath, $before, (New-Object System.Text.UTF8Encoding($false)))

        $patch = Update-CursorSettingsFile -Path $cursorPath -Theme (Get-WinmarchyTheme -Name 'nord')
        $patch.HadCustomisations | Should -BeTrue
        (([System.IO.File]::ReadAllText($cursorPath) | ConvertFrom-Json).'workbench.colorCustomizations'.'editor.background') | Should -Be '#2e3440'

        $null = Restore-CursorSettingsFile -Path $cursorPath -HadCustomisations $patch.HadCustomisations -OriginalColours $patch.OriginalColours

        $restored = [System.IO.File]::ReadAllText($cursorPath) | ConvertFrom-Json
        $restored.'workbench.colorCustomizations'.'editor.background' | Should -Be '#ffffff'
        $restored.'editor.fontSize' | Should -Be 14
    }

    It 'removes the colour block entirely when Cursor had none before' {
        $cursorPath = Join-Path $env:WINMARCHY_USERPROFILE 'cursor-fresh.json'
        [System.IO.File]::WriteAllText($cursorPath, '{ "editor.fontSize": 12 }', (New-Object System.Text.UTF8Encoding($false)))

        $patch = Update-CursorSettingsFile -Path $cursorPath -Theme (Get-WinmarchyTheme -Name 'nord')
        $patch.HadCustomisations | Should -BeFalse
        $null = Restore-CursorSettingsFile -Path $cursorPath -HadCustomisations $patch.HadCustomisations -OriginalColours $patch.OriginalColours

        $restored = [System.IO.File]::ReadAllText($cursorPath) | ConvertFrom-Json
        Test-PsObjectProperty $restored 'workbench.colorCustomizations' | Should -BeFalse
        $restored.'editor.fontSize' | Should -Be 12
    }

    It 'applies wallpaper and app mode only in omarchy mode' {
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'

        Set-WinmarchyTheme -Name 'rose-pine'

        Should -Invoke New-WinmarchyWallpaperImage -Times 1 -Exactly
        Should -Invoke Set-WinmarchyWallpaper -Times 1 -Exactly
        Should -Invoke Set-WinmarchyAppsTheme -Times 1 -Exactly -ParameterFilter { $AppsUseLightTheme -eq 1 }
    }

    It 'forces the omarchy surfaces with -AsOmarchy while state still reads win11' {
        (Get-WinmarchyState).mode | Should -Be 'win11'

        Set-WinmarchyTheme -Name 'tokyo-night' -AsOmarchy

        Should -Invoke Set-WinmarchyWallpaper -Times 1 -Exactly
        Should -Invoke Set-WinmarchyAppsTheme -Times 1 -Exactly -ParameterFilter { $AppsUseLightTheme -eq 0 }
    }

    It 'updates the borders for every theme and stays idempotent' {
        $original = [System.IO.File]::ReadAllText((Get-WinmarchyGlazewmConfigPath))
        foreach ($name in (Get-WinmarchyThemeNames)) {
            $theme = Get-WinmarchyTheme -Name $name
            $once = Update-WinmarchyGlazewmBorders -ConfigText $original -Theme $theme
            $twice = Update-WinmarchyGlazewmBorders -ConfigText $once -Theme $theme
            $twice | Should -Be $once
            $once | Should -Match ([regex]::Escape("color: '" + $theme.colors.accent + "' # winmarchy:focused-border"))
            $once | Should -Match ([regex]::Escape("color: '" + $theme.colors.muted + "' # winmarchy:other-border"))
        }
    }
}

Describe 'doctor' {
    BeforeEach {
        $profileDir = $env:WINMARCHY_USERPROFILE
        $glazeDir = Join-Path $profileDir (Join-Path '.glzr' 'glazewm')
        $null = New-Item -ItemType Directory -Path $glazeDir -Force
        Copy-Item (Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))) (Join-Path $glazeDir 'config.yaml')
        $yasbDir = Get-WinmarchyYasbConfigDir
        $null = New-Item -ItemType Directory -Path $yasbDir -Force
        Copy-Item (Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'yasb' 'config.yaml'))) (Join-Path $yasbDir 'config.yaml')
        Write-WinmarchyTextFile -Path (Join-Path $yasbDir 'styles.css') -Content '/* rendered */'
        Save-WinmarchyState -State (Get-WinmarchyDefaultState)

        # A chooser that is present and registered, so the health rows below
        # describe a working install unless a test breaks one on purpose.
        $script:fakeChooserExe = Join-Path (Get-WinmarchyChooserDir) 'Winmarchy.Chooser.exe'
        Write-WinmarchyTextFile -Path $script:fakeChooserExe -Content 'not really an exe'
        Write-WinmarchyTextFile -Path (Join-Path (Join-Path (Get-WinmarchyChooserDir) 'ui') 'index.html') -Content '<html></html>'

        Mock Find-WinmarchyExecutable { 'C:\fake\tool.exe' }
        Mock Test-WinmarchyProcessRunning { $false }
        Mock Get-WinmarchyTaskbarAutoHide { $false }
        Mock Get-WinmarchyDesktopIconsVisible { $true }
        Mock Get-WtSettingsPath { $null }
        Mock Test-WinmarchyWebView2Runtime { $true }
        Mock Test-WinmarchyStartupDisabledByWindows { $false }
        Mock Get-WinmarchyRunKeyValue { ('"' + $script:fakeChooserExe + '"') }
    }

    It 'emits a JSON health table whose only failure is the absent WT settings' {
        $json = Invoke-WinmarchyDoctor -Json
        $rows = @($json | ConvertFrom-Json)

        $rows.Count | Should -BeGreaterThan 12
        $failing = @()
        foreach ($row in $rows) {
            if (-not $row.pass) { $failing = $failing + $row.check }
        }
        $failing | Should -Be @('wt settings found')
    }

    It 'checks every link in the chain between install and a chooser at login' {
        $json = Invoke-WinmarchyDoctor -Json
        $checks = @(@($json | ConvertFrom-Json) | ForEach-Object { $_.check })
        foreach ($required in @('chooser installed', 'run key autostart', 'startup entry enabled', 'webview2 runtime', 'tray autostart')) {
            $checks | Should -Contain $required
        }
    }

    It 'fails the chooser row when the publish dropped the ui folder' {
        Remove-Item -Path (Join-Path (Get-WinmarchyChooserDir) 'ui') -Recurse -Force
        $rows = @(Invoke-WinmarchyDoctor -Json | ConvertFrom-Json)
        $row = $rows | Where-Object { $_.check -eq 'chooser installed' }
        $row.pass | Should -BeFalse
        $row.detail | Should -Match 'index.html'
    }

    It 'fails the run key row when it points at a file that is not there' {
        Mock Get-WinmarchyRunKeyValue { '"C:\nope\Winmarchy.Chooser.exe"' }
        $rows = @(Invoke-WinmarchyDoctor -Json | ConvertFrom-Json)
        $row = $rows | Where-Object { $_.check -eq 'run key autostart' }
        $row.pass | Should -BeFalse
        $row.detail | Should -Match 'does not exist'
    }

    It 'fails the startup row when Windows has the entry switched off' {
        Mock Test-WinmarchyStartupDisabledByWindows { $true }
        $rows = @(Invoke-WinmarchyDoctor -Json | ConvertFrom-Json)
        $row = $rows | Where-Object { $_.check -eq 'startup entry enabled' }
        $row.pass | Should -BeFalse
        $row.detail | Should -Match 'Startup'
    }
}
}
