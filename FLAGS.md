# FLAGS.md

Living register of judgement calls, deviations from the build brief, unverified
assumptions, and known limitations. Numbered, never deleted; closed entries keep
their number. A TODO or FIXME in code is only allowed if it cites a FLAG-n from
this file.

Status values: open (needs a decision), closed (decision made and recorded),
deferred-to-machine (cannot be verified in the Linux build container; needs a run
on Mat's Windows 11 machine).

## FLAG-1: built in a Linux container, machine gates deferred

Context: this build runs in a remote Ubuntu container with PowerShell 7.4.6
(pwsh), not on Mat's Windows 11 machine. All headless gates (check.ps1,
PSScriptAnalyzer, Pester, template rendering, config parsing) run here. Anything
that touches a real Windows session cannot run here: the manual swap checklist,
taskbar and desktop icon toggling, wallpaper application, winget installs, the
chooser render screenshot, real install and uninstall, the panic hotkey.

Decision: all code still targets Windows PowerShell 5.1 (enforced by the
compatibility grep in check.ps1 plus review discipline). Every on-machine gate is
listed in docs/manual-test-checklist.md and stays deferred-to-machine here rather
than being claimed as passed.

Status: deferred-to-machine.

## FLAG-2: repository name is WinOmarchy, product name is Winmarchy

Context: the brief describes a repo layout under a directory named winmarchy/.
The actual GitHub repository is Mathew-Harvey/WinOmarchy.

Decision: the Section 3 layout applies at the repository root unchanged. The
product, command, and install directory names stay winmarchy as specified.

Status: closed.

## FLAG-3: check.ps1 YAML parsing needs a parser dependency

Context: neither Windows PowerShell 5.1 nor PowerShell 7 ships a YAML parser.

Decision: check.ps1 uses the powershell-yaml module if present, otherwise falls
back to Python with PyYAML, otherwise fails with an instruction to install one.
The build container has powershell-yaml 0.4.12 installed.

Status: closed.

## FLAG-4: Pester 5 or newer required for the test suite

Context: Windows PowerShell 5.1 ships Pester 3.4.0, which cannot run this suite.
The build container has Pester 6.0.1.

Decision: tests are written for the Pester 5+ configuration API. check.ps1
detects Pester older than 5 and fails with the install instruction
(Install-Module Pester -Force -SkipPublisherCheck).

Status: closed.

## FLAG-5: catppuccin nvim colorscheme deviates from Omarchy deliberately

Context: Omarchy ships the colorscheme name catppuccin-nvim for its catppuccin
theme. The brief directs Winmarchy to use the long-documented catppuccin-mocha
instead and to note the deviation. Theme JSON cannot carry comments, so the
note lives here.

Decision: themes/catppuccin.json sets nvim.colorscheme to catppuccin-mocha.

Status: closed.

## FLAG-6: wt -w new must be verified on the machine

Context: the keymap launches Neovim and the popup menu terminals with
"wt -w new" to force a new Windows Terminal window. It is the documented flag
for that purpose, but the brief (Section 6) requires verifying it on the
machine in Phase 2, and this container has no Windows Terminal.

Open question for Mat: run "wt -w new nvim" and
"wt -w new --title \"Winmarchy Menu\" powershell -NoProfile -Command exit"
once; confirm each opens a new window and the title sticks.

Status: deferred-to-machine.

## FLAG-7: yasb font family name needs an on-machine render check

Context: the brief (Section 4.3) says the GDI engine wants
'JetBrainsMono NFP' or 'JetBrainsMono Nerd Font' and to test which renders
icons correctly on the machine. styles.template.css lists both, NFP first.

Open question for Mat: after install, check the bar icons render as glyphs,
not boxes. If boxes, swap the order of the two families in
config/yasb/styles.template.css and run winmarchy theme set again.

Status: deferred-to-machine.

## FLAG-8: adversarial review findings applied after Phase 1

Context: a three-reviewer adversarial pass over the Phase 1 code confirmed
three real defects, all fixed with regression tests: (1) redirected native
stderr under ErrorActionPreference Stop crashes on Windows PowerShell 5.1
(check.ps1 now relaxes the preference around native calls); (2) the JSONC
comment and trailing-comma strippers were plain regexes that could corrupt
string values such as "cmd.exe /c echo {a,}" inside Windows Terminal
settings.json (now a string-aware character walk); (3) PowerShell pipeline
unrolling collapsed one-element and empty arrays in state round-trips (fixed
with comma-prefixed returns). Hardening from the same review: torn journal
lines are skipped with a warning, an unparseable state file falls back to
defaults, state writes go through a temp file and rename, null profiles or
defaults or schemes in settings.json are normalised, check.ps1 scans dotfiles
with -Force and survives unreadable files, and theme cycling compares names
case-insensitively.

