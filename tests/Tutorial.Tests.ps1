# Pester tests for the onboarding tutorial. The point of these is coverage:
# the tutorial must teach keys that actually exist, and must not quietly leave
# a binding untaught. Both directions are checked against the live config.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    . (Join-Path $script:repoRoot (Join-Path 'bin' 'tutorial.ps1'))
    $script:configPath = Join-Path $script:repoRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))
    $script:savedHome = $env:WINMARCHY_HOME
    $script:savedProfile = $env:WINMARCHY_USERPROFILE
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
    $env:WINMARCHY_USERPROFILE = $script:savedProfile
}

Describe 'Onboarding tutorial' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        $env:WINMARCHY_HOME = Join-Path $testRoot 'home'
        $env:WINMARCHY_USERPROFILE = Join-Path $testRoot 'profile'
    }

    It 'only teaches keys that are actually bound' {
        $bound = @()
        foreach ($row in (Get-WinmarchyKeybindingRows -ConfigPath $script:configPath)) {
            foreach ($binding in ($row.Binding -split ', ')) { $bound = $bound + $binding }
        }
        foreach ($lesson in (Get-WinmarchyTutorialLessons)) {
            if ($lesson.Binding -eq '') { continue }
            $bound | Should -Contain $lesson.Binding -Because ('the tutorial teaches ' + $lesson.Binding + ', so it must be bound')
        }
    }

    It 'leaves no binding untaught without saying so' {
        $taught = @()
        foreach ($lesson in (Get-WinmarchyTutorialLessons)) {
            if ($lesson.Binding -ne '') { $taught = $taught + $lesson.Binding }
        }
        $excluded = @(Get-WinmarchyTutorialExcludedBindings)
        $missing = @()
        foreach ($row in (Get-WinmarchyKeybindingRows -ConfigPath $script:configPath)) {
            foreach ($binding in ($row.Binding -split ', ')) {
                if ($taught -contains $binding) { continue }
                if ($excluded -contains $binding) { continue }
                $missing = $missing + $binding
            }
        }
        $missing | Should -Be @() -Because 'every binding must be taught or listed as deliberately not taught'
    }

    It 'always teaches the way out first' {
        $lessons = @(Get-WinmarchyTutorialLessons)
        $panic = $lessons | Where-Object { $_.Binding -eq 'lwin+shift+x' }
        $panic | Should -Not -BeNullOrEmpty
        # It must be in the opening group, not buried at the bottom.
        $lessons[0].Group | Should -Be 'Start here'
        $panic.Group | Should -Be 'Start here'
    }

    It 'explains what each key replaces in Windows terms' {
        foreach ($lesson in (Get-WinmarchyTutorialLessons)) {
            $lesson.Title | Should -Not -BeNullOrEmpty
            $lesson.What.Length | Should -BeGreaterThan 40
            $lesson.Windows.Length | Should -BeGreaterThan 20
        }
    }

    It 'renders bindings as keycaps a Windows user recognises' {
        ConvertTo-WinmarchyKeycapHtml -Binding 'lwin+shift+x' | Should -Match '<kbd>Super</kbd>'
        ConvertTo-WinmarchyKeycapHtml -Binding 'lwin+shift+x' | Should -Match '<kbd>Shift</kbd>'
        ConvertTo-WinmarchyKeycapHtml -Binding 'lwin+shift+x' | Should -Match '<kbd>X</kbd>'
        ConvertTo-WinmarchyKeycapHtml -Binding 'lwin+oem_plus' | Should -Match '<kbd>Plus</kbd>'
        ConvertTo-WinmarchyKeycapHtml -Binding '' | Should -Be ''
    }

    It 'escapes text so a stray angle bracket cannot break the page' {
        ConvertTo-WinmarchyHtmlText -Text 'a <b> & c' | Should -Be 'a &lt;b&gt; &amp; c'
    }

    It 'renders for theme <_> with no unresolved tokens' -ForEach @('catppuccin', 'everforest', 'gruvbox', 'kanagawa', 'matte-black', 'nord', 'rose-pine', 'tokyo-night') {
        $html = New-WinmarchyTutorialPage -ThemeName $_
        $html.Contains('{{') | Should -BeFalse
        $theme = Get-WinmarchyTheme -Name $_
        $html.Contains($theme.colors.accent) | Should -BeTrue
        $html | Should -Match '<kbd>Super</kbd>'
        # Every lesson group must make it into the page.
        foreach ($group in @('Start here', 'Opening things', 'Moving around', 'Rearranging', 'Workspaces', 'Window states', 'Look and feel', 'Getting help')) {
            $html.Contains($group) | Should -BeTrue
        }
    }

    It 'writes the page and records that it has been seen' {
        $path = Show-WinmarchyTutorial -NoOpen
        Test-Path $path | Should -BeTrue
        (Get-WinmarchyState).tutorialSeen | Should -BeTrue
        [System.IO.File]::ReadAllText($path) | Should -Match 'You are in Omarchy mode'
    }
}
