# Winmarchy manual test checklist

These are the checks that only make sense on the real Windows 11 machine.
Run them after any change to the mode manager, the configs, or the installer.
The headless suite (`pwsh -NoProfile -File tools/check.ps1`) must be green
before starting; this checklist covers what it cannot see.

Record the date and outcome of each run at the bottom.

## A. One-off technique verification (first run only)

These verify the Windows techniques the brief flags for on-machine
confirmation. If any fails, record it in FLAGS.md before working around it.

- [ ] A1. Taskbar auto-hide: run `winmarchy mode omarchy`, confirm the
      taskbar slides away and reappears on hover at the screen edge. Run
      `winmarchy mode win11`, confirm it is pinned visible again.
- [ ] A2. Desktop icons: with files on the desktop, confirm icons vanish on
      entering Omarchy mode and return, in the same positions, on returning
      to Windows 11 mode.
- [ ] A3. `wt -w new nvim` opens a new Windows Terminal window running
      Neovim (FLAG-6).
- [ ] A4. `wt -w new --title "Winmarchy Menu" powershell -NoProfile -Command exit`
      opens a new window whose title starts with Winmarchy, and GlazeWM
      floats it centred (FLAG-6).
- [ ] A5. Bar icons render as glyphs, not boxes; if boxes, swap the font
      family order in config/yasb/styles.template.css (FLAG-7).

## B. Swap cycle (run three full cycles)

Each cycle, note anything slow, flickery or out of place.

- [ ] B1. From Windows 11 mode: `winmarchy mode omarchy`. Within 20 seconds:
      GlazeWM tiles a test window, the yasb bar is up with workspaces 1 to 9,
      the taskbar is hidden, desktop icons are gone, the themed wallpaper is
      set.
- [ ] B2. Open three windows; confirm tiling, `lwin+left/right` focus moves,
      `lwin+shift+left` moves the window, `lwin+2` then `lwin+shift+1`
      workspace moves work.
- [ ] B3. `lwin+enter` opens Windows Terminal with the Winmarchy colour
      scheme and JetBrainsMono Nerd Font.
- [ ] B4. `lwin+space` raises Flow Launcher.
- [ ] B5. `winmarchy theme next` (or `lwin+ctrl+space`): bar recolours
      without restart, GlazeWM borders change, wallpaper changes, terminal
      scheme changes in an open window.
- [ ] B6. `winmarchy mode win11`: taskbar back, icons back, original
      wallpaper restored byte-for-byte (check the path in Settings >
      Personalisation), light/dark mode as before, no glazewm or yasb
      process left (check Task Manager).
- [ ] B7. `winmarchy doctor` reports all green for the current mode.

## C. Recovery drills

- [ ] C1. Panic hotkey: in Omarchy mode press `lwin+shift+x`; you land on a
      normal Windows desktop.
- [ ] C2. Mid-swap kill: start `winmarchy mode omarchy` and kill the
      PowerShell window part-way (Task Manager). Run `winmarchy status`:
      it must auto-repair first (journal replay), then report a consistent
      mode. Desktop must be usable throughout.
- [ ] C3. Corrupt state: delete `%LOCALAPPDATA%\winmarchy\state\state.json`
      mid-session; `winmarchy mode win11 -Repair` still restores a clean
      desktop.
- [ ] C4. Start menu: search "Restore Windows 11" and run the shortcut from
      Omarchy mode; confirm clean return.
- [ ] C5. The by-hand worst case in docs/recovery.md is accurate: follow it
      literally with everything closed and confirm each step exists where
      the doc says it is.

## D. Chooser (after Phase 5 is installed)

- [ ] D1. Log out and in: the chooser appears full-screen with the live
      desktop screenshot on the left and the themed mock on the right.
- [ ] D2. The countdown ring counts from 5 and any key or mouse move cancels
      it; letting it lapse enters the last-used mode.
- [ ] D3. Arrow keys plus enter select; escape picks the last mode.
- [ ] D4. Clicking Windows 11 lands on the stock desktop; clicking Omarchy
      enters Omarchy mode.
- [ ] D5. "Don't ask at login" checkbox: tick it, log out and in, no
      chooser; re-enable via `winmarchy menu` (system menu, chooser toggle).
- [ ] D6. Kill the PowerShell child mid-swap from the chooser; the fallback
      lands on the Windows 11 desktop.

## Run log

| Date | Sections run | Result | Notes |
|---|---|---|---|
|  |  |  |  |

## E. Setup wizard (run before section B, on a machine with no install)

- [ ] E1. Double-click install-ui.cmd from a fresh clone: the wizard window
      opens centred, dark, with the step rail on the left.
- [ ] E2. System check page lists all seven checks with sensible values for
      this machine; amber rows do not block Next.
- [ ] E3. Theme page: clicking each of the eight themes updates the preview
      panel (bar, workspace dots, focused border, tile lines) to that
      palette, and rose-pine visibly reads as a light theme.
- [ ] E4. Components page: with a Neovim config present, that option is
      greyed and explains why. Unticking "Build the login chooser" greys and
      clears "Show the chooser when I log in".
- [ ] E5. Review page shows the plain-language summary, an accurate
      equivalent command line, and a step list matching what install.ps1
      -WhatIf prints in a terminal.
- [ ] E6. Install page streams the log live, scrolls to the bottom, and the
      Cancel and Back buttons are disabled while it runs.
- [ ] E7. Finish page appears on completion; ticking "Start Omarchy mode
      when I close this" and pressing Close enters Omarchy mode.
- [ ] E8. Re-run the wizard on the now-installed machine: the system check
      reports the existing install and describes the run as an update.
- [ ] E9. install-ui.ps1 -Console asks the same questions in text and
      produces the same result.
