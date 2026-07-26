# Media3 HLS 后台下载原生集成方案

## 一、环境审计结果

### 1.1 Android/Gradle 配置

| 项目 | 当前值 | 说明 |
|------|--------|------|
| **AGP** | 8.11.1 | `settings.gradle.kts` 中声明 |
| **Kotlin** | 2.2.20 | `settings.gradle.kts` 中声明 |
| **Java/JVM** | 17 | `app/build.gradle.kts` 中 `VERSION_17` |
| **compileSdk** | `flutter.compileSdkVersion` → **36** | Flutter 3.44.6 默认 |
| **minSdk** | `flutter.minSdkVersion` → **24** | Flutter 3.44.6 默认 |
| **targetSdk** | `flutter.targetSdkVersion` → **36** | Flutter 3.44.6 默认 |
| **NDK** | 28.2.13676358-2 | `local.properties` |
| **Gradle** | 8.14 | `gradle-wrapper.properties` (腾讯镜像) |
| **Namespace** | `com.example.box` | |
| **架构** | arm64-v8a 仅 | NDK abiFilters |

### 1.2 现有 Kotlin 文件结构

```
android/app/src/main/kotlin/com/example/box/
├── MainActivity.kt              # FlutterActivity + MethodChannel (@e1)
├── QuizOverlayManager.kt        # 悬浮窗管理器 (~890行)
├── QuizAccessibilityService.kt  # 无障碍服务
├── QuizOcrEntryOverlay.kt       # OCR 录入浮窗
└── RegionSelectorView.kt        # 区域选择器视图
```

### 1.3 现有 MethodChannel 模式

- **Channel 名**: `com.example.box/quiz_plugin` (`MainActivity.kt:15`)
- **已有 API**: isAccessibilityEnabled, requestOverlayPermission, setOverlayVisible 等 20+ 方法
- **FlutterEngine 缓存**: `FlutterEngineCache.getInstance().put("quiz_engine", flutterEngine)`
- **已有下载通道预留**: `com.example.box/video_downloads` (`video_download_gateway.dart:18`) — 接口已定义但无后端实现

### 1.4 现有 Flutter 侧下载基础设施

| 文件 | 作用 |
|------|------|
| `lib/video/models/video_download_task.dart` | 数据模型（status, progress, localPath 等） |
| `lib/video/services/video_download_repository.dart` | 存储抽象接口（save/load/delete） |
| `lib/video/services/hive_video_download_repository.dart` | Hive 持久化实现 |
| `lib/video/services/video_download_gateway.dart` | MethodChannel 网关接口（enqueue/pause/resume/cancel/remove/snapshots） |
| `lib/video/services/video_download_scheduler.dart` | 并发调度策略（maxConcurrentTasks=2） |
| `lib/video/pages/detail/detail_models.dart` | DetailPlayLine/DetailPlayEpisode（含 URL） |

### 1.5 播放器侧 URL 解析

- `lib/video/widgets/player/player_stream_resolver.dart`: HLS Master playlist 降维 + probe
- `lib/video/widgets/player/player_request_headers.dart`: Referer/User-Agent 构建
- 播放 URL 格式: `.m3u8`，支持 Referer 头（`source.detailUrl`）
- `lib/video/controller/video_detail_controller.dart`: `_isM3u8Line()` 优先选 m3u8 线路

---

## 二、Media3 DownloadService 接入方案

### 2.1 Gradle 依赖

**文件**: `android/app/build.gradle.kts`

在 `dependencies { }` 块中添加：

```kotlin
dependencies {
    testImplementation("junit:junit:4.13.2")

    // ── Media3 Download（HLS 后台下载） ──
    val media3Version = "1.8.0" // 与 Flutter compileSdk=36 兼容的最新稳定版
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-datasource:1.8.0")
    implementation("androidx.media3:media3-datasource-rtmp:1.8.0")
    implementation("androidx.media3:media3-extractor:1.8.0")
    implementation("androidx.media3:media3-database:1.8.0")
    implementation("androidx.media3:media3-downloader:1.8.0")
}
```

