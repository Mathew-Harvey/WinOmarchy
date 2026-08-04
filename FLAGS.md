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

## FLAG-24: Alacritty failed to install, and Winmarchy could not say why

Context: Mat's install log showed Alacritty.Alacritty FAILED with exit code
-1978334964. Everything else installed. Running "winget install
Alacritty.Alacritty" by hand immediately afterwards succeeded.

The code, verified rather than guessed. -1978334964 is 0x8A15010C,
APPINSTALLER_CLI_ERROR_INSTALL_CANCELLED_BY_USER, documented as "You cancelled
the installation." Source: microsoft/winget-cli,
doc/windows/package-manager/winget/returnCodes.md, whose header records that it
is generated by running "winget error", so it matches the shipping binary;
corroborated in src/AppInstallerSharedLib/Public/AppInstallerErrors.h and
Errors.cpp.

Provenance of that specific code for this specific package. The Alacritty
manifest in winget-pkgs declares InstallerType: wix, Scope: machine, a
PackageDependency on Microsoft.VCRedist.2015+.x64, and no ExpectedReturnCodes.
With no manifest-declared codes, winget falls back to GetDefaultKnownReturnCodes
in src/AppInstallerCommonCore/Manifest/ManifestCommon.cpp, whose Wix branch has
exactly one route to CancelledByUser: ERROR_INSTALL_USEREXIT, which is 1602,
"The user canceled installation" (learn.microsoft.com/windows/win32/msi/error-codes).
So Windows Installer itself returned 1602 and winget relabelled it.

That rules two things out. It was not the VCRedist dependency: a dependency
failure is rewritten to APPINSTALLER_CLI_ERROR_INSTALL_DEPENDENCIES (0x8A150110)
and a missing one is 0x8A150104. And it was not winget itself being cancelled,
which terminates with E_ABORT.

What is NOT settled: why msiexec returned 1602 in that run. The strongest
hypothesis, and it is only a hypothesis, is that Alacritty is a machine-scope
package, Winmarchy never elevates, and a UAC approval prompt was dismissed or
timed out. That is consistent with it installing by hand a minute later. It
would be settled by the winget log for that run under
%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir
if it still exists. Recorded as unproven, not diagnosed.

Judgement: no Winmarchy code change would have prevented the failure. What
Winmarchy did wrong was everything after it, which is FLAG-25.

Status: closed as to the meaning of the code; the reason msiexec returned 1602
is deferred-to-machine and may never be settled. Alacritty is now installed on
Mat's machine, confirmed by him.

## FLAG-25: a failed package was invisible, and stayed invisible

Context: the failure in FLAG-24 sat in a log Mat read and did not notice, and
every tool that should have caught it afterwards said the machine was healthy.
Reviewed adversarially: thirty five candidate defects were raised across three
dimensions, six survived two independent verifiers each, and the rest are
recorded as considered and dismissed.

The six, and what was done:

1. The exit code was printed as a raw negative integer, and winget's own
   English was piped to Out-Null. Now Get-WinmarchyWingetOutcome (bin/lib/common.ps1)
   classifies the code as installed, present, reboot or failed, and renders it
   as a sentence with the hex, and install.ps1 captures winget's output and
   prints its last few lines under a failure. Only the codes that change what
   the installer DOES are tabulated; everything else falls back to winget's own
   words, which stay correct as winget changes.

2. Only two codes were treated as benign. 0x8A15010D and 0x8A15010E, both
   meaning the machine already has the app, were reported as hard failures, and
   the two reboot codes were not distinguished from failure. All are classified
   now. 0x8A150109 is deliberately absent from every list: winget rewrites it
   to success internally and it cannot appear as an exit code.

3. doctor resolved two executables, glazewm and yasbc, so a machine with no
   terminal reported a clean bill of health while lwin+enter did nothing. There
   is now one shared table, Get-WinmarchyBindingCriticalApps, used by doctor,
   the preflight and the installer, and a FAIL row names the keys that die and
   the winget command that fixes it. A Nerd Font row was added too, because the
   bar renders every glyph as an empty box without it while nothing else looks
   wrong.

