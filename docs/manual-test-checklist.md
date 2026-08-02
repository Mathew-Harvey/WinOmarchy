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

## H. The four fixes from the first on-machine round

- [ ] H1. `winmarchy mode omarchy` completes: bar up, tiling on, taskbar
      hidden, icons hidden, wallpaper themed, and it STAYS (the taskbar call
      no longer crashes the swap). `winmarchy doctor` agrees.
- [ ] H2. Swap back and forth three times; both directions stay clean.
- [ ] H3. Restart Windows: the chooser appears and waits. Do not touch
      anything: after twenty seconds it continues to the last mode, and the
      log line says "countdown expired with no input", not "user chose".
- [ ] H4. Restart again and move the mouse: the countdown stops and the
      chooser waits for a real choice.
- [ ] H5. No terminal window anywhere for the tray: the icon is by the clock
      and Task Manager shows Winmarchy.Chooser.exe with a --tray command
      line, not a powershell.exe.
- [ ] H6. Tray actions (swap both ways, next theme, chooser, tutorial,
      repair) open no console window; Keybindings and Theme menu open a
      real, visible terminal on purpose.
- [ ] H7. Re-run setup: exactly one tray icon afterwards (the old one is
      stopped, the new one takes over).
- [ ] H8. After setup, the desktop carries no new icons from the app
      installers and none from Winmarchy. Anything setup could not remove
      from the shared desktop was named in a warning.

## I. Wallpapers, the bar menu, the Windows key and the TUIs

- [ ] I1. Setup's Components page: Browse picks a folder; the review page
      shows it in the summary and on the command line.
- [ ] I2. With a folder set: swapping modes, changing theme, lwin+ctrl+b and
      the menus each deal a different random picture, in BOTH modes; the
      tray deals one on its own within half an hour.
- [ ] I3. `winmarchy wallpaper off` stops it; themes control the wallpaper
      again on the next swap.
- [ ] I4. The bar's top-left button opens the floating menu with one click;
      every entry works, including System stats (btop) and Git TUI
      (lazygit) in the same window.
- [ ] I5. In Omarchy mode, tapping the Windows key opens nothing; every
      lwin combo still fires; Win+L still locks. Swap to Windows 11 mode:
      the key opens Start again immediately.
- [ ] I6. Hide the tray icon while in Omarchy mode: the Windows key opens
      Start again (the guard dies with the tray). Run winmarchy tray to
      bring both back.
- [ ] I7. lwin+ctrl+t opens btop floating and centred; q closes it and the
      window goes with it. If "winmarchy stats" says btop is not installed
      while winget shows aristocratos.btop4win installed, record the actual
      exe name in FLAGS.md (FLAG-33).

## J. Theme independence between the modes

- [ ] J1. In Windows mode, set Windows Terminal to a scheme and font of your
      own. Swap to Omarchy and back: both are exactly as you set them.
- [ ] J2. Change the Windows Terminal scheme again, swap to Omarchy and
      back: the NEW scheme survives (the baseline recaptures every entry).
- [ ] J3. From the pre-update pollution: if the terminal shows an Omarchy
      scheme while in Windows mode, one full swap cycle strips it rather
      than re-capturing it. Confirm the scheme dropdown no longer selects a
      Winmarchy scheme in Windows mode.
- [ ] J4. Same round trip for Cursor colours and the Windows light/dark
      setting. Omarchy keeps its theme; Windows keeps yours; neither leaks.
- [ ] I8. Put pictures in nested subfolders of the wallpaper folder: they
      all join the rotation.
- [ ] I9. Set the slider (or winmarchy wallpaper every 5): the wallpaper
      changes on that pace in BOTH modes, and a new interval takes effect
      within a minute. winmarchy wallpaper status reports folder and pace.
