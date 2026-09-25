#!/usr/bin/env bash
# 部署 box-ops 只读运维 API（C2 只读档）。
#
# 形状（与既有运维通道同一套约定：服务只绑回环，外网入口由边缘机 nginx 代理）：
#   175  : 127.0.0.1:8095  ← https://box.hpa888.top/opsapi175/   （经 175 隧道转到边缘机 127.0.0.1:8096）
#   hpa888: 127.0.0.1:8095  ← https://box.hpa888.top/opsapi/
#
# 用法（在本机 175 上跑）：
#   deploy_box_ops_api.sh --host 175        # 装/更新 175 上的服务
#   deploy_box_ops_api.sh --host hpa888     # 装/更新 hpa888 上的服务（sftp 过去）
#   deploy_box_ops_api.sh --edge            # 边缘机 nginx 两条 location + 175 隧道加一路转发
#   deploy_box_ops_api.sh --token 175|hpa888 # 签发/轮换设备令牌（写到 .secrets，只打印哈希与长度）
#   deploy_box_ops_api.sh --verify          # 端到端：两条公网入口 + 拒绝路径
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/box_ops_api.py"
REMOTE_SRC="/usr/local/sbin/box-ops-api.py"
UNIT="/etc/systemd/system/box-ops-api.service"
EDGE_VHOST="/www/server/panel/vhost/nginx/box.hpa888.top.conf"
SECRETS="/root/.secrets"
HPA888_SSH="hpa888"

say() { printf '%s\n' "$*"; }
die() { printf '[✗] %s\n' "$*" >&2; exit 1; }
ok()  { printf '[✓] %s\n' "$*"; }

