(() => {
  // --- Interactive Popover Preview ---
  const wakeBtn = document.getElementById("wake-btn");
  const popover = document.querySelector(".popover");
  const statusDot = document.getElementById("status-dot");
  const statusLabel = document.getElementById("status-label");
  const menubarIcon = document.getElementById("menubar-icon");
  const segBtns = document.querySelectorAll(".seg-btn");
  const ledDots = document.querySelectorAll(".led-dot");
  const stickL = document.getElementById("stick-l");
  const stickR = document.getElementById("stick-r");
  const readout = document.getElementById("tester-readout");

  let activeLed = 1;
  let wakeTimer = null;

  function setLed(n) {
    activeLed = n;
    segBtns.forEach((b) => b.classList.toggle("active", Number(b.dataset.led) === n));
    ledDots.forEach((d) => d.classList.toggle("lit", Number(d.dataset.dot) === n));
  }

  segBtns.forEach((btn) => {
    btn.addEventListener("click", () => setLed(Number(btn.dataset.led)));
  });

  if (wakeBtn) {
    wakeBtn.addEventListener("click", () => {
      if (wakeTimer) clearTimeout(wakeTimer);
      popover.classList.add("waking");
      menubarIcon.classList.add("flash");
      statusDot.className = "status-dot waking";
      statusLabel.textContent = "Sending USB handshake…";

      // Little playful stick wiggle during wake preview
      stickL.style.transform = "translate(-20%, -75%)";
      stickR.style.transform = "translate(-80%, -25%)";
      readout.textContent = "USB_INIT ACK (03 01 00 0d …) · Player " + activeLed + " LED set";
      readout.classList.add("active");

      wakeTimer = setTimeout(() => {
        popover.classList.remove("waking");
        menubarIcon.classList.remove("flash");
        statusDot.className = "status-dot awake";
        statusLabel.textContent = "Awake & Streaming";
        stickL.style.transform = "translate(-50%, -50%)";
        stickR.style.transform = "translate(-50%, -50%)";
      }, 650);
    });
  }

  // --- Optional Live Web Gamepad API Hook ---
  // If the visitor actually has their woken gamepad connected, animate the preview live!
  let polling = false;
  function pollGamepad() {
    const pads = navigator.getGamepads ? Array.from(navigator.getGamepads()).filter(Boolean) : [];
    if (pads.length === 0) {
      polling = false;
      return;
    }
    const gp = pads[0];
    const lx = gp.axes[0] || 0;
    const ly = gp.axes[1] || 0;
    const rx = gp.axes[2] || 0;
    const ry = gp.axes[3] || 0;

    stickL.style.transform = `translate(calc(-50% + ${(lx * 15).toFixed(1)}px), calc(-50% + ${(ly * 15).toFixed(1)}px))`;
    stickR.style.transform = `translate(calc(-50% + ${(rx * 15).toFixed(1)}px), calc(-50% + ${(ry * 15).toFixed(1)}px))`;

    const pressed = [];
    gp.buttons.forEach((b, i) => {
      if (b.pressed) pressed.push("b" + i);
    });
    if (pressed.length > 0) {
      readout.textContent = "Live HID: " + pressed.join(" · ");
      readout.classList.add("active");
    } else if (Math.hypot(lx, ly) > 0.15 || Math.hypot(rx, ry) > 0.15) {
      readout.textContent = `Live HID: L(${lx.toFixed(2)}, ${ly.toFixed(2)}) R(${rx.toFixed(2)}, ${ry.toFixed(2)})`;
      readout.classList.add("active");
    } else {
      readout.textContent = "Gamepad connected — press any button or move sticks";
      readout.classList.remove("active");
    }
    requestAnimationFrame(pollGamepad);
  }

  window.addEventListener("gamepadconnected", () => {
    statusDot.className = "status-dot awake";
    statusLabel.textContent = "Awake & Streaming (Live)";
    if (!polling) {
      polling = true;
      requestAnimationFrame(pollGamepad);
    }
  });

  // --- Install Method Tabs & Copy Button ---
  const SNIPPETS = {
    app: {
      code: `git clone https://github.com/mindthelatency/padwake.git\ncd padwake\nmake install-app`,
      note: `Builds a Universal Binary, installs <code>/Applications/PadWake.app</code>, and opens it in your menu bar. Enable <strong>Launch at Login</strong> inside the popover and restart your game launcher once.`
    },
    cli: {
      code: `make\n./bin/padwake enable\nmake install-daemon`,
      note: `Compiles the standalone IOKit CLI and installs a background <code>LaunchAgent</code> that wakes on USB hotplug and persists <code>SDL_JOYSTICK_MFI=0</code>.`
    },
    release: {
      code: `DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \\\nNOTARY_PROFILE="padwake-notary" \\\nmake release`,
      note: `Builds a Universal Binary (<code>arm64</code> + <code>x86_64</code>), signs with Hardened Runtime, packages a DMG, notarizes via <code>notarytool</code>, and staples the ticket.`
    }
  };

  const tabBtns = document.querySelectorAll(".tab-btn");
  const codeEl = document.getElementById("install-code");
  const noteEl = document.getElementById("install-note");
  const copyBtn = document.getElementById("copy-btn");

  tabBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      const key = btn.dataset.tab;
      const spec = SNIPPETS[key];
      if (!spec) return;
      tabBtns.forEach((b) => {
        const active = b === btn;
        b.classList.toggle("active", active);
        b.setAttribute("aria-selected", String(active));
      });
      codeEl.textContent = spec.code;
      noteEl.innerHTML = spec.note;
      copyBtn.textContent = "Copy";
    });
  });

  if (copyBtn) {
    copyBtn.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(codeEl.textContent);
        copyBtn.textContent = "Copied!";
        setTimeout(() => (copyBtn.textContent = "Copy"), 1500);
      } catch {
        copyBtn.textContent = "Select & ⌘C";
      }
    });
  }
})();
