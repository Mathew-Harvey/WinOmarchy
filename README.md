# Winmarchy

Winmarchy gives a Windows 11 machine two personalities. One is stock
Windows 11, untouched. The other is an Omarchy-inspired desktop: GlazeWM
tiling driven from the Super key, a slim themed yasb bar instead of the
taskbar, Flow Launcher on `lwin+space`, a themed Alacritty terminal and
Cursor, and one colour palette driving every surface. A chooser appears at
login with both worlds side by side; you click the one you want, and you
can hot swap from either side at any time. Omarchy itself is DHH's
opinionated Arch and Hyprland setup (omarchy.org); this is a port of its
feel, not its internals, built from off-the-shelf Windows parts.

The design principle throughout is recoverability beats beauty. Explorer
stays the Windows shell at all times; the chooser is an overlay, not a
shell replacement. Every mutating step in a swap writes an undo journal
entry before it acts, and every entry point checks that journal and repairs
first if a previous swap was interrupted. The panic paths are always there:
`lwin+shift+x`, a "Restore Windows 11 (repair)" Start menu shortcut,
`winmarchy mode win11 -Repair` from any shell, and docs/recovery.md for the
by-hand worst case.

## What you need

Windows 11 (build 22000 or later; Windows 10 is out of scope), winget (the
App Installer from the Microsoft Store, present on any current Windows 11),
and the .NET 8 SDK if you want the login chooser built (without it,
everything else still works and you swap from the Start menu or the
command line). Every app Winmarchy uses is installed per-user through
winget by the installer itself. Winmarchy's own files and settings are
entirely per-user and need no admin rights, but some of the apps it fetches
are machine-wide packages and Windows will ask you to approve those.

## Install

Download or clone this repository onto the Windows 11 machine, open the
folder, and double-click **install-ui.cmd**. That opens the setup wizard,
which walks you through it in seven steps:

1. **Welcome** explains what you are about to get and how to get back.
   Setup writes only into your own user profile and your own registry hive,
   so Winmarchy itself needs no administrator rights. Several of the apps it
   installs are machine-wide packages, though, so Windows will raise its own
   approval prompt for those. Approve each one. Dismissing a prompt makes
   winget report that app as cancelled and skip it, which is exactly how you
   end up with a working desktop and a dead Super+Enter.
2. **System check** looks at the machine and tells you what it found:
   Windows version, whether winget and the .NET SDK are there, free space,
   whether Cursor has run yet, and whether there is a previous install.
   Anything genuinely missing stops the wizard here rather than failing
   halfway.
3. **Theme** lets you pick a palette from the eight that ship, with a live
   preview of the bar, the window borders and the tiling layout in that
   palette.
4. **Components** is where you choose what to set up: the apps, the login
   chooser, whether the chooser appears at login, and whether to put a
   Winmarchy icon by the clock. Options whose prerequisites are missing
   switch themselves off and say why, so you cannot pick something that
   will fail later.
5. **Review** shows the decisions in plain language, the equivalent command
   line if you would rather run it yourself, and the complete step-by-step
   plan. Nothing has been changed at this point.
6. **Install** runs it with a live log.
7. **Finish** hands over the ten keybindings worth knowing and offers to
   start Omarchy mode straight away.

You do not need to reboot. The one Windows service involved belongs to
Everything, the file search behind the launcher; setup adds it through a
normal approval prompt, and everything else is plain per-user programs.

Three ways to swap, available the moment setup finishes:

- the **Winmarchy icon by the clock**, left click or right click
- the **Winmarchy folder in the Start menu**, under All apps
- `winmarchy mode omarchy` from any shell

Setup leaves the desktop alone: it puts no shortcuts of its own there, and
it removes the icons the third-party app installers drop while it runs
(ones on the shared desktop need admin rights to remove, so those are named
in a warning instead).

The login chooser needs a new logon session, so sign out and back in to meet
it (a reboot works too, but is not required). It waits twenty seconds before
continuing to your last mode, and any mouse movement or key press stops the
clock. To see it straight away without signing out, run `winmarchy chooser`.
If it does not appear at login, run `winmarchy doctor`: it checks the whole
chain, from whether the chooser was built to whether Windows has its startup
entry switched off.

If you prefer a text prompt, `install-ui.ps1 -Console` asks the same
questions in the terminal. That is also the automatic fallback if the
graphical wizard cannot open.

To skip the questions entirely and install with defaults:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

Add `-WhatIf` to print the full action list without touching anything.
`-Theme <name>` picks the palette; `-SkipApps`, `-SkipChooser`,
`-NoAutostart` and `-NoTray` correspond to the wizard's component choices.
The wizard passes these same switches, so there is only one install path
either way.

