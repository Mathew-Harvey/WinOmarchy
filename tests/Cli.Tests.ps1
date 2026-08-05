# Pester tests for the winmarchy command dispatcher: the exit codes and
# messages a shell user actually sees. Run through a child PowerShell, the
# way every real invocation arrives, so the param binding, the usage text
# and the exit codes are all exercised end to end.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:dispatcher = Join-Path $script:repoRoot (Join-Path 'bin' 'winmarchy.ps1')
    # The same PowerShell that is running the tests, so the suite behaves
    # identically under pwsh on the build container and 5.1 on Windows.
    $script:shell = (Get-Process -Id $PID).Path
    $script:savedHome = $env:WINMARCHY_HOME

    function Invoke-WinmarchyCli {
        param([string[]]$CliArgs)
        $output = @(& $script:shell -NoProfile -File $script:dispatcher @CliArgs 2>&1)
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Text     = (($output | ForEach-Object { [string]$_ }) -join "`n")
        }
    }
}

AfterAll {
    $env:WINMARCHY_HOME = $script:savedHome
}

Describe 'Command dispatcher' {
    BeforeEach {
        $env:WINMARCHY_HOME = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
    }

    It 'prints the usage and exits cleanly when called bare' {
        $result = Invoke-WinmarchyCli -CliArgs @()
        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match 'commands:'
        $result.Text | Should -Match 'winmarchy mode win11'
    }

    It 'prints the usage and exits 1 on a command it does not know' {
        $result = Invoke-WinmarchyCli -CliArgs @('frobnicate')
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'commands:'
    }

    It 'rejects a wallpaper pace outside 1 to 1440 minutes with a clear message' {
        $result = Invoke-WinmarchyCli -CliArgs @('wallpaper', 'every', '0')
        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'between 1 and 1440'
    }

    It 'reports wallpaper cycling off on a fresh install' {
        $result = Invoke-WinmarchyCli -CliArgs @('wallpaper', 'status')
        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match 'wallpaper cycling: off'
    }

    It 'lists the shipped themes' {
        $result = Invoke-WinmarchyCli -CliArgs @('theme', 'list')
        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match 'tokyo-night'
        $result.Text | Should -Match 'rose-pine'
    }
}
