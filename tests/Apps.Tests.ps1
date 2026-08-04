# Pester tests for the app dependency table, the winget exit code
# classification, and the GlazeWM path patching.
#
# These exist because of a real failure: one winget package (Alacritty) failed
# with a raw negative exit code, the installer reported it as a one-line
# warning nobody read, doctor could not see it, and four keybindings were dead
# with no way to find out why. See FLAGS.md FLAG-24 and FLAG-25.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    $script:glazeConfig = [System.IO.File]::ReadAllText(
        (Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))))
}

Describe 'Apps a keybinding depends on' {

Describe 'winget exit codes' {
    It 'treats a clean install and the already-present codes as not a failure' {
        (Get-WinmarchyWingetOutcome -ExitCode 0).Kind | Should -Be 'installed'
        # 0x8A150061 already installed, 0x8A15002B no applicable upgrade,
        # 0x8A15010D another version present, 0x8A15010E a newer version present.
        foreach ($code in @(-1978335135, -1978335189, -1978334963, -1978334962)) {
            (Get-WinmarchyWingetOutcome -ExitCode $code).Kind | Should -Be 'present' -Because ('code ' + $code + ' means the machine already has it')
        }
    }

    It 'decodes the code that actually bit, rather than printing the raw integer' {
        # 0x8A15010C APPINSTALLER_CLI_ERROR_INSTALL_CANCELLED_BY_USER.
        $outcome = Get-WinmarchyWingetOutcome -ExitCode -1978334964
        $outcome.Kind | Should -Be 'failed'
        $outcome.Hex | Should -Be '0x8A15010C'
        $outcome.Text | Should -Match 'cancelled'
        $outcome.Text | Should -Match '0x8A15010C'
    }

    It 'separates "installed, restart to finish" from "failed, restart and retry"' {
        # 0x8A150109 and 0x8A15010B are successes pending a restart.
        (Get-WinmarchyWingetOutcome -ExitCode -1978334967).Kind | Should -Be 'reboot'
        (Get-WinmarchyWingetOutcome -ExitCode -1978334965).Kind | Should -Be 'reboot'
        # 0x8A15010A is not: the install did not happen.
        (Get-WinmarchyWingetOutcome -ExitCode -1978334966).Kind | Should -Be 'failed'
    }

    It 'renders an unknown code as hex and decimal rather than swallowing it' {
        $outcome = Get-WinmarchyWingetOutcome -ExitCode -1978335224
        $outcome.Kind | Should -Be 'failed'
        $outcome.Text | Should -Match '0x8A150008'
        $outcome.Text | Should -Match '\-1978335224'
    }
}

Describe 'The dependency table' {
    It 'covers every program the GlazeWM config launches by name' {
        $names = @()
        foreach ($app in (Get-WinmarchyBindingCriticalApps)) { $names = $names + $app.Name }
        foreach ($required in @('glazewm', 'yasbc', 'alacritty', 'Flow.Launcher', 'Cursor')) {
            $names | Should -Contain $required
        }
    }

    It 'names a real winget package and a real consequence for each' {
        $installText = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'install.ps1'))
        foreach ($app in (Get-WinmarchyBindingCriticalApps)) {
            $app.PackageId | Should -Not -BeNullOrEmpty
            $app.Consequence | Should -Not -BeNullOrEmpty
            # The id has to be one install.ps1 actually installs, or the "fix
            # with" line in doctor would hand the user a command that fails.
            $installText | Should -BeLike ('*' + $app.PackageId + '*')
        }
    }
}

Describe 'Everything, the file search backend' {
    It 'never reinstalls: the presence probe runs before winget install in the loop' {
        # Round two of every install used to re-run all the machine-scope
        # installers, each one slow and each raising an elevation prompt for
        # software already on the machine.
        $installText = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'install.ps1'))
        $probeIndex = $installText.IndexOf('Test-WinmarchyWingetPackagePresent')
        $installIndex = $installText.IndexOf('& winget install')
        $probeIndex | Should -BeGreaterThan 0
        $installIndex | Should -BeGreaterThan $probeIndex
        $installText | Should -Match 'already present, skipped'
    }

    It 'is in every package table: installer, wizard and uninstaller' {
        foreach ($file in @('install.ps1', (Join-Path 'installer' 'wizard-lib.ps1'), 'uninstall.ps1')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $file))
            $text | Should -BeLike '*voidtools.Everything*' -Because ($file + ' must know the package')
        }
    }

    It 'fails the doctor verdict with the winget fix when it is not installed' {
        $verdict = Get-WinmarchyEverythingDoctorRow -Status ([pscustomobject]@{
            ExePath = $null; ServiceStatus = 'missing'; ClientRunning = $false; Autorun = $null
        })
        $verdict.Pass | Should -BeFalse
        $verdict.Detail | Should -Match 'winget install -e --id voidtools.Everything'
    }

    It 'names each broken leg: service, client, startup entry' {
        $verdict = Get-WinmarchyEverythingDoctorRow -Status ([pscustomobject]@{
            ExePath = 'C:\Program Files\Everything\Everything.exe'; ServiceStatus = 'Stopped'; ClientRunning = $false; Autorun = $null
        })
        $verdict.Pass | Should -BeFalse
        $verdict.Detail | Should -Match 'service is Stopped'
        $verdict.Detail | Should -Match 'client is not running'
        $verdict.Detail | Should -Match 'startup entry'
    }

    It 'passes only when installed, service running, client running and autorun set' {
        $verdict = Get-WinmarchyEverythingDoctorRow -Status ([pscustomobject]@{
            ExePath = 'C:\Program Files\Everything\Everything.exe'; ServiceStatus = 'Running'; ClientRunning = $true; Autorun = 'machine'
        })
        $verdict.Pass | Should -BeTrue
        $verdict.Detail | Should -Match 'client running, service running'

        $verdict = Get-WinmarchyEverythingDoctorRow -Status ([pscustomobject]@{
            ExePath = 'C:\Program Files\Everything\Everything.exe'; ServiceStatus = 'Running'; ClientRunning = $true; Autorun = $null
        })
        $verdict.Pass | Should -BeFalse -Because 'without a startup entry the search dies at the next reboot'
    }
}

