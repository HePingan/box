# 音乐区真入口 · 实施方案（2026-10-13）

> 状态：**阶段 1/2/3 已落地（2026-10-18）**。本文是调研后的实施方案。
> 承接 `docs/todo_consolidated_20261013.md` 的真欠债第 1 件。
>
> 落地记录见文末「阶段 2/3 实施结果」——其中阶段 3 的实现方式与原计划**不同**
> （原计划 MediaStore 全盘扫描，实际改成 SAF 文件选择器），原因在那一节说明。

## 一、结论先行

旧文档「复用 remote_storage 播放器」这条路**不仅成立，而且比旧文档判断的更强**：
remote_storage 现在就是一个现成的「视频/音频」双用途播放器，音频播放能力是
**已经写好、带测试、支持 10 种格式的完整实现**，不是「文件管理顺带能播一下」。

因此音乐区真入口**不需要引入任何新播放库**，缺的只是「入口 + 音频文件从哪来」。

---
## 二、现状核实（全部验证过，附代码证据）

### 2.1 音乐区仍是纯占位，零功能

- `lib/features/music/` 下只有 1 个文件：`presentation/music_placeholder_page.dart`
- 占位页内容（`music_placeholder_page.dart:57-70`）如实写着「没有播放器，也不能导入或下载」，
  并列出两种规划形态：**本地播放**（扫描设备音频）、**在线源下载后播放**（由用户提供源地址，
  App 不内置音源）
- 内容页入口（`warehouse_widgets.dart:204-214`）副标题「播放器开发中」，onTap 进占位页

### 2.2 HomePluginArea.music 枚举存在，但 0 插件

- `home_plugin_core.dart:43` 枚举有 `music`；`:75` 在 `displayOrder` 里
- 内置目录（`plugin_market_manifest.dart:699,711`）music 区只有 2 条**未上线占位**
  （专注白噪音/睡眠电台，都标 `comingSoon`），无任何真插件

### 2.3 关键发现：remote_storage 的音频播放能力是完整现成的

| 能力 | 证据 |
|---|---|
| 播放页就是「视频/音频」双用途 | `remote_storage_player_page.dart:1` 注释「远程存储：视频 / 音频播放页（拍板 7「直连播」）」 |
| 音频类型判定 | `remote_storage_models.dart:847` `enum RemoteEntryKind { ..., audio, ... }` |
| 音频扩展名 10 种 | `remote_storage_models.dart:876-886`：mp3/flac/wav/aac/m4a/ogg/opus/wma/amr/ape |
| 点音频文件直接进播放页 | `remote_storage_browser_page.dart:1971-1974` `case RemoteEntryKind.audio: _playEntry(entry)` |
| 播放器内核 | `video_player ^2.11.1`（pubspec.yaml:47，原生支持音频）+ `chewie ^1.14.1`（pubspec.yaml:57，UI 壳） |
| 音频专用 UI 分支 | `remote_storage_player_page.dart:569` `if (kind == RemoteEntryKind.audio)` |
| 倍速/进度/中继 | `playback_relay.dart` 完整（Range 透传拖动、明文 http 回环中继、断线回收） |

---
## 三、为什么「复用 remote_storage」成立（明确断言）

**`video_player` + `chewie` 已在 pubspec.yaml，不需要引入任何新播放库。**

- ✅ 播放器内核（video_player + chewie）已存在，且原生支持音频
- ✅ 播放页已内置 audio 分支（`remote_storage_player_page.dart:569`），不是只有视频画面层
- ✅ 中继转发（`playback_relay.dart`）对音频同样适用（http 明文源也能播）
- ✅ 本地文件播放路径已存在（`remote_storage_player_page.dart:130` `VideoPlayerController.file(File(widget.localPath!))`）

---
## 四、真正的难点：音频文件从哪来（不是播放器）

播放器不是难点，**难点是「音频文件从哪来」**。占位页规划了两种形态，对应两条完全
不同的工作量：

### 形态 B：在线源下载后播放（用户提供源地址）

- 现状：remote_storage 已有完整的「下载 → 本地 → 播放」链路
- 需要：一个「输入 URL 下载到本地」的入口 + 播放
- **100% 复用** remote_storage 的下载队列 + 播放页，工作量最小，风险最低

### 形态 A：本地播放（扫描设备音频文件）

- 现状：全仓**零**本地媒体扫描能力（`grep scan/MediaStore` 无命中，`:98` 只是占位文案）
- 需要：新增「扫描 /storage 下的音频文件」+ 列表 + 接入播放页
- 风险：Android 13+ 分区存储权限、MediaStore 查询，是**新领域**，不是复用

---
## 五、分阶段计划（用户已拍板 B→A）

| 阶段 | 内容 | 工作量 | 风险 |
|---|---|---|---|
| 0 | 定性确认（已拍板：B→A） | — | — |
| 1 | **在线下载 + 播放**（输入音频 URL → 下载 → 播放） | 1-1.5 天 | 低，100% 复用 |
| 2 | 接入 HomePluginArea.music 分区（可与阶段 1 合并） | 0.5 天 | 低，纯接线 |
| 3 | **本地播放**（扫描设备音频 → 列表 → 播放） | 1-2 天，独立一版 | 中高，分区存储 |
| 4 | 在线源「订阅/缓存」（可选，后续） | 另算 | 真正的「音乐源」功能 |

---
## 六、待核实（原样保留，不因文档好看而删）

