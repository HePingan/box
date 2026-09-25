#!/usr/bin/env bash
# box-ops：把一台机器接进「主机指标」这一半（A10）。
#
# 为什么需要单独一个脚本：文件通道与终端是**目标机**自己起的服务（接入脚本一条命令搞定），
# 而主机指标是**监控机**去 ssh 目标机采的 —— 信任方向相反，必须由监控机这一侧发起
# （要往目标机的 authorized_keys 里装监控机的公钥）。以前只做了前者，结果新机器接进来
# 只有文件与终端，服务器页里永远没有它。
#
# 用法（在监控机上执行，本仓库的常态是 175）：
#   box_ops_monitor_add.sh --id 176 --name "机房 C · 网关" --ip 1.2.3.4 --ssh root@1.2.3.4
#   box_ops_monitor_add.sh ... --dry-run          只打印计划，什么都不写
#   box_ops_monitor_add.sh --id 176 --remove      摘掉（含目标机 authorized_keys 里那行）
#   box_ops_monitor_add.sh ... --no-push          只写本地快照，不动边缘机上的线上文件
#
# 与运维通道的关系：用**独立密钥**（默认 /root/.ssh/id_box_monitor）与独立 ssh 别名
# （boxmon-<id>），不复用隧道密钥；目标机 authorized_keys 里的行带固定标记，便于幂等增删。
set -euo pipefail

COLLECTOR_DEFAULT=/opt/ops-monitor/gen_hosts_json.py
REPO_COLLECTOR=/root/box/tool/gen_hosts_json.py
KEY_DEFAULT=/root/.ssh/id_box_monitor
SSH_CONFIG=/root/.ssh/config
MARKER=box-ops-monitor

ID="" NAME="" IP="" SSH_TARGET=""
COLLECTOR="$COLLECTOR_DEFAULT"
KEY="$KEY_DEFAULT"
MODE=add
DRY=0
NO_PUSH=""

log() { printf '[%s] %s\n' "$1" "$2"; }
die() { printf '[停] %s\n' "$1" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf '  （dry-run）%s\n' "$*"; else "$@"; fi; }

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --ip) IP="${2:-}"; shift 2 ;;
    --ssh) SSH_TARGET="${2:-}"; shift 2 ;;
    --key) KEY="${2:-}"; shift 2 ;;
    --collector) COLLECTOR="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-push) NO_PUSH="--no-push"; shift ;;
    --remove) MODE=remove; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1（--help 看用法）" ;;
  esac
done

[ -n "$ID" ] || die "缺少 --id（稳定标识，插件按它做曲线历史的键）"
ALIAS="boxmon-$ID"

# ── 摘掉：倒着来（清单 → 别名 → 目标机公钥）─────────────────────────────
if [ "$MODE" = remove ]; then
  log 清单 "从 $COLLECTOR 摘掉 $ID"
  run python3 - "$COLLECTOR" "$ID" <<'PY'
import re, sys
path, mid = sys.argv[1], sys.argv[2]
src = open(path, encoding='utf-8').read()
new = re.sub(r'^\s*\{"id": "%s".*\n' % re.escape(mid), '', src, flags=re.M)
if new != src:
    open(path, 'w', encoding='utf-8').write(new)
    print(f"  已删除清单里的 {mid}")
else:
    print(f"  清单里没有 {mid}（无需删除）")
PY
  log 别名 "从 $SSH_CONFIG 摘掉 Host $ALIAS"
  run python3 - "$SSH_CONFIG" "$ALIAS" <<'PY'
import re, sys, pathlib
path, alias = sys.argv[1], sys.argv[2]
p = pathlib.Path(path)
if not p.exists():
    print('  没有 ssh config，跳过'); raise SystemExit
src = p.read_text(encoding='utf-8')
new = re.sub(r'\n*# >>> %s\n.*?# <<< %s\n' % (re.escape(alias), re.escape(alias)), '\n', src, flags=re.S)
if new != src:
    p.write_text(new, encoding='utf-8'); print(f'  已删除 {alias} 段')
else:
    print(f'  {alias} 段本来就不在')
