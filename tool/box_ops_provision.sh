#!/usr/bin/env bash
# box-ops 运维通道一键接入（给"没有域名/证书"的机器用，形状与 175 完全同构）。
#
# 目标机器上执行：本机回环起 rclone(WebDAV) + ttyd(终端) → 经 ssh 隧道挂到已有证书的边缘机
# → 边缘机加两条 location（复用它的证书与限速 zone）。外网只暴露 443，内部端口不出去。
#
#   box_ops_provision.sh --id 176                     一键接入（标识 176 → 前缀 /dav176、/term176）
#   box_ops_provision.sh --id 176 --dry-run            只体检 + 打印计划，不写任何东西
#   box_ops_provision.sh --id 176 --remove             拆掉这台机器在两侧的全部痕迹
#
# 设计要点（与手工接 175 时踩过的坑一一对应）：
#   * 边缘侧隧道是**独立 systemd 单元**，不往在用的隧道上加 -L（否则改端口会重启别人的隧道）；
#   * 口令**每台机器独立**、只写在目标机 /root/.secrets/（600）+ 边缘机 htpasswd（哈希），脚本全文不回显口令；
#   * 认证分两层：/dav 前缀靠本机 rclone 拦，/term 前缀靠边缘机 nginx 的 htpasswd 拦（ttyd 自身无凭据）；
#   * vhost 改动前备份、nginx -t 通过才 reload、不通过自动回滚；
#   * 端口自动挑空闲（本机与边缘机两侧都要空），避免和既有机器撞。
set -euo pipefail

EDGE_DEFAULT=hpa888
DOMAIN_DEFAULT=box.hpa888.top
USER_DEFAULT=boxops

# 文件通道 serve 的是整盘 `/`，而整盘里放着发布链的根材料（签名库 + 其口令 + 清单密钥）、
# 私钥、对面机器的口令。App 一行代码都没用到它们 —— 纯属"把 / 暴露出去"的副作用。
# 这里排除"密钥类路径"：目录级 + 名字级。**故意不含 `*.pem`**（/etc/ssl/certs 下全是
# 公共 CA 证书，按后缀一概排除等于把证书库藏起来，而它一点都不敏感）。
# 注意：黑名单不是安全边界（终端仍是 root shell），真边界是服务端代理 + 设备令牌。
# 已上线的两条通道用同一个清单，见 docs/server_ops_plugin_next_steps_291.md 的 C4。
RCLONE_EXCLUDE_ARGS='--exclude "/root/.secrets/**" --exclude "/root/.ssh/**" --exclude "/root/.hermes/**" --exclude "/root/.hermes-web-ui/**" --exclude "/root/.acme.sh/**" --exclude "/root/.docker/**" --exclude "/etc/shadow" --exclude "/etc/gshadow" --exclude "*.p12" --exclude "*.key" --exclude "*.env" --exclude "*.htpasswd" --exclude "*password*" --exclude "*secret*" --exclude "*token*" --exclude "id_rsa*" --exclude "id_ed25519*"' 
MIRROR=https://ghfast.top
RCLONE_VER=v1.71.2

ID=""
EDGE="$EDGE_DEFAULT"
DOMAIN="$DOMAIN_DEFAULT"
USERNAME="$USER_DEFAULT"
DAV_PORT=""
TERM_PORT=""
TARGET_HOST=""
MODE=provision

log()  { printf '[%s] %s\n' "$1" "$2"; }
die()  { printf '[停] %s\n' "$1" >&2; exit 1; }
sh_edge() { ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$EDGE" "$@"; }

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

可选参数：
  --edge <ssh别名>     边缘机（默认 hpa888，需已配好免密）
  --domain <域名>      边缘机上的对外域名（默认 box.hpa888.top）
  --user <用户名>      Basic 认证用户名（默认 boxops）
  --dav-port <端口>    WebDAV 回环端口（默认自动挑空闲）
  --term-port <端口>   终端回环端口（默认自动挑空闲）
  --target-host <地址> 边缘机 ssh 回本机用的地址（默认自动探测本机出网 IP）
  --dry-run            只体检 + 打印计划
  --remove             拆除（本机单元/凭据 + 边缘机 location/隧道/htpasswd）
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --edge) EDGE="${2:-}"; shift 2 ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --user) USERNAME="${2:-}"; shift 2 ;;
    --dav-port) DAV_PORT="${2:-}"; shift 2 ;;
    --term-port) TERM_PORT="${2:-}"; shift 2 ;;
    --target-host) TARGET_HOST="${2:-}"; shift 2 ;;
    --dry-run) MODE=dryrun; shift ;;
    --remove) MODE=remove; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1（--help 看用法）" ;;
  esac
