# 运维通道（box-ops）：整盘文件管理 + Web 终端

> 2026-09-25 部署并验证。目标是让 box 像宝塔APP 那样直接管服务器文件与终端，
> 且**不把宝塔面板 API key 放进客户端**（面板 API 权限等同 root，见下"为什么不用宝塔 API"）。

## 一、服务器端布局（hpa888 / 47.109.97.1）

| 组件 | 位置 | 说明 |
|---|---|---|
| WebDAV 后端 | `box-ops-dav.service` → `/usr/local/bin/rclone serve webdav / --addr 127.0.0.1:8081 --baseurl /dav --dir-cache-time 0` | **以 root 运行**、只监听回环、整盘为根 |
| Web 终端 | `box-ops-term.service` → `/usr/local/bin/ttyd -p 7681 -i 127.0.0.1 -b /term -W /bin/bash -l` | root shell，只监听回环 |
| 外网入口 | `box.hpa888.top` 的 `location ^~ /dav/` 与 `^~ /term/` | 复用已有 LE 证书；`^~` 前缀匹配**绕过该 vhost 里的"敏感文件/敏感目录"正则拦截**（整盘管理必须） |
| 限流 | nginx `box_ops` zone：`$binary_remote_addr` 20r/s burst=60 | 定义在 `/www/server/nginx/conf/nginx.conf` |
| 凭据 | `/root/.secrets/box-ops-webdav.password`（htpasswd 源）、`/root/.secrets/box-ops-rclone.env`（`RCLONE_USER`/`RCLONE_PASS`） | 令牌不进 argv（走 `EnvironmentFile`）；htpasswd 在 `/www/server/nginx/conf/box-ops.htpasswd`，需 `root:www 640`（600 会让 nginx worker 报 500） |

客户端侧（box 的「远端存储」插件）填：`baseUrl = https://box.hpa888.top/dav`，用户名 `boxops`。

## 二、为什么是 rclone，不是 nginx 原生 DAV

先用主 nginx 的 `dav_methods` 做过一版，能在**根目录**跑通，但连撞三个硬坑（均为实测）：

| 现象 | 原因 | 结论 |
|---|---|---|
| `GET /dav/root/.ssh/config` → 403 | 主 nginx worker 是 `www` 用户，读不到 0700 目录 | "整个 /" 必须由 root 身份的进程提供 |
| `MKCOL` / `DELETE` 目录（URI 不带尾斜杠）→ 409 | nginx 原生 DAV 把"集合 URI 必须以 / 结尾"当硬要求；box 客户端 `createDirectory` 不带尾斜杠 → 新建文件夹静默失败 | 靠 `if ($request_method = MKCOL)` + `if (-d $request_filename)` 两条 rewrite 可救 |
| `MOVE` 目录（目标不存在）→ 409/400 | 目标还不存在，`-d` 判断不了，无法补斜杠 | **无解** |
| `MOVE` 带绝对 URL Destination → 400 | nginx 只在 Destination 的端口/方案与监听端口一致时才接受；客户端按 RFC 发的是 `https://域名/...` | 得在 nginx 里 map 改写 Destination |
| 目录重定向 → `Location: http://域名:8081/...` | 绝对重定向带上了内网监听端口，客户端跟着跳就超时 | 得关 `absolute_redirect`/`port_in_redirect` |

换成 rclone 的 WebDAV 后，`--baseurl /dav` 直接提供正确前缀的 href，上面五条全部消失。
第二条还有一个**必须保留**的配置：`--dir-cache-time 0`，否则本地后端会缓存目录列表，
刚上传的文件在文件管理器里"看不见"。

## 三、已知差异（不是说服务端合规，是记录实情）

- **`Overwrite: F` 不被实现**：rclone 在目标已存在时仍返回 201 并覆盖。覆盖保护实际由
  服务层 `remote_storage_service.dart` 的 `renameEntry` / `moveEntry` 先 `exists(target)`
  再抛 `conflict` 承担（**竞态窗口仍在**）。live 测试断言的是 `exists()` 预检原语本身。
- **HEAD 集合（无尾斜杠）返回 405**：客户端 `exists()` 已内置退回 `PROPFIND Depth: 0`，实测正常。
- **权限等价 root**：`/etc/shadow`、`/root` 全树可读可写。凭据泄露 = 整机失守，
  所以只走 HTTPS、端点带 `limit_req`，凭据不进 APK 仓库、任何时候都不写进代码。