4. The preflight Alacritty row was hardcoded to pass and tested for
   alacritty.toml, a file Winmarchy writes itself, so after one swap it read
   "found" on a machine with no Alacritty at all. It now resolves the
   executable. Same for the Cursor row, which no longer conflates "not
   installed" with "installed but never run".

5. install.ps1 patched one of four Alacritty invocations. The keybinding
   overlay, the system menu and the theme menu hardcoded the bare name and
   could never be patched, so a Program Files install worked for lwin+enter and
   failed for the other three. All four are patched now, through
   Update-WinmarchyGlazewmAppPaths, with tests. Paths are written unquoted:
   GlazeWM's parse_command joins whitespace-separated parts cumulatively until
   one names a real file, whereas its quoted branch takes the THIRD double
   quote as the closing one and so mis-parses a quoted program followed by a
   quoted argument (verified in
   ref/glazewm/packages/wm/src/commands/general/shell_exec.rs).

6. The closing summary printed "warnings: 1 (see above)" and then a confident
   ten-line keybinding list advertising the very keys the failure had broken.
   The summary now names each failed package, what it was for, what it costs,
   and the retry command, and any key whose app did not install is marked NOT
   WORKING in the top ten.

Also corrected, and the likeliest cause of the original failure: install.ps1,
the wizard's welcome page, the components note and the README all promised that
nothing needs administrator rights. That is false. Winmarchy's own files and
settings are per-user, but Alacritty is a machine-scope winget package and
Windows raises an approval prompt for it. Telling a user to expect no prompts
is how a prompt gets dismissed. All four now say plainly that Windows will ask,
and that dismissing a prompt skips that app.

Explicitly NOT done, with reasons, so these are not revisited blindly:
pre-installing VCRedist (it was not the failing component, and doing it would
record a false cause); a full forty-entry winget code table (printing winget's
own English gets the same benefit and cannot drift); retry-with-backoff on
transient codes (re-running the installer is already idempotent, and it would
add ten magic constants for a failure this project has never hit); aborting the
loop on cancellation codes (Ctrl+C unwinds PowerShell before the exit code is
read, and the primary path is a wizard with no console); doctor rows for the
eight CLI conveniences (nothing in the repo binds them).

Deferred-to-machine: the Nerd Font row matches on the family name in the
documented Fonts registry key, but the value name winget's font package writes
is not documented anywhere. Confirm the row passes on Mat's machine before
trusting it.

Status: closed.

## FLAG-26: entering Omarchy mode crashed on the taskbar call, on the real machine only

Context: Mat could watch the bar appear and GlazeWM start tiling, then the
whole swap rolled back to Windows 11, every time. The log named it:
"enter-omarchy failed: Cannot convert the "1" value of type "System.UInt64"
to type "System.IntPtr"".

Root cause: Set-WinmarchyTaskbarAutoHide computed the new appbar state as a
uint64 (the bit maths casts through uint64) and assigned it with
"$data.lParam = [IntPtr]$newState". Windows PowerShell 5.1 has no conversion
from an unsigned integer type to IntPtr, so the assignment throws. PowerShell
7, which is what the build container runs, converts it happily, and the
effector is mocked in every test, so the only place this line ever executed
for real was Mat's machine. The rollback then worked exactly as designed,
which is why the failure looked like "Omarchy flashes and undoes itself"
rather than a broken desktop.

Fix: cast through a signed type first, "[IntPtr][int64]$newState". Guard:
check.ps1's 5.1 compatibility grep now fails any direct [IntPtr] cast of a
variable anywhere in the repo, with the message telling the author to go
through [int64]. Literal casts like [IntPtr]0x7402 are Int32 and unaffected.

Lesson recorded for the register: "compatible with 5.1" cannot be fully
proven from a container that only has PowerShell 7. The grep now covers this
class; anything of this kind that a grep cannot see remains FLAG-1 territory.

Status: closed; confirmation that the swap completes end to end on the
machine is part of checklist section H.

## FLAG-27: the tray icon kept a terminal window open

Context: Mat reported a terminal window that stays up and should be hidden.
The tray was bin/tray.ps1 hosted by powershell.exe, registered with
-WindowStyle Hidden and backed by a ShowWindow(SW_HIDE) call. On Windows 11
the default terminal is Windows Terminal, and Windows Terminal does not
honour either mechanism: ShowWindow on GetConsoleWindow() does not hide the
window when Terminal is the host (microsoft/terminal issues 12570 and 15311).
A console process that never exits therefore keeps a visible terminal window
for the whole session.