done

[ -n "$ID" ] || die "必须给 --id（标识，例如 176；会变成 /dav<id> 与单元名前缀）"
case "$ID" in *[!a-zA-Z0-9_-]*) die "--id 只用字母数字下划线连字符：$ID" ;; esac

PREFIX="dav${ID}"
TERMPREFIX="term${ID}"
UNIT_DAV="box-ops${ID}-dav.service"
UNIT_TERM="box-ops${ID}-term.service"
UNIT_TUN="box-ops${ID}-tunnel.service"
PW_FILE="/root/.secrets/box-ops${ID}-webdav.password"
ENV_FILE="/root/.secrets/box-ops${ID}-rclone.env"
ROTATE=/usr/local/sbin/box-ops${ID}-rotate-credentials.sh

detect_public_ip() {  # 多源轮询：VPC/NAT 后面 ip route 拿到的是私网地址，不能当边缘机的 ssh 目标
  local ip
  for u in https://ifconfig.me/ip http://ip.3322.net https://api.ipify.org; do
    ip=$(curl -fsS --max-time 6 "$u" 2>/dev/null | tr -d '[:space:]' || true)
    case "$ip" in [0-9]*.[0-9]*.[0-9]*.[0-9]*) echo "$ip"; return 0 ;; esac
  done
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1
}

rand_chars() {  # $1=字符集 $2=长度；|| true 见下（SIGPIPE 会变成"脚本自杀"）
  tr -dc "$1" </dev/urandom 2>/dev/null | head -c "$2" || true
}

is_private_ip() {
  case "$1" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|127.*|169.254.*) return 0 ;;
    *) return 1 ;;
  esac
}

port_free_local() { ! ss -ltnH 2>/dev/null | awk '{print $4}' | grep -q ":${1}\$"; }
port_free_edge()  { [ -z "$(sh_edge "ss -ltnH 2>/dev/null | awk '{print \$4}' | grep ':${1}\$' || true")" ]; }

pick_port() {  # $1=起始  $2=结束  两侧都要空闲
  local p
  for p in $(seq "$1" "$2"); do
    if port_free_local "$p" && port_free_edge "$p"; then echo "$p"; return 0; fi
  done
  return 1
}

preflight() {
  [ "$(id -u)" = 0 ] || die "要用 root 跑（要写 /etc/systemd/system 与 /root/.secrets）"
  command -v systemctl >/dev/null || die "这台机器没有 systemd，本脚本不适用"
  command -v curl >/dev/null || die "缺 curl"
  case "$(uname -m)" in
    x86_64|amd64) ARCH_RCLONE=amd64; ARCH_TTYD=x86_64 ;;
    aarch64|arm64) ARCH_RCLONE=arm64; ARCH_TTYD=aarch64 ;;
    *) die "不认识的架构 $(uname -m)（rclone/ttyd 只有 amd64/arm64 预编译）" ;;
  esac
  sh_edge true >/dev/null 2>&1 || die "ssh $EDGE 不通（先配好免密，边缘机要用它加 location 与隧道）"
  if [ -z "$TARGET_HOST" ]; then
    TARGET_HOST=$(detect_public_ip)
    log 体检 "自动探测出网地址：${TARGET_HOST:-（没探到）}"
    is_private_ip "$TARGET_HOST" && die "探测到的是私网地址 $TARGET_HOST（机器在 NAT/VPC 后面），边缘机 ssh 不过去：用 --target-host 指定公网 IP 或能被边缘机解析的域名"
  else
    log 体检 "出网地址由 --target-host 指定：$TARGET_HOST"
  fi
  [ -n "$TARGET_HOST" ] || die "探测不到本机出网 IP，用 --target-host 指定"
  log 体检 "本机 $(hostname) · 架构 $(uname -m) · 出网地址 $TARGET_HOST"
  log 体检 "边缘机 $EDGE 连通；目标前缀 /$PREFIX/ 与 /$TERMPREFIX/"
}

