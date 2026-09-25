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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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

# ---- 取监控快照令牌（端点已收口，缺了包里的插件会被判 404）-------------------
MONITOR_TOKEN_FILE="${MONITOR_TOKEN_FILE:-/root/.secrets/box-monitor-snapshot-token}"
MONITOR_TOKEN=""
if [[ -r "$MONITOR_TOKEN_FILE" ]]; then
  MONITOR_TOKEN="$(tr -d '\r\n' < "$MONITOR_TOKEN_FILE")"
fi
if [[ -z "$MONITOR_TOKEN" ]]; then
  echo "[错误] 找不到监控快照令牌：$MONITOR_TOKEN_FILE" >&2
  echo "       没有它，「服务监控」插件请求 https://box.hpa888.top/monitors.json 会被 nginx 判 404。" >&2
  echo "       写入方式：openssl rand -hex 24 > $MONITOR_TOKEN_FILE && chmod 600 $MONITOR_TOKEN_FILE" >&2
  echo "       （边缘机 nginx 的 location = /monitors.json 里那行 if 必须与本文件一致）" >&2
  exit 1
fi

# ---- 运维通道地址（口令**不再注入**：C1 中期档起只由用户输入、只存本机）--------
# 288/289 曾把口令 --dart-define 进包，但安装包是公网可下载的，反编译即得服务器 root。
# 现在包里只有地址与用户名（都不是秘密），口令要用户在设置里填一次。
OPS_DAV_BASE="${OPS_DAV_BASE:-https://box.hpa888.top/dav}"
OPS_DAV_USER="${OPS_DAV_USER:-boxops}"
OPS_TERM_URL="${OPS_TERM_URL:-https://box.hpa888.top/term/}"
# 第二台机器（175 = 构建/监控机）：同一台边缘机的 /dav175//term175/，
# 靠 hpa888 上的 box-ops175-tunnel.service 隧道 + 两个 nginx location 转过去。
# 同样是"只有地址和用户名"，口令用户自己填。
OPS_DAV175_BASE="${OPS_DAV175_BASE:-https://box.hpa888.top/dav175}"
OPS_DAV175_USER="${OPS_DAV175_USER:-boxops}"
OPS_TERM175_URL="${OPS_TERM175_URL:-https://box.hpa888.top/term175/}"

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

# ---- 导出给 Gradle（A 档守卫的判据）----------------------------------------
# android/app/build.gradle.kts 的 verifyUpdateSignInjected 任务靠
# UPDATE_SIGNATURE_SECRET 这个**环境变量**判断密钥是否注入。下面 flutter build
# 里的 --dart-define 只传给了 Dart 侧，Gradle 进程看不到 —— 必须在这里 export，
# 否则守卫会把正式构建也当成 plain build 拦下来（已实测踩到）。
export UPDATE_SIGNATURE_SECRET="$SECRET"

# ---- 入口标记（B 档守卫的另一半）-------------------------------------------
# 没有这个标记，tool/preflight_release_guard.sh 会阻断构建；plain build 拿不到标记。
# 标记里只放指纹，不放密钥。trap 保证任何退出路径（成功/失败/Ctrl-C）都清理，
# 否则残留标记会骗过守卫下一次 plain build。
MARKER="$REPO_ROOT/android/.update-sign-injected"
if [[ ! -d "$REPO_ROOT/android" ]]; then
  echo "[错误] 找不到 $REPO_ROOT/android，无法写入入口标记。" >&2
  exit 1
fi
{
  echo "versionCode=$VERSION_CODE"
  echo "secretFingerprint=$FP"
  echo "channel=$CHANNEL"
  echo "targetPlatform=$TARGET_PLATFORM"
  echo "writtenAt=$(date -Is)"
  echo "pid=$$"
} > "$MARKER"
cleanup_marker() { rm -f "$MARKER"; }
trap cleanup_marker EXIT INT TERM

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

# ---- 入口守卫自检（B 档）---------------------------------------------------
# 标记刚写完，立刻回跑一次守卫：如果守卫脚本本身被改坏（例如标记路径写错），
# 这里就会暴露，而不是等到「某天 plain build 又漏过去」才发现。
bash "$REPO_ROOT/tool/preflight_release_guard.sh"

flutter build apk --release \
  --target-platform "$TARGET_PLATFORM" \
  "${OBFUSCATE_ARGS[@]}" \
  --dart-define=UPDATE_CHECK_URL="$CHECK_URL" \
  --dart-define=UPDATE_SIGNATURE_ALGORITHM="$SIG_ALGO" \
  --dart-define=UPDATE_SIGNATURE_SECRET="$SECRET" \
  --dart-define=MONITOR_SNAPSHOT_TOKEN="$MONITOR_TOKEN" \
  --dart-define=OPS_DAV_BASE="$OPS_DAV_BASE" \
  --dart-define=OPS_DAV_USER="$OPS_DAV_USER" \
  --dart-define=OPS_TERM_URL="$OPS_TERM_URL" \
  --dart-define=OPS_DAV175_BASE="$OPS_DAV175_BASE" \
  --dart-define=OPS_DAV175_USER="$OPS_DAV175_USER" \
  --dart-define=OPS_TERM175_URL="$OPS_TERM175_URL" \
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
  # 注意：这里**不能**直接 trap 'rm -rf ...' EXIT —— 那会覆盖上面清理入口标记的
  # trap，标记就残留下来骗过守卫（已实测踩到）。合并成一个 trap。
  cleanup_probe() { rm -rf "$SECRET_PROBE_DIR"; }
  trap 'cleanup_marker; cleanup_probe' EXIT INT TERM
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
APKSIGNER=""
# apksigner 的位置随机器而变：本构建机装在 /root/Android/Sdk，服务端历史上在
# /root/android-sdk。按 ANDROID_HOME / ANDROID_SDK_ROOT / 两个已知路径依次探测。
# 为什么不能只写死一个路径：找不到时下面只会打一行 warning 然后**跳过签名核对**，
# 那等于静默放行一个可能用 debug 签名发的包——正是这个闸门要防的事。
for _sdk_cand in "${ANDROID_HOME:-}/build-tools" "${ANDROID_SDK_ROOT:-}/build-tools" /root/Android/Sdk/build-tools /root/android-sdk/build-tools; do
  [[ -n "$_sdk_cand" && -d "$_sdk_cand" ]] || continue
  _found="$(ls -d "$_sdk_cand"/*/apksigner 2>/dev/null | sort -r | head -1 || true)"
  if [[ -n "$_found" ]]; then
    APKSIGNER="$_found"
    break
  fi
done
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
