#!/usr/bin/env bash
#
# 构建带更新验签配置的 release APK。
#
# 为什么需要这个脚本：验签密钥**不能**进 git，只能在构建时经 --dart-define
# 注入。手工敲 flutter build 很容易漏掉某个 define，漏了就得到一个「装上去
# 才发现更新检查失败」的包。
#
# 用法：
#   bash tool/build_release_with_update_sign.sh                  # arm64 release
#   TARGET_PLATFORM=android-arm64,android-arm64 ... 见下方变量
#
# 密钥读取优先顺序：
#   1. 环境变量 UPDATE_SIGNATURE_SECRET
#   2. /root/.secrets/box-update-manifest-sign-secret
#   3. 报错退出（绝不静默构建出一个验签必失败的包）
set -euo pipefail

cd "$(dirname "$0")/.."

SECRET_FILE="${SECRET_FILE:-/root/.secrets/box-update-manifest-sign-secret}"
CHECK_URL="${UPDATE_CHECK_URL:-https://box.hpa888.top/api/v1/app-updates/check}"
ALLOWED_HOSTS="${UPDATE_DOWNLOAD_ALLOWED_HOSTS:-box.hpa888.top}"
SIG_ALGO="${UPDATE_SIGNATURE_ALGORITHM:-hmac_sha256}"
CHANNEL="${APP_CHANNEL:-release}"
TARGET_PLATFORM="${TARGET_PLATFORM:-android-arm64}"

# ---- 取密钥 ----------------------------------------------------------------
SECRET="${UPDATE_SIGNATURE_SECRET:-}"
if [[ -z "$SECRET" && -r "$SECRET_FILE" ]]; then
  SECRET="$(tr -d '\r\n' < "$SECRET_FILE")"
fi

if [[ -z "$SECRET" ]]; then
  cat >&2 <<EOF
[错误] 找不到更新验签密钥。

服务端已开启 HMAC 签名，构建时必须注入同一个密钥，否则 App 每次检查更新
都会报「更新清单签名不匹配」。

请任选其一：
  export UPDATE_SIGNATURE_SECRET='<secret>'
  或把密钥写入 $SECRET_FILE （chmod 600）

服务端密钥位置：47.109.97.1:/home/update-server/.env → MANIFEST_SIGN_SECRET
EOF
  exit 1
fi

# 只打印指纹，绝不打印密钥本身（构建日志可能被贴到别处）
FP="$(printf '%s' "$SECRET" | sha256sum | cut -c1-12)"

echo "==> 更新验签配置"
echo "    check URL   : $CHECK_URL"
echo "    算法        : $SIG_ALGO"
echo "    下载白名单  : $ALLOWED_HOSTS"
echo "    密钥指纹    : $FP (长度 ${#SECRET})"
echo "    渠道/架构   : $CHANNEL / $TARGET_PLATFORM"
echo

flutter build apk --release \
  --target-platform "$TARGET_PLATFORM" \
  --dart-define=UPDATE_CHECK_URL="$CHECK_URL" \
  --dart-define=UPDATE_SIGNATURE_ALGORITHM="$SIG_ALGO" \
  --dart-define=UPDATE_SIGNATURE_SECRET="$SECRET" \
  --dart-define=UPDATE_DOWNLOAD_ALLOWED_HOSTS="$ALLOWED_HOSTS" \
  --dart-define=REQUIRE_UPDATE_SHA256=true \
  --dart-define=APP_CHANNEL="$CHANNEL"

APK="build/app/outputs/flutter-apk/app-release.apk"
echo
echo "==> 构建完成"
ls -lh "$APK" | awk '{print "    "$5"  "$9}'
echo "    SHA-256: $(sha256sum "$APK" | cut -d" " -f1)"
