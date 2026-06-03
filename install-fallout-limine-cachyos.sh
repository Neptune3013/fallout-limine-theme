#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/Neptune3013/fallout-limine-theme.git"
ORIGINAL_BACKGROUND_URL="https://raw.githubusercontent.com/shvchk/fallout-grub-theme/master/background.png"
REPO_REF="${REPO_REF:-main}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BOOT_DIR="${BOOT_DIR:-}"
SECURE_BOOT_MODE="auto"
ACTION="install"
INTERACTIVE_MENU=0
BOOT_TIMEOUT=""
BACKGROUND_VARIANT=""
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPT_DIR/fallout-limine-backups}"
ORIGINAL_CONF_BACKUP="${ORIGINAL_CONF_BACKUP:-$SCRIPT_DIR/limine.conf_backup}"
ORIGINAL_SPLASH_BACKUP="${ORIGINAL_SPLASH_BACKUP:-$SCRIPT_DIR/limine-splash_backup.png}"
TMP_DIR=""

MARKER_BEGIN="# BEGIN fallout-limine-theme (managed by install-fallout-limine-cachyos.sh)"
MARKER_END="# END fallout-limine-theme"
THEME_KEY_RE='^(timeout|default_entry|remember_last_entry|wallpaper|term_font|term_font_size|term_font_scale|interface_branding|term_background|term_margin|term_background_bright|term_foreground|term_foreground_bright|term_palette|term_palette_bright|interface_help_hidden):'

usage() {
  cat <<'EOF'
Install the Fallout Limine theme on CachyOS.

Usage:
  install-fallout-limine-cachyos.sh [options]

Run without options to open the interactive menu.

Options:
  --boot-dir PATH          Directory containing limine.conf (default: auto, then /boot)
  --secure-boot auto|yes|no
                           Append BLAKE2B hashes for theme files (default: auto)
  --timeout 5|10|15        Set Limine menu timeout (default: 15 from the theme)
  --background compressed|original
                           Use compressed Limine JPG or original GRUB PNG
  --restore-original-background
                           Restore permanent backups of CachyOS' original Limine config and splash screen
  -h, --help               Show this help

When previous backups are found in the script backup directory, the script
will list them and ask before deleting anything.
The original CachyOS limine.conf and limine-splash.png are stored as
limine.conf_backup and limine-splash_backup.png next to this script; they are
never removed by that cleanup prompt.

Environment:
  REPO_REF=main            Git ref to install from
  BOOT_DIR=/boot           Same as --boot-dir
EOF
}

log() {
  printf '[fallout-limine] %s\n' "$*"
}

section() {
  printf '\n[fallout-limine] == %s ==\n' "$*"
}

die() {
  printf '[fallout-limine] ERROR: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local line="$1"
  local command="$2"
  local status="$3"

  printf '\n[fallout-limine] ERROR: command failed with exit code %s\n' "$status" >&2
  printf '[fallout-limine] ERROR: line %s: %s\n' "$line" "$command" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

run() {
  printf '[fallout-limine] $'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

parse_args() {
  if (($# == 0)); then
    INTERACTIVE_MENU=1
    ACTION=""
    return
  fi

  while (($#)); do
    case "$1" in
      --boot-dir)
        (($# >= 2)) || die "--boot-dir requires a path"
        BOOT_DIR="$2"
        shift 2
        ;;
      --secure-boot)
        (($# >= 2)) || die "--secure-boot requires auto, yes, or no"
        SECURE_BOOT_MODE="$2"
        shift 2
        ;;
      --timeout)
        (($# >= 2)) || die "--timeout requires 5, 10, or 15"
        BOOT_TIMEOUT="$2"
        shift 2
        ;;
      --background)
        (($# >= 2)) || die "--background requires compressed or original"
        BACKGROUND_VARIANT="$2"
        shift 2
        ;;
      --restore-original-background)
        ACTION="restore-original-background"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  case "$SECURE_BOOT_MODE" in
    auto|yes|no) ;;
    *) die "--secure-boot must be auto, yes, or no" ;;
  esac

  case "$BOOT_TIMEOUT" in
    ""|5|10|15) ;;
    *) die "--timeout must be 5, 10, or 15" ;;
  esac

  case "$BACKGROUND_VARIANT" in
    ""|compressed|original) ;;
    *) die "--background must be compressed or original" ;;
  esac
}

choose_from_menu() {
  local choice=""

  [[ -t 0 ]] || die "No interactive terminal available. Pass --restore-original-background or run with no options in a terminal."

  while true; do
    section "Interactive menu"
    printf '1) Apply the original full Fallout theme\n'
    printf '2) Restore the original CachyOS Limine config\n'
    printf '3) Exit\n'
    printf '[fallout-limine] Choose an option [1-3]: '
    read -r choice || die "Input cancelled."

    case "$choice" in
      1|"")
        ACTION="install"
        break
        ;;
      2)
        ACTION="restore-original-background"
        break
        ;;
      3|q|Q)
        log "No changes made."
        exit 0
        ;;
      *)
        log "Invalid menu choice: $choice"
        ;;
    esac
  done

  case "$ACTION" in
    install)
      log "Selected: apply the original full Fallout theme."
      ;;
    restore-original-background)
      log "Selected: restore the original CachyOS Limine config."
      ;;
  esac
}

