# Bapirlo OS — helpers for installing GNOME Shell extensions from extensions.gnome.org.
# Sourced by the 1xx-*.sh scripts. Every install is pinned to the running shell's major version
# and refuses an extension whose metadata does not list it.
SHELL_MAJOR=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
EXT_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions
EXT_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/bapirlo-ext
mkdir -p "$EXT_CACHE" "$EXT_DIR"

# ext_install UUID — download the newest build for this shell, verify, install (no enabling)
ext_install() {
  local uuid=$1 info url zip
  info=$(curl -fsS "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$SHELL_MAJOR")
  url=$(python3 -c 'import sys,json;print(json.loads(sys.stdin.read(),strict=False)["download_url"])' <<<"$info")
  zip=$EXT_CACHE/$uuid.zip
  curl -fsSL -o "$zip" "https://extensions.gnome.org$url"
  python3 - "$zip" "$SHELL_MAJOR" "$uuid" <<'PY'
import json, sys, zipfile
z, shell, uuid = sys.argv[1:]
m = json.loads(zipfile.ZipFile(z).read("metadata.json"))
assert m["uuid"] == uuid, f"uuid mismatch {m['uuid']}"
if shell not in [str(v).split(".")[0] for v in m["shell-version"]]:
    sys.exit(f"{uuid} v{m.get('version')} does not support GNOME {shell} ({m['shell-version']}) — not installing")
print(f"  {uuid} v{m.get('version')} (shell {', '.join(m['shell-version'])})")
PY
  gnome-extensions install --force "$zip"
}

# ext_enable UUID... — add to enabled-extensions (works before the shell has loaded them)
ext_enable() {
  python3 - "$@" <<'PY'
import ast, subprocess, sys
def get(k):
    v = subprocess.run(["gsettings", "get", "org.gnome.shell", k], capture_output=True, text=True).stdout.strip()
    return [] if v.startswith("@as") else ast.literal_eval(v)
en, dis = get("enabled-extensions"), get("disabled-extensions")
for u in sys.argv[1:]:
    if u not in en: en.append(u)
dis = [d for d in dis if d not in sys.argv[1:]]
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(en)], check=True)
subprocess.run(["gsettings", "set", "org.gnome.shell", "disabled-extensions", str(dis)], check=True)
PY
}

# eset UUID SCHEMA KEY VALUE — gsettings set using the extension's own schema dir
eset() {
  gsettings --schemadir "$EXT_DIR/$1/schemas" set "$2" "$3" "$4"
}

# backup_dconf DIR PATH... — dconf dump of each path into DIR
backup_dconf() {
  local d=$1; shift
  for p in "$@"; do dconf dump "$p" > "$d/$(echo "$p" | tr / _).ini"; done
}

# restore_dconf DIR PATH... — reset each path and load it back from DIR
restore_dconf() {
  local d=$1; shift
  for p in "$@"; do dconf reset -f "$p"; dconf load "$p" < "$d/$(echo "$p" | tr / _).ini"; done
}

# ext_unenable UUID... — remove from enabled-extensions only these (leaves everything else alone)
ext_unenable() {
  python3 - "$@" <<'PY'
import ast, subprocess, sys
v = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], capture_output=True, text=True).stdout.strip()
en = [] if v.startswith("@as") else ast.literal_eval(v)
en = [u for u in en if u not in sys.argv[1:]]
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(en)], check=True)
PY
  for u in "$@"; do gnome-extensions disable "$u" 2>/dev/null || true; done
}

# backup_keys DIR "schema key" ... — remember single keys (TSV: schema, key, value)
backup_keys() {
  local d=$1; shift
  : > "$d/keys.tsv"
  for sk in "$@"; do
    set -- $sk
    printf '%s\t%s\t%s\n' "$1" "$2" "$(gsettings get "$1" "$2")" >> "$d/keys.tsv"
  done
}

# restore_keys DIR — put those keys back
restore_keys() {
  [ -f "$1/keys.tsv" ] || return 0
  while IFS=$'\t' read -r schema key value; do
    gsettings set "$schema" "$key" "$value"
  done < "$1/keys.tsv"
}