However you start it, the installer backs up everything it is about to
touch into `%LOCALAPPDATA%\winmarchy\backup\<timestamp>\` before its first
mutation and refuses to continue if that backup fails.

Running setup again is cheap. Every app already on the machine is skipped
with an "already present, skipped" line before winget is asked to do
anything, so a re-run raises no approval prompts for what is already
there, however it got installed. The flip side is that setup never
upgrades an app; `winget upgrade` is the command for that, whenever you
choose.

Expect Windows to ask for approval a few times while the apps install:
Alacritty among others is a machine-wide package. If you dismiss one of
those prompts, winget reports the app as cancelled and the installer says
so, names what that app was for, and prints the one command that retries
it. `winmarchy doctor` will also fail a row for it afterwards.

Alacritty is the terminal `Super+Enter` opens, and its config is written
from the palette, ported verbatim from Omarchy's own Alacritty template. If
you already have an `alacritty.toml` it is backed up first and restored the
moment you swap back to Windows 11. Windows Terminal is still themed too,
so the terminal Windows opens from its own menus matches.

One note on Windows Terminal: its settings.json may contain comments, and
the first time Winmarchy patches it those comments are lost. The original
file is preserved beside it as `settings.json.winmarchy-bak`, and uninstall
removes only what Winmarchy added rather than reverting the whole file.

## Daily use

The first time you enter Omarchy mode a tutorial opens in your browser,
teaching every key in Windows terms and telling you the way out first. Open
it again any time with `winmarchy tutorial`.

`winmarchy keys` (or `lwin+k` in Omarchy mode) shows the full keymap, read
live from the GlazeWM config. The spine of it: `lwin+enter` terminal,
`lwin+space` launcher, `lwin+1` to `lwin+9` workspaces, `lwin+arrows`
focus, `lwin+shift+arrows` move, `lwin+w` close, `lwin+f` fullscreen,
`lwin+escape` the system menu, `lwin+ctrl+space` next theme. Windows keeps
`Win+L` for lock and `Alt+Tab` stays native.

Point setup (or `winmarchy wallpaper dir <path>`) at a folder of your own
pictures, subfolders and all, and both modes deal a random one from the
whole tree: on every swap, on every theme change, on `lwin+ctrl+b`, and on
whatever interval you set with the wizard's slider (or
`winmarchy wallpaper every <minutes>`, 1 to 1440, default 30). The folder
and the interval live in Winmarchy's state, so they persist across swaps,
sign-outs and reboots, in both modes alike. This is the one thing Winmarchy
will change about Windows 11 mode, and only because you asked it to;
`winmarchy wallpaper off` stops it.

The bar's top-left button opens the menu, Omarchy style: themes, wallpaper,
keybindings, the tutorial, system TUIs, files, the swap and the power
actions, all one click from anywhere. `lwin+escape` opens the same menu from
the keyboard, and `lwin+ctrl+t` opens btop in a floating terminal, the same
key Omarchy uses for its Activity view.

Typing a file's name into the launcher searches the whole disk instantly.
That is Everything (voidtools) answering underneath: setup installs it,
adds its indexing service, and keeps its client running in the background
from login onwards, so Flow Launcher's "Everything service is not running"
warning stays gone. If search ever goes quiet, `winmarchy doctor` has a
"file search (Everything)" row that names the broken link and the fix.

While Omarchy mode is on, tapping the Windows key does not open the Start
menu: the key belongs to the tiling layer, exactly like Super on Omarchy.
Every combo still works, Windows 11 mode is untouched, and the guard dies
with the tray icon, so killing the icon returns the key to stock instantly.

The bar is part of Winmarchy rather than a separate program. It draws the
menu button, your workspaces, the window title, the clock, CPU, memory,
volume and power from the same palette as everything else, and it costs a
fraction of what a standalone bar does, since those carry a whole runtime of
their own to show a clock. `lwin+shift+space` hides and shows it. It has no
system tray of its own, so those icons stay on the Windows taskbar, and its
speaker button opens the volume mixer rather than showing a level.

If you would rather use yasb, install it (`winget install -e --id AmN.yasb`)
and run `winmarchy bar yasb`; `winmarchy bar native` comes back to the
built-in one and `winmarchy bar status` says which is in use.

Two more Omarchy habits carry over. Focus follows the mouse: moving the
cursor onto a window activates it, no click needed (a GlazeWM setting, so
Windows 11 mode keeps click-to-focus). And the bar's tray area stays
clean: unpinned icons hide behind the arrow button by default; alt+click
an icon to pin the few you want always visible.

Eight themes ship: tokyo-night, catppuccin, gruvbox, nord, everforest,
rose-pine (light), matte-black and kanagawa. `winmarchy theme set <name>`
recolours the bar, the window borders, Alacritty, Windows Terminal, Cursor,
the wallpaper and the Windows light or dark app mode in one pass; the bar
picks up its new stylesheet without restarting.

Swapping back and forth is `winmarchy mode win11` and
`winmarchy mode omarchy`, from the tray icon, the Start menu, the in-mode
menu on `lwin+escape`, or any shell. The tray icon lives in the chooser
executable, which has no console; without the chooser built it falls back
to a PowerShell host, and on Windows 11 that host's terminal window stays
visible, because Windows Terminal does not honour hidden-console requests.

`winmarchy lockscreen on` themes the lock screen from the active palette,
which also themes the sign-in background, since Windows draws sign-in over
the lock screen picture. It is off by default and it refuses to switch on
unless it can first capture a plain picture to put back afterwards: Windows
Spotlight and slideshows cannot be restored once replaced, and this project
does not change things it cannot undo. `winmarchy lockscreen off` puts your
picture back. Putting the mode chooser *on* the sign-in screen itself is a
different matter, and Winmarchy does not do it; see Honest limitations.

The swap is symmetric, and that is the point. Windows 11 mode is defined as
the total absence of Winmarchy: no GlazeWM, no yasb, taskbar and desktop
icons back, your own wallpaper and light or dark setting restored, your
Alacritty config and Windows Terminal colour scheme back to exactly what
they were, and Cursor's colours back to whatever they were. Entering
Omarchy mode applies all of it again. Installing Winmarchy changes none of
it: until you first enter Omarchy mode, the machine looks and behaves
exactly as it did before.

## Honest limitations

Windows is not a Linux compositor, and four walls cannot be climbed from
user space. DWM owns composition, so there is no frame-level animation or
clipping of other applications' content; GlazeWM places windows, it does
not animate them. UIPI means an unelevated window manager cannot move
elevated windows, so an admin Task Manager or installer will sit where it
likes. The secure desktop, `Win+L` and exclusive-fullscreen games bypass
low-level keyboard hooks entirely. And some applications (Electron apps,
UWP dialogs) fight external placement; GlazeWM window rules cover the known
offenders and more rules can be added over time in
`~/.glzr/glazewm/config.yaml`.

Choosing your desktop *on the Windows sign-in screen* would mean writing a
credential provider: a COM DLL registered under HKLM and loaded by LogonUI
into the secure desktop. That needs administrator rights, and a faulty one
leaves a machine nobody can sign into, on the one screen none of the panic
paths can reach. Recoverability beats beauty, so Winmarchy themes the
sign-in backdrop and leaves the sign-in box to Windows; you choose your
desktop a second later, at the chooser.

The chooser draws with the WebView2 runtime, which ships with Windows 11. If
it is missing or fails, the chooser falls back to a plain window with the
same two options rather than showing nothing. Cursor theming only activates
once Cursor has been run at least once, because that is when it first writes
the settings file Winmarchy edits.

## Uninstall

```
powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