choose_timeout() {
  local choice=""

  [[ "$ACTION" == "install" ]] || return 0
  [[ -z "$BOOT_TIMEOUT" ]] || return 0

  if [[ ! -t 0 ]]; then
    BOOT_TIMEOUT=15
    log "No interactive terminal available; using default Limine timeout: ${BOOT_TIMEOUT}s."
    return 0
  fi

  while true; do
    section "Limine timeout"
    printf '1) 5 seconds\n'
    printf '2) 10 seconds\n'
    printf '3) 15 seconds (theme default)\n'
    printf '[fallout-limine] Choose timeout [1-3 or 5/10/15]: '
    read -r choice || die "Input cancelled."

    case "$choice" in
      1|5)
        BOOT_TIMEOUT=5
        break
        ;;
      2|10)
        BOOT_TIMEOUT=10
        break
        ;;
      3|15|"")
        BOOT_TIMEOUT=15
        break
        ;;
      *)
        log "Invalid timeout choice: $choice. Please choose 1, 2, 3, 5, 10, or 15."
        ;;
    esac
  done

  log "Selected Limine timeout: ${BOOT_TIMEOUT}s."
}

choose_background_variant() {
  local choice=""

  [[ "$ACTION" == "install" ]] || return 0
  if [[ -n "$BACKGROUND_VARIANT" ]]; then
    log "Selected background: $BACKGROUND_VARIANT."
    return 0
  fi

  if [[ ! -t 0 ]]; then
    die "No interactive terminal available. Pass --background compressed or --background original."
  fi

  while true; do
    section "Fallout background"
    printf '1) Compressed background: Neptune Limine JPG, Fallout_limine/background.jpg -> /boot/background.jpg\n'
    printf '2) Higher-resolution background: original GRUB PNG, shvchk/fallout-grub-theme/background.png -> /boot/background.png\n'
    printf '[fallout-limine] Choose background [1-2]: '
    read -r choice || die "Input cancelled."

    case "$choice" in
      1)
        BACKGROUND_VARIANT="compressed"
        break
        ;;
      2)
        BACKGROUND_VARIANT="original"
        break
        ;;
      *)
        log "Invalid background choice: $choice. Please choose 1 or 2."
        ;;
    esac
  done

  case "$BACKGROUND_VARIANT" in
    compressed)
      log "Selected background: compressed Limine JPG."
      ;;
    original)
      log "Selected background: original GRUB PNG."
      ;;
  esac
}

require_root() {
  if ((EUID != 0)); then
    exec sudo -E bash "$0" "$@"
  fi
}

