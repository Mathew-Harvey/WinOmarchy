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
    $script:savedNvim = $env:WINMARCHY_NVIM_DIR
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
    $env:WINMARCHY_USERPROFILE = $script:savedProfile
    $env:WINMARCHY_NVIM_DIR = $script:savedNvim
}

Describe 'Mode manager' {
    BeforeEach {
        # TestDrive persists across the tests inside a block, so every test
        # gets its own random subtree to stop state leaking between tests.
        $testRoot = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $env:WINMARCHY_HOME = Join-Path $testRoot 'home'
        $env:WINMARCHY_USERPROFILE = Join-Path $testRoot 'profile'
        $env:WINMARCHY_NVIM_DIR = Join-Path $testRoot 'nvim'
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
        $null = New-Item -ItemType Directory -Path (Join-Path $env:WINMARCHY_NVIM_DIR (Join-Path 'lua' 'plugins')) -Force
        Mock Test-WinmarchyProcessRunning { $false }
        Mock Get-WtSettingsPath { $null }
        Mock Set-WinmarchyAppsTheme { }
        Mock Set-WinmarchyWallpaper { }
        Mock New-WinmarchyWallpaperImage { }
    }

    It 'renders yasb styles, patches glazewm borders, writes the nvim spec and records state' {
        Set-WinmarchyTheme -Name 'gruvbox'

        $stylesPath = Join-Path (Get-WinmarchyYasbConfigDir) 'styles.css'
        Test-Path $stylesPath | Should -BeTrue
        $styles = [System.IO.File]::ReadAllText($stylesPath)
        $styles.Contains('#7daea3') | Should -BeTrue
        $styles.Contains('{{') | Should -BeFalse

        $glazeText = [System.IO.File]::ReadAllText((Get-WinmarchyGlazewmConfigPath))
        $glazeText | Should -Match "color: '#7daea3' # winmarchy:focused-border"
        $glazeText | Should -Match "color: '#665c54' # winmarchy:other-border"

        $nvimSpec = Join-Path $env:WINMARCHY_NVIM_DIR (Join-Path 'lua' (Join-Path 'plugins' 'winmarchy-theme.lua'))
        Test-Path $nvimSpec | Should -BeTrue
        [System.IO.File]::ReadAllText($nvimSpec) | Should -Match 'gruvbox'

        (Get-WinmarchyState).theme | Should -Be 'gruvbox'
        # win11 mode: the user's wallpaper and app mode stay untouched.
        Should -Invoke Set-WinmarchyWallpaper -Times 0 -Exactly
        Should -Invoke Set-WinmarchyAppsTheme -Times 0 -Exactly
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
    It 'emits a JSON health table whose only failure is the absent WT settings' {
        $profileDir = $env:WINMARCHY_USERPROFILE
        $glazeDir = Join-Path $profileDir (Join-Path '.glzr' 'glazewm')
        $null = New-Item -ItemType Directory -Path $glazeDir -Force
        Copy-Item (Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))) (Join-Path $glazeDir 'config.yaml')
        $yasbDir = Get-WinmarchyYasbConfigDir
        $null = New-Item -ItemType Directory -Path $yasbDir -Force
        Copy-Item (Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'yasb' 'config.yaml'))) (Join-Path $yasbDir 'config.yaml')
        Write-WinmarchyTextFile -Path (Join-Path $yasbDir 'styles.css') -Content '/* rendered */'
        Save-WinmarchyState -State (Get-WinmarchyDefaultState)

        Mock Find-WinmarchyExecutable { 'C:\fake\tool.exe' }
        Mock Test-WinmarchyProcessRunning { $false }
        Mock Get-WinmarchyTaskbarAutoHide { $false }
        Mock Get-WinmarchyDesktopIconsVisible { $true }
        Mock Get-WtSettingsPath { $null }
        Mock Test-WinmarchyRunKeyPresent { $true }

        $json = Invoke-WinmarchyDoctor -Json
        $rows = @($json | ConvertFrom-Json)

        $rows.Count | Should -BeGreaterThan 12
        $failing = @()
        foreach ($row in $rows) {
            if (-not $row.pass) { $failing = $failing + $row.check }
        }
        $failing | Should -Be @('wt settings found')
    }
}
}
