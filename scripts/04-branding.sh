#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

banner "Applying branding"

OVERRIDE_DIR="$CHROOT_DIR/usr/share/glib-2.0/schemas"
OVERRIDE_FILE="$OVERRIDE_DIR/99_livecd-builder.gschema.override"
mkdir -p "$OVERRIDE_DIR"
: > "$OVERRIDE_FILE"

WALLPAPER=$(find "$ROOT_DIR/assets/wallpapers" -maxdepth 1 -type f ! -name '.*' | sort | head -1 || true)
if [[ -n "$WALLPAPER" ]]; then
  EXT="${WALLPAPER##*.}"
  DEST_NAME="custom-wallpaper.${EXT,,}"
  mkdir -p "$CHROOT_DIR/usr/share/backgrounds"
  cp "$WALLPAPER" "$CHROOT_DIR/usr/share/backgrounds/$DEST_NAME"
  log "copied $(basename "$WALLPAPER") -> /usr/share/backgrounds/$DEST_NAME"

  cat >> "$OVERRIDE_FILE" <<EOF
[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/${DEST_NAME}'
picture-uri-dark='file:///usr/share/backgrounds/${DEST_NAME}'

EOF
else
  warn "no wallpaper found in assets/wallpapers, skipping wallpaper"
fi

KBD_LAYOUTS="$(yaml_get keyboard_layouts)"
if [[ -n "$KBD_LAYOUTS" ]]; then
  SOURCES=""
  IFS=',' read -ra LAYOUTS <<< "$KBD_LAYOUTS"
  for l in "${LAYOUTS[@]}"; do
    l="${l// /}"
    if [[ -n "$l" ]]; then
      SOURCES+="${SOURCES:+, }('xkb', '$l')"
    fi
  done
  if [[ -n "$SOURCES" ]]; then
    cat >> "$OVERRIDE_FILE" <<EOF
[org.gnome.desktop.input-sources]
sources=[${SOURCES}]

EOF
    log "keyboard layouts: $KBD_LAYOUTS"
  fi
fi

if [[ -s "$OVERRIDE_FILE" ]]; then
  chroot "$CHROOT_DIR" /bin/bash -c "glib-compile-schemas /usr/share/glib-2.0/schemas" \
    || warn "glib-compile-schemas failed — check gnome schemas exist in the base image"
else
  rm -f "$OVERRIDE_FILE"
fi

PLYMOUTH_SRC=$(find "$ROOT_DIR/assets/plymouth" -maxdepth 1 -type f -iname '*.png' | sort | head -1 || true)
if [[ -n "$PLYMOUTH_SRC" ]]; then
  SPINNER_DIR="$CHROOT_DIR/usr/share/plymouth/themes/spinner"
  if [[ -d "$SPINNER_DIR" ]]; then
    if command -v identify >/dev/null 2>&1 && command -v convert >/dev/null 2>&1 && \
       [[ "$(identify -format '%w' "$PLYMOUTH_SRC")" -gt 1024 ]]; then
      convert "$PLYMOUTH_SRC" -resize 1024x "$SPINNER_DIR/watermark.png"
      log "downscaled $(basename "$PLYMOUTH_SRC") -> plymouth watermark"
    else
      cp "$PLYMOUTH_SRC" "$SPINNER_DIR/watermark.png"
      log "copied $(basename "$PLYMOUTH_SRC") -> plymouth watermark"
    fi
    spin "update-initramfs (this takes a while)" -- \
      chroot "$CHROOT_DIR" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive; update-initramfs -u"
  else
    warn "plymouth spinner theme not found in base image, skipping boot splash"
  fi
else
  warn "no plymouth png found in assets/plymouth, skipping boot splash"
fi

DISTRO_NAME="$(yaml_get distro_name)"
if [[ -n "$DISTRO_NAME" && -f "$CHROOT_DIR/etc/os-release" ]]; then
  sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${DISTRO_NAME}\"|" "$CHROOT_DIR/etc/os-release"
  log "set PRETTY_NAME to '${DISTRO_NAME}'"
fi

log "branding applied"
