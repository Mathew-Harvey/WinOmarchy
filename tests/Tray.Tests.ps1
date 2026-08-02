# Pester tests for the notification area icon and the lock screen commands.
# The tray's value is that it is always in the same place, so the thing worth
# testing is that every label it offers is a label something knows how to run.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    . (Join-Path $script:repoRoot (Join-Path 'bin' 'menu.ps1'))
    . (Join-Path $script:repoRoot (Join-Path 'bin' 'tray.ps1'))
    . (Join-Path $script:repoRoot (Join-Path 'bin' 'theme-set.ps1'))
    . (Join-Path $script:repoRoot (Join-Path 'bin' 'mode.ps1'))
    $script:savedHome = $env:WINMARCHY_HOME
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
}

Describe 'Tray and lock screen' {
    BeforeEach {
        $env:WINMARCHY_HOME = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
    }

Describe 'Tray menu' {
    It 'offers the swap that matches the current mode' {
        $win11 = Get-WinmarchyDefaultState
        $win11.mode = 'win11'
        @(Get-WinmarchyTrayMenuLabels -State $win11) | Should -Contain 'Swap to Omarchy mode'

        $omarchy = Get-WinmarchyDefaultState
        $omarchy.mode = 'omarchy'
        @(Get-WinmarchyTrayMenuLabels -State $omarchy) | Should -Contain 'Swap to Windows 11 mode'
    }

    It 'puts the chooser and the panic path on the menu' {
        $labels = @(Get-WinmarchyTrayMenuLabels -State (Get-WinmarchyDefaultState))
        $labels | Should -Contain 'Show the chooser'
        $labels | Should -Contain 'Restore Windows 11 (repair)'
        $labels | Should -Contain 'Hide this icon'
    }

    It 'only shows labels that something knows how to run' {
        # Anything the tray does not own itself is delegated to the shared menu
        # action, so it has to be a label the system menu also offers. This is
        # what stops the two menus drifting apart.
        $trayOnly = @('Show the chooser', 'Tutorial', 'Restore Windows 11 (repair)', 'Hide this icon')
        foreach ($mode in @('win11', 'omarchy')) {
            $state = Get-WinmarchyDefaultState
            $state.mode = $mode
            # The system menu's swap label follows the recorded mode, so the
            # comparison has to be made in the same mode the tray is showing.
            Set-WinmarchyStateValue -Name 'mode' -Value $mode
            $systemEntries = @(Get-WinmarchySystemMenuEntries)
            foreach ($label in (Get-WinmarchyTrayMenuLabels -State $state)) {
                if ($label -eq '-') { continue }
                if ($trayOnly -contains $label) { continue }
                $systemEntries | Should -Contain $label -Because ('the system menu must know how to run ' + $label)
            }
        }
    }
}

Describe 'Lock screen command' {
    It 'refuses to turn on when the current lock screen cannot be put back' {
        Mock Get-WinmarchyCurrentLockScreenImage { $null }
        Mock Test-WinmarchyIsWindows { $true }
        { Set-WinmarchyLockScreenMode -Action 'on' } | Should -Throw '*Spotlight*'
        (Get-WinmarchyState).lockScreenEnabled | Should -BeFalse
    }

    It 'captures the original picture when turning on' {
        $original = Join-Path $TestDrive 'mine.jpg'
        Write-WinmarchyTextFile -Path $original -Content 'pretend picture'
        Mock Get-WinmarchyCurrentLockScreenImage { $original }
        Mock Test-WinmarchyIsWindows { $true }
        $null = Set-WinmarchyLockScreenMode -Action 'on'
        $state = Get-WinmarchyState
        $state.lockScreenEnabled | Should -BeTrue
        $state.savedLockScreen | Should -Be $original
    }

    It 'puts the original back and forgets it when turning off' {
        $original = Join-Path $TestDrive 'mine.jpg'
        Write-WinmarchyTextFile -Path $original -Content 'pretend picture'
        Set-WinmarchyStateValue -Name 'lockScreenEnabled' -Value $true
        Set-WinmarchyStateValue -Name 'savedLockScreen' -Value $original
        Mock Test-WinmarchyIsWindows { $true }
        Mock Set-WinmarchyLockScreenImage { }
        $null = Set-WinmarchyLockScreenMode -Action 'off'
        Should -Invoke Set-WinmarchyLockScreenImage -Times 1 -ParameterFilter { $Path -eq $original }
        $state = Get-WinmarchyState
        $state.lockScreenEnabled | Should -BeFalse
        $state.savedLockScreen | Should -BeNullOrEmpty
    }

    It 'is off by default, so installing changes nothing about the lock screen' {
        (Get-WinmarchyDefaultState).lockScreenEnabled | Should -BeFalse
    }
}
}