- 宝塔面板自带 API（`/www/server/panel/config/api.json`，`open:true`）**没有使用**：
  `limit_addr` 为空时它对任何 IP 都回"IP校验失败"（`class/common.py` 的 `is_api_limit_ip`），
  且其权限涵盖写任意文件、执行命令；把 key 放进客户端等于把 root 交出去。

## 四、验证

```bash
# 用仓库里那个真客户端（DioWebdavTransport，就是「远端存储」的生产传输层）打真服务端
export PATH=/opt/flutter-3.44.6/bin:$PATH
OPS_BASE=https://box.hpa888.top/dav OPS_USER=boxops OPS_PASS=... \
  flutter test --tags live test/features/extensions/remote_storage/ops_webdav_live_test.dart

# 终端 WebSocket 握手（公网，必须走 HTTP/1.1）
curl -s --http1.1 -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -u boxops:$PASS https://box.hpa888.top/term/ws | head -1   # 期望 101
```

回归口径：`box.hpa888.top` 的 OTA 端点（`/monitors.json` 带 token 200、无 token 404、
`/health` 200、`/admin` 200、`/docs` 404）在改 nginx 后逐条复测过。

## 五、主机指标快照 hosts.json（运维插件「服务器」页的数据源）

链路与 `monitors.json` 完全相同（采集 → 边缘机静态文件 → nginx 带 token）：

```
175: /opt/ops-monitor/gen_hosts_json.py   ← cron */2（/etc/cron.d/box-ops-monitor，日志 /var/log/ops-monitor.log）
        │ 本机读 /proc + statvfs；远端用 `ssh hpa888 python3 - --collect` 把同一份脚本喂过去执行
        ▼ ssh 推送（.tmp → mv 原子）
hpa888: /home/update-server/public/hosts.json
        ▼ nginx `location = /hosts.json`（与 monitors.json 同一把共享令牌）
https://box.hpa888.top/hosts.json?token=...
```

- 源在仓库 `tool/gen_hosts_json.py`，改完要 `scp` 到 175 的 `/opt/ops-monitor/`。
- 字段：`id/name/ip/online` + `cpuPercent/cpuCount/memTotal|UsedBytes/memPercent/
  swap*/diskTotal|UsedBytes/diskPercent/load1|5|15/uptimeSeconds/netRx|TxBytesPerSec`。
- 单台 SSH 采不到 → 那台 `online:false`（其余字段缺失），**不让一台机器拖垮整份快照**；
  离线不返回非 0 退出码（关机是常态，页面自己显示离线）。
- CPU 与网络速率靠两次采样（间隔 0.4s）求差，所以脚本自身耗时约 1 秒。

## 六、待办

1. **175 接入**：175 没有 443 也没有证书，计划用 SSH 隧道把 175 的回环 DAV 挂到 hpa888，
   再用 `^~ /dav175/` 暴露（不要新域名/新证书）。
2. **凭据轮换**：改 `/root/.secrets/box-ops-webdav.password` + htpasswd + `systemctl restart box-ops-dav`。
3. **插件 `server_ops`**：首页一个入口，页签「服务器（状态）/ 文件 / 终端」——
   文件页直接复用「远端存储」，状态页读主机指标快照，终端页用 `webview_flutter` 打开 `/term/`
   （`onHttpAuthRequest` 处理 Basic 认证）。

## 七、凭据轮换（C1 立即档）

口令分散在**两个认证层**，漏改一处就会出现「文件通了、终端 401」这种半失效状态：

| 位置 | 谁在用它 | 作用 |
|---|---|---|
| `/root/.secrets/box-ops-rclone.env`（`RCLONE_USER` / `RCLONE_PASS`） | rclone 守护 `box-ops-dav` | 外网 `/dav/` 的 Basic 认证（nginx 的 `/dav/` location 本身**不做认证**） |
| `/www/server/nginx/conf/box-ops.htpasswd` | nginx | `/term/` 的 Basic 认证（ttyd 以 `-W` 启动，自身没有凭据） |
| `/root/.secrets/box-ops-webdav.password` | 运维记录（hpa888 与本机 175 各一份） | **手输时的来源**；290 起安装包不再注入任何口令（C1 中期档），所以它只用于轮换后告知/手工核对 |

