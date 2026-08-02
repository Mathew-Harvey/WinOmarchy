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
                    Set-WinmarchyStateValue -Name 'savedWtColorScheme' -Value $result.OriginalColorScheme
                    Set-WinmarchyStateValue -Name 'savedWtFontFace' -Value $result.OriginalFontFace
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
                    Set-WinmarchyStateValue -Name 'savedCursorColours' -Value $cursorResult.OriginalColours
                    Set-WinmarchyStateValue -Name 'savedCursorHadColours' -Value $cursorResult.HadCustomisations
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

    # 6. Wallpaper: generate once per theme, then apply. Only meaningful in
    # Omarchy mode; in win11 mode the user's wallpaper stays untouched.
    try {
        if ($omarchyActive) {
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

    # 8. Record the theme in state.
    Set-WinmarchyStateValue -Name 'theme' -Value $Name

    if ($stepFailures.Count -gt 0) {
        Write-Warning ('Theme applied with failed steps: ' + ($stepFailures -join ', ') + '. See the log.')
    }
}
