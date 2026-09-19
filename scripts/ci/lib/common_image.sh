#!/usr/bin/env bash
set -euo pipefail

install_common_image_assets() {
  local rootfs_dir="$1"
  local gaokun_dir="$2"
  local executable_assets=(
    "tools/bluetooth/patch-nvm-bdaddr.py:/usr/local/bin/patch-nvm-bdaddr.py"
    "tools/monitors/gdm-monitor-sync:/usr/local/bin/gdm-monitor-sync"
    "tools/touchscreen-tuner/touchscreen-tune:/usr/local/bin/touchscreen-tune"
    "tools/hwcheck/gaokun-check:/usr/local/bin/gaokun-check"
    "tools/growroot/gaokun-grow-rootfs:/usr/local/bin/gaokun-grow-rootfs"
    "tools/installer/gaokun-install:/usr/local/bin/gaokun-install"
  )
  local service_assets=(
    "tools/bluetooth/patch-nvm-bdaddr.service:/etc/systemd/system/patch-nvm-bdaddr.service"
    "tools/monitors/gdm-monitor-sync.service:/etc/systemd/system/gdm-monitor-sync.service"
    "tools/growroot/gaokun-grow-rootfs.service:/etc/systemd/system/gaokun-grow-rootfs.service"
  )
  local data_assets=(
    "tools/audio/sc8280xp.conf:/usr/share/alsa/ucm2/Qualcomm/sc8280xp/sc8280xp.conf"
    "tools/touchscreen-tuner/tune.py:/usr/local/lib/gaokun-touchscreen-tuner/tune.py"
    "tools/touchscreen-tuner/tune-icon.svg:/usr/local/lib/gaokun-touchscreen-tuner/tune-icon.svg"
    "tools/touchscreen-tuner/touchscreen-tune.desktop:/usr/share/applications/touchscreen-tune.desktop"
    "tools/image-assets/usr/local/share/gaokun/monitors.xml:/usr/local/share/gaokun/monitors.xml"
    "tools/image-assets/etc/systemd/zram-generator.conf:/etc/systemd/zram-generator.conf"
    "tools/image-assets/etc/systemd/journald.conf.d/90-gaokun.conf:/etc/systemd/journald.conf.d/90-gaokun.conf"
    "tools/installer/gaokun-install.desktop:/usr/share/applications/gaokun-install.desktop"
    # 屏蔽 Lenovo X13s 启用包, 防止软件更新器把它们连带一串依赖装到 gaokun3 上
    "tools/image-assets/etc/apt/preferences.d/no-lenovo-x13s:/etc/apt/preferences.d/no-lenovo-x13s"
  )
  local asset src dest

  sudo mkdir -p \
    "$rootfs_dir/etc/modules-load.d" \
    "$rootfs_dir/etc/modprobe.d" \
    "$rootfs_dir/etc/apt/preferences.d" \
    "$rootfs_dir/etc/dconf/db/local.d" \
    "$rootfs_dir/etc/dconf/profile" \
    "$rootfs_dir/etc/udev/rules.d" \
    "$rootfs_dir/etc/systemd/system" \
    "$rootfs_dir/etc/gaokun" \
    "$rootfs_dir/usr/local/bin" \
    "$rootfs_dir/usr/local/lib/gaokun-touchscreen-tuner" \
    "$rootfs_dir/usr/share/alsa/ucm2/Qualcomm/sc8280xp" \
    "$rootfs_dir/usr/share/applications" \
    "$rootfs_dir/usr/local/share/gaokun"

  # --no-preserve=ownership：仓库检出目录属于 CI runner 用户，直接 cp -a 会把该 uid 带进镜像
  sudo cp -a --no-preserve=ownership "$gaokun_dir/tools/image-assets/etc/modules-load.d/." \
    "$rootfs_dir/etc/modules-load.d/"
  sudo cp -a --no-preserve=ownership "$gaokun_dir/tools/image-assets/etc/modprobe.d/." \
    "$rootfs_dir/etc/modprobe.d/"
  sudo cp -a --no-preserve=ownership "$gaokun_dir/tools/image-assets/etc/dconf/db/local.d/." \
    "$rootfs_dir/etc/dconf/db/local.d/"
  # dconf 默认 profile：不装这个文件 dconf 找不到 system-db:local，
  # screen-keyboard-enabled / 输入源等镜像默认值全部静默失效（已在线上踩过）
  sudo cp -a --no-preserve=ownership "$gaokun_dir/tools/image-assets/etc/dconf/profile/." \
    "$rootfs_dir/etc/dconf/profile/"

  for asset in "${executable_assets[@]}"; do
    src="${asset%%:*}"
    dest="${asset#*:}"
    sudo install -Dm755 "$gaokun_dir/$src" "$rootfs_dir$dest"
  done

  for asset in "${service_assets[@]}"; do
    src="${asset%%:*}"
    dest="${asset#*:}"
    sudo install -Dm644 "$gaokun_dir/$src" "$rootfs_dir$dest"
  done

  for asset in "${data_assets[@]}"; do
    src="${asset%%:*}"
    dest="${asset#*:}"
    sudo install -Dm644 "$gaokun_dir/$src" "$rootfs_dir$dest"
  done
}

install_el2_efi_payloads() {
  local rootfs_dir="$1"
  local gaokun_dir="$2"

  sudo install -d \
    "$rootfs_dir/boot/efi/EFI/systemd/drivers" \
    "$rootfs_dir/boot/efi/firmware"

  sudo install -Dm644 "$gaokun_dir/tools/el2/slbounceaa64.efi" \
    "$rootfs_dir/boot/efi/EFI/systemd/drivers/slbounceaa64.efi"
  sudo install -Dm644 "$gaokun_dir/tools/el2/qebspilaa64.efi" \
    "$rootfs_dir/boot/efi/EFI/systemd/drivers/qebspilaa64.efi"
  sudo install -Dm644 "$gaokun_dir/tools/el2/tcblaunch.exe" \
    "$rootfs_dir/boot/efi/tcblaunch.exe"
  sudo install -Dm644 "$rootfs_dir/lib/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcadsp8280.mbn" \
    "$rootfs_dir/boot/efi/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcadsp8280.mbn"
  sudo install -Dm644 "$rootfs_dir/lib/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qccdsp8280.mbn" \
    "$rootfs_dir/boot/efi/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qccdsp8280.mbn"
  sudo install -Dm644 "$rootfs_dir/lib/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcslpi8280.mbn" \
    "$rootfs_dir/boot/efi/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcslpi8280.mbn"
}