一次改三处 + 重启 + 自检的脚本：`/usr/local/sbin/box-ops-rotate-credentials.sh`

```bash
/usr/local/sbin/box-ops-rotate-credentials.sh --check   # 只自检当前口令（期望 dav=207 term=200）
/usr/local/sbin/box-ops-rotate-credentials.sh           # 轮换：生成新口令 → 改写三处 → 重启 → 自检
```

脚本末尾会自己打新旧口令的双通道状态码（新：`dav=207 term=200`；旧：`401/401`），
旧口令仍可用就直接以退出码 2 报警 —— 不要靠"看起来成功了"。

**轮换会让所有已发布 APK 里的旧口令立即失效**（这正是轮换的意义）：
轮换后必须①把新口令同步到 175 的 `/root/.secrets/box-ops-webdav.password`，
②紧跟一次发版。否则 App 的文件/终端页会 401。

## 八、第二台机器（175）接入 —— 服务端半边（2026-09-25）

### 为什么是这个形状

175 没有 443、也没有证书，但**两件东西都已经有了**：它自己的 nginx（宝塔）跑着别的站点，
以及 hpa888 上一条既有隧道（`searxng-tunnel.service`，`ssh -L` 把 175 的回环端口拉到 hpa888 回环）。
所以接入方式不是"给 175 申请证书/加域名"，而是**复用边缘机的证书与限速 zone**，
照抄 Kuma 那条通路的形态 —— 与方案 B1 里写的判断一致。

### 服务端落地了什么

| 位置 | 组件 | 说明 |
|---|---|---|
| 175 | `box-ops175-dav.service` | `rclone serve webdav / --addr 127.0.0.1:8083 --baseurl /dav175 --dir-cache-time 0`，root，整盘为根 |
| 175 | `box-ops175-term.service` | `ttyd -p 7683 -i 127.0.0.1 -b /term175 -W -t fontSize=14 /bin/bash -l`，root shell |
| 175 | `/root/.secrets/box-ops175-webdav.password`（600） | 这台机器口令的事实源（**与 hpa888 的互相独立**） |
| 175 | `/root/.secrets/box-ops175-rclone.env`（600） | `RCLONE_USER`/`RCLONE_PASS`，走 `EnvironmentFile` 不进 argv |
| hpa888 | `box-ops175-tunnel.service` | `ssh -N -T … -L 127.0.0.1:8083:… -L 127.0.0.1:7683:… root@175`，**独立单元**（改它不会重启 Kuma/SearXNG 那条在用的隧道） |
| hpa888 | `/www/server/nginx/conf/box-ops175.htpasswd`（root:www 640） | 只管 `/term175/`（ttyd 自身无凭据） |
| hpa888 | vhost 两条 location | `^~ /dav175/` → `127.0.0.1:8083`（认证由 175 的 rclone 拦，与 `/dav/` 一致）；`^~ /term175/` → `127.0.0.1:7683`（认证由 nginx 拦，与 `/term/` 一致） |

**口令两台互相独立是刻意的**：175 是构建机，放着发布密钥、GitHub 私钥、全部 `.secrets`，
它的口令泄露的后果与 hpa888 不同，不该绑在一根绳上。轮换脚本
`175:/usr/local/sbin/box-ops175-rotate-credentials.sh`（`--check` 只自检：期望
`dav=207 term=200`，错口令 `dav=401 term=401`），一次改两层（175 的 rclone env + hpa888 的 htpasswd）
并各自自检。

### 实测（外网经 `box.hpa888.top`）

```
PROPFIND /dav175/ 口令对  207      口令错 401      用 hpa888 的口令打 /dav175/ 也 401（两层独立）
判据：/opt/ops-monitor 只在 175 有 —— 经 /dav175/ 207，经 /dav/（hpa888）404   ← 证明是两台不同的盘
下载 /dav175/opt/ops-monitor/hosts.json 与本机文件逐字节一致（1105 字节）
PUT /dav175/tmp/*.txt → 201，读回一致，DELETE → 204
GET /term175/ 200 / 口令错 401 / WS 握手 101（必须 HTTP/1.1）
无回归：/dav/ 207、/term/ 200
```

### 注意

