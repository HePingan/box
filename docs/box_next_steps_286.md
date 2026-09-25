# 286 优化方案（box 应用；含宿主监控一条线）

> 命名说明：前几轮叫 `remote_storage_plugin_next_steps_28N.md`，因为范围就是远端存储插件。
> 这一轮范围扩到"整个 app 的插件 + 刚上线的监控链路"，所以改成 `box_next_steps_286.md`。

## 1. 事实基线（2026-09-25 核对，全部实机验证）

| 项 | 现状 |
|---|---|
| 线上版本 | **1.20.28+285（release id=127, published）**，284 已归档 |
| 内置插件 | 目录里 **16 条**（原 15 + 本轮「服务监控」），路由码登记在 `builtin_plugin_pages.dart` |
| 本轮新增插件 | `plugins/monitor/`：models 161 行 + page 466 行 + service 169 行 = **796 行** |
| 测试口径 | CI 口径 **3159 通过 / 3 跳过 / 0 失败**（排除 live）；插件目录 31 条 |
| analyze | 220 条（长期基线，门禁只卡 error/warning） |
| 悬挂 API 闸门 | 113 个公开方法 / 0 悬挂（已把 monitor 插件纳入） |
| 监控链路 | Kuma 10 项，cron `*/2` 采样 → 快照 893B → `https://box.hpa888.top/monitors.json` |
| **证书剩余（实测可采）** | myb **57 天** / kimi **43 天** / qwen 89 天 / zocr 76 天 —— 数字来自 `/metrics`，**目前没上界面** |
| remote_storage 未做项 | 限速/暂停：全仓 0 处；系统分享接收：`AndroidManifest.xml` 无 SEND 过滤 |
| 宿主侧 | GoAccess **两台都没装**；无任何安全巡检 cron |

## 2. 候选清单

### P 档（建议本轮四件）

| # | 项 | 落点（文件:行号） | 做法 | 收益 | 成本 | 验收标准 |
|---|---|---|---|---|---|---|
| **P1** | 监控插件收口：证书天数 + 采样链告警 + 端点收口 | `tool/gen_monitors_json.py:41`（LINE_RE 加 `monitor_cert_days_remaining`）、`:106 build()`、`:147 push_to_edge`；`monitor_models.dart:30/38/52`；`monitor_page.dart:411 _MonitorTile`；边缘机 `box.hpa888.top.conf` 的 `location = /monitors.json`；`monitor_service.dart:122` | ① 快照加 `certDays`（缺就省略，界面 `—`），行内显示「证书 43 天」，**<30 天标黄**；② 采样或推送失败时发飞书（复用已有告警链路），不再只写日志；③ 端点加共享 token（`$arg_token` 校验，不对返回 404） | 证书只剩 43 天这类信息从"哪天打不开才知道"变成提前可见；采样链断了能收到告警；端点不再裸奔 | 约 1 天（含用例） | 快照含 certDays 且界面显示；手动停 cron → 10 分钟内收到飞书；不带 token 请求 404，带上正常 |
| **P2** | 传输限速 / 暂停（285 D3） | `domain/webdav_client.dart:370 downloadTo` / `:442 uploadFrom`（按字节+时间片节流）、`application/remote_storage_service.dart:764/:998`（透传参数）、`application/transfer_queue.dart`（暂停=取消当前任务并留 `.part`） | 限速：每传 N 字节 sleep 到目标速率；暂停：取消在跑的任务、保留 `.part`，恢复时复用 C2 的 `resumeFrom`（206 追加 / 200 截断 / 416 清断点） | 弱网与流量敏感场景能限速；暂停/继续不必重下 | 约 1 天 + 用例 | 限速生效（单位时间字节数有界，用例断言）；暂停后 `.part` 在、恢复从中断处继续；不续传的服务端回落为重新下载 |
| **P3** | 接收系统分享上传（285 D4） | `android/app/src/main/AndroidManifest.xml:66`（新增 `SEND`/`SEND_MULTIPLE` 过滤）、`MainActivity.kt:17`（取 `EXTRA_STREAM`）、`remote_storage_service.dart:962 uploadFile`（复用入队） | 注册 `image/*` + `video/*`（**不用 `*/*`**，避免出现在所有分享面板），冷启动与 `onNewIntent` 两条路径都取 URI → 入传输队列，目标=当前目录 | 相册/文件管理器里分享文件直接进云盘 | 约 1 天（安卓侧 + 生命周期） | 从相册分享到 box → 任务出现在队列并上传成功；多选按数量入队；解析 URI 的纯函数有用例 |
| **P4** | 搜索复用目录快照（285 D1） | `application/remote_storage_service.dart:477 searchSubtree`、`:599 cachedListing`、`domain/remote_storage_models.dart:701 DirSnapshot` | 先用 D7 的快照秒出"上次见过的命中"并**显式标注可能过期**，同时后台精确扫，扫完替换 | 大目录搜索体感（不必每次等全树遍历） | 半天 + 5 用例 | 有快照时首屏立即可见且带"可能过期"提示；后台结果回来后替换；无快照时行为与现在一致 |

