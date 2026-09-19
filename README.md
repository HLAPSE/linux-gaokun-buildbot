English | [中文](docs/README_zh.md)

# linux-gaokun-buildbot

Build scripts, patches, kernel config, DTS files, tools, and firmware for Linux images targeting the Huawei MateBook E Go (codename `gaokun3`) based on Qualcomm Snapdragon 8cx Gen 3 (`SC8280XP`). The `gaokun3` device tree covers both the 2022 Performance Edition (GK-W76, prime cores at 3.0 GHz) and the 2023 Edition (downclocked to ~2.69 GHz) — see the [platform notes](docs/platform_notes_en.md) for how to tell them apart (the DMI model string alone is unreliable).

The image pipeline now uses `systemd-boot` by default and can optionally build a second EL2 kernel variant with `CONFIG_LOCALVERSION="-gaokun3-el2"`.

## What is included

### Repository layout

- `patches/`: kernel patches and device support changes
- `defconfig/`: local kernel configuration used by CI/manual builds
- `drivers/`: local mirrors of the patched driver sources kept in the patch series
- `dts/`: local mirrors of the patched device tree sources kept in the patch series
- `docs/`: bilingual usage/build guides and platform notes
- `firmware/`: minimal firmware bundle used by the image build
- `packaging/`: distro kernel and firmware package templates and metadata
- `tools/`: device-specific helper scripts, service files, and EL2 EFI payloads
- `scripts/ci/`: workflow build, image creation, and packaging scripts
- `scripts/local/`: some useful scripts that can be run on the local device

### Package outputs

The package pipeline builds and installs dedicated package sets:

- **Fedora (RPM)**: `kernel-gaokun3`, `kernel-modules-gaokun3`, `kernel-devel-gaokun3`, `linux-firmware-gaokun3`
- **Ubuntu (DEB)**: `linux-image-gaokun3`, `linux-modules-gaokun3`, `linux-headers-gaokun3`, `linux-firmware-gaokun3`
- **Optional EL2 variants**: `*-gaokun3-el2` package set for the second EL2 kernel build
- Ubuntu kernel image packages run `update-initramfs` during install/upgrade, which in turn refreshes the BLS entry through the distro `systemd-boot` hook.
- Fedora kernel RPMs now ship a matching `dracut.conf.d` snippet and run `dracut` + `kernel-install add` in `%posttrans`, so installing or upgrading the package refreshes the initramfs and BLS entry automatically.

### Releases

- Fedora and Ubuntu image releases contain compressed installable images.
- Gaokun RPM and DEB releases contain the standalone kernel and firmware package sets used by the image workflows.

### Patch Sources

