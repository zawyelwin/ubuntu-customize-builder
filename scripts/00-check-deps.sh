#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

banner "Checking dependencies"
require_bin unsquashfs mksquashfs xorriso rsync mount umount chroot
has_gum || warn "gum not found, falling back to plain echo output. Install for prettier logs (see README)."
log "all required tools present"
