# keybindings.ps1: the keybinding overlay. The content is generated from the
# GlazeWM config itself (the implementation of the brief's Section 6 table),
# so there is no hand-copied duplicate to drift out of date. Launched by
# lwin+k in a floating terminal titled "Winmarchy Keys", or via
# "winmarchy keys" from any shell.
# Compatible with Windows PowerShell 5.1. Dot-source to get the parser
# functions without running the overlay.

. (Join-Path $PSScriptRoot (Join-Path 'lib' 'common.ps1'))

function Get-WinmarchyKeybindingRows {
    # Parses the keybindings and binding_modes sections of a GlazeWM config
    # into rows of binding, description (taken from the comment above the
    # entry, falling back to the command string) and section.
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    $rows = @()
    $section = ''
    $bindingModeName = ''
    $pendingComment = ''
    $pendingCommands = ''

    foreach ($line in [System.IO.File]::ReadAllLines($ConfigPath)) {
        if ($line -match '^([a-z_]+):') {
            $section = $Matches[1]
            $pendingComment = ''
            $pendingCommands = ''
            continue
        }
        if ($section -ne 'keybindings' -and $section -ne 'binding_modes') { continue }

        if ($line -match "^\s*- name: '([^']+)'") {
            $bindingModeName = $Matches[1]
            continue
        }
        if ($line -match '^\s*$') {
            $pendingComment = ''
            continue
        }
        if ($line -match '^\s*#\s?(.*)$') {
            $commentText = $Matches[1].Trim()
            if ($pendingComment -eq '') {
                $pendingComment = $commentText
            } else {
                $pendingComment = $pendingComment + ' ' + $commentText
            }
            continue
        }
        if ($line -match '^\s*- commands: \[(.+)\]') {
            $pendingCommands = $Matches[1]
            continue
        }
        if ($line -match '^\s*bindings: \[(.+)\]') {
            $bindingList = @()
            foreach ($token in ($Matches[1] -split ',')) {
                $bindingList = $bindingList + $token.Trim().Trim("'")
            }
            $description = $pendingComment
            if ($description -eq '') {
                $description = ($pendingCommands -replace "'", '')
            }
            $rowSection = $section
            if ($section -eq 'binding_modes') { $rowSection = $bindingModeName + ' mode' }
            $rows = $rows + @(, [pscustomobject]@{
                Binding     = ($bindingList -join ', ')
                Description = $description
                Section     = $rowSection
            })
            $pendingComment = ''
            $pendingCommands = ''
            continue
        }
    }
    return $rows
}

function Get-WinmarchyActiveGlazewmConfigPath {
    # Deployed config when present, repo config as the fallback for dev runs.
    $deployed = Get-WinmarchyGlazewmConfigPath
    if (Test-Path $deployed) { return $deployed }
    return (Join-Path (Get-WinmarchyRepoRoot) (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml')))
}

function Show-WinmarchyKeybindings {
    $configPath = Get-WinmarchyActiveGlazewmConfigPath
    $rows = @(Get-WinmarchyKeybindingRows -ConfigPath $configPath)

    Write-Output ''
    Write-Output '  Winmarchy keybindings (read live from the GlazeWM config)'
    Write-Output ('  ' + $configPath)
    Write-Output ''
    # Main bindings first, binding modes after, regardless of file order.
    $ordered = @($rows | Where-Object { $_.Section -eq 'keybindings' })
    $ordered = $ordered + @($rows | Where-Object { $_.Section -ne 'keybindings' })
    $rows = $ordered
    $currentSection = ''
    foreach ($row in $rows) {
        if ($row.Section -ne $currentSection) {
            $currentSection = $row.Section
            if ($currentSection -ne 'keybindings') {
                Write-Output ''
                Write-Output ('  [' + $currentSection + ']')
            }
        }
        $description = $row.Description
        if ($description.Length -gt 76) { $description = $description.Substring(0, 73) + '...' }
        Write-Output ('  ' + $row.Binding.PadRight(28) + ' ' + $description)
    }
    Write-Output ''
    Write-Output '  Win+L locks (reserved by Windows). Alt+Tab stays native.'
    Write-Output ''
    Write-Output '  press any key to close'
    try {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch {
        $null = Read-Host
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Show-WinmarchyKeybindings
}
