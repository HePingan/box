# Box 远程存储插件方案（A 档：WebDAV / S3）

- 日期：2026-09-20 ｜ 状态：**已拍板**（结果见 §10；其中第 5、7 条为修订采纳，与原文建议不同）｜ 2026-09-21 复核与追加拍板见 §11（A 档随 1.20.22+278 发布；B 档随 1.20.23+279）
- 范围：**仅用户自有账户**的标准协议接入（WebDAV / S3 兼容）
- 明确不含：网盘链接解析、共享会员池、代理下载、破解限速、任何「加速」宣传

---

## 0. 背景与定位

对 B 站热门「云解析」类项目（萌娘助手 / 流光助手 / 云析）的调研结论：

- 其「加速下载」机制是**服务端 Cookie 池化/共享会员代理**（非本地算法），依赖第三方提供者维护会员账号；
- 法律风险：反不正当竞争法下有民事追责先例，刑事定性虽有争议但处于被审视状态；
- 夸克网盘**不存在**面向第三方开发者的网盘开放平台。

因此不做解析插件。本方案改为 **A 档：把用户自己的私有存储接进 Box**——浏览、预览、下载进本地、上传。速度即服务商官方额度，宣传口径只讲「连接你的网盘 / NAS」。

## 1. 目标与非目标

**目标**

1. 支持 WebDAV（覆盖：坚果云、群晖 NAS、Nextcloud、自建 Apache/rclone/Alist 等）与 S3 兼容（MinIO 等，P1；2026-09-21 拍板：先不做，见 §11）；
2. 目录浏览、文件预览、下载落盘（可打开/分享）、上传；
3. 凭据加密本地存储（沿用既有模式，见 §6）；
4. 全程可诊断：连接测试 + 既有调试日志接入〔2026-09-21 完成归位：落「存储」频道，应用内调试日志页可筛选〕；
5. 零新网络依赖、零推送、不后台常驻。

**非目标（本期不做，且不建议做）**

- 解析/转存第三方网盘分享链接；
- 共享账号、会员池、代下服务；
- 对任何服务做「限速绕过」；
- 上传到用户未授权的第三方公共空间。

## 2. 功能范围与分期

### P0（建议本期落地）

| 模块 | 内容 |
| --- | --- |
| 账户管理 | 新增/编辑/删除；字段：备注名、服务器地址、用户名、密码（应用密码）；「测试连接」按钮 |
| 目录浏览 | PROPFIND 逐级加载；目录优先排序〔2026-09-21 增强：页面级排序切换（名称/修改时间新在前/大小），目录恒在前；离开再进入恢复滚动位置（会话内）〕；面包屑返回；下拉刷新；空目录/错误态 |
| 下载 | 流式下载 + 进度 + 取消；完成后「打开」（OpenFilex）/「分享」（SharePlus） |
| 上传 | 系统文件选择器多选；PUT 上传 + 进度 + 取消；同名冲突默认「跳过并提示，可手动覆盖」 |
| 预览与播放 | 图片（内存预览、缩放）；文本/代码/JSON（前缀读取）；音视频**直连播放**（§5.7，不整文件下载）；其余格式「下载后外部打开」 |
| 诊断 | 错误中文映射；接既有调试日志〔2026-09-21 完成归位：原 13 处裸 `debugPrint` 全部迁入统一日志「存储」频道（`LogChannel.storage`），调试日志页可筛选；「已记入调试日志」承诺自此真实成立〕 |

### P1（2026-09-21 排期标注：B 档，随 1.20.23+279 实施）

- 写操作：重命名（MOVE）、删除（DELETE）、新建文件夹（MKCOL）——均需二次确认；〔B1〕
- 播放增强：断点续播（按文件记忆进度）、外挂字幕〔B3；**投屏不做**——需 DLNA，另立项〕；
- 「导出到公共下载目录」（SAF 目录选择）〔B2；内存缓冲阈值 64MB，超阈值提示改用「分享」〕。

