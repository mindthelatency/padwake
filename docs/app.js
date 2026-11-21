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
  const visualBtns = document.querySelectorAll("[data-btn]");

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

      // Playful stick & GL/A preview pulse during wake demo
      stickL.style.transform = "translate(-20%, -75%)";
      stickR.style.transform = "translate(-80%, -25%)";
      visualBtns.forEach((el) => {
        const idx = Number(el.dataset.btn);
        el.classList.toggle("pressed", idx === 1 || idx === 19);
      });
      readout.textContent = "USB_INIT ACK · Player " + activeLed + " LED · GL + A ready";
      readout.classList.add("active");

      wakeTimer = setTimeout(() => {
        popover.classList.remove("waking");
        menubarIcon.classList.remove("flash");
        statusDot.className = "status-dot awake";
        statusLabel.textContent = "Awake & Streaming";
        stickL.style.transform = "translate(-50%, -50%)";
        stickR.style.transform = "translate(-50%, -50%)";
        visualBtns.forEach((el) => el.classList.remove("pressed"));
      }, 650);
    });
  }

  // --- Optional Live Web Gamepad API Hook ---
  // If the visitor actually has their woken Switch 2 controller connected, animate the preview live!
  const BTN_NAMES = [
    "B", "A", "Y", "X", "R", "ZR", "+", "R3",
    "Down", "Right", "Left", "Up", "L", "ZL", "-", "L3",
    "Home", "Capture", "GR", "GL", "C"
  ];

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

    stickL.style.transform = `translate(calc(-50% + ${(lx * 13).toFixed(1)}px), calc(-50% + ${(ly * 13).toFixed(1)}px))`;
    stickR.style.transform = `translate(calc(-50% + ${(rx * 13).toFixed(1)}px), calc(-50% + ${(ry * 13).toFixed(1)}px))`;

    const pressed = [];
    const pressedSet = new Set();
    gp.buttons.forEach((b, i) => {
      if (b.pressed) {
        pressed.push(BTN_NAMES[i] || ("b" + i));
        pressedSet.add(i);
      }
    });
    visualBtns.forEach((el) => {
      el.classList.toggle("pressed", pressedSet.has(Number(el.dataset.btn)));
    });

    if (pressed.length > 0) {
      readout.textContent = "Live HID: " + pressed.join(" · ");
      readout.classList.add("active");
    } else if (Math.hypot(lx, ly) > 0.15 || Math.hypot(rx, ry) > 0.15) {
      readout.textContent = `Live HID: L(${lx.toFixed(2)}, ${ly.toFixed(2)}) R(${rx.toFixed(2)}, ${ry.toFixed(2)})`;
      readout.classList.add("active");
    } else {
      readout.textContent = "Switch 2 controller connected — press any button or paddle";
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
    app: `git clone https://github.com/mindthelatency/padwake.git\ncd padwake\nmake install-app`,
    wow: `/padwake apply\n# Later after leveling up or learning spells:\n/padwake bars`,
    cli: `make\n./bin/padwake enable\nmake install-wow`
  };

  const tabBtns = document.querySelectorAll(".tab-btn");
  const codeEl = document.getElementById("install-code");
  const noteEls = document.querySelectorAll(".install-note[data-note]");
  const copyBtn = document.getElementById("copy-btn");

  tabBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      const key = btn.dataset.tab;
      const code = SNIPPETS[key];
      if (!code) return;
      tabBtns.forEach((b) => {
        const active = b === btn;
        b.classList.toggle("active", active);
        b.setAttribute("aria-selected", String(active));
      });
      codeEl.textContent = code;
      noteEls.forEach((el) => {
        el.hidden = el.dataset.note !== key;
      });
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
