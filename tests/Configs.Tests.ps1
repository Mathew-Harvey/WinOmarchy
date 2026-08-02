# Pester tests for the Winmarchy configs (Phase 2).
# Cross-checks every GlazeWM command string and key token against the
# vocabulary verified from the GlazeWM source (ref/glazewm), validates the
# yasb config structure against the shapes verified from ref/yasb, and
# renders the yasb stylesheet template for all eight themes into
# artifacts/rendered/ where check.ps1 rescans them for unresolved tokens.

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    Import-Module powershell-yaml

    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:glazeConfigPath = Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))
    $script:yasbConfigPath = Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'yasb' 'config.yaml'))
    $script:stylesTemplatePath = Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'yasb' 'styles.template.css'))

    $script:glazeConfig = ConvertFrom-Yaml ([System.IO.File]::ReadAllText($script:glazeConfigPath))
    $script:yasbConfig = ConvertFrom-Yaml ([System.IO.File]::ReadAllText($script:yasbConfigPath))

    # Key token vocabulary verified from
    # ref/glazewm/packages/wm-platform/src/models/key.rs (impl_key_parsing!).
    $script:validKeyTokens = @()
    foreach ($c in ([char]'a')..([char]'z')) { $script:validKeyTokens = $script:validKeyTokens + [string][char]$c }
    foreach ($d in 0..9) {
        $script:validKeyTokens = $script:validKeyTokens + [string]$d
        $script:validKeyTokens = $script:validKeyTokens + ('d' + $d)
        $script:validKeyTokens = $script:validKeyTokens + ('numpad' + $d)
    }
    foreach ($f in 1..24) { $script:validKeyTokens = $script:validKeyTokens + ('f' + $f) }
    $script:validKeyTokens = $script:validKeyTokens + @(
        'cmd', 'ctrl', 'control', 'alt', 'menu', 'shift', 'win',
        'lcmd', 'rcmd', 'lctrl', 'rctrl', 'lalt', 'lmenu', 'ralt', 'rmenu', 'lshift', 'rshift', 'lwin', 'rwin',
        'space', 'tab', 'enter', 'return', 'delete', 'escape', 'backspace',
        'left', 'right', 'up', 'down',
        'home', 'end', 'page_up', 'page_down', 'insert',
        'num_lock', 'scroll_lock', 'caps_lock',
        'numpad_add', 'add', 'numpad_subtract', 'subtract', 'numpad_multiply', 'multiply',
        'numpad_divide', 'divide', 'numpad_decimal', 'decimal',
        'volume_up', 'volume_down', 'volume_mute',
        'media_next_track', 'media_prev_track', 'media_stop', 'media_play_pause', 'print_screen',
        'oem_semicolon', 'oem_question', 'oem_tilde', 'oem_open_brackets', 'oem_pipe',
        'oem_close_brackets', 'oem_quotes', 'oem_8', 'oem_102', 'oem_plus', 'oem_comma',
        'oem_minus', 'oem_period', 'muhenkan', 'henkan'
    )

    # Command patterns verified from the brief Section 4.2 and
    # ref/glazewm/packages/wm-common/src/app_command.rs.
    $script:validCommandPatterns = @(
        '^focus --direction (left|right|up|down)$',
        '^focus --workspace [0-9]+$',
        '^focus --next-active-workspace$',
        '^focus --prev-active-workspace$',
        '^focus --recent-workspace$',
        '^move --direction (left|right|up|down)$',
        '^move --workspace [0-9]+$',
        '^move-workspace --direction (left|right|up|down)$',
        '^resize --(width|height) [+-][0-9]+%$',
        '^toggle-floating --centered$',
        '^toggle-tiling$',
        '^toggle-fullscreen$',
        '^toggle-minimized$',
        '^toggle-tiling-direction$',
        '^wm-cycle-focus$',
        '^wm-enable-binding-mode --name [a-z]+$',
        '^wm-disable-binding-mode --name [a-z]+$',
        '^wm-toggle-pause$',
        '^wm-reload-config$',
        '^wm-redraw$',
        '^wm-exit$',
        '^close$',
        '^ignore$',
        '^shell-exec .+$'
    )

    function Get-AllKeybindingEntries {
        $entries = @()
        foreach ($entry in $script:glazeConfig['keybindings']) { $entries = $entries + @(, $entry) }
        foreach ($bindingMode in $script:glazeConfig['binding_modes']) {
            foreach ($entry in $bindingMode['keybindings']) { $entries = $entries + @(, $entry) }
        }
        return $entries
    }

    function Test-CommandValid {
        param([string]$Command)
        foreach ($pattern in $script:validCommandPatterns) {
            if ($Command -match $pattern) { return $true }
        }
        return $false
    }
}

