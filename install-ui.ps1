# install-ui.ps1: the guided Winmarchy setup. A WPF wizard hosted directly
# in Windows PowerShell, so there is nothing to compile and nothing to
# install before you can run it: clone the repo, double-click install-ui.cmd.
#
# It never reimplements the install. Every choice becomes a parameter to
# install.ps1, which stays the single install path.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File install-ui.ps1
#   ... -Console   force the text-mode wizard (also the automatic fallback)
# Compatible with Windows PowerShell 5.1.

[CmdletBinding()]
param(
    [switch]$Console
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
. (Join-Path $PSScriptRoot (Join-Path 'installer' 'wizard-lib.ps1'))

$script:installScript = Join-Path $PSScriptRoot 'install.ps1'
$script:xamlPath = Join-Path $PSScriptRoot (Join-Path 'installer' 'wizard.xaml')

# ---------------------------------------------------------------------------
# Running install.ps1 without freezing the window
# ---------------------------------------------------------------------------

function Get-WinmarchyPowerShellPath {
    # The interpreter used to run install.ps1 as a child process. Windows
    # PowerShell on the target; whatever is hosting us elsewhere, so the
    # run-and-tail path can be exercised in a build container.
    if (Test-WinmarchyIsWindows) { return 'powershell.exe' }
    $current = (Get-Process -Id $PID).Path
    if ($current) { return $current }
    return 'pwsh'
}

function Start-WinmarchyInstallRun {
    # Runs install.ps1 as a separate process writing to a log file, which the
    # window then tails. A child process rather than a background runspace on
    # purpose: winget wants a real console, and a process gives an honest exit
    # code plus a log file that survives for troubleshooting.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Arguments,
        [switch]$WhatIf
    )
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $tempDir = [System.IO.Path]::GetTempPath()
    $logPath = Join-Path $tempDir ('winmarchy-setup-' + $stamp + '.log')
    $errPath = Join-Path $tempDir ('winmarchy-setup-' + $stamp + '.err')

    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $script:installScript + '"'))
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [bool]) {
            if ($value) { $argumentList = $argumentList + ('-' + $key) }
        } else {
            $argumentList = $argumentList + ('-' + $key) + ('"' + [string]$value + '"')
        }
    }
    if ($WhatIf) { $argumentList = $argumentList + '-WhatIf' }

    # The files must exist before the first tail, even if the child is slow
    # to start or fails to launch at all.
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($logPath, '', $encoding)
    [System.IO.File]::WriteAllText($errPath, '', $encoding)

    $process = Start-Process -FilePath (Get-WinmarchyPowerShellPath) -ArgumentList $argumentList `
        -NoNewWindow -PassThru -RedirectStandardOutput $logPath -RedirectStandardError $errPath

    return [pscustomobject]@{
        Process = $process
        LogPath = $logPath
        ErrPath = $errPath
        Offset  = [long]0
        Partial = ''
    }
}

function Read-WinmarchyInstallRun {
    # Returns the complete lines written since the last call. Opened with a
    # shared read so tailing never blocks the writing process, and a trailing
    # partial line is held back until its newline arrives.
    param([Parameter(Mandatory = $true)]$Run)
    $lines = @()
    if (-not (Test-Path $Run.LogPath)) { return $lines }

    $text = ''
    $stream = $null
    try {
        $stream = New-Object System.IO.FileStream($Run.LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        if ($stream.Length -gt $Run.Offset) {
            $null = $stream.Seek($Run.Offset, [System.IO.SeekOrigin]::Begin)
            $count = [int]($stream.Length - $Run.Offset)
            $buffer = New-Object byte[] $count
            $read = $stream.Read($buffer, 0, $count)
            $Run.Offset = $Run.Offset + $read
            $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        }
    } catch {
        return $lines
    } finally {
        if ($stream) { $stream.Dispose() }
    }
    if ($text -eq '') { return $lines }

    $text = $Run.Partial + $text
    $Run.Partial = ''
    $parts = $text -split "`r`n|`n"
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($i -eq ($parts.Count - 1)) {
            # No trailing newline yet: hold this fragment back.
            $Run.Partial = $parts[$i]
            continue
        }
        $lines = $lines + @(, [pscustomobject]@{ Kind = 'out'; Text = $parts[$i] })
    }
    return $lines
}