### D 档（体验，可挑）

| # | 项 | 落点 | 收益 | 成本 |
|---|---|---|---|---|
| D1 | 监控插件历史趋势（极简 sparkline） | 生成脚本维护最近 60 次采样的环形缓冲；页面自绘（约 20 行，无新依赖） | 从"挂了才知道"到"变慢了看得出" | 半天 |
| D2 | remote_storage 筛选增强（类型/大小/时间） | 本目录筛选（C3）+ D10 的匹配纯函数 | 目录里几百个文件时能用 | 低 |
| D3 | 监控项详情页（最近心跳/证书/检查目标） | `monitor_page.dart` 行点击 → 新页；需要快照补字段 | 面板外也能看单点细节 | 半天 |
| D4 | 清一批 analyze info（挑喜欢的几类） | 全仓 | 门禁只卡 error/warning，纯卫生 | 低（可选） |

### E 档（不建议本轮）

- **E1 上传续传**：WebDAV 没有标准部分 PUT（`Content-Range` 是扩展，多数服务端直接拒）→
  只做「能力探测 + 明确报错」，不做分片拼接（285 已拍板）。
- **E2/E3 视频首帧扩展到中继/摘要账户、非 Android 平台**：收益小、代价大（要为一帧开中继会话）。
- **E4 监控快照改实时 API**：要让 app 直连就得给它一个带鉴权的服务端，收益不抵成本
  （现在静态快照 + `generatedAt` 已经够用）。

## 3. 宿主侧（另一条线，不动 box 代码）

| # | 项 | 现状 | 做法 |
|---|---|---|---|
| H1 | Kuma 告警入口换成 Hermes 原生 webhook | 现在是 nginx 随机路径即密钥 + `hermes send` 裸转发 | 用 Hermes 的 webhook 路由接 Kuma：路径/令牌即密钥，触发的是一次 agent run —— 告警能带上下文（先查该项状态、看日志）再发飞书 |
| H2 | 安全巡检 | 无任何巡检 cron | 每日一次：sshd 失败登录、开放端口变化、证书到期（快照里已有数字）、磁盘/内存、Docker 镜像是否有更新、nginx 配置哈希变化 → 结果进飞书 |
| H3 | GoAccess 流量分析 | 两台都没装（实测） | 边缘机装 goaccess + 解析 nginx 日志 + 出一份内部报表（每日/每周） |
| H4 | 文件投放页 | 未开工 | 临时文件上传/取件页（带过期与口令） |

## 4. 规模粗估（非承诺）

| 档 | 项数 | 估时 | 说明 |
|---|---|---|---|
| P1–P4 | 4 | 约 3.5 天 | P1 收益最快见效 |
| D1–D4 | 4 | 约 1.5 天 | 都可拆开单独做 |
| H1–H4 | 4 | 另算 | 属于宿主运维，与 box 发布节奏无关 |

## 5. 待拍板（3 条，各带建议）

1. **范围**：建议本轮做 **P1–P4 四件**（P1 先把监控这条新链路收口，P2/P3/P4 清掉远端存储的
   三个真实缺口）；D 档下轮。
2. **快照端点的"收口"到哪一步**：建议只加**共享 token**（`$arg_token`，不对就 404）——
   它挡得住随手扫到的爬虫，但**不是真鉴权**（app 里的常量可被反编译看到）。要真鉴权得给每台设备
   发凭据，成本和收益不成比例。能接受这个定位就按建议做，要更严就说（比如换独立子域 + IP 白名单）。
3. **宿主侧 H1–H4**：建议**先不动**，等 box 这条线停下再单独排；如果你更想先做 H2（安全巡检），
   说一声我把它提到本轮前面。
