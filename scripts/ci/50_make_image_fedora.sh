#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/common_image.sh"

: "${GAOKUN_DIR:?missing GAOKUN_DIR}"
: "${WORKDIR:?missing WORKDIR}"
: "${ROOTFS_DIR:?missing ROOTFS_DIR}"
: "${ARTIFACT_DIR:?missing ARTIFACT_DIR}"
: "${IMAGE_FILE:?missing IMAGE_FILE}"
: "${IMAGE_SIZE:?missing IMAGE_SIZE}"
: "${FEDORA_RELEASE:?missing FEDORA_RELEASE}"

BUILD_EL2="${BUILD_EL2:-false}"
KREL="$(cat "$WORKDIR/kernel-release.txt")"
KREL_EL2=""
if [[ "$BUILD_EL2" == "true" && -f "$WORKDIR/kernel-release-el2.txt" ]]; then
  KREL_EL2="$(cat "$WORKDIR/kernel-release-el2.txt")"
fi

EFI_END_MIB=1025
truncate -s "$IMAGE_SIZE" "$IMAGE_FILE"
parted -s "$IMAGE_FILE" mklabel gpt
parted -s "$IMAGE_FILE" mkpart EFI fat32 1MiB "${EFI_END_MIB}MiB"
parted -s "$IMAGE_FILE" set 1 esp on
parted -s "$IMAGE_FILE" mkpart rootfs btrfs "${EFI_END_MIB}MiB" 100%

LOOP="$(sudo losetup --show -fP "$IMAGE_FILE")"
sudo mkfs.vfat -F32 -n EFI "${LOOP}p1"
sudo mkfs.btrfs -f -L rootfs "${LOOP}p2"

EFI_UUID="$(sudo blkid -s UUID -o value "${LOOP}p1")"
ROOT_UUID="$(sudo blkid -s UUID -o value "${LOOP}p2")"