### 暂缓（backlog；2026-09-21 拍板）

- S3 兼容协议（SigV4，见 §5.6）——先不做；
- 传输任务持久化与断点续传（Range）——B4 暂缓（未拍板落地时间）。

### P2（backlog，不一定做）

通知栏传输进度（需原生侧改动）、WebDAV LOCK 支持、多账户并行传输合并视图。

## 3. 接入现有插件体系（真实接入点，全部已核）

上架方式与 **GitHub 加速下载 / AI 生图**完全相同：商店模板 → 用户安装 → 生成 `HomeCustomPluginConfig`（`fromMarketTemplate`）→ 出现在首页对应区域 → 点击经动作分发进入页面。**无需改 `builtin_plugin_catalog.dart`**。

共 4 处改动 + 1 个新目录：

1. **商店模板**：`lib/features/extensions/market/domain/plugin_market_manifest.dart`
   `MarketPluginManifestDefaults.defaults`（586–719 行，现有 12 条）新增：

   ```dart
   const MarketPluginTemplate(
     id: 'market_remote_storage',
     title: '远程存储',
     subtitle: 'WebDAV：坚果云 / 群晖 NAS / Nextcloud / 自建',
     areaCode: 'recommend',
     actionCode: 'openRemoteStorage',
     payload: '',
     icon: Icons.folder_shared_outlined,
     color: Color(0xFF0E7490),
     sort: 14,
   )
   ```
   （名称/落区/排序已按拍板 1 落地，均可调。）

2. **动作枚举**：`lib/features/extensions/core/home_plugin_core.dart`
   `HomePluginActionType`（87–126 行）新增成员 `openRemoteStorage`，`label` 返回「打开远程存储」，并加入 `displayOrder`。

3. **动作分发**：同文件 `HomePluginActionRegistry._handlers`（242–284 行）新增分支，照抄 `openImageGenerator` 块：`registerBuiltinRouteDefaults()` → `lookup('openRemoteStorage')` → `Navigator.push`。

4. **页面注册**：`lib/features/extensions/core/builtin_plugin_pages.dart`
   `registerBuiltinRouteDefaults()`（21–51 行）注册双 code：`'remote_storage'` 与 `'openRemoteStorage'` → `RemoteStoragePage`。

5. **新目录**：`lib/features/extensions/plugins/remote_storage/`（结构见 §5.1）。

## 4. 交互设计

```
首页/插件区「远程存储」
  └─ RemoteStoragePage            账户卡片列表 +「新增账户」+「传输任务」入口
       ├─ 编辑面板（新增/编辑/测试连接）
       └─ RemoteStorageBrowserPage  目录浏览
            ├─ 点击目录 → 下一层
            ├─ 点击文件 → 按类型：预览 / 下载后打开
            └─ 顶栏：上传、刷新、传输任务
  └─ 传输任务页（下载/上传队列，进度/取消/重试）
```

文案口径要点：空态「还没有连接任何存储」；错误一律中文可读（见 §5.5 映射表）；http/自签账户在卡片上有「不安全连接」提示徽标（私网默认放行，仅提示；可在编辑页调整）。

## 5. 技术设计

### 5.1 模块划分（P0 共 9 个源文件）

```
lib/features/extensions/plugins/remote_storage/
  domain/remote_storage_models.dart     # 账户/条目/传输任务模型 + 输入校验
  domain/webdav_client.dart             # WebDAV 协议客户端（含 multistatus XML 解析）
  data/remote_storage_store.dart        # 账户加密存储（沿用 account_store 模式）
  application/remote_storage_service.dart # 门面：列目录/下载/上传/测试连接 + 错误归一 + 日志
  application/transfer_queue.dart       # 串行传输队列（进度/取消/重试）
  application/playback_relay.dart       # 本机回环中继：http/自签源的播放取流（§5.7）
  presentation/remote_storage_page.dart # 账户首页（含编辑面板、传输入口）
  presentation/remote_storage_browser_page.dart # 浏览页（含预览）
  presentation/remote_storage_player_page.dart  # 直连播放页（video_player + chewie，与 Box 现有播放栈一致）
```