unit_body() {  # $1 = python 解释器
  cat <<EOF
[Unit]
Description=box-ops 只读运维 API（C2）—— 只绑回环，外网入口由边缘机 nginx 代理
After=network.target

[Service]
Type=simple
User=root
# 以 root 跑的理由：journalctl 读别家单元日志、ss -p 读进程名、lastb 读 /var/log/btmp
# 都要权限。风险面由"白名单只读动作 + 设备令牌 + 全量审计"承担（见 box_ops_api.py 头注释）。
ExecStart=$1 $REMOTE_SRC serve --port 8095
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

install_local() {
  [ -f "$SRC" ] || die "找不到 $SRC"
  python3 -c "import ast,sys; ast.parse(open('$SRC').read())" || die "语法不过"
  install -m 755 "$SRC" "$REMOTE_SRC"
  unit_body /usr/bin/python3 > "$UNIT"
  systemctl daemon-reload
  systemctl enable --now box-ops-api.service >/dev/null 2>&1
  systemctl restart box-ops-api.service
  sleep 1
  systemctl is-active --quiet box-ops-api.service || die "服务没起来，看 journalctl -u box-ops-api -n 30"
  ok "175：服务已起（$(systemctl show -p MainPID --value box-ops-api.service)），$REMOTE_SRC"
}

install_remote() {
  [ -f "$SRC" ] || die "找不到 $SRC"
  local py
  py=$(ssh "$HPA888_SSH" 'ls -1 /root/anaconda3/bin/python3 2>/dev/null || echo /usr/bin/python3')
  [[ "$py" == *anaconda3* ]] || say "[!] hpa888 系统 python3 只有 3.6，请确认：$py"
  scp -q "$SRC" "$HPA888_SSH:$REMOTE_SRC"
  ssh "$HPA888_SSH" "$py -c \"import ast; ast.parse(open('$REMOTE_SRC').read())\""
  unit_body "$py" | ssh "$HPA888_SSH" "cat > $UNIT"
  ssh "$HPA888_SSH" "systemctl daemon-reload && systemctl enable --now box-ops-api.service >/dev/null 2>&1 && systemctl restart box-ops-api.service && sleep 1 && systemctl is-active box-ops-api.service"
  ok "hpa888：服务已起（解释器 $py）"
}

install_edge() {
  ssh "$HPA888_SSH" 'bash -s' <<'REMOTE'
set -euo pipefail
VHOST=/www/server/panel/vhost/nginx/box.hpa888.top.conf
cp -a "$VHOST" "$VHOST.bak-opsapi-$(date +%Y%m%d%H%M%S)"
python3 - <<'PY'
from pathlib import Path
p = Path("/www/server/panel/vhost/nginx/box.hpa888.top.conf")
s = p.read_text()
block = """
    # =========================
    # 1.7) 只读运维 API（C2）：进程/服务/日志/端口/目录占用
    #      身份由 API 自己的设备令牌承担（可撤销、有审计），所以这里不加 Basic 认证；
    #      proxy_pass 带尾斜杠 = 剥掉 /opsapi/ 前缀，API 收到的是 /overview 这种干净路径。
    # =========================
    location ^~ /opsapi/ {
        limit_req zone=box_ops burst=30 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:8095/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    location ^~ /opsapi175/ {
        limit_req zone=box_ops burst=30 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:8096/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }
"""
assert "location ^~ /opsapi/" not in s, "已经加过了"
anchor = "    location ^~ /dav/"
assert anchor in s, "找不到 /dav/ 那段，vhost 结构变了？"
s = s.replace(anchor, block.lstrip("\n") + "\n" + anchor, 1)
p.write_text(s)
print("已插入两条 location")
PY
nginx -t && nginx -s reload && echo "nginx 已重载"

UNIT=/etc/systemd/system/box-ops175-tunnel.service
cp -a "$UNIT" "$UNIT.bak-opsapi-$(date +%Y%m%d%H%M%S)"
grep -q '8096:127.0.0.1:8095' "$UNIT" && echo "隧道已有这路转发" || {
  python3 - <<'PY'
from pathlib import Path
p = Path("/etc/systemd/system/box-ops175-tunnel.service")
s = p.read_text()
old = "-L 127.0.0.1:7683:127.0.0.1:7683 root@175.178.248.237"
assert old in s
s = s.replace(old, old.replace(" root@", " -L 127.0.0.1:8096:127.0.0.1:8095 root@"), 1)
p.write_text(s)
print("隧道已加 8096 -> 175:8095")
PY
  systemctl daemon-reload && systemctl restart box-ops175-tunnel.service && sleep 2
}
systemctl is-active --quiet box-ops175-tunnel.service && echo "隧道在跑"
REMOTE
  ok "边缘机：两条 location + 隧道转发就位"
}

issue_token() {  # $1 = 175|hpa888
  local host="$1" label out
  label="box-app-$( [ "$host" = 175 ] && echo 175 || echo hpa888 )"
  if [ "$host" = 175 ]; then
    out=$(python3 "$REMOTE_SRC" token issue --label "$label" --admin | tail -1)
    printf '%s' "$out" > "$SECRETS/box-ops-api-token-$host"
  else
    out=$(ssh "$HPA888_SSH" "python3 /usr/local/sbin/box-ops-api.py token issue --label $label --admin | tail -1")
    printf '%s' "$out" | ssh "$HPA888_SSH" "cat > $SECRETS/box-ops-api-token-hpa888"
  fi
  chmod 600 "$SECRETS/box-ops-api-token-$host" 2>/dev/null || true
  ok "$host 令牌已签发：label=$label 长度=$(printf '%s' "$out" | wc -c) 哈希=$(printf '%s' "$out" | sha256sum | cut -c1-16)…"
}

verify() {
  local t175 thpa t175len
  t175=$(cat "$SECRETS/box-ops-api-token-175" 2>/dev/null || true)
  t175len=$(ssh "$HPA888_SSH" "cat $SECRETS/box-ops-api-token-hpa888" 2>/dev/null || true)
  thpa="$t175len"
  [ -n "$t175" ] && [ -n "$thpa" ] || die "缺少令牌文件，先跑 --token"
  printf '%-14s %s\n' "入口" "结果"
  for pair in "175|https://box.hpa888.top/opsapi175|$t175" "hpa888|https://box.hpa888.top/opsapi|$thpa"; do
    IFS='|' read -r name base tok <<<"$pair"
    local h ov proc ports bad nolog
    h=$(code "$base/health" "$tok")
    ov=$(body "$base/overview" "$tok" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%s 核/负载%s/内存%s%%" % (d["cpu"]["cores"], d["load"]["load1"], d["memory"]["memUsedPercent"]))' 2>/dev/null || echo "解析失败")
    proc=$(body "$base/processes?sort=mem&limit=3" "$tok" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["count"])' 2>/dev/null || echo "?")
    ports=$(body "$base/ports" "$tok" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])' 2>/dev/null || echo "?")
    bad=$(code "$base/overview" "wrong-token")
    nolog=$(code "$base/logs?path=/etc/shadow" "$tok")
    printf '%s  health=%s  overview[%s]  进程%s 条  监听%s 条  错令牌=%s  读 /etc/shadow=%s\n' \
      "$name" "$h" "$ov" "$proc" "$ports" "$bad" "$nolog"
  done
}

code() { curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $2" "$1"; }
body() { curl -s -H "Authorization: Bearer $2" "$1"; }

case "${1:-}" in
  --host)
    case "${2:-}" in
      175) install_local ;;
      hpa888) install_remote ;;
      *) die "用法：--host 175|hpa888" ;;
    esac ;;
  --edge) install_edge ;;
  --token) issue_token "${2:?用法：--token 175|hpa888}" ;;
  --verify) verify ;;
  *) sed -n '2,20p' "$0" ;;
esac
