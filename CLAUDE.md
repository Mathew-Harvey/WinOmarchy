# CLAUDE.md

Standing rules for any Claude session working in this repository. These distil the
Winmarchy build brief (Sections 2, 9, and 10). The brief is the source of truth; this
file is the always-loaded summary. Do not weaken these rules without Mat's say-so.

## What this project is

Winmarchy gives Mat's Windows 11 machine two modes: stock Windows 11, and an
Omarchy-inspired mode (GlazeWM tiling, yasb bar, Flow Launcher, themed terminal and
Cursor, one palette driving every surface). A chooser appears at login; a hot swap is
available from either mode. Explorer stays the shell at all times. Windows 11 mode is
defined as the absence of all Winmarchy runtime effects.

## Hard constraints

1. Recoverability beats beauty. The machine must never be left unable to reach a
   normal Windows desktop. Every mutating operation records an undo first. A panic
   path always exists: the lwin+shift+x hotkey, the "Restore Windows 11 (repair)"
   Start menu shortcut, `winmarchy mode win11 -Repair` from any shell, and
   docs/recovery.md for the by-hand worst case.
2. Least parts, most basic tech. No frameworks where vanilla works, no service where
   a script works, no abstraction with one implementation.
3. Stack: PowerShell for system automation, C# (.NET 8) only for the chooser host,
   plain HTML/CSS/JS in WebView2 for chooser UI. No npm build step, no Electron,
   no Tailwind.
4. All PowerShell must run on stock Windows PowerShell 5.1. Forbidden: ternary
   operator, null-coalescing (`??`), pipeline chain operators (`&&`, `||`),
   `ForEach-Object -Parallel`. Check `$LASTEXITCODE` after native commands. Write
   text files with `[System.IO.File]::WriteAllText()` (UTF-8, no BOM), never
   `Out-File -Encoding utf8` (BOM breaks YAML parsers).
5. Never use an em dash or en dash anywhere: code, comments, docs, strings, commit
   messages. tools/check.ps1 fails the build if one appears.
6. Australian English in all prose (colour, behaviour, licence as noun, organise).
   Plain prose, no AI-slop phrasing.
7. Licences: this repo is MIT. GlazeWM is GPL-3.0, installed via winget, never
   vendored. Never copy code from komorebi (its licence forbids it); reading its
   source for ideas is fine.
8. No fabricated APIs. Any Windows API, CLI flag, config key, or registry value not
   stated in the brief's Section 4 must be verified against official docs or the
   ref/ clones before use, with a comment saying where it was verified.
9. Windows 11 only. Windows 10 is out of scope.

## Process contract

1. Plan before code, every phase: restate acceptance criteria, list files to touch,
   note deviations. Genuine forks get numbered options plus a recommendation.
2. `tools/check.ps1` is the machine gate. Run it after every meaningful change.
3. Fix loop: read the whole error, reproduce in isolation, fix one thing, re-run.
   After three failed attempts on the same error, stop, record it in FLAGS.md with
   the verbatim error, and ask Mat.
4. Self-review every phase diff against the hard constraints before declaring done.
   Hunt for: silent API guesses, missing backups before mutations, missing undo
   journal entries, 5.1 violations, invented config keys.
5. FLAGS.md is the register. Every judgement call, deviation, unverified assumption,
   and known limitation gets a numbered entry. Never let a known problem ride
   unrecorded. Never silently fix what you are unsure of.
6. Never claim completion without evidence (gate output, artefact path, doctor
   table). If something could not be run, say exactly that.
7. Verify external claims at the point of use: yasb widget options from
   ref/yasb/docs, GlazeWM syntax from ref/glazewm/resources/assets/sample-config.yaml,
   Omarchy patterns from ref/omarchy. Cite the file path in a comment when copying
   a shape.
8. Surgical diffs. No reformatting or drive-by improvements outside the task.

## Safety and recovery requirements

- Undo journal: every mutating step in a swap appends (action, previous value) to
  `%LOCALAPPDATA%\winmarchy\state\journal.jsonl` before acting; the journal is
  cleared on successful commit; `repair` replays outstanding entries in reverse.
- On every chooser start and every `winmarchy` invocation, a non-empty journal
  triggers repair before anything else.
- Logging: every component appends timestamped lines to
  `%LOCALAPPDATA%\winmarchy\log\winmarchy.log`; errors name the failing step.
- The installer never proceeds past a failed backup. The uninstaller never assumes
  a healthy install.

## Environment notes

- Development may happen on a Linux container with PowerShell 7 (pwsh). All code
  still targets Windows PowerShell 5.1; the compatibility grep in check.ps1 guards
  the syntax level, and discipline guards the rest. Anything that can only be
  verified on Mat's Windows 11 machine is recorded in FLAGS.md as deferred, never
  claimed as passed.
- Run checks with: `pwsh -NoProfile -File tools/check.ps1` (or powershell.exe on
  Windows).