Describe 'GlazeWM config vocabulary' {
    It 'parses as YAML with every top-level section present' {
        foreach ($section in @('general', 'gaps', 'window_effects', 'window_behavior', 'workspaces', 'window_rules', 'binding_modes', 'keybindings')) {
            $script:glazeConfig.Keys | Should -Contain $section
        }
    }

    It 'uses only verified key tokens in every binding' {
        $entries = Get-AllKeybindingEntries
        @($entries).Count | Should -BeGreaterThan 40
        foreach ($entry in $entries) {
            foreach ($binding in $entry['bindings']) {
                foreach ($token in ($binding -split '\+')) {
                    $script:validKeyTokens | Should -Contain $token.Trim() -Because ('binding "' + $binding + '" uses token "' + $token + '"')
                }
            }
        }
    }

    It 'uses only verified command strings in every keybinding' {
        foreach ($entry in Get-AllKeybindingEntries) {
            foreach ($command in $entry['commands']) {
                Test-CommandValid -Command $command | Should -BeTrue -Because ('command "' + $command + '" must match the verified vocabulary')
            }
        }
    }

    It 'uses only verified command strings in window rules' {
        foreach ($rule in $script:glazeConfig['window_rules']) {
            foreach ($command in $rule['commands']) {
                Test-CommandValid -Command $command | Should -BeTrue -Because ('window rule command "' + $command + '" must match the verified vocabulary')
            }
        }
    }

    It 'never binds lwin+l because Windows reserves Win+L for lock' {
        foreach ($entry in Get-AllKeybindingEntries) {
            foreach ($binding in $entry['bindings']) {
                $binding | Should -Not -Be 'lwin+l'
            }
        }
    }

    It 'binds every combo at most once' {
        $seen = @{}
        foreach ($entry in $script:glazeConfig['keybindings']) {
            foreach ($binding in $entry['bindings']) {
                $normalised = (($binding -split '\+') | Sort-Object) -join '+'
                $seen.ContainsKey($normalised) | Should -BeFalse -Because ('binding "' + $binding + '" appears twice')
                $seen[$normalised] = $true
            }
        }
    }

    It 'carries the panic binding to Windows 11 mode' {
        $found = $false
        foreach ($entry in $script:glazeConfig['keybindings']) {
            if (@($entry['bindings']) -contains 'lwin+shift+x') {
                $found = $true
                $entry['commands'][0] | Should -Be 'shell-exec winmarchy mode win11'
            }
        }
        $found | Should -BeTrue
    }

    It 'defines nine workspaces named 1 to 9' {
        $names = @()
        foreach ($workspace in $script:glazeConfig['workspaces']) { $names = $names + $workspace['name'] }
        $names | Should -Be @('1', '2', '3', '4', '5', '6', '7', '8', '9')
    }

    It 'keeps the winmarchy border marker comments for the theme engine' {
        $raw = [System.IO.File]::ReadAllText($script:glazeConfigPath)
        $raw | Should -Match "color: '#[0-9a-fA-F]{6}' # winmarchy:focused-border"
        $raw | Should -Match "color: '#[0-9a-fA-F]{6}' # winmarchy:other-border"
    }

    It 'floats windows whose title starts with Winmarchy' {
        $found = $false
        foreach ($rule in $script:glazeConfig['window_rules']) {
            if ($rule['commands'][0] -eq 'toggle-floating --centered') {
                foreach ($match in $rule['match']) {
                    if ($match.ContainsKey('window_title')) {
                        if ($match['window_title']['regex'] -eq '^Winmarchy') { $found = $true }
                    }
                }
            }
        }
        $found | Should -BeTrue
    }
}

