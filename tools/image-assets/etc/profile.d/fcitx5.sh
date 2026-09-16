#!/usr/bin/env bash
# fcitx5 中文输入法环境变量（E-Go 触屏平板）
# 已有环境变量优先，避免覆盖用户在桌面会话里的自定义配置。
export XMODIFIERS="${XMODIFIERS:-@im=fcitx}"
export GTK_IM_MODULE="${GTK_IM_MODULE:-fcitx}"
export QT_IM_MODULE="${QT_IM_MODULE:-fcitx}"