Status: closed.

## FLAG-9: taskbar and desktop icon techniques need machine verification

Context: the brief (Section 3) prescribes SHAppBarMessage ABM_SETSTATE for
taskbar auto-hide and WM_COMMAND 0x7402 to SHELLDLL_DefView for the live icon
toggle, with registry fallbacks, and says to verify both on the machine in
Phase 3 before relying on them. The container cannot exercise either. Both
are implemented with the registry state read first (0x7402 is a blind
toggle) and the icon path falls back to HideIcons plus an Explorer restart
when SHELLDLL_DefView cannot be found.

Open question for Mat: checklist items A1 and A2 in
docs/manual-test-checklist.md cover this; if either technique no-ops on the
current Windows 11 build, say so and the fallback becomes the primary.

Status: deferred-to-machine.

## FLAG-10: config/ is deployed alongside bin/, themes/ and templates/

Context: the brief Section 7.5 step 4 lists bin/, themes/ and templates/ as
the payload copied to %LOCALAPPDATA%\winmarchy. The theme engine re-renders
the yasb stylesheet at runtime from config/yasb/styles.template.css, so that
file must exist in the deployed tree too.

Decision: install.ps1 also copies config/ to %LOCALAPPDATA%\winmarchy\config,
keeping one path shape (root/config/yasb/styles.template.css) valid in both
the repo and the deployed layout.

Status: closed.

## FLAG-11: chooser render test and crash-fallback drill need the machine

Context: dotnet build of the chooser is clean (0 warnings, 0 errors, built
from the container with EnableWindowsTargeting), but the Phase 5 gate also
wants the --render-test screenshot reviewed, the mid-swap kill fallback
demonstrated, and the countdown and keyboard paths exercised. Those need
Windows with the WebView2 runtime. A stand-in preview of the page rendered
in headless Chromium was produced and shared for the visual eyeball.

Open question for Mat: after install, run
"%LOCALAPPDATA%\winmarchy\chooser\Winmarchy.Chooser.exe --render-test" and
review artifacts\chooser.png, then run checklist section D.

Status: deferred-to-machine.

## FLAG-12: the Phase 7 end-to-end run is Mat's sign-off

Context: the definition of done is the Section 1 vision statement being
demonstrably true on the machine: chooser at login, both halves beautiful,
clean swaps both ways surviving reboots and a mid-swap kill, panic hotkey,
uninstall to baseline. None of that can run in the build container.

Open question for Mat: run docs/manual-test-checklist.md end to end
(sections A through D plus three B cycles), record the run in its log
table, and file anything that misbehaves as a new FLAG entry.

The full deferred-to-machine set at handover: FLAG-1 (environment), FLAG-6
(wt -w new), FLAG-7 (bar font rendering), FLAG-9 (taskbar and icon
techniques), FLAG-11 (chooser render test and fallback drill), and this
entry.

Status: deferred-to-machine.

## FLAG-13: final adversarial review findings applied at wrap-up

Context: a four-reviewer pass (5.1 compatibility, safety audit, brief
conformance, chooser C#) with two adversarial skeptics per finding confirmed
four real defects, all fixed with tests: (1) the captured win11 baseline
(wallpaper, light/dark) was never cleared after restore, so changes the user
made later in Windows 11 mode were silently reverted on every subsequent
swap-back; enter-win11 now clears the saved values so the next Omarchy entry
recaptures the current baseline. (2) Uninstall restored the install-day
Windows Terminal settings wholesale, destroying customisations made since;
it now surgically removes only the Winmarchy schemes and the
defaults.colorScheme reference, and leaves settings.json.winmarchy-bak in
place as a by-hand recovery option. This deliberately deviates from the
brief's "restore from the bak" wording in favour of its intent (baseline
restoration without collateral loss). (3) The numbered menu fallback wrote
its display lines into the function's return stream; they now go to the
console directly. (4) The chooser never subscribed to WebView2 ProcessFailed
and relied on implicit focus; it now falls back on a process failure and
focuses the WebView after navigation. A separate mid-build fix: the first
enter-omarchy now applies wallpaper and app mode via an explicit -AsOmarchy
switch (state.mode still reads win11 until commit) with both mutations
journalled.

