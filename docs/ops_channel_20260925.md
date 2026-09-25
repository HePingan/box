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