function Complete-WinmarchyInstallRun {
    # Called once the process has exited. Flushes whatever is left, folds in
    # anything on the error stream, and reports the outcome.
    param([Parameter(Mandatory = $true)]$Run)
    $lines = @(Read-WinmarchyInstallRun -Run $Run)
    if ($Run.Partial -ne '') {
        $lines = $lines + @(, [pscustomobject]@{ Kind = 'out'; Text = $Run.Partial })
        $Run.Partial = ''
    }

    $warnings = @()
    $errors = @()
    if (Test-Path $Run.ErrPath) {
        foreach ($line in [System.IO.File]::ReadAllLines($Run.ErrPath)) {
            if ($line.Trim() -eq '') { continue }
            # Write-Warning from the child arrives on the error stream.
            if ($line -like 'WARNING:*') {
                $warnings = $warnings + $line.Substring(8).Trim()
                $lines = $lines + @(, [pscustomobject]@{ Kind = 'warn'; Text = $line })
            } else {
                $errors = $errors + $line
                $lines = $lines + @(, [pscustomobject]@{ Kind = 'error'; Text = $line })
            }
        }
    }

    # WaitForExit with no timeout also flushes the redirected streams, so the
    # exit code is settled before it is read.
    try { $Run.Process.WaitForExit() } catch { }

    # An unreadable exit code must never be reported as a failed install:
    # Start-Process -PassThru can hand back a Process whose ExitCode throws
    # even though the child finished perfectly. Fall back to the error stream.
    $exitCode = $null
    try {
        $rawExitCode = $Run.Process.ExitCode
        if ($null -ne $rawExitCode) { $exitCode = [int]$rawExitCode }
    } catch {
        $exitCode = $null
    }

    if ($null -eq $exitCode) {
        $failed = ($errors.Count -gt 0)
    } else {
        $failed = ($exitCode -ne 0)
    }

    return [pscustomobject]@{
        Failed   = $failed
        ExitCode = $exitCode
        Warnings = $warnings
        Lines    = $lines
        LogPath  = $Run.LogPath
    }
}

# ---------------------------------------------------------------------------
# WPF wizard
# ---------------------------------------------------------------------------

function ConvertTo-WinmarchyBrush {
    # Script scope on purpose: event handlers resolve it long after the
    # scope that created them has gone.
    param([Parameter(Mandatory = $true)][string]$Hex)
    return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex)))
}