1. **video_player 对冷门格式的解码支持度**：`_audioExts` 列了 10 种（含 ape/wma/amr），
   但 video_player 底层是 ExoPlayer，实际能否解码 ape/wma 等格式**需真机验证**。
   解码失败的兜底逻辑见 `remote_storage_player_page.dart:170` 附近的 `errorBuilder`
   → `_downloadAndPlay`（下载后走系统播放器）。
2. **Android 13+ 分区存储下扫描音频文件的具体权限路径**：阶段 3 要新增 MediaStore 查询，
   具体权限申请与兼容性**待核实**（真机 + 各 Android 版本）。
3. **「在线源」的用户真实需求强度**：是「单条 URL 下载」还是「持续源抓取」——
   决定阶段 1 是否够用，还是需要阶段 4 的「订阅/缓存」。**待与用户确认**。

---
## 七、给实施者的关键接口（阶段 1 用）

### 播放页（复用）

- 类：`RemoteStoragePlayerPage`（`remote_storage_player_page.dart:73`）
- 构造：`account`（`RemoteStorageAccount`，required）、`entry`（`RemoteStorageEntry`，required）、
  `localPath`（`String?`，**非空时直接播本地文件**，走 `VideoPlayerController.file`）
- **坑**：`account` 和 `entry` 都是 required，即使播本地文件也要传；`entry` 用于
  播放失败时的「下载后播放」回退逻辑（`errorBuilder` → `_downloadAndPlay`）

### 下载队列（复用）

- 类：`TransferQueue`（`transfer_queue.dart:179`，`ChangeNotifier`）
- 方法：`enqueue({kind, title, subtitle, totalBytes, runner, onFinished, spec})`（`:274`）
- `TransferRunner`（`:173`）签名：`Future<Object?> Function(... onProgress)`
- 支持暂停/续传（`pause`/`resume`，断点保留）、并发上限、网络策略

### 类型判定（复用）

- `remoteEntryKind(entry)`（`remote_storage_models.dart:949`）按扩展名返回
  `RemoteEntryKind.audio` 等
- `_audioExts`（`:876`）10 种扩展名白名单

---
## 附录：公开 CORS 音频源实测（2026-10-15）

验证命令：curl -sI --connect-timeout 8 -H Origin: https://box.hpa888.top URL | grep -i access-control|content-type|http/

实测 6 个公开音频源结果：

- soundhelix.com mp3：HTTP/2 200，无 Access-Control-Allow-Origin 头。App 可用，Web 会被 CORS 拦截。
- mixkit.co mp3：返回 HTTP/2 403，虽然有 Access-Control-Allow-Origin: *，但实际请求被拒绝，不可用。
- pixabay.com mp3：返回 HTTP/2 403，无 CORS 头，不可用。
- freesound.org mp3：返回 HTTP/2 404，虽有 Access-Control-Allow-Origin: *，但资源不存在，不可用。
- kozco.com LRMonoPhase4.mp3：HTTP/2 200，无 CORS 头。
- kozco.com piano2.wav：HTTP/2 200，无 CORS 头。

结论：公开 CDN 和测试站点中，能 HTTP 200 的源大多不带 CORS 头；带 CORS 头的源又常返回 403/404。阶段 1 Web 验证建议优先使用同域部署的测试音频，可彻底避开 CORS。

推荐测试音频：https://box.hpa888.top/updates/box/android/test-music/test-tone-440hz.mp3
15 秒 440Hz 正弦波，同域，HTTP/2 200，Range 请求返回 206，无 CORS 限制。

---

## 阶段 2/3 实施结果（2026-10-18）

### 阶段 2：music 分区接线（已完成）

- `HomePluginActionType` 新增 `openMusic`（label「打开音乐」），进 `displayOrder`
  —— 投稿页下拉能选到它。
- 动作 handler + 路由 `openMusic` → `MusicPlaceholderPage`。
- 内置插件 `builtin_music_online`（在线音频）挂进 `HomePluginArea.music`：
  **music 分区从 0 插件变成 1 个真插件**。

回归锁：`test/plugin_manager/builtin_music_entry_test.dart`（4 条）。

### 阶段 3：本地音频（已完成，但**换了实现方式**）

原计划是 MediaStore 全盘扫描（`READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE`），
实际改成 **SAF 文件选择器**，原因：

1. 本仓库**没有任何权限申请插件**（现有权限全是安装时授权或系统 Intent 触发）。
   引入运行时权限 = 新依赖 + 新权限 + 各 Android 版本的真机验证，成本远超收益。
2. 走 SAF 是**零权限**：用户挑哪个文件，App 才看得到哪个 —— 也是 Android 现在
   推荐的做法。
3. 代价：不能「打开就列出我手机里所有歌」，需要用户主动挑一次。

**一个必须写下来的坑**：`file_picker` 的 Android 实现会把选中文件**复制**到
`cacheDir/file_picker/<时间戳>/`，Dart 侧拿到的 `path` 是那份**缓存副本**，
不是用户原件（见 `android_file_picker` 的 `FileUtils.getFileInfo`）。所以：

- 不能直接播那个路径 —— 系统清缓存时正在播的音频会断；
- 也不能让它越积越多 —— 每挑一次就多一份，`clearTemporaryFiles()` 在插件里有但
  不调就永远不清。

本页因此复制一份到自己的临时目录再播，复制完成后清掉插件那份，
`dispose` 时只删自己那份（用户原件一律不碰）。

### 阶段 4：在线源「订阅/缓存」（未做）

仍是可选项，取决于用户实际需求强度（文档第 6 节第 3 条「待与用户确认」仍未答）。
