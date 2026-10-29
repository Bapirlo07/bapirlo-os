#!/usr/bin/env bash
# Kuro OS — Timeshift safety net (ext4 → rsync mode). NEEDS sudo.
#   sudo bash ~/bapirlo-os/05-timeshift.sh            # backup + install + "Before extras" snapshot + weekly x3
#   sudo bash ~/bapirlo-os/05-timeshift.sh restore    # schedule off, cronie off, config back (snapshots are KEPT)
#
# Snapshots live in /timeshift on the root partition (nvme0n1p6). Partitions are not touched.
# Included: the whole system + hidden files/folders in your home (= all theme/app configs),
# minus caches, Trash and Steam games. Your normal files (Documents, Pictures, ...) are NOT in it.
# Delete all snapshots:  sudo timeshift --delete-all      GUI: timeshift-launcher
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U=${SUDO_USER:?run via sudo from your user}
H=$(getent passwd "$U" | cut -d: -f6)
ROOT_UUID=$(findmnt -no UUID /)                    # the partition / lives on
CONF=/etc/timeshift/timeshift.json
DROPIN=/etc/systemd/system/cronie.service.d/bapirlo-lowprio.conf
CRON=/etc/cron.d/timeshift-hourly
LATEST=$H/theme-backups/LATEST-TIMESHIFT

apply() {
  [ "$(findmnt -no UUID /)" = "$ROOT_UUID" ] || { echo "root UUID changed — stopping"; exit 1; }
  local BK=$H/theme-backups/$(date +%Y%m%d-%H%M%S)-timeshift
  mkdir -p "$BK"
  [ -d /etc/timeshift ] && cp -a /etc/timeshift "$BK/etc-timeshift"
  [ -e "$CRON" ] && cp -a "$CRON" "$BK/"
  pacman -Q timeshift cronie > "$BK/pkgs-before.txt" 2>&1 || true
  systemctl is-enabled cronie > "$BK/cronie-enabled.txt" 2>&1 || true
  chown -R "$U:" "$BK"; echo "$BK" > "$LATEST"; chown "$U:" "$LATEST"
  echo "backup -> $BK"

  pacman -S --needed timeshift          # official repo (pulls cronie, rsync, ...) — confirm the list

  mkdir -p /etc/timeshift
  cat > "$CONF" <<EOF
{
  "backup_device_uuid" : "$ROOT_UUID",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "false",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "true",
  "schedule_daily" : "false",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [
    "$H/.cache/**",
    "$H/.local/share/Trash/**",
    "$H/.local/share/Steam/**",
    "$H/.var/app/*/cache/**",
    "$H/.ollama/models/**",
    "$H/.npm/_cacache/**",
    "+ $H/.**",
    "$H/**",
    "/root/**"
  ],
  "exclude-apps" : []
}
EOF

  # weekly runs happen in the background via cron → keep them out of the way of games/streams
  mkdir -p "$(dirname "$DROPIN")"
  printf '[Service]\nNice=19\nCPUSchedulingPolicy=idle\nIOSchedulingClass=idle\n' > "$DROPIN"
  systemctl daemon-reload
  systemctl enable --now cronie

  echo; echo ">>> creating snapshot \"Before extras\" (first one copies ~36 GB — several minutes)"
  nice -n 10 timeshift --create --comments "Before extras" --tags O   # not --scripted: that hides the progress

  # timeshift normally writes its hourly checker itself; make sure it exists
  if [ ! -e "$CRON" ]; then
    printf 'SHELL=/bin/bash\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nMAILTO=""\n\n0 * * * * root timeshift --check --scripted\n' > "$CRON"
  fi
  echo; timeshift --list
  echo; echo "OK. Weekly snapshots, last 3 kept (hourly check: $CRON). Undo schedule: sudo bash $0 restore"
}

restore() {
  local BK; BK=$(cat "$LATEST")
  echo "restoring from $BK (snapshots in /timeshift are kept)"
  rm -f "$CRON" "$DROPIN"
  rmdir "$(dirname "$DROPIN")" 2>/dev/null || true
  rm -f "$CONF"
  [ -d "$BK/etc-timeshift" ] && cp -a "$BK/etc-timeshift/." /etc/timeshift/
  [ -e "$BK/timeshift-hourly" ] && cp -a "$BK/timeshift-hourly" "$CRON"
  systemctl daemon-reload
  grep -q '^enabled' "$BK/cronie-enabled.txt" || systemctl disable --now cronie 2>/dev/null || true
  echo "done. Remove the packages too:  sudo pacman -Rns timeshift   (snapshots: sudo timeshift --delete-all first)"
}

case "${1:-}" in "") apply ;; restore) restore ;; *) sed -n 2,4p "$0"; exit 1 ;; esac