Status: closed.

## FLAG-14: setup wizard is WPF hosted in PowerShell, untestable headlessly

Context: the guided installer needs to run on a machine where nothing is
installed yet, so it cannot depend on the .NET SDK (which would be a
chicken-and-egg problem, since the SDK is only needed to build the chooser
and may be absent). It is therefore a WPF window hosted directly in Windows
PowerShell 5.1 via XamlReader: no build step, no dependency, runs from a
fresh clone. The XAML carries no x:Class and no event attributes because
XamlReader cannot bind them; every handler is wired in PowerShell, and a
test asserts the file stays that way.

Decision: all decision logic lives in installer/wizard-lib.ps1 with no UI,
so preflight rules, option interlocks, the answers-to-parameters mapping and
the review text are all covered by tests (including one asserting the wizard
only ever names parameters install.ps1 actually has). The wizard never
reimplements the install: every choice becomes a switch passed to
install.ps1, and the review page's step list is real install.ps1 -WhatIf
output. A text-mode wizard (install-ui.ps1 -Console) asks the same questions
and is the automatic fallback when WPF cannot start; that path was smoke-run
end to end in the container.

Open question for Mat: the WPF window itself cannot run here, so the visual
result, the STA launch through install-ui.cmd, the runspace log streaming
and the theme preview all need a run on the machine. A rendered mock of the
four main pages was produced and shared for the design eyeball. Checklist
section E covers the run.

Status: deferred-to-machine.

## FLAG-15: install page hung with an empty log; run mechanism replaced

Context: reported from the machine. The wizard reached the Install page and
sat there with an empty log and no progress. The first line install.ps1
writes never appeared, so the child never produced output, and because the
page was shown and the buttons disabled BEFORE the run was started, a
failure during start-up left the window frozen with nothing to read.

Cause: the run used a background runspace with
PSDataCollection plus a generic BeginInvoke overload, and nothing wrapped
it, so any failure setting that up was swallowed by the WPF event handler
under ErrorActionPreference Stop. The path had no test, which is why it
shipped broken.

Decision: install.ps1 now runs as a child powershell.exe process with its
output redirected to a log file that the window tails. That removes the
generic-overload and cross-thread concerns, gives winget a real console,
yields an honest exit code, and leaves a log file behind for
troubleshooting. Start-up and every timer tick are wrapped so any failure
is written into the log and shown on the summary page: a frozen page with
an empty log is now impossible. Five tests drive the real path end to end,
including one asserting the first log line reaches the window, one that a
failing install reports rather than hangs, and one for partial-line
handling.

Status: closed.

## FLAG-16: false failure verdict and black check marks in the wizard

Context: reported from the machine with the log attached. The install ran
perfectly start to finish (all 16 winget packages, deploy, configs, chooser
build, shortcuts, wallpapers, theme) and the log ended with the normal
summary, but the wizard showed "Setup did not finish". Separately, the ok
and x marks on the system check page rendered black instead of green, amber
or red.

Cause one: the redirected error file was empty, so the false verdict came
from the exit code. Start-Process -PassThru can return a Process whose
ExitCode throws even after a clean run, and the code turned that exception
into -1, which then read as a failure. install.ps1 also had no explicit exit
statement, so its exit code could be inherited from the last native command
(winget reports "already installed" and "no applicable upgrade" as non-zero
values).

Cause two: the check marks and the theme swatches bound Foreground and
Background to SolidColorBrush objects held on PSCustomObjects. WPF cannot
convert a PowerShell-wrapped Brush, so the binding failed silently and the
elements fell back to their default black. Text bindings on the same objects
worked, which is why only the colours were wrong.

Decision: install.ps1 now ends with an explicit exit 0, so the exit code is
a contract rather than an accident. Complete-WinmarchyInstallRun calls
WaitForExit first, and an unreadable exit code is no longer treated as
failure: it falls back to the error stream. All colour bindings are now hex
strings, which WPF converts through the target property's type converter,
and a test asserts no {Binding *Brush} pattern can return to the XAML. Five
tests cover the verdict rules, including unreadable exit codes and warnings
being distinguished from errors.

Status: closed.

## FLAG-17: mode swap made symmetric; installing no longer changes Windows

Context: Mat's requirement, stated after seeing his terminal reskinned by
the installer: swapping to Windows 11 must restore every setting Windows
had, swapping to Omarchy must apply every Winmarchy effect, and neither
direction may leave a mess.

