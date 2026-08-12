#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
require_root

BASE_ISO="${1:?usage: 01-fetch-extract.sh <path-to-base.iso>}"
banner "Extracting base ISO"

if [[ -d "$WORK_DIR" ]]; then
  awk -v d="$WORK_DIR/" 'index($2, d) == 1 { print $2 }' /proc/mounts | sort -r | \
    while read -r m; do umount -lf "$m" || true; done
  rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR/mnt" "$EXTRACT_DIR" "$CHROOT_DIR"

spin "mounting $BASE_ISO" -- mount -o loop,ro "$BASE_ISO" "$WORK_DIR/mnt"
spin "copying ISO contents" -- rsync -a "$WORK_DIR/mnt/" "$EXTRACT_DIR/"
umount "$WORK_DIR/mnt"

GRUB_CFG="$EXTRACT_DIR/boot/grub/grub.cfg"
LAYER_TOP=""
if [[ -f "$GRUB_CFG" ]]; then
  LAYER_TOP=$(grep -oE 'layerfs-path=[^ ]+' "$GRUB_CFG" | head -1 | cut -d= -f2 || true)
fi

if [[ -n "$LAYER_TOP" ]]; then
  LAYER_TOP_PATH=$(find "$EXTRACT_DIR" -maxdepth 2 -name "$LAYER_TOP" | head -1)
  [[ -n "$LAYER_TOP_PATH" ]] || die "grub boots layer $LAYER_TOP but it is not on the ISO"
  LIVE_DIR="$(dirname "$LAYER_TOP_PATH")"

  # Layer chain is encoded in the filename: minimal.standard.live.squashfs
  # stacks minimal -> minimal.standard -> minimal.standard.live.
  CHAIN=()
  name=""
  IFS='.' read -ra PARTS <<< "${LAYER_TOP%.squashfs}"
  for p in "${PARTS[@]}"; do
    name="${name:+$name.}$p"
    if [[ -f "$LIVE_DIR/$name.squashfs" ]]; then
      CHAIN+=("$name.squashfs")
    fi
  done
  [[ ${#CHAIN[@]} -gt 0 ]] || die "could not resolve layer chain for $LAYER_TOP"
  log "layered ISO: ${CHAIN[*]}"

  LOWER=""
  MOUNTS=()
  i=0
  for layer in "${CHAIN[@]}"; do
    mp="$WORK_DIR/layers/$i"
    mkdir -p "$mp"
    mount -o loop,ro "$LIVE_DIR/$layer" "$mp"
    MOUNTS+=("$mp")
    LOWER="$mp${LOWER:+:$LOWER}"
    i=$((i + 1))
  done

  MERGED="$WORK_DIR/merged"
  mkdir -p "$MERGED"
  mount -t overlay overlay -o "lowerdir=$LOWER" "$MERGED"
  spin "flattening ${#CHAIN[@]} layers (this takes a while)" -- \
    rsync -aHAX --numeric-ids "$MERGED/" "$CHROOT_DIR/"
  umount "$MERGED"
  for mp in "${MOUNTS[@]}"; do umount "$mp"; done

  printf '%s\n' "${CHAIN[@]}" > "$WORK_DIR/layers.rel"
  echo "${LIVE_DIR#"$EXTRACT_DIR"/}" > "$WORK_DIR/live.dir"
else
  mapfile -t SQUASHES < <(find "$EXTRACT_DIR" -maxdepth 2 -name '*.squashfs' | sort)
  [[ ${#SQUASHES[@]} -eq 1 ]] || \
    die "unsupported ISO layout (found ${#SQUASHES[@]} squashfs files and no layerfs boot chain)"
  SQUASHFS_PATH="${SQUASHES[0]}"
  basename "$SQUASHFS_PATH" > "$WORK_DIR/layers.rel"
  dirname "${SQUASHFS_PATH#"$EXTRACT_DIR"/}" > "$WORK_DIR/live.dir"
  spin "unsquashfs filesystem (this takes a while)" -- unsquashfs -f -d "$CHROOT_DIR" "$SQUASHFS_PATH"
fi

log "root filesystem ready at $CHROOT_DIR"
