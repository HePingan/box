package top.hpa888.box

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 接收系统分享（286 P3）。
 *
 * 为什么在原生：`ACTION_SEND` 的附件是 `content://` URI，Dart 侧没有
 * ContentResolver，拿不到真实的文件路径与大小；先由原生把内容**复制**进
 * 应用缓存目录，Dart 侧就能复用已有的"本地文件上传"通路（含队列/续传/落盘），
 * 不需要为分享单独写一套流式上传。
 *
 * 只收图片与视频（`image/*`、`video/*`，见 AndroidManifest 的 intent-filter）：
 * 分享文本/任意文件没有明确落点，出现在候选里只会让用户困惑。
 *
 * 生命周期：冷启动时 Intent 在 Dart 就绪前就到了（此时 Dart 侧 handler 还没挂），
 * 所以**先攒着**（[pending]），Dart 挂好 handler 后调 `ready` / `takePending` 取走；
 * 热启动（`onNewIntent`）时 Dart 已就绪，直接 `onSharedFiles` 推过去。
 */
object ShareInboxReceiver {

    const val CHANNEL = "top.hpa888.box/share_inbox"

    /** Dart → 原生：Dart 侧 handler 已挂好。 */
    private const val METHOD_READY = "ready"

    /** Dart → 原生：取走冷启动时攒下的分享文件。 */
    private const val METHOD_TAKE_PENDING = "takePending"

    /** 原生 → Dart：有新的分享文件（热启动）。 */
    private const val METHOD_ON_SHARED_FILES = "onSharedFiles"

    /** 一次最多收多少个文件：系统分享上限一般也就十几个，多的直接截断。 */
    private const val MAX_FILES = 20

    /** 单个文件复制上限：超过就不收（进缓存再传本来就只是中转，别把存储撑爆）。 */
    private const val MAX_FILE_BYTES = 512L * 1024 * 1024

    /** 缓存里的中转文件保留多久：上传成功会删；失败/中途退出的靠这里兜底清理。 */
    private const val INBOX_TTL_MS = 24L * 60 * 60 * 1000

    private var channel: MethodChannel? = null
    private var dartReady = false
    private val pending = mutableListOf<Map<String, Any?>>()

    fun register(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_READY -> {
                    dartReady = true
                    // 冷启动期间攒下的文件在这里补推（Dart 侧刚挂上 handler）。
                    if (pending.isNotEmpty()) pushToDart()
                    result.success(true)
                }
                METHOD_TAKE_PENDING -> {
                    val out = pending.toList()
                    pending.clear()
                    result.success(out)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Activity 销毁时解绑：否则重建后事件会投向失效 channel。 */
    fun detach() {
        channel = null
        dartReady = false
    }

    fun handleIntent(intent: Intent?, activity: Activity) {
        if (intent == null) return
        val uris = extractUris(intent)
        if (uris.isEmpty()) return

        pruneInbox(activity)

        val copied = mutableListOf<Map<String, Any?>>()
        for (uri in uris.take(MAX_FILES)) {
            val entry = try {
                copyToInbox(activity, uri)
            } catch (_: Throwable) {
                null
            }
            if (entry != null) copied.add(entry)
        }
        if (copied.isEmpty()) return

        pending.addAll(copied)
        if (dartReady) pushToDart()
    }

    private fun extractUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> {
            @Suppress("DEPRECATION")
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri == null) emptyList() else listOf(uri)
        }
        Intent.ACTION_SEND_MULTIPLE -> {
            @Suppress("DEPRECATION")
            val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            list ?: emptyList()
        }
        else -> emptyList()
    }

    private fun pushToDart() {
        val payload = pending.toList()
        if (payload.isEmpty()) return
        pending.clear()
        try {
            channel?.invokeMethod(METHOD_ON_SHARED_FILES, payload)
        } catch (_: Throwable) {
            // 推失败就当没收到：文件已在 inbox 目录，用户可以重发分享。
        }
    }

    private fun inboxDir(activity: Activity): File =
        File(activity.cacheDir, "shared_inbox").apply { mkdirs() }

    /** 扔掉过期中转文件（上传成功会即时删，这里是失败/中断的兜底）。 */
    private fun pruneInbox(activity: Activity) {
        val dir = inboxDir(activity)
        val cutoff = System.currentTimeMillis() - INBOX_TTL_MS
        dir.listFiles()?.forEach { f ->
            try {
                if (f.lastModified() < cutoff) f.delete()
            } catch (_: Throwable) {
            }
        }
    }

    /**
     * 把 `content://` 内容复制进缓存，返回给 Dart 的描述。
     * 拿不到大小（部分 provider 不给）时按复制出来的字节数算。
     */
    private fun copyToInbox(activity: Activity, uri: Uri): Map<String, Any?>? {
        val resolver = activity.contentResolver
        val mime = resolver.getType(uri) ?: ""
        // 双重保险：intent-filter 已经只放 image/video 进来，这里再挡一次。
        if (!mime.startsWith("image/") && !mime.startsWith("video/")) return null

        var name = "shared"
        var declaredSize = -1L
        try {
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx >= 0 && !cursor.isNull(nameIdx)) {
                        name = cursor.getString(nameIdx)
                    }
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                        declaredSize = cursor.getLong(sizeIdx)
                    }
                }
            }
        } catch (_: Throwable) {
        }

        if (declaredSize > MAX_FILE_BYTES) return null

        val safeName = sanitizeName(name, mime)
        val target = File(inboxDir(activity), "${System.currentTimeMillis()}_$safeName")
        var written = 0L
        try {
            resolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        written += n
                        if (written > MAX_FILE_BYTES) {
                            // 中间发现超限：删掉半截文件，当没收到。
                            output.close()
                            target.delete()
                            return null
                        }
                        output.write(buf, 0, n)
                    }
                }
            } ?: return null
        } catch (e: Throwable) {
            target.delete()
            throw e
        }
        if (written <= 0) {
            target.delete()
            return null
        }

        return mapOf(
            "path" to target.absolutePath,
            "name" to safeName,
            "sizeBytes" to written,
            "mimeType" to mime,
        )
    }

    /**
     * 文件名清洗：去掉路径分隔符与上级目录写法，只留纯文件名。
     * 分享来源的名字可能是 `../../x.jpg` 这类，直接拼路径会写到缓存目录之外。
     */
    private fun sanitizeName(raw: String, mime: String): String {
        val base = raw.substringAfterLast('/').substringAfterLast('\\').trim()
        val cleaned = base.replace(Regex("[\\u0000-\\u001f]"), "").trim()
        if (cleaned.isEmpty() || cleaned == "." || cleaned == "..") {
            val ext = when {
                mime.startsWith("image/") -> ".jpg"
                mime.startsWith("video/") -> ".mp4"
                else -> ".bin"
            }
            return "shared$ext"
        }
        return cleaned.take(120)
    }
}