Two surfaces broke that rule. The Windows Terminal colour scheme and font
face, and the Neovim theme file, were applied at install time and persisted
across both modes, because the brief (Sections 5 and 4.4) treats them as
install-time actions. Everything else was already mode-scoped.

Decision: both are now Omarchy-mode surfaces only.
  - theme-set writes the terminal scheme, the terminal font and the Neovim
    plugin file only when Omarchy mode is active (or -AsOmarchy is passed by
    enter-omarchy, which commits its mode after the health check).
  - The first terminal patch captures the pre-Winmarchy colorScheme and
    font.face into state; enter-win11 calls the new Restore-WtSettingsFile,
    which drops every Winmarchy scheme and puts those two values back,
    removing the keys entirely if they were absent before. Every other
    terminal setting, including ones added since, is left alone.
  - enter-win11 also removes the Neovim theme file, which Winmarchy owns
    outright, so Neovim returns to its own colourscheme.
  - The captured terminal baseline is deliberately NOT cleared on the way
    out, unlike the wallpaper baseline: it records the terminal as it was
    before Winmarchy ever ran, and the restore has just written those values
    back, so clearing it would make the next Omarchy entry capture
    Winmarchy's own settings as the baseline.
  - install.ps1 therefore no longer reskins anything. Installing sets
    Winmarchy up; the machine only changes when Omarchy mode is entered.

This is a deliberate deviation from the brief's wording in favour of its
Section 1 intent, that Windows 11 mode is bone-stock Windows. Seven tests
cover it, including a terminal patch-then-restore round trip against both a
file with no colour scheme and one with an existing scheme and font.

Status: closed.

## FLAG-18: onboarding tutorial, and Cursor replaces Neovim

Context: Mat asked for an onboarding tutorial teaching a Windows user the new
keys, and to swap Neovim for Cursor and Windows Terminal for Ghostty.

Tutorial: bin/tutorial.ps1 renders templates/tutorial.html.tpl in the active
palette and opens it in the default browser. It is HTML rather than another
WPF window on purpose: it can be rendered and inspected in the build
container, which WPF cannot. It opens automatically the first time Omarchy
mode is entered (state key tutorialSeen) and on demand with
winmarchy tutorial. Lessons name bindings; the bindings come from the live
GlazeWM config, and two tests enforce the contract in both directions: every
key taught must be bound, and every bound key must be either taught or on the
explicit not-taught list. Lessons lead with the way out (Super Shift X) and
every card says what the key replaces in Windows terms.

Cursor: winget id Anysphere.Cursor, verified present in microsoft/winget-pkgs
with versions through 1.5.1. Cursor is a Visual Studio Code fork, so it is
themed by setting workbench.colorCustomizations in
%APPDATA%\Cursor\User\settings.json from the palette, using documented VS
Code theme colour identifiers. Like the terminal, this is an Omarchy-mode
surface only: the previous value of that one key is captured on the first
patch and put back on entering Windows 11 mode, or the key is removed
entirely when Cursor had no customisations before. Neovim, the LazyVim
starter step, the -SkipNeovim switch, the wizard's Neovim option and
zig.zig (which existed only for nvim-treesitter) are all removed rather than
left as dead weight.

Status: closed.

## FLAG-19: Ghostty has no official Windows build; terminal unchanged for now

Context: Mat asked to replace Windows Terminal with Ghostty. Verified against
the Ghostty project's own Windows support discussion
(github.com/ghostty-org/ghostty/discussions/2563): as of April 2026 there is
no official Windows executable or installer. Maintainers state they want a
Direct3D renderer and have not settled on a frontend, and they explicitly
discourage unofficial builds using the Ghostty name. Only third-party forks
exist, none of them in winget.

Decision: not implemented. Installing an unofficial fork of a terminal as the
user's default shell is a supply-chain risk that needs Mat's explicit
agreement, and the brief's hard constraint 8 forbids relying on anything
unverified. Windows Terminal stays the themed terminal until Mat chooses.

Open question for Mat: three options. (1) Stay on Windows Terminal and revisit
when Ghostty ships Windows support. (2) Move to Alacritty, which is what
Omarchy itself uses, is official on Windows, is in winget as
Alacritty.Alacritty (0.17.0), and whose exact palette template already exists
in ref/omarchy for a verbatim port. (3) Adopt a named community Ghostty fork,
accepting the risk. Recommendation is 2 if the goal is Omarchy fidelity, 1 if
the goal is Ghostty specifically.

