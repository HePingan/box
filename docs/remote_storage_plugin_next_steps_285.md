# 远端存储插件下一步打磨方案（285）

> 前提：线上已是 **1.20.27+284**（release id=126，2026-09-25 发布）。本文是 285 的候选
> 清单，**不含承诺**；每项的"收益/成本/风险"都是基于当前代码的实估。
> 口径沿用：每项一提交、每项带测试；组内跑插件目录，整轮跑 CI 口径
> `flutter test --exclude-tags live`（CI 钉的 Flutter 3.44.6），analyze 保持
> 0 error / 0 warning。

## 1. 事实基线（2026-09-25 核对）

插件代码 10,710 行，按分层：

| 文件 | 行数 | 说明 |
|---|---|---|
| `presentation/remote_storage_browser_page.dart` | 2,458 | 浏览器页（本轮 D6–D10 主要落点） |
| `domain/remote_storage_models.dart` | 1,539 | 纯模型/纯函数（零 `dart:io`） |
| `application/remote_storage_service.dart` | 1,514 | 服务 + `DioWebdavTransport`(:33) |
| `domain/webdav_client.dart` | 1,114 | 协议层（`downloadTo` :370、`uploadFrom` :442） |
| `presentation/remote_storage_page.dart` | 890 | 账户页/传输面板 |
| `presentation/remote_storage_player_page.dart` | 625 | 播放页 |
| `presentation/image_preview_dialog.dart` | 334 | 预览（283 D5 / 284 P2 落点） |
| `data/remote_storage_store.dart` | 377 | 偏好/快照/断点 |
| `application/playback_relay.dart` | 321 | 本地中继（空闲 30s 自关，:86-92） |
| `data/remote_thumbnail_cache.dart` | 294 | 缩略图磁盘缓存 |
| `application/transfer_queue.dart` | **274** | 传输队列（`TransferQueue` :76、`enqueue` :102） |
| `domain/digest_auth.dart` | 211 | 摘要认证（C5） |
| `domain/exif_thumbnail.dart` | 196 | EXIF 内嵌缩略图 + **orientation 解析（:19/:28/:56，目前无人用）** |
| `data/video_frame_channel.dart` | 64 | 视频首帧通道（284 D8） |

测试与闸门：

- 插件目录 **469 通过**；CI 全量 **3094 通过 / 3 跳过 / 0 失败**；`flutter analyze`
  0 error / 0 warning（220 条 info 为既有基线）；悬挂 API 闸门 **99 个公开方法 / 0 悬挂**。
- 协议层已有真回环用例：`preview_strict_server_test`、`download_resume_test`、
  `digest_auth_test`、`remote_storage_relay_test`（这一层不是空白）。

两个已知瑕疵（本轮必须如实带进方案）：

1. **C7 并发同名上传用例在全量并发下偶发红**（`remote_storage_service_test.dart:521`；
   单跑 3/3 绿、复跑即过）。
2. **`github_accel_live_e2e_test` 稳定红**：`签名长链 → 真实可下载的加速地址` 返回
   **403**，来自第三方加速镜像（`gh-proxy.com`，见测试 :50/:76）；与本插件无关，
   但它把全量口径弄脏了。

## 2. 与既有遗留的核对

| 遗留 | 状态 |
|---|---|
| 283 §5 ①：坚果云上 EXIF 内嵌缩略图的**实际命中率** | 284 P3 已把命中数做到「更多 → 缩略图缓存」面板上，**等真机数据**（装 284 包后看） |
| 283 §5 ②：**Flutter 是否已应用 EXIF Orientation** | 本仓零处理；`exif_thumbnail.dart` 已把 orientation 解析出来但没人用 → 见 P2 |
| 283 §5 ③：D7 快照的"看到旧列表"认知成本 | 已按"横幅写明时间 + 刷新失败保留旧内容并写原因"落地，**等真机体感** |
| 284 §9 三条待拍板 | 已全部拍板（P1–P5 全做、倍速先做、扫描器入库接 CI） |
| 284 D8 的三种拿不到首帧的场景 | 非 Android / 需中继 / 摘要认证：**目前故意不做**，已在文档写明 → 见 E2/E3 |

