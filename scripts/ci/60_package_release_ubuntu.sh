#!/usr/bin/env bash
set -euo pipefail

: "${WORKDIR:?missing WORKDIR}"
: "${ARTIFACT_DIR:?missing ARTIFACT_DIR}"
: "${IMAGE_FILE:?missing IMAGE_FILE}"
: "${IMAGE_CHUNK_SIZE:?missing IMAGE_CHUNK_SIZE}"
: "${UBUNTU_RELEASE:?missing UBUNTU_RELEASE}"
: "${KERNEL_TAG:?missing KERNEL_TAG}"
: "${DESKTOP_ENVIRONMENT:?missing DESKTOP_ENVIRONMENT}"
: "${EXTRA_PACKAGES:?missing EXTRA_PACKAGES}"

KREL="$(cat "$WORKDIR/kernel-release.txt")"
BUILD_EL2="${BUILD_EL2:-false}"
EL2_KREL=""
if [[ "$BUILD_EL2" == "true" && -f "$WORKDIR/kernel-release-el2.txt" ]]; then
  EL2_KREL="$(cat "$WORKDIR/kernel-release-el2.txt")"
fi
IMAGE_BASENAME="$(basename "$IMAGE_FILE")"
ZST_FILE="$ARTIFACT_DIR/${IMAGE_BASENAME}.zst"
RELEASE_BODY_FILE="$ARTIFACT_DIR/release-body.md"
SPLIT_THRESHOLD_BYTES=$((2 * 1024 * 1024 * 1024))
EL2_RELEASE_BLOCK=""
EL2_LOGIN_BLOCK=""
if [[ "$BUILD_EL2" == "true" && -n "$EL2_KREL" ]]; then
  EL2_RELEASE_BLOCK="$(cat <<EOF
- Optional EL2 Kernel Release: \`${EL2_KREL}\`
EOF
)"
  EL2_LOGIN_BLOCK="## EL2 Payload

- Includes systemd-boot EL2 menu entry
- Includes \`slbounceaa64.efi\`, \`qebspilaa64.efi\`, \`tcblaunch.exe\`, and the three DSP firmware blobs in ESP \`/firmware/qcom/sc8280xp/HUAWEI/gaokun3/\`

"
fi

# 压缩级别可调：-19 极慢，-15 压缩率基本持平、速度快约一倍
# 原始 img 不随发布上传（只上传 .zst / 分卷），直接从 IMAGE_FILE 压缩，省一次整盘拷贝
ZSTD_LEVEL="${ZSTD_LEVEL:-19}"
zstd -T0 "-${ZSTD_LEVEL}" "$IMAGE_FILE" -o "$ZST_FILE"

# 公共发布说明先写一份，超过 2GB 再追加分卷重组说明
cat > "$RELEASE_BODY_FILE" <<EOF
## Build Information

- Distribution: \`Ubuntu ${UBUNTU_RELEASE}\`
- Kernel Tag: \`${KERNEL_TAG}\`
- Kernel Release: \`${KREL}\`
- Architecture: \`arm64\`
${EL2_RELEASE_BLOCK}
- Root Filesystem: \`ext4\`
- Bootloader: \`systemd-boot\`
- Image File: \`${IMAGE_BASENAME}\`
- Compressed File: \`${IMAGE_BASENAME}.zst\`
- Build Time (UTC): \`$(date -u +"%Y-%m-%dT%H:%M:%SZ")\`

## Rootfs Selection

- Desktop Environment: \`${DESKTOP_ENVIRONMENT}\`
- Extra Packages: \`${EXTRA_PACKAGES}\`

## Default Login

- Username: \`user\`
- Password: \`user\`
${EL2_LOGIN_BLOCK}
EOF

if [ "$(stat -c '%s' "$ZST_FILE")" -lt "$SPLIT_THRESHOLD_BYTES" ]; then
  PACKAGE_GLOB="${IMAGE_BASENAME}.zst"
else
  split -b "$IMAGE_CHUNK_SIZE" -d -a 3 \
    "$ZST_FILE" \
    "$ZST_FILE.part-"
  PACKAGE_GLOB="${IMAGE_BASENAME}.zst.part-*"

  cat >> "$RELEASE_BODY_FILE" <<EOF
## Reassemble And Decompress

\`\`\`bash
cat ${IMAGE_BASENAME}.zst.part-* > ${IMAGE_BASENAME}.zst
zstd -d ${IMAGE_BASENAME}.zst -o ${IMAGE_BASENAME}
\`\`\`
EOF
fi

sudo chown "$(id -u):$(id -g)" "$RELEASE_BODY_FILE"

el2_suffix=""
[[ "$BUILD_EL2" == "true" ]] && el2_suffix="-el2"
TAG_NAME="ubuntu${UBUNTU_RELEASE}-${KREL}${el2_suffix}-$(date -u +%Y%m%d%H%M%S)"

# workflow 从 GITHUB_OUTPUT 读取发布信息；本地构建没有该变量时跳过
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "tag_name=$TAG_NAME"
    echo "kernel_release=$KREL"
    echo "package_glob=$PACKAGE_GLOB"
  } >> "$GITHUB_OUTPUT"
fi