install_bins() {
  if command -v rclone >/dev/null && command -v ttyd >/dev/null; then
    log 安装 "rclone/ttyd 都已在：$(rclone version | head -1) / $(ttyd --version)"
    return 0
  fi
  if [ "$MODE" = dryrun ]; then log 计划 "会装 rclone $RCLONE_VER ($ARCH_RCLONE) 与 ttyd 1.7.7 ($ARCH_TTYD) 到 /usr/local/bin"; return 0; fi
  cd /tmp
  if ! command -v rclone >/dev/null; then
    curl -fsSL -o rclone.zip "$MIRROR/https://github.com/rclone/rclone/releases/download/$RCLONE_VER/rclone-$RCLONE_VER-linux-$ARCH_RCLONE.zip"
    unzip -oq rclone.zip
    install -m755 "rclone-$RCLONE_VER-linux-$ARCH_RCLONE/rclone" /usr/local/bin/rclone
    rm -rf rclone.zip "rclone-$RCLONE_VER-linux-$ARCH_RCLONE"
  fi
  if ! command -v ttyd >/dev/null; then
    curl -fsSL -o /usr/local/bin/ttyd "$MIRROR/https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.$ARCH_TTYD"
    chmod 755 /usr/local/bin/ttyd
  fi
  log 安装 "rclone $(rclone version | head -1) / $(ttyd --version)"
}

write_creds() {
  mkdir -p /root/.secrets && chmod 700 /root/.secrets
  if [ -f "$PW_FILE" ]; then log 凭据 "沿用已有 $PW_FILE"; else
    if [ "$MODE" = dryrun ]; then log 计划 "会生成 40 位口令 → $PW_FILE（600，不回显）"; return 0; fi
    # 注意 || true：head 读满 40 字节就关管道，tr 会收到 SIGPIPE(141)，
    # 在 set -o pipefail 下整条管道算失败 —— 不加这个会把"生成口令"变成"脚本自杀"。
    rand_chars 'A-Za-z0-9' 40 > "$PW_FILE"
    chmod 600 "$PW_FILE"
    log 凭据 "已生成 40 位口令（只打印长度）→ $PW_FILE"
  fi
  if [ "$MODE" != dryrun ]; then
    printf 'RCLONE_USER=%s\nRCLONE_PASS=%s\n' "$USERNAME" "$(cat "$PW_FILE")" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  fi
}

write_units() {
  if [ "$MODE" = dryrun ]; then
    log 计划 "会写 $UNIT_DAV（rclone 回环 $DAV_PORT，--baseurl /$PREFIX）与 $UNIT_TERM（ttyd 回环 $TERM_PORT，-b /$TERMPREFIX）"
    return 0
  fi
  cat > "/etc/systemd/system/$UNIT_DAV" <<EOF
[Unit]
Description=box-ops $ID WebDAV (rclone, root, whole filesystem, loopback only)
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=$ENV_FILE
# --dir-cache-time 0：本地后端必须关缓存，否则刚上传的文件看不见
ExecStart=/usr/local/bin/rclone serve webdav / --addr 127.0.0.1:$DAV_PORT --baseurl /$PREFIX --dir-cache-time 0 --log-level INFO \
$RCLONE_EXCLUDE_ARGS
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  cat > "/etc/systemd/system/$UNIT_TERM" <<EOF
[Unit]
Description=box-ops $ID web terminal (ttyd, root, loopback only)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ttyd -p $TERM_PORT -i 127.0.0.1 -b /$TERMPREFIX -W -t fontSize=14 /bin/bash -l
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$UNIT_DAV" "$UNIT_TERM" >/dev/null
  log 本机 "$UNIT_DAV / $UNIT_TERM 已启用"
}

