# Pester tests for the menu and the keybinding overlay (Phase 6).
# The overlay is generated from the GlazeWM config, so the key assertion is
# completeness: every binding the YAML parser sees must appear in the
# overlay rows (single source, nothing hand-copied to drift).

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    . (Join-Path $script:repoRoot (Join-Path 'bin' 'keybindings.ps1'))
    . (Join-Path $script:repoRoot (Join-Path 'bin' 'menu.ps1'))
    Import-Module powershell-yaml
    $script:configPath = Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))
    $script:savedHome = $env:WINMARCHY_HOME
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
}

Describe 'Menus and overlay' {
    BeforeEach {
        $env:WINMARCHY_HOME = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
    }

Describe 'Keybinding overlay parser' {
    It 'covers every binding the YAML parser sees, missing nothing' {
        $rows = @(Get-WinmarchyKeybindingRows -ConfigPath $script:configPath)
        $rows.Count | Should -BeGreaterThan 30

        $overlayBindings = @()
        foreach ($row in $rows) {
            foreach ($binding in ($row.Binding -split ', ')) { $overlayBindings = $overlayBindings + $binding }
        }

        $config = ConvertFrom-Yaml ([System.IO.File]::ReadAllText($script:configPath))
        foreach ($entry in $config['keybindings']) {
            foreach ($binding in $entry['bindings']) {
                $overlayBindings | Should -Contain $binding -Because ('overlay must show ' + $binding)
            }
        }
        foreach ($bindingMode in $config['binding_modes']) {
            foreach ($entry in $bindingMode['keybindings']) {
                foreach ($binding in $entry['bindings']) {
                    $overlayBindings | Should -Contain $binding -Because ('overlay must show resize-mode ' + $binding)
                }
            }
        }
    }

    It 'labels rows with descriptions from the config comments' {
        $rows = @(Get-WinmarchyKeybindingRows -ConfigPath $script:configPath)
        $panic = $rows | Where-Object { $_.Binding -eq 'lwin+shift+x' }
        $panic.Description | Should -Match 'PANIC'
        $terminal = $rows | Where-Object { $_.Binding -eq 'lwin+enter' }
        $terminal.Description | Should -Match 'Alacritty is the themed terminal'
    }

    It 'marks the resize mode rows with their own section' {
        $rows = @(Get-WinmarchyKeybindingRows -ConfigPath $script:configPath)
        $resizeRows = @($rows | Where-Object { $_.Section -eq 'resize mode' })
        $resizeRows.Count | Should -BeGreaterThan 3
    }
}

Describe 'Theme menu entries' {
    It 'lists all eight themes with the active one marked' {
        Set-WinmarchyStateValue -Name 'theme' -Value 'nord'
        $entries = @(Get-WinmarchyThemeMenuEntries)
        $entries.Count | Should -Be 8
        $entries | Should -Contain '* nord'
        $entries | Should -Contain '  tokyo-night'
    }
}

Describe 'System menu entries' {
    It 'offers the swap that matches the current mode' {
        Set-WinmarchyStateValue -Name 'mode' -Value 'win11'
        @(Get-WinmarchySystemMenuEntries) | Should -Contain 'Swap to Omarchy mode'
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'
        @(Get-WinmarchySystemMenuEntries) | Should -Contain 'Swap to Windows 11 mode'
    }

    It 'carries every entry the brief requires' {
        $entries = @(Get-WinmarchySystemMenuEntries)
        foreach ($required in @('Theme menu', 'Next theme', 'Next wallpaper', 'Keybindings', 'Tutorial', 'System stats (btop)', 'Git TUI (lazygit)', 'Files', 'Reload GlazeWM', 'Edit GlazeWM config', 'Lock', 'Sleep', 'Restart', 'Shutdown', 'Sign out')) {
            $entries | Should -Contain $required
        }
    }

    It 'toggles the chooser-at-login flag' {
        (Get-WinmarchyState).chooserDisabled | Should -BeFalse
        $null = Invoke-WinmarchyMenuAction -Label 'Chooser at login: on (toggle)'
        (Get-WinmarchyState).chooserDisabled | Should -BeTrue
        $null = Invoke-WinmarchyMenuAction -Label 'Chooser at login: off (toggle)'
        (Get-WinmarchyState).chooserDisabled | Should -BeFalse
    }

    It 'shows the same entries in the native window as in the PowerShell list' {
        # The native menu owns only what the list LOOKS like; every action
        # stays here. These two lists are the seam, so they are pinned
        # together the way the tray's labels are (FLAGS.md FLAG-57).
        $menuCs = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'chooser' 'MenuWindow.cs')))
        $entries = ($menuCs -split 'return new List<string>')[1]
        foreach ($label in (Get-WinmarchySystemMenuEntries)) {
            # The two dynamic labels are built the same way on both sides.
            if ($label -like 'Swap to*' -or $label -like 'Chooser at login*') { continue }
            $entries | Should -BeLike ('*"' + $label + '"*') -Because ($label + ' must appear in the native menu too')
        }
        $menuCs | Should -Match 'Swap to Windows 11 mode'
        $menuCs | Should -Match 'Swap to Omarchy mode'
        $menuCs | Should -Match 'Chooser at login: on \(toggle\)'
    }

    It 'gives the console entries a terminal when the caller is a window' {
        # btop, lazygit, the keybinding overlay and the fzf theme menu all
        # need a console. Run from the native menu there is none, so they get
        # their own rather than failing invisibly.
        Mock Start-Process { }
        Mock Resolve-WinmarchyBindingCriticalApp { 'C:\fake\alacritty.exe' }
        Mock Find-WinmarchyExecutable { 'C:\fake\lazygit.exe' }
        foreach ($label in @('System stats (btop)', 'Keybindings', 'Theme menu', 'Git TUI (lazygit)')) {
            $null = Invoke-WinmarchyMenuAction -Label $label -InOwnTerminal
        }
        Should -Invoke Start-Process -Times 4 -Exactly -ParameterFilter { $FilePath -eq 'C:\fake\alacritty.exe' }
    }

    It 'launches a mode swap detached, so the menu window does not outlive the swap' {
        # The menu used to run the swap in-process, which made it the PARENT
        # of the teardown: its floating terminal sat on screen for the whole
        # thing and was still there, an Omarchy window on a Windows 11
        # desktop, once the swap finished (FLAGS.md FLAG-55).
        Mock Start-WinmarchyDispatcherDetached { }
        $null = Invoke-WinmarchyMenuAction -Label 'Swap to Windows 11 mode'
        Should -Invoke Start-WinmarchyDispatcherDetached -Times 1 -Exactly -ParameterFilter { $Arguments -contains 'win11' }
        $null = Invoke-WinmarchyMenuAction -Label 'Swap to Omarchy mode'
        Should -Invoke Start-WinmarchyDispatcherDetached -Times 1 -Exactly -ParameterFilter { $Arguments -contains 'omarchy' }
    }

    It 'hands over the winget command when lazygit is missing, instead of failing silently' {
        Mock Find-WinmarchyExecutable { $null }
        $out = @(Invoke-WinmarchyMenuAction -Label 'Git TUI (lazygit)')
        ($out -join ' ') | Should -Match 'winget install -e --id JesseDuffield.lazygit'
    }
}
}
