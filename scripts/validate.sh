#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ONLINE=false
if [[ "${1:-}" == "--online" ]]; then ONLINE=true; fi

ERRORS=0
fail() { warn "FAIL: $*"; ERRORS=$((ERRORS + 1)); }

HAVE_IDENTIFY=false
if command -v identify >/dev/null 2>&1; then HAVE_IDENTIFY=true; fi

mime_of() { file --brief --mime-type "$1"; }
img_width() { identify -format '%w' "$1" 2>/dev/null || echo 0; }

banner "Validating branding.yaml"
for key in distro_name volid base_iso_url output_name; do
  if [[ -z "$(yaml_get "$key")" ]]; then
    fail "branding.yaml is missing '$key'"
  else
    log "$key: $(yaml_get "$key")"
  fi
done

VOLID="$(yaml_get volid)"
if [[ -n "$VOLID" ]]; then
  if (( ${#VOLID} > 32 )); then fail "volid '$VOLID' is longer than 32 characters"; fi
  if [[ "$VOLID" =~ [[:space:]] ]]; then fail "volid must not contain spaces"; fi
fi

KBD="$(yaml_get keyboard_layouts)"
if [[ -n "$KBD" ]]; then
  IFS=',' read -ra LAYOUTS <<< "$KBD"
  for l in "${LAYOUTS[@]}"; do
    l="${l// /}"
    if [[ -n "$l" && ! "$l" =~ ^[a-z]{2,8}$ ]]; then
      fail "keyboard_layouts: '$l' does not look like an xkb layout code (e.g. us, mm, de)"
    fi
  done
fi

URL="$(yaml_get base_iso_url)"
if [[ "$ONLINE" == true && -n "$URL" ]]; then
  if curl -fsIL --max-time 60 -o /dev/null "$URL"; then
    log "base_iso_url is reachable"
  else
    fail "base_iso_url is not reachable: $URL"
  fi
fi

banner "Validating wallpapers"
WALLS=()
while IFS= read -r f; do WALLS+=("$f"); done < <(find "$ROOT_DIR/assets/wallpapers" -maxdepth 1 -type f ! -name '.*' | sort)
if [[ ${#WALLS[@]} -eq 0 ]]; then
  warn "no wallpaper present — wallpaper branding will be skipped"
else
  log "default wallpaper: $(basename "${WALLS[0]}")"
  for w in "${WALLS[@]}"; do
    case "$(mime_of "$w")" in
      image/png|image/jpeg) ;;
      *) fail "$(basename "$w"): wallpapers must be PNG or JPEG, got $(mime_of "$w")" ;;
    esac
    if [[ "$HAVE_IDENTIFY" == true ]]; then
      W="$(img_width "$w")"
      if (( W < 1920 )); then
        warn "$(basename "$w") is only ${W}px wide — may look blurry on 1080p+ screens"
      fi
    fi
  done
fi

banner "Validating grub theme"
GRUB_BG=$(find "$ROOT_DIR/assets/grub-theme" -maxdepth 1 -type f -iname '*.png' | sort | head -1 || true)
if [[ -z "$GRUB_BG" ]]; then
  warn "no grub background png — grub splash will be skipped"
elif [[ "$(mime_of "$GRUB_BG")" != "image/png" ]]; then
  fail "$(basename "$GRUB_BG") is not a real PNG file ($(mime_of "$GRUB_BG"))"
else
  log "grub background: $(basename "$GRUB_BG") (stretched to screen size at boot)"
fi

FONT="$ROOT_DIR/assets/grub-theme/grub_font.pf2"
if [[ -f "$FONT" ]]; then
  if head -c 12 "$FONT" | grep -q PFF2; then
    log "grub_font.pf2 looks valid"
  else
    fail "grub_font.pf2 is not a valid PF2 grub font"
  fi
fi

banner "Validating plymouth splash"
PLY=$(find "$ROOT_DIR/assets/plymouth" -maxdepth 1 -type f ! -name '.*' | sort | head -1 || true)
if [[ -z "$PLY" ]]; then
  warn "no plymouth image — boot splash branding will be skipped"
elif [[ "$(mime_of "$PLY")" != "image/png" ]]; then
  fail "$(basename "$PLY"): plymouth watermark must be a PNG, got $(mime_of "$PLY")"
elif [[ "$HAVE_IDENTIFY" == true && "$(img_width "$PLY")" -gt 1024 ]]; then
  warn "$(basename "$PLY") is wider than 1024px — it will be downscaled during the build"
else
  log "plymouth watermark: $(basename "$PLY")"
fi

banner "Validating package lists"
HAVE_APT=false
if [[ "$ONLINE" == true ]] && command -v apt-cache >/dev/null 2>&1; then HAVE_APT=true; fi

check_pkgs() {
  local list="$1" p
  local pkgs=()
  while IFS= read -r p; do pkgs+=("$p"); done < <(grep -vE '^\s*#|^\s*$' "$list" 2>/dev/null || true)
  log "$(basename "$list"): ${#pkgs[@]} package(s)"
  if [[ ${#pkgs[@]} -eq 0 ]]; then return 0; fi
  for p in "${pkgs[@]}"; do
    if [[ ! "$p" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
      fail "$(basename "$list"): '$p' is not a valid package name"
      continue
    fi
    if [[ "$HAVE_APT" == true ]] && ! apt-cache show "$p" >/dev/null 2>&1; then
      fail "$(basename "$list"): '$p' not found in the apt archive"
    fi
  done
}
check_pkgs "$ROOT_DIR/config/packages-add.txt"
check_pkgs "$ROOT_DIR/config/packages-remove.txt"

if (( ERRORS > 0 )); then
  die "validation failed with $ERRORS error(s)"
fi
banner "Validation passed"
