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

# ---- 混淆与符号表 ----------------------------------------------------------
# --obfuscate 把 Dart 符号从 libapp.so 里剥掉，实测省 1.69MB（11.86→10.09MB）。
# 代价：崩溃堆栈变成乱码。所以符号表**必须**归档，否则线上崩溃无法还原函数名。
# 归档目录按 versionCode 分子目录，与发布的 APK 一一对应。
#
# 关掉混淆：OBFUSCATE=0 bash tool/build_release_with_update_sign.sh
OBFUSCATE="${OBFUSCATE:-1}"
VERSION_CODE="$(grep -m1 '^version:' pubspec.yaml | sed 's/.*+//' | tr -d ' \r')"
SYMBOLS_DIR="${SYMBOLS_DIR:-build/symbols/$VERSION_CODE}"

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

OBFUSCATE_ARGS=()
if [[ "$OBFUSCATE" == "1" ]]; then
  mkdir -p "$SYMBOLS_DIR"
  OBFUSCATE_ARGS=(--obfuscate --split-debug-info="$SYMBOLS_DIR")
  echo "    混淆        : 开启，符号表 → $SYMBOLS_DIR"
else
  echo "    混淆        : 关闭（OBFUSCATE=0）"
fi
echo

flutter build apk --release \
  --target-platform "$TARGET_PLATFORM" \
  "${OBFUSCATE_ARGS[@]}" \
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

# ---- 验签密钥闸门 ----------------------------------------------------------
# 为什么必须在**产物**上验而不是只看变量：这个脚本传了 --dart-define 不等于
# 密钥真进了包。单测也挡不住——单测跑在没注入 define 的环境，
# test/update/update_signature_secret_present_test.dart 那条只会 skip。
#
# 这个错已经犯过两次：1.7.3(173) 和 1.8.5(185) 都是绕过本脚本手工敲
# flutter build 发出去的，用户装上后每次检查更新都报「更新清单签名校验未
# 通过 (HMAC 更新验签缺少 secret)」，且再也收不到后续版本——更新链路是断的。
# 所以在这里直接搜 libapp.so，产物里没有密钥就不让发。
if [[ "$SIG_ALGO" == "hmac_sha256" ]]; then
  SECRET_PROBE_DIR="$(mktemp -d)"
  trap 'rm -rf "$SECRET_PROBE_DIR"' EXIT
  unzip -q -o "$APK" 'lib/*/libapp.so' -d "$SECRET_PROBE_DIR" 2>/dev/null || true
  PROBE_SO="$(find "$SECRET_PROBE_DIR" -name libapp.so | head -1)"
  if [[ -z "$PROBE_SO" ]]; then
    echo "    [警告] APK 内找不到 libapp.so，跳过密钥注入核对" >&2
  elif grep -qF "$SECRET" "$PROBE_SO"; then
    echo "    验签密钥    : 已确认注入产物（指纹 $FP）"
  else
    cat >&2 <<EOF

[错误] 验签密钥没有进到 APK 产物里，不要发布这个包。

算法是 $SIG_ALGO，但 libapp.so 内搜不到密钥。装上这个包的用户每次检查
更新都会报「更新清单签名校验未通过 (HMAC 更新验签缺少 secret)」，并且
收不到任何后续版本。

请检查 flutter build 是否真的收到了
  --dart-define=UPDATE_SIGNATURE_SECRET=...
EOF
    exit 1
  fi
fi

# ---- 符号表闸门 ------------------------------------------------------------
# 开了混淆却没产出符号表，等于放弃了线上崩溃排查能力，必须卡住。
if [[ "$OBFUSCATE" == "1" ]]; then
  SYM_COUNT="$(ls -1 "$SYMBOLS_DIR" 2>/dev/null | wc -l)"
  if [[ "$SYM_COUNT" -eq 0 ]]; then
    cat >&2 <<EOF

[错误] 混淆已开启，但 $SYMBOLS_DIR 里没有符号表文件。

没有符号表，这个包一旦在线上崩溃，堆栈全是混淆后的名字，无法定位。
不要发布这个包。请检查 flutter build 是否真的收到了 --split-debug-info。
EOF
    exit 1
  fi
  echo "    符号表      : $SYMBOLS_DIR （$SYM_COUNT 个文件）"
  ls -lh "$SYMBOLS_DIR" | awk 'NR>1{print "                  "$5"  "$9}'

  # build/ 在 .gitignore 里，flutter clean 会连符号表一起清掉。所以立刻复制到
  # 持久归档目录——发布出去的包一旦崩溃，只有这份符号表能还原堆栈。
  ARCHIVE_DIR="${SYMBOLS_ARCHIVE_DIR:-/root/.box-symbols/$VERSION_CODE}"
  mkdir -p "$ARCHIVE_DIR"
  cp -f "$SYMBOLS_DIR"/* "$ARCHIVE_DIR"/ 2>/dev/null || true
  sha256sum "$APK" | cut -d' ' -f1 > "$ARCHIVE_DIR/apk.sha256"
  echo "    符号表归档  : $ARCHIVE_DIR （已附 apk.sha256 对应关系）"
fi

# ---- 签名闸门 --------------------------------------------------------------
# 为什么必须卡这一道：key.properties 缺失时 build.gradle.kts 会静默 fallback
# 到 debug 签名，产出一个"看起来正常、装到老机器上必失败"的包。线上 1.1.8
# 与本机构建就是两把不同的 debug key（4f5fa752… vs 8daac29e…），跨签名无法
# 覆盖安装，用户会拿到 INSTALL_FAILED_UPDATE_INCOMPATIBLE。
APKSIGNER="$(ls -d /root/android-sdk/build-tools/*/apksigner 2>/dev/null | sort -r | head -1 || true)"
if [[ -z "$APKSIGNER" ]]; then
  echo "    [警告] 未找到 apksigner，跳过签名核对" >&2
else
  CERTS="$("$APKSIGNER" verify --print-certs "$APK" 2>&1 || true)"
  if grep -q 'CN=Android Debug' <<<"$CERTS"; then
    cat >&2 <<EOF

[错误] 这个包是 debug 签名，不能对外发布。

原因：android/key.properties 缺失或 storeFile 为空，Gradle 回退到了 debug
签名。debug 签名的包无法覆盖安装到用正式证书签过的机器上，老用户会看到
INSTALL_FAILED_UPDATE_INCOMPATIBLE。

请配置 android/key.properties（storeFile/storePassword/keyAlias/keyPassword），
keystore 位置：/root/.secrets/box-release.p12
EOF
    exit 1
  fi
  FPR="$(grep -oiE 'certificate SHA-256 digest: [0-9a-f]+' <<<"$CERTS" | head -1 | awk '{print $NF}')"
  echo "    签名证书    : $(grep -oE 'certificate DN: .*' <<<"$CERTS" | head -1 | cut -c17-)"
  echo "    证书指纹    : ${FPR:-未取到}"
fi