write_rotate_script() {
  [ "$MODE" = dryrun ] && { log 计划 "会写轮换脚本 $ROTATE（--check 自检两层认证）"; return 0; }
  cat > "$ROTATE" <<EOF
#!/usr/bin/env bash
# box-ops $ID 口令轮换（两层认证：本机 rclone 的 RCLONE_PASS + 边缘机 nginx 的 htpasswd）。
# --check 只自检；不带参数则轮换。轮换后 App 里这台机器要重新填一次口令。
set -euo pipefail
PW_FILE=$PW_FILE
ENV_FILE=$ENV_FILE
EDGE=$EDGE
HTPASSWD=/www/server/nginx/conf/box-ops${ID}.htpasswd
BASE=https://$DOMAIN
probe() {
  local p="\$1" dav term
  dav=\$(curl -s -o /dev/null -w '%{http_code}' -u "$USERNAME:\$p" -X PROPFIND -H 'Depth: 0' "\$BASE/$PREFIX/" || true)
  term=\$(curl -s -o /dev/null -w '%{http_code}' -u "$USERNAME:\$p" "\$BASE/$TERMPREFIX/" || true)
  printf 'dav=%s term=%s' "\$dav" "\$term"
}
if [ "\${1:-}" = "--check" ]; then
  printf '[检查] 当前口令：%s（期望 dav=207 term=200）\n' "\$(probe "\$(cat \$PW_FILE)")"
  printf '[检查] 错口令：%s（期望 dav=401 term=401）\n' "\$(probe not-the-password)"
  exit 0
fi
old=\$(cat "\$PW_FILE"); new=\$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 40 || true)
printf '%s\n' "\$new" > "\$PW_FILE"; chmod 600 "\$PW_FILE"
printf 'RCLONE_USER=$USERNAME\nRCLONE_PASS=%s\n' "\$new" > "\$ENV_FILE"; chmod 600 "\$ENV_FILE"
systemctl restart $UNIT_DAV
printf '$USERNAME:%s\n' "\$(printf '%s' "\$new" | openssl passwd -apr1 -stdin)" \\
  | ssh "\$EDGE" "umask 022; cat > \$HTPASSWD; chown root:www \$HTPASSWD; chmod 640 \$HTPASSWD"
ssh "\$EDGE" 'nginx -t >/dev/null 2>&1 && nginx -s reload'
sleep 2
printf '[轮换] 新口令：%s（期望 dav=207 term=200）\n' "\$(probe "\$new")"
printf '[轮换] 旧口令：%s（期望 dav=401 term=401）\n' "\$(probe "\$old")"
printf '[完成] 两层已一致。记得：App 里这台机器要重新填一次口令。\n'
EOF
  chmod 755 "$ROTATE"
  log 轮换 "$ROTATE 已写入"
}

