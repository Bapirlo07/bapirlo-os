// Bapirlo OS greeter — primary screen: user, password, session picker, power, LightDM auth flow.
"use strict";

const PREFERRED_SESSION = "gnome";   // plain GNOME unless picked otherwise in the chip
const CONFIRM_MS = 3000;             // power buttons need a second click within this time

let user = null;          // LightDM user object being authenticated
let session = null;       // session key passed to start_session
let promptType = null;    // 0 = visible (username), 1 = secret, null = waiting for PAM
let pending = null;       // password typed before PAM asked for it
let starting = false;

const msg = (text, error = false) => {
  const m = $("#message");
  m.textContent = text || "";
  m.classList.toggle("error", error);
};

function pickUser() {
  const users = lightdm.users || [];
  const hint = lightdm.select_user_hint || lightdm.authentication_user;
  return users.find((u) => u.username === hint) || users[0] || null;
}

function showUser(u) {
  $("#name").textContent = u ? (u.display_name || u.username) : "Log in";
  const img = $("#avatar");
  img.onerror = () => { img.onerror = null; img.src = "img/avatar.png"; };
  if (u && u.image) img.src = u.image;
}

function startAuth() {
  promptType = null;
  if (lightdm.in_authentication) lightdm.cancel_authentication();
  lightdm.authenticate(user ? user.username : null);
}

function submit(ev) {
  ev.preventDefault();
  if (starting) return;
  const input = $("#password");
  const value = input.value;
  if (promptType === 0) {               // PAM asked for a username (no user list)
    lightdm.respond(value);
    input.value = "";
    return;
  }
  if (!value) return;
  document.body.classList.add("busy");
  msg("");
  if (promptType === 1) {
    promptType = null;
    lightdm.respond(value);
  } else {
    pending = value;                    // answered as soon as the prompt arrives
  }
}

function onPrompt(text, type) {
  promptType = type;
  const input = $("#password");
  input.type = type === 1 ? "password" : "text";
  input.placeholder = type === 1 ? "Password" : (text || "Username").replace(/:\s*$/, "");
  if (type === 1 && pending !== null) {
    const p = pending;
    pending = null;
    promptType = null;
    lightdm.respond(p);
  }
}

function onMessage(text, type) {
  msg(text, type === 1);
}

async function onComplete() {
  document.body.classList.remove("busy");
  const input = $("#password");
  if (lightdm.is_authenticated) {
    starting = true;
    input.blur();
    msg(lightdm.lock_hint ? "Welcome back" : "Welcome");
    if (window.greeter_comm) {
      try { greeter_comm.broadcast({ type: "leave" }); } catch (_) { /* single screen */ }
    }
    await leave();
    lightdm.start_session(session || PREFERRED_SESSION);
    return;
  }
  input.value = "";
  msg("Wrong password — try again", true);
  document.body.classList.remove("wrong");
  void document.body.offsetWidth;       // restart the shake if it is already applied
  document.body.classList.add("wrong");
  setTimeout(() => document.body.classList.remove("wrong"), 900);
  input.focus();
  startAuth();
}

// ---------- session chip ----------
function setupSessions() {
  const chip = $("#session");
  const list = $("#session-list");
  const sessions = lightdm.sessions || [];
  const keys = sessions.map((s) => s.key);
  session = keys.includes(PREFERRED_SESSION) ? PREFERRED_SESSION : (lightdm.default_session || keys[0]);
  const render = () => {
    const cur = sessions.find((s) => s.key === session);
    $("#session-name").textContent = cur ? cur.name : session;
    list.querySelectorAll("li").forEach((li) => li.classList.toggle("sel", li.dataset.key === session));
  };
  for (const s of sessions) {
    const li = document.createElement("li");
    li.textContent = s.name;
    li.dataset.key = s.key;
    li.addEventListener("click", (ev) => {
      ev.stopPropagation();
      session = s.key;
      render();
      chip.classList.remove("open");
      $("#password").focus();
    });
    list.appendChild(li);
  }
  chip.addEventListener("click", () => chip.classList.toggle("open"));
  document.addEventListener("click", (ev) => { if (!chip.contains(ev.target)) chip.classList.remove("open"); });
  if (sessions.length < 2) chip.style.visibility = "hidden";
  render();
}

// ---------- power ----------
function setupPower() {
  const can = { suspend: lightdm.can_suspend, restart: lightdm.can_restart, shutdown: lightdm.can_shutdown };
  document.querySelectorAll(".pw").forEach((btn) => {
    const act = btn.dataset.act;
    const label = btn.querySelector("span");
    const plain = label.textContent;
    let timer = 0;
    if (!can[act]) btn.hidden = true;
    btn.addEventListener("click", () => {
      if (!btn.classList.contains("confirm")) {
        document.querySelectorAll(".pw.confirm").forEach((b) => b.dispatchEvent(new Event("disarm")));
        btn.classList.add("confirm");
        label.textContent = `${plain}?`;
        timer = setTimeout(() => btn.dispatchEvent(new Event("disarm")), CONFIRM_MS);
        return;
      }
      btn.dispatchEvent(new Event("disarm"));
      if (act === "suspend") {
        lightdm.suspend();
      } else {
        leave().then(() => lightdm[act]());
      }
    });
    btn.addEventListener("disarm", () => {
      clearTimeout(timer);
      btn.classList.remove("confirm");
      label.textContent = plain;
    });
  });
}

// ---------- keyboard ----------
function setupKeys() {
  const input = $("#password");
  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") {
      input.value = "";
      $("#session").classList.remove("open");
      document.querySelectorAll(".pw.confirm").forEach((b) => b.dispatchEvent(new Event("disarm")));
    }
    if (ev.getModifierState && !$("#message").classList.contains("error")) {
      msg(ev.getModifierState("CapsLock") ? "Caps Lock is on" : "");
    }
    // typing anywhere goes to the password box
    if (document.activeElement !== input && ev.key.length === 1 && !ev.ctrlKey && !ev.altKey) input.focus();
  });
  input.addEventListener("input", () => { if ($("#message").classList.contains("error")) msg(""); });
  window.addEventListener("focus", () => input.focus());
}

function init() {
  if (lightdm.lock_hint) document.body.classList.add("locked");
  lightdm.show_prompt.connect(onPrompt);
  lightdm.show_message.connect(onMessage);
  lightdm.authentication_complete.connect(onComplete);
  user = pickUser();
  showUser(user);
  setupSessions();
  setupPower();
  setupKeys();
  $("#login").addEventListener("submit", submit);
  bootCommon(16);
  startAuth();
  setTimeout(() => $("#password").focus(), 50);
}

window.addEventListener("GreeterReady", init);
