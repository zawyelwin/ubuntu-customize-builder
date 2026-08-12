#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

banner "Repacking squashfs"

LIVE_DIR="$EXTRACT_DIR/$(cat "$WORK_DIR/live.dir")"
mapfile -t OLD_LAYERS < "$WORK_DIR/layers.rel"

for layer in "${OLD_LAYERS[@]}"; do
  base="${layer%.squashfs}"
  rm -f "$LIVE_DIR/$layer" "$LIVE_DIR/$base.manifest" "$LIVE_DIR/$base.size"
done

chroot "$CHROOT_DIR" dpkg-query -W --showformat='${Package}\t${Version}\n' > "$LIVE_DIR/filesystem.manifest"
log "regenerated filesystem.manifest ($(wc -l < "$LIVE_DIR/filesystem.manifest") packages)"

spin "mksquashfs (this takes a while)" -- \
  mksquashfs "$CHROOT_DIR" "$LIVE_DIR/filesystem.squashfs" -comp xz

SIZE_BYTES=$(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1)
echo "$SIZE_BYTES" > "$LIVE_DIR/filesystem.size"

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
if [[ -n "$INITRD" && -f "$LIVE_DIR/initrd" ]]; then
  cp "$INITRD" "$LIVE_DIR/initrd"
  log "synced $(basename "$INITRD") -> $(basename "$LIVE_DIR")/initrd"
fi

for cfg in "$EXTRACT_DIR/boot/grub/grub.cfg" "$EXTRACT_DIR/boot/grub/loopback.cfg"; do
  if [[ -f "$cfg" ]]; then
    sed -i 's/ layerfs-path=[^ ]*//g' "$cfg"
  fi
done

log "regenerating md5sum.txt"
( cd "$EXTRACT_DIR" && \
  find . -type f -not -path ./md5sum.txt -not -name 'boot.cat*' -print0 \
    | xargs -0 md5sum > md5sum.txt )
