# Pester tests for the setup wizard. The WPF shell cannot run in the build
# container, so the decision layer lives in installer/wizard-lib.ps1 and is
# tested here in full: preflight blocking rules, option interlocks, the
# mapping from answers to install.ps1 parameters, and the XAML being loadable.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    . (Join-Path $script:repoRoot (Join-Path 'installer' 'wizard-lib.ps1'))
    $script:xamlPath = Join-Path $script:repoRoot (Join-Path 'installer' 'wizard.xaml')
    $script:savedHome = $env:WINMARCHY_HOME
    $script:savedNvim = $env:WINMARCHY_NVIM_DIR

    function New-Row {
        param([string]$Name, [bool]$Pass, [bool]$Blocking, [string]$Detail = '')
        return [pscustomobject]@{ Name = $Name; Pass = $Pass; Blocking = $Blocking; Detail = $Detail }
    }
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
    $env:WINMARCHY_NVIM_DIR = $script:savedNvim
}

Describe 'Setup wizard' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $env:WINMARCHY_HOME = Join-Path $testRoot 'home'
        $env:WINMARCHY_NVIM_DIR = Join-Path $testRoot 'nvim'
    }

Describe 'Preflight' {
    It 'reports every check the wizard and installer rely on' {
        $names = @()
        foreach ($row in (Get-WinmarchyPreflight)) { $names = $names + $row.Name }
        foreach ($expected in @('Windows 11', 'winget', '.NET 8 SDK', 'Disk space', 'Existing install', 'Neovim config', 'Windows Terminal')) {
            $names | Should -Contain $expected
        }
    }

    It 'never blocks on an optional component' {
        foreach ($row in (Get-WinmarchyPreflight)) {
            if ($row.Name -eq '.NET 8 SDK' -or $row.Name -eq 'Existing install' -or $row.Name -eq 'Neovim config' -or $row.Name -eq 'Windows Terminal') {
                $row.Blocking | Should -BeFalse -Because ($row.Name + ' must never stop an install')
            }
        }
    }

    It 'stops blocking on winget once the apps are skipped' {
        $withApps = @(Get-WinmarchyPreflight) | Where-Object { $_.Name -eq 'winget' }
        $withoutApps = @(Get-WinmarchyPreflight -SkipApps) | Where-Object { $_.Name -eq 'winget' }
        $withoutApps.Blocking | Should -BeFalse
        # On Windows the with-apps case blocks; off Windows neither does, and
        # the point of the test is that -SkipApps only ever relaxes it.
        if ($withApps.Blocking) { $withApps.Pass | Should -BeFalse }
    }

    It 'notices an existing Neovim config and says it will be left alone' {
        $null = New-Item -ItemType Directory -Path $env:WINMARCHY_NVIM_DIR -Force
        $row = @(Get-WinmarchyPreflight) | Where-Object { $_.Name -eq 'Neovim config' }
        $row.Detail | Should -Match 'left completely untouched'
    }

    It 'notices an existing install and calls it an update' {
        $null = New-Item -ItemType Directory -Path (Join-Path $env:WINMARCHY_HOME 'bin') -Force
        $row = @(Get-WinmarchyPreflight) | Where-Object { $_.Name -eq 'Existing install' }
        $row.Detail | Should -Match 'already installed'
    }
}

Describe 'Default choices' {
    It 'switches off components whose prerequisites are missing' {
        $preflight = @(
            (New-Row 'winget' $false $true),
            (New-Row '.NET 8 SDK' $false $false),
            (New-Row 'Neovim config' $true $false 'no Neovim config; the LazyVim starter can be set up for you')
        )
        $choices = New-WinmarchyWizardChoices -Preflight $preflight
        $choices.InstallApps | Should -BeFalse
        $choices.BuildChooser | Should -BeFalse
        $choices.Autostart | Should -BeFalse
        $choices.SetupNeovim | Should -BeTrue
    }

    It 'leaves an existing Neovim config alone by default' {
        $preflight = @(
            (New-Row 'winget' $true $true),
            (New-Row '.NET 8 SDK' $true $false),
            (New-Row 'Neovim config' $true $false 'your Neovim config exists and will be left completely untouched')
        )
        $choices = New-WinmarchyWizardChoices -Preflight $preflight
        $choices.SetupNeovim | Should -BeFalse
        $choices.InstallApps | Should -BeTrue
        $choices.BuildChooser | Should -BeTrue
    }
}

