package com.example.box

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.StatFs
import androidx.core.app.NotificationCompat
import java.io.BufferedInputStream
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * 轻量视频下载服务 — 使用 HttpURLConnection 分段下载，支持断点续传。
 *
 * 关键设计：任务状态存放在 companion 的静态 [sharedTasks] 中（进程内共享），
 * 这样 MainActivity 无需持有 Service 实例即可通过 [snapshotList] 读取真实进度，
 * 打通「原生下载 → Flutter 轮询」的回传链路。
 */
class VideoDownloadService : Service() {
    companion object {
        const val ACTION_ENQUEUE = "com.example.box.ACTION_ENQUEUE"
        const val ACTION_PAUSE = "com.example.box.ACTION_PAUSE"
        const val ACTION_RESUME = "com.example.box.ACTION_RESUME"
        const val ACTION_CANCEL = "com.example.box.ACTION_CANCEL"
        const val ACTION_REMOVE = "com.example.box.ACTION_REMOVE"
        const val EXTRA_TASK_DATA = "com.example.box.EXTRA_TASK_DATA"
        const val EXTRA_TASK_ID = "com.example.box.EXTRA_TASK_ID"
        const val NOTIFICATION_CHANNEL_ID = "video_download_channel"
        const val NOTIFICATION_ID = 1001
        private const val CHUNK_SIZE = 8192 // 8KB chunks
        private const val PROGRESS_UPDATE_BYTES = 64 * 1024L // 每累计 64KB 回传一次进度
        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36"

        // 进程内共享的任务快照 —— 供 MainActivity.handleSnapshots 读取。
        private val sharedTasks = ConcurrentHashMap<String, DownloadTask>()

        // 下载线程的控制标志: taskId -> "pause" / "cancel"。
        private val controlFlags = ConcurrentHashMap<String, String>()

        /** MainActivity 通过 MethodChannel 'snapshots' 调用，返回全部任务的真实状态。 */
        fun snapshotList(): List<Map<String, Any>> =
            sharedTasks.values.map { it.toSnapshotMap() }

        fun restoreTasks(context: Context) {
            if (sharedTasks.isNotEmpty()) return
            val cacheDir = File(context.filesDir, "video_downloads")
            DownloadTaskStore(context).readAll().forEach { stored ->
                val localFile = File(cacheDir, "${stored.id}.mp4")
                val interrupted = stored.status == "downloading" || stored.status == "queued"
                sharedTasks[stored.id] = if (interrupted) {
                    stored.copy(
                        status = "paused",
                        downloadedBytes = if (localFile.exists()) localFile.length() else stored.downloadedBytes,
                        downloadSpeedBytesPerSecond = 0L,
                        errorMessage = "应用重启后已暂停，可继续下载",
                        updatedAt = System.currentTimeMillis()
                    )
                } else {
                    stored
                }
            }
        }

        fun taskForId(context: Context, taskId: String): DownloadTask? {
            restoreTasks(context)
            return sharedTasks[taskId]
        }
    }

    private val downloadThreads = ConcurrentHashMap<String, Thread>()
    private lateinit var notificationManager: NotificationManager
    private lateinit var notificationBuilder: NotificationCompat.Builder
    private var foregroundStarted = false