edge_setup() {
  if [ "$MODE" = dryrun ]; then
    log 计划 "边缘机会：装隧道公钥 → 写 htpasswd → vhost 插 /$PREFIX/ 与 /$TERMPREFIX/ → 建 $UNIT_TUN → nginx -t + reload"
    return 0
  fi
  # 1) 隧道密钥：边缘机要有能 ssh 回本机的私钥（每台机器一把，互不影响）
  local key=/root/.ssh/id_target_${ID}
  if [ -z "$(sh_edge "test -f $key.pub && cat $key.pub" || true)" ]; then
    sh_edge "ssh-keygen -t ed25519 -N '' -C box-ops-$ID -f $key >/dev/null"
    log 隧道 "已在 $EDGE 生成专用密钥 $key"
  fi
  local pub; pub=$(sh_edge "cat $key.pub")
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
  touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
  if ! grep -qF "$pub" /root/.ssh/authorized_keys; then
    printf '%s\n' "$pub" >> /root/.ssh/authorized_keys
    log 隧道 "边缘机公钥已加入本机 authorized_keys"
  fi
  # 2) 边缘机连通性：隧道单元建之前先证一遍，别让 Restart=always 掩盖认证问题
  sh_edge "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 -i $key root@$TARGET_HOST true" \
    || die "边缘机用 $key ssh 不回本机（$TARGET_HOST）—— 检查本机 sshd 是否放行边缘机"
  log 隧道 "已验证 $EDGE → $TARGET_HOST 免密可达"

  # 3) htpasswd（口令经 stdin，不进 argv）
  printf '%s:%s\n' "$USERNAME" "$(printf '%s' "$(cat "$PW_FILE")" | openssl passwd -apr1 -stdin)" \
    | sh_edge "umask 022; cat > /www/server/nginx/conf/box-ops${ID}.htpasswd; chown root:www /www/server/nginx/conf/box-ops${ID}.htpasswd; chmod 640 /www/server/nginx/conf/box-ops${ID}.htpasswd"
  log 边缘 "htpasswd 已落地（640 root:www）"

  # 4) vhost 两条 location + 独立隧道单元（生成器经 stdin 送过去，参数在本地替换）
  sed -e "s/@ID@/$ID/g" -e "s/@DAVPORT@/$DAV_PORT/g" -e "s/@TERMPORT@/$TERM_PORT/g" \
      -e "s/@TARGETHOST@/$TARGET_HOST/g" <<'EDGESCRIPT' | sh_edge "cat > /tmp/box-ops-edge-$ID.py; python3 /tmp/box-ops-edge-$ID.py; rm -f /tmp/box-ops-edge-$ID.py"
#!/usr/bin/env python3
"""边缘机侧：vhost 两条 location（幂等 + 备份 + 语法不过自动回滚）+ 独立隧道单元。"""
import shutil, subprocess, sys
from pathlib import Path

ID, DAVPORT, TERMPORT, TARGET = "@ID@", "@DAVPORT@", "@TERMPORT@", "@TARGETHOST@"
VHOST = Path("/www/server/panel/vhost/nginx/box.hpa888.top.conf")
UNIT = Path(f"/etc/systemd/system/box-ops{ID}-tunnel.service")
HT = f"/www/server/nginx/conf/box-ops{ID}.htpasswd"


def sh(c):
    return subprocess.run(c, shell=True, capture_output=True, text=True)


BLOCK = f"""    # ---- box-ops {ID}：隧道单元 box-ops{ID}-tunnel.service 把目标机回环
    #      {DAVPORT}/{TERMPORT} 拉到本机回环，再由这里转发（复用本 vhost 的证书与限速 zone）
    location ^~ /dav{ID}/ {{
        limit_req zone=box_ops burst=60 nodelay;
        limit_req_status 429;
        client_max_body_size 0;
        client_body_timeout 3600s;
        send_timeout 3600s;
        proxy_pass http://127.0.0.1:{DAVPORT};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }}

    location ^~ /term{ID}/ {{
        auth_basic "box-ops{ID}";
        auth_basic_user_file {HT};
        limit_req zone=box_ops burst=60 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:{TERMPORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }}

"""

body = VHOST.read_text()
if f"/dav{ID}/" in body:
    print(f"[边缘] vhost 已含 /dav{ID}/，跳过插入")
else:
    shutil.copy2(VHOST, str(VHOST) + f".bak-boxops{ID}")
    marker = "    location = /hosts.json {"
    if marker not in body:
        sys.exit("[停] vhost 找不到插入锚点 location = /hosts.json")
    VHOST.write_text(body.replace(marker, BLOCK + marker, 1))
    print(f"[边缘] 已插入 /dav{ID}/ 与 /term{ID}/（备份 .bak-boxops{ID}）")

UNIT.write_text(f"""[Unit]
Description=box-ops{ID} tunnel: 127.0.0.1:{DAVPORT}/{TERMPORT} -> {TARGET}
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ssh -N -T -o BatchMode=yes -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no -i /root/.ssh/id_target_{ID} -L 127.0.0.1:{DAVPORT}:127.0.0.1:{DAVPORT} -L 127.0.0.1:{TERMPORT}:127.0.0.1:{TERMPORT} root@{TARGET}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
""")
sh("systemctl daemon-reload")
sh(f"systemctl enable --now box-ops{ID}-tunnel.service")
t = sh("nginx -t 2>&1")
print("[边缘] nginx -t " + (t.stdout + t.stderr).strip().replace("\\n", " | "))
if t.returncode != 0:
    shutil.copy2(str(VHOST) + f".bak-boxops{ID}", str(VHOST))
    sys.exit("[停] nginx 语法不通过，已回滚 vhost（隧道单元保留，可先 --remove）")
sh("nginx -s reload")
print("[边缘] nginx reload 完成")
EDGESCRIPT
  log 边缘 "vhost 与隧道就绪"
}

