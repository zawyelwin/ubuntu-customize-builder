#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/common.sh"
require_root

ISO=""
OUT=""
YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso) ISO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --yes) YES=true; shift ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -f "$ISO" ]] || die "--iso <path> required and must exist"
ISO="$(readlink -f "$ISO")"
OUT="${OUT:-$(yaml_get output_name)}"
OUT="${OUT:-custom.iso}"

banner "livecd-builder: $(yaml_get distro_name)"

if [[ "$YES" != true ]]; then
  confirm "Build custom ISO from $ISO -> $OUT?" || die "aborted by user"
fi

cleanup_mounts() {
  for m in dev/pts dev run proc sys; do
    umount -lf "$CHROOT_DIR/$m" 2>/dev/null || true
  done
}
trap cleanup_mounts ERR

bash "$ROOT_DIR/scripts/00-check-deps.sh"
bash "$ROOT_DIR/scripts/01-fetch-extract.sh" "$ISO"
bash "$ROOT_DIR/scripts/02-chroot-setup.sh"
bash "$ROOT_DIR/scripts/03-customize.sh"
bash "$ROOT_DIR/scripts/04-branding.sh"
bash "$ROOT_DIR/scripts/05-boot-theme.sh"
bash "$ROOT_DIR/scripts/06-cleanup-chroot.sh"
bash "$ROOT_DIR/scripts/07-repack.sh"
bash "$ROOT_DIR/scripts/08-build-iso.sh" "$ISO" "$OUT"

banner "Done -> $OUT"