resolve_boot_dir() {
  if [[ -n "$BOOT_DIR" ]]; then
    [[ -f "$BOOT_DIR/limine.conf" ]] || die "No limine.conf found in $BOOT_DIR"
    return
  fi

  if [[ -f /boot/limine.conf ]]; then
    BOOT_DIR="/boot"
  elif [[ -f /boot/efi/limine.conf ]]; then
    BOOT_DIR="/boot/efi"
  else
    die "Could not find limine.conf. Pass --boot-dir PATH."
  fi
}

detect_secure_boot() {
  if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    return 0
  fi

  local efivar value
  for efivar in /sys/firmware/efi/efivars/SecureBoot-*; do
    [[ -r "$efivar" ]] || continue
    value="$(od -An -t u1 -j 4 -N 1 "$efivar" 2>/dev/null | tr -d '[:space:]')"
    [[ "$value" == "1" ]] && return 0
  done

  return 1
}

use_secure_boot_hashes() {
  case "$SECURE_BOOT_MODE" in
    yes) return 0 ;;
    no) return 1 ;;
    auto) detect_secure_boot ;;
  esac
}

review_existing_backups() {
  local reply=""
  local backup
  local backups=()

  if [[ -f "$ORIGINAL_SPLASH_BACKUP" ]]; then
    section "Permanent original splash backup"
    log "Original CachyOS splash backup: $ORIGINAL_SPLASH_BACKUP"
    log "This file is not part of the cleanup prompt and will not be deleted."
  fi
  if [[ -f "$ORIGINAL_CONF_BACKUP" ]]; then
    section "Permanent original Limine config backup"
    log "Original CachyOS Limine config backup: $ORIGINAL_CONF_BACKUP"
    log "This file is not part of the cleanup prompt and will not be deleted."
  fi

  [[ -d "$BACKUP_ROOT" ]] || return 0

  while IFS= read -r backup; do
    backups+=("$backup")
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

  ((${#backups[@]} > 0)) || return 0

  section "Previous script backups"
  log "Found ${#backups[@]} previous backup(s) in $BACKUP_ROOT:"
  for backup in "${backups[@]}"; do
    printf '  - %s\n' "$backup"
  done

  if [[ ! -t 0 ]]; then
    log "No interactive terminal available; keeping previous backups."
    return
  fi

  while true; do
    printf '[fallout-limine] Delete these previous backups? [y/N] '
    read -r reply || die "Input cancelled."

    case "$reply" in
      y|Y|yes|YES)
        for backup in "${backups[@]}"; do
          run rm -rf -- "$backup"
        done
        log "Previous backups deleted."
        break
        ;;
      ""|n|N|no|NO)
        log "Keeping previous backups."
        break
        ;;
      *)
        log "Invalid answer: $reply. Please enter y or n."
        ;;
    esac
  done
}

backup_boot_files() {
  local backup_dir="$1"

  section "Backing up current boot files"
  run mkdir -p "$backup_dir"
  run cp "$BOOT_DIR/limine.conf" "$backup_dir/limine.conf"

  [[ -e "$BOOT_DIR/background.jpg" ]] && run cp "$BOOT_DIR/background.jpg" "$backup_dir/background.jpg"
  [[ -e "$BOOT_DIR/background.png" ]] && run cp "$BOOT_DIR/background.png" "$backup_dir/background.png"
  [[ -e "$BOOT_DIR/limine-splash.png" ]] && run cp "$BOOT_DIR/limine-splash.png" "$backup_dir/limine-splash.png"
  [[ -e "$BOOT_DIR/PHXEGA8.F14" ]] && run cp "$BOOT_DIR/PHXEGA8.F14" "$backup_dir/PHXEGA8.F14"

  log "Backup saved in $backup_dir"
}

