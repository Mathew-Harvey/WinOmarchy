# theme-set.ps1: applies a theme to every surface. Defines functions only;
# the dispatcher dot-sources this after lib/common.ps1.
# Surface order from the build brief Section 5. Every step is independent:
# a failure is logged and the remaining surfaces still apply.

function Set-WinmarchyTheme {
    # -AsOmarchy forces the Omarchy-only surfaces (wallpaper, app mode) even
    # though state.mode still reads win11; enter-omarchy needs that because
    # mode is only committed after the health check passes.
    # -SetTerminalFont additionally sets profiles.defaults.font.face; the
    # installer passes it (the brief sets the font on install only).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AsOmarchy,
        [switch]$SetTerminalFont
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

    # 3. Windows Terminal: patch settings.json (skip when WT has never run).
    try {
        $wtPath = Get-WtSettingsPath
        if ($wtPath) {
            $null = Update-WtSettingsFile -Path $wtPath -Theme $theme -SetFontFace:$SetTerminalFont
            Write-WinmarchyLog -Message 'theme-set: windows terminal patched'
        } else {
            Write-WinmarchyLog -Message 'theme-set: windows terminal has never run; skipped' -Level 'WARN'
        }
    } catch {
        $stepFailures = $stepFailures + 'windows-terminal'
        Write-WinmarchyLog -Message ('theme-set: windows terminal step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 4. Neovim: write the plugin spec, only when a LazyVim config exists.
    try {
        $nvimPluginsDir = Join-Path (Get-WinmarchyNvimConfigDir) (Join-Path 'lua' 'plugins')
        if (Test-Path $nvimPluginsDir) {
            $nvimTemplate = [System.IO.File]::ReadAllText((Join-Path (Get-WinmarchyTemplatesDir) 'nvim-theme.lua.tpl'))
            $nvimRendered = Expand-WinmarchyTemplate -Template $nvimTemplate -Tokens $tokens
            Write-WinmarchyTextFile -Path (Join-Path $nvimPluginsDir 'winmarchy-theme.lua') -Content $nvimRendered
            Write-WinmarchyLog -Message 'theme-set: nvim theme written'
        } else {
            Write-WinmarchyLog -Message 'theme-set: no nvim plugins directory; skipped' -Level 'WARN'
        }
    } catch {
        $stepFailures = $stepFailures + 'nvim'
        Write-WinmarchyLog -Message ('theme-set: nvim step failed: ' + $_.Exception.Message) -Level 'ERROR'
    }

    # 5. Wallpaper: generate once per theme, then apply. Only meaningful in
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

    # 6. Windows app mode: dark for dark themes, light for rose-pine. Only in
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

    # 7. Record the theme in state.
    Set-WinmarchyStateValue -Name 'theme' -Value $Name

    if ($stepFailures.Count -gt 0) {
        Write-Warning ('Theme applied with failed steps: ' + ($stepFailures -join ', ') + '. See the log.')
    }
}
