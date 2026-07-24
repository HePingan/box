#!/usr/bin/env bash
# 题库平台状态与题图备份/恢复脚本。
# 默认工作在当前目录，读取 IMAGE_STATE_PATH（默认 .var/image_platform_state.json）。
set -euo pipefail

STATE_PATH="${IMAGE_STATE_PATH:-.var/image_platform_state.json}"
IMAGE_DIR="${QUIZ_IMAGE_DIR:-.var/quiz_images}"
BACKUP_ROOT="${QUIZ_BACKUP_ROOT:-.var/backups}"
TS="$(date +%Y%m%d_%H%M%S)"
KEEP="${QUIZ_BACKUP_KEEP:-7}"

usage() {
  cat <<'EOF'
用法:
  backup_quiz_platform.sh [backup]
  backup_quiz_platform.sh restore <backup_dir>
  backup_quiz_platform.sh list

环境变量:
  IMAGE_STATE_PATH   状态文件路径（默认 .var/image_platform_state.json）
  QUIZ_IMAGE_DIR     题图目录（默认 .var/quiz_images）
  QUIZ_BACKUP_ROOT   备份根目录（默认 .var/backups）
  QUIZ_BACKUP_KEEP   保留份数（默认 7）
EOF
}

backup_now() {
  mkdir -p "$BACKUP_ROOT"
  local dest="$BACKUP_ROOT/quiz_$TS"
  mkdir -p "$dest"
  if [[ -f "$STATE_PATH" ]]; then
    cp -a "$STATE_PATH" "$dest/image_platform_state.json"
  else
    echo "WARN: state not found: $STATE_PATH" >&2
  fi
  if [[ -d "$IMAGE_DIR" ]]; then
    mkdir -p "$dest/quiz_images"
    cp -a "$IMAGE_DIR"/. "$dest/quiz_images"/
  else
    echo "WARN: image dir not found: $IMAGE_DIR" >&2
  fi
  (
    cd "$dest"
    find . -type f | sort | xargs sha256sum > SHA256SUMS
  )
  echo "Backup created: $dest"
  # prune
  mapfile -t old < <(ls -1dt "$BACKUP_ROOT"/quiz_* 2>/dev/null | tail -n +$((KEEP + 1)) || true)
  for d in "${old[@]:-}"; do
    [[ -n "$d" ]] || continue
    rm -rf "$d"
    echo "Pruned: $d"
  done
}

restore_from() {
  local src="${1:-}"
  if [[ -z "$src" || ! -d "$src" ]]; then
    echo "restore 需要有效备份目录" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$STATE_PATH")"
  if [[ -f "$src/image_platform_state.json" ]]; then
    cp -a "$src/image_platform_state.json" "$STATE_PATH"
    echo "Restored state -> $STATE_PATH"
  fi
  if [[ -d "$src/quiz_images" ]]; then
    mkdir -p "$IMAGE_DIR"
    cp -a "$src/quiz_images"/. "$IMAGE_DIR"/
    echo "Restored images -> $IMAGE_DIR"
  fi
  echo "Restore done. 请重启 box-image-platform 服务。"
}

list_backups() {
  ls -1dt "$BACKUP_ROOT"/quiz_* 2>/dev/null || echo "(no backups)"
}

cmd="${1:-backup}"
case "$cmd" in
  backup) backup_now ;;
  restore) restore_from "${2:-}" ;;
  list) list_backups ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
