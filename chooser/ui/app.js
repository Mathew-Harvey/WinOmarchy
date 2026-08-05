// Winmarchy chooser page logic. Plain JS, no build step. Talks to the WPF
// host through window.chrome.webview.postMessage; when opened in a normal
// browser for development it runs with mock data.

(function () {
  'use strict';

  var lastMode = 'win11';
  var selectedMode = null;
  var countdownRemaining = 5;
  var countdownTotal = 5;
  var countdownTimer = null;
  var countdownCancelled = false;
  var choiceSent = false;

  var halves = {
    win11: document.getElementById('half-win11'),
    omarchy: document.getElementById('half-omarchy'),
  };
  var ring = document.getElementById('ring');
  var countNum = document.getElementById('count-num');
  var countdownEl = document.getElementById('countdown');
  var countdownText = document.getElementById('countdown-text');
  var dontAsk = document.getElementById('dont-ask');

  var host = window.chrome && window.chrome.webview ? window.chrome.webview : null;

  function modeLabel(mode) {
    if (mode === 'omarchy') { return 'Omarchy'; }
    return 'Windows 11';
  }

  function applyPalette(palette) {
    if (!palette) { return; }
    var map = {
      accent: '--accent',
      selection: '--selection',
      muted: '--muted',
      background: '--background',
      dark_background: '--dark-background',
      darker_background: '--darker-background',
      lighter_background: '--lighter-background',
      foreground: '--foreground',
      bright_foreground: '--bright-foreground',
    };
    var root = document.documentElement;
    Object.keys(map).forEach(function (key) {
      if (palette[key]) { root.style.setProperty(map[key], palette[key]); }
    });
  }

  function setSelected(mode) {
    selectedMode = mode;
    Object.keys(halves).forEach(function (key) {
      halves[key].classList.toggle('selected', key === mode);
    });
  }

  function choose(mode, auto) {
    if (choiceSent) { return; }
    choiceSent = true;
    cancelCountdown();
    document.body.classList.add('fading');
    window.setTimeout(function () {
      if (host) {
        // auto distinguishes "the countdown expired" from "the user clicked"
        // in the log, because at login the two look identical from outside
        // and diagnosing that difference once took a day.
        host.postMessage({ type: 'choose', mode: mode, auto: auto === true });
      }
    }, 380);
  }

  function tickCountdown() {
    countdownRemaining -= 1;
    if (countdownRemaining <= 0) {
      countNum.textContent = '0';
      ring.style.strokeDashoffset = '119.38';
      choose(lastMode, true);
      return;
    }
    countNum.textContent = String(countdownRemaining);
    countdownText.textContent = 'Continuing to ' + modeLabel(lastMode) + ' in ' + countdownRemaining;
    var fraction = countdownRemaining / countdownTotal;
    ring.style.strokeDashoffset = String(119.38 * (1 - fraction));
  }

  function startCountdown(seconds) {
    countdownTotal = seconds;
    countdownRemaining = seconds;
    countNum.textContent = String(seconds);
    countdownText.textContent = 'Continuing to ' + modeLabel(lastMode) + ' in ' + seconds;
    countdownTimer = window.setInterval(tickCountdown, 1000);
  }

  function cancelCountdown() {
    if (countdownTimer !== null) {
      window.clearInterval(countdownTimer);
      countdownTimer = null;
    }
    if (!countdownCancelled) {
      countdownCancelled = true;
      countdownEl.classList.add('cancelled');
      countdownText.textContent = 'Arrows select, Enter confirms, Escape keeps ' + modeLabel(lastMode);
      countdownText.classList.add('cancelled');
    }
  }

  // Any mouse or key input cancels the countdown (brief 7.1).
  ['mousemove', 'mousedown', 'wheel', 'keydown', 'touchstart'].forEach(function (eventName) {
    window.addEventListener(eventName, function () {
      if (!choiceSent) { cancelCountdown(); }
    }, { passive: true });
  });

  Object.keys(halves).forEach(function (mode) {
    halves[mode].addEventListener('click', function () { choose(mode); });
    halves[mode].addEventListener('mouseenter', function () { setSelected(mode); });
  });

  window.addEventListener('keydown', function (event) {
    if (event.key === 'ArrowLeft') {
      setSelected('win11');
    } else if (event.key === 'ArrowRight') {
      setSelected('omarchy');
    } else if (event.key === 'Enter') {
      choose(selectedMode || lastMode);
    } else if (event.key === 'Escape') {
      choose(lastMode);
    }
  });

  dontAsk.addEventListener('change', function () {
    if (host) {
      host.postMessage({ type: 'chooserDisabled', value: dontAsk.checked });
    }
  });

  function handleInit(message) {
    lastMode = message.lastMode === 'omarchy' ? 'omarchy' : 'win11';
    applyPalette(message.palette);
    setSelected(lastMode);
    if (message.screenshot) {
      var shot = document.getElementById('win11-shot');
      shot.src = message.screenshot;
      shot.hidden = false;
      document.getElementById('win11-fallback').style.display = 'none';
    }
    if (message.renderTest) {
      // Deterministic artefact: no ticking countdown in render-test shots.
      cancelCountdown();
      countdownText.textContent = 'Continuing to ' + modeLabel(lastMode) + ' in 5';
      countdownText.classList.remove('cancelled');
    } else {
      startCountdown(message.countdownSeconds || 5);
    }
  }

  if (host) {
    host.addEventListener('message', function (event) {
      var message = event.data;
      if (message && message.type === 'init') { handleInit(message); }
    });
  } else {
    // Browser development fallback.
    handleInit({ lastMode: 'win11', palette: null, screenshot: null, countdownSeconds: 5 });
  }
})();