- **ttyd 自身没有凭据**（两台机器都一样），所以"终端口令"实际只由 nginx 那一层拦；
  直连回环时 ttyd 对任何口令都回 200 —— 这不是漏洞，但**别把它当成"认证通过了"**。
- 175 的 DAV 根是 `/`：**整个构建机对 App 开放**，包括 `/root/.secrets/`（发布密钥、GitHub 私钥）。
  这是用户明确要求的能力（"整个"），但换机/换人时必须先轮换口令，并把"175 口令 = 构建链"写进心里。
- 客户端（多服务器模型）见 `docs/server_ops_plugin_next_steps_289.md` 的 B1。

## 九、新机器一键接入：`box_ops_provision.sh`（2026-09-25）

175 是手工接的（装 rclone/ttyd、写单元、建凭据、边缘加 location + 隧道、轮换脚本）。
这一节把它脚本化：**目标机器上一条命令**，两侧全部到位并自检。

```bash
# 在新机器上（root，需要能免密 ssh 到边缘机 hpa888）
scp tool/box_ops_provision.sh newhost:/tmp/            # 或者从仓库拉
ssh newhost 'bash /tmp/box_ops_provision.sh --id 176'  # 标识 176 → 前缀 /dav176、/term176
# 先看不写：--id 176 --dry-run
# 拆除：    --id 176 --remove
```

脚本做的事（标识 `X`）：

| 侧 | 动作 |
|---|---|
| 目标机 | 按架构装 rclone（v1.71.2，amd64/arm64）+ ttyd（1.7.7）；生成 40 位口令 → `/root/.secrets/box-opsX-webdav.password`（600）+ rclone env；写 `box-opsX-dav.service`（回环，`--baseurl /davX`）与 `box-opsX-term.service`（回环，`-b /termX`）；写 `/usr/local/sbin/box-opsX-rotate-credentials.sh` |
| 边缘机 | 生成**每台机器一把**的隧道密钥 `id_target_X`，把公钥加到目标机 `authorized_keys`；写 htpasswd（640 root:www）；vhost 幂等插入 `/davX/` 与 `/termX/`（改前备份、`nginx -t` 不过自动回滚）；建**独立**隧道单元 `box-opsX-tunnel.service` 并启动 |
| 自检 | 对=207/200、错=401/401、WS 握手=101，外加**内容判据**：在本机建一个标记文件，从外网经新前缀取回并与本地逐字节比对 —— 证明这条通道确实通向本机的盘（只看状态码分不出两台机器） |

踩过并已修的四个坑（都在脚本里留了注释）：

1. **`set -o pipefail` + `tr </dev/urandom | head -c N` = 脚本自杀**：`head` 读满就关管道，
   `tr` 收到 SIGPIPE(141)，整条管道算失败。生成口令与 nonce 的行必须 `|| true`。
   （同一个坑也埋在 175 的轮换脚本里，`--check` 不走那条路所以当时没暴露。）
2. **端口幂等**：重跑时必须沿用既有单元里的端口，否则会重挑一个端口写进单元，
   而边缘机那条已建好的隧道还指着老端口 —— 表现为"单元 active 但外网连不上"。
3. **出网地址不等于公网地址**：腾讯云 VPC 里 `ip route get` 给的是 `10.1.0.15`，
   边缘机 ssh 不过去。脚本改成多源探测公网 IP（ifconfig.me → ip.3322.net → ipify），
   探到私网地址直接停并要求 `--target-host`。
4. **`--remove` 要摘 `authorized_keys`**：否则边缘机的公钥行留在目标机上，
   是一把悬空的授权密钥。

另：`--remove` 会回滚 vhost（用插入前的备份）、删隧道单元/htpasswd/密钥/单元/轮换脚本，
但**保留凭据文件**并提示手工删（避免手滑把别人那台的凭据带走）。

## 十、客户端：多服务器模型（291，B1 下半）

「服务器运维」插件从"一台机器的连接"改成**服务器列表 + 当前机器切换器**：

- 设置里每台机器一条连接：名称 / WebDAV 地址 / 用户名 / 终端地址 / 口令；支持新增、编辑、删除
  （**最后一台不许删**）。AppBar 上的切换器切换"当前机器"，选择持久化，
  文件页 / 终端页 / 测试连接三联都跟着当前机器走；服务器页给与当前机器同名的那一行打「当前」标记
  （按 `snapshotId` 对应 `hosts.json` 里的机器 id）。