Decision: the icon moved into the chooser executable, which is a WinExe with
no console at all. "Winmarchy.Chooser.exe --tray" runs chooser/TrayApplet.cs:
same menu, same theme-coloured icon, same single-instance mutex name
(Local\WinmarchyTray) as the script version, so the two hosts can never both
show an icon. Menu actions run the dispatcher with CreateNoWindow, which
never allocates a console, rather than a hidden window, which allocates one
and asks for it to be concealed. The Keybindings and Theme menu entries are
console programs on purpose and open a real terminal.

bin/tray.ps1 remains as the fallback for installs without the .NET SDK; the
installer says plainly that under that host a terminal window will be
visible, and its own detached launches now use CreateNoWindow too. The
installer stops any running icon before starting the new one, because the
old one holds the mutex. Tests pin the label parity between the two hosts
and the shared mutex name.

Status: closed.

## FLAG-28: the login chooser auto-continued before the user arrived

Context: "when i restart windows it boots straight into windows, not the
selector". The log shows the opposite of a missing chooser: at 15:42:55 the
chooser started at login, and at 15:43:02, seven seconds later, "user chose
win11" was recorded. Nobody chose anything. The chooser's countdown was five
seconds, auto-continuing to the last mode, and the log line for an expired
countdown was identical to the line for a real click. Five seconds after the
desktop appears is before a person has arrived; from the chair it reads as
"no selector, straight into Windows".

Fix: the countdown is twenty seconds in both faces (rich and plain), any
mouse movement or key press still cancels it instantly, and an expiry now
logs "countdown expired with no input, continuing to <mode>" so it can never
again be mistaken for a choice. The page already cancelled on input; only
the window length and the logging were wrong.

Status: closed.

## FLAG-29: app installers littered the desktop

Context: "The installed software puts icons on my desk top i don't want
this". Several of the sixteen winget packages drop a desktop shortcut on
install. Winmarchy also added two of its own swap shortcuts, which the same
complaint covers.

Decision: the installer snapshots every .lnk on the user's desktop and the
shared desktop before the winget loop, and afterwards removes exactly the
ones that appeared, naming each removal in the log. Shortcuts on the shared
desktop cannot always be removed without admin rights; those are listed in a
warning for removal by hand rather than failed over silently. Winmarchy's
own desktop shortcuts are gone: setup no longer creates them, removes the
two an earlier install created, and the tray icon plus the Start menu folder
carry every entry point. The uninstaller keeps its desktop cleanup for old
installs.

The snapshot-and-diff is deliberately scoped: only shortcuts that appeared
between the two moments the installer looked are touched, so nothing the
user placed themselves can ever be swept up.

Status: closed.

## FLAG-30: wallpaper folder cycling, in both modes

Context: Mat asked for setup to take a folder of wallpapers and for BOTH
modes to cycle random pictures from it. That makes Windows 11 mode no longer
strictly "the absence of all Winmarchy effects": with a folder configured,
Winmarchy changes the Windows wallpaper too. Recorded as a deliberate scope
change on the user's explicit instruction, not a drift. With no folder set,
nothing changes: themed wallpapers in Omarchy mode, Windows keeps its own.

Mechanics: the wizard's components page and install.ps1 -WallpaperDir set
state.wallpaperDir; a picture is dealt on every swap, every theme change,
every half hour from the tray timer, on lwin+ctrl+b and from the menus. The
picker avoids repeating the current picture when there is a choice. If the
folder goes missing, cycling pauses with a log line rather than failing.
"winmarchy wallpaper off" stops it and leaves the current picture in place;
an exact restore is impossible once the user has been cycling by choice, and
the pre-install wallpaper remains recorded in the oldest backup manifest.

Status: closed.

## FLAG-31: the bar's top-left menu button

Context: Omarchy's bar has a menu in the top left that reaches everything.
Emulated with a yasb CustomWidget (shape verified against
ref/yasb/docs/widgets/(Widget)-Custom.md) whose on_left callback execs
"winmarchy menu popup" through the winmarchy.cmd shim on the user PATH. The
popup opens the system menu in the same floating Alacritty the lwin+escape
binding uses, with a plain PowerShell window as the stand-in when Alacritty
is missing. The system menu itself grew to carry everything: themes,
wallpaper, keys, tutorial, the TUIs, files, the swap, config editing, the
chooser toggle and power.

