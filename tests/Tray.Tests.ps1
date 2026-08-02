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
    $script:savedLocalAppData = $env:LOCALAPPDATA
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

    It 'is mirrored exactly by the C# tray in the chooser exe' {
        # The icon has two hosts: TrayApplet.cs inside the WinExe (preferred,
        # because a WinExe has no console for Windows Terminal to keep open)
        # and this script (fallback when the chooser was never built). Every
        # label the PowerShell menu offers must appear in the C# source, or
        # the two menus drift apart.
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'chooser' 'TrayApplet.cs')))
        foreach ($mode in @('win11', 'omarchy')) {
            $state = Get-WinmarchyDefaultState
            $state.mode = $mode
            foreach ($label in (Get-WinmarchyTrayMenuLabels -State $state)) {
                if ($label -eq '-') { continue }
                $applet | Should -BeLike ('*"' + $label + '"*') -Because ('TrayApplet.cs must offer ' + $label)
            }
        }
    }

    It 'shares one single-instance mutex with the C# tray, so only one icon can exist' {
        $mutexName = 'Local\WinmarchyTray'
        $applet = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'chooser' 'TrayApplet.cs')))
        $script = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot (Join-Path 'bin' 'tray.ps1')))
        $applet | Should -BeLike ('*' + $mutexName + '*')
        $script | Should -BeLike ('*' + $mutexName + '*')
    }

    It 'prefers the exe host and falls back to PowerShell' {
        # No chooser exe under this WINMARCHY_HOME: PowerShell fallback.
        $command = Get-WinmarchyTrayCommand
        $command.Host | Should -Be 'powershell'
        $command.RunKeyValue | Should -BeLike '*tray.ps1*'

        # Now the exe exists: it wins, with --tray.
        Write-WinmarchyTextFile -Path (Get-WinmarchyChooserExePath) -Content 'exe'
        $command = Get-WinmarchyTrayCommand
        $command.Host | Should -Be 'exe'
        $command.RunKeyValue | Should -BeLike '*Winmarchy.Chooser.exe" --tray'
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

Describe 'Desktop shortcut cleanup' {
    BeforeEach {
        $script:desktopA = Join-Path $TestDrive ('desk-' + [System.IO.Path]::GetRandomFileName())
        $script:desktopB = Join-Path $TestDrive ('shared-' + [System.IO.Path]::GetRandomFileName())
        $null = New-Item -ItemType Directory -Path $script:desktopA, $script:desktopB -Force
        $env:WINMARCHY_DESKTOP_DIRS = $script:desktopA + ';' + $script:desktopB
    }

    AfterEach {
        $env:WINMARCHY_DESKTOP_DIRS = $null
    }

    It 'removes only the shortcuts that appeared after the snapshot' {
        Write-WinmarchyTextFile -Path (Join-Path $script:desktopA 'Mine.lnk') -Content 'users own'
        $snapshot = @(Get-WinmarchyDesktopShortcutSnapshot)

        # The app installers drop their icons.
        Write-WinmarchyTextFile -Path (Join-Path $script:desktopA 'Alacritty.lnk') -Content 'dropped'
        Write-WinmarchyTextFile -Path (Join-Path $script:desktopB 'Flow.Launcher.lnk') -Content 'dropped'

        $result = Remove-WinmarchyNewDesktopShortcuts -Snapshot $snapshot
        @($result.Removed).Count | Should -Be 2
        Test-Path (Join-Path $script:desktopA 'Mine.lnk') | Should -BeTrue
        Test-Path (Join-Path $script:desktopA 'Alacritty.lnk') | Should -BeFalse
        Test-Path (Join-Path $script:desktopB 'Flow.Launcher.lnk') | Should -BeFalse
    }

    It 'touches nothing when nothing new appeared' {
        Write-WinmarchyTextFile -Path (Join-Path $script:desktopA 'Mine.lnk') -Content 'users own'
        $snapshot = @(Get-WinmarchyDesktopShortcutSnapshot)
        $result = Remove-WinmarchyNewDesktopShortcuts -Snapshot $snapshot
        @($result.Removed).Count | Should -Be 0
        @($result.Stuck).Count | Should -Be 0
        Test-Path (Join-Path $script:desktopA 'Mine.lnk') | Should -BeTrue
    }

    It 'copes with an empty snapshot from an empty desktop' {
        $snapshot = @(Get-WinmarchyDesktopShortcutSnapshot)
        $snapshot.Count | Should -Be 0
        Write-WinmarchyTextFile -Path (Join-Path $script:desktopA 'New.lnk') -Content 'dropped'
        $result = Remove-WinmarchyNewDesktopShortcuts -Snapshot $snapshot
        @($result.Removed).Count | Should -Be 1
    }
}

Describe 'Wallpaper cycling' {
    It 'is off by default, so installing changes nothing about the wallpaper' {
        (Get-WinmarchyDefaultState).wallpaperDir | Should -BeNullOrEmpty
        Get-WinmarchyWallpaperFolder | Should -BeNullOrEmpty
    }

    It 'finds only pictures in the folder' {
        $folder = Join-Path $TestDrive ('walls-' + [System.IO.Path]::GetRandomFileName())
        $null = New-Item -ItemType Directory -Path $folder -Force
        Write-WinmarchyTextFile -Path (Join-Path $folder 'a.jpg') -Content 'x'
        Write-WinmarchyTextFile -Path (Join-Path $folder 'b.PNG') -Content 'x'
        Write-WinmarchyTextFile -Path (Join-Path $folder 'c.bmp') -Content 'x'
        Write-WinmarchyTextFile -Path (Join-Path $folder 'notes.txt') -Content 'x'
        @(Get-WinmarchyWallpaperCandidates -Folder $folder).Count | Should -Be 3
    }

    It 'never deals the same picture twice in a row when there is a choice' {
        $candidates = @('C:\w\a.jpg', 'C:\w\b.jpg', 'C:\w\c.jpg')
        foreach ($i in 1..20) {
            $next = Get-WinmarchyNextWallpaperPath -Candidates $candidates -Current 'C:\w\b.jpg'
            $next | Should -Not -Be 'C:\w\b.jpg'
            $candidates | Should -Contain $next
        }
    }

    It 'copes with one picture and with none' {
        Get-WinmarchyNextWallpaperPath -Candidates @('C:\w\only.jpg') -Current 'C:\w\only.jpg' | Should -Be 'C:\w\only.jpg'
        Get-WinmarchyNextWallpaperPath -Candidates @() | Should -BeNullOrEmpty
    }

    It 'pauses cycling when the folder goes missing instead of failing' {
        Set-WinmarchyStateValue -Name 'wallpaperDir' -Value (Join-Path $TestDrive 'gone-away')
        Get-WinmarchyWallpaperFolder | Should -BeNullOrEmpty
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
