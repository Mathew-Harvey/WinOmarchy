# Pester tests for the Winmarchy theme engine core (Phase 1).
# Pure logic only: no Windows APIs, no real user profile. WINMARCHY_HOME is
# pointed at the Pester TestDrive so nothing touches the machine.

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    $script:fixturesDir = Join-Path $PSScriptRoot 'fixtures'
    $script:allThemeNames = @('catppuccin', 'everforest', 'gruvbox', 'kanagawa', 'matte-black', 'nord', 'rose-pine', 'tokyo-night')
    $script:paletteKeys = @(
        'accent', 'selection', 'muted',
        'background', 'dark_background', 'darker_background', 'lighter_background',
        'foreground', 'dark_foreground', 'light_foreground', 'bright_foreground',
        'red', 'yellow', 'orange', 'green', 'cyan', 'blue', 'magenta', 'brown',
        'bright_red', 'bright_yellow', 'bright_green', 'bright_cyan', 'bright_blue', 'bright_magenta'
    )
    $script:savedHome = $env:WINMARCHY_HOME
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
}

Describe 'Theme engine core' {
    BeforeEach {
        $env:WINMARCHY_HOME = Join-Path $TestDrive 'winmarchy-home'
    }

Describe 'Theme loading' {
    It 'lists exactly the eight themes in alphabetical order' {
        $names = @(Get-WinmarchyThemeNames)
        $names | Should -Be $script:allThemeNames
    }

    It 'loads theme <_> with every required key and all 25 palette colours' -ForEach @('catppuccin', 'everforest', 'gruvbox', 'kanagawa', 'matte-black', 'nord', 'rose-pine', 'tokyo-night') {
        $theme = Get-WinmarchyTheme -Name $_
        $theme.name | Should -Be $_
        $theme.mode | Should -BeIn @('dark', 'light')
        $theme.wt_scheme | Should -Match '^Winmarchy '
        $theme.nvim.plugin | Should -Not -BeNullOrEmpty
        $theme.nvim.colorscheme | Should -Not -BeNullOrEmpty
        foreach ($key in $script:paletteKeys) {
            $theme.colors.$key | Should -Match '^#[0-9a-fA-F]{6}$' -Because ('colour key ' + $key + ' must be a hex colour')
        }
        @($theme.colors.PSObject.Properties).Count | Should -Be 25
    }

    It 'throws on an unknown theme name' {
        { Get-WinmarchyTheme -Name 'no-such-theme' } | Should -Throw
    }

    It 'rose-pine is the only light theme' {
        $lightThemes = @()
        foreach ($name in (Get-WinmarchyThemeNames)) {
            $theme = Get-WinmarchyTheme -Name $name
            if ($theme.mode -eq 'light') { $lightThemes = $lightThemes + $name }
        }
        $lightThemes | Should -Be @('rose-pine')
    }
}

Describe 'Theme cycling' {
    It 'cycles alphabetically and wraps at the end' {
        Get-WinmarchyNextThemeName -Current 'catppuccin' | Should -Be 'everforest'
        Get-WinmarchyNextThemeName -Current 'tokyo-night' | Should -Be 'catppuccin'
    }
}

Describe 'Template renderer' {
    It 'renders the all-tokens fixture for theme <_> with zero unresolved tokens' -ForEach @('catppuccin', 'everforest', 'gruvbox', 'kanagawa', 'matte-black', 'nord', 'rose-pine', 'tokyo-night') {
        $template = [System.IO.File]::ReadAllText((Join-Path $script:fixturesDir 'all-tokens.template.css'))
        $theme = Get-WinmarchyTheme -Name $_
        $tokens = Get-WinmarchyThemeTokens -Theme $theme
        $rendered = Expand-WinmarchyTemplate -Template $template -Tokens $tokens
        $rendered.Contains('{{') | Should -BeFalse
        $rendered.Contains($theme.colors.accent) | Should -BeTrue
    }

    It 'throws and names the token when a placeholder is unresolved' {
        $theme = Get-WinmarchyTheme -Name 'tokyo-night'
        $tokens = Get-WinmarchyThemeTokens -Theme $theme
        { Expand-WinmarchyTemplate -Template 'x {{not_a_real_token}} y' -Tokens $tokens } | Should -Throw '*not_a_real_token*'
    }

    It 'builds the catppuccin nvim plugin spec with its alias name' {
        $theme = Get-WinmarchyTheme -Name 'catppuccin'
        $tokens = Get-WinmarchyThemeTokens -Theme $theme
        $tokens['nvim_plugin_spec'] | Should -Be '"catppuccin/nvim", name = "catppuccin"'
    }

    It 'builds a plain nvim plugin spec when there is no alias' {
        $theme = Get-WinmarchyTheme -Name 'tokyo-night'
        $tokens = Get-WinmarchyThemeTokens -Theme $theme
        $tokens['nvim_plugin_spec'] | Should -Be '"folke/tokyonight.nvim"'
    }

    It 'renders the nvim theme template into valid-looking lua for every theme' {
        $templatePath = Join-Path (Get-WinmarchyTemplatesDir) 'nvim-theme.lua.tpl'
        $template = [System.IO.File]::ReadAllText($templatePath)
        foreach ($name in (Get-WinmarchyThemeNames)) {
            $theme = Get-WinmarchyTheme -Name $name
            $rendered = Expand-WinmarchyTemplate -Template $template -Tokens (Get-WinmarchyThemeTokens -Theme $theme)
            $rendered.Contains('{{') | Should -BeFalse
            $rendered | Should -Match 'colorscheme = "'
        }
    }
}

Describe 'Windows Terminal scheme builder' {
    It 'builds the tokyo-night scheme exactly matching the expected fixture' {
        $expected = [System.IO.File]::ReadAllText((Join-Path $script:fixturesDir 'wt-scheme-tokyo-night.json')) | ConvertFrom-Json
        $theme = Get-WinmarchyTheme -Name 'tokyo-night'
        $built = New-WtSchemeObject -Theme $theme
        $expectedProps = @($expected.PSObject.Properties.Name)
        $builtProps = @($built.PSObject.Properties.Name)
        $builtProps.Count | Should -Be $expectedProps.Count
        foreach ($prop in $expectedProps) {
            $built.$prop | Should -Be $expected.$prop -Because ('scheme key ' + $prop + ' must match the fixture')
        }
    }
}

Describe 'Windows Terminal settings patcher' {
    It 'patches the clean fixture preserving unrelated keys and creating a backup' {
        $settingsPath = Join-Path $TestDrive 'settings.json'
        Copy-Item (Join-Path $script:fixturesDir 'wt-settings-clean.json') $settingsPath
        $original = [System.IO.File]::ReadAllText($settingsPath)
        $theme = Get-WinmarchyTheme -Name 'tokyo-night'

        $result = Update-WtSettingsFile -Path $settingsPath -Theme $theme -SetFontFace
        $result.BackupCreated | Should -BeTrue

        [System.IO.File]::ReadAllText($settingsPath + '.winmarchy-bak') | Should -Be $original

        $patched = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        $patched.profiles.defaults.colorScheme | Should -Be 'Winmarchy Tokyo Night'
        $patched.profiles.defaults.font.face | Should -Be 'JetBrainsMono Nerd Font'
        $patched.profiles.defaults.padding | Should -Be '8'
        $patched.defaultProfile | Should -Be '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
        $patched.copyOnSelect | Should -BeFalse
        $patched.copyFormatting | Should -Be 'none'
        @($patched.profiles.list).Count | Should -Be 2
        $patched.profiles.list[1].commandline | Should -Be 'cmd.exe'
        @($patched.actions).Count | Should -Be 2
        $patched.actions[0].keys | Should -Be 'ctrl+c'
        $patched.theme | Should -Be 'dark'

        $schemeNames = @()
        foreach ($scheme in $patched.schemes) { $schemeNames = $schemeNames + $scheme.name }
        $schemeNames | Should -Contain 'Campbell'
        $schemeNames | Should -Contain 'Winmarchy Tokyo Night'
        @($patched.schemes).Count | Should -Be 2
    }

    It 'parses the comment-laden fixture and replaces the stale scheme by name' {
        $settingsPath = Join-Path $TestDrive 'settings-comments.json'
        Copy-Item (Join-Path $script:fixturesDir 'wt-settings-comments.json') $settingsPath
        $theme = Get-WinmarchyTheme -Name 'tokyo-night'

        $null = Update-WtSettingsFile -Path $settingsPath -Theme $theme

        $patched = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        @($patched.schemes).Count | Should -Be 1
        $patched.schemes[0].name | Should -Be 'Winmarchy Tokyo Night'
        $patched.schemes[0].background | Should -Be '#1a1b26'
        $patched.schemes[0].brightBlack | Should -Be '#414868'
        $patched.copyOnSelect | Should -BeTrue
        $patched.defaultProfile | Should -Be '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
        $patched.profiles.list[0].name | Should -Be 'Windows PowerShell'
        $patched.theme | Should -Be 'system'
    }

    It 'parses the trailing-comma fixture preserving unrelated keys' {
        $settingsPath = Join-Path $TestDrive 'settings-commas.json'
        Copy-Item (Join-Path $script:fixturesDir 'wt-settings-trailing-commas.json') $settingsPath
        $theme = Get-WinmarchyTheme -Name 'nord'

        $null = Update-WtSettingsFile -Path $settingsPath -Theme $theme

        $patched = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        $patched.profiles.defaults.colorScheme | Should -Be 'Winmarchy Nord'
        $patched.profiles.defaults.padding | Should -Be '4'
        $patched.launchMode | Should -Be 'default'
        $patched.actions[0].command | Should -Be 'find'
        $patched.profiles.list[0].commandline | Should -Be 'powershell.exe'
        @($patched.schemes).Count | Should -Be 1
    }

    It 'aborts on the corrupt fixture writing nothing at all' {
        $settingsPath = Join-Path $TestDrive 'settings-corrupt.json'
        Copy-Item (Join-Path $script:fixturesDir 'wt-settings-corrupt.json') $settingsPath
        $original = [System.IO.File]::ReadAllText($settingsPath)
        $theme = Get-WinmarchyTheme -Name 'tokyo-night'

        { Update-WtSettingsFile -Path $settingsPath -Theme $theme } | Should -Throw '*could not be parsed*'

        [System.IO.File]::ReadAllText($settingsPath) | Should -Be $original
        Test-Path ($settingsPath + '.winmarchy-bak') | Should -BeFalse
    }

    It 'never overwrites an existing backup on later patches' {
        $settingsPath = Join-Path $TestDrive 'settings-repatch.json'
        Copy-Item (Join-Path $script:fixturesDir 'wt-settings-clean.json') $settingsPath
        $original = [System.IO.File]::ReadAllText($settingsPath)

        $first = Update-WtSettingsFile -Path $settingsPath -Theme (Get-WinmarchyTheme -Name 'tokyo-night')
        $second = Update-WtSettingsFile -Path $settingsPath -Theme (Get-WinmarchyTheme -Name 'gruvbox')

        $first.BackupCreated | Should -BeTrue
        $second.BackupCreated | Should -BeFalse
        [System.IO.File]::ReadAllText($settingsPath + '.winmarchy-bak') | Should -Be $original

        $patched = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        $patched.profiles.defaults.colorScheme | Should -Be 'Winmarchy Gruvbox'
        $schemeNames = @()
        foreach ($scheme in $patched.schemes) { $schemeNames = $schemeNames + $scheme.name }
        $schemeNames | Should -Contain 'Winmarchy Tokyo Night'
        $schemeNames | Should -Contain 'Winmarchy Gruvbox'
    }

    It 'wraps a legacy bare-array profiles form into the object form' {
        $settingsPath = Join-Path $TestDrive 'settings-legacy.json'
        $legacy = '{ "profiles": [ { "guid": "{aaa}", "name": "Legacy" } ], "schemes": [] }'
        [System.IO.File]::WriteAllText($settingsPath, $legacy, (New-Object System.Text.UTF8Encoding($false)))
        $theme = Get-WinmarchyTheme -Name 'tokyo-night'

        $null = Update-WtSettingsFile -Path $settingsPath -Theme $theme

        $patched = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        $patched.profiles.defaults.colorScheme | Should -Be 'Winmarchy Tokyo Night'
        @($patched.profiles.list).Count | Should -Be 1
        $patched.profiles.list[0].name | Should -Be 'Legacy'
    }
}

Describe 'State' {
    It 'returns defaults when no state file exists' {
        $state = Get-WinmarchyState
        $state.mode | Should -Be 'win11'
        $state.lastMode | Should -Be 'win11'
        $state.theme | Should -Be 'tokyo-night'
        $state.chooserDisabled | Should -BeFalse
    }

    It 'round-trips saved state and merges defaults for missing keys' {
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'
        Set-WinmarchyStateValue -Name 'theme' -Value 'nord'
        $state = Get-WinmarchyState
        $state.mode | Should -Be 'omarchy'
        $state.theme | Should -Be 'nord'
        $state.lastMode | Should -Be 'win11'
    }

    It 'stores the saved wallpaper path' {
        Set-WinmarchyStateValue -Name 'savedWallpaper' -Value 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
        (Get-WinmarchyState).savedWallpaper | Should -Be 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
    }
}

Describe 'Undo journal' {
    It 'reports no pending entries when the journal is absent' {
        Test-WinmarchyJournalPending | Should -BeFalse
        @(Get-WinmarchyJournalEntries).Count | Should -Be 0
    }

    It 'appends entries in order with action and data preserved' {
        Add-WinmarchyJournalEntry -Action 'taskbar-autohide' -Data @{ previous = 'visible' }
        Add-WinmarchyJournalEntry -Action 'icons-hide' -Data @{ previous = 'shown' }
        Test-WinmarchyJournalPending | Should -BeTrue
        $entries = @(Get-WinmarchyJournalEntries)
        $entries.Count | Should -Be 2
        $entries[0].action | Should -Be 'taskbar-autohide'
        $entries[0].data.previous | Should -Be 'visible'
        $entries[1].action | Should -Be 'icons-hide'
    }

    It 'clears the journal on commit' {
        Add-WinmarchyJournalEntry -Action 'wallpaper-set' -Data @{ previous = 'x.jpg' }
        Clear-WinmarchyJournal
        Test-WinmarchyJournalPending | Should -BeFalse
    }
}

Describe 'Review regression fixes' {
    It 'preserves one-element and empty arrays through a state round trip' {
        Set-WinmarchyStateValue -Name 'oneItem' -Value @('gruvbox')
        Set-WinmarchyStateValue -Name 'noItems' -Value @()
        $state = Get-WinmarchyState
        , $state['oneItem'] | Should -BeOfType [System.Array]
        @($state['oneItem']).Count | Should -Be 1
        $state['oneItem'][0] | Should -Be 'gruvbox'
        $null -eq $state['noItems'] | Should -BeFalse
        @($state['noItems']).Count | Should -Be 0
    }

    It 'never mutates string values while stripping comments and trailing commas' {
        $settingsPath = Join-Path $TestDrive 'settings-tricky.json'
        $tricky = @(
            '// leading comment forces the fallback parser',
            '{',
            '  "profiles": {',
            '    "defaults": {},',
            '    "list": [',
            '      { "name": "Tricky", "commandline": "cmd.exe /c echo {a,}" },',
            '      { "name": "Slashy", "commandline": "wsl.exe /mnt/c/*startup*/x" }',
            '    ]',
            '  },',
            '  "schemes": [],',
            '}'
        ) -join "`n"
        [System.IO.File]::WriteAllText($settingsPath, $tricky, (New-Object System.Text.UTF8Encoding($false)))

        $null = Update-WtSettingsFile -Path $settingsPath -Theme (Get-WinmarchyTheme -Name 'tokyo-night')

        $patched = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        $patched.profiles.list[0].commandline | Should -Be 'cmd.exe /c echo {a,}'
        $patched.profiles.list[1].commandline | Should -Be 'wsl.exe /mnt/c/*startup*/x'
        $patched.profiles.defaults.colorScheme | Should -Be 'Winmarchy Tokyo Night'
    }

    It 'skips a torn final journal line and still returns the intact entries' {
        Add-WinmarchyJournalEntry -Action 'taskbar-autohide' -Data @{ previous = $false }
        $journalPath = Get-WinmarchyJournalPath
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($journalPath, '{"ts":"2026-08-01","action":"wallpaper-set","da', $encoding)
        $entries = @(Get-WinmarchyJournalEntries)
        $entries.Count | Should -Be 1
        $entries[0].action | Should -Be 'taskbar-autohide'
        Test-WinmarchyJournalPending | Should -BeTrue
    }

    It 'falls back to defaults when the state file is torn' {
        Save-WinmarchyState -State (Get-WinmarchyDefaultState)
        $statePath = Get-WinmarchyStatePath
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($statePath, '{"mode": "omarchy", "the', $encoding)
        $state = Get-WinmarchyState
        $state.mode | Should -Be 'win11'
        # And the next save recovers the file.
        Set-WinmarchyStateValue -Name 'mode' -Value 'omarchy'
        (Get-WinmarchyState).mode | Should -Be 'omarchy'
    }

    It 'normalises null profiles, defaults and schemes in settings.json' {
        $settingsPath = Join-Path $TestDrive 'settings-nulls.json'
        $nulls = '{ "profiles": null, "schemes": null }'
        [System.IO.File]::WriteAllText($settingsPath, $nulls, (New-Object System.Text.UTF8Encoding($false)))
        $null = Update-WtSettingsFile -Path $settingsPath -Theme (Get-WinmarchyTheme -Name 'tokyo-night')
        $patched = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        $patched.profiles.defaults.colorScheme | Should -Be 'Winmarchy Tokyo Night'
        @($patched.schemes).Count | Should -Be 1
    }

    It 'cycles themes case-insensitively' {
        Get-WinmarchyNextThemeName -Current 'Gruvbox' | Should -Be 'kanagawa'
    }

    It 'rejects a theme with a null or malformed colour value' {
        $badDir = Join-Path $TestDrive 'bad-themes'
        $null = New-Item -ItemType Directory -Path $badDir -Force
        # Build a broken copy of tokyo-night in a fake themes dir layout.
        $fakeRoot = Join-Path $TestDrive 'fake-root'
        $null = New-Item -ItemType Directory -Path (Join-Path $fakeRoot 'themes') -Force
        $raw = [System.IO.File]::ReadAllText((Join-Path (Get-WinmarchyThemesDir) 'tokyo-night.json'))
        $broken = $raw.Replace('"red": "#f7768e"', '"red": null')
        [System.IO.File]::WriteAllText((Join-Path (Join-Path $fakeRoot 'themes') 'broken.json'), $broken, (New-Object System.Text.UTF8Encoding($false)))
        Mock Get-WinmarchyThemesDir { return (Join-Path $fakeRoot 'themes') }
        { Get-WinmarchyTheme -Name 'broken' } | Should -Throw '*not a six-digit hex colour*'
    }
}
}