Status: closed; the glyph rendering and click behaviour need the machine.

## FLAG-32: the Windows key no longer opens the Start menu in Omarchy mode

Context: Mat: "in omarchy the windows key should not trigger the windows
menu". GlazeWM swallows bound combos but a bare Win tap still reaches the
shell. No supported per-user setting turns that off cleanly, and the NoWinKeys
policy is a blunt instrument that also needs Explorer to restart.

Decision: WinKeyGuard.cs, a low-level keyboard hook (SetWindowsHookExW,
WH_KEYBOARD_LL) inside the tray host. When a Windows key goes down and comes
back up with no other key in between, and state.mode reads omarchy, SendInput
injects the unassigned virtual key 0xE8 before the key-up passes, so the
shell sees a combo rather than a bare tap and Start stays shut. Nothing is
ever swallowed, so no key can stick. The mode is re-read at most once a
second. The guard's lifetime is the tray's: kill the icon and the Windows key
is stock again instantly, which is the recoverability story. In Windows 11
mode the key behaves exactly as stock. Limitation: no guard when the tray is
running under the PowerShell fallback host; recorded, not worked around.

Status: closed; needs on-machine confirmation that combos still fire and
Win+L still locks.

## FLAG-33: system TUIs

Context: Omarchy leans on TUIs for system work. Mirrored where the tools
already ship: lwin+ctrl+t opens btop in a floating terminal, the same key
Omarchy binds for its Activity view (verified verbatim in
ref/omarchy/default/hypr/bindings/utilities.lua: "SUPER + CTRL + T",
"Activity", tui btop). "winmarchy stats" is the command underneath, running
btop4win (falling back to btop) in the current console. The system menu
carries "System stats (btop)" and "Git TUI (lazygit)". lazydocker is not
mirrored: Winmarchy does not install Docker. The btop4win executable name
is resolved at runtime rather than assumed; if the winget package names its
binary differently on the machine, doctor's guidance and the stats command
both surface it rather than failing silently.

Status: closed; the btop4win executable name is deferred-to-machine.

## FLAG-34: each mode's theme must never modify the other's

Context: Mat's instruction, verbatim: "The theme that was in windows, should
not be modified by the omarchy theming and vice versa." Two defects broke
that promise, one latent on his machine right now.

First, the terminal and editor baselines were captured once and kept forever
(the old comment called it deliberate). So a colour scheme or font the user
changed IN WINDOWS between swaps was clobbered by the stale snapshot on the
next return from Omarchy mode. Fixed: entering Windows 11 mode now clears
every captured baseline (terminal, editor, wallpaper, app mode alike), and
each Omarchy entry recaptures whatever the user has set in Windows by then.
The capture-once gate within a single Omarchy session stays, so mid-session
theme changes cannot capture Winmarchy's own values.

Second, the poisoned baseline. Mat's first install ran a build old enough to
theme Windows Terminal unconditionally; his terminal still carries that
scheme in Windows mode. The next successful Omarchy entry would have
captured "Winmarchy Rose Pine" as HIS setting and then faithfully restored
the Omarchy look into Windows mode on every exit, forever. Guards now sit at
the capture points: a terminal scheme matching "Winmarchy *" or the
JetBrainsMono Nerd Font face, and Cursor colours identical to any shipped
theme's rendered template, are treated as no baseline, which makes the
restore strip them instead of reinstate them. His machine heals on the first
full swap cycle after updating. The font guard can misfire for a user who
genuinely chose that font before Winmarchy; the cost is the font resetting
to the terminal default once, accepted and recorded.

Also fixed in the same round: check.ps1 counted only failed tests, so a test
FILE that failed to parse reported ALL GREEN while its whole container of
tests silently never ran. It happened during this change (an apostrophe in a
test name). The gate now fails on broken containers explicitly.

Status: closed; the on-machine confirmation is one full swap cycle showing
the Windows terminal scheme, font, colours, wallpaper and light/dark exactly
as the user left them, with checklist item J covering it.

