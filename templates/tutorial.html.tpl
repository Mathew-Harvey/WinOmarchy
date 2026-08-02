<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Winmarchy: learning Omarchy mode</title>
<style>
/* Rendered by bin/tutorial.ps1 in the active palette ({{label}}). */
:root {
  --accent: {{accent}};
  --bg: {{background}};
  --bg-dark: {{dark_background}};
  --bg-darker: {{darker_background}};
  --bg-light: {{lighter_background}};
  --fg: {{foreground}};
  --fg-bright: {{bright_foreground}};
  --fg-dim: {{dark_foreground}};
  --muted: {{muted}};
  --selection: {{selection}};
  --green: {{green}};
  --red: {{red}};
  --yellow: {{yellow}};
}
* { margin: 0; padding: 0; box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  background: var(--bg-darker);
  color: var(--fg);
  font-family: 'Segoe UI Variable Display', 'Segoe UI', system-ui, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  padding: 0 0 90px 0;
}
.wrap { max-width: 1080px; margin: 0 auto; padding: 0 28px; }

header {
  background: linear-gradient(160deg, var(--bg-dark) 0%, var(--bg) 70%, var(--bg-light) 100%);
  border-bottom: 1px solid var(--selection);
  padding: 64px 0 52px 0;
  margin-bottom: 44px;
}
header h1 {
  font-size: 40px;
  font-weight: 600;
  color: var(--fg-bright);
  letter-spacing: -0.4px;
  margin-bottom: 12px;
}
header p { font-size: 18px; color: var(--fg); max-width: 68ch; }
header .theme-note { margin-top: 18px; font-size: 14px; color: var(--fg-dim); }

.panic {
  margin-top: 26px;
  background: var(--bg-darker);
  border: 1px solid var(--green);
  border-radius: 10px;
  padding: 18px 22px;
  max-width: 68ch;
}
.panic strong { color: var(--green); display: block; margin-bottom: 6px; font-size: 15px; }
.panic span { font-size: 14.5px; color: var(--fg); }

h2 {
  font-size: 13px;
  text-transform: uppercase;
  letter-spacing: 1.6px;
  color: var(--accent);
  font-weight: 600;
  margin: 46px 0 18px 0;
  padding-bottom: 9px;
  border-bottom: 1px solid var(--selection);
}
h2:first-of-type { margin-top: 0; }

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(324px, 1fr));
  gap: 16px;
}
.card {
  background: var(--bg);
  border: 1px solid var(--selection);
  border-radius: 11px;
  padding: 20px 22px 22px 22px;
  transition: border-color 140ms ease, transform 140ms ease;
}
.card:hover { border-color: var(--accent); transform: translateY(-2px); }
.card h3 { font-size: 16.5px; color: var(--fg-bright); font-weight: 600; margin: 14px 0 8px 0; }
.card p { font-size: 14.5px; color: var(--fg); }
.card p.was {
  margin-top: 11px;
  padding-top: 11px;
  border-top: 1px dashed var(--selection);
  font-size: 13.5px;
  color: var(--fg-dim);
}

.keys { display: flex; align-items: center; flex-wrap: wrap; gap: 2px; }
.keys.none { font-size: 13px; color: var(--fg-dim); font-style: italic; }
kbd {
  display: inline-block;
  background: var(--bg-light);
  color: var(--fg-bright);
  border: 1px solid var(--muted);
  border-bottom-width: 3px;
  border-radius: 6px;
  padding: 5px 11px;
  font-family: 'Cascadia Mono', 'Consolas', ui-monospace, monospace;
  font-size: 13px;
  font-weight: 600;
  white-space: nowrap;
}
.keys .plus { color: var(--fg-dim); padding: 0 4px; font-size: 12px; }

.tips { margin-top: 46px; }
.tip {
  background: var(--bg);
  border-left: 3px solid var(--accent);
  border-radius: 0 8px 8px 0;
  padding: 16px 20px;
  margin-bottom: 12px;
}
.tip b { color: var(--fg-bright); }
.tip span { color: var(--fg); font-size: 14.5px; }

footer {
  margin-top: 54px;
  padding-top: 26px;
  border-top: 1px solid var(--selection);
  color: var(--fg-dim);
  font-size: 14px;
}
footer code {
  font-family: 'Cascadia Mono', 'Consolas', ui-monospace, monospace;
  background: var(--bg);
  border: 1px solid var(--selection);
  border-radius: 4px;
  padding: 2px 7px;
  color: var(--fg);
}
</style>
</head>
<body>

<header>
  <div class="wrap">
    <h1>You are in Omarchy mode</h1>
    <p>Windows still works the way it always did underneath. What changes is that
       your windows arrange themselves, and the keyboard does the driving. This
       page teaches the whole thing in about five minutes. Leave it open on one
       workspace and try each key as you read it.</p>
    <div class="panic">
      <strong>If you ever want out, press Super and Shift and X</strong>
      <span>That returns you to a completely normal Windows desktop, with your
            taskbar, icons, wallpaper, terminal and editor exactly as they were.
            Nothing here is one-way, so try things freely.</span>
    </div>
    <p class="theme-note">Theme: {{label}}. Everything you see here, and every
       window border and bar on screen, is drawn from this one palette.</p>
  </div>
</header>

<div class="wrap">

{{lessons}}

<div class="tips">
  <h2>Three habits that make it click</h2>
  <div class="tip"><b>Stop closing windows to tidy up.</b>
    <span>Send them to another workspace instead. Super and a number gets you
          back to them instantly, and nothing has to be reopened.</span></div>
  <div class="tip"><b>Stop reaching for the mouse to move a window.</b>
    <span>Super and Shift and an arrow does it faster, and the layout stays tidy
          because nothing overlaps.</span></div>
  <div class="tip"><b>When an app fights the layout, let it float.</b>
    <span>Super and T lifts it out of the grid and it behaves like an ordinary
          Windows window again. Installers and dialogs usually want this.</span></div>
</div>

<footer>
  <p>Open this page again any time with <code>winmarchy tutorial</code>. The full
     key list is <code>winmarchy keys</code>, or Super and K. Both are generated
     from your actual configuration, so they always match the keys that work.</p>
  <p style="margin-top:10px">To go back to Windows: Super and Shift and X, the
     "Restore Windows 11 (repair)" shortcut in the Start menu, or
     <code>winmarchy mode win11</code>.</p>
</footer>

</div>
</body>
</html>