Describe 'Option interlocks' {
    It 'turns autostart off when the chooser is not being built' {
        $choices = @{ Theme = 'nord'; InstallApps = $true; SetupNeovim = $true; BuildChooser = $false; Autostart = $true }
        $resolved = Resolve-WinmarchyWizardChoices -Choices $choices -Preflight @()
        $resolved.Autostart | Should -BeFalse
    }

    It 'never enables Neovim setup over an existing config' {
        $choices = @{ Theme = 'nord'; InstallApps = $true; SetupNeovim = $true; BuildChooser = $true; Autostart = $true }
        $preflight = @((New-Row 'Neovim config' $true $false 'your Neovim config exists and will be left completely untouched'))
        $resolved = Resolve-WinmarchyWizardChoices -Choices $choices -Preflight $preflight
        $resolved.SetupNeovim | Should -BeFalse
    }

    It 'leaves a valid combination untouched' {
        $choices = @{ Theme = 'gruvbox'; InstallApps = $true; SetupNeovim = $true; BuildChooser = $true; Autostart = $true }
        $resolved = Resolve-WinmarchyWizardChoices -Choices $choices -Preflight @()
        $resolved.Theme | Should -Be 'gruvbox'
        $resolved.Autostart | Should -BeTrue
        $resolved.SetupNeovim | Should -BeTrue
    }
}

Describe 'Mapping answers to install.ps1' {
    It 'passes only the theme when everything is wanted' {
        $choices = @{ Theme = 'kanagawa'; InstallApps = $true; SetupNeovim = $true; BuildChooser = $true; Autostart = $true }
        $arguments = New-WinmarchyInstallArguments -Choices $choices
        $arguments.Theme | Should -Be 'kanagawa'
        $arguments.Keys.Count | Should -Be 1
    }

    It 'adds a skip switch for each declined component' {
        $choices = @{ Theme = 'nord'; InstallApps = $false; SetupNeovim = $false; BuildChooser = $false; Autostart = $false }
        $arguments = New-WinmarchyInstallArguments -Choices $choices
        $arguments.ContainsKey('SkipApps') | Should -BeTrue
        $arguments.ContainsKey('SkipNeovim') | Should -BeTrue
        $arguments.ContainsKey('SkipChooser') | Should -BeTrue
        $arguments.ContainsKey('NoAutostart') | Should -BeTrue
    }

    It 'only ever names parameters install.ps1 actually has' {
        $installParams = @((Get-Command (Join-Path $script:repoRoot 'install.ps1')).Parameters.Keys)
        $choices = @{ Theme = 'nord'; InstallApps = $false; SetupNeovim = $false; BuildChooser = $false; Autostart = $false }
        foreach ($key in (New-WinmarchyInstallArguments -Choices $choices).Keys) {
            $installParams | Should -Contain $key
        }
    }

    It 'shows an equivalent command line the user could type' {
        $choices = @{ Theme = 'nord'; InstallApps = $false; SetupNeovim = $true; BuildChooser = $true; Autostart = $true }
        Get-WinmarchyInstallCommandLine -Choices $choices | Should -Be '.\install.ps1 -Theme nord -SkipApps'
    }
}

Describe 'Review summary' {
    It 'describes each decision in plain language and always promises the backup' {
        $choices = @{ Theme = 'everforest'; InstallApps = $true; SetupNeovim = $false; BuildChooser = $true; Autostart = $false }
        $lines = @(Get-WinmarchyWizardSummary -Choices $choices)
        ($lines -join ' ') | Should -Match 'everforest'
        ($lines -join ' ') | Should -Match 'install all 16 packages'
        ($lines -join ' ') | Should -Match 'leave Neovim alone'
        ($lines -join ' ') | Should -Match 'build the login chooser'
        ($lines -join ' ') | Should -Match 'Windows starts as it always has'
        ($lines -join ' ') | Should -Match 'never proceed if that backup fails'
    }
}