## FLAG-35: wallpaper recursion and the cycling interval

Context: Mat asked for the wallpaper function to recurse through all
subfolders, flatten the pictures into one pool, and change on a chosen
interval (5, 10 or arbitrary minutes, a slider), persisted in both modes.

Decisions: the scan recurses (Get-ChildItem -Recurse) so the whole tree is
one pool and new pictures join the moment they land; the flattening is
logical, at scan time, never a physical copy, which would duplicate the
collection and go stale. The interval is state.wallpaperIntervalMinutes
(default 30, clamped 1 to 1440), set by the wizard's slider (1 to 120),
install.ps1 -WallpaperIntervalMinutes, or "winmarchy wallpaper every <n>".
Both tray hosts tick once a minute and count up to the interval, so a
changed interval takes effect within a minute instead of after the old
interval runs out. Folder and interval live in state.json, which is mode
independent: they persist across swaps, sign-outs and reboots in both modes.

Status: closed.

## FLAG-36: the Windows key guard shipped armed but firing blanks

Context: Mat: "the windows key still opens the windows menu in omarchy
mode". Two independent defects, both of the class only the real machine
could catch.

First, the guard never armed. It decided the mode by searching the raw
state.json text for the substring "mode": "omarchy" with one space after
the colon. Windows PowerShell 5.1's ConvertTo-Json writes TWO spaces after
the colon; PowerShell 7, which writes the file in the build container,
writes one. Green here, dead there, exactly the FLAG-26 lesson in a new
coat. The guard now parses the file properly through WinmarchyState.Load,
once a second, and a test forbids the raw-text sniff from returning.

Second, even armed it fired too late. The dummy key was injected during the
Windows key-UP's own hook callback, and SendInput queues behind the
in-flight key-up, so the shell saw a completed bare tap and opened Start
before the unassigned key ever landed. The injection now happens on the
key DOWN: the shell sees Win plus an unassigned key while Win is held, the
tap is cancelled up front, and every real combo still works because 0xE8
is bound to nothing. Nothing is swallowed in either direction, so no key
can stick and Windows 11 mode remains untouched.

Status: closed; needs the machine to confirm a bare tap opens nothing in
Omarchy mode while combos and Win+L still fire.

## FLAG-37: desktop icons stuck hidden in Windows mode

Context: Mat: "In windows mode i can no longer put files on my desk top and
view them." The icon toggle is a blind WM_COMMAND to SHELLDLL_DefView, and
the code trusted the registry HideIcons value as the current state. Those
two can disagree: any missed or doubled toggle, or an interrupted swap,
leaves reality (icons hidden) out of step with belief (registry says
visible), after which enter-win11 reads "already visible", does nothing,
and the desktop stays empty in Windows mode with no path back.

Fix: the state is now read LIVE. The desktop icons are the SysListView32
child of the DefView, and the show/hide command shows and hides that
window, so IsWindowVisible on it is the actual truth (FindWindowEx and
IsWindowVisible, both documented user32 calls). The registry is now only
Explorer's startup belief, written to match reality on every set, and the
toggle verifies itself afterwards: if the live state still disagrees, it
falls back to registry plus an Explorer restart rather than walking away
wrong. A machine already stuck heals on the next enter-win11 or repair,
because the live read sees the truth. By hand, right-clicking the desktop,
View, Show desktop icons does the same.

Status: closed; the live read and the self-heal are checklist items.

## FLAG-38: the Windows key guard could be silently killed by its own mode check

Context: third report of the same symptom after FLAG-36's two fixes: "the
windows key still triggers in omarchy mode".

The structural defect found on re-reading: the mode check ran INSIDE the
low-level hook callback. It was throttled to once a second, but that once
did a file read plus a JSON parse plus, on failure, a log append, and the
first call also paid the cold JIT of the whole parse path. Windows gives a
low-level hook callback a hard time budget (LowLevelHooksTimeout, described
under the LowLevelKeyboardProc documentation), and a callback that overruns
can have its hook silently removed. One slow first read and the guard is
dead for the entire session, with nothing in any log, which matches the
report exactly and would have kept matching it no matter how correct the
arming logic became.