Describe 'yasb config structure' {
    It 'keeps the stylesheet watcher on so theme changes hot-reload' {
        $script:yasbConfig['watch_stylesheet'] | Should -BeTrue
    }

    It 'reserves screen space as a Windows app bar' {
        $script:yasbConfig['bars']['winmarchy-bar']['window_flags']['windows_app_bar'] | Should -BeTrue
    }

    It 'lays out the widgets exactly as specified' {
        $bar = $script:yasbConfig['bars']['winmarchy-bar']
        @($bar['widgets']['left']) | Should -Be @('menu_button', 'glazewm_workspaces', 'active_window')
        @($bar['widgets']['center']) | Should -Be @('clock')
        @($bar['widgets']['right']) | Should -Be @('cpu', 'memory', 'volume', 'systray', 'power_menu')
    }

    It 'defines every widget referenced by the bar' {
        $bar = $script:yasbConfig['bars']['winmarchy-bar']
        $referenced = @($bar['widgets']['left']) + @($bar['widgets']['center']) + @($bar['widgets']['right'])
        foreach ($name in $referenced) {
            $script:yasbConfig['widgets'].Keys | Should -Contain $name
        }
    }

    It 'uses only verified widget types' {
        $validTypes = @(
            'glazewm.workspaces.GlazewmWorkspacesWidget',
            'glazewm.binding_mode.GlazewmBindingModeWidget',
            'glazewm.tiling_direction.GlazewmTilingDirectionWidget',
            'yasb.clock.ClockWidget',
            'yasb.cpu.CpuWidget',
            'yasb.memory.MemoryWidget',
            'yasb.volume.VolumeWidget',
            'yasb.active_window.ActiveWindowWidget',
            'yasb.power_menu.PowerMenuWidget',
            'yasb.systray.SystrayWidget',
            'yasb.taskbar.TaskbarWidget',
            'yasb.custom.CustomWidget',
            'yasb.home.HomeWidget',
            'yasb.launchpad.LaunchpadWidget'
        )
        foreach ($widgetName in $script:yasbConfig['widgets'].Keys) {
            $validTypes | Should -Contain $script:yasbConfig['widgets'][$widgetName]['type']
        }
    }
}

Describe 'yasb stylesheet template' {
    It 'orders the focused_ rules after the active_ rules' {
        $template = [System.IO.File]::ReadAllText($script:stylesTemplatePath)
        $activePos = $template.IndexOf('.ws-btn.active_populated')
        $focusedPos = $template.IndexOf('.ws-btn.focused_populated')
        $activePos | Should -BeGreaterThan 0
        $focusedPos | Should -BeGreaterThan $activePos
        $activeEmptyPos = $template.IndexOf('.ws-btn.active_empty')
        $focusedEmptyPos = $template.IndexOf('.ws-btn.focused_empty')
        $focusedEmptyPos | Should -BeGreaterThan $activeEmptyPos
    }

    It 'renders for theme <_> with zero unresolved tokens into artifacts' -ForEach @('catppuccin', 'everforest', 'gruvbox', 'kanagawa', 'matte-black', 'nord', 'rose-pine', 'tokyo-night') {
        $template = [System.IO.File]::ReadAllText($script:stylesTemplatePath)
        $theme = Get-WinmarchyTheme -Name $_
        $rendered = Expand-WinmarchyTemplate -Template $template -Tokens (Get-WinmarchyThemeTokens -Theme $theme)
        $rendered.Contains('{{') | Should -BeFalse
        $rendered.Contains($theme.colors.accent) | Should -BeTrue
        $outDir = Join-Path $script:repoRoot (Join-Path 'artifacts' 'rendered')
        if (-not (Test-Path $outDir)) { $null = New-Item -ItemType Directory -Path $outDir -Force }
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $outDir ('styles-' + $_ + '.css')), $rendered, $encoding)
    }
}
