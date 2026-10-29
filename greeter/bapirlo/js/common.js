// Kuro OS greeter — shared by the primary (index.html) and secondary-monitor (secondary.html) pages:
// clock, embers, pointer parallax and the "leaving" transition.
"use strict";

const $ = (s) => document.querySelector(s);

function pad(n) { return String(n).padStart(2, "0"); }

function tickClock() {
  const now = new Date();
  $("#clock").innerHTML = `${pad(now.getHours())}<span class="colon">:</span>${pad(now.getMinutes())}`;
  const date = $("#date");
  if (date) {
    date.textContent = now.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
  }
  // re-arm exactly on the next minute so the clock never drifts
  setTimeout(tickClock, 60000 - (now.getSeconds() * 1000 + now.getMilliseconds()) + 20);
}

function spawnEmbers(count) {
  const box = $("#embers");
  for (let i = 0; i < count; i++) {
    const e = document.createElement("i");
    e.className = "ember";
    const size = 4 + Math.random() * 7;
    e.style.cssText = `left:${Math.random() * 100}vw;--s:${size}px;--d:${14 + Math.random() * 16}s;` +
      `--delay:${-Math.random() * 30}s;--dx:${(Math.random() - 0.5) * 16}vw`;
    box.appendChild(e);
  }
}

// Pointer parallax: the art leans away from the cursor by at most ~1.2% of the screen.
function parallax() {
  const layer = $("#parallax");
  let raf = 0, x = 0, y = 0;
  window.addEventListener("mousemove", (ev) => {
    x = ev.clientX / window.innerWidth - 0.5;
    y = ev.clientY / window.innerHeight - 0.5;
    if (raf) return;
    raf = requestAnimationFrame(() => {
      raf = 0;
      layer.style.transform = `translate(${-x * 1.2}%, ${-y * 1.2}%)`;
    });
  });
}

// Zoom/fade into the desktop. Resolves once the curtain is black.
function leave() {
  document.body.classList.add("leaving");
  return new Promise((resolve) => setTimeout(resolve, 1150));
}

function bootCommon(embers) {
  tickClock();
  spawnEmbers(embers);
  parallax();
  // first frame matches the dark Plymouth hand-off, then the art lifts in
  // (a timer, not rAF: a hidden or headless window may never paint, and the UI must not stay invisible)
  setTimeout(() => {
    document.body.classList.remove("booting");
    document.body.classList.add("ready");
  }, 80);
  window.addEventListener("GreeterBroadcastEvent", (ev) => {
    if (ev.data && ev.data.type === "leave") leave();
  });
}
