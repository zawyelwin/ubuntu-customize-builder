#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

banner "Cleaning chroot"

chroot "$CHROOT_DIR" /bin/bash -c "apt-get clean" || true

rm -f "$CHROOT_DIR/usr/sbin/policy-rc.d"
rm -f "$CHROOT_DIR/root/.bash_history"
rm -f "$CHROOT_DIR/var/lib/dbus/machine-id"
rm -rf "$CHROOT_DIR/tmp/"* 2>/dev/null || true
truncate -s 0 "$CHROOT_DIR/etc/machine-id" 2>/dev/null || true

rm -f "$CHROOT_DIR/etc/resolv.conf"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$CHROOT_DIR/etc/resolv.conf"

for m in dev/pts dev run proc sys; do
  umount -lf "$CHROOT_DIR/$m" 2>/dev/null || true
done

log "chroot cleaned and unmounted"
