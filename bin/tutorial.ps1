# tutorial.ps1: the Omarchy mode onboarding tutorial. Builds a themed page
# teaching a Windows user the new keys, then opens it in the default browser.
#
# The lessons name bindings; the bindings themselves are read from the live
# GlazeWM config, so the tutorial can never teach a key that is not actually
# bound. A test asserts the reverse too: every binding in the config is either
# taught here or listed as deliberately not taught.
#
# Compatible with Windows PowerShell 5.1. Dot-source to get the functions
# without building or opening anything.

. (Join-Path $PSScriptRoot (Join-Path 'lib' 'common.ps1'))
. (Join-Path $PSScriptRoot 'keybindings.ps1')

function Get-WinmarchyTutorialLessons {
    # Written for someone who has used Windows for twenty years and has never
    # seen a tiling window manager. Every lesson says what the key does and
    # what Windows habit it replaces.
    return @(
        [pscustomobject]@{
            Group = 'Start here'
            Binding = ''
            Title = 'The Windows key is now your command key'
            What = 'In Omarchy mode almost every shortcut starts by holding the Windows key. The tutorial calls it Super, which is what the rest of the tiling world calls it. Hold it down and press one more key.'
            Windows = 'Nothing is lost: Windows still owns Win+L to lock the screen, and Alt+Tab works exactly as it always has.'
        },
        [pscustomobject]@{
            Group = 'Start here'
            Binding = 'lwin+shift+x'
            Title = 'The way out, before anything else'
            What = 'Puts you straight back to normal Windows: taskbar, icons, wallpaper, terminal and editor all restored. Learn this one first and the rest is safe to experiment with.'
            Windows = 'There is also a "Restore Windows 11 (repair)" shortcut in the Start menu, and winmarchy mode win11 from any shell.'
        },
        [pscustomobject]@{
            Group = 'Opening things'
            Binding = 'lwin+enter'
            Title = 'Open a terminal'
            What = 'A new terminal window, themed to match everything else. It tiles itself into the free space; you never position it.'
            Windows = 'Replaces hunting for Terminal in the Start menu.'
        },
        [pscustomobject]@{
            Group = 'Opening things'
            Binding = 'lwin+space'
            Title = 'Open the launcher'
            What = 'Start typing an app name and press Enter. This is how you open everything in Omarchy mode.'
            Windows = 'Replaces the Start menu and the search box on the taskbar.'
        },
        [pscustomobject]@{
            Group = 'Opening things'
            Binding = 'lwin+shift+n'
            Title = 'Open the editor'
            What = 'Opens the code editor, themed to the same palette as everything else.'
            Windows = 'Replaces pinning your editor to the taskbar.'
        },
        [pscustomobject]@{
            Group = 'Opening things'
            Binding = 'lwin+shift+f'
            Title = 'Open the file manager'
            What = 'Ordinary Windows File Explorer, tiled alongside your other windows.'
            Windows = 'The same Explorer you already use; only the way it is placed changes.'
        },
        [pscustomobject]@{
            Group = 'Opening things'
            Binding = 'lwin+shift+enter'
            Title = 'Open the browser'
            What = 'Opens your default browser at its start page.'
            Windows = 'Replaces the browser icon on the taskbar.'
        },
        [pscustomobject]@{
            Group = 'Moving around'
            Binding = 'lwin+left'
            Title = 'Move focus between windows'
            What = 'Focus moves to whichever window sits in that direction on screen. Try the other arrows too: right, up and down all work the same way.'
            Windows = 'Replaces Alt+Tab for anything on screen. You aim at where a window is, rather than cycling through a list.'
        },
        [pscustomobject]@{
            Group = 'Moving around'
            Binding = 'lwin+tab'
            Title = 'Jump to the next busy workspace'
            What = 'Cycles forward through the workspaces that actually have windows in them. Add Shift to go backwards.'
            Windows = 'Similar to Ctrl+Win+Arrow between virtual desktops, but it skips the empty ones.'
        },
        [pscustomobject]@{
            Group = 'Moving around'
            Binding = 'lwin+ctrl+tab'
            Title = 'Back to where you just were'
            What = 'Returns to the workspace you were on before this one. Press it again to bounce back.'
            Windows = 'The workspace equivalent of Alt+Tab between two windows.'
        },
        [pscustomobject]@{
            Group = 'Rearranging'
            Binding = 'lwin+shift+left'
            Title = 'Move a window'
            What = 'Picks the focused window up and swaps it in that direction. The layout re-tiles itself around the change. All four arrows work.'
            Windows = 'Replaces dragging a window by its title bar, and replaces Win+Arrow snapping.'
        },
        [pscustomobject]@{
            Group = 'Rearranging'
            Binding = 'lwin+j'
            Title = 'Change the split direction'
            What = 'Decides whether the next window you open lands beside the current one or below it. Press it, then open a terminal to see the difference.'
            Windows = 'There is no Windows equivalent; this is the core idea of tiling.'
        },
        [pscustomobject]@{
            Group = 'Rearranging'
            Binding = 'lwin+oem_plus'
            Title = 'Make a window wider or narrower'
            What = 'Grows the focused window by five percent. The minus key shrinks it. Hold Shift with either to change the height instead.'
            Windows = 'Replaces dragging the border between two windows.'
        },
        [pscustomobject]@{
            Group = 'Rearranging'
            Binding = 'lwin+r'
            Title = 'Resize mode, for bigger adjustments'
            What = 'Puts you in a mode where the arrow keys resize the focused window continuously. Press Escape or Enter when the size looks right.'
            Windows = 'The bar shows that resize mode is active, so you always know where you are.'
        },
        [pscustomobject]@{
            Group = 'Workspaces'
            Binding = 'lwin+1'
            Title = 'Go to a workspace by number'
            What = 'Nine workspaces, numbered one to nine, each holding its own set of windows. The bar along the top shows which are in use and which one you are on.'
            Windows = 'Replaces virtual desktops, but reaching them is one keystroke rather than a gesture.'
        },
        [pscustomobject]@{
            Group = 'Workspaces'
            Binding = 'lwin+shift+1'
            Title = 'Send a window to a workspace'
            What = 'Moves the focused window to that workspace and follows it there. Works for one through nine.'
            Windows = 'Replaces dragging a window in Task View.'
        },
        [pscustomobject]@{
            Group = 'Window states'
            Binding = 'lwin+w'
            Title = 'Close the focused window'
            What = 'Closes the window you are looking at and re-tiles the rest.'
            Windows = 'Same as Alt+F4, and same as clicking the X.'
        },
        [pscustomobject]@{
            Group = 'Window states'
            Binding = 'lwin+f'
            Title = 'Fullscreen'
            What = 'Blows the focused window up to the whole screen. Press again to put it back in the layout.'
            Windows = 'Similar to F11 in a browser, but it works for any window.'
        },
        [pscustomobject]@{
            Group = 'Window states'
            Binding = 'lwin+t'
            Title = 'Let a window float'
            What = 'Lifts the window out of the tiling layout and centres it, so it behaves like an ordinary Windows window you can drag. Press again to put it back in the grid.'
            Windows = 'This is how you get normal Windows behaviour back for one stubborn app.'
        },
        [pscustomobject]@{
            Group = 'Window states'
            Binding = 'lwin+p'
            Title = 'Pause the tiling'
            What = 'Stops the window manager arranging anything, without leaving Omarchy mode. Useful for a screen share or a fussy application.'
            Windows = 'Windows behaves normally again until you press it a second time.'
        },
        [pscustomobject]@{
            Group = 'Look and feel'
            Binding = 'lwin+ctrl+space'
            Title = 'Next theme'
            What = 'Cycles to the next of the eight palettes. The bar, window borders, terminal, editor and wallpaper all change together, instantly.'
            Windows = 'Nothing in Windows does this; it is the whole point of the theme engine.'
        },
        [pscustomobject]@{
            Group = 'Look and feel'
            Binding = 'lwin+ctrl+shift+space'
            Title = 'Pick a theme from a list'
            What = 'Opens a searchable list of the eight themes so you can jump straight to one.'
            Windows = 'Replaces Settings, Personalisation, Colours.'
        },
        [pscustomobject]@{
            Group = 'Look and feel'
            Binding = 'lwin+shift+space'
            Title = 'Hide or show the bar'
            What = 'Toggles the status bar along the top of the screen.'
            Windows = 'Similar to auto-hiding the taskbar.'
        },
        [pscustomobject]@{
            Group = 'Getting help'
            Binding = 'lwin+k'
            Title = 'The full key list'
            What = 'Shows every binding, read live from the configuration, in a floating window. When you forget something, this is the fastest answer.'
            Windows = 'Think of it as the cheat sheet that is always one key away.'
        },
        [pscustomobject]@{
            Group = 'Getting help'
            Binding = 'lwin+escape'
            Title = 'The system menu'
            What = 'Themes, keybindings, swapping back to Windows, reloading the config, lock, sleep, restart, shut down and sign out, all in one searchable list.'
            Windows = 'Replaces right-clicking the Start button and the power menu.'
        }
    )
}