Status: closed. Mat chose option 2, Alacritty. See FLAG-20.

## FLAG-20: Alacritty is the themed terminal

Context: Mat chose option 2 from FLAG-19. Alacritty is what Omarchy itself
uses, has official Windows support, and is in winget as
Alacritty.Alacritty.

Verified before implementing, against the Alacritty man page in the project
repository: the Windows config location is %APPDATA%\alacritty\alacritty.toml,
and the import mechanism is an import array inside a [general] section.

Decision: templates/alacritty.toml.tpl is a verbatim port of Omarchy's
default/themed/alacritty.toml.tpl colour mapping (see ref/omarchy), with
Omarchy's two derived keys substituted directly: selection_background is
selection, selection_foreground is bright_foreground.

Winmarchy writes the whole alacritty.toml rather than editing it or adding
an import line. Two reasons: TOML forbids a table being declared twice, so
appending a [general] section to a config that already has one would break
it, and there is no TOML parser on stock Windows PowerShell 5.1. Any
pre-existing config is copied to alacritty.toml.winmarchy-bak exactly once;
entering Windows 11 mode restores that backup, or removes the file entirely
when it was ours to begin with. That keeps the swap symmetric with no TOML
surgery. Same treatment in the uninstaller.

lwin+enter and the popup menu and keybinding terminals now launch Alacritty,
using its documented --title and -e flags; --title keeps the existing
GlazeWM float rule working for the Winmarchy popups. install.ps1 resolves
the Alacritty path at the winmarchy:terminal-path marker the same way it
does the launcher and editor.

Windows Terminal theming is deliberately kept. It is the terminal Windows
itself opens from Win+X and right-click menus, so leaving it unthemed while
everything else is themed would look broken. It is mode-scoped and restored
exactly as before.

Status: closed.

## FLAG-21: the chooser did not appear at login, and could not say why

Context: Mat installed, signed out, signed back in, and nothing appeared. The
install log showed the chooser built and the Run key registered, with no
warnings, so every check the installer had said the install was fine.

Root cause analysis: the chooser had four ways to fail after starting, and all
four ended the same way. A missing WebView2 assembly threw out of the MainWindow
constructor into Main's catch; a WebView2 environment that would not create, a
navigation that would not complete, and a renderer crash each called
Program.Fallback and then Close(). Fallback writes a log line and runs
"mode win11 -Repair", which on an already-stock desktop does nothing visible. So
every failure looked identical from the user's chair: a login where nothing
happened. The exact trigger on Mat's machine is still unknown, and with the
process exiting silently there was no way to find out from the outside.

Decisions, in order of how much they matter:

1. The chooser now has a second face. chooser/FallbackWindow.xaml is a plain WPF
   chooser with no WebView2 in it: the same two options, keyboard and mouse
   driven, coloured from the active palette. Every one of the four failure paths
   now hands over to it instead of closing, and it shows the reason it is
   standing in. The rule this encodes is that a failure of the pretty path must
   degrade to the plain path, never to silence. Chooser.Tests.ps1 asserts the
   hand-over count so a future edit cannot quietly restore the old behaviour.
2. RollForward is set to LatestMajor in the csproj. The chooser is built on the
   user's own machine with whatever SDK they have; a net8.0 app will not start
   on a machine that has only a newer Desktop Runtime, because the default
   rollForward policy does not cross a major version. A WinExe failing that way
   shows nothing useful at login. This is a plausible cause of Mat's symptom and
   is cheap to rule out for good.
3. install.ps1 now verifies what actually landed rather than trusting the
   publish exit code: the exe and ui\index.html both have to be there, and a
   missing WebView2 runtime and a Windows-disabled startup entry are both called
   out as warnings.
4. doctor checks the whole chain end to end: chooser installed, Run key present
   AND pointing at a file that exists, the Windows startup toggle, the WebView2
   runtime, and the tray entry.
5. "winmarchy chooser" runs the chooser now, in the current session, so a
   failure can be seen rather than inferred. "winmarchy chooser plain" forces
   the plain face.

Unverified: which of these was Mat's actual failure. That can only be settled on
his machine, by running "winmarchy doctor" and then "winmarchy chooser".

Status: closed (the silent-failure class is fixed); the specific trigger is
deferred-to-machine.

## FLAG-22: no way into Omarchy from a stock Windows desktop

