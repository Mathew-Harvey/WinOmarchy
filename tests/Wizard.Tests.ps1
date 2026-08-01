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
}
