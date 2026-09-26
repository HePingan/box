#!/bin/bash
# 在**监控机（175）**上安装资源越线告警：脚本 + 配置 + 只读令牌 + 5 分钟 cron。
#
# 为什么跑在 175 而不是两台各跑一份：告警要"一台机器说话"。
# 两台各报各的会出现两个后果：① 同一次故障两条消息；② 被监控的那台挂了就没人报（它自己报不了自己）。
# 175 是构建/监控机（Kuma 也在这台），它去**取**两台的数（本地回环 + 公网入口）。
#
# 凭据用的是**只读令牌**（`token issue` 不带 --admin/--write）：这台机器的告警只需要看，
# 不需要读审计、更不需要能改东西。令牌文件 600，只在本机。
#
# 用法：
#   deploy_box_ops_alert.sh              # 安装/更新（令牌已存在就不动）
#   deploy_box_ops_alert.sh --rotate     # 重签两把只读令牌（旧令牌立即失效）
#   deploy_box_ops_alert.sh --verify     # 只验：取数 + 会不会发（--check）+ 链路自检提示
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN=/usr/local/sbin/box-ops-alert.py
CONF_DIR=/etc/box-ops-alert
CONF=$CONF_DIR/config.json
CRON=/etc/cron.d/box-ops-alert
SECRETS=/root/.secrets
STATE_DIR=/var/lib/box-ops-alert
LOG=/var/log/box-ops-alert.log
ROTATE=0
VERIFY_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --rotate) ROTATE=1 ;;
    --verify) VERIFY_ONLY=1 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }

issue_token() {  # $1=在哪台签（175|hpa888） $2=label $3=输出文件
  local where=$1 label=$2 out=$3 raw
  if [ "$where" = "175" ]; then
    raw=$(/usr/local/sbin/box-ops-api.py token issue --label "$label" 2>&1)
  else
    raw=$(ssh hpa888 "/usr/local/sbin/box-ops-api.py token issue --label $label" 2>&1)
  fi
  # 令牌单独占最后一行（部署脚本的取法一致：别把说明文字当令牌抓进来）
  local tok
  tok=$(printf '%s\n' "$raw" | grep -E '^[A-Za-z0-9_-]{40,}$' | tail -1)
  if [ -z "$tok" ]; then
    say "  ✗ $where 签发失败：$raw" >&2
    return 1
  fi
  umask 077
  printf '%s\n' "$tok" > "$out"
  chmod 600 "$out"
  say "  ✓ $where → $out（$(wc -c < "$out") 字节）"
}

if [ "$VERIFY_ONLY" = "0" ]; then
  say "== 安装脚本 =="
  install -m 755 "$REPO/tool/ops_api/box_ops_alert.py" "$BIN"
  say "  ✓ $BIN"

  say "== 配置 =="
  mkdir -p "$CONF_DIR"
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<'JSON'
{
  "hosts": [
    {
      "id": "175",
      "label": "腾讯云 · 构建/监控机",
      "icon": "🖥️ ",
      "base": "http://127.0.0.1:8095",
      "token_file": "/root/.secrets/box-ops-alert-token-175"
    },
    {
      "id": "hpa888",
      "label": "阿里云 · 主服务端",
      "icon": "☁️ ",
      "base": "https://box.hpa888.top/opsapi",
      "token_file": "/root/.secrets/box-ops-alert-token-hpa888"
    }
  ],
  "thresholds": {
    "cpu_warn": 85,
    "cpu_crit": 95,
    "mem_warn": 85,
    "mem_crit": 95,
    "swap_warn": 50,
    "swap_crit": 80,
    "load_per_core_warn": 1.5,
    "load_per_core_crit": 3.0,
    "samples_before_alert": 2,
    "repeat_minutes": 360,
    "fail_before_alert": 3,
    "timeout_seconds": 20,
    "disk_enabled": false
  }
}
JSON
    chmod 644 "$CONF"
    say "  ✓ 写了默认配置 $CONF"
  else
    say "  · $CONF 已存在，保留（要重置先删掉它）"
  fi

  say "== 只读令牌 =="
  if [ "$ROTATE" = "1" ] || [ ! -f "$SECRETS/box-ops-alert-token-175" ]; then
    issue_token 175 box-ops-alert-175 "$SECRETS/box-ops-alert-token-175" || exit 1
  else
    say "  · 175 的令牌已存在（--rotate 才重签）"
  fi
  if [ "$ROTATE" = "1" ] || [ ! -f "$SECRETS/box-ops-alert-token-hpa888" ]; then
    issue_token hpa888 box-ops-alert-hpa888 "$SECRETS/box-ops-alert-token-hpa888" || exit 1
  else
    say "  · hpa888 的令牌已存在（--rotate 才重签）"
  fi

  say "== cron（每 5 分钟） =="
  cat > "$CRON" <<CRONEOF
# 资源越线告警（C3）：只在档位变化/恢复/采不到数据时发飞书，平时静默。
# 自检：$BIN --selftest（不联网） / --test（故意发一条，验链路）
*/5 * * * * root $BIN --once --quiet >> $LOG 2>&1
CRONEOF
  chmod 644 "$CRON"
  mkdir -p "$STATE_DIR"
  say "  ✓ $CRON"
fi

say "== 验证 =="
"$BIN" --selftest 2>&1 | tail -1
say "  —— 当前两台的取值与阈值判定（--check，不落状态、不真发）："
"$BIN" --check
say "  —— 链路自检（会真的发一条飞书）：$BIN --test"