preserve_original_limine_splash() {
  section "Preserving original CachyOS files"

  if [[ -f "$ORIGINAL_CONF_BACKUP" ]]; then
    log "Permanent original Limine config backup already exists: $ORIGINAL_CONF_BACKUP"
  else
    run cp -p "$BOOT_DIR/limine.conf" "$ORIGINAL_CONF_BACKUP"
    log "Permanent original Limine config backup saved: $ORIGINAL_CONF_BACKUP"
  fi

  if [[ ! -f "$BOOT_DIR/limine-splash.png" ]]; then
    log "No existing $BOOT_DIR/limine-splash.png found; nothing to preserve."
    return
  fi

  if [[ -f "$ORIGINAL_SPLASH_BACKUP" ]]; then
    log "Permanent original splash backup already exists: $ORIGINAL_SPLASH_BACKUP"
    return
  fi

  run cp -p "$BOOT_DIR/limine-splash.png" "$ORIGINAL_SPLASH_BACKUP"
  log "Permanent original splash backup saved: $ORIGINAL_SPLASH_BACKUP"
}

restore_boot_files() {
  local backup_dir="$1"

  log "Restoring files from $backup_dir"
  run cp "$backup_dir/limine.conf" "$BOOT_DIR/limine.conf"
  [[ -e "$backup_dir/background.jpg" ]] && run cp "$backup_dir/background.jpg" "$BOOT_DIR/background.jpg"
  [[ -e "$backup_dir/background.png" ]] && run cp "$backup_dir/background.png" "$BOOT_DIR/background.png"
  [[ -e "$backup_dir/limine-splash.png" ]] && run cp "$backup_dir/limine-splash.png" "$BOOT_DIR/limine-splash.png"
  [[ -e "$backup_dir/PHXEGA8.F14" ]] && run cp "$backup_dir/PHXEGA8.F14" "$BOOT_DIR/PHXEGA8.F14"
}

restore_original_limine_splash() {
  section "Restoring original CachyOS splash screen"

  [[ -f "$ORIGINAL_SPLASH_BACKUP" ]] || die "Permanent original splash backup not found: $ORIGINAL_SPLASH_BACKUP"
  run cp "$ORIGINAL_SPLASH_BACKUP" "$BOOT_DIR/limine-splash.png"
  log "Original CachyOS splash screen restored to $BOOT_DIR/limine-splash.png"
}

restore_original_limine_conf() {
  section "Restoring original CachyOS Limine config"

  [[ -f "$ORIGINAL_CONF_BACKUP" ]] || die "Permanent original Limine config backup not found: $ORIGINAL_CONF_BACKUP"
  run cp "$ORIGINAL_CONF_BACKUP" "$BOOT_DIR/limine.conf"
  log "Original CachyOS Limine config restored to $BOOT_DIR/limine.conf"
}

clone_theme() {
  local target="$1"
  section "Downloading Fallout Limine theme"
  run git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$target"
}

download_original_background() {
  local output="$1"

  section "Downloading original Fallout background"
  if command -v curl >/dev/null 2>&1; then
    run curl -L --fail -o "$output" "$ORIGINAL_BACKGROUND_URL"
  elif command -v wget >/dev/null 2>&1; then
    run wget -O "$output" "$ORIGINAL_BACKGROUND_URL"
  else
    die "Missing curl or wget to download the original background."
  fi
}

install_theme_assets() {
  local repo_dir="$1"

  [[ -f "$repo_dir/Fallout_limine/background.jpg" ]] || die "Theme background.jpg not found"
  [[ -f "$repo_dir/Fallout_limine/PHXEGA8.F14" ]] || die "Theme PHXEGA8.F14 not found"
  [[ -f "$repo_dir/Fallout_limine/Limine.txt" ]] || die "Theme Limine.txt not found"

  section "Copying theme assets"
  if [[ "$BACKGROUND_VARIANT" == "original" ]]; then
    download_original_background "$TMP_DIR/background.png"
    run cp "$TMP_DIR/background.png" "$BOOT_DIR/background.png"
  else
    run cp "$repo_dir/Fallout_limine/background.jpg" "$BOOT_DIR/background.jpg"
  fi
  run cp "$repo_dir/Fallout_limine/PHXEGA8.F14" "$BOOT_DIR/PHXEGA8.F14"
}

