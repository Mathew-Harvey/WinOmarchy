# menu.ps1: the Winmarchy menu. Runs in a floating terminal (lwin+escape for
# the system menu, lwin+ctrl+shift+space for the theme menu) or inline via
# "winmarchy menu". Uses fzf when available and falls back to a plain
# numbered prompt, so the menu never hard-depends on fzf.
# Compatible with Windows PowerShell 5.1. Dot-source to get the functions
# without running the menu.

param(
    [string]$Kind = 'system'
)

. (Join-Path $PSScriptRoot (Join-Path 'lib' 'common.ps1'))

function Select-WinmarchyMenuEntry {
    # Presents labels and returns the chosen one, or $null when cancelled.
    param([Parameter(Mandatory = $true)][string[]]$Labels)
    $fzf = Get-Command fzf -ErrorAction SilentlyContinue
    if ($fzf) {
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $selection = $Labels | & $fzf.Source --height=100% --reverse --prompt='winmarchy> '
        } finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($LASTEXITCODE -ne 0) { return $null }
        return $selection
    }
    # Plain numbered fallback. Write-Host, not Write-Output: this function's
    # output stream IS its return value, so display lines must go straight
    # to the console or they pollute the selection.
    Write-Host ''
    for ($i = 0; $i -lt $Labels.Count; $i++) {
        Write-Host ('  ' + ($i + 1).ToString().PadLeft(2) + '. ' + $Labels[$i])
    }
    Write-Host ''
    $answer = Read-Host 'number (blank cancels)'
    if ($answer -match '^\d+$') {
        $index = [int]$answer - 1
        if ($index -ge 0 -and $index -lt $Labels.Count) { return $Labels[$index] }
    }
    return $null
}

function Get-WinmarchyThemeMenuEntries {
    # Theme names with the active one marked.
    $current = (Get-WinmarchyState).theme
    $entries = @()
    foreach ($name in (Get-WinmarchyThemeNames)) {
        $marker = '  '
        if ($name -eq $current) { $marker = '* ' }
        $entries = $entries + ($marker + $name)
    }
    return $entries
}

function Get-WinmarchySystemMenuEntries {
    # Entry list from the brief Section 7.4. The swap entry follows the mode.
    $mode = (Get-WinmarchyState).mode
    $swapLabel = 'Swap to Omarchy mode'
    if ($mode -eq 'omarchy') { $swapLabel = 'Swap to Windows 11 mode' }
    $chooserLabel = 'Chooser at login: on (toggle)'
    if ((Get-WinmarchyState).chooserDisabled) { $chooserLabel = 'Chooser at login: off (toggle)' }
    return @(
        'Theme menu',
        'Next theme',
        'Next wallpaper',
        'Keybindings',
        'Tutorial',
        'System stats (btop)',
        'Git TUI (lazygit)',
        'Files',
        $swapLabel,
        'Reload GlazeWM',
        'Edit GlazeWM config',
        'Edit yasb config',
        $chooserLabel,
        'Lock',
        'Sleep',
        'Restart',
        'Shutdown',
        'Sign out'
    )
}

function Invoke-WinmarchyMenuAction {
    # Executes one system menu entry. Commands for lock, restart, shutdown
    # and sign out are the ones named in the brief Section 7.4.
    param([Parameter(Mandatory = $true)][string]$Label)
    $dispatcher = Join-Path $PSScriptRoot 'winmarchy.ps1'
    switch -Wildcard ($Label) {
        'Theme menu' { Show-WinmarchyThemeMenu }
        'Next theme' { & $dispatcher theme next }
        'Next wallpaper' { & $dispatcher wallpaper next }
        'Keybindings' { & (Join-Path $PSScriptRoot 'keybindings.ps1') }
        'Tutorial' { & $dispatcher tutorial }
        'System stats (btop)' {
            # Runs in THIS console, which is the floating menu terminal when
            # the menu was opened from the bar or lwin+escape. The Omarchy
            # original is SUPER+CTRL+T, "Activity", a btop TUI
            # (ref/omarchy/default/hypr/bindings/utilities.lua).
            & $dispatcher stats
        }
        'Git TUI (lazygit)' {
            $lazygit = Find-WinmarchyExecutable -Name 'lazygit'
            if ($lazygit) {
                if ($env:USERPROFILE) { Push-Location $env:USERPROFILE }
                try { & $lazygit } finally { if ($env:USERPROFILE) { Pop-Location } }
            } else {
                Write-Output 'lazygit is not installed. Fix with: winget install -e --id JesseDuffield.lazygit'
            }
        }
        'Files' { Start-Process 'explorer.exe' }
        'Swap to Omarchy mode' { & $dispatcher mode omarchy }
        'Swap to Windows 11 mode' { & $dispatcher mode win11 }
        'Reload GlazeWM' { Invoke-WinmarchyGlazewmCommand -Command 'wm-reload-config' }
        'Edit GlazeWM config' { Start-Process notepad.exe -ArgumentList (Get-WinmarchyGlazewmConfigPath) }
        'Edit yasb config' { Start-Process notepad.exe -ArgumentList (Join-Path (Get-WinmarchyYasbConfigDir) 'config.yaml') }
        'Chooser at login*' {
            $state = Get-WinmarchyState
            Set-WinmarchyStateValue -Name 'chooserDisabled' -Value (-not $state.chooserDisabled)
            $flag = 'on'
            if (-not $state.chooserDisabled) { $flag = 'off' }
            Write-Output ('chooser at login is now ' + $flag)
        }
        'Lock' { & rundll32 user32.dll,LockWorkStation }
        'Sleep' {
            # SetSuspendState sleeps the machine; note it hibernates instead
            # when hibernation is enabled (documented rundll32 behaviour).
            & rundll32 powrprof.dll,SetSuspendState 0,1,0
        }
        'Restart' { & shutdown /r /t 0 }
        'Shutdown' { & shutdown /s /t 0 }
        'Sign out' { & logoff }
        default { Write-Output ('no action for: ' + $Label) }
    }
}

function Show-WinmarchyThemeMenu {
    $selection = Select-WinmarchyMenuEntry -Labels (Get-WinmarchyThemeMenuEntries)
    if ($null -eq $selection) { return }
    $themeName = $selection.Substring(2).Trim()
    $dispatcher = Join-Path $PSScriptRoot 'winmarchy.ps1'
    & $dispatcher theme set $themeName
    Write-Output ('theme: ' + $themeName)
}

function Show-WinmarchySystemMenu {
    $selection = Select-WinmarchyMenuEntry -Labels (Get-WinmarchySystemMenuEntries)
    if ($null -eq $selection) { return }
    Invoke-WinmarchyMenuAction -Label $selection
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($Kind -eq 'theme') {
        Show-WinmarchyThemeMenu
    } else {
        Show-WinmarchySystemMenu
    }
}