verify() {
  local pw; pw=$(cat "$PW_FILE")
  local base="https://$DOMAIN"
  local marker="/root/.box-ops-${ID}-marker"
  local nonce; nonce=$(rand_chars 'a-z0-9' 12)
  printf 'host=%s id=%s nonce=%s\n' "$(hostname)" "$ID" "$nonce" > "$marker"

  local dav_ok dav_bad term_ok term_bad ws_code got
  dav_ok=$(curl -s -o /dev/null -w '%{http_code}' -u "$USERNAME:$pw" -X PROPFIND -H 'Depth: 0' "$base/$PREFIX/")
  dav_bad=$(curl -s -o /dev/null -w '%{http_code}' -u "$USERNAME:wrong" -X PROPFIND -H 'Depth: 0' "$base/$PREFIX/")
  term_ok=$(curl -s -o /dev/null -w '%{http_code}' -u "$USERNAME:$pw" "$base/$TERMPREFIX/")
  term_bad=$(curl -s -o /dev/null -w '%{http_code}' -u "$USERNAME:wrong" "$base/$TERMPREFIX/")
  ws_code=$(curl -s --http1.1 -o /dev/null -w '%{http_code}' -N -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
      -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -u "$USERNAME:$pw" "$base/$TERMPREFIX/ws")
  # 内容判据：标记文件是在本机建的，能从外网经这条新前缀逐字节取回 = 这条通道确实通向本机的盘
  got=$(curl -s -u "$USERNAME:$pw" "$base/$PREFIX${marker}")
  local content_ok=false
  [ "$got" = "$(cat "$marker")" ] && content_ok=true

  printf '  文件通道 : 对=%s(期望207) 错=%s(期望401) | 内容判据=%s\n' "$dav_ok" "$dav_bad" "$content_ok"
  printf '  终端通道 : 对=%s(期望200) 错=%s(期望401) | WS 握手=%s(期望101)\n' "$term_ok" "$term_bad" "$ws_code"
  rm -f "$marker"

  [ "$dav_ok" = 207 ] && [ "$dav_bad" = 401 ] && [ "$term_ok" = 200 ] && [ "$term_bad" = 401 ] \
    && [ "$ws_code" = 101 ] && [ "$content_ok" = true ] \
    || die "自检没过（上面那两行就是实测值）—— 别对外宣布接好了"

  cat <<EOF

============= 接入完成 =============
  边缘入口（App 里填这两个）：
    WebDAV 地址  https://$DOMAIN/$PREFIX
    终端地址     https://$DOMAIN/$TERMPREFIX/
    用户名       $USERNAME
  口令：在 $PW_FILE（600，脚本不回显）。填进 App 时用 cat 读一次即可，
        或直接在 App 里重新设置口令走 $ROTATE 轮换。
  轮换：$ROTATE --check   （期望 dav=207 term=200）
  注意：WebDAV 根是 /，这台机器整盘对 App 开放 —— 它是谁的机器、放着什么秘密，心里要有数。
====================================
EOF
}

