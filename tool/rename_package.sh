#!/usr/bin/env bash
# 把 Android 包名从 com.example.box 改成 top.hpa888.box。
#
# 为什么要脚本而不是手工 sed：这个改动横跨 Kotlin package 声明、源码目录结构、
# gradle 的 namespace/applicationId、res XML 里的自定义 View 全限定名、
# MethodChannel 字符串（Dart 与 Kotlin 两侧必须逐字一致，错一个字就是运行时
# MissingPluginException，编译期发现不了），漏一处就是真机崩。
#
# 只改源码，不碰仓库根目录那堆历史 .apk 产物，也不碰 build/ 与 .dart_tool/。
set -euo pipefail

OLD="com.example.box"
NEW="top.hpa888.box"
OLD_DIR="android/app/src/main/kotlin/com/example/box"
NEW_DIR="android/app/src/main/kotlin/top/hpa888/box"

cd "$(dirname "$0")/.."

if [[ ! -d "$OLD_DIR" ]]; then
  echo "[跳过] $OLD_DIR 不存在，可能已经改过了"
  exit 0
fi

echo "==> 1/4 git mv Kotlin 源码目录（保留历史）"
mkdir -p "$(dirname "$NEW_DIR")"
git mv "$OLD_DIR" "$NEW_DIR"
# com/example 下如果空了就清掉，避免留下空目录
find android/app/src/main/kotlin/com -type d -empty -delete 2>/dev/null || true

echo "==> 2/4 替换 Kotlin / Gradle / res XML 里的包名"
# 注意 res XML 里是 <com.example.box.TouchAwareFrameLayout>，同一个替换就能覆盖
while IFS= read -r f; do
  perl -pi -e "s/\Qcom.example.box\E/$NEW/g" "$f"
  echo "    $f"
done < <(grep -rl "$OLD" \
  android/app/src/main/kotlin \
  android/app/src/main/res \
  android/app/build.gradle.kts \
  2>/dev/null || true)

echo "==> 3/4 替换 Dart 侧 MethodChannel 字符串"
# Dart 与 Kotlin 的 channel 名必须逐字一致。
# 只替换 channel 名与 prefs 名，不动注释里描述设备路径的示例。
while IFS= read -r f; do
  perl -pi -e "s|'\Qcom.example.box\E/|'$NEW/|g" "$f"
  echo "    $f"
done < <(grep -rl "'com\.example\.box/" lib test 2>/dev/null || true)

echo "==> 4/4 校验：源码里不应再有旧包名"
LEFT=$(grep -rn "$OLD" \
  android/app/src/main/kotlin \
  android/app/src/main/res \
  android/app/build.gradle.kts \
  lib \
  2>/dev/null | grep -v "_preferences" || true)
if [[ -n "$LEFT" ]]; then
  echo "[警告] 仍有残留（若是 prefs 兜底/注释里的设备路径示例则属预期）："
  echo "$LEFT"
fi

echo "==> 完成"
