#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

banner "Applying boot theme"

GRUB_SRC_DIR="$ROOT_DIR/assets/grub-theme"
GRUB_BG=$(find "$GRUB_SRC_DIR" -maxdepth 1 -type f -iname '*.png' | sort | head -1 || true)
VOLID="$(yaml_get volid)"
DISTRO_NAME="$(yaml_get distro_name)"
DEFAULT_LANG="$(yaml_get default_lang)"

if [[ -n "$GRUB_BG" ]]; then
  mkdir -p "$EXTRACT_DIR/boot/grub"
  cp "$GRUB_BG" "$EXTRACT_DIR/boot/grub/splash.png"
  log "copied $(basename "$GRUB_BG") -> boot/grub/splash.png"
  if [[ -f "$EXTRACT_DIR/boot/grub/grub.cfg" ]]; then
    grep -q "background_image" "$EXTRACT_DIR/boot/grub/grub.cfg" || \
      printf '\nbackground_image -m stretch /boot/grub/splash.png\n' >> "$EXTRACT_DIR/boot/grub/grub.cfg"
  fi
else
  warn "no grub background png found in $GRUB_SRC_DIR, skipping grub splash"
fi

FONT_SRC="$GRUB_SRC_DIR/grub_font.pf2"
if [[ -f "$FONT_SRC" ]]; then
  cp "$FONT_SRC" "$EXTRACT_DIR/boot/grub/font.pf2"
  log "copied custom grub font"
fi

if [[ -n "$VOLID" ]]; then
  if [[ -f "$EXTRACT_DIR/.disk/info" ]]; then
    sed -i "1s|.*|${DISTRO_NAME:-Custom Ubuntu} - Release ${VOLID}|" "$EXTRACT_DIR/.disk/info"
  fi
  if [[ -f "$EXTRACT_DIR/README.diskdefines" ]]; then
    sed -i "s|^#define DISKNAME.*|#define DISKNAME  ${DISTRO_NAME:-Custom Ubuntu}|" "$EXTRACT_DIR/README.diskdefines"
  fi
  log "set disk metadata: volid=${VOLID}"
fi

if [[ -n "$DEFAULT_LANG" && -f "$EXTRACT_DIR/isolinux/isolinux.cfg" ]]; then
  sed -i "s|^DEFAULT_LANG=.*|DEFAULT_LANG=${DEFAULT_LANG}|" "$EXTRACT_DIR/isolinux/isolinux.cfg" || true
fi

log "boot theme step done"
