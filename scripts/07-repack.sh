#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

banner "Repacking squashfs"

LIVE_DIR="$EXTRACT_DIR/$(cat "$WORK_DIR/live.dir")"

find "$LIVE_DIR" -maxdepth 1 \( -name '*.squashfs' -o -name '*.squashfs.gpg' \
  -o -name '*.manifest' -o -name '*.size' \) -delete

chroot "$CHROOT_DIR" dpkg-query -W --showformat='${Package}\t${Version}\n' > "$LIVE_DIR/filesystem.manifest"
log "regenerated filesystem.manifest ($(wc -l < "$LIVE_DIR/filesystem.manifest") packages)"

spin "mksquashfs (this takes a while)" -- \
  mksquashfs "$CHROOT_DIR" "$LIVE_DIR/filesystem.squashfs" -comp xz

SIZE_BYTES=$(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1)
echo "$SIZE_BYTES" > "$LIVE_DIR/filesystem.size"
log "filesystem.size = ${SIZE_BYTES} bytes"

if [[ -f "$LIVE_DIR/install-sources.yaml" ]]; then
  DISTRO_NAME="$(yaml_get distro_name)"
  cat > "$LIVE_DIR/install-sources.yaml" <<EOF
- default: true
  description:
    en: ${DISTRO_NAME:-Custom Ubuntu}
  id: custom-desktop
  locale_support: locale-only
  name:
    en: ${DISTRO_NAME:-Custom Ubuntu}
  path: filesystem.squashfs
  size: ${SIZE_BYTES}
  type: fsimage
EOF
  log "rewrote install-sources.yaml for the flattened image"
fi

VMLINUZ=$(find "$CHROOT_DIR/boot" -maxdepth 1 -name 'vmlinuz-*' | sort -V | tail -1 || true)
INITRD=$(find "$CHROOT_DIR/boot" -maxdepth 1 -name 'initrd.img-*' | sort -V | tail -1 || true)
if [[ -n "$VMLINUZ" && -f "$LIVE_DIR/vmlinuz" ]]; then
  cp "$VMLINUZ" "$LIVE_DIR/vmlinuz"
  log "synced $(basename "$VMLINUZ") -> $(basename "$LIVE_DIR")/vmlinuz"
fi
if [[ -z "$INITRD" && -f "$LIVE_DIR/initrd" ]]; then
  warn "no initrd in chroot /boot — the ISO keeps the stock initrd, which still expects the deleted squashfs layers"
fi
if [[ -n "$INITRD" && -f "$LIVE_DIR/initrd" ]]; then
  cp "$INITRD" "$LIVE_DIR/initrd"
  log "synced $(basename "$INITRD") -> $(basename "$LIVE_DIR")/initrd"

  # A regenerated initrd carries a new casper uuid; .disk/casper-uuid-* on
  # the medium must match or casper rejects the live filesystem at boot.
  if command -v unmkinitramfs >/dev/null 2>&1 && [[ -d "$EXTRACT_DIR/.disk" ]]; then
    UUID_TMP="$WORK_DIR/initrd-uuid"
    rm -rf "$UUID_TMP"
    mkdir -p "$UUID_TMP"
    if unmkinitramfs "$INITRD" "$UUID_TMP" 2>/dev/null; then
      UUID_CONF=$(find "$UUID_TMP" -name uuid.conf | head -1)
      if [[ -n "$UUID_CONF" ]]; then
        rm -f "$EXTRACT_DIR/.disk/casper-uuid-"*
        cp "$UUID_CONF" "$EXTRACT_DIR/.disk/casper-uuid-generic"
        log "refreshed .disk/casper-uuid-generic from the regenerated initrd"
      fi
    else
      warn "could not unpack initrd to refresh the casper uuid — live boot may fail"
    fi
    rm -rf "$UUID_TMP"
  else
    warn "unmkinitramfs unavailable — casper uuid not refreshed, live boot may fail"
  fi
fi

for cfg in "$EXTRACT_DIR/boot/grub/grub.cfg" "$EXTRACT_DIR/boot/grub/loopback.cfg"; do
  if [[ -f "$cfg" ]]; then
    sed -i -E 's/layerfs-path=[^[:space:]]+/layerfs-path=filesystem.squashfs/g' "$cfg"
    sed -i -E '/^[[:space:]]*linux[[:space:]]/{/layerfs-path=/! s/[[:space:]]+---/ layerfs-path=filesystem.squashfs ---/}' "$cfg"
  fi
done

log "regenerating md5sum.txt"
( cd "$EXTRACT_DIR" && \
  find . -type f -not -path ./md5sum.txt -not -name 'boot.cat*' -print0 \
    | xargs -0 md5sum > md5sum.txt )
