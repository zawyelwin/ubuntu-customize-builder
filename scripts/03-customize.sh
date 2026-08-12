#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

banner "Applying package changes"

ADD_LIST="$ROOT_DIR/config/packages-add.txt"
REMOVE_LIST="$ROOT_DIR/config/packages-remove.txt"

mapfile -t ADD_PKGS < <(grep -vE '^\s*#|^\s*$' "$ADD_LIST" 2>/dev/null || true)
mapfile -t REMOVE_PKGS < <(grep -vE '^\s*#|^\s*$' "$REMOVE_LIST" 2>/dev/null || true)

in_chroot() {
  chroot "$CHROOT_DIR" /bin/bash -c "export HOME=/root LC_ALL=C DEBIAN_FRONTEND=noninteractive; $1"
}

in_chroot "apt-get update"

if [[ ${#ADD_PKGS[@]} -gt 0 ]]; then
  log "installing: ${ADD_PKGS[*]}"
  in_chroot "apt-get install -y ${ADD_PKGS[*]}"
fi

if [[ ${#REMOVE_PKGS[@]} -gt 0 ]]; then
  log "removing: ${REMOVE_PKGS[*]}"
  in_chroot "apt-get purge -y ${REMOVE_PKGS[*]}"
  in_chroot "apt-get autoremove -y"
fi

log "package customization done"
