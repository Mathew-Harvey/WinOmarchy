# tray.ps1: the Winmarchy notification area icon.
# This is the answer to "there is no way to get to Omarchy from Windows". The
# Start menu shortcuts exist but Windows files them under Recommended, where
# nobody finds them; an icon by the clock is always in the same place.
# WinForms NotifyIcon, no build step, no service: the script is the process.
# Every action shells out to the dispatcher rather than doing the work inline,
# so a failed swap cannot take the icon down with it.
# Compatible with Windows PowerShell 5.1. Dot-source to get the functions
# without starting the icon.

. (Join-Path $PSScriptRoot (Join-Path 'lib' 'common.ps1'))
. (Join-Path $PSScriptRoot 'menu.ps1')

# Labels the tray owns. Everything else it shows is a label from
# Get-WinmarchySystemMenuEntries, executed by Invoke-WinmarchyMenuAction, so
# the two menus cannot drift apart.
$script:WinmarchyTraySeparator = '-'
$script:WinmarchyTrayOwnLabels = @(
    'Show the chooser',
    'Tutorial',
    'Restore Windows 11 (repair)',
    'Hide this icon'
)

function Get-WinmarchyTrayMenuLabels {
    # The ordered tray menu. Pure: takes state in, returns labels out, so the
    # whole menu shape is testable without a desktop.
    param(
        [Parameter(Mandatory = $true)][hashtable]$State
    )
    $swapLabel = 'Swap to Omarchy mode'
    if ($State.mode -eq 'omarchy') { $swapLabel = 'Swap to Windows 11 mode' }
    return @(
        $swapLabel,
        'Show the chooser',
        $script:WinmarchyTraySeparator,
        'Theme menu',
        'Next theme',
        'Next wallpaper',
        'Keybindings',
        'Tutorial',
        $script:WinmarchyTraySeparator,
        'Restore Windows 11 (repair)',
        'Hide this icon'
    )
}

function Invoke-WinmarchyTrayAction {
    # Runs one tray label. Tray-only labels are handled here; everything else
    # goes to the shared menu action so there is one implementation per verb.
    param(
        [Parameter(Mandatory = $true)][string]$Label
    )
    switch ($Label) {
        'Show the chooser' { Start-WinmarchyDetached -Arguments @('chooser') }
        'Tutorial' { Start-WinmarchyDetached -Arguments @('tutorial') }
        'Restore Windows 11 (repair)' { Start-WinmarchyDetached -Arguments @('mode', 'win11', '-Repair') }
        'Swap to Omarchy mode' { Start-WinmarchyDetached -Arguments @('mode', 'omarchy') }
        'Swap to Windows 11 mode' { Start-WinmarchyDetached -Arguments @('mode', 'win11') }
        'Next theme' { Start-WinmarchyDetached -Arguments @('theme', 'next') }
        'Next wallpaper' { Start-WinmarchyDetached -Arguments @('wallpaper', 'next') }
        'Keybindings' { Start-WinmarchyDetached -Arguments @('keys') -Visible }
        'Theme menu' { Start-WinmarchyDetached -Arguments @('menu', 'theme') -Visible }
        default {
            # Anything the tray shows that it does not own is a system menu
            # label, and the system menu already knows how to run it.
            Invoke-WinmarchyMenuAction -Label $Label
        }
    }
}

function Start-WinmarchyDetached {
    # Runs a dispatcher command in its own process so the icon stays live and
    # responsive no matter how long the command takes or how badly it fails.
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Visible
    )
    $dispatcher = Join-Path $PSScriptRoot 'winmarchy.ps1'
    Write-WinmarchyLog -Message ('tray: running ' + ($Arguments -join ' '))
    if ($Visible) {
        $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $dispatcher + '"')) + $Arguments
        $null = Start-Process -FilePath (Get-WinmarchyPowerShellExe) -ArgumentList $argumentList -WindowStyle Normal
        return
    }
    # CreateNoWindow rather than a hidden window: with no console allocated
    # at all, Windows Terminal (the Windows 11 default terminal, which does
    # not honour hide requests; microsoft/terminal issues 12570 and 15311)
    # has nothing to show.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Get-WinmarchyPowerShellExe
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $dispatcher + '" ' + ($Arguments -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $null = [System.Diagnostics.Process]::Start($startInfo)
}

