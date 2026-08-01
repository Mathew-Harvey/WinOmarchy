# wizard-lib.ps1: pure logic for the Winmarchy setup wizard. No UI, no
# side effects on import, so the whole decision layer is testable headlessly
# while the WPF shell in install-ui.ps1 stays a thin renderer.
# Compatible with Windows PowerShell 5.1.

function Get-WinmarchyWizardPages {
    # The wizard's page model, in order. Titles drive the step rail.
    return @(
        [pscustomobject]@{ Key = 'welcome';    Title = 'Welcome' },
        [pscustomobject]@{ Key = 'checks';     Title = 'System check' },
        [pscustomobject]@{ Key = 'theme';      Title = 'Theme' },
        [pscustomobject]@{ Key = 'components'; Title = 'Components' },
        [pscustomobject]@{ Key = 'review';     Title = 'Review' },
        [pscustomobject]@{ Key = 'install';    Title = 'Install' },
        [pscustomobject]@{ Key = 'done';       Title = 'Finish' }
    )
}

function New-WinmarchyWizardChoices {
    # The wizard's answer sheet, pre-filled with what suits this machine:
    # components whose prerequisites are missing start switched off rather
    # than set up to fail later.
    param(
        [pscustomobject[]]$Preflight
    )
    $hasDotnet = $true
    $hasWinget = $true
    $hasNvim = $false
    foreach ($row in @($Preflight)) {
        if ($row.Name -eq '.NET 8 SDK') { $hasDotnet = $row.Pass }
        if ($row.Name -eq 'winget') { $hasWinget = $row.Pass }
        if ($row.Name -eq 'Neovim config') { $hasNvim = ($row.Detail -like '*will be left*') }
    }
    return @{
        Theme        = 'tokyo-night'
        InstallApps  = $hasWinget
        SetupNeovim  = (-not $hasNvim)
        BuildChooser = $hasDotnet
        Autostart    = $hasDotnet
    }
}

function Resolve-WinmarchyWizardChoices {
    # Applies the rules between options, so an impossible combination can
    # never reach install.ps1: autostart needs a chooser to start, and
    # Neovim setup is meaningless when a config already exists.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Choices,
        [pscustomobject[]]$Preflight
    )
    $resolved = @{}
    foreach ($key in $Choices.Keys) { $resolved[$key] = $Choices[$key] }
    if (-not $resolved.BuildChooser) { $resolved.Autostart = $false }
    foreach ($row in @($Preflight)) {
        if ($row.Name -eq 'Neovim config' -and $row.Detail -like '*will be left*') {
            $resolved.SetupNeovim = $false
        }
    }
    return $resolved
}

function New-WinmarchyInstallArguments {
    # Maps the answer sheet to install.ps1 parameters. The wizard never
    # reimplements install logic; it only decides which switches to pass.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Choices
    )
    $arguments = @{ Theme = $Choices.Theme }
    if (-not $Choices.InstallApps) { $arguments['SkipApps'] = $true }
    if (-not $Choices.SetupNeovim) { $arguments['SkipNeovim'] = $true }
    if (-not $Choices.BuildChooser) { $arguments['SkipChooser'] = $true }
    if (-not $Choices.Autostart) { $arguments['NoAutostart'] = $true }
    return $arguments
}

function Get-WinmarchyInstallCommandLine {
    # The equivalent command line, shown on the review page so the wizard
    # never feels like a black box and the choice can be repeated by hand.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Choices
    )
    $arguments = New-WinmarchyInstallArguments -Choices $Choices
    $parts = @('.\install.ps1', '-Theme', $arguments.Theme)
    foreach ($switchName in @('SkipApps', 'SkipNeovim', 'SkipChooser', 'NoAutostart')) {
        if ($arguments.ContainsKey($switchName)) { $parts = $parts + ('-' + $switchName) }
    }
    return ($parts -join ' ')
}

