# Pester tests for install.ps1 and uninstall.ps1 (Phase 4).
# Runs both scripts for real against throwaway directories (WINMARCHY_HOME,
# WINMARCHY_USERPROFILE and LOCALAPPDATA all point into the TestDrive), so
# the file-level behaviour is tested end to end while the Windows-only steps
# skip themselves.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    $script:savedHome = $env:WINMARCHY_HOME
    $script:savedProfile = $env:WINMARCHY_USERPROFILE
    $script:savedLocalAppData = $env:LOCALAPPDATA

    function Get-FileSnapshot {
        # Path plus content hash for every file under a directory.
        param([string]$Root)
        $snapshot = @{}
        if (Test-Path $Root) {
            foreach ($file in (Get-ChildItem -Path $Root -Recurse -File -Force)) {
                $snapshot[$file.FullName] = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
            }
        }
        return $snapshot
    }

    function Initialize-FakeMachine {
        # A little pre-existing user world for the installer to respect.
        param([string]$Root)
        $profileDir = Join-Path $Root 'profile'
        $localAppData = Join-Path $Root 'localappdata'
        $glazeDir = Join-Path $profileDir (Join-Path '.glzr' 'glazewm')
        $yasbDir = Join-Path $profileDir (Join-Path '.config' 'yasb')
        $wtDir = Join-Path $localAppData (Join-Path 'Microsoft' 'Windows Terminal')
        $null = New-Item -ItemType Directory -Path $glazeDir, $yasbDir, $wtDir -Force
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $glazeDir 'config.yaml'), "general: {}`n# users own glazewm config`n", $encoding)
        [System.IO.File]::WriteAllText((Join-Path $yasbDir 'config.yaml'), "bars: {}`n# users own yasb config`n", $encoding)
        [System.IO.File]::WriteAllText((Join-Path $wtDir 'settings.json'), '{ "profiles": { "defaults": {}, "list": [] }, "schemes": [] }', $encoding)

        $env:WINMARCHY_HOME = Join-Path $Root 'winmarchy-home'
        $env:WINMARCHY_USERPROFILE = $profileDir
        $env:LOCALAPPDATA = $localAppData
    }
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
    $env:WINMARCHY_USERPROFILE = $script:savedProfile
    $env:LOCALAPPDATA = $script:savedLocalAppData
}

Describe 'Installer and uninstaller' {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $null = New-Item -ItemType Directory -Path $script:testRoot -Force
        Initialize-FakeMachine -Root $script:testRoot
    }

Describe 'install.ps1 -WhatIf' {
    It 'prints the complete action list and writes nothing at all' {
        $before = Get-FileSnapshot -Root $script:testRoot

        $output = & (Join-Path $script:repoRoot 'install.ps1') -WhatIf -SkipApps 2>&1 | Out-String

        $after = Get-FileSnapshot -Root $script:testRoot
        $after.Count | Should -Be $before.Count
        foreach ($path in $before.Keys) {
            $after[$path] | Should -Be $before[$path] -Because ($path + ' must be untouched by -WhatIf')
        }

        $output | Should -Match 'whatif: back up everything'
        $output | Should -Match 'whatif: deploy bin/'
        $output | Should -Match 'whatif: write GlazeWM config'
        $output | Should -Match 'whatif: write yasb config'
        $output | Should -Match ([regex]::Escape('whatif: apply the tokyo-night theme'))
    }
}

