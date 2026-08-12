#!/usr/bin/env bash
# Shared helpers sourced by every scripts/NN-*.sh step.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${WORK_DIR:-/tmp/livecd-build}"
# shellcheck disable=SC2034  # consumed by the step scripts that source this file
CHROOT_DIR="${WORK_DIR}/edit"
# shellcheck disable=SC2034
EXTRACT_DIR="${WORK_DIR}/extract-cd"

has_gum() { command -v gum >/dev/null 2>&1; }

log()  { has_gum && gum log --level info  "$*" || echo "[INFO] $*"; }
warn() { has_gum && gum log --level warn  "$*" || echo "[WARN] $*"; }
die()  { has_gum && gum log --level error "$*" || echo "[ERROR] $*"; exit 1; }

banner() {
  if has_gum; then
    gum style --border rounded --margin "1" --padding "0 2" --border-foreground 212 "$1"
  else
    echo "== $1 =="
  fi
}

spin() {
  # spin "label" -- command args...
  local label="$1"; shift
  [[ "$1" == "--" ]] && shift
  if has_gum; then
    gum spin --spinner dot --title "$label" -- "$@"
  else
    echo "[...] $label"
    "$@"
  fi
}

confirm() {
  local prompt="$1"
  if has_gum; then
    gum confirm "$prompt"
  else
    read -rp "$prompt [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
  fi
}

require_root() {
  [[ "$EUID" -eq 0 ]] || die "run as root (sudo ./build.sh ...)"
}

# Minimal YAML reader for our flat branding.yaml (no nested keys/lists).
yaml_get() {
  local key="$1" file="${2:-$ROOT_DIR/branding.yaml}"
  grep -E "^${key}:" "$file" | head -1 \
    | sed -E 's/^[^:]+:[[:space:]]*//; s/^"([^"]*)".*$/\1/; s/[[:space:]]*#.*$//; s/[[:space:]]+$//'
}

require_bin() {
  for b in "$@"; do
    command -v "$b" >/dev/null 2>&1 || die "missing required binary: $b"
  done
}
