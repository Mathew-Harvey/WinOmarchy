# Why antivirus flags Winmarchy, and what to do about it

Windows Defender, SmartScreen and other engines sometimes flag Winmarchy.
This page says exactly which behaviours cause that, where each one lives in
the source, why it is there, and how to get the detection corrected properly.

Nothing here is a trick for hiding from a scanner. There is no packing, no
obfuscation and no attempt to look like something else, and there never will
be: this is software people run at login, and it has to be inspectable. The
routes below are the ones that fix the problem permanently.

## The short version

Winmarchy ships **no executable at all**. The repository contains source
plus one icon file, which `tools/make-icon.py` generates and anyone can
regenerate. The program that gets flagged is compiled **on your own machine**
by `dotnet publish` during setup, from the C# in `chooser/`. You can read
every line of it before you run it, and you can diff what you built against
the source.

That also means a detection is a judgement about **behaviour**, not about a
known bad file, because there is no shipped file to have a reputation.

## The behaviours that trigger it, and why each exists

### A system-wide keyboard hook that swallows and injects keystrokes

`chooser/WinKeyGuard.cs` installs a `WH_KEYBOARD_LL` hook, sees every
keystroke on the machine, suppresses some and synthesises others with
`SendInput`. In isolation that is the shape of a keylogger, and it is fair
for an engine to be suspicious of it.

Why it exists: in Omarchy mode the Windows key belongs to the window manager,
as Super does on Omarchy itself. Windows opens the Start menu when it sees a
Windows key press and release with nothing in between, so the guard puts a
harmless unassigned key (0xE8) between them. That is the entire mechanism.

What it does NOT do, and what you can verify in that one file, which is
around 400 lines including comments:

- it records nothing: no buffer, no file, no accumulation of keystrokes
- it sends nothing anywhere: there is no network code in it at all
- it only ever acts on the Windows key itself; every other key passes
  through untouched
- it is disarmed unless the recorded mode is `omarchy`, and it dies with the
  tray icon, so closing the icon returns the key to stock immediately

### A background process that starts at login

The tray icon runs windowless from an `HKCU\...\Run` entry
(`Set-WinmarchyRunKey` in `bin/lib/common.ps1`). Persistence plus a hidden
window plus a keyboard hook is a well-known malware profile.

Why it exists: it hosts the notification area icon, the mode swap, and the
key guard, which has to outlive any one command to work at all.

### PowerShell started with `-ExecutionPolicy Bypass`

Every shortcut, the `winmarchy` shim and the chooser start PowerShell this
way. Defender's attack-surface-reduction rules weigh that heavily, because
it is how a lot of real attacks run their payload.

Why it exists: Winmarchy is a collection of unsigned local scripts, and the
default policy on Windows client editions refuses to run any script at all.
Without the flag nothing works. Signing the scripts (see below) is the way
to stop needing it.

### Registry and personalisation changes

Setup writes the Run key, the user PATH entry, the wallpaper, the light and
dark mode setting, and the taskbar auto-hide state. Bulk personalisation
changes look like the tail end of an infection.

Why they exist: they are the modes. Every one of them is journalled before
it happens and restored on the way back to Windows 11; see `docs/recovery.md`.

### Miscellaneous

`SHAppBarMessage` to reserve the bar's strip, `SystemParametersInfo` to set
the wallpaper, a WebSocket to `127.0.0.1:6123` to talk to GlazeWM, and
starting third-party programs. All ordinary, all local, all visible in the
source.

## What to do, in the order worth doing it

### 1. Report the false positive to Microsoft

This is the fix that helps everyone, not just you. Submit the file at:

https://www.microsoft.com/en-us/wdsi/filesubmission

Submit as a **software developer**, choose "incorrectly detected"
(false positive), attach the flagged `Winmarchy.Chooser.exe`, and link this
page and the repository. The points worth making in the description:

- the binary is built from public source on the user's own machine
- the detection is behavioural: a keyboard hook and a Run key
- the hook's entire purpose is one key, it stores nothing, and it has no
  network code anywhere in the process
- the repository ships no binaries

Turnaround is usually a few days, and a corrected verdict propagates to
every machine rather than each user working around it.

### 2. Sign the executable

An unsigned binary that hooks the keyboard and starts at login has the worst
possible reputation profile, and nothing else fixes that as thoroughly. A
standard code-signing certificate quiets SmartScreen and lowers heuristic
weighting; an EV certificate skips SmartScreen's reputation build-up
entirely. This costs money and needs a real identity behind it, so it is the
maintainer's call rather than something setup can do for you.

Once the C# is signed, signing the PowerShell too would let the scripts run
under `AllSigned` and remove the `-ExecutionPolicy Bypass` flag from every
launch, which is the other large heuristic trigger.

### 3. Only then, an exclusion on your own machine

If you need it working today, you can exclude the install directory
(`%LOCALAPPDATA%\winmarchy`) under Settings > Privacy and security > Windows
Security > Virus and threat protection > Exclusions.

Understand the trade before you do it: an exclusion means Defender stops
inspecting that folder for everything, not just for Winmarchy. Prefer step 1,
and treat this as the stopgap it is. Do not exclude your whole user profile
or a whole drive.

## If you think it is NOT a false positive

Take that seriously rather than assuming. Check what you actually built:

- `winmarchy doctor` prints the commit the install was built from, so you
  can compare it against this repository
- the flagged file should be `%LOCALAPPDATA%\winmarchy\chooser\Winmarchy.Chooser.exe`,
  compiled locally; if a scanner names a file somewhere else, or names a
  downloaded installer, that did not come from here
- upload the file to VirusTotal: a local build with one or two heuristic
  hits reads very differently from a file with many named-family detections

If something genuinely looks wrong, raise it on the repository with the
detection name and the file path, and do not run it in the meantime.
