![Kinoite Gaming — Next Generation](repo_assets/banner.png)

# Kinoite-Gaming-Next-Generation

A **universal** **bootc** (Fedora Atomic) image based on **Kinoite 45**
(`quay.io/fedora-ostree-desktops/kinoite:45`), built with
[BlueBuild](https://blue-build.org/). Next generation of
`swam-os-kinoite-gaming`: same stack, F45 base.

**Identity**: stock Fedora/Kinoite — the SwamOS rebadge (os-release, SDDM,
fastfetch) was reverted (commit `c4790e1`).

- **Base**: `quay.io/fedora-ostree-desktops/kinoite`, version `45`
- **Published image**: `ghcr.io/swam-web/kinoite-gaming-next-generation:latest`
- **F45 base status**: GA scheduled **2026-10-27** (delayed from 10/20) — until then,
  the `:45` tag points at final-freeze composes. The CachyOS COPR already builds
  for `fedora-45-x86_64` ✓

## Why a universal image

| Hardware | What happens |
|---|---|
| NVIDIA | `nvidia.ko` (clang-built akmod) loads, `nouveau` blacklisted; ROCm present but inert |
| AMD | in-tree `amdgpu` (CachyOS kernel) loads; the NVIDIA stack is inert |
| Hybrid laptop (AMD iGPU + NVIDIA dGPU) | Both load and cooperate — impossible with two separate images |

## What's inside

| | Detail |
|---|---|
| **Kernel** | CachyOS `kernel-cachyos-lto` (Clang LTO, 1000 Hz, full preempt) — COPR `bieszczaders/kernel-cachyos-lto`, replaces the Fedora kernel (`install-kernel-akmods` pattern) |
| **NVIDIA (RPMFusion)** | `akmod-nvidia` + userland `xorg-x11-drv-nvidia` (`.i686` included), kmods rebuilt with **clang** against the CachyOS kernel (`pahole` + `xorg-x11-drv-nvidia-kmodsrc`) |
| **AMD ROCm (minimal gaming)** | Official AMD repo (RHEL9): `rocm-core`, `rocm-opencl-runtime`, `rocm-smi` — installed via the BlueBuild optfix (`/usr/lib/opt`, `/opt` symlinks at boot). **No HIP stack** (`rocm-hip-runtime`, `rocm-libs`/rocBLAS ≈ 5-6 GB): useless for gaming (Vulkan/DXVK via mesa) — if you need it: `rpm-ostree install rocm-hip-runtime rocm-libs` |
| **MT7927 WiFi/BT** | `mt7925e`/`mt76` + `btusb`/`btmtk` prebuilt (jetm/mediatek-mt7927-dkms v2.16, clang) against the CachyOS kernel; BT firmware `MT6639` bundled (missing from linux-firmware) |
| **Universal codecs** | RPMFusion: full ffmpeg, `@multimedia`, openh264, libdvdcss; VA-API/Vulkan **AMD** (`mesa-*-freeworld`) **and** NVIDIA NVDEC→VA-API bridge (`libva-nvidia-driver`); full 32-bit |
| **Gaming** | gamescope, gamemode, mangohud, vkBasalt, goverlay, steam-devices (RPM); Steam, Lutris, Heroic, Bottles, OBS, **BoxBuddy** (distrobox GUI)… (Flathub, `default-flatpaks`); **flatpak VulkanLayer** MangoHud/gamescope/vkBasalt (refs pinned to 25.08/26.08 — RPM layers don't reach flatpak games) |
| **Peripherals (fail-soft)** | **xpadneo** (Xbox BT controllers, advanced rumble), **xone** (Xbox USB dongle + firmware), **OpenRazer** (clang kmods + daemon), **OpenTabletDriver** (tablets), `libcec` (HDMI CEC via Pulse-Eight adapter) — a failed source doesn't kill the build |
| **Responsiveness (CachyOS base)** | `scx_lavd` (sched_ext, auto Gaming mode), `ananicy-cpp`, zram + `cachyos-settings` sysctls; **`game-performance`** (provided by `cachyos-settings`): `powerprofilesctl` performance on app launch — add it to Steam launch options (`game-performance %command%`) for games outside gamemode |
| **Gaming tuning** | `gamemode.ini` (renice -10 via PAM limits `limits.d/swam-gamemode.conf`, performance governor); PipeWire quantum **256** (~5.3 ms); sysctl **BBR + fq + `vm.max_map_count`** (absent from `cachyos-settings`); Plasma animations ÷2 (`kdeglobals` /etc/xdg); `thermald` (Intel, inert on AMD); karg `nvidia-drm.fbdev=1` |
| **Peripheral latency** | BT **ERTM off** (DualSense/DS4 controllers), HDA **power-save off** (anti-crackle, consistent with quantum 256), USB **autosuspend off** (karg, dongles), MT7927 WiFi **ASPM off** (`mt7925e.disable_aspm`), memory anti-stall (`watermark_boost_factor=0`, `watermark_scale_factor=125`, `compaction_proactiveness=0`) — `modprobe.d/70-swam-gaming.conf` + `sysctl.d/70-swam-gaming.conf` |
| **Lightweight** | Baloo (indexer) masked, `irqbalance` and `plasma-discover` removed, `cups`/`avahi` **socket-activated**, KWin `AllowTearing`, btrfs `zstd` compression; **measured RAM footprint: ~1.6 GiB at 44 s after boot** (31 GiB, full KDE + gaming stack — scx, ananicy, firewalld, avahi, bluetooth — swap 0) |
| **Data snapshots** | `snapper` (hourly timeline on `/var/home`, config created on first boot by `swam-snapper-setup.service`, progressive pruning) + **Btrfs Assistant** (GUI: browse/restore) + `btrfsmaintenance` (scrub/balance). Fine-grained data recovery — **not a backup** (same disk); the OS itself is versioned by ostree (`rpm-ostree rollback`) |

## Installation

```bash
sudo bootc switch ghcr.io/swam-web/kinoite-gaming-next-generation:latest
sudo systemctl reboot
```

## Caveats

- **Secure Boot**: the CachyOS kernel and built modules are not signed by a
  Microsoft-approved key. Disable Secure Boot, or enroll your own MOK key.
- The **NVIDIA open** driver supports **Turing (RTX 20) and newer**.
- On **AMD-only** machines, the initramfs forces `nvidia.ko` which finds no hardware:
  a benign boot warning, no effect.
- **MT7927 (WiFi/BT)**: prebuilt modules jetm/mediatek-mt7927-dkms v2.16
  against the CachyOS kernel (clang) + bundled BT firmware `BT_RAM_CODE_MT6639`.
  The driver was once removed (2026-10) as a suspect in the user-profile
  corruption saga; it was **cleared** (identical crash with or without it)
  and is back in the image.
- `tsc=reliable clocksource=tsc`: remove these kargs if you hit clock drift (exotic VMs).
- `clearcpuid=514`: masks CPUID feature 514 — **required to launch some games**
  (Proton/Wine). Only remove it knowingly.
- **NVIDIA troubleshooting**: on a black screen or a session that won't start with the
  proprietary driver, the karg `nvidia.NVreg_EnableGpuFirmware=0` (GSP off) is the first
  lever, proven on RTX 40 (validated on i9-14900K, driver 615). Add it **case by case** —
  the image doesn't enforce it (GSP on works fine on most setups).
- `mitigations=off` is deliberately **not enabled** (see the comment in `recipe.yml`).

## Build

```bash
# container image
sudo -E nix run github:blue-build/cli -- build recipe recipes/recipe.yml

# validation only (fast)
bluebuild validate recipes/recipe.yml
```

## Disk images (ISO / qcow2)

Via **bootc-image-builder** (read the caveat in the `swam-os-kinoite-nvidia` repo about
`bluebuild generate-iso` limitations):

```bash
sudo podman run --rm --privileged --pull=newer \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type anaconda-iso \
  --config ./disk_config/iso.toml \
  --local --chown $(id -u):$(id -g) \
  ghcr.io/swam-web/kinoite-gaming-next-generation:latest
```

Or via GitHub Actions: `Actions → Build disk images → Run workflow`
(set `release-tag`, e.g. `v45.0`, to publish the ISO to Releases — public download).

## Signing

Images are signed with **cosign** (public key in `cosign.pub`, GitHub secret `SIGNING_SECRET`).

```bash
cosign verify --key cosign.pub ghcr.io/swam-web/kinoite-gaming-next-generation:latest
```

## Credits

[Fedora Kinoite](https://fedoraproject.org/kinoite/) / [Universal Blue](https://universal-blue.org/),
[BlueBuild](https://blue-build.org/), [CachyOS](https://cachyos.org/), [RPMFusion](https://rpmfusion.org/),
[AMD ROCm](https://www.amd.com/en/developer/resources/rocm-hub.html),
[jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms).
