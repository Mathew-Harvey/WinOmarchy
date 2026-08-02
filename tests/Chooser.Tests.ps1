# Pester tests for the chooser's health checks and for the rule that came out
# of a real failure: the chooser must never be able to show nothing.
#
# The C# cannot be exercised headlessly on Linux, so the source-level
# assertions below stand in for it. They are deliberately about the shape of
# the failure handling, not about wording: every WebView2 failure path has to
# reach the plain chooser rather than closing the window.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
    $script:chooserDir = Join-Path $script:repoRoot 'chooser'
    $script:savedHome = $env:WINMARCHY_HOME
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
}

Describe 'Chooser' {
    BeforeEach {
        $env:WINMARCHY_HOME = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
    }

Describe 'Payload check' {
    It 'reports both pieces missing on a machine with no chooser' {
        $payload = Test-WinmarchyChooserPayload
        $payload.Ok | Should -BeFalse
        $payload.Missing | Should -Contain 'Winmarchy.Chooser.exe'
        $payload.Missing | Should -Contain 'ui\index.html'
    }

    It 'reports the ui folder alone when the publish dropped it' {
        Write-WinmarchyTextFile -Path (Get-WinmarchyChooserExePath) -Content 'exe'
        $payload = Test-WinmarchyChooserPayload
        $payload.Ok | Should -BeFalse
        $payload.Missing | Should -Be @('ui\index.html')
    }

    It 'passes when the exe and the page are both there' {
        Write-WinmarchyTextFile -Path (Get-WinmarchyChooserExePath) -Content 'exe'
        Write-WinmarchyTextFile -Path (Join-Path (Join-Path (Get-WinmarchyChooserDir) 'ui') 'index.html') -Content '<html></html>'
        (Test-WinmarchyChooserPayload).Ok | Should -BeTrue
    }
}

Describe 'Launch' {
    It 'explains what is missing instead of starting a chooser that cannot draw' {
        Mock Test-WinmarchyIsWindows { $true }
        { Start-WinmarchyChooser } | Should -Throw '*Winmarchy.Chooser.exe*'
    }
}

Describe 'Never shows nothing' {
    It 'ships a plain chooser with no WebView2 in it' {
        $xaml = Join-Path $script:chooserDir 'FallbackWindow.xaml'
        $code = Join-Path $script:chooserDir 'FallbackWindow.xaml.cs'
        Test-Path $xaml | Should -BeTrue
        Test-Path $code | Should -BeTrue
        # The namespace, not the word: both files mention WebView2 in prose,
        # explaining why they exist.
        [System.IO.File]::ReadAllText($xaml) | Should -Not -Match 'Microsoft\.Web\.WebView2'
        [System.IO.File]::ReadAllText($code) | Should -Not -Match 'Microsoft\.Web\.WebView2'
    }

    It 'routes every WebView2 failure to the plain chooser' {
        $source = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'MainWindow.xaml.cs'))
        # Creation failure, navigation failure, renderer crash and the health
        # timeout: four ways for the rich chooser to fail, four hand-overs.
        ([regex]::Matches($source, 'HandOverToPlainChooser\(')).Count | Should -BeGreaterOrEqual 5
    }

    It 'falls back to the plain chooser when the WebView2 window cannot be built at all' {
        $source = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Program.cs'))
        $source | Should -Match 'new FallbackWindow'
        # OnLastWindowClose, because the rich chooser shows the plain one and
        # then closes itself; the default would take both down.
        $source | Should -Match 'ShutdownMode\.OnLastWindowClose'
    }

    It 'can run on a newer .NET than it was built for' {
        # A net8.0 app with only a newer Desktop Runtime installed refuses to
        # start, and a WinExe failing that way is silent at login.
        $project = [System.IO.File]::ReadAllText((Join-Path $script:chooserDir 'Winmarchy.Chooser.csproj'))
        $project | Should -Match '<RollForward>LatestMajor</RollForward>'
    }
}
}
