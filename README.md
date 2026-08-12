# livecd-builder

Automates Ubuntu LiveCD/ISO customization following
https://help.ubuntu.com/community/LiveCDCustomization.
Fork it, drop your branding assets in folders, open a PR — CI validates your
assets, builds the ISO, and comments the download link on the PR.

## How it works

1. Fork this repo.
2. Edit `branding.yaml` and drop assets into the folders below.
3. Open a pull request.
4. The **validate** job checks your config, images, and package lists and
   fails fast with clear errors.
5. The **build** job produces the ISO (~60–90 min) and uploads it as a
   workflow artifact.
6. A bot comment appears on the PR with the download link.

Notes: you must be signed in to GitHub to download artifacts, artifacts
expire after 14 days, and first-time contributors need a maintainer to
approve the workflow run. Pushes to `main` and manual dispatch from the
Actions tab build the ISO too.

## Folder map

| Path | Purpose |
|---|---|
| `branding.yaml` | distro name, volid, locale, base ISO url, output name |
| `assets/wallpapers/` | desktop background images (first file = default) |
| `assets/grub-theme/` | grub menu background png + optional `grub_font.pf2` |
| `assets/plymouth/` | boot splash logo png (plymouth watermark) |
| `config/packages-add.txt` | one package name per line, installed in chroot |
| `config/packages-remove.txt` | one package name per line, purged in chroot |

## Asset guidelines

### Wallpapers — `assets/wallpapers/`

- **Format**: PNG or JPEG (validation rejects anything else).
- **Size**: 3840×2160 recommended, 1920×1080 minimum. Validation warns below
  1920px wide. GNOME zooms the image to fill the screen, so any aspect ratio
  works, but 16:9 avoids visible cropping on most displays.
- Keep files under ~10 MB — every byte ships inside the ISO.
- The alphabetically **first** file becomes the default desktop background;
  prefix filenames (`00-default.png`, `01-alt.png`) to control ordering.

### GRUB background — `assets/grub-theme/`

- **Format**: PNG only (first `*.png` found is used).
- **Size**: 1920×1080 recommended. The image is stretched to the boot screen
  resolution, so exact size is not critical, but very large files slow the
  boot menu.
- Use a dark or low-contrast image — the GRUB menu renders white text
  directly over it.
- Optional `grub_font.pf2`: generate one with
  `grub-mkfont -s 16 -o grub_font.pf2 YourFont.ttf`.

### Plymouth boot splash — `assets/plymouth/`

- **Format**: PNG, ideally with a transparent background (first `*.png`
  found is used).
- **Size**: this is a centered logo watermark, not a wallpaper — 300–600px
  wide looks right. Anything wider than 1024px is automatically downscaled
  during the build.
- It is displayed on a dark background while booting, so light or white
  logos read best.
- Applied to Ubuntu's spinner/bgrt theme; the build regenerates the
  initramfs so the splash shows in both the live session and installed
  systems.

### Package lists — `config/`

- One package per line, `#` comments allowed.
- Names must exist in the Ubuntu archive matching your base release —
  validation checks each name against apt before the build starts.
- Removing large metapackages can break desktop dependencies; test in a VM
  before relying on the result.

## Validating locally

```bash
./scripts/validate.sh            # offline checks
./scripts/validate.sh --online   # also checks base_iso_url + apt package names
```

Runs without root. `file` is required; `imagemagick` enables the dimension
checks. CI runs the same script plus `shellcheck` on every PR.

## Base image support

Supported bases are **Ubuntu 24.04 and newer** (the default in `branding.yaml`
is the latest 24.04 desktop point release). Releases older than 24.04 are not
supported.

Modern Ubuntu desktop ISOs ship the root filesystem as a stack of squashfs
layers (`minimal` → `minimal.standard` → `minimal.standard.live`). The build
flattens the layer chain that grub boots into a single tree, customizes it in
a chroot, then repacks it as one classic `filesystem.squashfs` — a layout
casper and the installer still fully support (it is what official flavors
like Xubuntu use). Flavors that already ship a single squashfs work as-is.

## Local build

Requires a real Linux kernel with mount/chroot/loop-device/overlayfs
privileges — bare metal, a VM, or WSL2 (not a default Docker container).
Needs ~30 GB free disk.

```bash
sudo apt-get install squashfs-tools xorriso rsync imagemagick
sudo ./build.sh --iso ubuntu-base.iso --out custom.iso
```

`gum` is optional and only makes the logs prettier — install per
https://github.com/charmbracelet/gum#installation.

Add `--yes` to skip the confirmation prompt. The working directory defaults
to `/tmp/livecd-build`; override with `WORK_DIR=/path sudo -E ./build.sh ...`.

## Pipeline

`build.sh` runs `scripts/00`–`08` in order:

| Step | What it does |
|---|---|
| 00 | verify required binaries |
| 01 | loop-mount base ISO, copy tree, flatten the squashfs layer chain into a root filesystem |
| 02 | bind-mount /dev /run /proc /sys into the chroot |
| 03 | apt install/purge per `config/*.txt` |
| 04 | wallpaper, gschema override, plymouth watermark, `PRETTY_NAME` |
| 05 | grub splash/font, `.disk/info`, `README.diskdefines` |
| 06 | clean apt cache, machine-id, history; unmount chroot |
| 07 | drop old layers, mksquashfs, sync kernel/initrd, regenerate manifest/size/install-sources.yaml/md5sum.txt |
| 08 | rebuild hybrid BIOS+EFI ISO with xorriso (boot layout derived from the base ISO) |

Each step is independently runnable for debugging, e.g.
`sudo scripts/07-repack.sh` after a manual chroot tweak.
