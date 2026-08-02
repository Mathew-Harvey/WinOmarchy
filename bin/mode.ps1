# mode.ps1: the Winmarchy mode manager. Defines functions only; the
# dispatcher (winmarchy.ps1) dot-sources this after lib/common.ps1.
# Every operating-system effector lives in lib/common.ps1 behind a plain
# function boundary so Pester can mock the lot and test the state machine
# headlessly (build brief Section 7.2 and Phase 3).

function Enter-WinmarchyOmarchyMode {
    # Enters Omarchy mode: GlazeWM plus yasb plus hidden taskbar and icons
    # plus themed everything. Journals every mutation before making it, and
    # rolls back to Windows 11 mode automatically if the health check fails.
    [CmdletBinding()]
    param()

    Write-WinmarchyLog -Message 'enter-omarchy: begin'
    $state = Get-WinmarchyState

    # Capture the user's Windows wallpaper and light/dark setting once, before
    # anything changes, so enter-win11 can restore them exactly.
    if (-not $state.savedWallpaper) {
        $currentWallpaper = Get-WinmarchyCurrentWallpaper
        if ($currentWallpaper) {
            Set-WinmarchyStateValue -Name 'savedWallpaper' -Value $currentWallpaper
            Write-WinmarchyLog -Message ('enter-omarchy: captured wallpaper ' + $currentWallpaper)
        }
    }
    if ($null -eq $state.savedAppsUseLightTheme) {
        $appsTheme = Get-WinmarchyAppsTheme
        Set-WinmarchyStateValue -Name 'savedAppsUseLightTheme' -Value $appsTheme.AppsUseLightTheme
        Set-WinmarchyStateValue -Name 'savedSystemUsesLightTheme' -Value $appsTheme.SystemUsesLightTheme
    }
    # Same again for the lock screen, but only when the user opted in: without
    # a capture there is nothing to restore, so theme-set is told to leave it
    # alone rather than change something it cannot undo.
    if ($state.lockScreenEnabled -and (-not $state.savedLockScreen)) {
        $currentLockScreen = Get-WinmarchyCurrentLockScreenImage
        if ($currentLockScreen) {
            Set-WinmarchyStateValue -Name 'savedLockScreen' -Value $currentLockScreen
            Write-WinmarchyLog -Message ('enter-omarchy: captured lock screen ' + $currentLockScreen)
        } else {
            Set-WinmarchyStateValue -Name 'lockScreenEnabled' -Value $false
            Write-WinmarchyLog -Message 'enter-omarchy: the current lock screen is not a file that can be put back (Spotlight or a slideshow), so lock screen theming stays off' -Level 'WARN'
            Write-Warning 'Lock screen theming switched off: Windows is showing Spotlight or a slideshow, which Winmarchy cannot restore afterwards. Set a picture in Settings > Personalisation > Lock screen first, then run: winmarchy lockscreen on'
        }
    }

    try {
        # Step: start GlazeWM.
        if (-not (Test-WinmarchyProcessRunning -Name 'glazewm')) {
            Add-WinmarchyJournalEntry -Action 'glazewm-started'
            Start-WinmarchyGlazewm
            Write-WinmarchyLog -Message 'enter-omarchy: started GlazeWM'
        }

        # Step: start yasb.
        if (-not (Test-WinmarchyProcessRunning -Name 'yasb')) {
            Add-WinmarchyJournalEntry -Action 'yasb-started'
            Start-WinmarchyYasb
            Write-WinmarchyLog -Message 'enter-omarchy: started yasb'
        }

        # Step: taskbar to auto-hide.
        $taskbarState = Get-WinmarchyTaskbarAutoHide
        if (-not $taskbarState) {
            Add-WinmarchyJournalEntry -Action 'taskbar-autohide' -Data @{ previous = $taskbarState }
            Set-WinmarchyTaskbarAutoHide -Enabled $true
            Write-WinmarchyLog -Message 'enter-omarchy: taskbar set to auto-hide'
        }

        # Step: desktop icons off. The live toggle is a blind WM_COMMAND, so
        # the current state is read from the registry first (Section 3).
        $iconsVisible = Get-WinmarchyDesktopIconsVisible
        if ($iconsVisible) {
            Add-WinmarchyJournalEntry -Action 'icons-hidden' -Data @{ previous = $true }
            Set-WinmarchyDesktopIcons -Visible $false
            Write-WinmarchyLog -Message 'enter-omarchy: desktop icons hidden'
        }

        # Step: launcher.
        if (-not (Test-WinmarchyProcessRunning -Name 'Flow.Launcher')) {
            Start-WinmarchyFlowLauncher
            Write-WinmarchyLog -Message 'enter-omarchy: started Flow Launcher'
        }

        # Step: apply the current theme across every surface, including the
        # Omarchy-only ones (wallpaper, app mode). Both of those mutations
        # get journal entries first; their undo values were captured into
        # state before anything changed.
        $freshState = Get-WinmarchyState
        Add-WinmarchyJournalEntry -Action 'wallpaper-set' -Data @{ previous = $freshState.savedWallpaper }
        Add-WinmarchyJournalEntry -Action 'apps-theme-set' -Data @{ previousApps = $freshState.savedAppsUseLightTheme; previousSystem = $freshState.savedSystemUsesLightTheme }
        if ($freshState.lockScreenEnabled -and $freshState.savedLockScreen) {
            Add-WinmarchyJournalEntry -Action 'lock-screen-set' -Data @{ previous = $freshState.savedLockScreen }
        }
        Set-WinmarchyTheme -Name $freshState.theme -AsOmarchy

        # Health check: GlazeWM process alive AND its IPC socket connectable
        # AND yasb process alive, within 20 seconds.
        if (-not (Wait-WinmarchyOmarchyHealthy -TimeoutSeconds 20)) {
            throw 'health check failed: GlazeWM or yasb did not come up healthy within 20 seconds'
        }

        # Commit.
        Clear-WinmarchyJournal
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'
        Set-WinmarchyStateValue -Name 'lastMode' -Value 'omarchy'
        Write-WinmarchyLog -Message 'enter-omarchy: committed'
        Write-Output 'Omarchy mode active.'

        # First time in: teach the keys. Never blocks the swap, and never
        # shows twice; winmarchy tutorial reopens it on demand.
        if (-not (Get-WinmarchyState).tutorialSeen) {
            try {
                & (Join-Path $PSScriptRoot 'tutorial.ps1')
                Write-Output 'First run: the tutorial is opening in your browser (winmarchy tutorial to see it again).'
            } catch {
                Write-WinmarchyLog -Message ('enter-omarchy: tutorial failed to open: ' + $_.Exception.Message) -Level 'WARN'
            }
        }
    } catch {
        $reason = $_.Exception.Message
        Write-WinmarchyLog -Message ('enter-omarchy failed: ' + $reason) -Level 'ERROR'
        # Automatic rollback: land the user on a normal Windows desktop.
        Enter-WinmarchyWin11Mode -ForceRepair
        $logPath = Join-Path (Get-WinmarchyLogDir) 'winmarchy.log'
        Write-Error ('Could not enter Omarchy mode (' + $reason + '); rolled back to Windows 11. Log: ' + $logPath)
    }
}