- **口令按服务器分键**存在本机加密存储（`serverOps.dav.password.<id>`）：两台机器口令不同是常态
  （175 是运维机），共用一个键等于"改一台把另一台也改了"。口令永不写进 SharedPreferences、永不进安装包。
- **老用户升级无缝**：289/290 的单服务器配置（`serverOps.dav.baseUrl/user/terminalUrl` + 老口令键，
  含 289 那份明文）会一次性折成一台 `hpa888`，口令搬到分服务器键，四个老键全部清掉 ——
  不会要求重新输口令。

### 想加一台机器，地址该填什么

| 你手上的机器 | 填什么 |
|---|---|
| 有域名 + 受信证书 | `https://域名/dav` 与 `https://域名/term/`，直接填 ✅ |
| 没有域名/证书 | **先跑 `tool/box_ops_provision.sh --id X`**（见第九节），然后填 `https://box.hpa888.top/davX` 与 `.../termX/` |
| `http://IP:端口` | ❌ 连不上：本 App 的网络安全配置只对 `localhost/127.0.0.1` 放开明文（`android/app/src/main/res/xml/network_security_config.xml`），公网明文一律被系统掐断 |
| `https://IP:端口` + 自签证书 | ❌ 连不上：证书不受信时 WebDAV 与终端都会失败，得先在系统里信任那张证书 |

端口不用记也不用填：外网只暴露 443，内部回环端口由边缘机转发。

## 十一、通道收口（C4）：密钥类路径不再可达

两条通道 serve 的是整盘 `/`。整盘里放着发布链的根材料 —— 实测（只读探测，2026-09-25）：

| 通道 | 路径 | 收口前 | 收口后 |
|---|---|---|---|
| `/dav175` | `root/.secrets/box-release.p12`（**APK 发布签名库**，4402 B） | 200 | **404** |
| `/dav175` | `root/.secrets/box-release-keystore-password`、`box-update-manifest-sign-secret` | 200 | **404** |
| `/dav175` | `root/.secrets/box-ops-webdav.password`（**主服务端那只口令**） | 200 | **404** |
| `/dav175` | `root/.ssh/hermes-target`（**连主服务端的私钥**）、`root/.ssh/id_ed25519` | 200 | **404** |
| `/dav` | `root/.secrets/box-update-server.admin_password` / `.env` / 清单密钥 | 200 | **404** |
| `/dav` | `etc/shadow` | 200 | **404** |

含义：收口前任一口令都能下载签名库 + 库口令 + 清单密钥 → **签一个假 APK 发给全部用户**（客户端验签会通过）。

现在的过滤（两条单元各 17 条，接入脚本同步生成）：

```
/root/.secrets/**  /root/.ssh/**  /root/.hermes/**  /root/.hermes-web-ui/**
/root/.acme.sh/**  /root/.docker/**  /etc/shadow  /etc/gshadow
*.p12  *.key  *.env  *.htpasswd  *password*  *secret*  *token*  id_rsa*  id_ed25519*
```

**故意不含 `*.pem`**：`/etc/ssl/certs` 下全是公共 CA 证书，按后缀排除等于把证书库藏起来（而它不敏感）。

改动方式与验收：`/root/.hermes/cache/scratch/apply_ops_filters.py <unit> <baseurl> <port>`（备份单元 →
重写 ExecStart → daemon-reload → restart → 18 条密钥路径期望 404、对照期望 200）；
live 守卫 `test/features/extensions/server_ops/ops_webdav_denylist_live_test.dart`（两条通道各 10/10）。

**边界（别把黑名单当边界）**：终端仍是 root shell，有口令的人 `cat` 一下就回来了。它收掉的是
"文件通道 + 手机缓存/备份/截屏"这一类的意外暴露。真正的边界是服务端代理 + 设备令牌（方案 C2）。

顺带记录：rclone 本地后端**不跟随符号链接**，`/etc/os-release` 这类软链一律 404
（直取 `/usr/lib/os-release` 才是 200）。这是既有行为，不是收口收过头。

## 十二、新机器接入的"指标"这一半（A10）