function Get-WinmarchyWizardSummary {
    # Plain-language review lines: what the user just chose, in their terms.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Choices
    )
    $lines = @()
    $lines = $lines + ('Theme: ' + $Choices.Theme)
    if ($Choices.InstallApps) {
        $lines = $lines + ('Apps: install all ' + (@(Get-WinmarchyWingetPackages).Count) + ' packages with winget')
    } else {
        $lines = $lines + 'Apps: skip the winget installs, deploy configuration only'
    }
    if ($Choices.SetupNeovim) {
        $lines = $lines + 'Neovim: set up the LazyVim starter'
    } else {
        $lines = $lines + 'Neovim: leave Neovim alone'
    }
    if ($Choices.BuildChooser) {
        $lines = $lines + 'Chooser: build the login chooser'
    } else {
        $lines = $lines + 'Chooser: do not build it; swap from the Start menu or the command line'
    }
    if ($Choices.Autostart) {
        $lines = $lines + 'At login: show the chooser'
    } else {
        $lines = $lines + 'At login: nothing; Windows starts as it always has'
    }
    $lines = $lines + 'Always: back up every touched file first, and never proceed if that backup fails'
    return $lines
}

function Get-WinmarchyWingetPackages {
    # The Section 4.1 package table, shared by the wizard's component page
    # and its review summary. install.ps1 keeps its own copy as the thing
    # that actually runs; this is the list the user is shown.
    return @(
        [pscustomobject]@{ Id = 'glzr-io.glazewm'; Purpose = 'tiling window manager' },
        [pscustomobject]@{ Id = 'AmN.yasb'; Purpose = 'status bar' },
        [pscustomobject]@{ Id = 'Flow-Launcher.Flow-Launcher'; Purpose = 'launcher' },
        [pscustomobject]@{ Id = 'Microsoft.WindowsTerminal'; Purpose = 'terminal' },
        [pscustomobject]@{ Id = 'Neovim.Neovim'; Purpose = 'editor' },
        [pscustomobject]@{ Id = 'Git.Git'; Purpose = 'version control' },
        [pscustomobject]@{ Id = 'junegunn.fzf'; Purpose = 'fuzzy finder for menus' },
        [pscustomobject]@{ Id = 'BurntSushi.ripgrep.MSVC'; Purpose = 'grep' },
        [pscustomobject]@{ Id = 'sharkdp.fd'; Purpose = 'find' },
        [pscustomobject]@{ Id = 'sharkdp.bat'; Purpose = 'cat' },
        [pscustomobject]@{ Id = 'eza-community.eza'; Purpose = 'ls' },
        [pscustomobject]@{ Id = 'ajeetdsouza.zoxide'; Purpose = 'cd' },
        [pscustomobject]@{ Id = 'JesseDuffield.lazygit'; Purpose = 'git TUI' },
        [pscustomobject]@{ Id = 'aristocratos.btop4win'; Purpose = 'top' },
        [pscustomobject]@{ Id = 'zig.zig'; Purpose = 'C compiler for nvim-treesitter' },
        [pscustomobject]@{ Id = 'DEVCOM.JetBrainsMonoNerdFont'; Purpose = 'font' }
    )
}

function Get-WinmarchyThemeGallery {
    # Theme rows for the picker: the label plus the four colours the preview
    # strip shows. Kept separate from the theme files so the picker cannot
    # drift from what the engine will actually apply.
    $gallery = @()
    foreach ($name in (Get-WinmarchyThemeNames)) {
        $theme = Get-WinmarchyTheme -Name $name
        $gallery = $gallery + @(, [pscustomobject]@{
            Name       = $theme.name
            Label      = $theme.label
            Mode       = $theme.mode
            Accent     = $theme.colors.accent
            Background = $theme.colors.background
            Foreground = $theme.colors.foreground
            Muted      = $theme.colors.muted
            Red        = $theme.colors.red
            Green      = $theme.colors.green
            Yellow     = $theme.colors.yellow
            Blue       = $theme.colors.blue
            Magenta    = $theme.colors.magenta
        })
    }
    return $gallery
}

function Test-WinmarchyWizardCanProceed {
    # Whether the system check page allows Next: only blocking failures stop
    # the wizard, and the app check stops blocking once apps are switched off.
    param(
        [Parameter(Mandatory = $true)][pscustomobject[]]$Preflight,
        [Parameter(Mandatory = $true)][hashtable]$Choices
    )
    foreach ($row in @($Preflight)) {
        if ($row.Pass) { continue }
        if (-not $row.Blocking) { continue }
        if ($row.Name -eq 'winget' -and (-not $Choices.InstallApps)) { continue }
        return $false
    }
    return $true
}