    override fun onCreate() {
        super.onCreate()
        restoreTasks(this)
        persistTasks()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
        notificationBuilder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("视频下载")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "视频下载",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示视频下载进度"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * 关键修复：以 startForegroundService 启动后必须在 ~5s 内调用 startForeground，
     * 否则 Android 8+ 抛 ForegroundServiceDidNotStartInTimeException 直接杀死服务。
     */
    private fun ensureForeground() {
        if (foregroundStarted) return
        val notification = notificationBuilder.setContentText("准备下载…").build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregroundStarted = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureForeground()
        intent?.let {
            when (it.action) {
                ACTION_ENQUEUE ->
                    it.getBundleExtra(EXTRA_TASK_DATA)?.let { b -> enqueueFromBundle(b) }
                ACTION_PAUSE ->
                    it.getStringExtra(EXTRA_TASK_ID)?.let { id -> pauseTask(id) }
                ACTION_RESUME ->
                    it.getStringExtra(EXTRA_TASK_ID)?.let { id -> resumeTask(id) }
                ACTION_CANCEL ->
                    it.getStringExtra(EXTRA_TASK_ID)?.let { id -> cancelTask(id) }
                ACTION_REMOVE ->
                    it.getStringExtra(EXTRA_TASK_ID)?.let { id -> removeTask(id) }
            }
        }
        // 处理完控制指令后，若已无活跃下载，及时收尾避免常驻通知。
        checkStopSelf()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun persistTasks() {
        DownloadTaskStore(this).writeAll(sharedTasks.values)
    }

    // ─────────────────────── 入队 / 续传 ───────────────────────

    private fun enqueueFromBundle(bundle: Bundle) {
        val taskId = bundle.getString("id") ?: return
        val mediaUrl = bundle.getString("media_url") ?: return
        val episodeName = bundle.getString("episode_name") ?: ""
        val sourceName = bundle.getString("source_name") ?: ""
        val referer = bundle.getString("referer") ?: ""

        if (!mediaUrl.startsWith("https://")) {
            putFailed(taskId, episodeName, sourceName, mediaUrl, referer, "仅支持HTTPS链接进行下载")
            return
        }

        // 已在下载中 → 忽略重复入队。
        downloadThreads[taskId]?.let { if (it.isAlive) return }

        val cacheDir = File(filesDir, "video_downloads").apply { mkdirs() }
        val outputFile = File(cacheDir, "$taskId.mp4")

        // HLS resumes by playlist segment, not by byte range. The companion
        // `.hls-state` file records the next fully completed segment, so the
        // partial output stays intact and can be appended safely after a pause.
        // 已完成且文件仍在 → 无需重下。
        val existing = sharedTasks[taskId]
        if (existing?.status == "completed" && outputFile.exists() && outputFile.length() > 0) {
            return
        }

        // 清除旧的暂停/取消标记（例如“继续”会走这里重新入队）。
        controlFlags.remove(taskId)

        val alreadyBytes = if (outputFile.exists()) outputFile.length() else 0L

        // ── A2: 存储空间预检 ──
        val requiredSpace = estimateRequiredSpace(alreadyBytes, existing)
        val availableSpace = getAvailableStorageBytes(cacheDir)
        if (availableSpace < requiredSpace + DownloadExecutionPolicy.STORAGE_RESERVE_BYTES) {
            val needed = requiredSpace + DownloadExecutionPolicy.STORAGE_RESERVE_BYTES - availableSpace
            putFailed(taskId, episodeName, sourceName, mediaUrl, referer,
                "存储空间不足（需要 ${formatBytes(needed)}）")
            return
        }

        val task = existing?.copy(
            status = "downloading",
            downloadedBytes = alreadyBytes,
            errorMessage = "",
            episodeName = episodeName.ifEmpty { existing.episodeName },
            sourceName = sourceName.ifEmpty { existing.sourceName },
            referer = referer.ifEmpty { existing.referer },
            updatedAt = System.currentTimeMillis()
        ) ?: DownloadTask(
            id = taskId,
            sourceId = "",
            vodId = "",
            vodName = "",
            sourceName = sourceName,
            episodeName = episodeName,
            mediaUrl = mediaUrl,
            referer = referer,
            status = "downloading",
            downloadedBytes = alreadyBytes,
            totalBytes = 0L,
            downloadSpeedBytesPerSecond = 0L,
            localPath = outputFile.absolutePath,
            errorMessage = "",
            isPlaybackActive = false,
            createdAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis()
        )
        sharedTasks[taskId] = task
        persistTasks()
        updateNotification(task)

        // ── A1: 并发队列调度 ──
        val activeCount = downloadThreads.count { it.value.isAlive }
        if (activeCount >= DownloadExecutionPolicy.MAX_CONCURRENT_TASKS) {
            // 队列已满 → 标记为 queued，等当前下载完成后再自动启动。
            sharedTasks[taskId] = task.copy(status = "queued", updatedAt = System.currentTimeMillis())
            persistTasks()
            return
        }

        launchDownloadThread(mediaUrl, referer, outputFile, taskId, alreadyBytes)
        // 尝试启动后续排队任务。
        drainQueue()
    }

    /**
     * 尝试从排队任务中启动下一个（当有并发槽位时）。
     */
    private fun drainQueue() {
        val activeCount = downloadThreads.count { it.value.isAlive }
        val queuedIds = DownloadExecutionPolicy.nextTaskIds(
            sharedTasks.values.filter { it.status == "queued" }.toList(),
            activeCount
        )
        for (qid in queuedIds) {
            val qTask = sharedTasks[qid] ?: continue
            val outputFile = File(File(filesDir, "video_downloads"), "$qid.mp4")
            launchDownloadThread(qTask.mediaUrl, qTask.referer, outputFile, qid, qTask.downloadedBytes)
        }
    }

    private fun launchDownloadThread(
        mediaUrl: String,
        referer: String,
        outputFile: File,
        taskId: String,
        startByte: Long
    ) {
        val thread = Thread {
            var lastException: Exception? = null
            var attempt = 0
            while (attempt <= DownloadExecutionPolicy.MAX_RETRIES) {
                try {
                    downloadMedia(mediaUrl, referer, outputFile, taskId, startByte)
                    // 文件已完整落盘后才发布 completed；避免 Flutter 先拿到“完成”快照、
                    // 而播放器打开仍未 sync 的半成品文件。
                    if (controlFlags[taskId] == null && verifyCompletedFile(outputFile, taskId)) {
                        File(outputFile.parentFile, "$taskId.hls-state").delete()
                        updateTask(taskId, status = "completed", downloadSpeedBytesPerSecond = 0L)
                    } else if (controlFlags[taskId] == null) {
                        updateTask(taskId, status = "failed", errorMessage = "下载文件不完整")
                    }
                    break // success → exit retry loop
                } catch (_: InterruptedException) {
                    // 被 remove/cancel 中断，状态已在对应处理里设置。
                    return@Thread
                } catch (e: Exception) {
                    lastException = e
                    val flag = controlFlags[taskId]
                    if (flag == "cancel" || flag == "pause") {
                        // Explicit pause/cancel overrides retry.
                        return@Thread
                    }
                    val classification = DownloadExecutionPolicy.classifyFailure(e)
                    if (!classification.retryable || attempt >= DownloadExecutionPolicy.MAX_RETRIES) {
                        // Final failure or non-retryable.
                        val msg = if (attempt >= DownloadExecutionPolicy.MAX_RETRIES) {
                            "多次重试失败：${classification.userMessage}"
                        } else {
                            classification.userMessage
                        }
                        updateTask(taskId, status = "failed", errorMessage = msg)
                        break
                    }
                    // Retryable → wait for backoff then retry.
                    val delayMs = DownloadExecutionPolicy.retryDelayMillis(attempt + 1)
                    updateTask(taskId, errorMessage = "${classification.userMessage}（将在 ${(delayMs / 1000)}s 后重试 ${attempt + 1}/${DownloadExecutionPolicy.MAX_RETRIES}）")
                    Thread.sleep(delayMs)
                    attempt++
                }
            }
        }
        thread.isDaemon = true
        downloadThreads[taskId] = thread
        thread.start()
    }

    // ─────────────────────── 下载实现 ───────────────────────

    private fun downloadMedia(
        urlStr: String,
        referer: String,
        outputFile: File,
        taskId: String,
        startByte: Long
    ) {
        if (urlStr.substringBefore('?').endsWith(".m3u8", ignoreCase = true)) {
            downloadHls(urlStr, referer, outputFile, taskId)
        } else {
            downloadFile(urlStr, referer, outputFile, taskId, startByte)
        }
    }

    /**
     * HLS is a playlist, not an MP4. Resolve its media playlist and append every
     * TS segment, so the output is a real local video file instead of a 96-byte
     * `index.m3u8` text document.
     */
    private fun downloadHls(
        masterUrl: String,
        referer: String,
        outputFile: File,
        taskId: String
    ) {
        val master = readText(masterUrl, referer)
        val mediaUrl = if (HlsPlaylistResolver.isMasterPlaylist(master)) {
            HlsPlaylistResolver.selectVariantUrl(masterUrl, master)
        } else {
            masterUrl
        }
        val mediaPlaylist = if (mediaUrl == masterUrl) master else readText(mediaUrl, referer)
        if (!HlsPlaylistResolver.isCompleteVodPlaylist(mediaPlaylist)) {
            throw IllegalArgumentException("直播流暂不支持离线下载")
        }
        val segments = HlsPlaylistResolver.mediaSegmentUrls(mediaUrl, mediaPlaylist)
        if (segments.isEmpty()) throw IllegalArgumentException("HLS 播放列表没有视频分片")

        // Estimate total size from the first segment as a warm-up.
        val segmentCount = segments.size
        var estimatedTotalBytes = estimateTotalSize(segments[0], referer, segmentCount)

        outputFile.parentFile?.mkdirs()
        val stateFile = File(outputFile.parentFile, "${taskId}.hls-state")
        var nextSegmentIndex = readHlsResumeIndex(stateFile)
        if (nextSegmentIndex !in 0..segmentCount) {
            nextSegmentIndex = 0
            stateFile.delete()
        }

        RandomAccessFile(outputFile, "rw").use { output ->
            // State is written only after a full segment. Therefore content after
            // this boundary belongs to an interrupted segment and is discarded.
            val resumeOffset = readHlsResumeOffset(stateFile)
            if (nextSegmentIndex == 0) {
                output.setLength(0)
            } else if (resumeOffset in 0..output.length()) {
                output.setLength(resumeOffset)
                output.seek(resumeOffset)
            } else {
                nextSegmentIndex = 0
                stateFile.delete()
                output.setLength(0)
            }
            var downloaded = output.length()
            // Speed tracking — rolling window of last 5 seconds.
            var speedBytes = 0L
            var speedSince = System.currentTimeMillis()
            updateTask(taskId, downloadedBytes = downloaded, totalBytes = estimatedTotalBytes)
            for (index in nextSegmentIndex until segmentCount) {
                val segmentUrl = segments[index]
                when (controlFlags[taskId]) {
                    "pause" -> {
                        output.fd.sync()
                        updateTask(taskId, status = "paused", downloadedBytes = downloaded, downloadSpeedBytesPerSecond = 0L)
                        return
                    }
                    "cancel" -> return
                }
                val connection = openConnection(segmentUrl, referer)
                try {
                    BufferedInputStream(connection.inputStream).use { input ->
                        val buffer = ByteArray(CHUNK_SIZE)
                        while (true) {
                            when (controlFlags[taskId]) {
                                "pause" -> {
                                    output.fd.sync()
                                    // Do not record this partial segment. On resume it is
                                    // truncated back to the last fully persisted boundary.
                                    updateTask(taskId, status = "paused", downloadedBytes = downloaded, downloadSpeedBytesPerSecond = 0L)
                                    return
                                }
                                "cancel" -> return
                            }
                            val bytesRead = input.read(buffer)
                            if (bytesRead == -1) break
                            output.write(buffer, 0, bytesRead)
                            downloaded += bytesRead
                            speedBytes += bytesRead
                            if (downloaded % PROGRESS_UPDATE_BYTES < bytesRead) {
                                val speed = calculateSpeed(speedBytes, speedSince, System.currentTimeMillis())
                                updateTask(taskId, downloadedBytes = downloaded, downloadSpeedBytesPerSecond = speed)
                            }
                        }
                    }
                } finally {
                    connection.disconnect()
                }
                // A segment is durable only after its bytes have been synced;
                // persist the checkpoint so pause/resume continues at index + 1.
                output.fd.sync()
                writeHlsResumeState(stateFile, index + 1, downloaded)
                // Refine estimate after each segment.
                if (index < 20) {
                    estimatedTotalBytes = refineEstimate(estimatedTotalBytes, index + 1, downloaded, segmentCount)
                    updateTask(taskId, totalBytes = estimatedTotalBytes)
                }
                // Update speed at segment boundary.
                val speed = calculateSpeed(speedBytes, speedSince, System.currentTimeMillis())
                updateTask(taskId, downloadedBytes = downloaded, downloadSpeedBytesPerSecond = speed)
                // Rolling window: keep only bytes downloaded in the last 5 seconds.
                val now = System.currentTimeMillis()
                if (now - speedSince >= 5000L) {
                    val elapsed = (now - speedSince) / 1000.0
                    val avgSpeed = (speedBytes / elapsed).toLong()
                    speedBytes = avgSpeed.coerceAtLeast(0L)
                    speedSince = now
                }
            }
            output.fd.sync()
            stateFile.delete()
            updateTask(taskId, downloadedBytes = downloaded, totalBytes = downloaded, downloadSpeedBytesPerSecond = 0L)
        }
    }

    private fun readHlsResumeIndex(stateFile: File): Int =
        runCatching { stateFile.readLines().firstOrNull()?.toIntOrNull() ?: 0 }.getOrDefault(0)

    private fun readHlsResumeOffset(stateFile: File): Long =
        runCatching { stateFile.readLines().getOrNull(1)?.toLongOrNull() ?: 0L }.getOrDefault(0L)

    private fun writeHlsResumeState(stateFile: File, nextSegmentIndex: Int, byteOffset: Long) {
        stateFile.writeText("$nextSegmentIndex\n$byteOffset\n")
    }

    /** Calculate instantaneous speed from a 5-second rolling window. */
    private fun calculateSpeed(speedBytes: Long, sinceMs: Long, nowMs: Long): Long {
        val elapsed = (nowMs - sinceMs) / 1000.0
        return if (elapsed > 0) (speedBytes / elapsed).toLong() else 0L
    }

    /** Probe the first segment to get a rough total size before streaming all segments. */
    private fun estimateTotalSize(firstSegmentUrl: String, referer: String, segmentCount: Int): Long {
        return try {
            val conn = openConnection(firstSegmentUrl, referer)
            val cl = conn.contentLengthLong
            conn.disconnect()
            if (cl > 0) cl * segmentCount else 0L
        } catch (_: Exception) {
            0L
        }
    }

    /** Gradually shift the estimate toward actual downloaded / segments_ratio. */
    private fun refineEstimate(current: Long, completedSegments: Int, downloaded: Long, totalSegments: Int): Long {
        if (completedSegments < 3) return current
        val ratio = completedSegments.toDouble() / totalSegments
        val projected = (downloaded * totalSegments / completedSegments).toLong()
        // Blend: start from the probe-based estimate, then gradually converge to actual ratio.
        return (current * 0.7 + projected * 0.3).toLong()
    }

    private fun readText(urlStr: String, referer: String): String {
        val connection = openConnection(urlStr, referer)
        return try {
            BufferedReader(InputStreamReader(connection.inputStream, StandardCharsets.UTF_8)).use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun openConnection(urlStr: String, referer: String): HttpURLConnection =
        (URL(urlStr).openConnection() as HttpURLConnection).apply {
            setRequestProperty("User-Agent", USER_AGENT)
            if (referer.isNotEmpty()) setRequestProperty("Referer", referer)
            connectTimeout = 30_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            connect()
        }

    private fun downloadFile(
        urlStr: String,
        referer: String,
        outputFile: File,
        taskId: String,
        startByte: Long
    ) {
        var conn: HttpURLConnection? = null
        var raf: RandomAccessFile? = null
        try {
            val url = URL(urlStr)
            conn = (url.openConnection() as HttpURLConnection).apply {
                setRequestProperty("User-Agent", USER_AGENT)
                if (referer.isNotEmpty()) setRequestProperty("Referer", referer)
                if (startByte > 0) setRequestProperty("Range", "bytes=$startByte-")
                connectTimeout = 30_000
                readTimeout = 30_000
                instanceFollowRedirects = true
                connect()
            }

            // 206 表示服务器支持断点续传；否则从头覆盖。
            val supportsResume =
                startByte > 0 && conn.responseCode == HttpURLConnection.HTTP_PARTIAL
            val writePos = if (supportsResume) startByte else 0L

            val remaining = conn.contentLengthLong
            val total = when {
                supportsResume && remaining > 0 -> writePos + remaining
                remaining > 0 -> remaining
                else -> sharedTasks[taskId]?.totalBytes ?: 0L
            }
            updateTask(taskId, downloadedBytes = writePos, totalBytes = total)

            raf = RandomAccessFile(outputFile, "rw")
            if (supportsResume) {
                raf.seek(writePos)
            } else {
                raf.setLength(0)
            }

            val buffer = ByteArray(CHUNK_SIZE)
            var bytesRead: Int
            var totalBytesRead = writePos
            var lastReported = writePos
            val input = conn.inputStream
            while (input.read(buffer).also { bytesRead = it } != -1) {
                when (controlFlags[taskId]) {
                    "pause" -> {
                        raf.fd.sync()
                        updateTask(taskId, status = "paused", downloadedBytes = totalBytesRead)
                        return
                    }
                    "cancel" -> return
                }
                raf.write(buffer, 0, bytesRead)
                totalBytesRead += bytesRead
                if (totalBytesRead - lastReported >= PROGRESS_UPDATE_BYTES) {
                    updateTask(taskId, downloadedBytes = totalBytesRead)
                    lastReported = totalBytesRead
                }
            }
            raf.fd.sync()
            updateTask(taskId, downloadedBytes = totalBytesRead)
        } finally {
            try {
                raf?.close()
            } catch (_: Exception) {
            }
            conn?.disconnect()
        }
    }

    /**
     * 将“完成”与实际文件状态绑定。Content-Length 缺失时只能验证非空；
     * 有长度时必须已写满，避免伪完成任务进入离线播放器。
     */
    private fun verifyCompletedFile(outputFile: File, taskId: String): Boolean {
        if (!outputFile.exists() || outputFile.length() <= 0L) return false
        val task = sharedTasks[taskId] ?: return false
        val isHls = task.mediaUrl.substringBefore('?').endsWith(".m3u8", ignoreCase = true)
        if (isHls && File(outputFile.parentFile, "$taskId.hls-state").exists()) return false
        val expectedBytes = task.totalBytes
        return expectedBytes <= 0L || outputFile.length() >= expectedBytes
    }

    // ─────────────────────── 控制指令 ───────────────────────

    private fun pauseTask(taskId: String) {
        controlFlags[taskId] = "pause"
        val thread = downloadThreads[taskId]
        if (thread == null || !thread.isAlive) {
            // 线程已结束，直接兜底标记。
            sharedTasks[taskId]?.let { updateTask(taskId, status = "paused") }
        }
    }

    /**
     * 从暂停/失败状态恢复下载：清除暂停标记，并按磁盘上已有字节数走 Range 断点续传。
     * 任务元数据（mediaUrl / referer）仍保存在 sharedTasks 中，无需 Flutter 重新入队。
     */
    private fun resumeTask(taskId: String) {
        val task = sharedTasks[taskId] ?: return
        // 已在下载中 → 忽略。
        downloadThreads[taskId]?.let { if (it.isAlive) return }

        controlFlags.remove(taskId)

        val outputFile = File(File(filesDir, "video_downloads"), "$taskId.mp4")
        val alreadyBytes = if (outputFile.exists()) outputFile.length() else 0L

        // ── A2: 空间预检 ──
        val requiredSpace = estimateRequiredSpace(alreadyBytes, task)
        val cacheDir = File(filesDir, "video_downloads")
        val availableSpace = getAvailableStorageBytes(cacheDir)
        if (availableSpace < requiredSpace + DownloadExecutionPolicy.STORAGE_RESERVE_BYTES) {
            val needed = requiredSpace + DownloadExecutionPolicy.STORAGE_RESERVE_BYTES - availableSpace
            updateTask(taskId, status = "failed", errorMessage = "存储空间不足（需要 ${formatBytes(needed)}）")
            return
        }

        sharedTasks[taskId] = task.copy(
            status = "downloading",
            downloadedBytes = alreadyBytes,
            errorMessage = "",
            updatedAt = System.currentTimeMillis()
        )
        updateNotification(sharedTasks[taskId]!!)

        // ── A1: 并发调度 ──
        val activeCount = downloadThreads.count { it.value.isAlive }
        if (activeCount >= DownloadExecutionPolicy.MAX_CONCURRENT_TASKS) {
            sharedTasks[taskId] = sharedTasks[taskId]!!.copy(
                status = "queued",
                updatedAt = System.currentTimeMillis()
            )
            persistTasks()
            return
        }

        launchDownloadThread(task.mediaUrl, task.referer, outputFile, taskId, alreadyBytes)
        drainQueue()
    }

    private fun cancelTask(taskId: String) {
        controlFlags[taskId] = "cancel"
        downloadThreads[taskId]?.interrupt()
        deleteLocalFile(taskId)
        sharedTasks[taskId]?.let {
            sharedTasks[taskId] = it.copy(
                status = "cancelled",
                downloadedBytes = 0L,
                totalBytes = 0L,
                downloadSpeedBytesPerSecond = 0L,
                errorMessage = "已取消",
                updatedAt = System.currentTimeMillis()
            )
            persistTasks()
            updateNotification(sharedTasks[taskId]!!)
        }
    }

    private fun removeTask(taskId: String) {
        controlFlags[taskId] = "cancel"
        downloadThreads[taskId]?.interrupt()
        deleteLocalFile(taskId)
        sharedTasks.remove(taskId)
        persistTasks()
        controlFlags.remove(taskId)
    }

    private fun deleteLocalFile(taskId: String) {
        val cacheDir = File(filesDir, "video_downloads")
        File(cacheDir, "$taskId.mp4").delete()
        File(cacheDir, "$taskId.hls-state").delete()
    }

    // ─────────────────────── 状态 / 通知 ───────────────────────

    private fun putFailed(
        taskId: String,
        episodeName: String,
        sourceName: String,
        mediaUrl: String,
        referer: String,
        message: String
    ) {
        val now = System.currentTimeMillis()
        val existing = sharedTasks[taskId]
        val task = existing?.copy(
            status = "failed",
            errorMessage = message,
            updatedAt = now
        ) ?: DownloadTask(
            id = taskId,
            sourceId = "",
            vodId = "",
            vodName = "",
            sourceName = sourceName,
            episodeName = episodeName,
            mediaUrl = mediaUrl,
            referer = referer,
            status = "failed",
            downloadedBytes = 0L,
            totalBytes = 0L,
            downloadSpeedBytesPerSecond = 0L,
            localPath = "",
            errorMessage = message,
            isPlaybackActive = false,
            createdAt = now,
            updatedAt = now
        )
        sharedTasks[taskId] = task
        persistTasks()
        updateNotification(task)
    }

    private fun updateTask(
        taskId: String,
        status: String? = null,
        downloadedBytes: Long? = null,
        totalBytes: Long? = null,
        downloadSpeedBytesPerSecond: Long? = null,
        errorMessage: String? = null
    ) {
        val task = sharedTasks[taskId] ?: return
        val updated = task.copy(
            status = status ?: task.status,
            downloadedBytes = downloadedBytes ?: task.downloadedBytes,
            totalBytes = totalBytes ?: task.totalBytes,
            downloadSpeedBytesPerSecond = downloadSpeedBytesPerSecond ?: task.downloadSpeedBytesPerSecond,
            errorMessage = errorMessage ?: task.errorMessage,
            updatedAt = System.currentTimeMillis()
        )
        sharedTasks[taskId] = updated
        persistTasks()
        updateNotification(updated)
    }

    private fun updateNotification(task: DownloadTask) {
        val contentText = when (task.status) {
            "completed" -> "${task.episodeName} 下载完成"
            "failed" -> "${task.episodeName} 下载失败: ${task.errorMessage}"
            "paused" -> "${task.episodeName} 已暂停"
            "cancelled" -> "${task.episodeName} 已取消"
            "queued" -> "${task.episodeName} 排队中"
            else -> {
                val progress = if (task.totalBytes > 0) {
                    "${((task.downloadedBytes.toDouble() / task.totalBytes) * 100).toInt()}%"
                } else "..."
                "${task.episodeName} $progress"
            }
        }

        val indeterminate = task.status == "downloading" && task.totalBytes <= 0
        notificationBuilder
            .setContentText(contentText)
            .setProgress(
                if (task.totalBytes > 0) task.totalBytes.toInt() else 0,
                task.downloadedBytes.toInt(),
                indeterminate
            )

        notificationManager.notify(NOTIFICATION_ID, notificationBuilder.build())
    }

    /** 无活跃下载线程时，移除前台通知并停止服务（静态快照仍保留供 Flutter 读取）。 */
    private fun checkStopSelf() {
        val anyActive = downloadThreads.values.any { it.isAlive }
        if (!anyActive) {
            @Suppress("DEPRECATION")
            stopForeground(true)
            foregroundStarted = false
            stopSelf()
        }
    }

    // ─────────────────────── 存储工具 ───────────────────────

    /**
     * 获取缓存目录所在分区的可用字节数。
     */
    private fun getAvailableStorageBytes(dir: File): Long {
        val statFs = StatFs(dir.absolutePath)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            statFs.availableBytes
        } else {
            @Suppress("DEPRECATION")
            statFs.availableBlocks.toLong() * statFs.blockSize.toLong()
        }
    }

    /**
     * 估算下载所需空间：已知已下载字节 + 预估剩余大小。
     * 如果 totalBytes 未知，按 50MB 做保守预估。
     */
    private fun estimateRequiredSpace(alreadyBytes: Long, existing: DownloadTask?): Long {
        val remaining = existing?.let {
            if (it.totalBytes > alreadyBytes) it.totalBytes - alreadyBytes else 0L
        } ?: 0L
        return if (remaining > 0) remaining else 50L * 1024 * 1024
    }

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes >= 1024L * 1024 * 1024 -> "${bytes / (1024L * 1024 * 1024)} GB"
            bytes >= 1024L * 1024 -> "${bytes / (1024L * 1024)} MB"
            bytes >= 1024L -> "${bytes / 1024L} KB"
            else -> "$bytes B"
        }
    }
}

data class DownloadTask(
    val id: String,
    val sourceId: String,
    val vodId: String,
    val vodName: String,
    val sourceName: String,
    val episodeName: String,
    val mediaUrl: String,
    val referer: String,
    val status: String,
    val downloadedBytes: Long,
    val totalBytes: Long,
    val downloadSpeedBytesPerSecond: Long,
    val localPath: String,
    val errorMessage: String,
    val isPlaybackActive: Boolean,
    val createdAt: Long,
    val updatedAt: Long
) {
    fun toSnapshotMap(): Map<String, Any> = mapOf(
        "id" to id,
        "sourceId" to sourceId,
        "vodId" to vodId,
        "vodName" to vodName,
        "sourceName" to sourceName,
        "episodeName" to episodeName,
        "mediaUrl" to mediaUrl,
        "referer" to referer,
        "status" to status,
        "downloadedBytes" to downloadedBytes,
        "totalBytes" to totalBytes,
        "downloadSpeedBytesPerSecond" to downloadSpeedBytesPerSecond,
        "localPath" to localPath,
        "errorMessage" to errorMessage,
        "isPlaybackActive" to isPlaybackActive,
        "createdAt" to createdAt,
        "updatedAt" to updatedAt
    )
}