**风险点**:
1. Media3 `downloader` 模块依赖 `ExoPlayer` 内部 API，需确认与 AGP 8.11.1 兼容
2. Java 17 是最低要求（项目已满足），Media3 1.8.0 要求 Java 8+ ✅
3. NDK 28.2 和 Media3 无 native 依赖，不会冲突 ✅

### 2.2 Manifest 声明

**文件**: `android/app/src/main/AndroidManifest.xml`

需要添加的权限：

```xml
<!-- 前台服务权限（DownloadService 需要） -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
<!-- Android 14+ 需要声明前台服务类型 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<!-- 精确闹钟（用于断点续传调度） -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<!-- WAKE_LOCK（保活） -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

需要添加的 Service：

```xml
<application ...>
    <!-- ── Media3 DownloadService ── -->
    <service
        android:name=".VideoDownloadService"
        android:exported="false"
        android:foregroundServiceType="dataSync"
        android:permission="android.permission.FOREGROUND_SERVICE" />

    <!-- 保留现有的 QuizAccessibilityService 等... -->
</application>
```

**风险点**:
1. Android 14+ (API 34) 要求所有前台服务声明 `foregroundServiceType`，我们使用 `dataSync`
2. Android 12+ (API 31+) 启动前台服务需要先启动 `START_STICKY` 的普通前台服务
3. `FOREGROUND_SERVICE_DATA_SYNC` 权限仅在 API 34+ 需要

### 2.3 Kotlin 实现文件

#### 2.3.1 `VideoDownloadService.kt`

**路径**: `android/app/src/main/kotlin/com/example/box/VideoDownloadService.kt`

```kotlin
package com.example.box

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.media3.database.ExoDatabaseProvider
import androidx.media3.downloader.DownloadService
import androidx.media3.downloader.DownloadRequest
import androidx.media3.downloader.ForegroundConfig
import androidx.media3.downloader.HttpDataSource
import androidx.media3.extractor.ts.PsiContinuityError
import com.google.common.util.concurrent.ListenableFuture
import java.util.UUID