## 3. 候选清单

### P 档（建议先做）

#### P1 传输队列持久化 + 后台继续（收益最大的一项）

- **落点**：`application/transfer_queue.dart:76`（`TransferQueue`）、`:102`（`enqueue`）；
  新增 `data/transfer_queue_store.dart`；安卓侧复用现成模板
  `android/app/src/main/kotlin/top/hpa888/box/VideoDownloadService.kt:33`，
  注册处 `MainActivity.kt:448` 附近。
- **现状**：队列是**纯内存**（274 行里没有任何持久化）——app 被杀或系统回收后，排队中与
  在传的任务全部消失且不可恢复；下载虽然落了 `.part`（C2 续传），但**队列本身没了**，
  用户得重新点一遍。
- **做法**：
  1. 任务元数据（kind / 账户 id / 本地路径 / 远端路径 / 大小 / 状态）在 `enqueue` 与状态
     变化时写盘（JSON 文件 + 条数上限，别用 SharedPreferences 塞大数组）；
  2. 启动时把"未完成 + 账户与本地文件仍在"的任务恢复到队列，标「已恢复」；
  3. 传输期间起前台通知（照 `VideoDownloadService` 的写法），退到后台继续跑。
- **收益**：切后台/被杀不再白传（大文件最痛）；重启后能看到并续跑。
- **成本**：中，约 300–400 行 + 6–8 条用例（含 1 条真机验收）。
- **验收**：① 单测：入队 → 写盘 → 重建队列恢复出等价状态；② 恢复的任务标「已恢复」；
  ③ 幂等：恢复不会和"已在队列里的同一任务"重复；④ 真机：退到后台 1 分钟回来，
  任务还在跑或明确显示可恢复。
- **风险**：前台服务的通知与权限（最小化到"传输期间才有通知"）；恢复时的去重键要定死
  （建议"账户 + 远端路径 + 本地路径"）。

#### P2 EXIF Orientation：先验证、确认为问题再修

- **落点**：`domain/exif_thumbnail.dart:19/:28/:56`（orientation 已解析）；
  显示层 `presentation/remote_storage_browser_page.dart`（行首缩略图）与
  `presentation/image_preview_dialog.dart`（预览）。
- **做法**：先拿一张 **Orientation=6**（竖拍）的照片在真机上看缩略图与预览是否躺倒；
  **确认为问题再修**——在显示层按 orientation 做旋转变换（`RotatedBox`/`Transform`），
  **不重新编码**，直接用已缓存的字节。
- **收益**：竖拍照片不再躺倒（相机原图很常见）。
- **成本**：验证 0.5h；修：低（约 60 行 + 4 条用例：1–8 映射、2/4/5/7 镜像、null 不转）。
- **验收**：真机截图对比 + 单测覆盖 1–8（含镜像分支）。
- **风险**：Flutter 各版本对 JPEG EXIF 的处理不一致 —— 所以规定"先验证再修"，别先改代码。

#### P3 GitHub 加速链核查 + live 用例分级

- **落点**：`lib/features/extensions/plugins/github_accel/`（`github_accel_probe.dart`、
  `github_accel_service.dart`）；用例 `test/features/extensions/github_accel_live_e2e_test.dart:50/:76`。
- **做法**：核实 `gh-proxy.com` 现在的规则（是否已不再放行 releases 下载），换或加备用域名
  （要真实验证，不用"看起来能用"的地址）；把 live 用例改成**分级断言**：整域不可达 →
  `skip` 并写原因；可达但目标返回 403 → 单独标红且文案指明是外部行为。
- **收益**：全量测试重新可信；加速链真断了也能立刻知道。
- **成本**：低，1–2h。
- **验收**：live 用例本机连跑 3 次结果稳定可解释。