Describe 'install.ps1 real run' {
    It 'backs up every touched file with a complete manifest, then deploys' {
        $glazeConfig = Join-Path $env:WINMARCHY_USERPROFILE (Join-Path '.glzr' (Join-Path 'glazewm' 'config.yaml'))
        $originalGlaze = [System.IO.File]::ReadAllText($glazeConfig)

        $null = & (Join-Path $script:repoRoot 'install.ps1') -SkipApps 2>&1 | Out-String

        # Backup manifest completeness: every pre-existing file the installer
        # overwrites must be in the manifest with a real backup copy.
        $backupRoot = Join-Path $env:WINMARCHY_HOME 'backup'
        $backupSets = @(Get-ChildItem -Path $backupRoot -Directory)
        $backupSets.Count | Should -Be 1
        $manifest = [System.IO.File]::ReadAllText((Join-Path $backupSets[0].FullName 'manifest.json')) | ConvertFrom-Json
        $labels = @()
        foreach ($entry in @($manifest.entries)) { $labels = $labels + $entry.label }
        $labels | Should -Contain 'glazewm-config'
        $labels | Should -Contain 'yasb-config'
        $labels | Should -Contain 'wt-settings'
        foreach ($entry in @($manifest.entries)) {
            if ((Test-PsObjectProperty $entry 'existed') -and $entry.existed) {
                Test-Path $entry.backupPath | Should -BeTrue -Because ('backup copy for ' + $entry.label + ' must exist')
                if ($entry.label -eq 'glazewm-config') {
                    [System.IO.File]::ReadAllText($entry.backupPath) | Should -Be $originalGlaze
                }
            }
        }

        # Deployment happened.
        Test-Path (Join-Path $env:WINMARCHY_HOME (Join-Path 'bin' 'winmarchy.ps1')) | Should -BeTrue
        Test-Path (Join-Path $env:WINMARCHY_HOME (Join-Path 'themes' 'tokyo-night.json')) | Should -BeTrue
        Test-Path (Join-Path $env:WINMARCHY_HOME (Join-Path 'config' (Join-Path 'yasb' 'styles.template.css'))) | Should -BeTrue

        # The user's glazewm config was replaced with ours.
        $newGlaze = [System.IO.File]::ReadAllText($glazeConfig)
        $newGlaze | Should -Match 'winmarchy:focused-border'

        # The theme was applied: yasb styles rendered with no leftover tokens.
        $styles = [System.IO.File]::ReadAllText((Join-Path (Join-Path $env:WINMARCHY_USERPROFILE (Join-Path '.config' 'yasb')) 'styles.css'))
        $styles.Contains('{{') | Should -BeFalse
        $styles.Contains('#7aa2f7') | Should -BeTrue

        # State records the chosen theme.
        (Get-WinmarchyState).theme | Should -Be 'tokyo-night'
    }

    It 'honours -Theme and validates it before doing anything' {
        $null = & (Join-Path $script:repoRoot 'install.ps1') -SkipApps -Theme 'nord' 2>&1 | Out-String
        (Get-WinmarchyState).theme | Should -Be 'nord'
        { & (Join-Path $script:repoRoot 'install.ps1') -WhatIf -SkipApps -Theme 'not-a-theme' } | Should -Throw '*Unknown theme*'
    }
}