协议栈：**dio（已是依赖，与 github_accel/生图下载同栈）** + **xml（已在 pubspec.lock，属传递依赖，提升为直接依赖零新增下载）**。不引入任何新依赖。

### 5.2 WebDAV 客户端要点

- 方法：`OPTIONS`（测试连接，读 `DAV:` 头确认 class 1/2）、`PROPFIND Depth:1`（列目录）、`GET`、`PUT`、P1：`MKCOL/MOVE/DELETE`；
- Basic 认证；**坚果云需使用网页端生成的「应用密码」**（错误文案里直接提示）；
- `href` 需按百分号编码解码，中文/空格文件名常见于群晖、Nextcloud；
- **系统目录过滤（启发式）**：群晖 `@eaDir`、回收站 `#recycle`、macOS `.DS_Store/.Trashes`——常量名单 `kWebdavSystemDirNames`，可在设置里关闭（调大名单→更干净但可能误伤同名真实目录）；
- 超时常量：连接 10s / 读 30s（`kConnectTimeout` / `kReadTimeout`，可调）；
- 测试连接输出诊断明细（HTTP 状态、DAV 头、目录可读性），失败原因入调试日志。

### 5.3 传输设计

- dio 流式下载/上传，`CancelToken` 取消（与 github_accel 同模式）；进度按 `content-length` 计算，缺失时显示已接收字节数；
- 下载：先写 `临时目录`，完成后原子移动到 `应用文档目录/remote_storage/<accountId>/<路径>`（与 github_accel/生图 落盘习惯一致），随后提供「打开 / 分享」；
- **路径安全**：文件名与远端路径做 `..`/分隔符清洗，禁止越权写出目标目录；
- 冲突策略（已拍板）：上传前 `HEAD` 探测；默认**跳过并在结果中提示**，冲突项可在对话框中手动选择覆盖；
- 队列串行（常量 `kMaxConcurrentTransfers = 1`，调大→更快但 NAS 弱机失败率升高）；失败自动重试 2 次（`kTransferRetries`）。
- 任务列表 P0 仅内存态（应用重启不保留）；持久化续传 2026-09-21 调整为暂缓（B4，见 §2/§8/§11）。

### 5.4 预览矩阵

| 类型 | P0 策略 | 常量（可调，附方向） |
| --- | --- | --- |
| 图片 | 下载入内存后缩放预览（InteractiveViewer） | `kPreviewImageMaxBytes = 20MB`（调大→更大图内存风险↑） |
| 文本/代码 | 读前缀片段展示 | `kPreviewTextMaxBytes = 512KB`（调大→更完整但载入变慢） |
| 音视频 | **直连播放**（拍板 7）：https 直连；http/自签走本机回环中继（§5.7）；播放失败兜底提供「下载后播放」按钮 | 空闲自关 `kRelayIdleTimeout = 30min`（调大→保留更久；调小→端口更快回收） |
| 其他 | 下载后 OpenFilex 外部打开 / 分享 | — |

### 5.5 错误映射（节选）

| 状态/异常 | 文案 |
| --- | --- |
| 401 | 用户名或密码不正确；坚果云请使用「应用密码」 |
| 403 | 服务器拒绝访问（检查账号权限） |
| 404 | 路径不存在（服务器地址可能缺少 WebDAV 前缀，如 `/dav`） |
| 405 | 服务器未启用 WebDAV 或不允许该方法 |
| 507 | 服务器空间不足 |
| 证书错误 | 如为自建/群晖自签证书，请在账户里开启「允许自签名证书」 |
| 超时/断网 | 网络不可达，已记入调试日志 |

### 5.6 S3 兼容（P1；2026-09-21 拍板：先不做，设计备查）