文件与终端由**目标机**自己起（`box_ops_provision.sh`，一条命令）；主机指标则由**监控机**去 ssh
目标机采 —— 信任方向相反，必须在监控机上跑：

```bash
box_ops_monitor_add.sh --id 176 --name "机房 C · 网关" --ip 1.2.3.4 --ssh root@1.2.3.4
box_ops_monitor_add.sh --id 176 --ssh root@1.2.3.4 --remove     # 摘掉（含目标机 authorized_keys 里那行）
```

它做四件幂等的事：装监控机专用钥匙（`/root/.ssh/id_box_monitor`）→ 写目标机 `authorized_keys`
（带标记）→ 写 `boxmon-<id>` ssh 别名 → upsert 采集器的额外机器清单（部署副本 + 仓库副本同步），
最后采一次并**断言该 id 出现在快照里**（截图级验收，而不是"应该好了"）。

采集器侧的新接缝：`EXTRA_HOSTS`（标记内由脚本维护）、`BOX_OPS_HOSTS_OUT`（输出可重定向）、
`--no-push`（自检不碰线上快照）。

---

## 十三、只读运维 API（C2 只读档；同时是 C1 凭据根治档的载体）

### 为什么有它

WebDAV 拿不到 unix 权限/属主，也拿不到进程、服务、日志、端口、目录占用 ——
宝塔式管理里真正好用的那半。而它还有第二个身份：**凭据模型的根治档**。
以前只有一条通道、一个口令，那口令等同 root（整盘读写 + root shell）；现在 App 拆成
「文件通道（口令）」+「只读接口（**可撤销的设备令牌**）」——令牌泄了单独撤，不必动通道口令。

### 形状（与既有两条通道同一套约定：服务只绑回环，外网入口由边缘机 nginx 代理）

| 机器 | 服务监听 | 公网入口 | 解释器 |
|---|---|---|---|
| hpa888 | 127.0.0.1:8095 | `https://box.hpa888.top/opsapi/` | `/root/anaconda3/bin/python3`（3.11；**系统 python3 只有 3.6**） |
| 175 | 127.0.0.1:8095 | `https://box.hpa888.top/opsapi175/` | `/usr/bin/python3`（3.11） |

175 那条经**既有隧道**多转一路：边缘机 `127.0.0.1:8096` → `175:8095`
（`box-ops175-tunnel.service` 里加了 `-L 127.0.0.1:8096:127.0.0.1:8095`）。
nginx 两条 location 用 `proxy_pass .../;`（带尾斜杠）= 剥掉 `/opsapi*` 前缀，API 收到的是 `/overview` 这种干净路径。
服务以 root 跑（`journalctl` 读别家单元日志、`ss -p` 读进程名、`lastb` 读 /var/log/btmp 都要权限），
风险面由「白名单只读动作 + 设备令牌 + 全量审计」承担。

### 部署与运维（一条脚本）

```bash
tool/ops_api/deploy_box_ops_api.sh --host 175      # 或 --host hpa888
tool/ops_api/deploy_box_ops_api.sh --edge          # 边缘机：两条 location + 隧道加一路
tool/ops_api/deploy_box_ops_api.sh --token 175     # 签发/轮换设备令牌（写 .secrets，只打印长度与哈希）
tool/ops_api/deploy_box_ops_api.sh --verify        # 端到端：两条公网入口 + 拒绝路径
python3 tool/ops_api/box_ops_api.py selftest       # 20 项自检（正常 + 拒绝 + 撤销 + 审计），不碰线上文件
```

### 动作（全部只读；**没有写动作、没有 shell**）

| 动作 | 说明 |
|---|---|
| `health` | 活着没、版本 |
| `overview` | 发行版/内核/uptime/负载/CPU/内存/Swap/各挂载点用量 |
| `processes?sort=cpu\|mem&limit=N` | 前 N 个进程（pid/user/cpu%/mem%/rss/已跑时长/命令行） |
| `services?q=&limit=` | systemd 服务清单（active/sub/enabled/描述） |
| `service?unit=nginx.service&lines=20` | 单个服务详情 + journal 尾巴 |
| `logs?path=/var/log/x&lines=N` | 白名单目录下的文件 tail（从尾部读，不整文件载入） |
| `ports` | `ss -ltnp` 监听端口与进程 |
| `diskusage?path=/var/log` | `du -x --max-depth=1` |
| `sessions` | `last` / `lastb` 最近登录与失败登录 |
| `audit?limit=N` | 审计流水（**要 admin 令牌**） |