- `upstream/*` and `others/0006`: adapted from [right-0903/linux-gaokun](https://github.com/right-0903/linux-gaokun) for the base SC8280XP / gaokun3 enablement, display bring-up, EC suspend/resume, and DSI stability work
- `others/0001`: adapted from [whitelewi1-ctrl/matebook-e-go-linux](https://github.com/whitelewi1-ctrl/matebook-e-go-linux) to avoid setting `USE_BDADDR_PROPERTY` when the adapter address is invalid
- `others/0002`: local change in this repository to enable DSC and allow 60 Hz / 120 Hz switching
- `others/0003`: adapted from [chiyuki0325/EGoTouchRev-Linux](https://github.com/chiyuki0325/EGoTouchRev-Linux) to add the Himax HX83121A SPI touchscreen driver
- `others/0004`: local change in this repository to fix DPU video timing width truncation when DSC is enabled
- `others/0005`: adapted from [right-0903/linux-gaokun](https://github.com/right-0903/linux-gaokun) to add backlight regulator supply for the HX83121A panel driver
- `others/0007`: local change in this repository; on cold boot the EC UCSI PPM may stay half-responsive for a long time, so registration is retried 10 times at 5s and then backed off to 30s/60s for a ~30 minute window, preventing Type-C from being permanently unusable for the boot session
- `others/0008`, `others/0009`: Pengyu Luo's upstream submission making the touchscreen QUP-SPI honor `qcom,force-gsi-mode` (GSI/DMA instead of word-by-word FIFO; the DTS already carries the property but the v7.2.5 driver ignores it), carried via [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun); [mailing list](https://lore.kernel.org/linux-arm-msm/20260614083424.464132-1-mitltlatltl@gmail.com)
- `others/0010`: from [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun) to expose GPU utilization/memory/clock/temperature telemetry nodes from the msm DRM driver for system monitors
- `media/*`: adapted from the [jhovold/linux](https://github.com/jhovold/linux/commits/wip/sc8280xp-6.16) to add SC8280XP Venus support
- `0099`: local patch in this repository to import the current DTS files and `gaokun3_defconfig`
- `0100`: from [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun); the Himax HX83121A cascade IC selects its host interface via the TLMM gpio174 level, which the boot firmware leaves high (I2C-HID mode, SPI path silent) — the board DTS now describes it as a low output so the IC latches SPI mode before the touch firmware reload. **Must be applied after `0099`** (see `scripts/ci/20_build_kernel_variants.sh`)
- **[Optional]** `el2/*`: adapted from [TravMurav/linux](https://github.com/TravMurav/linux/tree/x13s-6.18-v1.1-cxsd) for the EL2 boot path, including SMP2P handover, remoteproc attach/restart flow, SCM/SHM owner handling, and related rpmsg/QRTR/pmic_glink stability fixes

### Tool Sources

- `tools/audio`, `tools/bluetooth`: adapted from [whitelewi1-ctrl/matebook-e-go-linux](https://github.com/whitelewi1-ctrl/matebook-e-go-linux)
- `tools/el2/qebspilaa64.efi`: sourced from [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil)
- `tools/el2/slbounceaa64.efi`: sourced from [TravMurav/slbounce](https://github.com/TravMurav/slbounce)
- `tools/touchscreen-tuner`: adapted from [chiyuki0325/EGoTouchRev-Linux](https://github.com/chiyuki0325/EGoTouchRev-Linux), with GTK4 GUI improvements in this repository
- `tools/touch-bench/gk-touch-bench.py`: from [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun), a touch path benchmark (report rate / frame intervals / IRQ efficiency)

## Boot artifact layout

The image and local-install workflows now follow the standard `kernel-install` + BLS flow instead of hand-writing `systemd-boot` entries.

- BLS entry names and entry directories are generated by `kernel-install`. With the default `--entry-token=machine-id`, filenames are tied to `/etc/machine-id`, e.g. `loader/entries/<machine-id>-<kernel-release>.conf`.
- Kernel, initrd/initramfs, and DTB files copied into the ESP are also placed under the matching `<entry-token>/<kernel-release>/` directory automatically by the distro hook.
- A compatibility copy of the DTB is also kept in `/boot` so users can switch to GRUB more easily later.
- Ubuntu DTBs are installed in `/usr/lib/linux-image-<kernel-release>/qcom/` for `kernel-install`, plus `/boot/dtb-<kernel-release>` as a compatibility copy.
- Fedora DTBs are installed in `/usr/lib/modules/<kernel-release>/dtb/qcom/` for `kernel-install`, plus `/boot/dtb-<kernel-release>/qcom/` as a compatibility copy.
- The Gaokun3 image scripts provide `/etc/kernel/cmdline` and `/etc/kernel/devicetree`, then call `kernel-install add` to populate the final BLS entry.

## Getting started

- Release: <https://github.com/KawaiiHachimi/linux-gaokun-build/releases>
- Platform notes – device variants & capability boundaries: [English](docs/platform_notes_en.md) | [中文](docs/platform_notes_zh.md)
- Dual-boot guide: [English](docs/dual_boot_guide_en.md) | [中文](docs/dual_boot_guide_zh.md)
- EL2 implementation notes: [English](docs/el2_kvm_guide_en.md) | [中文](docs/el2_kvm_guide_zh.md)
- Awesome Gaokun3: [English](docs/awesome_gaokun3_en.md) | [中文](docs/awesome_gaokun3_zh.md)
- Build guide – Fedora 44: [English](docs/matebook_ego_build_guide_fedora44_en.md) | [中文](docs/matebook_ego_build_guide_fedora44_zh.md)
- Build guide – Ubuntu 26.04: [English](docs/matebook_ego_build_guide_ubuntu26.04_en.md) | [中文](docs/matebook_ego_build_guide_ubuntu26.04_zh.md)

## Feature Support

For an overview of hardware support status on the device, see [right-0903/linux-gaokun `## Feature Support`](https://github.com/right-0903/linux-gaokun?tab=readme-ov-file#feature-support).

## References

- [right-0903/linux-gaokun](https://github.com/right-0903/linux-gaokun) : The main source of the kernel patches and device support work, with detailed commit messages and explanations.
- [TheUnknownThing/linux-gaokun](https://github.com/TheUnknownThing/linux-gaokun) : Another fork of the kernel patches and device support work, with some unique commits and explanations for Touchscreen and EC.
- [whitelewi1-ctrl/matebook-e-go-linux](https://github.com/whitelewi1-ctrl/matebook-e-go-linux) : The earliest repo to fix panel backlight problem, with some additional resources and modifications for Gaokun3 Linux support.
- [gaokun on AUR](https://aur.archlinux.org/packages?O=0&K=gaokun) : Several AUR packages built for Gaokun3, including kernel and firmware packages.
- [chenxuecong2/firmware-huawei-gaokun3](https://github.com/chenxuecong2/firmware-huawei-gaokun3) : A firmware bundle repository for Gaokun3.
- [chiyuki0325/EGoTouchRev-Linux](https://github.com/chiyuki0325/EGoTouchRev-Linux) : The upstream source for the directly integrated Himax HX83121A Linux touchscreen driver and tuning algorithm in this repository.
- [awarson2233/EGoTouchRev](https://github.com/awarson2233/EGoTouchRev) : The original Windows-side touchscreen algorithm project referenced by EGoTouchRev-Linux, and an important upstream reference for the Gaokun3 touchscreen tuning pipeline.
- [TravMurav/slbounce](https://github.com/TravMurav/slbounce) : A UEFI application that enables EL2 support and Secure Launch on Gaokun3.
- [TravMurav/linux](https://github.com/TravMurav/linux/tree/x13s-6.18-v1.1-cxsd) : A Linux kernel tree with some useful patches for EL2 support on sc8280xp platforms.
- [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil) : A UEFI application that pre-launches the DSP firmware on Qualcomm platforms, which can be used in the boot chain before launching Linux.
- [aoripus/easy-for-gaokun](https://github.com/aoripus/easy-for-gaokun) : A deep-adaptation repository for the MateBook E Go 2022 Performance Edition (GK-W76), built on this project's images; the touchscreen interface-mode fix, SPI GSI patches, GPU telemetry patch, and the audio/fingerprint/video-decode forensics all come from there.