Context: Mat's report, verbatim: "while im in windows, there is no ui element in
the windows menu to change to omarchy". The Start menu shortcuts existed, but
Windows filed them under Recommended and Recently added, where they are easy to
miss and eventually scroll away.

Decision: bin/tray.ps1, a notification area icon built on WinForms NotifyIcon.
No build step, no service: the script is the process, and every action shells out
to the dispatcher in a separate process so a failed swap cannot take the icon
down. It carries the swap, the chooser, the theme menu, the keybindings, the
tutorial and the panic path. The menu is rebuilt on every open, so it always
shows the current mode and theme, and the icon is redrawn from the palette when
the theme changes.

Two rules keep it from drifting: every label it shows that it does not own
itself must exist in Get-WinmarchySystemMenuEntries, which is what executes it
(asserted in Tray.Tests.ps1), and the labels come from one pure function that
takes state in and returns labels out, so the menu shape is testable without a
desktop.

install.ps1 registers it under a second Run key value, WinmarchyTray, starts it
immediately so the swap is reachable without signing out, and also puts "Swap to
Omarchy mode" and "Swap to Windows 11 mode" on the desktop. The wizard has a
checkbox for it and install.ps1 has -NoTray. uninstall.ps1 removes the Run key,
stops a running copy and deletes the desktop shortcuts.

Judgement call: a permanently resident PowerShell process is more parts than
this project likes. It is justified because the alternative is the complaint
that prompted it: shortcuts nobody can find. It is a single script, it can be
switched off at install time or dismissed at any time from its own menu, and
nothing else depends on it.

Undocumented territory: Test-WinmarchyStartupDisabledByWindows reads
HKCU\...\Explorer\StartupApproved\Run to tell whether Windows has the startup
entry switched off in Settings. That location is not documented by Microsoft.
The check is read-only, reports "not disabled" whenever it cannot tell, and is
used only to print a diagnostic line, so being wrong costs nothing.

Status: closed.

## FLAG-23: a mode chooser on the Windows sign-in screen

Context: Mat asked whether the selection could happen at the sign-in screen
itself, and for that screen to be themed.

Answer on the selector: no, not within this project's constraints. Putting UI on
the sign-in screen means writing a credential provider: an in-process COM DLL
registered under HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\
Credential Providers, loaded by LogonUI into the secure desktop. That requires
administrator rights, which this project has avoided everywhere else, and a
faulty credential provider can leave a machine that nobody can sign into. Hard
constraint 1 says the machine must never be left unable to reach a normal
Windows desktop; a component that runs before the desktop exists, on the secure
desktop, where none of the panic paths reach, is the one place where that
promise cannot be kept. Not building it.

What is delivered instead: Windows draws the sign-in screen over the lock screen
picture by default, so theming the lock screen themes the sign-in backdrop.
New-WinmarchyLockScreenImage paints the palette gradient with the accent glow
behind where the sign-in box lands and the wordmark low left, and
Set-WinmarchyLockScreenImage applies it through
Windows.System.UserProfile.LockScreen.SetImageFileAsync, which is per-user and
needs no admin. Windows PowerShell 5.1 cannot await a WinRT IAsyncOperation
directly, so Wait-WinmarchyWinRtResult bridges through the AsTask extension
methods on WindowsRuntimeSystemExtensions.

Opt in only, by "winmarchy lockscreen on", and off by default. The reason is
symmetry, which Mat asked for in his own words: a wallpaper can be put back
exactly, but a lock screen cannot. Setting a picture moves Personalisation >
Lock screen off Windows Spotlight or a slideshow, and putting the original file
back afterwards leaves it on Picture. So Winmarchy refuses to turn the feature
on at all unless it can first capture a plain file to restore, and says why. In
Omarchy mode the themed image applies; entering Windows 11 mode puts the
captured original back, and the mutation is journalled like every other.

Status: closed.

## FLAG-24: Alacritty failed to install on Mat's machine

Context: Mat's install log shows Alacritty.Alacritty FAILED with exit code
-1978334964 (0x8A15010C). Everything else installed. Winmarchy's terminal
keybinding, its popup menu and its keybinding overlay all launch Alacritty, so
those keys do nothing until it is present.

Not reproducible in the build container; winget is Windows-only and the code
path is a plain winget install call that succeeded for the other fifteen
packages. Verifying the meaning of that specific code needs the machine.

Action for Mat: run "winget install Alacritty.Alacritty" by hand and read the
message. Nothing in Winmarchy needs changing until that message is known.

Status: deferred-to-machine.