function Start-WinmarchyWpfWizard {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $reader = New-Object System.Xml.XmlNodeReader ([xml](Get-Content -Path $script:xamlPath -Raw))
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Named elements.
    $ui = @{}
    foreach ($name in @(
        'Step0', 'Step1', 'Step2', 'Step3', 'Step4', 'Step5', 'Step6',
        'PageWelcome', 'PageChecks', 'PageTheme', 'PageComponents', 'PageReview', 'PageInstall', 'PageDone',
        'ChecksList', 'ChecksVerdict', 'ThemeList', 'PreviewRoot', 'PreviewBar', 'PreviewClock',
        'PreviewWs1', 'PreviewWs2', 'PreviewWs3', 'PreviewTileFocused', 'PreviewTileOther',
        'PreviewLine1', 'PreviewLine2', 'PreviewLine3', 'PreviewLine4', 'PreviewLine5', 'PreviewPrompt', 'PreviewCaption',
        'OptApps', 'OptAppsNote', 'OptNeovim', 'OptNeovimNote', 'OptChooser', 'OptChooserNote',
        'OptAutostart', 'OptAutostartNote', 'ReviewSummary', 'ReviewPlan',
        'InstallStatus', 'InstallProgress', 'InstallLog', 'LogScroller',
        'DoneTitle', 'DoneSub', 'DoneWarnings', 'OptEnterNow',
        'FooterNote', 'BtnCancel', 'BtnBack', 'BtnNext'
    )) {
        $ui[$name] = $window.FindName($name)
    }

    $pages = @(Get-WinmarchyWizardPages)
    $pageElements = @($ui.PageWelcome, $ui.PageChecks, $ui.PageTheme, $ui.PageComponents, $ui.PageReview, $ui.PageInstall, $ui.PageDone)
    $stepElements = @($ui.Step0, $ui.Step1, $ui.Step2, $ui.Step3, $ui.Step4, $ui.Step5, $ui.Step6)

    $state = @{
        Index      = 0
        Preflight  = @(Get-WinmarchyPreflight)
        Choices    = $null
        Run        = $null
        Timer      = $null
        Installed  = $false
        PlanLoaded = $false
        PlanRun    = $null
        PlanTimer  = $null
        PlanLines  = $null
    }
    $state.Choices = New-WinmarchyWizardChoices -Preflight $state.Preflight

    # --- system check page ---
    $checkRows = @()
    foreach ($row in $state.Preflight) {
        # Bound values are hex strings, never Brush objects: WPF converts a
        # string for us, but cannot convert a PowerShell-wrapped Brush, and a
        # failed binding silently renders as default black.
        $mark = 'ok'
        $markColour = '#9ece6a'
        if (-not $row.Pass) {
            $mark = 'x'
            $markColour = '#f7768e'
            if (-not $row.Blocking) { $markColour = '#e0af68' }
        }
        $checkRows = $checkRows + @(, [pscustomobject]@{ Mark = $mark; MarkColour = $markColour; Name = $row.Name; Detail = $row.Detail })
    }
    $ui.ChecksList.ItemsSource = $checkRows

    # --- theme page ---
    $gallery = @()
    foreach ($theme in (Get-WinmarchyThemeGallery)) {
        $gallery = $gallery + @(, [pscustomobject]@{
            Name         = $theme.Name
            Label        = $theme.Label
            Mode         = $theme.Mode
            Accent       = $theme.Accent
            Background   = $theme.Background
            Foreground   = $theme.Foreground
            Muted        = $theme.Muted
            AccentColour  = $theme.Accent
            RedColour     = $theme.Red
            GreenColour   = $theme.Green
            YellowColour  = $theme.Yellow
            MagentaColour = $theme.Magenta
        })
    }
    $ui.ThemeList.ItemsSource = $gallery

    $updatePreview = {
        $selected = $ui.ThemeList.SelectedItem
        if ($null -eq $selected) { return }
        $state.Choices.Theme = $selected.Name
        $background = ConvertTo-WinmarchyBrush $selected.Background
        $accent = ConvertTo-WinmarchyBrush $selected.Accent
        $muted = ConvertTo-WinmarchyBrush $selected.Muted
        $foreground = ConvertTo-WinmarchyBrush $selected.Foreground
        $ui.PreviewRoot.Background = $background
        $ui.PreviewBar.Background = ConvertTo-WinmarchyBrush $selected.Background
        $ui.PreviewBar.BorderBrush = $muted
        $ui.PreviewClock.Foreground = $foreground
        $ui.PreviewWs1.Background = $accent
        $ui.PreviewWs2.Background = $accent
        $ui.PreviewWs3.Background = $muted
        $ui.PreviewTileFocused.BorderBrush = $accent
        $ui.PreviewTileOther.BorderBrush = $muted
        foreach ($line in @($ui.PreviewLine1, $ui.PreviewLine2, $ui.PreviewLine3, $ui.PreviewLine4, $ui.PreviewLine5)) {
            $line.Background = $muted
        }
        $ui.PreviewPrompt.Background = $accent
        $ui.PreviewCaption.Text = ($selected.Label + '  (' + $selected.Mode + ' mode)')
    }
    $null = $ui.ThemeList.Add_SelectionChanged($updatePreview)
    $ui.ThemeList.SelectedIndex = 0
    foreach ($i in 0..($gallery.Count - 1)) {
        if ($gallery[$i].Name -eq $state.Choices.Theme) { $ui.ThemeList.SelectedIndex = $i }
    }

    # --- components page ---
    $ui.OptApps.IsChecked = $state.Choices.InstallApps
    $ui.OptAppsNote.Text = ('The ' + (@(Get-WinmarchyWingetPackages).Count) + ' packages Winmarchy uses: the window manager, bar, launcher, terminal, Neovim, the Nerd Font and a handful of command line tools. Per-user, no admin prompt.')
    $ui.OptNeovim.IsChecked = $state.Choices.SetupNeovim
    $ui.OptChooser.IsChecked = $state.Choices.BuildChooser
    $ui.OptAutostart.IsChecked = $state.Choices.Autostart

    $nvimNote = 'Clones the LazyVim starter so Neovim picks up the palette straight away.'
    foreach ($row in $state.Preflight) {
        if ($row.Name -eq 'Neovim config' -and $row.Detail -like '*will be left*') {
            $nvimNote = 'You already have a Neovim config, so this stays off and your setup is left completely alone. Theming applies once a LazyVim config is present.'
            $ui.OptNeovim.IsEnabled = $false
            $ui.OptNeovim.IsChecked = $false
        }
        if ($row.Name -eq 'winget' -and (-not $row.Pass)) {
            $ui.OptApps.IsEnabled = $false
            $ui.OptApps.IsChecked = $false
            $ui.OptAppsNote.Text = 'winget was not found, so the apps cannot be installed automatically. Setup will deploy the configuration only.'
        }
        if ($row.Name -eq '.NET 8 SDK' -and (-not $row.Pass)) {
            $ui.OptChooser.IsEnabled = $false
            $ui.OptChooser.IsChecked = $false
        }
    }
    $ui.OptNeovimNote.Text = $nvimNote

    $chooserNote = 'The split-screen picker at login. Needs the .NET 8 SDK to build once.'
    $autostartNote = 'Without this, Windows starts normally and you swap from the Start menu or by running winmarchy mode omarchy.'
    if (-not $ui.OptChooser.IsEnabled) {
        $chooserNote = 'The .NET 8 SDK was not found, so the chooser cannot be built. Everything else works; you swap from the Start menu or the command line.'
    }
    $ui.OptChooserNote.Text = $chooserNote
    $ui.OptAutostartNote.Text = $autostartNote

    $syncAutostart = {
        # Autostart is meaningless with no chooser to start.
        if (-not $ui.OptChooser.IsChecked) {
            $ui.OptAutostart.IsChecked = $false
            $ui.OptAutostart.IsEnabled = $false
        } else {
            $ui.OptAutostart.IsEnabled = $true
        }
    }
    $null = $ui.OptChooser.Add_Checked($syncAutostart)
    $null = $ui.OptChooser.Add_Unchecked($syncAutostart)
    & $syncAutostart

    # --- page navigation ---
    $collectChoices = {
        $state.Choices.InstallApps = [bool]$ui.OptApps.IsChecked
        $state.Choices.SetupNeovim = [bool]$ui.OptNeovim.IsChecked
        $state.Choices.BuildChooser = [bool]$ui.OptChooser.IsChecked
        $state.Choices.Autostart = [bool]$ui.OptAutostart.IsChecked
        $state.Choices = Resolve-WinmarchyWizardChoices -Choices $state.Choices -Preflight $state.Preflight
    }

    $appendLog = {
        param($Text, $Kind)
        $run = New-Object System.Windows.Documents.Run
        $run.Text = $Text + [Environment]::NewLine
        if ($Kind -eq 'warn') { $run.Foreground = ConvertTo-WinmarchyBrush '#e0af68' }
        if ($Kind -eq 'error') { $run.Foreground = ConvertTo-WinmarchyBrush '#f7768e' }
        $null = $ui.InstallLog.Inlines.Add($run)
        $ui.LogScroller.ScrollToEnd()
    }

    $startInstall = $null
    $showPage = $null

    $showPage = {
        param([int]$Index)
        $state.Index = $Index
        for ($i = 0; $i -lt $pageElements.Count; $i++) {
            if ($i -eq $Index) {
                $pageElements[$i].Visibility = 'Visible'
            } else {
                $pageElements[$i].Visibility = 'Collapsed'
            }
            if ($i -eq $Index) {
                $stepElements[$i].Foreground = ConvertTo-WinmarchyBrush '#7aa2f7'
                $stepElements[$i].FontWeight = 'SemiBold'
            } elseif ($i -lt $Index) {
                $stepElements[$i].Foreground = ConvertTo-WinmarchyBrush '#a9b1d6'
                $stepElements[$i].FontWeight = 'Normal'
            } else {
                $stepElements[$i].Foreground = ConvertTo-WinmarchyBrush '#565f89'
                $stepElements[$i].FontWeight = 'Normal'
            }
        }

        $key = $pages[$Index].Key
        $ui.BtnBack.IsEnabled = ($Index -gt 0 -and $Index -lt 5)
        $ui.BtnNext.IsEnabled = $true
        $ui.BtnNext.Content = 'Next'
        $ui.BtnCancel.IsEnabled = $true
        $ui.FooterNote.Text = ''

        if ($key -eq 'checks') {
            $canProceed = Test-WinmarchyWizardCanProceed -Preflight $state.Preflight -Choices $state.Choices
            if ($canProceed) {
                $ui.ChecksVerdict.Text = 'This machine is ready. Anything marked in amber is optional and only limits what setup can do for you.'
                $ui.ChecksVerdict.Foreground = ConvertTo-WinmarchyBrush '#9ece6a'
            } else {
                $ui.ChecksVerdict.Text = 'Setup cannot continue until the failures above are fixed. Close this, sort them out and run setup again.'
                $ui.ChecksVerdict.Foreground = ConvertTo-WinmarchyBrush '#f7768e'
                $ui.BtnNext.IsEnabled = $false
            }
        }

        if ($key -eq 'review') {
            & $collectChoices
            $ui.ReviewSummary.Children.Clear()
            foreach ($line in (Get-WinmarchyWizardSummary -Choices $state.Choices)) {
                $block = New-Object System.Windows.Controls.TextBlock
                $block.Text = $line
                $block.Foreground = ConvertTo-WinmarchyBrush '#a9b1d6'
                $block.FontSize = 13
                $block.TextWrapping = 'Wrap'
                $block.Margin = '0,0,0,6'
                $null = $ui.ReviewSummary.Children.Add($block)
            }
            $commandLine = New-Object System.Windows.Controls.TextBlock
            $commandLine.Text = ('Same thing from a shell:  ' + (Get-WinmarchyInstallCommandLine -Choices $state.Choices))
            $commandLine.Foreground = ConvertTo-WinmarchyBrush '#565f89'
            $commandLine.FontFamily = 'Consolas'
            $commandLine.FontSize = 12
            $commandLine.TextWrapping = 'Wrap'
            $commandLine.Margin = '0,8,0,0'
            $null = $ui.ReviewSummary.Children.Add($commandLine)

            $ui.BtnNext.Content = 'Install'
            if (-not $state.PlanLoaded) {
                # The plan comes from install.ps1 -WhatIf, so what is shown is
                # produced by the code that will do the work. The run, timer
                # and collected lines are held in $state because this scope
                # has exited by the time the first tick fires.
                $ui.ReviewPlan.Text = 'Working out the plan...'
                try {
                    $state.PlanRun = Start-WinmarchyInstallRun -Arguments (New-WinmarchyInstallArguments -Choices $state.Choices) -WhatIf
                    $state.PlanLines = New-Object System.Collections.ArrayList
                    $state.PlanTimer = New-Object System.Windows.Threading.DispatcherTimer
                    $state.PlanTimer.Interval = [TimeSpan]::FromMilliseconds(150)
                    $null = $state.PlanTimer.Add_Tick({
                        try {
                            foreach ($line in (Read-WinmarchyInstallRun -Run $state.PlanRun)) {
                                if ($line.Text.Trim() -ne '') { $null = $state.PlanLines.Add($line.Text) }
                            }
                            if (-not $state.PlanRun.Process.HasExited) { return }
                            $state.PlanTimer.Stop()
                            $planResult = Complete-WinmarchyInstallRun -Run $state.PlanRun
                            foreach ($line in $planResult.Lines) {
                                if ($line.Text.Trim() -ne '') { $null = $state.PlanLines.Add($line.Text) }
                            }
                            $ui.ReviewPlan.Text = ($state.PlanLines -join [Environment]::NewLine)
                            $state.PlanLoaded = $true
                        } catch {
                            $state.PlanTimer.Stop()
                            $ui.ReviewPlan.Text = ('The plan preview could not be produced: ' + $_.Exception.Message + [Environment]::NewLine + 'Setup can still run; the plan is only a preview.')
                            $state.PlanLoaded = $true
                        }
                    })
                    $state.PlanTimer.Start()
                } catch {
                    $ui.ReviewPlan.Text = ('The plan preview could not be produced: ' + $_.Exception.Message + [Environment]::NewLine + 'Setup can still run; the plan is only a preview.')
                    $state.PlanLoaded = $true
                }
            }
        }

        if ($key -eq 'install') {
            $ui.BtnBack.IsEnabled = $false
            $ui.BtnNext.IsEnabled = $false
            $ui.BtnCancel.IsEnabled = $false
            $ui.FooterNote.Text = 'Closing this window before setup finishes can leave a partial install. Run uninstall.ps1 if that happens.'
            & $startInstall
        }

        if ($key -eq 'done') {
            $ui.BtnBack.IsEnabled = $false
            $ui.BtnNext.Content = 'Close'
            $ui.BtnCancel.IsEnabled = $false
        }
    }

    $failInstall = {
        param($Message)
        # Anything that goes wrong here must be visible: a frozen page with an
        # empty log is the one outcome this wizard must never produce.
        if ($state.Timer) { $state.Timer.Stop() }
        & $appendLog $Message 'error'
        $ui.InstallProgress.IsIndeterminate = $false
        $state.Installed = $false
        $ui.DoneTitle.Text = 'Setup did not finish'
        $ui.DoneTitle.Foreground = ConvertTo-WinmarchyBrush '#f7768e'
        $ui.DoneSub.Text = ($Message + '  Nothing has been left running. Run uninstall.ps1 to clear away anything partial.')
        $ui.OptEnterNow.Visibility = 'Collapsed'
        $ui.BtnNext.IsEnabled = $true
        $ui.BtnNext.Content = 'Close'
    }

    $startInstall = {
        & $collectChoices
        $ui.InstallLog.Inlines.Clear()
        $ui.InstallStatus.Text = 'Backing up, installing and applying the theme. This can take a few minutes while winget works.'
        $ui.InstallProgress.IsIndeterminate = $true

        try {
            $state.Run = Start-WinmarchyInstallRun -Arguments (New-WinmarchyInstallArguments -Choices $state.Choices)
        } catch {
            & $failInstall ('Setup could not be started: ' + $_.Exception.Message)
            & $showPage 6
            return
        }
        & $appendLog ('Running ' + (Get-WinmarchyInstallCommandLine -Choices $state.Choices)) 'out'
        & $appendLog ('Log file: ' + $state.Run.LogPath) 'out'

        $state.Timer = New-Object System.Windows.Threading.DispatcherTimer
        $state.Timer.Interval = [TimeSpan]::FromMilliseconds(200)
        $null = $state.Timer.Add_Tick({
          try {
            foreach ($line in (Read-WinmarchyInstallRun -Run $state.Run)) {
                if ($line.Text.Trim() -ne '') { & $appendLog $line.Text $line.Kind }
            }
            if (-not $state.Run.Process.HasExited) { return }

            $state.Timer.Stop()
            $result = Complete-WinmarchyInstallRun -Run $state.Run
            foreach ($line in $result.Lines) {
                if ($line.Text.Trim() -ne '') { & $appendLog $line.Text $line.Kind }
            }
            $ui.InstallProgress.IsIndeterminate = $false
            $ui.InstallProgress.Value = 100
            $state.Installed = (-not $result.Failed)

            if ($result.Failed) {
                $ui.DoneTitle.Text = 'Setup did not finish'
                $ui.DoneTitle.Foreground = ConvertTo-WinmarchyBrush '#f7768e'
                $ui.DoneSub.Text = ('Nothing has been left running. The log above has the detail, and it is saved at ' + $result.LogPath + '. Run uninstall.ps1 to clear away anything partial.')
                $ui.OptEnterNow.Visibility = 'Collapsed'
            } else {
                $ui.DoneSub.Text = ('Everything is in place, and your original settings are backed up under ' + (Get-WinmarchyBackupDir) + '.')
                if ($state.Choices.Autostart) {
                    $ui.DoneSub.Text = $ui.DoneSub.Text + ' Log out and back in to meet the chooser.'
                }
                if ($result.Warnings.Count -gt 0) {
                    $ui.DoneWarnings.Text = ('Finished with ' + $result.Warnings.Count + ' warning(s): ' + ($result.Warnings -join '; '))
                    $ui.DoneWarnings.Visibility = 'Visible'
                }
            }
            & $showPage 6
          } catch {
            & $failInstall ('Setup stopped unexpectedly: ' + $_.Exception.Message)
            & $showPage 6
          }
        })
        $state.Timer.Start()
    }

    # --- buttons ---
    $null = $ui.BtnNext.Add_Click({
        if ($pages[$state.Index].Key -eq 'done') {
            $window.Close()
            return
        }
        if ($pages[$state.Index].Key -eq 'components') { & $collectChoices; $state.PlanLoaded = $false }
        & $showPage ($state.Index + 1)
    })
    $null = $ui.BtnBack.Add_Click({ & $showPage ($state.Index - 1) })
    $null = $ui.BtnCancel.Add_Click({ $window.Close() })

    & $showPage 0
    $null = $window.ShowDialog()

    if ($state.Installed -and $ui.OptEnterNow.IsChecked) {
        Write-Output 'Starting Omarchy mode...'
        & (Join-Path $PSScriptRoot (Join-Path 'bin' 'winmarchy.ps1')) mode omarchy
    }
}

