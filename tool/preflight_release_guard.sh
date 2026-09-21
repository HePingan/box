#!/usr/bin/env bash
#
# 构建入口守卫（B 档）—— 独立可跑，也被 tool/build_release_with_update_sign.sh 调用。
#
# 为什么需要它：
#   plain `flutter build apk --release` 会产出一个「看起来完全正常」的包，
#   但它没有更新验签密钥 → 装到用户手机上「检查更新」永久失败，
#   而且产物本身没有任何标记可以分辨（applicationId / versionCode /
#   证书指纹全都对）。唯一原判据是构建脚本打印的那行「已确认注入产物」，
#   而构建日志在 CI 里过期就没了。
#
#   历史上已因此发错两次：1.7.3(173) 和 1.8.5(185)。
#
#   A 档守卫（android/app/build.gradle.kts 的 verifyUpdateSignInjected）能挡住
#   plain build —— 但前提是 Gradle 真的走到那个 task。若有人用
#   `flutter build apk --release --no-pub` 之外的路径、或改了 Gradle 配置、
#   或守卫被误删，就漏了。B 档是第二道：**构建入口**处的显式标记。
#
# 机制：
#   走正式脚本构建时，脚本会先写 android/.update-sign-injected 标记文件
#   （含时间戳、versionCode、密钥指纹短串——**不含密钥本身**），构建结束后删除。
#   plain build 没有这个标记，本守卫在读 pubspec/构建参数阶段就报错退出。
#
# 用法（供人工排查）：
#   bash tool/preflight_release_guard.sh          # 检查当前是否满足正式发布条件
#
# 返回码：0 = 可继续；1 = 阻断（信息打印到 stderr）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKER="$REPO_ROOT/android/.update-sign-injected"
SECRET_FILE="${SECRET_FILE:-/root/.secrets/box-update-manifest-sign-secret}"

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# 标记文件必须存在且新鲜（同一构建会话内写入；超过 30 分钟视为陈旧残留）
if [[ ! -f "$MARKER" ]]; then
  cat >&2 <<'EOF'
[错误] 发布构建缺少入口标记，已阻断。

你没有通过正式脚本构建，或标记文件已被清理。plain
  flutter build apk --release
产出的包**没有更新验签密钥**，用户装上后永远收不到更新（历史上因此发错两次）。

正确命令：
  bash tool/build_release_with_update_sign.sh

（若你确实在跑正式脚本却看到这条，说明标记写入失败，请检查
 android/ 目录写权限，并在脚本里看 write_marker 那一段。）
EOF
  exit 1
fi

# 陈旧标记：上一次构建崩在中途，没清掉。会骗过守卫 → 必须当成缺失。
if [[ -n "$(find "$MARKER" -mmin +30 2>/dev/null)" ]]; then
  red "[错误] 入口标记陈旧（超过 30 分钟），视为上次构建残留，已阻断。"
  red "        请删除 $MARKER 后走正式脚本构建：bash tool/build_release_with_update_sign.sh"
  exit 1
fi

# 标记存在时也再确认密钥真的可得（防止「标记写了但密钥读取失败」的错位）
SECRET="${UPDATE_SIGNATURE_SECRET:-}"
if [[ -z "$SECRET" && -r "$SECRET_FILE" ]]; then
  SECRET="$(tr -d '\r\n' < "$SECRET_FILE")"
fi
if [[ -z "$SECRET" ]]; then
  red "[错误] 入口标记存在，但更新验签密钥读取失败，已阻断。"
  red "        export UPDATE_SIGNATURE_SECRET='<secret>' 或写入 $SECRET_FILE (chmod 600)"
  exit 1
fi

FP="$(printf '%s' "$SECRET" | sha256sum | cut -c1-12)"
echo "    入口守卫    : 通过（标记存在，密钥指纹 $FP）"