Fix: the callback now touches nothing but a volatile flag, a struct read
and SendInput; the marshalling path is pre-warmed at install so no
first-call JIT lands inside it. The mode lives on a one-second WinForms
timer on the tray's message loop: it parses state.json, flips the flag,
logs "armed" and "disarmed" transitions, re-establishes the hook whenever
the mode turns to omarchy (a fresh hook at the moment it matters, in case
anything removed the old one), and reports a masked-tap count so the log
finally carries evidence of the guard firing. Doctor gained a "tray
running" row that names the host, because the guard only exists in the exe
host and a PowerShell-hosted tray showing the icon is indistinguishable
from a working guard by looking at the notification area.

What the next report needs if the symptom survives even this: the doctor
output (the tray running row), and whether the log shows "win key guard:
armed" and any "masked N bare tap(s)" lines while in Omarchy mode. Those
three facts separate "guard not running", "guard not arming" and "guard
firing but the shell ignoring the mask", which are three different bugs.

Status: closed pending on-machine confirmation (checklist I10 retests).

## FLAG-39: the swap now owns the Windows key guard's liveness

Context: fourth report of the Start menu opening in Omarchy mode, with no
log or doctor output to separate "guard not running" from "guard not
arming" from "mask ignored". The masking mechanism itself (vkE8 injected on
key-down) is AutoHotkey's own default menu mask and is sound when the guard
is live, so every remaining explanation is a liveness problem: a stale exe,
a PowerShell-hosted tray, a tray not running at all, or a failed hook.

Decision: entering Omarchy mode now ENSURES the guard instead of hoping.
If the chooser exe exists and the running tray is not the exe host (or is
not running), the swap stops whatever icon is up and starts the exe host;
if the chooser exe does not exist, the swap says plainly that nothing can
stop the Windows key opening Start and how to fix it. Never fatal to the
swap. The tray logs its own build timestamp at start, so the log proves
WHICH build is running; the guard's re-hook path logs failure instead of
dying silently.

Still open until Mat sends three facts from the machine: doctor's "tray
running" row, the "win key guard: armed" line, and a "masked N bare
tap(s)" line. Together they pin the failure to one of the three causes.

Status: closed as to the self-healing; the on-machine confirmation is
checklist I12.

## FLAG-40: the Windows key guard, third mechanism, and the reason the first two could not work

Context: fifth report. Doctor now proves the tray runs in the exe host with
the guard installed, so the mechanism itself was the last suspect standing,
and on analysis both earlier mechanisms were geometrically incapable of
working: SendInput only ever APPENDS to the input queue, so a mask injected
during the key-up's hook callback lands after the up (v1), and one injected
during the down lands before the up but after the down has already been
delivered, leaving the up still bare from the shell's point of view on any
build that checks the up itself (v2). Neither could put the mask BETWEEN
the down and the up, which is the only place it counts.

Mat, mid-round, proposed a Scancode Map script (HKLM Keyboard Layout,
remap-to-null). Declined with reasons: it kills the key at the driver, so
every lwin binding dies with it including lwin+shift+x, the panic key; it
needs admin, which this project has avoided throughout; and it only applies
at reboot, so it cannot follow a hot swap at all. It solves the Start menu
by deleting the keymap.

The third mechanism controls ordering by construction: on a bare Windows
key UP in omarchy mode, the hook SWALLOWS the physical up (returns 1) and
replays the tail as injected input: mask down, mask up, Windows key up.
The mask now sits between the down and the up because the up the system
delivers IS part of the replay. It also degrades safely if a future build
ignores injected input entirely: the shell then sees a down with no up,
and a tap that never completes opens nothing. The key cannot stick: the
replay is sent FIRST and the real up is only swallowed when SendInput
accepted all three events; on any failure the real up passes untouched.
Autorepeat of a held Windows key no longer resets the combo flag. Combos
are passed through entirely.

Also added: a doctor row for the "do not ask at login" flag, because a
ticked box routes every login straight to the last mode and is
indistinguishable from a broken chooser without looking at state. That is
the leading explanation for "on restart i don't get the selector": the
chooser logs "chooserDisabled is set, going straight to <mode>" when it
happens, and the row now names the fix.

Status: closed pending the machine; if a "masked N bare tap(s)" line
appears AND Start still opens, the shell is not seeing our swallow, which
would point at another agent re-injecting the up, and the log will say so.