class VideoDownloadService : DownloadService(
    notificationChannelId = CHANNEL_ID,
    notificationId = NOTIFICATION_ID,
) {
    companion object {
        private const val CHANNEL_ID = "video_downloads"
        private const val NOTIFICATION_ID = 0x2024_12_01
        private const val REQUEST_QUEUE_ID = 1

        @Volatile
        private var _databaseProvider: ExoDatabaseProvider? = null

        val databaseProvider: ExoDatabaseProvider
            get() = _databaseProvider ?: synchronized(this) {
                _databaseProvider ?: ExoDatabaseProviderINSTANCE.also { _databaseProvider = it }
            }

        /** 从 Flutter 侧调用此方法获取 downloadUri */
        fun buildDownloadRequest(
            context: Context,
            taskId: String,
            url: String,
            referer: String? = null,
            totalBytes: Long = 0L,
        ): DownloadRequest {
            val requestBuilder = DownloadRequest.Builder(
                context.packageName,
                UUID.nameUUIDFromBytes(taskId.toByteArray()).toInt(),
                REQUEST_QUEUE_ID,
            ).setData(taskId.toByteArray())

            // 构建带 Referer 的 DataSource.Factory
            val dataSourceFactory = HttpDataSource.Factory().apply {
                setUserAgent("Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36")
                if (!referer.isNullOrBlank()) {
                    setDefaultRequestProperties(mapOf("Referer" to referer))
                }
            }.also { factory ->
                // 注意：需要在 createDataSource 时传入
            }

            return requestBuilder.build()
        }
    }

    override fun getForegroundConfigBuilder(): ListenableFuture<ForegroundConfig> {
        // Android 14+ 要求前台服务配置
        return com.google.common.util.concurrent.Futures.immediateFuture(
            ForegroundConfig.Builder()
                .setNotificationId(NOTIFICATION_ID)
                .setNotificationChannelId(CHANNEL_ID)
                .build()
        )
    }

    override fun onCreate() {
        super.onCreate()
        // 创建通知渠道
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "视频离线下载",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "后台视频下载进度通知"
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    override fun toNotification(download: androidx.media3.downloader.Download?): Notification? {
        return if (download != null) {
            val taskId = String(download.request.data, Charsets.UTF_8)
            NotificationCompat.Builder(applicationContext, CHANNEL_ID)
                .setContentTitle("正在下载: $taskId")
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setOngoing(true)
                .setProgress(100, download.percentCompleted.toInt(), download.status == androidx.media3.downloader.Download.STATUS_WAITING)
                .build()
        } else {
            null
        }
    }

    override fun shouldStopDownloadWithInProgress(): Boolean = false
    override fun shouldStopForegroundStop(reason: Int): Boolean = reason == FOREGROUND_STOP_NOT_IN_PROGRESS
}
```

**关键设计决策**:
1. `DownloadService` 继承 Google Media3 基类，自动处理前台服务和通知
2. `shouldStopDownloadWithInProgress() = false`：应用退出时不取消下载
3. 使用 `UUID.nameUUIDFromBytes(taskId)` 作为 download ID，保证可复现
4. `setData(taskId.toByteArray())` 携带 Flutter 侧的任务 ID

#### 2.3.2 `DownloadManager.kt`

**路径**: `android/app/src/main/kotlin/com/example/box/DownloadManager.kt`

```kotlin
package com.example.box

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.os.IBinder
import android.util.Log
import androidx.media3.downloader.DownloadService
import androidx.media3.downloader.DownloadService.Binder
import androidx.media3.exoplayer.upstream.DefaultHttpDataSource
import com.example.box.VideoDownloadService.Companion.buildDownloadRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

private const val TAG = "DownloadManager"

/**
 * 下载管理器：封装 DownloadService 绑定、任务队列、状态同步。
 * 
 * 生命周期：
 * 1. Flutter 侧通过 MethodChannel 调用 enqueue/pause/resume/cancel
 * 2. DownloadManager 转发到 DownloadService
 * 3. DownloadService 通过 onDownloadChanged 回调推送状态更新
 * 4. Flutter 侧通过 MethodChannel.invokeMethod 回传状态到 Dart
 */
class DownloadManager(private val context: Context) {
    private val _downloads = MutableStateFlow<Map<String, DownloadInfo>>(emptyMap())
    val downloads: StateFlow<Map<String, DownloadInfo>> = _downloads.asStateFlow()

    private var binder: Binder? = null
    private var serviceConnected = false

    // 绑定 DownloadService
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            binder = service?.let { Binder.from(it) }
            serviceConnected = true
            Log.d(TAG, "DownloadService connected")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            binder = null
            serviceConnected = false
            Log.d(TAG, "DownloadService disconnected")
        }
    }

    init {
        bindService()
    }

    private fun bindService() {
        val intent = android.content.Intent(context, VideoDownloadService::class.java).apply {
            setPackage(context.packageName)
        }
        try {
            context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        } catch (e: Exception) {
            Log.w(TAG, "bindService failed", e)
        }
    }

    /** 入队下载任务 */
    fun enqueue(taskId: String, url: String, referer: String? = null, totalBytes: Long = 0L) {
        val binder = binder ?: run {
            Log.w(TAG, "enqueue: service not connected")
            return
        }

        val request = buildDownloadRequest(context, taskId, url, referer, totalBytes)
        
        // 检查是否已存在同 ID 任务
        val existing = binder.downloadQueue.getDownload(taskId)
        if (existing != null && existing.status == androidx.media3.downloader.Download.STATUS_COMPLETED) {
            Log.d(TAG, "enqueue: task $taskId already completed, skipping")
            return
        }

        binder.downloadQueue.enqueue(request)
        Log.d(TAG, "enqueue: taskId=$taskId url=$url")
    }

    /** 暂停任务 */
    fun pause(taskId: String) {
        binder?.downloadQueue?.removeDownload(taskId)
    }

    /** 恢复任务 */
    fun resume(taskId: String) {
        val download = binder?.downloadQueue?.getDownload(taskId)
        download?.let {
            binder?.downloadQueue?.enqueue(it.request)
        }
    }

    /** 取消并移除任务 */
    fun cancel(taskId: String) {
        binder?.downloadQueue?.removeDownload(taskId)
    }

    /** 获取所有下载状态 */
    fun snapshots(): List<Map<String, Any?>> {
        val binder = binder ?: return emptyList()
        return binder.downloadQueue.downloads.map { download ->
            val taskId = String(download.request.data, Charsets.UTF_8)
            mapOf(
                "id" to taskId,
                "url" to download.request.uri.toString(),
                "status" to download.status,
                "bytesDownloaded" to download.bytesDownloaded,
                "totalBytes" to download.totalBytes,
                "percentCompleted" to download.percentCompleted,
            )
        }
    }

    data class DownloadInfo(
        val taskId: String,
        val url: String,
        val status: Int,
        val bytesDownloaded: Long,
        val totalBytes: Long,
        val percentCompleted: Float,
    )
}
```

#### 2.3.3 MainActivity 扩展

**文件**: `android/app/src/main/kotlin/com/example/box/MainActivity.kt`

在现有 `configureFlutterEngine` 中注册新的 MethodChannel：

```kotlin
// 在现有 MethodChannel ("com.example.box/quiz_plugin") 之后添加:
private var downloadManager: DownloadManager? = null