remove_all() {
  log 拆除 "本机：停用并删除 $UNIT_DAV / $UNIT_TERM / $ROTATE"
  systemctl disable --now "$UNIT_DAV" "$UNIT_TERM" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/$UNIT_DAV" "/etc/systemd/system/$UNIT_TERM" "$ROTATE"
  systemctl daemon-reload
  log 拆除 "边缘：删隧道单元/htpasswd、vhost 回滚到插之前"
  sh_edge "systemctl disable --now $UNIT_TUN >/dev/null 2>&1 || true; rm -f /etc/systemd/system/$UNIT_TUN; systemctl daemon-reload"
  sh_edge "rm -f /www/server/nginx/conf/box-ops${ID}.htpasswd /root/.ssh/id_target_${ID} /root/.ssh/id_target_${ID}.pub"
  sh_edge "V=/www/server/panel/vhost/nginx/box.hpa888.top.conf; if [ -f \$V.bak-boxops${ID} ]; then cp -p \$V.bak-boxops${ID} \$V; rm -f \$V.bak-boxops${ID}; nginx -t >/dev/null 2>&1 && nginx -s reload && echo '  vhost 已回滚 + reload'; else echo '  （没有备份文件，逐条手工删 /dav${ID}/ 与 /term${ID}/ 段）'; fi"
  # 边缘机的公钥也要从本机 authorized_keys 里摘掉：留着就是一把悬空的授权密钥
  # （密钥在边缘机上已被删，但 authorized_keys 里那行还会匹配同注释的任何密钥）。
  if [ -f /root/.ssh/authorized_keys ] && grep -q " box-ops-${ID}\$" /root/.ssh/authorized_keys; then
    grep -v " box-ops-${ID}\$" /root/.ssh/authorized_keys > /root/.ssh/authorized_keys.tmp
    mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    log 拆除 "已从 authorized_keys 摘掉 box-ops-${ID} 公钥"
  fi
  log 拆除 "本机凭据文件保留（要一并删：rm -f $PW_FILE $ENV_FILE；确认 App 里也已删掉这台机器）"
  log 完成 "已拆除 $ID"
}

main() {
  preflight
  if [ "$MODE" = remove ]; then remove_all; exit 0; fi
  # 幂等：重跑时端口必须沿用既有单元里的值。否则会重挑一个端口、把单元改了，
  # 而边缘机那条已建好的隧道还指着老端口 —— 表现为"单元 active 但外网 502/连不上"。
  if [ -f "/etc/systemd/system/$UNIT_DAV" ]; then
    [ -n "$DAV_PORT" ] || DAV_PORT=$(sed -n 's/.*--addr 127\.0\.0\.1:\([0-9]*\).*/\1/p' "/etc/systemd/system/$UNIT_DAV")
    [ -n "$TERM_PORT" ] || TERM_PORT=$(sed -n 's/.*-p \([0-9]*\) .*/\1/p' "/etc/systemd/system/$UNIT_TERM" 2>/dev/null || true)
    [ -n "$DAV_PORT" ] && [ -n "$TERM_PORT" ] && log 端口 "沿用既有单元：WebDAV=$DAV_PORT 终端=$TERM_PORT"
  fi
  [ -n "$DAV_PORT" ] || DAV_PORT=$(pick_port 8081 8099) || die "8081-8099 两侧都没空端口"
  [ -n "$TERM_PORT" ] || TERM_PORT=$(pick_port 7681 7699) || die "7681-7699 两侧都没空端口"
  log 端口 "WebDAV=$DAV_PORT 终端=$TERM_PORT（本机与边缘机两侧均已确认空闲）"
  install_bins
  write_creds
  write_units
  write_rotate_script
  edge_setup
  if [ "$MODE" = dryrun ]; then log 完成 "dry-run：以上都是计划，没有写任何东西"; exit 0; fi
  sleep 2
  verify
  # 文件与终端到此就通了。**指标是另一半**，而且信任方向相反（监控机要 ssh 进这台机器采 /proc），
  # 所以必须在监控机上执行另一个脚本 —— 否则新机器接进来只有文件与终端，服务器页里永远没有它。
  log 下一步 "主机指标（服务器页那一行）在监控机上补："
  log 下一步 "  box_ops_monitor_add.sh --id $ID --name '显示名' --ip \$(curl -s https://api.ipify.org) --ssh root@<这台机器的公网地址>"
}

main