- SigV4 签名（`crypto` 包 HMAC-SHA256 链即可，无需新依赖）；
- P1 最小集：ListObjectsV2（列桶）、GET、PUT、HEAD；路径风格（MinIO 兼容）；
- 单请求 PUT 上限 5GB；分块上传列 P2。

### 5.7 本机回环中继（直连播的实现，拍板 7）

问题：原生播放器（video_player → Android ExoPlayer）受 §6.4 约束，不能直连 http 或自签 https。
方案：插件内起一个**仅监听 127.0.0.1 的本机转发**，播放器连它、它连远端：

- `PlaybackRelay.start()`：`HttpServer.bind(InternetAddress.loopbackIPv4, 0)`（系统分配端口）；
  路径前缀 `/rs/<sessionToken>/...`，`sessionToken` 为 `Random.secure()` 生成的一次性 32 位 hex，
  仅当次播放会话有效（防同机其他应用猜路径蹭转发）；
- 转发：GET/HEAD 透传 `Range` 头 → 上游（同账户 dio 客户端，含 Basic 认证与自签开关）；
  回写状态码（200/206）、`Content-Range`/`Content-Length`/`Content-Type`/`Accept-Ranges`/`Last-Modified`/`ETag`（白名单，其余不回写）；`If-Range` 条件头暂不转发（Range 按无条件处理）；
- 响应体以块流**直通复制**：上游块原样转发，不做二次分块（原设计固定缓冲块 `kRelayChunkBytes` 未采用——上游块本即 socket 尺寸，二次分块徒增延迟）；
- 缓冲与背压（dart:io 实测）：`response.bufferOutput = false`——默认 8KB 输出缓冲会滞留小响应体（播放器只见响应头、收不到数据）；下游消费慢时暂停上游取流（pause/resume），不无限缓冲；
- 断线回收（dart:io 实测）：**不上报**客户端单方断开（写失败被静默吞掉、`response.done` 不触发）→ 回收不依赖写失败；播放页 `close()` 显式取消在途取流订阅（单测钉住取消语义与该平台行为）；
- 上游不支持 Range → 返回整段流，seek 退化为重新取流（播放器自行处理，**不做假 206**）；
- 生命周期：进入播放页 start、退出 dispose 时 `close()`（内部 `server.close(force: true)` 并取消在途取流）；无请求且无在途取流超过 `kRelayIdleTimeout`（默认 30min）自关兜底，不常驻；
- https 且证书有效：**不经中继**，video_player 直连（`httpHeaders` 带 Basic 认证），少一层开销；
- 失败兜底：播放出错（如编码不支持）→ 播放页提供「下载后播放」按钮；
- 边界：不缓存整文件到磁盘（仅流拷贝）、不对外提供任何服务（绑定回环、仅本机、仅播放会话期）。

## 6. 安全与网络策略

### 6.1 凭据存储（沿用 `account_store.dart` 既有模式）

- AES-256-CBC（`encrypt` 包）+ 随机 IV，`base64(iv‖ciphertext)`；
- 密钥 = `sha256('box-remote-storage-v1')`（独立盐，不与账号 token 共用）；
- 存储：SharedPreferences 单条加密 blob `remoteStorage.accountsEnc`（整个账户列表加密，含密码/密钥）；
- **如实说明**：`account_store.dart:11–13` 注释声称设计令密文「differ per install」，实际为固定盐 `'box-account-store-v1'` → **密钥跨安装恒定**（密文每次不同仅因随机 IV）。保护级别＝防明文、防随手查看，**不防逆向**；本插件沿用即同级别（本次拍板 4 选 A；如未来要提升，列为独立事项再评估）。

### 6.2 TLS 策略（拍板 5：私网默认放行）

