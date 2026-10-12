// Browser-preview stand-in for web-greeter's LightDM bridge. Never loaded inside web-greeter
// (index.html only adds it when window.qt is missing). Password "kuro" succeeds.
// Query flags: ?lock  ?nousers  ?secondary  ?name=Shown+Name  ?user=login
"use strict";
(() => {
  const q = new URLSearchParams(location.search);
  const sig = () => { const cbs = []; return { connect: (f) => cbs.push(f), emit: (...a) => cbs.forEach((f) => f(...a)) }; };
  const users = q.has("nousers") ? [] : [{
    username: q.get("user") || "kuro", display_name: q.get("name") || "Kuro", image: q.get("avatar") || "img/avatar.png", session: "gnome-classic",
  }];
  const lm = {
    users, lock_hint: q.has("lock"), select_user_hint: "", authentication_user: "",
    sessions: [{ key: "gnome", name: "GNOME" }, { key: "gnome-classic", name: "GNOME Classic" }],
    default_session: "gnome", can_suspend: true, can_restart: true, can_shutdown: true,
    in_authentication: false, is_authenticated: false,
    show_prompt: sig(), show_message: sig(), authentication_complete: sig(),
    authenticate(name) { this.in_authentication = true; this._user = name;
      setTimeout(() => this.show_prompt.emit(name ? "Password: " : "login:", name ? 1 : 0), 80); },
    cancel_authentication() { this.in_authentication = false; },
    respond(r) {
      if (!this._user) { this._user = r; setTimeout(() => this.show_prompt.emit("Password: ", 1), 80); return; }
      setTimeout(() => { this.is_authenticated = r === "kuro"; this.in_authentication = false;
        this.authentication_complete.emit(); }, 450);
    },
    start_session(s) { console.log("MOCK start_session", s); document.title = "SESSION " + s; return true; },
    suspend() { console.log("MOCK suspend"); }, restart() { console.log("MOCK restart"); },
    shutdown() { console.log("MOCK shutdown"); },
  };
  window.lightdm = lm;
  window.dispatchEvent(new Event("GreeterReady"));
})();