### 硬上限与拒绝路径（都实测过）

* 行数 ≤ 500、进程 ≤ 200、服务 ≤ 400、超时 ≤ 15 秒、响应 ≤ 256 KB；
* 限流：每个令牌 10 秒内 60 次，超了 429；
* 日志只允许 `/var/log`、`/www/wwwlogs`、`/home/update-server/logs`、`/tmp` 下的**文件**，
  且显式拒绝含 `..` 的路径（`/etc/shadow` → 403）；
* `du` 拒绝 `/root/.secrets`、`/root/.ssh`、`/root/.hermes`、`/proc`、`/sys`、`/dev`；
* unit 名走正则且必须是 systemd 里真实存在的单元；
* **没有 shell**：每条命令都是固定 argv 模板 + 校验过的参数，绝不拼字符串；
* 未知动作 404、无/错令牌 401 —— **被拒绝的调用同样进审计**（这才是审计的意义）。

### 设备令牌模型

* 文件：`/root/.secrets/box-ops-api-tokens.json`（只存 `sha256` 哈希 + `label` + `admin` + 创建时间，chmod 600）；
* 比较用 `hmac.compare_digest`；签发 `box_ops_api.py token issue --label <名字> [--admin]`；
* 撤销 `box_ops_api.py token revoke --label <名字>` → **立刻 401**（无需重启服务）；
* `admin` 令牌才能读审计；普通令牌读 → 403；
* 令牌只存在 App 的加密存储里（键 `serverOps.api.token.<机器id>`），与口令**分表** ——
  撤销令牌不影响文件/终端，改口令也不影响系统页。

### 审计

`/var/log/box-ops-api/audit.jsonl`（超过 5 MB 轮转一份 `.1`），一行一条：
`at / action / params / token(=label) / ip / status / ms / note`。
**不记凭据**：参数里只有动作参数（如 unit、path、limit），没有口令、没有令牌。

### 有意不做（写清楚，免得下次又被当成"漏了"）

* 服务启停、解压、改权限这类**写动作**：等审计与令牌先跑一段时间再说；
* 任意命令执行 / 伪终端：那是既有 ttyd 终端的事，别在这里开口子；
* "读任意文件当日志"：只白名单目录，不做"整盘当日志"；
* 把审计开放给普通令牌（跨设备可见的活动记录只给 admin）。

### 与 WebDAV 通道的关系

两条通道**互相独立、可以只开一条**：只读接口不需要 DAV 口令，DAV 也不需要令牌。
客户端两套凭据分别按机器存（口令 `serverOps.dav.password.<id>`、令牌 `serverOps.api.token.<id>`），
设置页一行能看出这台"口令配没配 / 系统页令牌配没配"。

## 十四、写档：服务启停 / 建目录 / 改权限 / 改属主 / 解压（C2 写档）

C2 拆成两档做：**先只读**（十三节），**再写**。顺序不是随便定的 —— 写动作只有在
"令牌可撤销 + 每次调用有审计"这两件事先立住之后，才敢从手机上按下去；反过来先做写档，
出事时你连"谁在什么时候改了什么"都答不上来。

### 14.1 凭据：作用域在令牌上，不在地址上

同一个只读接口，令牌分三种作用域（可叠加）：

| 作用域 | 能做什么 | 用在哪 |
|---|---|---|
| （无） | 只读动作：概览 / 进程 / 服务状态 / 端口 / 目录占用 / 登录 | "只想看"的令牌 |
| `admin` | 额外能读**服务端审计**（谁、从哪来、调了什么、成不成） | 同上 |
| `write` | 额外能做**写动作**（下面 5 个） | App 的两把 `box-app-*` 都带 |

签发与撤销（服务端）：

```bash
box-ops-api.py token issue  --label box-app-175 --admin --write   # 带写权限
box-ops-api.py token revoke --label box-app-175                    # 立即失效
```

**把写关掉**不需要改代码：重签一条不带 `--write` 的令牌，把 App 里那格替换掉即可；
`GET /capabilities` 会如实回 `write:false`，界面上的启停按钮随之变灰（不是"点了才 403"）。
服务端只存令牌的 sha256；令牌只进请求头，**不进错误文案、不进审计**。