Describe 'GlazeWM path patching' {
    It 'patches every Alacritty invocation, not just the one with a marker' {
        # lwin+enter carries the terminal-path marker; the keybinding overlay,
        # the system menu, the theme menu and the stats TUI do not, and used
        # to be left on the bare name so a Program Files install worked for
        # one key and failed for the rest. The count is asserted against the
        # config so a new alacritty binding cannot dodge the patch.
        $expected = ([regex]::Matches($script:glazeConfig, 'shell-exec alacritty')).Count
        $expected | Should -BeGreaterOrEqual 5
        $patched = Update-WinmarchyGlazewmAppPaths -ConfigText $script:glazeConfig -ResolvedPaths @{
            'alacritty' = 'C:\Program Files\Alacritty\alacritty.exe'
        }
        ([regex]::Matches($patched, [regex]::Escape('C:\Program Files\Alacritty\alacritty.exe'))).Count | Should -Be $expected
        $patched | Should -Not -Match "shell-exec alacritty"
    }

    It 'keeps the arguments on the three popup invocations' {
        $patched = Update-WinmarchyGlazewmAppPaths -ConfigText $script:glazeConfig -ResolvedPaths @{
            'alacritty' = 'C:\Program Files\Alacritty\alacritty.exe'
        }
        $patched | Should -Match ([regex]::Escape('alacritty.exe --title "Winmarchy Keys"'))
        $patched | Should -Match ([regex]::Escape('alacritty.exe --title "Winmarchy Menu"'))
    }

    It 'writes paths unquoted, because GlazeWM mis-parses a quoted program with a quoted argument' {
        # ref/glazewm/packages/wm/src/commands/general/shell_exec.rs: the quoted
        # branch takes the THIRD double quote as the closing one, so a command
        # like "path" --title "x" resolves the wrong program. The unquoted
        # branch joins parts cumulatively until one names a real file.
        $patched = Update-WinmarchyGlazewmAppPaths -ConfigText $script:glazeConfig -ResolvedPaths @{
            'alacritty' = 'C:\Program Files\Alacritty\alacritty.exe'
        }
        $patched | Should -Not -Match ([regex]::Escape('shell-exec "C:\Program Files'))
    }

    It 'patches the launcher and editor marker lines' {
        $patched = Update-WinmarchyGlazewmAppPaths -ConfigText $script:glazeConfig -ResolvedPaths @{
            'Flow.Launcher' = 'C:\Flow\Flow.Launcher.exe'
            'Cursor'        = 'C:\Cursor\Cursor.exe'
        }
        $patched | Should -Match ([regex]::Escape("commands: ['shell-exec C:\Flow\Flow.Launcher.exe'] # winmarchy:launcher-path"))
        $patched | Should -Match ([regex]::Escape("commands: ['shell-exec C:\Cursor\Cursor.exe'] # winmarchy:editor-path"))
    }

    It 'leaves the config alone for anything it could not resolve' {
        $patched = Update-WinmarchyGlazewmAppPaths -ConfigText $script:glazeConfig -ResolvedPaths @{
            'alacritty' = $null
            'Cursor'    = ''
        }
        $patched | Should -Be $script:glazeConfig
    }

    It 'still parses as YAML after patching' {
        Import-Module powershell-yaml
        $patched = Update-WinmarchyGlazewmAppPaths -ConfigText $script:glazeConfig -ResolvedPaths @{
            'alacritty'     = 'C:\Program Files\Alacritty\alacritty.exe'
            'Flow.Launcher' = 'C:\Flow\Flow.Launcher.exe'
            'Cursor'        = 'C:\Cursor\Cursor.exe'
        }
        { ConvertFrom-Yaml $patched } | Should -Not -Throw
    }
}
}