## FLAG-41: the GlazeWM-native Windows key option, investigated and ruled out

Context: "go hard" on the sixth round of the Start menu. The obvious
question finally asked properly: can GlazeWM itself own the bare Windows
key? Its hook already suppresses bound combos, and a bare ['lwin'] binding
would be mode-scoped for free.

Answer from its source: no. GlazeWM fires a binding when the combo's LAST
key goes down and suppresses that keystroke
(wm-platform/src/keybinding_listener.rs, trigger_key and the hook closure
returning true). A bare lwin binding therefore swallows the Windows key
DOWN. But combo matching tests held modifiers through GetKeyState
(platform_impl/windows/keyboard_hook.rs, is_key_down_raw), which is OS
keyboard state, and a suppressed keystroke never updates OS state. Swallow
the down and GetKeyState reports the key up, so every lwin combo dies with
the Start menu. Not viable, recorded so nobody walks this path again.

What shipped instead: the guard's heartbeat. The tray guard now writes
state/winkey-guard.json once a second (pid, armed, maskedTaps, tick time),
and doctor gained a "win key guard" row that reads it: no heartbeat is a
dead guard, a stale tick is a dead timer, armed=false in omarchy mode is a
guard that cannot see the mode, and maskedTaps is the count of taps it
actually intercepted. Tap the key three times, run doctor, and the row
either shows the count rising or names which link is broken. The
uncertainty that ate five rounds is now one command.

Status: closed.

## FLAG-42: a Winmarchy wallpaper captured as the user's own

Context: "the theme for omarchy pollutes the windows again". The wallpaper
baseline is captured on entering Omarchy mode; if a Winmarchy wallpaper was
still up at that moment, left behind by any earlier failed round on this
machine, the capture records it as "the user's wallpaper" and every return
to Windows faithfully restores the Omarchy look. The same poisoned-baseline
disease FLAG-34 fixed for the terminal, one surface over.

Fix, both ends: at capture, a wallpaper under the winmarchy wallpapers
directory is never accepted as a baseline; the pre-install truth from the
OLDEST backup manifest is captured instead (the installer has recorded the
wallpaper there since Phase 4). At restore, the same test runs against
whatever is already in state, so an old poisoned capture heals on the next
swap to Windows 11 mode. The light/dark app mode cannot be guarded the same
way, because dark is dark whoever set it; if the pollution Mat sees
includes the app mode, the manifest holds the pre-install values and the
same substitution can be added there.

Status: closed; on-machine confirmation is one swap cycle showing the
user's own wallpaper back in Windows mode.

## FLAG-43: every reinstall kept running the original chooser exe

Context: the doctor output that finally broke the case open. "tray running:
in the chooser exe" alongside "win key guard: no heartbeat; the guard has
never run" can only mean the running exe predates the guard entirely, and
the reason is mechanical: Windows locks executing binaries, the installer
ran dotnet publish into the chooser directory while the OLD tray exe from
that directory was still running, publish failed to overwrite the locked
file, the "chooser build failed" warning scrolled past among sixteen
winget lines, and the tray restart step then dutifully relaunched the OLD
exe. Every pull-and-reinstall round repeated the cycle, which is why five
generations of Windows key guard fixes changed nothing on the machine: not
one of them ever executed there. The mechanism fixes were fixing code that
was never run.

Fix, three layers: the build step now STOPS the tray and any running
chooser before publishing (the tray step later restarts the fresh build);
a failed publish prints the build tool's own last lines and says plainly
that the OLD code keeps running; and after a "successful" publish the exe's
timestamp is compared against the build start, so a lock failure can never
again masquerade as a completed install. A test pins the ordering: the
process stop must precede dotnet publish in install.ps1.

Lesson for the register, the third of its kind: FLAG-25 was "trust the exit
code", FLAG-26 and 36 were "trust the container to behave like 5.1", and
this is "trust that deploying replaced what was running". The register rule
generalises: an installer must verify what is on disk and running after it
acts, never infer it from the steps having reported success.

Status: closed; the on-machine confirmation is the very next reinstall
printing "chooser exe fresh, built <today>", followed by doctor's guard
row showing "armed" and a rising masked-tap count.