- 公网主机：默认仅 https；`http://` 需显式开启，卡片显示「不安全连接」徽标；
- **私网主机（RFC1918 / `.local` / 回环）：默认允许 http 与自签证书**（拍板 5 修订）；判定函数 `isPrivateHost()` 单测覆盖；编辑页可手动关闭；
- 自签证书：`badCertificateCallback` 仅对**该账户填写的主机**放行，其他主机一律拒绝；告警入日志；
- `network_security_config.xml` 唯一一处改动：`domain-config` 为 `localhost` 与 `127.0.0.1` 开启明文（供 §5.7 播放中继；回环地址外部设备不可达，非全局放开）。Android 17+ 对回环隐式允许，低版本未定义，显式声明保证全版本一致。

### 6.3 日志脱敏

密码/密钥永不出现在日志与 UI；日志最多记录 `host + 用户名首字符`。UI 中输入框密文显示、不复制。

### 6.4 原生播放的通道事实（决定 §5.7）

| 通道 | 是否受 Android 明文限制 | 结论 |
| --- | --- | --- |
| Dart 网络（dio/http/dart:io，本插件全部走这里） | 否（Flutter 引擎策略，Box 内既有 http 源可用为证） | 局域网 http WebDAV 可用 |
| 原生播放（video_player/ExoPlayer） | 是（NSC base-config false） | http/自签 https 不能直连 → 走本机回环中继（§5.7）；https 有效证书直连 |
| 回环（127.0.0.1） | NSC 显式豁免后可用（§6.2 唯一改动） | 中继成立；真机 ExoPlayer 实测列入首次真机验证项 |

### 6.5 其他

- `AndroidManifest.xml` 未显式设置 `allowBackup`（即默认 true），与账号 token 目前的备份暴露面同级；如需收紧另行单独提出（涉及全 App 数据备份行为，不擅自改）。

## 7. 诊断与测试

- **单测注入模式**：参照 `github_accel_service.dart` 的「typedef 注入 fetch」先例，WebDAV 客户端注入传输层，测试全程不联网；
- XML 解析 fixtures：Nextcloud 风格（含命名空间前缀）与群晖风格（含 `@eaDir`）真样例各一组；
- 单测：href 解码、路径安全（`../` 注入）、错误映射、队列状态机（进度/取消/重试）、账户加解密往返与损坏数据降级（返回 null 不崩溃，同 `_decrypt` 既有行为）、URL 校验；
- Widget 测试：编辑面板校验、浏览页空态/错误态（fake service 注入）；
- **播放中继单测**：本机起假「源服务器」（dart:io HttpServer）→ 中继转发；断言 200/206、Range 透传、字节一致、HEAD 无 body、token 不匹配 404、非 GET/HEAD 405、上游异常 502、close 幂等且取消在途取流，并钉住「客户端单方断开不上报写失败」的平台行为；全程不联网。
- **live e2e 打 tag 默认排除**（沿用 `--exclude-tags live` 既有实践），真机对真实服务器验证留给你提供账号那次性执行。

## 8. 分期与规模（粗估，非承诺）

| 阶段 | 内容 | 规模粗估 |
| --- | --- | --- |
| P0 | 上表 §2 P0 全部（含中继与播放页） | 9 源文件 + 7~9 测试文件，约 2–3 天工作量。**已完成并发布：1.20.21+277** |
| P1 | 写操作 + 播放增强（断点续播/字幕）+ SAF 导出（**B 档，随 1.20.23+279**） | 另约 1–2 天 |
| P2 | 通知栏、LOCK | 视需要 |
| 暂缓 | S3 兼容（先不做）；传输任务持久化与断点续传（B4，暂缓） | 视需要 |

## 9. 风险与折中（主动列明）