function New-WinmarchyTrayIcon {
    # A 32x32 icon drawn from the palette: the theme background with two
    # accent tiles, so the icon recolours with the theme and reads as tiling
    # at notification area size.
    param(
        [Parameter(Mandatory = $true)]$Theme
    )
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $background = [System.Drawing.ColorTranslator]::FromHtml($Theme.colors.background)
        $accent = [System.Drawing.ColorTranslator]::FromHtml($Theme.colors.accent)
        $muted = [System.Drawing.ColorTranslator]::FromHtml($Theme.colors.muted)

        $backBrush = New-Object System.Drawing.SolidBrush $background
        $graphics.FillRectangle($backBrush, 1, 1, 30, 30)
        $backBrush.Dispose()

        $edgePen = New-Object System.Drawing.Pen $muted, 2
        $graphics.DrawRectangle($edgePen, 1, 1, 29, 29)
        $edgePen.Dispose()

        $accentBrush = New-Object System.Drawing.SolidBrush $accent
        # Left tile full height, two stacked tiles on the right: the layout the
        # window manager actually produces.
        $graphics.FillRectangle($accentBrush, 6, 6, 9, 20)
        $graphics.FillRectangle($accentBrush, 18, 6, 8, 9)
        $graphics.FillRectangle($accentBrush, 18, 17, 8, 9)
        $accentBrush.Dispose()

        $handle = $bitmap.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($handle)
        # The caller owns both: the Icon wraps the handle without owning it, so
        # the handle has to be destroyed separately (documented behaviour of
        # Icon.FromHandle).
        return [pscustomobject]@{ Icon = $icon; Handle = $handle }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Start-WinmarchyTray {
    # Builds the icon and runs the WinForms message loop. Returns when the user
    # picks "Hide this icon".
    [CmdletBinding()]
    param()
    Assert-WinmarchyWindows -Operation 'Notification area icon'
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # One icon only. A second copy started by a stray shortcut or a re-run of
    # the installer would sit there doing nothing useful.
    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\WinmarchyTray', [ref]$createdNew)
    if (-not $createdNew) {
        Write-WinmarchyLog -Message 'tray: already running, second copy exiting'
        return
    }

    # Hide the console this script was launched from. GetConsoleWindow
    # (kernel32) and ShowWindow (user32) are both documented Win32 calls;
    # SW_HIDE is 0.
    try {
        if (-not ('Winmarchy.TrayNative' -as [type])) {
            Add-Type -Namespace 'Winmarchy' -Name 'TrayNative' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool DestroyIcon(System.IntPtr hIcon);
'@
        }
        $console = [Winmarchy.TrayNative]::GetConsoleWindow()
        if ($console -ne [System.IntPtr]::Zero) {
            $null = [Winmarchy.TrayNative]::ShowWindow($console, 0)
        }
    } catch {
        Write-WinmarchyLog -Message ('tray: could not hide the console window: ' + $_.Exception.Message) -Level 'WARN'
    }

    # Script scope, not local: WinForms event handlers run in the scope the
    # scriptblock was defined in, and a function local would not be reachable
    # from them.
    $script:trayNotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:trayIconHandle = [System.IntPtr]::Zero
    $script:trayThemeName = ''

    $script:trayNotifyIcon.ContextMenuStrip = $script:trayMenu
    $script:trayNotifyIcon.Text = 'Winmarchy'
    Update-WinmarchyTrayIcon
    $script:trayNotifyIcon.Visible = $true

    $script:trayMenu.add_Opening({
        $state = Get-WinmarchyState
        $script:trayMenu.Items.Clear()
        $modeLabel = 'Windows 11'
        if ($state.mode -eq 'omarchy') { $modeLabel = 'Omarchy' }
        $header = New-Object System.Windows.Forms.ToolStripMenuItem
        $header.Text = 'Winmarchy: ' + $modeLabel + ' (' + $state.theme + ')'
        $header.Enabled = $false
        $null = $script:trayMenu.Items.Add($header)
        $null = $script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        foreach ($label in (Get-WinmarchyTrayMenuLabels -State $state)) {
            if ($label -eq $script:WinmarchyTraySeparator) {
                $null = $script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
                continue
            }
            $item = New-Object System.Windows.Forms.ToolStripMenuItem
            $item.Text = $label
            $item.Tag = $label
            $item.add_Click({
                param($clicked, $clickArgs)
                if ($clickArgs) { }
                $chosen = [string]$clicked.Tag
                if ($chosen -eq 'Hide this icon') {
                    $script:trayNotifyIcon.Visible = $false
                    [System.Windows.Forms.Application]::Exit()
                    return
                }
                try {
                    Invoke-WinmarchyTrayAction -Label $chosen
                } catch {
                    Write-WinmarchyLog -Message ('tray: ' + $chosen + ' failed: ' + $_.Exception.Message) -Level 'ERROR'
                    $null = [System.Windows.Forms.MessageBox]::Show(
                        ($chosen + ' failed: ' + $_.Exception.Message), 'Winmarchy')
                }
            })
            $null = $script:trayMenu.Items.Add($item)
        }
        Update-WinmarchyTrayIcon
        $script:trayNotifyIcon.Text = 'Winmarchy: ' + $modeLabel
    })

    # Windows opens a NotifyIcon's context menu on right click only. Showing it
    # on left click too costs one line and removes the "I clicked it and
    # nothing happened" moment. ContextMenuStrip.Show raises Opening, so the
    # menu is rebuilt either way.
    $script:trayNotifyIcon.add_MouseUp({
        param($clicked, $mouseArgs)
        if ($clicked) { }
        if ($mouseArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:trayMenu.Show([System.Windows.Forms.Control]::MousePosition)
        }
    })

    # With a wallpaper folder configured, a fresh picture on the interval
    # the user chose. One-minute ticks with a counter, so a changed interval
    # takes effect within a minute rather than after the old one.
    $script:wallpaperTimer = New-Object System.Windows.Forms.Timer
    $script:wallpaperTimer.Interval = 60 * 1000
    $script:wallpaperMinutes = 0
    $script:wallpaperTimer.add_Tick({
        if (-not (Get-WinmarchyState).wallpaperDir) {
            $script:wallpaperMinutes = 0
            return
        }
        $script:wallpaperMinutes = $script:wallpaperMinutes + 1
        if ($script:wallpaperMinutes -ge (Get-WinmarchyWallpaperIntervalMinutes)) {
            $script:wallpaperMinutes = 0
            Start-WinmarchyDetached -Arguments @('wallpaper', 'next')
        }
    })
    $script:wallpaperTimer.Start()

    Write-WinmarchyLog -Message 'tray: icon shown'
    try {
        [System.Windows.Forms.Application]::Run()
    } finally {
        $script:wallpaperTimer.Stop()
        $script:trayNotifyIcon.Visible = $false
        $script:trayNotifyIcon.Dispose()
        if ($script:trayIconHandle -ne [System.IntPtr]::Zero) {
            $null = [Winmarchy.TrayNative]::DestroyIcon($script:trayIconHandle)
        }
        $mutex.ReleaseMutex()
        $mutex.Dispose()
        Write-WinmarchyLog -Message 'tray: exited'
    }
}

function Update-WinmarchyTrayIcon {
    # Repaints the icon when the theme has changed, and never more often: each
    # repaint mints a new HICON that has to be destroyed by hand.
    $state = Get-WinmarchyState
    if ($state.theme -eq $script:trayThemeName) { return }
    try {
        $built = New-WinmarchyTrayIcon -Theme (Get-WinmarchyTheme -Name $state.theme)
        $script:trayNotifyIcon.Icon = $built.Icon
        if ($script:trayIconHandle -ne [System.IntPtr]::Zero) {
            $null = [Winmarchy.TrayNative]::DestroyIcon($script:trayIconHandle)
        }
        $script:trayIconHandle = $built.Handle
        $script:trayThemeName = $state.theme
    } catch {
        Write-WinmarchyLog -Message ('tray: icon build failed, using the system default: ' + $_.Exception.Message) -Level 'WARN'
        $script:trayNotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
        $script:trayThemeName = $state.theme
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-WinmarchyTray
}