// 在 configureFlutterEngine 中:
downloadManager = DownloadManager(this)

MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.box/video_downloads").setMethodCallHandler { call, result ->
    when (call.method) {
        "enqueue" -> {
            val args = call.arguments<Map<*, *>>() ?: run { result.error("INVALID_ARGS", "null arguments", null); return@setMethodCallHandler }
            val taskId = args["id"]?.toString() ?: ""
            val mediaUrl = args["mediaUrl"]?.toString() ?: ""
            val referer = args["referer"]?.toString()?.takeIf { it.isNotEmpty() }
            val totalBytes = (args["totalBytes"] as? Number)?.toLong() ?: 0L
            downloadManager?.enqueue(taskId, mediaUrl, referer, totalBytes)
            result.success(null)
        }
        "pause" -> {
            val id = call.argument<String>("id") ?: ""
            downloadManager?.pause(id)
            result.success(null)
        }
        "resume" -> {
            val id = call.argument<String>("id") ?: ""
            downloadManager?.resume(id)
            result.success(null)
        }
        "cancel" -> {
            val id = call.argument<String>("id") ?: ""
            downloadManager?.cancel(id)
            result.success(null)
        }
        "remove" -> {
            val id = call.argument<String>("id") ?: ""
            downloadManager?.cancel(id)
            result.success(null)
        }
        "snapshots" -> {
            val list = downloadManager?.snapshots() ?: emptyList()
            result.success(list)
        }
        else -> result.notImplemented()
    }
}
```

### 2.4 Flutter 侧 MethodChannel 对接

**文件**: `lib/video/services/video_download_gateway.dart`

现有接口已定义，只需确保参数映射匹配：

```dart
// MethodChannelVideoDownloadGateway 已有的方法签名：
// enqueue(task.toMap())    → 对应 native "enqueue"
// pause(id)                → 对应 native "pause"
// resume(id)               → 对应 native "resume"
// cancel(id)               → 对应 native "cancel"
// remove(id)               → 对应 native "remove"
// snapshots()              → 对应 native "snapshots"
```

**参数映射** (`VideoDownloadTask.toMap()`):
```dart
{
  'id': task.id,
  'mediaUrl': task.mediaUrl,
  'referer': task.referer,
  'totalBytes': task.totalBytes,
  // ... 其他字段供 Flutter 侧使用
}
```

### 2.5 详情页下载入口

**文件**: `lib/video/pages/video_detail_page.dart`

在 `_buildPlaybackPanel` 中，每个剧集项添加下载按钮：

```dart
// 在 _buildEpisodeSection 的每个 episode tile 上:
leading: IconButton(
    icon: Icon(_isDownloaded(vodId, episodeIndex) 
        ? Icons.check_circle : Icons.download),
    onPressed: () => _startDownload(controller),
),
```

下载触发逻辑：
```dart
void _startDownload(VideoDetailController controller) {
    final line = controller.playLines[controller.selectedLineIndex];
    final ep = line.episodes[controller.selectedEpisodeIndex];
    
    // 通过 MethodChannel 发送到原生层
    const channel = MethodChannel('com.example.box/video_downloads');
    channel.invokeMethod('enqueue', {
        'id': '${controller.vodId}_${controller.selectedLineIndex}_${controller.selectedEpisodeIndex}',
        'mediaUrl': ep.url,
        'referer': controller.source.detailUrl,
        'totalBytes': 0, // 暂不预知大小
    });
}
```

---

## 三、状态事件同步机制

### 3.1 原生 → Flutter 状态推送

使用 `MethodChannel.invokeMethod` 从 DownloadService 回调推送到 Flutter：

```kotlin
// 在 DownloadManager 中，当下载状态变化时:
private fun notifyFlutter(method: String, args: Map<String, Any?>) {
    val engine = FlutterEngineCache.getInstance().get("quiz_engine")
    engine?.dartExecutor?.binaryMessenger?.let { messenger ->
        MethodChannel(messenger, "com.example.box/video_downloads")
            .invokeMethod(method, args)
    }
}
```

### 3.2 Flutter 侧状态监听

```dart
class VideoDownloadController extends ChangeNotifier {
    final VideoDownloadGateway _gateway;
    final Map<String, VideoDownloadTask> _tasks = {};