1. **服务商差异**：坚果云需应用密码、群晖常见自签证书、Nextcloud 路径带 `/remote.php/dav` 前缀——由「测试连接」诊断 + 错误映射缓解；
2. **弱 NAS 性能**：大目录 PROPFIND 逐目录请求，上千项时列表排序有延迟（可接受；P1 可加首屏优先/分页）；
3. **上传无分块**：P0 单请求 PUT 大文件失败需重试；S3 分块列 P2（2026-09-21：S3 先不做，此项随之暂缓）；
4. **启发式清单**（均带常量名与调整方向）：系统目录过滤名单、预览阈值、重试次数、串行传输——如与真实环境不符，报我实测样本再校准；
5. **已验证 / 未验证**：本方案基于仓库真实代码与依赖清单（见附录 B）；协议/中继逻辑用假服务器单测可验证；服务商侧行为与**真机播放（ExoPlayer 经回环中继）属未验证**，首次装机时一并做；
6. 凭据保护级别如 §6.1 所述，属既有水平，不粉饰。
7. **中继代价（拍板 7 的直接成本）**：播放取流经进程内转发多一跳本机拷贝；拖动 seek 依赖服务端 Range，不支持则退化为重新取流（不做假 206）；无请求且无在途取流超过 `kRelayIdleTimeout`（默认 30min）自关（调大→保留更久；调小→端口更快回收）；如真机拖动卡顿，先查服务端 Range 支持与网络，再考虑回退「下载后播」。

## 10. 拍板结果与落地映射（2026-09-20）

| # | 拍板 | 落地 |
| --- | --- | --- |
| 1 | 可以 | 命名「远程存储」、区域 recommend、sort 14，按方案 |
| 2 | 可以 | P0 仅上传；重命名/删除/新建文件夹 P1 |
| 3 | 可以 | 冲突默认「跳过并提示，可手动覆盖」 |
| 4 | A | 沿用账号同款加密（固定盐模式，§6.1 已注明保护级别） |
| 5 | **默认放行（修订）** | 私网默认允许 http+自签（§6.2）；公网仍需显式；NSC 仅加回环豁免 |
| 6 | OK | 图片 20MB / 文本 512KB |
| 7 | **直连播（修订）** | https 直连 + http/自签走回环中继（§5.7）；失败兜底下载后播；P0 内落地 |
| 8 | 推 | SAF 导出列 P1 |
| 9 | 行 | 只上商店模板；接入时补 displayOrder（含 `openGithubAccel`，附录 A-1 已核实为真缺口） |

> 2026-09-21 追加拍板与状态标注见 §11（A/B 档排期、S3 先不做、B4 暂缓、导出阈值 64MB）。

## 11. 复核与追加拍板（2026-09-21，基于已发布 1.20.21+277）

### 11.1 复核发现（针对本方案代码落点，先说缺陷）

1. **日志承诺未落实（已修）**：§2 P0「诊断」承诺「接既有调试日志」，实际插件 0 处 AppLogger、13 处裸 `debugPrint`；而错误文案已向用户承诺「已记入调试日志」——照做的用户找不到落点。已归位，见 11.3 A1。
2. **分期口径不一致（已统一）**：§2 P1 曾列「传输任务持久化与断点续传」，§8 表将其归 P2。现两处口径统一：「持久化续传」为**暂缓（B4）**，「S3」为**先不做**。
3. **两处轻 UX 缺口（已修）**：浏览页无排序切换（比较器只有「目录优先」）；离开目录再进入不保持滚动位置。见 11.3 A2。

### 11.2 追加拍板结果（2026-09-21）

| # | 事项 | 拍板 |
| --- | --- | --- |
| 1 | A 档三项（日志归位 + 排序/滚动 + 本文档对齐） | 合成一版：1.20.22+278 |
| 2 | 浏览页排序默认 | 修改时间新在前（目录恒在前，不随排序改变） |
| 3 | B 档本轮范围 | B1 写操作 + B2 导出（先做） |
| 4 | 导出内存阈值 | 64MB（超阈值提示改用「分享」） |
| 5 | B3 播放增强 | 断点续播 + 字幕 都做；投屏不做 |
| 6 | S3（B5） | 先不做 |
| 7 | B4 传输持久化/续传 | 暂缓（未拍板落地时间） |

### 11.3 落地映射与状态

