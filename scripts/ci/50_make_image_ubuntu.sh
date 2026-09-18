#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/lib/common_image.sh"

: "${GAOKUN_DIR:?missing GAOKUN_DIR}"
: "${WORKDIR:?missing WORKDIR}"
: "${ROOTFS_DIR:?missing ROOTFS_DIR}"
: "${ARTIFACT_DIR:?missing ARTIFACT_DIR}"
: "${IMAGE_FILE:?missing IMAGE_FILE}"
: "${IMAGE_SIZE:?missing IMAGE_SIZE}"
: "${UBUNTU_RELEASE:?missing UBUNTU_RELEASE}"

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
parted -s "$IMAGE_FILE" mkpart rootfs ext4 "${EFI_END_MIB}MiB" 100%

LOOP="$(sudo losetup --show -fP "$IMAGE_FILE")"
sudo mkfs.vfat -F32 -n EFI "${LOOP}p1"
sudo mkfs.ext4 -L rootfs "${LOOP}p2"

EFI_UUID="$(sudo blkid -s UUID -o value "${LOOP}p1")"
ROOT_UUID="$(sudo blkid -s UUID -o value "${LOOP}p2")"

MNT=/mnt/ego-ubuntu
cleanup() {
  set +e
  sudo umount "$MNT/dev/pts" 2>/dev/null || true
  sudo umount "$MNT/boot/efi" 2>/dev/null || true
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
sudo mkdir -p "$MNT/boot/efi"
sudo mount "${LOOP}p1" "$MNT/boot/efi"

# --chown=root:root：rsync -a 会把源根目录的属主带到镜像 / 上（CI 里 ROOTFS_DIR 属于 runner 用户）
sudo rsync -aHAX --chown=root:root --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' "$ROOTFS_DIR/" "$MNT/"
install_common_image_assets "$MNT" "$GAOKUN_DIR"

sudo tee "$MNT/etc/fstab" >/dev/null <<EOF
UUID=${ROOT_UUID}  /         ext4   errors=remount-ro,noatime  0  1
UUID=${EFI_UUID}   /boot/efi vfat   defaults,nofail,x-systemd.device-timeout=10s  0  2
EOF

sudo mount --bind /dev "$MNT/dev"
sudo mount --bind /dev/pts "$MNT/dev/pts"
sudo mount -t proc proc "$MNT/proc"
sudo mount -t sysfs sys "$MNT/sys"
sudo mount -t tmpfs tmpfs "$MNT/run"

sudo chroot "$MNT" /usr/bin/env KREL="$KREL" KREL_EL2="$KREL_EL2" BUILD_EL2="$BUILD_EL2" ROOT_UUID="$ROOT_UUID" /bin/bash -euxo pipefail <<'CHROOT_EOF'
echo "ubuntu" > /etc/hostname
id -u user >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo user
echo "user:user" | chpasswd
mkdir -p /etc/sudoers.d
echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sudo-nopasswd
chmod 440 /etc/sudoers.d/sudo-nopasswd
cat > /etc/default/locale <<'EOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:en_US:en
LC_MESSAGES=zh_CN.UTF-8
EOF

rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

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

# 预置 user 级输入源（与系统级 dconf 默认完全一致）：
# 首次登录的 gnome-initial-setup（--existing-user）键盘页会按 zh_CN locale
# 再写一份 user 级输入源，与系统级默认叠加后出现重复的「智能拼音」；
# 显式预置后，所有「未配置则按 locale 自动追加输入源」的逻辑都会跳过。
_user_kf_dir=$(mktemp -d)
cat > "$_user_kf_dir/00-input-sources" <<'INPUT_SOURCES_EOF'
[org/gnome/desktop/input-sources]
current=uint32 0
sources=[('xkb', 'us'), ('ibus', 'libpinyin')]
xkb-options=@as []
INPUT_SOURCES_EOF
install -d -m 0755 /home/user/.config/dconf
dconf compile /home/user/.config/dconf/user "$_user_kf_dir"
rm -rf "$_user_kf_dir"

# 预置「已完成初始设置」标记，跳过首次登录的 gnome-initial-setup：
# marker 路径对应 gnome-initial-setup-first-login.service 的
# ConditionPathExists=!%E/gnome-initial-setup-done（%E 即 ~/.config）
install -D -m 0644 /dev/null /home/user/.config/gnome-initial-setup-done

chown -R user:user /home/user

install -d -m 1777 -o root -g root /tmp/.X11-unix

# GDM 登录默认要求密码验证（安全默认）。
# 如需平板形态/补丁测试场景免密登录，取消注释下面两行 AutomaticLogin 即可
cat > /etc/gdm3/custom.conf <<'EOF'
[daemon]
#AutomaticLoginEnable=True
#AutomaticLogin=user
EOF

cat > /etc/systemd/system/gaokun-fix-x11-unix.service <<'EOF'
[Unit]
Description=Fix /tmp/.X11-unix ownership for Xwayland
After=gdm.service
Wants=gdm.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'mkdir -p /tmp/.X11-unix && chown root:root /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix'

[Install]
WantedBy=graphical.target
EOF

systemctl enable gdm NetworkManager ssh \
  gaokun-fix-x11-unix.service gdm-monitor-sync.service \
  gaokun-grow-rootfs.service patch-nvm-bdaddr.service || true

# 平板桌面场景没有需要等网络的本机服务/mount，wait-online 在 Wi-Fi 下白等 7s+，禁用之
systemctl disable NetworkManager-wait-online.service || true

# 编译 system-db:local（screen-keyboard-enabled / 输入源默认值）进 dconf 数据库
# dconf 由 dconf-cli 提供（构建时已显式安装）；缺失直接失败，避免屏幕键盘等默认值静默丢失
# 中文输入走 GNOME 原生 ibus + libpinyin（屏幕键盘依赖 Shell 的 ibus/text-input 链路，fcitx5 会使其失效）
command -v dconf >/dev/null 2>&1 || { echo "ERROR: dconf not available in chroot (install dconf-cli)" >&2; exit 1; }
dconf update

# 构建期冒烟测试：完整走一遍「软件更新器」(update-manager) 的启动导入链
# （gi/Handy → uaclient(ubuntu-pro-client) → UbuntuDrivers → DistUpgrade）。
# 26.04 开发期 update-manager 与 python3-distupgrade 版本错配会导致启动即
# ImportError（LP: #2141637）；任何依赖缺失也会点击即崩。
# 在这里失败远好过装出一个「软件更新器点开就报错」的镜像。
if [ -e /usr/bin/update-manager ]; then
  python3 -c "import gi; gi.require_version('Gdk', '3.0'); gi.require_version('Gtk', '3.0'); gi.require_version('Handy', '1'); from gi.repository import Gtk, Handy; from UpdateManager.UpdateManager import UpdateManager; from UpdateManager.Core.utils import init_proxy; import UpdateManager.UpdatesAvailable"
fi

# 时区：中国区默认 Asia/Shanghai（chroot 内 timedatectl 不可用，用符号链接 + tz 文件）
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
cat > /etc/timezone <<'EOF'
Asia/Shanghai
EOF

cat >> /etc/initramfs-tools/modules <<'MODEOF'
# Storage and USB
nvme
phy-qcom-qmp-pcie
phy-qcom-qmp-combo
phy-qcom-qmp-usb
phy-qcom-snps-femto-v2
usb-storage
uas
typec
# WiFi
pci-pwrctrl-pwrseq
ath11k
ath11k_pci
# Input
i2c-hid-of
MODEOF

# initramfs 固件拷贝 hook 由 linux-firmware-gaokun3 DEB 打包安装
# （packaging/deb/linux-firmware-gaokun3/hooks/initramfs-hook.in），
# 这里不再重复落盘，避免两份内容日后漂移互相覆盖

install -d /etc/kernel
cat > /etc/kernel/install.conf <<'EOF'
layout=bls
EOF

# 参数分组（bring-up 历史遗留，无硬件逐项验证前不擅自摘除）：
#   root=UUID                              根分区
#   clk_ignore_unused pd_ignore_unused     【续航相关, 稳定后优先摘除实验】
#                                          禁止关未被消费者持有的时钟/电源域，SC8280XP 早期
#                                          DTS 资源不完整时防外设挂死；代价是静态功耗增加
#   arm64.nopauth                          关闭指针认证（早期固件/兼容性 workaround）
#   iommu.passthrough=0 iommu.strict=0     启用 DMA 映射但用 lazy 模式（性能/安全折中）
#   pcie_aspm.policy=powersupersave        NVMe/WiFi 链路省电
#   modprobe.blacklist=simpledrm           避免 simpledrm 与 msm/msmgfx 争显
#   efi=noruntime                          UEFI Runtime Services 不稳定，禁用
#   fbcon=rotate:1                         竖屏 TTY
#   usbcore.autosuspend=-1                 【续航相关, 稳定后优先摘除实验】
#                                          全局关闭 USB 自动休眠；0x12d1:0x10b8(华为 EC/HID)
#                                          行为不标准(另需 NO_INIT_REPORTS quirk)，其 resume
#                                          路径同样可疑，摘掉可能导致 USB 唤醒后失灵
#   usbhid.quirks=...:0x20000000           HID_QUIRK_NO_INIT_REPORTS，华为 EC 启动不报点
#   consoleblank=0 loglevel=4 psi=1        控制台/日志/PSI
cat > /etc/kernel/cmdline <<EOF
root=UUID=$ROOT_UUID clk_ignore_unused pd_ignore_unused arm64.nopauth iommu.passthrough=0 iommu.strict=0 pcie_aspm.policy=powersupersave modprobe.blacklist=simpledrm efi=noruntime fbcon=rotate:1 usbcore.autosuspend=-1 usbhid.quirks=0x12d1:0x10b8:0x20000000 consoleblank=0 loglevel=4 psi=1
EOF

# /etc/kernel/{install.conf,cmdline,devicetree} 就是 kernel-install 的默认配置位置：
# 按内核变体切换 devicetree 后，update-initramfs 与 kernel-install 依次复用，
# 无需再为每次 kernel-install 构造临时 KERNEL_INSTALL_CONF_ROOT 目录
install_kernel_variant() {
  local krel="$1"
  local dtb="$2"

  printf 'qcom/%s\n' "$dtb" > /etc/kernel/devicetree
  update-initramfs -c -k "$krel"
  kernel-install --entry-token=machine-id remove "$krel" || true
  kernel-install --verbose --make-entry-directory=yes --entry-token=machine-id add \
    "$krel" "/boot/vmlinuz-$krel" "/boot/initrd.img-$krel"
}

rm -f /etc/machine-id
systemd-machine-id-setup
MACHINE_ID="$(cat /etc/machine-id)"

bootctl --no-variables --esp-path=/boot/efi install

install_kernel_variant "$KREL" "sc8280xp-huawei-gaokun3.dtb"
if [[ "$BUILD_EL2" == "true" && -n "$KREL_EL2" ]]; then
  install_kernel_variant "$KREL_EL2" "sc8280xp-huawei-gaokun3-el2.dtb"
  # 上面的 el2 安装会把 /etc/kernel/devicetree 留在 el2 值上，恢复为 standard：
  # 默认启动项是 standard，设备上手工 kernel-install 也应默认用 standard DTB；
  # el2 包 postinst 安装时会临时写入 el2 DTB 并自行恢复，不依赖该持久值
  printf 'qcom/sc8280xp-huawei-gaokun3.dtb\n' > /etc/kernel/devicetree
fi

cat > /boot/efi/loader/loader.conf <<EOF
# 通配所有 standard gaokun3 条目（不含 -gaokun3-el2）：systemd-boot 对多匹配按版本排序，
# 自动选择最高版本，设备上 dpkg 升级新内核后无需再手工改 default
default *-gaokun3.conf
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
