#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

BASE_ISO="${1:?usage: 08-build-iso.sh <path-to-base.iso> <output.iso>}"
OUT_ISO="${2:?usage: 08-build-iso.sh <path-to-base.iso> <output.iso>}"
BASE_ISO="$(readlink -f "$BASE_ISO")"
VOLID="$(yaml_get volid)"
VOLID="${VOLID:-CUSTOM}"

banner "Building final ISO"

# Derive the exact El Torito / hybrid boot layout from the base ISO so the
# rebuild boots BIOS+EFI regardless of release (isolinux vs grub-only).
OPTS_FILE="$WORK_DIR/mkisofs-opts.txt"
xorriso -indev "$BASE_ISO" -report_el_torito as_mkisofs 2>/dev/null \
  | grep -vE '^-V ' > "$OPTS_FILE"
[[ -s "$OPTS_FILE" ]] || die "could not derive boot options from $BASE_ISO (needs xorriso >= 1.4.4)"

rm -f "$OUT_ISO"
log "assembling ISO with xorriso"
eval "xorriso -as mkisofs $(tr '\n' ' ' < "$OPTS_FILE") -V '$VOLID' -o '$OUT_ISO' '$EXTRACT_DIR'"

log "ISO written to $OUT_ISO"