- **A 档 → 1.20.22+278（本轮）**
  - A1 日志归位：新增「存储」频道 `LogChannel.storage`（tag `STORAGE`，含 `fromTag` 锁定测试）；13 处裸 `debugPrint` 全部迁入统一日志（`AppLogger`），错误文案「已记入调试日志」自此有真实落点；调试日志页筛选器由 `LogChannel.values` 自动生成，**页面零改动**；`kDebugMode` 下 logcat 镜像由 AppLogger 既有机制保留。
  - A2 浏览页：排序切换（名称 / 修改时间新在前 / 大小，目录恒在前，默认修改时间新在前，**会话内保持、不落盘**）；离开再进入恢复滚动位置（会话级）。
  - A3 本文档对齐（本节即产出）。
  - 验证：`dart analyze` 无问题；远程存储相关新增与既有测试全绿（含本轮新增排序/滚动测试与频道锁定、错误日志测试）。
- **B 档 → 1.20.23+279（实施中）**：B1 写操作（MOVE/DELETE/MKCOL + 二次确认与不可恢复警示）、B2 导出到公共下载（相册流式 / SAF 另存为，64MB 内存阈值）、B3 断点续播 + 外挂字幕。
- **仍未验证（沿用 §9，首次真机执行）**：回环中继播放（ExoPlayer 经 127.0.0.1）、真实服务器连接（坚果云）、大目录排序性能（启发式预估）。

> 11.2 为 2026-09-21 六问短答的映射（1 是 / 2 时间 / 3 B1+B2 / 4 可以 / 5 都做 / 6 同意）；B4 未在问内，按未拍板暂缓处理。

## 附录 A：顺手发现（需确认，与本插件无因果）

1. 【已核实】`HomePluginActionType.displayOrder`（`home_plugin_core.dart` 118–125）**缺 `openGithubAccel`**，而投稿页下拉（`plugin_submit_page.dart:40`）正依赖此列表——「打开加速」在投稿时选不到，属真缺口（非刻意）。接入本插件时一并补 `openGithubAccel` 与 `openRemoteStorage`。
2. `account_store.dart` 第 11–12 行注释（「differ per install」）易被误读为密钥每安装不同；密钥实际跨安装恒定（第 13 行固定盐）——已在 §6.1 如实注明，不改代码。

## 附录 B：证据索引（本仓库，均本次已核）

- 商店模板结构与 12 条既有模板：`lib/features/extensions/market/domain/plugin_market_manifest.dart` 586–719；
- 动作枚举/标签/顺序：`lib/features/extensions/core/home_plugin_core.dart` 87–126；
- 动作分发现场（openGithubAccel 先例）：同文件 242–284；
- 路由双 code 注册：`lib/features/extensions/core/builtin_plugin_pages.dart` 21–51；
- 凭据加密先例：`lib/features/account/data/account_store.dart` 11–48；
- 权限枚举（供商店展示）：`plugin_market_manifest.dart` 185（`network/storage/...`）；
- 下载 UI 先例（进度/取消/打开/分享）：`lib/features/extensions/plugins/github_accel/github_accel_sheet.dart` 640–726；
- 单测注入先例：`github_accel_service.dart` 7–35；
- 依赖可用性：`pubspec.yaml`（dio/http/encrypt/crypto/file_picker/open_filex/share_plus/path_provider）、`pubspec.lock` 1176（`xml`）；
- 网络策略现状：`android/app/src/main/res/xml/network_security_config.xml`（base-config false；本次仅加回环豁免，见 §6.2）；`AndroidManifest.xml` 无 `allowBackup` 显式设置；
- 播放栈证据：`pubspec.yaml` 44/53（`video_player ^2.11.1`、`chewie ^1.14.1`）；容器先例 `lib/video/widgets/video_play_container.dart`（`networkUrl`/headers/ChewieController）；
- 投稿页下拉数据源：`lib/features/extensions/market/presentation/plugin_submit_page.dart` 40/44。
