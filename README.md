# Winmarchy

Winmarchy gives a Windows 11 machine two personalities. One is stock
Windows 11, untouched. The other is an Omarchy-inspired desktop: GlazeWM
tiling driven from the Super key, a slim themed yasb bar instead of the
taskbar, Flow Launcher on `lwin+space`, a themed Windows Terminal and
Neovim, and one colour palette driving every surface. A chooser appears at
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
winget by the installer itself; nothing needs admin rights.

## Install

Download or clone this repository onto the Windows 11 machine, open the
folder, and double-click **install-ui.cmd**. That opens the setup wizard,
which walks you through it in seven steps:

1. **Welcome** explains what you are about to get and how to get back.
2. **System check** looks at the machine and tells you what it found:
   Windows version, whether winget and the .NET SDK are there, free space,
   whether you already have a Neovim config or a previous install. Anything
   genuinely missing stops the wizard here rather than failing halfway.
3. **Theme** lets you pick a palette from the eight that ship, with a live
   preview of the bar, the window borders and the tiling layout in that
   palette.
4. **Components** is where you choose what to set up: the apps, Neovim, the
   login chooser, and whether the chooser appears at login. Options whose
   prerequisites are missing switch themselves off and say why, so you
   cannot pick something that will fail later.
5. **Review** shows the decisions in plain language, the equivalent command
   line if you would rather run it yourself, and the complete step-by-step
   plan. Nothing has been changed at this point.
6. **Install** runs it with a live log.
7. **Finish** hands over the ten keybindings worth knowing and offers to
   start Omarchy mode straight away.

If you prefer a text prompt, `install-ui.ps1 -Console` asks the same
questions in the terminal. That is also the automatic fallback if the
graphical wizard cannot open.

To skip the questions entirely and install with defaults:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

Add `-WhatIf` to print the full action list without touching anything.
`-Theme <name>` picks the palette; `-SkipApps`, `-SkipNeovim`,
`-SkipChooser` and `-NoAutostart` correspond to the wizard's component
choices. The wizard passes these same switches, so there is only one
install path either way.

However you start it, the installer backs up everything it is about to
touch into `%LOCALAPPDATA%\winmarchy\backup\<timestamp>\` before its first
mutation and refuses to continue if that backup fails. Apps are installed
per-user through winget; no admin prompt is expected.

One note on Windows Terminal: its settings.json may contain comments, and
the first time Winmarchy patches it those comments are lost. The original
file is preserved beside it as `settings.json.winmarchy-bak`, and uninstall
removes only what Winmarchy added rather than reverting the whole file.

## Daily use

`winmarchy keys` (or `lwin+k` in Omarchy mode) shows the full keymap, read
live from the GlazeWM config. The spine of it: `lwin+enter` terminal,
`lwin+space` launcher, `lwin+1` to `lwin+9` workspaces, `lwin+arrows`
focus, `lwin+shift+arrows` move, `lwin+w` close, `lwin+f` fullscreen,
`lwin+escape` the system menu, `lwin+ctrl+space` next theme. Windows keeps
`Win+L` for lock and `Alt+Tab` stays native.

Eight themes ship: tokyo-night, catppuccin, gruvbox, nord, everforest,
rose-pine (light), matte-black and kanagawa. `winmarchy theme set <name>`
recolours the bar, the window borders, the terminal, Neovim, the wallpaper
and the Windows light or dark app mode in one pass; the bar picks up its
new stylesheet without restarting.

Swapping back and forth is `winmarchy mode win11` and
`winmarchy mode omarchy`, from the menu, from the Start menu shortcuts, or
from any shell. Windows 11 mode is defined as the absence of Winmarchy's
runtime effects: no GlazeWM, no yasb, taskbar and icons back, your original
wallpaper and colour mode restored from the values captured before Omarchy
mode first ran.

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

The chooser needs the WebView2 runtime, which ships with Windows 11. The
Neovim theming only activates when a LazyVim config exists; the installer
sets one up only if you have no Neovim config at all, and never touches an
existing one.

## Uninstall

```
powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

returns the machine to baseline: Windows 11 mode re-asserted, autostart and
shortcuts and PATH entry removed, the Winmarchy colour schemes taken out of
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
