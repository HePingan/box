#!/usr/bin/env bash
#
# 构建守卫回归测试（A 档 + B 档）。
#
# 为什么需要：守卫本身出错的两种方式都很隐蔽——
#   ① 假阴性：plain build 没被拦住 → 又发出一个静默坏包（历史事故 1.7.3/1.8.5）。
#   ② 假阳性：正式脚本被拦住 → 发布流程直接卡死（2026-09-12 实测踩到：
#      脚本只把密钥传给 --dart-define，没 export，Gradle 进程看不到环境变量）。
# 两种都必须有测试兜住，否则下次改脚本又悄悄回归。
#
# 用法：bash tool/test_release_guard.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MARKER="android/.update-sign-injected"
GRADLE_FILE="android/app/build.gradle.kts"
BUILD_SCRIPT="tool/build_release_with_update_sign.sh"
GUARD_SCRIPT="tool/preflight_release_guard.sh"

PASS=0
FAIL=0
MARKER_BAK="$(mktemp)"

ok()   { printf '  \033[32m✅ %s\033[0m\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31m❌ %s\033[0m\n' "$1"; FAIL=$((FAIL + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

cleanup() {
  if [[ -s "$MARKER_BAK" ]]; then
    cp -f "$MARKER_BAK" "$MARKER"
  else
    rm -f "$MARKER"
  fi
  rm -f "$MARKER_BAK"
}
trap cleanup EXIT

[[ -f "$MARKER" ]] && cp -f "$MARKER" "$MARKER_BAK"

# ---- 静态契约：脚本必须把密钥导出给 Gradle ---------------------------------
head_ "1. 静态契约（脚本 ↔ Gradle 守卫的接口）"
if grep -qE '^\s*export\s+UPDATE_SIGNATURE_SECRET=' "$BUILD_SCRIPT"; then
  ok "构建脚本 export 了 UPDATE_SIGNATURE_SECRET（Gradle 守卫拿得到）"
else
  bad "构建脚本没有 export UPDATE_SIGNATURE_SECRET → 守卫会误拦正式构建"
fi

if grep -q 'verifyUpdateSignInjected' "$GRADLE_FILE"; then
  ok "build.gradle.kts 里存在 verifyUpdateSignInjected 守卫"
else
  bad "build.gradle.kts 里找不到 verifyUpdateSignInjected 守卫"
fi

if grep -qE 'name == "assembleRelease"' "$GRADLE_FILE"; then
  ok "守卫挂到了 assembleRelease 上"
else
  bad "守卫没有挂到 assembleRelease → 不会被执行"
fi

# 守卫必须在正式签名时才阻断：否则会挡住日常 debug-signed 装机测试
if grep -q 'realReleaseSigning' "$GRADLE_FILE"; then
  ok "守卫以 realReleaseSigning 为条件（debug 回退不阻断）"
else
  bad "守卫缺少 realReleaseSigning 条件 → 会挡住本地装机测试"
fi

# ---- 运行时：B 档入口守卫三态 ----------------------------------------------
head_ "2. 运行时（B 档入口守卫三态）"
rm -f "$MARKER"
if bash "$GUARD_SCRIPT" >/dev/null 2>&1; then
  bad "无标记时未阻断（plain build 能溜过去）"
else
  ok "无标记 → 阻断（plain build 被拦）"
fi

printf 'versionCode=test\n' > "$MARKER"
touch -d "31 minutes ago" "$MARKER"
# 注意：不要写 `bash "$GUARD_SCRIPT" 2>&1 | grep -q "陈旧"` —— 守卫本身退出码是 1
# （它正确阻断了），在 set -o pipefail 下这个管道整体返回 1，grep 是否匹配被掩盖，
# 测试会假失败。先捕获输出再 case 匹配。
STALE_OUT="$(bash "$GUARD_SCRIPT" 2>&1 || true)"
case "$STALE_OUT" in
  *陈旧*) ok "陈旧标记（>30 分钟）→ 识别为残留并阻断" ;;
  *)      bad "陈旧标记未被识别 → 上次崩溃残留会骗过守卫" ;;
esac

printf 'versionCode=test\n' > "$MARKER"
if bash "$GUARD_SCRIPT" >/dev/null 2>&1; then
  ok "新鲜标记 + 密钥可得 → 放行"
else
  bad "新鲜标记被误拦 → 正式发布流程被卡死"
fi

# ---- 运行时：A 档 Gradle 守卫 ----------------------------------------------
head_ "3. 运行时（A 档 Gradle 守卫，实测调 Gradle）"
if [[ ! -d android ]]; then
  bad "找不到 android/，跳过 Gradle 实测"
else
  # 3a 无密钥 + 正式签名 → 必须 FAIL
  if (cd android && env -u UPDATE_SIGNATURE_SECRET \
        ./gradlew :app:verifyUpdateSignInjected -q --offline >/dev/null 2>&1); then
    bad "无密钥时 Gradle 守卫没阻断（假阴性！）"
  else
    ok "无密钥 + 正式签名 → Gradle 守卫阻断"
  fi

  # 3b 有密钥 → 必须 PASS
  SECRET_VAL="$(tr -d '\r\n' < /root/.secrets/box-update-manifest-sign-secret 2>/dev/null || true)"
  if [[ -z "$SECRET_VAL" ]]; then
    echo "  ⏭  跳过 3b：读不到密钥文件"
  elif (cd android && UPDATE_SIGNATURE_SECRET="$SECRET_VAL" \
        ./gradlew :app:verifyUpdateSignInjected -q --offline >/dev/null 2>&1); then
    ok "有密钥 → Gradle 守卫放行（正式脚本路径通）"
  else
    bad "有密钥时仍被阻断（假阳性！发布流程会卡死）"
  fi
fi

# ---- 汇总 ------------------------------------------------------------------
head_ "汇总"
printf '  通过 %d，失败 %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] && printf '  \033[32m全部通过\033[0m\n' || printf '  \033[31m有失败项\033[0m\n'
exit $(( FAIL > 0 ? 1 : 0 ))