Describe 'uninstall.ps1' {
    It 'restores the pre-install configs from the oldest backup and removes the install' {
        $glazeConfig = Join-Path $env:WINMARCHY_USERPROFILE (Join-Path '.glzr' (Join-Path 'glazewm' 'config.yaml'))
        $originalGlaze = [System.IO.File]::ReadAllText($glazeConfig)

        $null = & (Join-Path $script:repoRoot 'install.ps1') -SkipApps 2>&1 | Out-String
        [System.IO.File]::ReadAllText($glazeConfig) | Should -Not -Be $originalGlaze

        $null = & (Join-Path $script:repoRoot 'uninstall.ps1') -KeepTerminalTheme 3>$null 2>&1 | Out-String

        [System.IO.File]::ReadAllText($glazeConfig) | Should -Be $originalGlaze
        Test-Path $env:WINMARCHY_HOME | Should -BeFalse
    }

    It 'leaves Windows Terminal completely untouched at install time' {
        $wtPath = Join-Path $env:LOCALAPPDATA (Join-Path 'Microsoft' (Join-Path 'Windows Terminal' 'settings.json'))
        $originalWt = [System.IO.File]::ReadAllText($wtPath)

        $null = & (Join-Path $script:repoRoot 'install.ps1') -SkipApps 2>&1 | Out-String

        # Installing sets Winmarchy up; it does not reskin Windows. The
        # terminal only changes on entering Omarchy mode.
        [System.IO.File]::ReadAllText($wtPath) | Should -Be $originalWt
    }

    It 'surgically removes the Winmarchy additions from Windows Terminal settings' {
        $wtPath = Join-Path $env:LOCALAPPDATA (Join-Path 'Microsoft' (Join-Path 'Windows Terminal' 'settings.json'))

        $null = & (Join-Path $script:repoRoot 'install.ps1') -SkipApps 2>&1 | Out-String
        # Entering Omarchy mode is what themes the terminal, so simulate that.
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'
        $null = Update-WtSettingsFile -Path $wtPath -Theme (Get-WinmarchyTheme -Name 'tokyo-night') -SetFontFace
        $patched = [System.IO.File]::ReadAllText($wtPath) | ConvertFrom-Json
        $patched.profiles.defaults.colorScheme | Should -Be 'Winmarchy Tokyo Night'

        # A customisation made after install must survive the uninstall.
        Set-PsObjectProperty $patched 'copyOnSelect' $true
        [System.IO.File]::WriteAllText($wtPath, ($patched | ConvertTo-Json -Depth 64), (New-Object System.Text.UTF8Encoding($false)))

        $null = & (Join-Path $script:repoRoot 'uninstall.ps1') 3>$null 2>&1 | Out-String

        $cleaned = [System.IO.File]::ReadAllText($wtPath) | ConvertFrom-Json
        $cleaned.copyOnSelect | Should -BeTrue
        foreach ($scheme in @($cleaned.schemes)) {
            if ($null -ne $scheme) { $scheme.name | Should -Not -Match '^Winmarchy ' }
        }
        Test-PsObjectProperty $cleaned.profiles.defaults 'colorScheme' | Should -BeFalse
    }

    It 'works from a simulated half-failed install' {
        # Half-install: deployed bin only; no state, no backups, no configs.
        $null = New-Item -ItemType Directory -Path (Join-Path $env:WINMARCHY_HOME 'bin') -Force
        Copy-Item -Path (Join-Path $script:repoRoot (Join-Path 'bin' '*')) -Destination (Join-Path $env:WINMARCHY_HOME 'bin') -Recurse -Force

        $output = & (Join-Path $script:repoRoot 'uninstall.ps1') -KeepTerminalTheme 3>$null 2>&1 | Out-String

        Test-Path $env:WINMARCHY_HOME | Should -BeFalse
        $output | Should -Match 'winmarchy removed'
    }

    It 'keeps state and backups with -KeepState' {
        $null = & (Join-Path $script:repoRoot 'install.ps1') -SkipApps 2>&1 | Out-String

        $null = & (Join-Path $script:repoRoot 'uninstall.ps1') -KeepState -KeepTerminalTheme 3>$null 2>&1 | Out-String

        Test-Path (Join-Path $env:WINMARCHY_HOME 'state') | Should -BeTrue
        Test-Path (Join-Path $env:WINMARCHY_HOME 'backup') | Should -BeTrue
        Test-Path (Join-Path $env:WINMARCHY_HOME 'bin') | Should -BeFalse
        Test-Path (Join-Path $env:WINMARCHY_HOME 'themes') | Should -BeFalse
    }

    It 'removes deployed configs when the user had none before install' {
        # Fresh machine with no pre-existing configs at all.
        $freshRoot = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $null = New-Item -ItemType Directory -Path $freshRoot -Force
        $env:WINMARCHY_HOME = Join-Path $freshRoot 'winmarchy-home'
        $env:WINMARCHY_USERPROFILE = Join-Path $freshRoot 'profile'
        $env:LOCALAPPDATA = Join-Path $freshRoot 'localappdata'
        $null = New-Item -ItemType Directory -Path $env:WINMARCHY_USERPROFILE, $env:LOCALAPPDATA -Force

        $null = & (Join-Path $script:repoRoot 'install.ps1') -SkipApps 2>&1 | Out-String
        $glazeConfig = Join-Path $env:WINMARCHY_USERPROFILE (Join-Path '.glzr' (Join-Path 'glazewm' 'config.yaml'))
        Test-Path $glazeConfig | Should -BeTrue

        $null = & (Join-Path $script:repoRoot 'uninstall.ps1') -KeepTerminalTheme 3>$null 2>&1 | Out-String

        Test-Path $glazeConfig | Should -BeFalse
    }
}
}