function Enter-WinmarchyWin11Mode {
    # Returns to stock Windows 11. Defined as the absence of Winmarchy
    # runtime effects. Idempotent and tolerant of any half-state: every step
    # checks before acting and tolerates the target already being true.
    [CmdletBinding()]
    param(
        [switch]$ForceRepair
    )

    Write-WinmarchyLog -Message 'enter-win11: begin'
    $state = Get-WinmarchyState
    $failures = @()

    # Step: stop GlazeWM (graceful wm-exit, then force).
    try {
        if (Test-WinmarchyProcessRunning -Name 'glazewm') {
            Stop-WinmarchyGlazewm
        }
    } catch {
        $failures = $failures + ('glazewm: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: glazewm stop failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: stop yasb (yasbc stop, then force).
    try {
        if (Test-WinmarchyProcessRunning -Name 'yasb') {
            Stop-WinmarchyYasb
        }
    } catch {
        $failures = $failures + ('yasb: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: yasb stop failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: taskbar back to always visible.
    try {
        if (Get-WinmarchyTaskbarAutoHide) {
            Set-WinmarchyTaskbarAutoHide -Enabled $false
        }
    } catch {
        $failures = $failures + ('taskbar: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: taskbar restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: desktop icons back on.
    try {
        if (-not (Get-WinmarchyDesktopIconsVisible)) {
            Set-WinmarchyDesktopIcons -Visible $true
        }
    } catch {
        $failures = $failures + ('icons: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: icon restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: restore the captured Windows wallpaper.
    try {
        if ($state.savedWallpaper) {
            Set-WinmarchyWallpaper -Path $state.savedWallpaper
        }
    } catch {
        $failures = $failures + ('wallpaper: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: wallpaper restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: restore the captured lock screen picture.
    try {
        if ($state.savedLockScreen) {
            Set-WinmarchyLockScreenImage -Path $state.savedLockScreen
        }
    } catch {
        $failures = $failures + ('lock-screen: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: lock screen restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: restore the captured light/dark app mode.
    try {
        if ($null -ne $state.savedAppsUseLightTheme) {
            Set-WinmarchyAppsTheme -AppsUseLightTheme $state.savedAppsUseLightTheme -SystemUsesLightTheme $state.savedSystemUsesLightTheme
        }
    } catch {
        $failures = $failures + ('apps-theme: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: app theme restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: put Alacritty's config back, or remove the one Winmarchy wrote.
    try {
        $alacrittyPath = Get-WinmarchyAlacrittyConfigPath
        if ($alacrittyPath) {
            $null = Restore-AlacrittyConfigFile -Path $alacrittyPath
        }
    } catch {
        $failures = $failures + ('alacritty: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: alacritty restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: put Windows Terminal back. The colour scheme and font face are a
    # visible Winmarchy effect, so Windows 11 mode must not carry them.
    try {
        $wtPath = Get-WtSettingsPath
        if ($wtPath) {
            $null = Restore-WtSettingsFile -Path $wtPath -OriginalColorScheme $state.savedWtColorScheme -OriginalFontFace $state.savedWtFontFace
        }
    } catch {
        $failures = $failures + ('windows-terminal: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: terminal restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Step: put Cursor's colours back to whatever they were.
    try {
        $cursorPath = Get-WinmarchyCursorSettingsPath
        if ($cursorPath) {
            $null = Restore-CursorSettingsFile -Path $cursorPath -HadCustomisations ([bool]$state.savedCursorHadColours) -OriginalColours $state.savedCursorColours
        }
    } catch {
        $failures = $failures + ('cursor: ' + $_.Exception.Message)
        Write-WinmarchyLog -Message ('enter-win11: cursor restore failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # Commit. The journal is cleared because the baseline has been re-asserted
    # wholesale; there is nothing left to undo. The captured baseline values
    # are cleared too, so the NEXT enter-omarchy recaptures whatever the user
    # has set in the meantime instead of reverting to a stale snapshot.
    Clear-WinmarchyJournal
    Set-WinmarchyStateValue -Name 'mode' -Value 'win11'
    Set-WinmarchyStateValue -Name 'lastMode' -Value 'win11'
    Set-WinmarchyStateValue -Name 'savedWallpaper' -Value $null
    Set-WinmarchyStateValue -Name 'savedAppsUseLightTheme' -Value $null
    Set-WinmarchyStateValue -Name 'savedSystemUsesLightTheme' -Value $null
    Set-WinmarchyStateValue -Name 'savedLockScreen' -Value $null
    # savedWtColorScheme and savedWtFontFace are deliberately kept: they record
    # the terminal as it was before Winmarchy ever touched it, and the restore
    # above has just put those values back, so the next Omarchy entry would
    # otherwise capture its own settings as the baseline.
    if ($failures.Count -eq 0) {
        Write-WinmarchyLog -Message 'enter-win11: committed clean'
        Write-Output 'Windows 11 mode restored.'
    } else {
        Write-WinmarchyLog -Message ('enter-win11: committed with ' + $failures.Count + ' step failures') -Level 'WARN'
        Write-Warning ('Windows 11 mode restored with warnings: ' + ($failures -join '; '))
    }
}

function Invoke-WinmarchyRepair {
    # Replays outstanding undo journal entries in reverse, then re-asserts
    # the recorded mode's full state (build brief Sections 7.2 and 10).
    [CmdletBinding()]
    param()

    $entries = @(Get-WinmarchyJournalEntries)
    if ($entries.Count -gt 0) {
        Write-WinmarchyLog -Message ('repair: replaying ' + $entries.Count + ' journal entries in reverse') -Level 'WARN'
        for ($i = $entries.Count - 1; $i -ge 0; $i--) {
            $entry = $entries[$i]
            try {
                switch ($entry.action) {
                    'glazewm-started' { Stop-WinmarchyGlazewm }
                    'yasb-started' { Stop-WinmarchyYasb }
                    'taskbar-autohide' { Set-WinmarchyTaskbarAutoHide -Enabled ([bool]$entry.data.previous) }
                    'icons-hidden' { Set-WinmarchyDesktopIcons -Visible ([bool]$entry.data.previous) }
                    'wallpaper-set' { Set-WinmarchyWallpaper -Path $entry.data.previous }
                    'apps-theme-set' { Set-WinmarchyAppsTheme -AppsUseLightTheme $entry.data.previousApps -SystemUsesLightTheme $entry.data.previousSystem }
                    'lock-screen-set' { Set-WinmarchyLockScreenImage -Path $entry.data.previous }
                    default { Write-WinmarchyLog -Message ('repair: unknown journal action ' + $entry.action) -Level 'WARN' }
                }
            } catch {
                Write-WinmarchyLog -Message ('repair: undo of ' + $entry.action + ' failed: ' + $_.Exception.Message) -Level 'ERROR'
            }
        }
        Clear-WinmarchyJournal
    }

    # Re-assert the recorded mode in full.
    $state = Get-WinmarchyState
    if ($state.mode -eq 'omarchy') {
        Enter-WinmarchyOmarchyMode
    } else {
        Enter-WinmarchyWin11Mode
    }
}

function Set-WinmarchyLockScreenMode {
    # "winmarchy lockscreen on|off|status". Opt-in, because a themed lock
    # screen is the one Winmarchy surface that cannot be restored exactly:
    # switching it back puts the original picture back, but a machine that was
    # on Windows Spotlight or a slideshow stays on "Picture" afterwards. So
    # turning it on requires a picture that can be captured first, and saying
    # so plainly is part of the deal.
    [CmdletBinding()]
    param([string]$Action = 'status')

    $state = Get-WinmarchyState
    if ($Action -eq 'on') {
        Assert-WinmarchyWindows -Operation 'Lock screen theming'
        $current = Get-WinmarchyCurrentLockScreenImage
        if (-not $current) {
            throw 'Windows is showing Spotlight or a slideshow on the lock screen, and Winmarchy cannot put those back afterwards. Open Settings > Personalisation > Lock screen, choose Picture, then run this again.'
        }
        Set-WinmarchyStateValue -Name 'savedLockScreen' -Value $current
        Set-WinmarchyStateValue -Name 'lockScreenEnabled' -Value $true
        Write-Output ('Lock screen theming on. Your current picture is remembered: ' + $current)
        if ($state.mode -eq 'omarchy') {
            Set-WinmarchyTheme -Name $state.theme
            Write-Output 'Applied now. Press Win+L to see it.'
        } else {
            Write-Output 'It applies the next time you enter Omarchy mode, and is put back when you leave it.'
        }
        return
    }

    if ($Action -eq 'off') {
        Assert-WinmarchyWindows -Operation 'Lock screen theming'
        if ($state.savedLockScreen) {
            try {
                Set-WinmarchyLockScreenImage -Path $state.savedLockScreen
                Write-Output ('Lock screen put back to ' + $state.savedLockScreen)
            } catch {
                Write-Warning ('Could not put the lock screen back: ' + $_.Exception.Message)
            }
        }
        Set-WinmarchyStateValue -Name 'lockScreenEnabled' -Value $false
        Set-WinmarchyStateValue -Name 'savedLockScreen' -Value $null
        Write-Output 'Lock screen theming off; Winmarchy will not touch it again.'
        return
    }

    $flag = 'off'
    if ($state.lockScreenEnabled) { $flag = 'on' }
    Write-Output ('lock screen theming: ' + $flag)
    if ($state.savedLockScreen) {
        Write-Output ('remembered original:  ' + $state.savedLockScreen)
    }
    Write-Output 'The sign-in screen uses the lock screen picture, so this themes both.'
    Write-Output 'Choosing a mode from the sign-in screen itself is not possible without an'
    Write-Output 'administrator-installed credential provider, which Winmarchy will not do.'
}

function Get-WinmarchyStatus {
    [CmdletBinding()]
    param()
    $state = Get-WinmarchyState
    Write-Output ('mode:    ' + $state.mode)
    Write-Output ('theme:   ' + $state.theme)
    Write-Output ('journal: ' + (@(Get-WinmarchyJournalEntries).Count) + ' pending entries')
    foreach ($processName in @('glazewm', 'yasb', 'Flow.Launcher')) {
        $running = Test-WinmarchyProcessRunning -Name $processName
        $label = 'stopped'
        if ($running) { $label = 'running' }
        Write-Output ($processName + ': ' + $label)
    }
}

function Invoke-WinmarchyDoctor {
    # Prints a pass/fail health table. -Json emits the same rows as JSON for
    # the test suite.
    [CmdletBinding()]
    param(
        [switch]$Json
    )
    $state = Get-WinmarchyState
    $rows = @()

    function New-DoctorRow {
        param([string]$Check, [bool]$Pass, [string]$Detail)
        return [pscustomobject]@{ check = $Check; pass = $Pass; detail = $Detail }
    }

    $rows = $rows + (New-DoctorRow 'state file' (Test-Path (Get-WinmarchyStatePath)) (Get-WinmarchyStatePath))
    $rows = $rows + (New-DoctorRow 'journal empty' (-not (Test-WinmarchyJournalPending)) (Get-WinmarchyJournalPath))
    $rows = $rows + (New-DoctorRow 'recorded mode valid' ($state.mode -eq 'win11' -or $state.mode -eq 'omarchy') $state.mode)
    $rows = $rows + (New-DoctorRow 'theme exists' ((Get-WinmarchyThemeNames) -contains $state.theme) $state.theme)

    $glazeConfig = Get-WinmarchyGlazewmConfigPath
    $rows = $rows + (New-DoctorRow 'glazewm config present' (Test-Path $glazeConfig) $glazeConfig)
    $yasbConfig = Join-Path (Get-WinmarchyYasbConfigDir) 'config.yaml'
    $rows = $rows + (New-DoctorRow 'yasb config present' (Test-Path $yasbConfig) $yasbConfig)
    $yasbStyles = Join-Path (Get-WinmarchyYasbConfigDir) 'styles.css'
    $rows = $rows + (New-DoctorRow 'yasb styles present' (Test-Path $yasbStyles) $yasbStyles)

    $glazewmOnPath = $null -ne (Find-WinmarchyExecutable -Name 'glazewm')
    $rows = $rows + (New-DoctorRow 'glazewm resolvable' $glazewmOnPath 'Get-Command glazewm plus standard install dirs')
    $yasbcOnPath = $null -ne (Find-WinmarchyExecutable -Name 'yasbc')
    $rows = $rows + (New-DoctorRow 'yasbc resolvable' $yasbcOnPath 'Get-Command yasbc plus standard install dirs')

    $expectedProcesses = ($state.mode -eq 'omarchy')
    $rows = $rows + (New-DoctorRow ('glazewm ' + $(if ($expectedProcesses) { 'running' } else { 'stopped' })) ((Test-WinmarchyProcessRunning -Name 'glazewm') -eq $expectedProcesses) ('mode is ' + $state.mode))
    $rows = $rows + (New-DoctorRow ('yasb ' + $(if ($expectedProcesses) { 'running' } else { 'stopped' })) ((Test-WinmarchyProcessRunning -Name 'yasb') -eq $expectedProcesses) ('mode is ' + $state.mode))

    $taskbarAutoHide = Get-WinmarchyTaskbarAutoHide
    $rows = $rows + (New-DoctorRow 'taskbar state matches mode' ($taskbarAutoHide -eq $expectedProcesses) ('auto-hide is ' + $taskbarAutoHide))
    $iconsVisible = Get-WinmarchyDesktopIconsVisible
    $rows = $rows + (New-DoctorRow 'icon state matches mode' ($iconsVisible -ne $expectedProcesses) ('visible is ' + $iconsVisible))

    $wtPath = Get-WtSettingsPath
    if ($wtPath) {
        $wtPatched = $false
        try {
            $wtSettings = ConvertFrom-WtSettingsJson -RawText ([System.IO.File]::ReadAllText($wtPath))
            if (Test-PsObjectProperty $wtSettings 'schemes') {
                foreach ($scheme in @($wtSettings.schemes)) {
                    if ($null -ne $scheme -and $scheme.name -like 'Winmarchy *') { $wtPatched = $true }
                }
            }
        } catch {
            $wtPatched = $false
        }
        $rows = $rows + (New-DoctorRow 'wt settings patched' $wtPatched $wtPath)
    } else {
        $rows = $rows + (New-DoctorRow 'wt settings found' $false 'Windows Terminal has never run; theme skips it')
    }

    # The chooser chain, end to end. Everything between "the installer said it
    # worked" and "something appears at login" is checked separately, because a
    # break anywhere in it used to look identical: a login where nothing
    # happened.
    $payload = Test-WinmarchyChooserPayload
    $payloadDetail = $payload.ExePath
    if (-not $payload.Ok) { $payloadDetail = 'missing: ' + ($payload.Missing -join ', ') }
    $rows = $rows + (New-DoctorRow 'chooser installed' $payload.Ok $payloadDetail)

    $runKeyValue = Get-WinmarchyRunKeyValue
    $runKeyOk = $false
    $runKeyDetail = 'not set; the chooser will not appear at login'
    if ($runKeyValue) {
        $runKeyDetail = $runKeyValue
        $runKeyTarget = $runKeyValue.Trim('"')
        $runKeyOk = (Test-Path $runKeyTarget)
        if (-not $runKeyOk) { $runKeyDetail = $runKeyValue + ' (that file does not exist)' }
    }
    $rows = $rows + (New-DoctorRow 'run key autostart' $runKeyOk $runKeyDetail)

    $startupDisabled = Test-WinmarchyStartupDisabledByWindows
    $startupDetail = 'enabled in Settings > Apps > Startup'
    if ($startupDisabled) { $startupDetail = 'switched OFF in Settings > Apps > Startup; turn Winmarchy back on there' }
    $rows = $rows + (New-DoctorRow 'startup entry enabled' (-not $startupDisabled) $startupDetail)

    $hasWebView2 = Test-WinmarchyWebView2Runtime
    $webViewDetail = 'Evergreen runtime found'
    if (-not $hasWebView2) { $webViewDetail = 'not found; the chooser falls back to its plain window. Install from https://developer.microsoft.com/microsoft-edge/webview2/' }
    $rows = $rows + (New-DoctorRow 'webview2 runtime' $hasWebView2 $webViewDetail)

    $trayValue = Get-WinmarchyRunKeyValue -Name 'WinmarchyTray'
    $trayDetail = 'not set; no Winmarchy icon in the notification area'
    if ($trayValue) { $trayDetail = $trayValue }
    $rows = $rows + (New-DoctorRow 'tray autostart' ([bool]$trayValue) $trayDetail)

    if ($state.lockScreenEnabled) {
        $lockDetail = 'on, original captured: ' + $state.savedLockScreen
        $lockOk = [bool]$state.savedLockScreen
        if (-not $lockOk) { $lockDetail = 'on, but no original captured yet (captured on entering Omarchy mode)' }
        $rows = $rows + (New-DoctorRow 'lock screen theming' $lockOk $lockDetail)
    }

    if ($Json) {
        Write-Output ($rows | ConvertTo-Json -Depth 4)
    } else {
        foreach ($row in $rows) {
            $mark = 'FAIL'
            if ($row.pass) { $mark = 'ok  ' }
            Write-Output ($mark + '  ' + $row.check.PadRight(28) + ' ' + $row.detail)
        }
        $failCount = @($rows | Where-Object { -not $_.pass }).Count
        Write-Output ''
        Write-Output ('doctor: ' + (@($rows).Count - $failCount) + ' passed, ' + $failCount + ' failed')
    }
}