Describe 'Blocking rules for the Next button' {
    It 'stops on a blocking failure' {
        $preflight = @((New-Row 'Windows 11' $false $true))
        $choices = @{ InstallApps = $true }
        Test-WinmarchyWizardCanProceed -Preflight $preflight -Choices $choices | Should -BeFalse
    }

    It 'ignores a non-blocking failure' {
        $preflight = @((New-Row '.NET 8 SDK' $false $false))
        Test-WinmarchyWizardCanProceed -Preflight $preflight -Choices @{ InstallApps = $true } | Should -BeTrue
    }

    It 'lets a missing winget through once the apps are declined' {
        $preflight = @((New-Row 'winget' $false $true))
        Test-WinmarchyWizardCanProceed -Preflight $preflight -Choices @{ InstallApps = $true } | Should -BeFalse
        Test-WinmarchyWizardCanProceed -Preflight $preflight -Choices @{ InstallApps = $false } | Should -BeTrue
    }
}

Describe 'Theme gallery' {
    It 'offers every installed theme with the colours the preview needs' {
        $gallery = @(Get-WinmarchyThemeGallery)
        $gallery.Count | Should -Be 8
        foreach ($entry in $gallery) {
            $entry.Label | Should -Not -BeNullOrEmpty
            $entry.Mode | Should -BeIn @('dark', 'light')
            foreach ($colour in @($entry.Accent, $entry.Background, $entry.Foreground, $entry.Muted, $entry.Red, $entry.Green, $entry.Yellow, $entry.Blue, $entry.Magenta)) {
                $colour | Should -Match '^#[0-9a-fA-F]{6}$'
            }
        }
    }
}

Describe 'Wizard XAML' {
    It 'is well-formed XML' {
        { [xml](Get-Content -Path $script:xamlPath -Raw) } | Should -Not -Throw
    }

    It 'carries every element install-ui.ps1 looks up by name' {
        $xaml = [xml](Get-Content -Path $script:xamlPath -Raw)
        $names = @()
        foreach ($node in $xaml.SelectNodes('//*')) {
            $nameAttribute = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
            if ($nameAttribute) { $names = $names + $nameAttribute }
        }
        $driver = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'install-ui.ps1'))
        # The lookup list in install-ui.ps1 is the contract between the two files.
        foreach ($required in @('BtnNext', 'BtnBack', 'BtnCancel', 'ThemeList', 'ChecksList', 'InstallLog', 'ReviewPlan', 'OptApps', 'OptChooser', 'OptAutostart', 'OptNeovim', 'PageWelcome', 'PageDone')) {
            $names | Should -Contain $required
            $driver | Should -Match ("'" + $required + "'")
        }
    }

    It 'binds colours as strings, never as Brush objects' {
        # A PowerShell-wrapped Brush cannot be converted by WPF, so the binding
        # fails silently and the element renders in its default colour (black).
        $raw = [System.IO.File]::ReadAllText($script:xamlPath)
        $raw | Should -Not -Match '\{Binding \w*Brush\}'
        $raw | Should -Match '\{Binding MarkColour\}'
        $raw | Should -Match '\{Binding AccentColour\}'
    }

    It 'has no event handler attributes, which XamlReader cannot bind' {
        $raw = [System.IO.File]::ReadAllText($script:xamlPath)
        $raw | Should -Not -Match '\sClick="'
        $raw | Should -Not -Match '\sx:Class="'
    }

    It 'has one page element per wizard step' {
        $xaml = [xml](Get-Content -Path $script:xamlPath -Raw)
        $pageNames = @()
        foreach ($node in $xaml.SelectNodes('//*')) {
            $nameAttribute = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
            if ($nameAttribute -like 'Page*') { $pageNames = $pageNames + $nameAttribute }
        }
        $pageNames.Count | Should -Be (@(Get-WinmarchyWizardPages).Count)
    }
}