show_installed_assets() {
  section "Installed asset hashes"
  if [[ "$BACKGROUND_VARIANT" == "original" ]]; then
    run ls -l "$BOOT_DIR/background.png" "$BOOT_DIR/PHXEGA8.F14"
    run b2sum "$BOOT_DIR/background.png" "$BOOT_DIR/PHXEGA8.F14"
  else
    run ls -l "$BOOT_DIR/background.jpg" "$BOOT_DIR/PHXEGA8.F14"
    run b2sum "$BOOT_DIR/background.jpg" "$BOOT_DIR/PHXEGA8.F14"
  fi
}

build_theme_block() {
  local repo_dir="$1"
  local output="$2"
  local wallpaper_hash=""
  local font_hash=""
  local wallpaper_path="background.jpg"

  section "Preparing Limine theme block"

  if [[ "$BACKGROUND_VARIANT" == "original" ]]; then
    wallpaper_path="background.png"
  fi

  if use_secure_boot_hashes; then
    wallpaper_hash="$(b2sum "$BOOT_DIR/$wallpaper_path" | awk '{print $1}')"
    font_hash="$(b2sum "$BOOT_DIR/PHXEGA8.F14" | awk '{print $1}')"
    log "Secure Boot hashes enabled for wallpaper and font."
  else
    log "Secure Boot hashes not enabled."
  fi

  awk -v wallpaper_hash="$wallpaper_hash" -v font_hash="$font_hash" -v boot_timeout="$BOOT_TIMEOUT" -v wallpaper_path="$wallpaper_path" '
    /^timeout:/ && boot_timeout != "" {
      print "timeout: " boot_timeout
      next
    }
    /^wallpaper: boot\(\):\/background\.jpg$/ {
      if (wallpaper_hash != "") {
        print "wallpaper: boot():/" wallpaper_path "#" wallpaper_hash
      } else {
        print "wallpaper: boot():/" wallpaper_path
      }
      next
    }
    /^term_font: boot\(\):\/PHXEGA8\.F14$/ && font_hash != "" {
      print "term_font: boot():/PHXEGA8.F14#" font_hash
      next
    }
    { print }
  ' "$repo_dir/Fallout_limine/Limine.txt" > "$output"
}

write_limine_conf() {
  local theme_block="$1"
  local tmp_body="$2"
  local tmp_new="$3"

  section "Writing Limine config"

  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v theme_key_re="$THEME_KEY_RE" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip { next }
    $0 ~ theme_key_re { next }
    /^# CachyOS Limine theme$/ { next }
    /^# Author: diegons490 / { next }
    !skip { print }
  ' "$BOOT_DIR/limine.conf" > "$tmp_body"

  {
    printf '%s\n' "$MARKER_BEGIN"
    cat "$theme_block"
    printf '%s\n\n' "$MARKER_END"
    cat "$tmp_body"
  } > "$tmp_new"

  run cp "$tmp_new" "$BOOT_DIR/limine.conf"
  log "Theme block written to $BOOT_DIR/limine.conf"
}

show_limine_theme_preview() {
  section "Limine theme preview"
  sed -n '1,40p' "$BOOT_DIR/limine.conf"
}

run_limine_update() {
  section "Running limine-update"
  run limine-update
}

should_enroll_config() {
  use_secure_boot_hashes && return 0
  [[ -f /etc/default/limine ]] && grep -q '^ENABLE_ENROLL_LIMINE_CONFIG=yes$' /etc/default/limine
}

enroll_limine_config() {
  section "Enrolling Limine config"

  if should_enroll_config && command -v limine-enroll-config >/dev/null 2>&1; then
    run limine-enroll-config
  elif should_enroll_config; then
    die "limine-enroll-config is required after editing limine.conf, but it was not found."
  else
    log "Limine config enrollment not enabled."
  fi
}