# ---------------------------------------------------------------------------
# Console wizard: the fallback when WPF is unavailable, and -Console
# ---------------------------------------------------------------------------

function Read-WinmarchyYesNo {
    param([string]$Question, [bool]$Default)
    $suffix = ' [y/N] '
    if ($Default) { $suffix = ' [Y/n] ' }
    $answer = Read-Host ($Question + $suffix)
    if ($answer.Trim() -eq '') { return $Default }
    return ($answer.Trim().ToLower().StartsWith('y'))
}

function Start-WinmarchyConsoleWizard {
    Write-Output ''
    Write-Output '  Winmarchy setup'
    Write-Output '  Two desktops on one machine: stock Windows 11, and an Omarchy-style'
    Write-Output '  tiling desktop you can swap to at any time. Nothing is overwritten'
    Write-Output '  without a backup, and there is always a way back.'
    Write-Output ''

    $preflight = @(Get-WinmarchyPreflight)
    Write-Output '  System check'
    foreach ($row in $preflight) {
        $mark = 'ok  '
        if (-not $row.Pass) {
            $mark = 'note'
            if ($row.Blocking) { $mark = 'FAIL' }
        }
        Write-Output ('    ' + $mark + ' ' + $row.Name.PadRight(18) + ' ' + $row.Detail)
    }
    Write-Output ''

    $choices = New-WinmarchyWizardChoices -Preflight $preflight
    $nvimExists = $false
    $wingetMissing = $false
    foreach ($row in $preflight) {
        if ($row.Name -eq 'Neovim config' -and $row.Detail -like '*will be left*') { $nvimExists = $true }
        if ($row.Name -eq 'winget' -and (-not $row.Pass)) { $wingetMissing = $true }
    }

    Write-Output '  Themes'
    $gallery = @(Get-WinmarchyThemeGallery)
    for ($i = 0; $i -lt $gallery.Count; $i++) {
        $marker = '  '
        if ($gallery[$i].Name -eq $choices.Theme) { $marker = '* ' }
        Write-Output ('    ' + ($i + 1).ToString().PadLeft(2) + '. ' + $marker + $gallery[$i].Label.PadRight(14) + ' ' + $gallery[$i].Mode)
    }
    $themeAnswer = Read-Host '  theme number (blank keeps the marked one)'
    if ($themeAnswer -match '^\d+$') {
        $index = [int]$themeAnswer - 1
        if ($index -ge 0 -and $index -lt $gallery.Count) { $choices.Theme = $gallery[$index].Name }
    }
    Write-Output ''

    # Questions whose answer is already forced are stated, not asked.
    if ($wingetMissing) {
        Write-Output '  Apps: winget is not available, so the configuration is deployed on its own.'
    } else {
        $choices.InstallApps = Read-WinmarchyYesNo -Question ('  Install the ' + (@(Get-WinmarchyWingetPackages).Count) + ' apps with winget?') -Default $choices.InstallApps
    }
    if ($nvimExists) {
        Write-Output '  Neovim: you already have a config, so it is left completely untouched.'
    } else {
        $choices.SetupNeovim = Read-WinmarchyYesNo -Question '  Set up Neovim with the LazyVim starter?' -Default $choices.SetupNeovim
    }
    $choices.BuildChooser = Read-WinmarchyYesNo -Question '  Build the login chooser?' -Default $choices.BuildChooser
    if ($choices.BuildChooser) {
        $choices.Autostart = Read-WinmarchyYesNo -Question '  Show the chooser at login?' -Default $choices.Autostart
    }
    $choices = Resolve-WinmarchyWizardChoices -Choices $choices -Preflight $preflight

    Write-Output ''
    Write-Output '  Review'
    foreach ($line in (Get-WinmarchyWizardSummary -Choices $choices)) {
        Write-Output ('    ' + $line)
    }
    Write-Output ('    Same thing from a shell: ' + (Get-WinmarchyInstallCommandLine -Choices $choices))
    Write-Output ''

    if (-not (Read-WinmarchyYesNo -Question '  Start setup now?' -Default $true)) {
        Write-Output '  Nothing was changed.'
        return
    }

    Write-Output ''
    $arguments = New-WinmarchyInstallArguments -Choices $choices
    & $script:installScript @arguments

    Write-Output ''
    if (Read-WinmarchyYesNo -Question '  Start Omarchy mode now?' -Default $false) {
        & (Join-Path $PSScriptRoot (Join-Path 'bin' 'winmarchy.ps1')) mode omarchy
    }
}

# ---------------------------------------------------------------------------
# Entry point: WPF where possible, console where not
# ---------------------------------------------------------------------------

# Dot-sourcing loads the functions without launching anything, so the tests
# can drive the real run-and-tail path.
if ($MyInvocation.InvocationName -eq '.') { return }

if ($Console) {
    Start-WinmarchyConsoleWizard
    return
}

$wpfAvailable = $true
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
} catch {
    $wpfAvailable = $false
}
if ($wpfAvailable -and ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA')) {
    # WPF needs a single-threaded apartment; install-ui.cmd passes -STA.
    Write-Output 'This shell is not running in STA mode, so the window cannot open.'
    Write-Output 'Re-run with: powershell -NoProfile -ExecutionPolicy Bypass -STA -File install-ui.ps1'
    Write-Output 'Falling back to the text version.'
    Write-Output ''
    $wpfAvailable = $false
}

if ($wpfAvailable) {
    Start-WinmarchyWpfWizard
} else {
    Start-WinmarchyConsoleWizard
}