Describe 'Install run and log tail' {
    # This is the path that streams install.ps1 into the wizard's log window.
    # It runs install.ps1 as a child process and tails its log file, so it is
    # exercisable here even though the window itself is not.
    BeforeAll {
        . (Join-Path $script:repoRoot 'install-ui.ps1')

        function Invoke-RunToCompletion {
            param([hashtable]$Arguments, [switch]$WhatIf)
            $run = Start-WinmarchyInstallRun -Arguments $Arguments -WhatIf:$WhatIf
            $lines = @()
            $deadline = (Get-Date).AddSeconds(120)
            while (-not $run.Process.HasExited) {
                $lines = $lines + @(Read-WinmarchyInstallRun -Run $run)
                if ((Get-Date) -gt $deadline) { throw 'install run did not finish within 120 seconds' }
                Start-Sleep -Milliseconds 100
            }
            $result = Complete-WinmarchyInstallRun -Run $run
            $lines = $lines + @($result.Lines)
            return [pscustomobject]@{ Result = $result; Lines = $lines; Text = (($lines | ForEach-Object { $_.Text }) -join [Environment]::NewLine) }
        }
    }

    BeforeEach {
        $script:runRoot = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $null = New-Item -ItemType Directory -Path $script:runRoot -Force
        $script:savedRunHome = $env:WINMARCHY_HOME
        $script:savedRunProfile = $env:WINMARCHY_USERPROFILE
        $script:savedRunLocal = $env:LOCALAPPDATA
        $env:WINMARCHY_HOME = Join-Path $script:runRoot 'home'
        $env:WINMARCHY_USERPROFILE = Join-Path $script:runRoot 'profile'
        $env:LOCALAPPDATA = Join-Path $script:runRoot 'lad'
    }

    AfterEach {
        $env:WINMARCHY_HOME = $script:savedRunHome
        $env:WINMARCHY_USERPROFILE = $script:savedRunProfile
        $env:LOCALAPPDATA = $script:savedRunLocal
    }

    It 'streams the plan when asked for a preview and changes nothing' {
        $before = @(Get-ChildItem -Path $script:runRoot -Recurse -File -Force).Count
        $run = Invoke-RunToCompletion -Arguments @{ Theme = 'nord'; SkipApps = $true } -WhatIf

        $run.Result.Failed | Should -BeFalse
        $run.Result.ExitCode | Should -Be 0
        $run.Text | Should -Match 'whatif: back up everything'
        $run.Text | Should -Match 'whatif: deploy bin/'
        @(Get-ChildItem -Path $script:runRoot -Recurse -File -Force).Count | Should -Be $before
    }

    It 'streams a real install line by line and reports success' {
        $run = Invoke-RunToCompletion -Arguments @{ Theme = 'gruvbox'; SkipApps = $true; SkipNeovim = $true; SkipChooser = $true; NoAutostart = $true }

        $run.Result.Failed | Should -BeFalse
        $run.Result.ExitCode | Should -Be 0
        # The very first line of install.ps1 must reach the log: an empty log
        # is the symptom this test exists to catch.
        $run.Lines[0].Text | Should -Match 'winmarchy installer'
        $run.Text | Should -Match 'install: deploy bin/'
        $run.Text | Should -Match 'install: apply the gruvbox theme'
        @($run.Lines).Count | Should -BeGreaterThan 5
        Test-Path (Join-Path $env:WINMARCHY_HOME 'bin') | Should -BeTrue
    }

    It 'reports a failed install rather than hanging' {
        $run = Invoke-RunToCompletion -Arguments @{ Theme = 'no-such-theme'; SkipApps = $true }

        $run.Result.Failed | Should -BeTrue
        $run.Result.ExitCode | Should -Not -Be 0
        ($run.Text + ' ') | Should -Match 'Unknown theme'
    }

    It 'keeps a log file behind for troubleshooting' {
        $run = Start-WinmarchyInstallRun -Arguments @{ Theme = 'nord'; SkipApps = $true } -WhatIf
        while (-not $run.Process.HasExited) { Start-Sleep -Milliseconds 100 }
        $result = Complete-WinmarchyInstallRun -Run $run
        Test-Path $result.LogPath | Should -BeTrue
        [System.IO.File]::ReadAllText($result.LogPath) | Should -Match 'winmarchy installer'
    }

    It 'holds back a partial line until its newline arrives' {
        $logPath = Join-Path $script:runRoot 'partial.log'
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($logPath, "first line`nsecond", $encoding)
        $fake = [pscustomobject]@{ LogPath = $logPath; ErrPath = (Join-Path $script:runRoot 'partial.err'); Offset = [long]0; Partial = '' }

        $first = @(Read-WinmarchyInstallRun -Run $fake)
        $first.Count | Should -Be 1
        $first[0].Text | Should -Be 'first line'
        $fake.Partial | Should -Be 'second'

        [System.IO.File]::AppendAllText($logPath, " half`nthird`n", $encoding)
        $second = @(Read-WinmarchyInstallRun -Run $fake)
        $second[0].Text | Should -Be 'second half'
        $second[1].Text | Should -Be 'third'
    }

    It 'exits zero on success so the wizard can trust the exit code' {
        $run = Invoke-RunToCompletion -Arguments @{ Theme = 'nord'; SkipApps = $true; SkipNeovim = $true; SkipChooser = $true; NoAutostart = $true }
        $run.Result.ExitCode | Should -Be 0
        $run.Result.Failed | Should -BeFalse
    }

    It 'does not call an install failed just because the exit code cannot be read' {
        # Start-Process -PassThru can hand back a Process whose ExitCode throws
        # even after a clean run; that must never read as a failed install.
        $logPath = Join-Path $script:runRoot 'unreadable.log'
        $errPath = Join-Path $script:runRoot 'unreadable.err'
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($logPath, "winmarchy installer`ninstall: done`n", $encoding)
        [System.IO.File]::WriteAllText($errPath, '', $encoding)
        $stub = New-Object psobject
        $stub | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { }
        $stub | Add-Member -MemberType ScriptProperty -Name ExitCode -Value { throw 'no handle' }
        $fake = [pscustomobject]@{ Process = $stub; LogPath = $logPath; ErrPath = $errPath; Offset = [long]0; Partial = '' }

        $result = Complete-WinmarchyInstallRun -Run $fake
        $result.Failed | Should -BeFalse
        $null -eq $result.ExitCode | Should -BeTrue
    }

    It 'still reports failure from the error stream when the exit code is unreadable' {
        $logPath = Join-Path $script:runRoot 'stderr.log'
        $errPath = Join-Path $script:runRoot 'stderr.err'
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($logPath, "winmarchy installer`n", $encoding)
        [System.IO.File]::WriteAllText($errPath, "something exploded`n", $encoding)
        $stub = New-Object psobject
        $stub | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { }
        $stub | Add-Member -MemberType ScriptProperty -Name ExitCode -Value { throw 'no handle' }
        $fake = [pscustomobject]@{ Process = $stub; LogPath = $logPath; ErrPath = $errPath; Offset = [long]0; Partial = '' }

        (Complete-WinmarchyInstallRun -Run $fake).Failed | Should -BeTrue
    }

    It 'treats a child warning as a warning, not an error' {
        $logPath = Join-Path $script:runRoot 'warn.log'
        $errPath = Join-Path $script:runRoot 'warn.err'
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($logPath, "winmarchy installer`n", $encoding)
        [System.IO.File]::WriteAllText($errPath, "WARNING: dotnet SDK not found; chooser not built`n", $encoding)
        $stub = New-Object psobject
        $stub | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { }
        $stub | Add-Member -MemberType ScriptProperty -Name ExitCode -Value { 0 }
        $fake = [pscustomobject]@{ Process = $stub; LogPath = $logPath; ErrPath = $errPath; Offset = [long]0; Partial = '' }

        $result = Complete-WinmarchyInstallRun -Run $fake
        $result.Failed | Should -BeFalse
        @($result.Warnings).Count | Should -Be 1
        $result.Warnings[0] | Should -Match 'chooser not built'
    }
}
}
