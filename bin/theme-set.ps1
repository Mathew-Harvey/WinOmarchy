# theme-set.ps1: applies a theme to every surface. Defines functions only;
# the dispatcher dot-sources this after lib/common.ps1.
# Surface order from the build brief Section 5. Every step is independent:
# a failure is logged and the remaining surfaces still apply.

function Set-WinmarchyTheme {
    # -AsOmarchy forces the Omarchy-only surfaces (wallpaper, app mode) even
    # though state.mode still reads win11; enter-omarchy needs that because
    # mode is only committed after the health check passes.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AsOmarchy
    )

    $theme = Get-WinmarchyTheme -Name $Name
    $tokens = Get-WinmarchyThemeTokens -Theme $theme
    Write-WinmarchyLog -Message ('theme-set: applying ' + $Name)
    $stepFailures = @()
    $omarchyActive = $AsOmarchy
    if (-not $omarchyActive) {
        $omarchyActive = ((Get-WinmarchyState).mode -eq 'omarchy')
    }

    # 1. yasb: render the stylesheet template; the watcher hot-reloads it.
    try {
        $templatePath = Get-WinmarchyYasbStylesTemplatePath
        $template = [System.IO.File]::ReadAllText($templatePath)
        $rendered = Expand-WinmarchyTemplate -Template $template -Tokens $tokens
        $stylesPath = Join-Path (Get-WinmarchyYasbConfigDir) 'styles.css'
        Write-WinmarchyTextFile -Path $stylesPath -Content $rendered
        Write-WinmarchyLog -Message 'theme-set: yasb styles written'
    } catch {
        $stepFailures = $stepFailures + 'yasb'
        Write-WinmarchyLog -Message ('theme-set: yasb step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 2. GlazeWM: swap the border colours on the marker lines, then reload.
    try {
        $glazeConfigPath = Get-WinmarchyGlazewmConfigPath
        if (Test-Path $glazeConfigPath) {
            $configText = [System.IO.File]::ReadAllText($glazeConfigPath)
            $newText = Update-WinmarchyGlazewmBorders -ConfigText $configText -Theme $theme
            if ($newText -ne $configText) {
                Write-WinmarchyTextFile -Path $glazeConfigPath -Content $newText
            }
            if (Test-WinmarchyProcessRunning -Name 'glazewm') {
                Invoke-WinmarchyGlazewmCommand -Command 'wm-reload-config'
            }
            Write-WinmarchyLog -Message 'theme-set: glazewm borders updated'
        } else {
            Write-WinmarchyLog -Message ('theme-set: glazewm config not found at ' + $glazeConfigPath + '; skipped') -Level 'WARN'
        }
    } catch {
        $stepFailures = $stepFailures + 'glazewm'
        Write-WinmarchyLog -Message ('theme-set: glazewm step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 3. Alacritty: the terminal Winmarchy launches. Omarchy mode only, and
    # enter-win11 puts the user's own config back (see mode.ps1).
    try {
        if ($omarchyActive) {
            $alacrittyPath = Get-WinmarchyAlacrittyConfigPath
            if ($alacrittyPath) {
                $null = Update-AlacrittyConfigFile -Path $alacrittyPath -Theme $theme
                Write-WinmarchyLog -Message 'theme-set: alacritty config written'
            }
        }
    } catch {
        $stepFailures = $stepFailures + 'alacritty'
        Write-WinmarchyLog -Message ('theme-set: alacritty step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 4. Windows Terminal: still themed, so the terminal Windows opens from
    # its own menus matches even though Alacritty is the one Winmarchy
    # launches. Omarchy mode only; entering win11 restores it (see mode.ps1).
    try {
        if ($omarchyActive) {
            $wtPath = Get-WtSettingsPath
            if ($wtPath) {
                $result = Update-WtSettingsFile -Path $wtPath -Theme $theme -SetFontFace
                # Capture the pre-Winmarchy values once, on the first patch,
                # so the restore on the way out is exact.
                if (-not (Get-WinmarchyState).savedWtCaptured) {
                    # Poison guard: if the value already there is Winmarchy's
                    # own (an old build themed the terminal unconditionally,
                    # or a swap was interrupted), capturing it as "the user's
                    # setting" would restore the Omarchy look into Windows
                    # mode forever. A Winmarchy value is treated as no
                    # baseline, so the restore strips it instead (FLAG-34).
                    $originalScheme = $result.OriginalColorScheme
                    if ($originalScheme -like 'Winmarchy *') { $originalScheme = $null }
                    $originalFont = $result.OriginalFontFace
                    if ($originalFont -eq 'JetBrainsMono Nerd Font') { $originalFont = $null }
                    Set-WinmarchyStateValue -Name 'savedWtColorScheme' -Value $originalScheme
                    Set-WinmarchyStateValue -Name 'savedWtFontFace' -Value $originalFont
                    Set-WinmarchyStateValue -Name 'savedWtCaptured' -Value $true
                }
                Write-WinmarchyLog -Message 'theme-set: windows terminal patched'
            } else {
                Write-WinmarchyLog -Message 'theme-set: windows terminal has never run; skipped' -Level 'WARN'
            }
        }
    } catch {
        $stepFailures = $stepFailures + 'windows-terminal'
        Write-WinmarchyLog -Message ('theme-set: windows terminal step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 5. Cursor: only in Omarchy mode, and only once Cursor has run at least
    # once. enter-win11 puts the colours back (see mode.ps1).
    try {
        if ($omarchyActive) {
            $cursorPath = Get-WinmarchyCursorSettingsPath
            if ($cursorPath) {
                $cursorResult = Update-CursorSettingsFile -Path $cursorPath -Theme $theme
                if (-not (Get-WinmarchyState).savedCursorCaptured) {
                    # Same poison guard as the terminal: colours matching one
                    # of the shipped themes are Winmarchy's own leftovers,
                    # not the user's customisation (FLAG-34).
                    $originalColours = $cursorResult.OriginalColours
                    $hadColours = $cursorResult.HadCustomisations
                    if ($hadColours -and (Test-WinmarchyCursorColoursAreOurs -Colours $originalColours)) {
                        $originalColours = $null
                        $hadColours = $false
                    }
                    Set-WinmarchyStateValue -Name 'savedCursorColours' -Value $originalColours
                    Set-WinmarchyStateValue -Name 'savedCursorHadColours' -Value $hadColours
                    Set-WinmarchyStateValue -Name 'savedCursorCaptured' -Value $true
                }
                Write-WinmarchyLog -Message 'theme-set: cursor colours written'
            } else {
                Write-WinmarchyLog -Message 'theme-set: cursor has never run; skipped' -Level 'WARN'
            }
        }
    } catch {
        $stepFailures = $stepFailures + 'cursor'
        Write-WinmarchyLog -Message ('theme-set: cursor step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 6. Wallpaper. With a wallpaper folder configured, a theme change deals
    # a fresh random picture from it, in either mode (the folder is the
    # user's explicit choice; see the note above Get-WinmarchyWallpaperFolder).
    # Without one, the generated theme wallpaper applies in Omarchy mode only
    # and win11 mode's wallpaper stays untouched.
    try {
        $wallpaperFolder = Get-WinmarchyWallpaperFolder
        if ($wallpaperFolder) {
            $null = Invoke-WinmarchyWallpaperNext
            Write-WinmarchyLog -Message 'theme-set: wallpaper dealt from the folder'
        } elseif ($omarchyActive) {
            $wallpaperPath = Join-Path (Get-WinmarchyWallpaperDir) ($Name + '.png')
            if (-not (Test-Path $wallpaperPath)) {
                New-WinmarchyWallpaperImage -Theme $theme -Path $wallpaperPath
            }
            Set-WinmarchyWallpaper -Path $wallpaperPath
            Write-WinmarchyLog -Message 'theme-set: wallpaper applied'
        }
    } catch {
        $stepFailures = $stepFailures + 'wallpaper'
        Write-WinmarchyLog -Message ('theme-set: wallpaper step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 7. Windows app mode: dark for dark themes, light for rose-pine. Only in
    # Omarchy mode; win11 mode keeps the user's own setting.
    try {
        if ($omarchyActive) {
            $light = 0
            if ($theme.mode -eq 'light') { $light = 1 }
            Set-WinmarchyAppsTheme -AppsUseLightTheme $light -SystemUsesLightTheme $light
            Write-WinmarchyLog -Message ('theme-set: app mode set to ' + $theme.mode)
        }
    } catch {
        $stepFailures = $stepFailures + 'app-mode'
        Write-WinmarchyLog -Message ('theme-set: app mode step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 8. Lock screen, which is also the sign-in screen backdrop. Opt in only
    # ("winmarchy lockscreen on"), because unlike a wallpaper it cannot be put
    # back to Windows Spotlight or a slideshow once changed; see the note in
    # lib/common.ps1. Omarchy mode only, and enter-win11 restores it.
    try {
        if ($omarchyActive -and (Get-WinmarchyState).lockScreenEnabled) {
            $lockPath = Get-WinmarchyLockScreenImagePath -ThemeName $Name
            if (-not (Test-Path $lockPath)) {
                New-WinmarchyLockScreenImage -Theme $theme -Path $lockPath
            }
            Set-WinmarchyLockScreenImage -Path $lockPath
            Write-WinmarchyLog -Message 'theme-set: lock screen applied'
        }
    } catch {
        $stepFailures = $stepFailures + 'lock-screen'
        Write-WinmarchyLog -Message ('theme-set: lock screen step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 9. Record the theme in state.
    Set-WinmarchyStateValue -Name 'theme' -Value $Name

    if ($stepFailures.Count -gt 0) {
        Write-Warning ('Theme applied with failed steps: ' + ($stepFailures -join ', ') + '. See the log.')
    }
}