PY
  if [ -n "$SSH_TARGET" ]; then
    # 按**公钥本体**（第二列）摘，不靠注释文字：注释是 ssh-keygen -C 定下的（只是个标签），
    # 拿 "$MARKER-$ID" 去匹配会一行都摘不掉却报告成功（第一版就是这么漏的）。
    BLOB=$(cut -d' ' -f2 "$KEY.pub" 2>/dev/null || true)
    log 公钥 "目标机 $SSH_TARGET 上摘掉监控机公钥（按指纹匹配）"
    if [ -z "$BLOB" ]; then
      log 警告 "本地没有 $KEY.pub，无法按指纹摘；手工删目标机 authorized_keys 里的监控机行"
    else
      run ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$SSH_TARGET" \
        "f=/root/.ssh/authorized_keys; if [ -f \$f ]; then before=\$(wc -l < \$f); grep -vF '$BLOB' \$f > \$f.tmp && mv \$f.tmp \$f; after=\$(wc -l < \$f); echo \"  已摘 \$((before-after)) 行\"; else echo '  没有 authorized_keys'; fi" \
        || log 警告 "目标机不可达，公钥没摘掉（手工删 $KEY.pub 对应的那行）"
    fi
  fi
  if [ "$DRY" = 0 ] && [ -f "$REPO_COLLECTOR" ] && ! diff -q "$COLLECTOR" "$REPO_COLLECTOR" >/dev/null 2>&1; then
    cp -p "$COLLECTOR" "$REPO_COLLECTOR"
    log 同步 "已把采集器同步回仓库副本 $REPO_COLLECTOR（记得 git 提交）"
  fi
  log 完成 "摘除完成；如需让线上快照立刻更新，等下一次 cron（每 2 分钟）或手工跑 $COLLECTOR"
  exit 0
fi

[ -n "$NAME" ] || die "缺少 --name（显示名）"
[ -n "$IP" ] || die "缺少 --ip（公网地址）"
[ -n "$SSH_TARGET" ] || die "缺少 --ssh（监控机到目标机的 ssh 目标，如 root@1.2.3.4）"
[ -f "$COLLECTOR" ] || die "找不到采集器 $COLLECTOR"

log 体检 "目标机 $SSH_TARGET 免密可达性"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$SSH_TARGET" true \
  || die "ssh $SSH_TARGET 不通：先确认免密（把本机公钥装到目标机，或先跑目标机上的 box-ops-provision）"
log 体检 "目标机可达；id=$ID 别名=$ALIAS 采集器=$COLLECTOR"

# ── 1. 监控机专用密钥 ────────────────────────────────────────────────
if [ ! -f "$KEY" ]; then
  log 密钥 "生成监控机专用密钥 $KEY"
  run ssh-keygen -t ed25519 -N '' -C "$MARKER" -f "$KEY" >/dev/null
else
  log 密钥 "已有 $KEY，沿用"
fi
PUB=$(cat "$KEY.pub" 2>/dev/null || { [ "$DRY" = 1 ] && echo '（dry-run 占位）' || die "取不到 $KEY.pub"; })

# ── 2. 目标机 authorized_keys（幂等，带标记）──────────────────────────
log 公钥 "把 $MARKER 公钥装到 $SSH_TARGET（幂等）"
run ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "umask 077; mkdir -p /root/.ssh; f=/root/.ssh/authorized_keys; touch \$f; grep -v '$MARKER' \$f > \$f.tmp || true; printf '%s\n' '$PUB' >> \$f.tmp; mv \$f.tmp \$f; chmod 600 \$f; echo '  authorized_keys 已更新（含 $MARKER 行）'"

# ── 3. 监控机的 ssh 别名 ─────────────────────────────────────────────
log 别名 "在 $SSH_CONFIG 写 Host $ALIAS（HostName=$IP，密钥=$KEY）"
run python3 - "$SSH_CONFIG" "$ALIAS" "$IP" "$KEY" <<'PY'
import pathlib, re, sys
path, alias, ip, key = sys.argv[1:5]
p = pathlib.Path(path)
src = p.read_text(encoding='utf-8') if p.exists() else ''
block = (
    f'# >>> {alias}\n'
    f'Host {alias}\n'
    f'  HostName {ip}\n'
    f'  User root\n'
    f'  IdentityFile {key}\n'
    f'  StrictHostKeyChecking no\n'
    f'  BatchMode yes\n'
    f'  ConnectTimeout 8\n'
    f'# <<< {alias}\n'
)
src = re.sub(r'# >>> %s\n.*?# <<< %s\n' % (re.escape(alias), re.escape(alias)), '', src, flags=re.S)
if src and not src.endswith('\n'):
    src += '\n'
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(src + block, encoding='utf-8')
print(f'  {alias} 段已写入（重复执行不会重复）')
PY

