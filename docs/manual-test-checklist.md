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
- [ ] A3. `lwin+shift+n` opens Cursor.
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
- [ ] B8. Symmetry: after B6, open Windows Terminal and confirm the colour
      scheme and font are exactly what they were before Winmarchy (check
      Settings > Appearance, and that no "Winmarchy ..." scheme is offered).
      Open Cursor and confirm its colours are its own again. Then
      `winmarchy mode omarchy` and confirm both come back.

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
- [ ] E4. Components page: unticking "Build the login chooser" greys and
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

## F. Login chooser, tray icon and lock screen

Run F1 first: it is the fastest way to find out why nothing appeared at
login, and it either passes or tells you exactly which link is broken.

- [ ] F1. `winmarchy doctor` on the installed machine. Every row in the
      chooser chain passes: chooser installed, run key autostart, startup
      entry enabled, webview2 runtime, tray autostart. Record any FAIL row
      verbatim.
- [ ] F2. `winmarchy chooser` shows the chooser in the current session,
      within a couple of seconds. Choosing either mode does what it says.
- [ ] F3. `winmarchy chooser plain` shows the plain window instead: two
      cards, arrow keys move the selection, Enter chooses, Escape gives
      Windows 11, the countdown stops on the first key or mouse move, and
      the colours match the active theme.
- [ ] F4. Sign out and back in: the chooser appears by itself.
- [ ] F5. Tick "Do not ask at login" in the chooser, sign out and back in:
      no chooser, and the machine goes straight to the last mode. Undo it
      with the "Chooser at login" toggle in the system menu.
- [ ] F6. The Winmarchy icon is by the clock (check under the caret; Windows
      hides new icons there until they are dragged out). Left click and
      right click both open the menu.
- [ ] F7. The tray menu header shows the current mode and theme, and the
      swap entry follows the mode. Swap from the tray both ways.
- [ ] F8. Tray: Show the chooser, Theme menu, Next theme, Keybindings,
      Tutorial and Restore Windows 11 (repair) all do what they say. The
      icon recolours after Next theme.
- [ ] F9. "Hide this icon" removes it; `winmarchy tray` brings it back; two
      copies of `winmarchy tray` still leave exactly one icon.
- [ ] F10. Desktop: "Swap to Omarchy mode" and "Swap to Windows 11 mode"
      shortcuts are there and work, with no console window flashing up.
- [ ] F11. `winmarchy lockscreen on` while Windows is set to Spotlight:
      refuses, and names Settings > Personalisation > Lock screen.
- [ ] F12. Set a picture in Settings, then `winmarchy lockscreen on`, enter
      Omarchy mode, press Win+L: the lock and sign-in screens show the
      themed image. Return to Windows 11 mode: your own picture is back.
- [ ] F13. `winmarchy lockscreen off` puts the picture back and stops
      Winmarchy touching it again.
- [ ] F14. uninstall.ps1: the tray icon disappears, both Run key values are
      gone, and the desktop shortcuts are removed.

## G. A package that fails to install

Simulating this is easy: dismiss the approval prompt when Windows raises one
during setup, or run the installer with a bad winget source.

- [ ] G1. Dismiss the elevation prompt for one machine-wide package during
      setup. The live log shows a red line naming the package, winget's own
      words underneath, and the retry command, at the moment it happens and
      not after the summary.
- [ ] G2. The closing summary lists the failed package, what it was for, what
      it costs, and `winget install -e --id <id>`.
- [ ] G3. The top-ten keybinding list marks any key whose app did not install
      as NOT WORKING.
- [ ] G4. `winmarchy doctor` FAILs a row for the missing app, names the keys
      that die and gives the winget command.
- [ ] G5. Install the missing app by hand, re-run install.ps1, and confirm
      doctor goes green and the key works.
- [ ] G6. `winmarchy doctor` on a healthy machine passes the nerd font row.
      If it FAILs while the bar glyphs render correctly, the family-name match
      is wrong and FLAG-25 needs reopening.
- [ ] G7. With Alacritty installed under Program Files rather than on PATH,
      all four of lwin+enter, lwin+k, lwin+escape and lwin+ctrl+shift+space
      work. Confirm the GlazeWM config at ~/.glzr/glazewm/config.yaml carries
      the full unquoted path on all four lines.