function Get-WinmarchyTutorialExcludedBindings {
    # Bindings deliberately not taught: the remaining arrows and digits that
    # a taught lesson already covers as a family, plus the maintenance keys a
    # newcomer does not need on day one. The coverage test uses this list, so
    # nothing can quietly go untaught.
    return @(
        'lwin+right', 'lwin+up', 'lwin+down',
        'lwin+shift+right', 'lwin+shift+up', 'lwin+shift+down',
        'lwin+2', 'lwin+3', 'lwin+4', 'lwin+5', 'lwin+6', 'lwin+7', 'lwin+8', 'lwin+9',
        'lwin+shift+2', 'lwin+shift+3', 'lwin+shift+4', 'lwin+shift+5',
        'lwin+shift+6', 'lwin+shift+7', 'lwin+shift+8', 'lwin+shift+9',
        'lwin+shift+tab',
        'lwin+oem_minus', 'lwin+shift+oem_minus', 'lwin+shift+oem_plus',
        'lwin+shift+alt+left', 'lwin+shift+alt+right', 'lwin+shift+alt+up', 'lwin+shift+alt+down',
        'lwin+shift+r', 'lwin+shift+e',
        'h', 'l', 'k', 'j', 'left', 'right', 'up', 'down', 'escape', 'enter', 'lwin+r'
    )
}