### 14.2 五个动作与它们的边界

| 动作 | 参数 | 服务端做的事 |
|---|---|---|
| `service` | `unit` + `op ∈ {start,stop,restart,reload,enable,disable}` | 只调 `systemctl`，单元名要过正则且**真实存在** |
| `mkdir` | `path` | `os.mkdir`（不建父级，已存在就 400） |
| `chmod` | `path` + `mode`（八进制）+ `recursive?` | 校验八进制位数，拒绝 `0000`（那是"把自己锁死"） |
| `chown` | `path` + `owner?` + `group?` | 属主/属组必须真在 `/etc/passwd`、`/etc/group` 里（数字 uid 也认） |
| `extract` | `path` + `dest?`（默认压缩包所在目录） | zip / tar / tar.gz / tgz / tar.bz2 / tar.xz / gz，纯标准库 |

写动作**没有 shell、没有任意命令**：动作是固定的几个，参数逐个校验，argv 是列表不是字符串。

### 14.3 五道闸门（顺序就是拒绝的顺序）

1. **作用域**：没有 `write` 的令牌，写动作一律 403（文案直说"要用 --write 重签"，不提令牌本身）；
2. **参数**：路径必须绝对、不许 `..`；单元名正则；八进制位数；属主存在性；
3. **保护名单**（`WRITE_DENY_PREFIXES`）：`/proc`、`/sys`、`/dev`、`/boot`、
   `/root/.secrets`、`/root/.ssh`、`/root/.hermes`、`/var/log/box-ops-api`、
   本服务自己的文件（`/usr/local/sbin/box-ops-api.py`、它的 unit、令牌文件）。
   **判定在 `Path.resolve()` 之后做** —— 否则一个指向 `/root/.secrets` 的软链接就能绕过去；
4. **自杀名单**：`stop` / `disable` 拒绝 `sshd`、本服务、隧道、网络、systemd 的底座单元。
   理由写进错误文案：**本服务被停之后，App 就再也没法从手机上把它启回来**
   （`start` / `restart` / `reload` 不在此列，重启 sshd 是合法需求）；
5. **审计**：每个写调用（含被拒的）落一行 JSONL，带参数与结果。

解压另有三条硬约束：**每个条目先校验再解**（`../evil` 这类 zip 穿越一律 403）、
解压总量超过 2 GB 就停（返回 `truncated:true`）、条目数上限；已有的同名文件会被覆盖。

### 14.4 有意不做的事

* **删除**：文件通道（WebDAV）本来就能删，不在这里再开一个入口；
* **任意命令 / 脚本执行**：那等于把 root shell 放进一个 HTTP 接口；
* **包管理器 / 编译**：同理；要跑构建就在终端页里手动跑；
* **chattr / setfacl**：等真需要再说，先不加没边界的动作。

### 14.5 真机证据（2026-09-26）

| 项 | 结果 |
|---|---|
| 服务端自检（不碰线上） | **42 项全过**（读 21 + 写 21，含 zip 穿越、自杀单元、作用域闸门、CLI 撤销） |
| 公网入口 live（两条） | 各 **7/7**：capabilities 带 `write=true`；受保护路径 403、停 sshd 403、单元名带路径 400、不存在的单元 404 |
| 只读令牌实测（两台） | `capabilities.write=false`；`health` 200、`mkdir` 403、`service restart` 403；**撤销后 401** |
| App 令牌实测 | 两台 `write=True`、`admin=True`；真建目录成功（随后已清） |
| 泄漏检查 | 两台 `/tmp` 无残留；令牌清单里只有 `box-app-175` / `box-app-hpa888` 两条 |

### 14.6 已知边界

* 写动作**以 root 运行**（`systemctl`、`chown` 需要）。风险面由上面五道闸门承担，
  不是"最小权限"那种安全模型 —— 它与文件通道（整盘读写）是同一个信任级别，只是多了审计与作用域；
* 递归 `chmod`/`chown` 在大目录上会跑很久（有超时；超时以 5xx 回来，实际可能已改了一部分）；
* 审计会记参数（含路径、单元名）—— 这是有意的，也意味着审计文件本身是敏感文件（已在保护名单里）；
* 限流按令牌算（60 次 / 10 秒），写动作与读动作共享这个额度。
