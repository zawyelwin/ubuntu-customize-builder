#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

banner "Preparing chroot"

rm -f "$CHROOT_DIR/etc/resolv.conf"
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

cat > "$CHROOT_DIR/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT_DIR/usr/sbin/policy-rc.d"

mount --bind /dev  "$CHROOT_DIR/dev"
mount --bind /run  "$CHROOT_DIR/run"
mount -t proc  proc "$CHROOT_DIR/proc"
mount -t sysfs sys  "$CHROOT_DIR/sys"
mount -t devpts devpts "$CHROOT_DIR/dev/pts"

chroot "$CHROOT_DIR" /bin/bash -c "command -v dbus-uuidgen >/dev/null && dbus-uuidgen > /var/lib/dbus/machine-id" || true

log "bind mounts ready — chroot at $CHROOT_DIR"