MNT=/mnt/ego-fedora
cleanup() {
  set +e
  sudo umount "$MNT/dev/pts" 2>/dev/null || true
  sudo umount "$MNT/boot/efi" 2>/dev/null || true
  sudo umount "$MNT/var" 2>/dev/null || true
  sudo umount "$MNT/home" 2>/dev/null || true
  sudo umount "$MNT/dev" 2>/dev/null || true
  sudo umount "$MNT/proc" 2>/dev/null || true
  sudo umount "$MNT/sys" 2>/dev/null || true
  sudo umount "$MNT/run" 2>/dev/null || true
  sudo umount "$MNT" 2>/dev/null || true
  sudo losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

sudo mkdir -p "$MNT"
sudo mount "${LOOP}p2" "$MNT"
sudo btrfs subvolume create "$MNT/@"
sudo btrfs subvolume create "$MNT/@home"
sudo btrfs subvolume create "$MNT/@var"
sudo umount "$MNT"
sudo mount -o subvol=@ "${LOOP}p2" "$MNT"
sudo mkdir -p "$MNT/home"
sudo mount -o subvol=@home "${LOOP}p2" "$MNT/home"
sudo mkdir -p "$MNT/var"
sudo mount -o subvol=@var "${LOOP}p2" "$MNT/var"
sudo mkdir -p "$MNT/boot/efi"
sudo mount "${LOOP}p1" "$MNT/boot/efi"

# --chown=root:root：rsync -a 会把源根目录的属主带到镜像 / 上（CI 里 ROOTFS_DIR 属于 runner 用户）
sudo rsync -aHAX --chown=root:root "$ROOTFS_DIR/" "$MNT/"
install_common_image_assets "$MNT" "$GAOKUN_DIR"

sudo tee "$MNT/etc/fstab" >/dev/null <<EOF
UUID=${ROOT_UUID}  /         btrfs  subvol=@,compress=zstd:1,ssd,noatime  0  0
UUID=${ROOT_UUID}  /home     btrfs  subvol=@home,compress=zstd:1,ssd,noatime  0  0
UUID=${ROOT_UUID}  /var      btrfs  subvol=@var,compress=zstd:1,ssd,noatime  0  0
UUID=${EFI_UUID}   /boot/efi vfat   defaults,nofail,x-systemd.device-timeout=10s  0  2
EOF

sudo mount --bind /dev "$MNT/dev"
sudo mount --bind /dev/pts "$MNT/dev/pts"
sudo mount -t proc proc "$MNT/proc"
sudo mount -t sysfs sys "$MNT/sys"
sudo mount -t tmpfs tmpfs "$MNT/run"

sudo chroot "$MNT" /usr/bin/env KREL="$KREL" KREL_EL2="$KREL_EL2" BUILD_EL2="$BUILD_EL2" ROOT_UUID="$ROOT_UUID" /bin/bash -euxo pipefail <<'CHROOT_EOF'
echo "fedora" > /etc/hostname
id -u user >/dev/null 2>&1 || useradd -m -s /bin/bash -G wheel user
echo "user:user" | chpasswd
mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/wheel-nopasswd
chmod 440 /etc/sudoers.d/wheel-nopasswd
cat > /etc/locale.conf <<'EOF'
LANG=zh_CN.UTF-8
LC_MESSAGES=zh_CN.UTF-8
EOF

mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/user <<'EOF'
[User]
Language=zh_CN.UTF-8
EOF
cat > /var/lib/AccountsService/users/gdm <<'EOF'
[User]
Language=zh_CN.UTF-8
SystemAccount=true
EOF

install -d -m 0755 /home/user/.config
install -Dm644 /usr/local/share/gaokun/monitors.xml /home/user/.config/monitors.xml
chown -R user:user /home/user

# GDM 自动登录：平板形态 + 补丁测试场景（触屏失效时无需键盘输密码）
# 如需关闭，注释掉下面两行 AutomaticLogin 即可
cat > /etc/gdm/custom.conf <<'EOF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=user
EOF

systemctl enable gdm NetworkManager sshd \
  gdm-monitor-sync.service gaokun-grow-rootfs.service \
  patch-nvm-bdaddr.service || true

# 平板桌面场景没有需要等网络的本机服务/mount，wait-online 在 Wi-Fi 下白等 7s+，禁用之
systemctl disable NetworkManager-wait-online.service || true

# 编译 system-db:local（screen-keyboard-enabled 等镜像默认值）进 dconf 数据库
# dconf 由 dconf 包提供（构建时已显式安装）；缺失直接失败，避免屏幕键盘等默认值静默丢失
command -v dconf >/dev/null 2>&1 || { echo "ERROR: dconf not available in chroot (install dconf)" >&2; exit 1; }
dconf update

# 双击 .rpm 用 GNOME Software 打开
if [[ -f /usr/share/applications/org.gnome.Software.desktop ]]; then
  install -d -m 0755 /etc/xdg
  printf '[Default Applications]\napplication/x-rpm=org.gnome.Software.desktop\n' > /etc/xdg/mimeapps.list
fi

# 时区：中国区默认 Asia/Shanghai（chroot 内 timedatectl 不可用，用符号链接；
# /etc/timezone 是 Debian 系专属文件，Fedora 不读取，无需写入）
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

cat > /etc/dracut.conf.d/matebook.conf <<'MODEOF'
hostonly="no"
add_drivers+=" btrfs nvme phy-qcom-qmp-pcie phy-qcom-qmp-combo phy-qcom-qmp-usb phy-qcom-snps-femto-v2 usb-storage uas typec pci-pwrctrl-pwrseq ath11k ath11k_pci i2c-hid-of "
MODEOF

install -d /etc/kernel
cat > /etc/kernel/install.conf <<'EOF'
layout=bls
EOF

install -d /etc/kernel/install.d
ln -sf /dev/null /etc/kernel/install.d/51-dracut-rescue.install

cat > /etc/kernel/cmdline <<EOF
root=UUID=$ROOT_UUID rootflags=subvol=@ clk_ignore_unused pd_ignore_unused arm64.nopauth iommu.passthrough=0 iommu.strict=0 pcie_aspm.policy=powersupersave efi=noruntime fbcon=rotate:1 usbcore.autosuspend=-1 usbhid.quirks=0x12d1:0x10b8:0x20000000 consoleblank=0 loglevel=4 psi=1
EOF

cat > /etc/kernel/devicetree <<'EOF'
qcom/sc8280xp-huawei-gaokun3.dtb
EOF

dracut --force --kver "$KREL"
if [[ "$BUILD_EL2" == "true" && -n "$KREL_EL2" ]]; then
  dracut --force --kver "$KREL_EL2"
fi

rm -f /etc/machine-id
systemd-machine-id-setup
MACHINE_ID="$(cat /etc/machine-id)"

bootctl --no-variables --esp-path=/boot/efi install

run_kernel_install() {
  local krel="$1"
  local image="$2"
  local dtb="$3"
  local cmdline="$4"
  local conf_root

  conf_root="$(mktemp -d)"
  cat > "$conf_root/install.conf" <<'EOF'
layout=bls
EOF
  printf '%s\n' "$cmdline" > "$conf_root/cmdline"
  printf 'qcom/%s\n' "$dtb" > "$conf_root/devicetree"

  kernel-install --entry-token=machine-id remove "$krel" || true
  KERNEL_INSTALL_CONF_ROOT="$conf_root" \
    kernel-install --verbose --make-entry-directory=yes --entry-token=machine-id add \
    "$krel" "$image"
  rm -rf "$conf_root"
}

BASE_CMDLINE="$(cat /etc/kernel/cmdline)"
run_kernel_install \
  "$KREL" \
  "/boot/vmlinuz-$KREL" \
  "sc8280xp-huawei-gaokun3.dtb" \
  "$BASE_CMDLINE"

if [[ "$BUILD_EL2" == "true" && -n "$KREL_EL2" ]]; then
  EL2_CMDLINE="${BASE_CMDLINE} modprobe.blacklist=simpledrm"
  run_kernel_install \
    "$KREL_EL2" \
    "/boot/vmlinuz-$KREL_EL2" \
    "sc8280xp-huawei-gaokun3-el2.dtb" \
    "$EL2_CMDLINE"
fi

cat > /boot/efi/loader/loader.conf <<EOF
default ${MACHINE_ID}-${KREL}.conf
timeout 5
console-mode keep
editor no
EOF
CHROOT_EOF

if [[ "$BUILD_EL2" == "true" && -n "$KREL_EL2" ]]; then
  install_el2_efi_payloads "$MNT" "$GAOKUN_DIR"
fi

sync

trap - EXIT
cleanup