verify_theme_applied() {
  section "Verifying final config"

  if grep -Eq '^wallpaper: boot\(\):/background\.(jpg|png)#' "$BOOT_DIR/limine.conf" &&
     grep -q '^term_font: boot():/PHXEGA8.F14#' "$BOOT_DIR/limine.conf"; then
    log "Fallout wallpaper and font are active in limine.conf."
  elif grep -Eq '^wallpaper: boot\(\):/background\.(jpg|png)$' "$BOOT_DIR/limine.conf" &&
       grep -q '^term_font: boot():/PHXEGA8.F14$' "$BOOT_DIR/limine.conf"; then
    log "Fallout wallpaper and font are active in limine.conf without Secure Boot hashes."
  else
    die "Fallout theme was not found in the final limine.conf."
  fi
}

verify_original_background_restored() {
  section "Verifying restored original Limine config"

  [[ -f "$ORIGINAL_CONF_BACKUP" ]] || die "Permanent original Limine config backup not found: $ORIGINAL_CONF_BACKUP"
  [[ -f "$ORIGINAL_SPLASH_BACKUP" ]] || die "Permanent original splash backup not found: $ORIGINAL_SPLASH_BACKUP"

  if cmp -s "$ORIGINAL_CONF_BACKUP" "$BOOT_DIR/limine.conf" &&
     cmp -s "$ORIGINAL_SPLASH_BACKUP" "$BOOT_DIR/limine-splash.png"; then
    log "Original CachyOS Limine config and splash screen are restored."
    return
  fi

  die "Original CachyOS Limine config restore could not be verified."
}

main() {
  parse_args "$@"
  require_root "$@"
  if ((INTERACTIVE_MENU == 1)); then
    choose_from_menu
  fi

  need_cmd b2sum
  need_cmd awk
  need_cmd od
  need_cmd limine-update
  if [[ "$ACTION" == "install" ]]; then
    need_cmd git
  fi

  resolve_boot_dir
  local conf="$BOOT_DIR/limine.conf"
  [[ -s "$conf" ]] || die "$conf is empty or unreadable"

  log "Using boot directory: $BOOT_DIR"
  log "Using Limine config: $conf"
  log "Action: $ACTION"

  review_existing_backups

  local timestamp repo_dir backup_dir
  timestamp="$(date +%Y%m%d-%H%M%S)"
  TMP_DIR="$(mktemp -d)"
  repo_dir="$TMP_DIR/repo"
  backup_dir="$BACKUP_ROOT/$timestamp"

  trap 'if [[ -n "$TMP_DIR" ]]; then rm -rf "$TMP_DIR"; fi' EXIT

  backup_boot_files "$backup_dir"
  choose_timeout
  choose_background_variant

  if [[ "$ACTION" == "restore-original-background" ]]; then
    restore_original_limine_splash
    run ls -l "$BOOT_DIR/limine-splash.png"
    run b2sum "$BOOT_DIR/limine-splash.png"

    if ! run_limine_update; then
      restore_boot_files "$backup_dir"
      die "Limine update failed. The previous boot files were restored."
    fi

    restore_original_limine_conf
    show_limine_theme_preview

    if ! enroll_limine_config; then
      restore_boot_files "$backup_dir"
      die "Limine config enrollment failed. The previous boot files were restored."
    fi

    verify_original_background_restored
    log "Done. Original Limine config restored. Reboot when ready."
    return
  fi

  clone_theme "$repo_dir"
  preserve_original_limine_splash
  install_theme_assets "$repo_dir"
  show_installed_assets

  if ! run_limine_update; then
    restore_boot_files "$backup_dir"
    die "Limine update failed. The previous boot files were restored."
  fi

  build_theme_block "$repo_dir" "$TMP_DIR/theme-block.conf"
  write_limine_conf "$TMP_DIR/theme-block.conf" "$TMP_DIR/limine.body" "$TMP_DIR/limine.conf.new"
  show_limine_theme_preview

  if ! enroll_limine_config; then
    restore_boot_files "$backup_dir"
    die "Limine config enrollment failed. The previous boot files were restored."
  fi

  verify_theme_applied
  log "Done. Reboot when ready."
}

trap 'on_error "$LINENO" "$BASH_COMMAND" "$?"' ERR
main "$@"