#### P4 C7 flake 的定位与根治

- **落点**：`test/features/extensions/remote_storage/remote_storage_service_test.dart:521`
  （用例）、`service.uploadFile` 的 `_inFlightUploads` 占位逻辑（`remote_storage_service.dart:984`（占位集合字段在 :277））。
- **做法**：在"全量并发 + 重复 5 次"下复现，抓真实时序（占位集合清理时机 vs 假传输层调度）；
  再决定改实现还是改用例。**如果真实竞态不存在（只是用例假设了不确定时序）**，就把用例改成
  断言结果层语义（"不静默覆盖"），而不是断言并发计数。
- **收益**：CI 不再偶发红，报告数字可当证据用。
- **成本**：中，1–2h（复现靠跑的）。
- **验收**：CI 口径全量连跑 5 次全绿。

### D 档（体验，可挑）

| 项 | 落点 | 做法与收益 | 成本 |
|---|---|---|---|
| D1 跨目录搜索复用目录快照 | `service.searchSubtree`(:477) + D7 的 `DirSnapshot` | 先秒出"上次见过的命中"并标明可能过期，再后台精确扫；大目录体感明显 | 中（约 150 行 + 5 用例），**风险：陈旧结果误导** |
| D2 筛选增强（类型/大小/时间） | 本目录筛选（C3）+ D10 的匹配纯函数 | 纯本地匹配，扩 `SearchHit` 匹配规则与筛选条 | 低 |
| D3 传输限速 / 暂停 | `DioWebdavTransport`(:33) 的 `downloadTo`/`uploadFrom` 流 | 弱网与流量敏感场景（限速按字节节流、暂停=取消并留 `.part`） | 中 |
| D4 接收系统分享上传 | 仓库现有 intent-filter 只有 LAUNCHER(:66) 与无障碍服务(:77)，**没有 SEND/分享过滤**；需新增 + `MainActivity` + `service.uploadFile`(:962) | 别的 app 分享文件直接传到当前目录 | 中（安卓侧改动 + 权限/生命周期） |

### E 档（更大或不确定，建议先不做）

- **E1 上传续传**：WebDAV **没有标准的部分 PUT**（`Content-Range` 属扩展，多数服务端直接
  拒绝），下载那套 C2 断点续传搬不过来。建议先做"**能力探测 + 明确报错**"（探测一次，
  支持才续传），**不做分片拼接**（服务端不提供合并原语，自己拼会造出坏文件）。
- **E2 视频首帧覆盖中继/摘要认证账户**：要为一帧开一条中继会话（中继本是给播放用的），
  性价比低。
- **E3 非 Android 平台的首帧**：需要各平台原生解码或 FFI（`media_kit` 量级），不在安卓主线内。

## 4. 规模粗估（非承诺）

| 档 | 项数 | 估计 | 说明 |
|---|---|---|---|
| P1 | 1 | ~1 天 | 含安卓前台服务与真机验收 |
| P2 | 1 | 0.5 天 | 含真机验证 |
| P3 | 1 | 0.2 天 | 主要是核实外部行为 |
| P4 | 1 | 0.5 天 | 复现靠跑 |
| D1–D4 | 4 | ~2 天 | D1/D4 各半天以上 |
| E1–E3 | 3 | 不建议本轮 | 见上 |

## 5. 待拍板（3 条，各带建议）

1. **范围**：建议只做 **P 档四件**（P1 队列持久化是收益最大的一项；P2/P3/P4 都是"把已知
   瑕疵收干净"）。D 档等下轮，E 档本轮不动。
2. **E1 上传续传**：建议**只做能力探测 + 明确报错**，不做分片——WebDAV 缺合并原语，
   硬做会造坏文件。
3. **P2 的前置**：Orientation 是"先验证再修"——如果你能给我一张竖拍照片（或告诉我你手机
   相册里竖拍照片在 box 里是否躺倒），这条就能立刻定案。