function ConvertTo-WinmarchyKeycapHtml {
    # Turns a GlazeWM binding such as lwin+shift+x into keycaps a Windows user
    # recognises: Super, Shift, X.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Binding)
    if ($Binding -eq '') { return '' }
    $names = @{
        'lwin' = 'Super'; 'shift' = 'Shift'; 'ctrl' = 'Ctrl'; 'alt' = 'Alt'
        'enter' = 'Enter'; 'space' = 'Space'; 'escape' = 'Esc'; 'tab' = 'Tab'
        'left' = 'Left'; 'right' = 'Right'; 'up' = 'Up'; 'down' = 'Down'
        'oem_plus' = 'Plus'; 'oem_minus' = 'Minus'
    }
    $caps = @()
    foreach ($token in ($Binding -split '\+')) {
        $label = $token
        if ($names.ContainsKey($token)) {
            $label = $names[$token]
        } else {
            $label = $token.ToUpper()
        }
        $caps = $caps + ('<kbd>' + $label + '</kbd>')
    }
    return ($caps -join '<span class="plus">+</span>')
}

function ConvertTo-WinmarchyHtmlText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $escaped = $Text.Replace('&', '&amp;')
    $escaped = $escaped.Replace('<', '&lt;')
    $escaped = $escaped.Replace('>', '&gt;')
    return $escaped
}

function Build-WinmarchyTutorialLessonHtml {
    # The lesson cards, grouped, as a single HTML fragment.
    param([pscustomobject[]]$Lessons)
    $html = ''
    $currentGroup = ''
    foreach ($lesson in @($Lessons)) {
        if ($lesson.Group -ne $currentGroup) {
            if ($currentGroup -ne '') { $html = $html + '</div>' + [Environment]::NewLine }
            $currentGroup = $lesson.Group
            $html = $html + '<h2>' + (ConvertTo-WinmarchyHtmlText $currentGroup) + '</h2>' + [Environment]::NewLine
            $html = $html + '<div class="cards">' + [Environment]::NewLine
        }
        $keys = ConvertTo-WinmarchyKeycapHtml -Binding $lesson.Binding
        $keysBlock = '<div class="keys none">no key, just so you know</div>'
        if ($keys -ne '') { $keysBlock = '<div class="keys">' + $keys + '</div>' }
        $html = $html + '  <article class="card">' + [Environment]::NewLine
        $html = $html + '    ' + $keysBlock + [Environment]::NewLine
        $html = $html + '    <h3>' + (ConvertTo-WinmarchyHtmlText $lesson.Title) + '</h3>' + [Environment]::NewLine
        $html = $html + '    <p>' + (ConvertTo-WinmarchyHtmlText $lesson.What) + '</p>' + [Environment]::NewLine
        $html = $html + '    <p class="was">' + (ConvertTo-WinmarchyHtmlText $lesson.Windows) + '</p>' + [Environment]::NewLine
        $html = $html + '  </article>' + [Environment]::NewLine
    }
    if ($currentGroup -ne '') { $html = $html + '</div>' + [Environment]::NewLine }
    return $html
}

function New-WinmarchyTutorialPage {
    # Renders the tutorial in the active palette and returns the HTML.
    param(
        [string]$ThemeName = ''
    )
    if ($ThemeName -eq '') { $ThemeName = (Get-WinmarchyState).theme }
    $theme = Get-WinmarchyTheme -Name $ThemeName
    $tokens = Get-WinmarchyThemeTokens -Theme $theme
    $tokens['lessons'] = Build-WinmarchyTutorialLessonHtml -Lessons (Get-WinmarchyTutorialLessons)

    $templatePath = Join-Path (Get-WinmarchyTemplatesDir) 'tutorial.html.tpl'
    $template = [System.IO.File]::ReadAllText($templatePath)
    return (Expand-WinmarchyTemplate -Template $template -Tokens $tokens)
}

function Show-WinmarchyTutorial {
    # Writes the page and opens it in the default browser.
    [CmdletBinding()]
    param(
        [switch]$NoOpen
    )
    $html = New-WinmarchyTutorialPage
    $path = Join-Path (Get-WinmarchyHome) 'tutorial.html'
    Write-WinmarchyTextFile -Path $path -Content $html
    Write-WinmarchyLog -Message ('tutorial written to ' + $path)
    Set-WinmarchyStateValue -Name 'tutorialSeen' -Value $true
    if (-not $NoOpen) {
        # explorer.exe opens a local file in the default browser without
        # needing to know which browser that is.
        Start-Process 'explorer.exe' -ArgumentList $path
    }
    return $path
}

if ($MyInvocation.InvocationName -ne '.') {
    $null = Show-WinmarchyTutorial
}
