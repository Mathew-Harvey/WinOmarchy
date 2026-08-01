# Recovery, worst case first

Winmarchy is built so you can always get back to a normal Windows desktop.
This page starts from the ugliest situation and works back to the easy ones.
Explorer is never replaced as the shell, so the machine always has more
underneath than it appears to when something goes wrong.

## The by-hand worst case

Screen looks wrong, no bar, no taskbar, keybindings dead, nothing responds
the way you expect. Do this, in order:

1. Press Ctrl+Alt+Del and choose Task Manager.
2. In Task Manager choose Run new task (File menu on the compact view),
   type `explorer.exe`, tick "Create this task with administrative
   privileges" only if plain explorer refuses to start, and press Enter.
   You now have a desktop and a Start button even if the taskbar is still
   hidden.
3. Run new task again and enter:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File %LOCALAPPDATA%\winmarchy\bin\winmarchy.ps1 mode win11 -Repair
   ```

   That replays any interrupted swap from the undo journal and re-asserts
   the full Windows 11 baseline: GlazeWM and yasb stopped, taskbar pinned,
   desktop icons shown, your original wallpaper and light or dark setting
   restored.
4. If the winmarchy files themselves are gone or broken, fix the two things
   a swap changes by hand:
   - Taskbar: Settings > Personalisation > Taskbar > Taskbar behaviours,
     untick "Automatically hide the taskbar".
   - Desktop icons: right-click the desktop > View > Show desktop icons.
   Wallpaper and colours are under Settings > Personalisation as usual.

## The panic hotkey

In Omarchy mode, `lwin+shift+x` runs `winmarchy mode win11` immediately.
It works whenever GlazeWM is alive enough to see keys.

## The Start menu shortcut

Search the Start menu for "Restore Windows 11 (repair)". It runs the same
repair command as the worst case above and is available in both modes.

## From any shell

```
winmarchy mode win11 -Repair
```

Every `winmarchy` invocation also checks the undo journal first and repairs
automatically if a previous swap was interrupted, so simply running
`winmarchy status` after a crash is already enough to trigger recovery.

## The chooser

The chooser at login can never strand you: any internal failure or a
20 second hang triggers its fallback, which runs the repair command above
and exits. If the chooser itself is the annoyance, tick "Don't ask at
login" on it, or toggle the same flag from `winmarchy menu`, or delete the
`Winmarchy` value under
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

## Where the evidence lives

- Log: `%LOCALAPPDATA%\winmarchy\log\winmarchy.log` (every component,
  timestamped, errors name the failing step).
- Undo journal: `%LOCALAPPDATA%\winmarchy\state\journal.jsonl` (non-empty
  only while a swap is mid-flight or was interrupted).
- Backups: `%LOCALAPPDATA%\winmarchy\backup\<timestamp>\` with a
  `manifest.json` describing what was saved; the oldest set is your
  pre-Winmarchy machine state, and `settings.json.winmarchy-bak` beside the
  Windows Terminal settings file preserves the original terminal config.

## Full removal

```
powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

from the repo checkout returns the machine to baseline even when an install
half-failed. It never assumes a healthy install.
