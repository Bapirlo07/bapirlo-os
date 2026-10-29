# Kuro OS — emergency sheet

**Laptop:** MSI Pulse 16 · CachyOS + GNOME 51 · Linux = `nvme0n1p6` (ext4, 150 GB) · Windows = `nvme0n1p3` · EFI = `nvme0n1p1`
**Never** format, resize or "repair" `p1` (EFI) or `p3`/`p4`/`p5` (Windows).

## 1 · Desktop frozen
1. [[Esc]], then [[Super]], then [[Super+Escape]] — closes stuck menus / gives keys back.
2. [[Ctrl+Alt+F3]] → log in → `bapirlo-doctor`
3. All extensions off, live:
   `export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus`
   `gsettings set org.gnome.shell disable-user-extensions true` → [[Ctrl+Alt+F8]] back to the desktop
4. Restart the desktop (unsaved work lost): `sudo systemctl restart lightdm`
5. Last resort: hold power 10 s.

## 2 · Extension gone after an update
Extension Manager → Updates. Kuro's own ones: code in `~/bapirlo-os` (add the new GNOME number to `metadata.json`, log out/in).
Shell crashes at login → TTY step 3 above.

## 3 · Login screen broken
[[Ctrl+Alt+F3]] → `sudo bapirlo-greeter-revert` → `sudo systemctl restart lightdm` (plain login screen).

## 4 · No Wi-Fi
`nmcli radio wifi on` · `rfkill unblock all` · `sudo systemctl restart NetworkManager` · after a kernel update: **reboot**.
No luck → phone hotspot / USB-C Ethernet.

## 5 · Won't boot
- At the MSI logo: [[F11]] = boot picker → **Limine** → CachyOS. Tap [[Esc]] while GRUB starts for its menu → fallback kernel **linux-cachyos**.
- Splash stuck: [[Esc]] shows messages; wait 1 min; then [[Ctrl+Alt+F3]].
- Broke after an update (desktop or TTY works): `sudo timeshift --list` → `sudo timeshift --restore --snapshot '<name>' --skip-grub`

## 6 · Restore from the CachyOS USB (nothing boots)
1. USB in → [[F11]] at the MSI logo → USB (UEFI) → live desktop → Wi-Fi → terminal.
2. `sudo pacman -Sy --needed timeshift`
3. `sudo timeshift --list --snapshot-device /dev/nvme0n1p6`
4. `sudo timeshift --restore --snapshot-device /dev/nvme0n1p6 --target /dev/nvme0n1p6 --snapshot '<name>' --skip-grub`
   (`<name>` like `2026-10-12_18-00-00`; pick **Kuro OS final** or the newest **Before update**.)
5. **Don't reinstall the bootloader.** Never choose `p1` or `p3`. Remove USB → reboot.

## 7 · Windows
- Switch: Start menu → **Restart to Windows** (one boot only) · or [[F11]] → Windows Boot Manager.
- Windows drive is read-only from Linux. Write only via `bapirlo-windows rw` (refuses if unsafe), then `bapirlo-windows ro`.
- **Never write to Windows with Fast Startup / hibernation on.** Never enable BitLocker without saving the recovery key to your Microsoft account.
- Clock 1 h off → in Windows run `C:\Shared\Fix clock for Linux (double-click).reg` once.

## 8 · Undo
One change: `bash ~/bapirlo-os/<script>.sh restore` · everything: Timeshift → **Kuro OS final** → Restore.
Full manual: Start menu → **Kuro OS Guide** · `~/bapirlo-os/MANUAL.md`