    VideoDownloadController({required VideoDownloadGateway gateway})
        : _gateway = gateway;

    Future<void> loadSnapshots() async {
        final raw = await _gateway.snapshots();
        for (final item in raw) {
            final task = VideoDownloadTask.fromMap(item);
            _tasks[task.id] = task;
        }
        notifyListeners();
    }

    /// 定时轮询（每 5 秒）或事件驱动刷新
    void refreshAfterChange() {
        unawaited(loadSnapshots());
    }
}
```

---

## 四、文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `android/app/build.gradle.kts` | **修改** | 添加 Media3 依赖 |
| `android/app/src/main/AndroidManifest.xml` | **修改** | 添加权限 + VideoDownloadService |
| `android/app/src/main/kotlin/com/example/box/VideoDownloadService.kt` | **新建** | DownloadService 实现 |
| `android/app/src/main/kotlin/com/example/box/DownloadManager.kt` | **新建** | 下载管理桥接层 |
| `android/app/src/main/kotlin/com/example/box/MainActivity.kt` | **修改** | 注册 video_downloads channel |
| `lib/video/services/video_download_gateway.dart` | **验证** | 接口已存在，确认参数匹配 |
| `lib/video/services/hive_video_download_repository.dart` | **验证** | 持久化已存在 |
| `lib/video/pages/video_detail_page.dart` | **修改** | 添加下载按钮入口 |
| `lib/video/controller/video_detail_controller.dart` | **修改** | 添加下载方法 |

---

## 五、风险与注意事项

### 5.1 编译风险

1. **Media3 1.8.0 + AGP 8.11.1**: 需验证兼容性。如编译失败，降级到 1.7.0 或升级 AGP
2. **Java 17**: Media3 支持 ✅，但部分旧插件可能有问题 → 项目无此类插件
3. **NDK 28.2**: Media3 downloader 无 native 代码，不会冲突 ✅

### 5.2 运行时风险

1. **Android 14+ 前台服务类型声明**: 必须正确声明 `foregroundServiceType="dataSync"`，否则崩溃
2. **Storage 权限**: 已有 `READ/WRITE_EXTERNAL_STORAGE`，Android 13+ 需要动态请求
3. **HLS 分片下载**: Media3 `DefaultHttpDataSource` 默认不支持 Range 请求的 HLS 分片断点续传 → 需自定义 `DataSource.Factory`
4. **Referer 头传递**: Media3 DownloadService 的 `HttpDataSource.Factory` 需要在 `buildDownloadRequest` 时设置 default request properties

### 5.3 架构风险

1. **FlutterEngineCache 耦合**: DownloadManager 依赖 `"quiz_engine"` 缓存的 FlutterEngine 来推送状态 → 如果 quiz_engine 被清理（MainActivity.onDestroy），推送会失败
   - **缓解**: 使用独立的 MethodChannel 注册或在 Application 级别持有 Engine
2. **并发控制**: 当前 `VideoDownloadScheduler.maxConcurrentTasks=2`，Media3 内部也有并发限制 → 需统一
3. **存储路径**: Media3 默认下载到 `Context.getCacheDir()`，如需自定义路径（如 `/sdcard/Download/`）需配置 `ExtractorRendererProvider`

### 5.4 国内 ROM 适配

1. MIUI/HarmonyOS 等会杀死后台服务 → 需在设置中白名单
2. 通知可能被折叠 → 使用 `IMPORTANCE_DEFAULT` 或更高
3. 电池优化限制 → 引导用户关闭本应用的电池优化

---

## 六、HLS 特定注意事项

### 6.1 为什么用 Media3 DownloadService 而非 OkHttp 分段下载

| 对比项 | Media3 DownloadService | OkHttp 手动下载 |
|--------|----------------------|-----------------|
| HLS 分片管理 | ✅ 自动解析 m3u8 + 管理 ts 分片 | ❌ 需自行实现 |
| 断点续传 | ✅ 内置数据库记录 | ❌ 需自行实现 |
| 后台运行 | ✅ DownloadService 原生支持 | ❌ 需自建 Service |
| 通知展示 | ✅ 自动 | ❌ 需自建 |
| 并发控制 | ✅ 内置队列 | ❌ 需自建 |
| Referer/Headers | ✅ 支持 | ✅ 支持 |

### 6.2 HLS 下载的特殊处理

Media3 的 `DefaultHttpDataSource` 需要处理：

1. **Master Playlist → Media Playlist 降维**: 复用 `player_stream_resolver.dart` 的逻辑
2. **KEY 加密 (AES-128)**: 如果源有加密，Media3 需要配置 `DecryptingDataSource`
3. **分片过期**: 某些 CDN 的分片 URL 有过期时间，需定期刷新

建议在 `DownloadManager.enqueue` 前做一次 HLS probe：

```kotlin
fun resolveHlsMaster(url: String, headers: Map<String, String>): String {
    // 复用 player_stream_resolver.dart 的降维逻辑
    // 或直接让 Media3 的 Extractors 处理
    return url
}
```

---

## 七、实施优先级

1. **P0**: `VideoDownloadService.kt` + `DownloadManager.kt` + Manifest 声明
2. **P0**: `build.gradle.kts` 添加 Media3 依赖
3. **P1**: MainActivity 注册 MethodChannel
4. **P1**: Flutter 侧 `video_download_gateway.dart` 参数对齐
5. **P2**: 详情页添加下载按钮
6. **P2**: 状态同步（轮询/事件驱动）
7. **P3**: HLS master playlist 降维
8. **P3**: 下载队列 UI 页面