# 用新别名自检一次：别名不通 = 采集一定拿不到指标
if [ "$DRY" = 0 ]; then
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$ALIAS" true \
    || die "别名 $ALIAS 连不上（检查 $IP 是否公网可达、sshd 是否允许该密钥）"
  log 隧道 "别名 $ALIAS 自检通过"
fi

# ── 4. 采集器清单（幂等 upsert）─────────────────────────────────────
log 清单 "把 $ID 写进 $COLLECTOR 的 extra 段"
if [ "$DRY" = 1 ]; then
  printf '  （dry-run）会在 extra 段写入：{"id": "%s", "name": "%s", "ip": "%s", "ssh": "%s"}\n' "$ID" "$NAME" "$IP" "$ALIAS"
else
  python3 - "$COLLECTOR" "$ID" "$NAME" "$IP" "$ALIAS" <<'PY'
import re, sys
path, mid, name, ip, alias = sys.argv[1:6]
src = open(path, encoding='utf-8').read()
entry = ('    {"id": "%s", "name": "%s", "ip": "%s", "ssh": "%s"},\n'
         % (mid, name, ip, alias))
src = re.sub(r'^\s*\{"id": "%s".*\n' % re.escape(mid), '', src, flags=re.M)
# 标记必须在 `EXTRA_HOSTS = [` 与 `]` 之间：插到标记行的**紧后面**（也就是列表内部）。
# 第一版把内容插在 `# <<<` 之前，而标记当时包住了整条声明 —— 条目落在右括号之后，
# 采集器直接 IndentationError（自检当场抓到）。所以这里顺手把这条前置条件也验掉。
decl = src.find('EXTRA_HOSTS')
if decl < 0:
    sys.exit('[停] 采集器里没有 EXTRA_HOSTS 声明')
# 只在**声明之后**找标记：注释里出现过同名文字，从全文找会先命中注释那一处（第一版踩过）。
m = re.search(r'(# >>> extra machines[^\n]*\n)(.*?)(\s*# <<< extra machines)',
              src[decl:], flags=re.S)
if not m:
    sys.exit('[停] EXTRA_HOSTS 声明后面找不到 extra 段标记（# >>> extra machines）')
bracket = src.find('[', decl)
if bracket < 0 or bracket > decl + m.start(1):
    sys.exit('[停] 标记不在 EXTRA_HOSTS 的方括号内，先修采集器再跑本脚本')
pos = decl + m.end(1)
src = src[:pos] + entry + src[pos:]
open(path, 'w', encoding='utf-8').write(src)
print(f'  已写入/更新 {mid}')
PY
  # 仓库副本一起改，避免部署副本与源码漂移（改完记得提交）。
  if [ -f "$REPO_COLLECTOR" ] && ! diff -q "$COLLECTOR" "$REPO_COLLECTOR" >/dev/null 2>&1; then
    cp -p "$REPO_COLLECTOR" "$REPO_COLLECTOR.bak-monitor-add" 2>/dev/null || true
    cp -p "$COLLECTOR" "$REPO_COLLECTOR"
    log 同步 "已把采集器同步回仓库副本 $REPO_COLLECTOR（记得 git 提交）"
  fi
fi

# ── 5. 采一次并断言这台机器真出现在快照里 ────────────────────────────
OUT_TMP=$(mktemp /tmp/box-ops-hosts-XXXX.json)
if [ "$DRY" = 1 ]; then
  printf '  （dry-run）会跑：BOX_OPS_HOSTS_OUT=%s python3 %s %s\n' "$OUT_TMP" "$COLLECTOR" "$NO_PUSH"
else
  log 验证 "采一次，断言 hosts.json 里出现 $ID"
  BOX_OPS_HOSTS_OUT="$OUT_TMP" python3 "$COLLECTOR" $NO_PUSH || die "采集失败（看上面输出）"
  python3 - "$OUT_TMP" "$ID" <<'PY'
import json, sys
path, mid = sys.argv[1], sys.argv[2]
doc = json.load(open(path, encoding='utf-8'))
found = [h for h in doc['hosts'] if h['id'] == mid]
if not found:
    sys.exit(f'[停] 快照里没有 {mid}：{" ".join(h["id"] for h in doc["hosts"])}')
h = found[0]
print(f"  ✅ {mid} 已在快照里：online={h['online']} name={h['name']}")
if not h['online']:
    print('  ⚠️ 离线：指标没采到（ssh 别名通了不代表能跑采集脚本，看上面 [error]）')
PY
fi
rm -f "$OUT_TMP"
log 完成 "接入完成；线上快照由 cron（每 2 分钟）刷新，也可手工跑 $COLLECTOR"
