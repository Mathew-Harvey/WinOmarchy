# winmarchy.ps1: the Winmarchy command dispatcher.
# Usage:
#   winmarchy mode <omarchy|win11> [-Repair]
#   winmarchy theme <set <name>|next|list|current>
#   winmarchy menu [system|theme]
#   winmarchy keys
#   winmarchy status
#   winmarchy repair
#   winmarchy doctor [-Json]
#   winmarchy chooser [plain]
#   winmarchy tray
#   winmarchy lockscreen <on|off|status>
# Compatible with Windows PowerShell 5.1.

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(Position = 1)][string]$Argument = '',
    [Parameter(Position = 2)][string]$Argument2 = '',
    [switch]$Repair,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot (Join-Path 'lib' 'common.ps1'))
. (Join-Path $PSScriptRoot 'mode.ps1')
. (Join-Path $PSScriptRoot 'theme-set.ps1')

function Show-WinmarchyUsage {
    Write-Output 'winmarchy: hot-swappable Omarchy mode for Windows 11'
    Write-Output ''
    Write-Output 'commands:'
    Write-Output '  winmarchy mode omarchy      enter Omarchy mode'
    Write-Output '  winmarchy mode win11        return to stock Windows 11 (panic-safe)'
    Write-Output '  winmarchy mode win11 -Repair  same, forcing a full repair pass'
    Write-Output '  winmarchy theme set <name>  apply a theme to every surface'
    Write-Output '  winmarchy theme next        cycle to the next theme'
    Write-Output '  winmarchy theme list        list themes'
    Write-Output '  winmarchy theme current     show the active theme'
    Write-Output '  winmarchy menu [system|theme]  open the menu'
    Write-Output '  winmarchy keys              show the keybinding overlay'
    Write-Output '  winmarchy tutorial          open the Omarchy mode tutorial'
    Write-Output '  winmarchy status            show mode, theme and process state'
    Write-Output '  winmarchy repair            replay the undo journal and re-assert the recorded mode'
    Write-Output '  winmarchy doctor [-Json]    print a pass/fail health table'
    Write-Output '  winmarchy chooser [plain]   show the mode chooser now (plain skips WebView2)'
    Write-Output '  winmarchy tray              put the Winmarchy icon in the notification area'
    Write-Output '  winmarchy lockscreen on     theme the lock and sign-in screen in Omarchy mode'
    Write-Output '  winmarchy lockscreen off    put the lock screen back and leave it alone'
}

# Safety rule from the build brief Section 10: a non-empty undo journal means
# an earlier swap was interrupted, so repair runs before anything else.
if (Test-WinmarchyJournalPending) {
    Write-WinmarchyLog -Message 'journal not empty on invocation; running automatic repair first' -Level 'WARN'
    Invoke-WinmarchyRepair
}

switch ($Command) {
    'mode' {
        if ($Argument -eq 'omarchy') {
            Enter-WinmarchyOmarchyMode
        } elseif ($Argument -eq 'win11') {
            Enter-WinmarchyWin11Mode -ForceRepair:$Repair
        } else {
            Show-WinmarchyUsage
            exit 1
        }
    }
    'theme' {
        if ($Argument -eq 'set' -and $Argument2 -ne '') {
            Set-WinmarchyTheme -Name $Argument2
        } elseif ($Argument -eq 'next') {
            $state = Get-WinmarchyState
            $next = Get-WinmarchyNextThemeName -Current $state.theme
            Set-WinmarchyTheme -Name $next
            Write-Output ('theme: ' + $next)
        } elseif ($Argument -eq 'list') {
            Get-WinmarchyThemeNames | ForEach-Object { Write-Output $_ }
        } elseif ($Argument -eq 'current') {
            Write-Output ((Get-WinmarchyState).theme)
        } else {
            Show-WinmarchyUsage
            exit 1
        }
    }
    'menu' {
        $menuKind = $Argument
        if ($menuKind -eq '') { $menuKind = 'system' }
        & (Join-Path $PSScriptRoot 'menu.ps1') $menuKind
    }
    'keys' {
        & (Join-Path $PSScriptRoot 'keybindings.ps1')
    }
    'tutorial' {
        & (Join-Path $PSScriptRoot 'tutorial.ps1')
    }
    'status' {
        Get-WinmarchyStatus
    }
    'repair' {
        Invoke-WinmarchyRepair
        Write-Output 'repair complete'
    }
    'doctor' {
        Invoke-WinmarchyDoctor -Json:$Json
    }
    'chooser' {
        # Shows the chooser in this session. The point of having it as a
        # command is that a chooser that fails at login fails visibly here.
        $null = Start-WinmarchyChooser -Plain:($Argument -eq 'plain')
        Write-Output 'chooser launched'
    }
    'tray' {
        $trayHost = Start-WinmarchyTrayHost
        Write-Output ('tray started via ' + $trayHost + ' (look in the notification area, under the caret if Windows hid it)')
    }
    'lockscreen' {
        Set-WinmarchyLockScreenMode -Action $Argument
    }
    default {
        Show-WinmarchyUsage
        if ($Command -eq '') { exit 0 }
        exit 1
    }
}