returns the machine to baseline: Windows 11 mode re-asserted, both autostart
entries and the tray icon and the Start menu folder and the PATH entry
removed, the Winmarchy colour schemes taken out of
Windows Terminal while your own settings stay put, your pre-install GlazeWM
and yasb configs restored from the oldest backup set, and
`%LOCALAPPDATA%\winmarchy` removed. `-KeepTerminalTheme`, `-KeepState` and
`-RemoveApps` adjust the edges. It works even when an install half-failed.

## Development

`pwsh -NoProfile -File tools/check.ps1` is the gate: forbidden-character
scan, PSScriptAnalyzer, the Pester suite, config and theme parsing, a
Windows PowerShell 5.1 compatibility grep, an unresolved-token scan and a
task-marker scan tied to FLAGS.md. All PowerShell targets stock Windows
PowerShell 5.1. Tests need Pester 5 or newer plus the powershell-yaml
module. FLAGS.md is the living register of judgement calls and everything
that still needs verification on a real machine;
docs/manual-test-checklist.md is the on-machine test plan.

## Licences

This repository is MIT. GlazeWM is GPL-3.0 and is installed through winget,
never vendored here. Komorebi's source was read for ideas only; its licence
forbids copying and nothing was copied. The theme palettes are ported from
Omarchy (MIT).
