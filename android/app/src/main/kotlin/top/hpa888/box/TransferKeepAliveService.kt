package top.hpa888.box

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 远端存储插件的传输保活（284 P1）。
 *
 * 为什么需要：Flutter 起的上传/下载是普通应用进程里的任务，app 一退到后台、
 * 系统内存吃紧就会把进程回收，传输直接断掉（用户回到前台只看到"任务没了"）。
 * 传输入队期间把一个前台服务挂上去，系统就不会随便杀这个进程。
 *
 * 与 [VideoDownloadService] 的关系：同一个模式（通知渠道 + 5s 内 startForeground +
 * 进程内静态状态），但**各管各的**——那边下载的是外部直链 mp4，这边是 WebDAV 传输，
 * 混在一起会让两边的状态机互相干扰。通知 ID 也分开（1001 / 1002）。
 *
 * 三道防线（都被真实用户场景逼出来的）：
 *  1. `startForegroundService` 后必须在 ~5s 内 `startForeground`，否则 Android 8+
 *     直接抛 ForegroundServiceDidNotStartInTimeException 杀服务 → [ensureForeground]；
 *  2. Flutter 侧异常退出可能来不及调 stop → **看门狗**：超过 [IDLE_TIMEOUT_MS]
 *     没有更新就自己收工，绝不留下一个常驻通知；
 *  3. 服务没起来时的 update/stop 一律当无操作，不抛异常（Dart 侧也不该为此报错）。
 */
class TransferKeepAliveService : Service() {
    companion object {
        private const val TAG = "BoxTransferKeepAlive"
        const val CHANNEL_ID = "remote_storage_transfer_channel"
        const val NOTIFICATION_ID = 1002

        /** 看门狗：多久没有更新就自己收工（Flutter 侧异常退出的兜底）。 */
        private const val IDLE_TIMEOUT_MS = 10 * 60 * 1000L

        /** 进程内静态状态：MainActivity 无需持有实例即可更新通知。 */
        @Volatile
        private var running = false

        @Volatile
        private var currentTitle = "Box 传输中"

        @Volatile
        private var currentText = "正在传输…"

        fun isRunning(): Boolean = running

        /** 起前台服务（已在跑就只更新文案）。 */
        fun start(context: Context, title: String, text: String) {
            currentTitle = title
            currentText = text
            val intent = Intent(context, TransferKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (t: Throwable) {
                // 后台限制等场景可能拒绝启动：不影响传输本身，记一条就好。
                Log.w(TAG, "启动保活服务失败: ${t.javaClass.simpleName}: ${t.message}")
            }
        }

        /** 更新通知文案；服务没在跑则无操作。 */
        fun update(context: Context, text: String) {
            currentText = text
            if (!running) return
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildNotification(context))
        }

        /** 收工：撤掉通知并停服务。 */
        fun stop(context: Context) {
            running = false
            try {
                context.stopService(Intent(context, TransferKeepAliveService::class.java))
            } catch (t: Throwable) {
                Log.w(TAG, "停止保活服务失败: ${t.message}")
            }
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(NOTIFICATION_ID)
        }

        private fun buildNotification(context: Context): android.app.Notification =
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setContentTitle(currentTitle)
                .setContentText(currentText)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build()
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastUpdateAt = System.currentTimeMillis()

    private val watchdog = object : Runnable {
        override fun run() {
            val idle = System.currentTimeMillis() - lastUpdateAt
            if (!running || idle > IDLE_TIMEOUT_MS) {
                Log.i(TAG, "看门狗收工（空闲 ${idle}ms）")
                stop(this@TransferKeepAliveService)
                return
            }
            handler.postDelayed(this, 60 * 1000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        running = true
        lastUpdateAt = System.currentTimeMillis()
        ensureForeground()
        handler.removeCallbacks(watchdog)
        handler.postDelayed(watchdog, 60 * 1000L)
        // 不被系统重启：状态由 Flutter 侧掌握，重启一个没有任务的服务只会留下空通知。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(watchdog)
        running = false
        super.onDestroy()
    }

    /** Android 8+ 要求 startForegroundService 后 ~5s 内必须 startForeground。 */
    private fun ensureForeground() {
        val notification = buildNotification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "文件传输",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "传输期间保持后台运行" }
            manager.createNotificationChannel(channel)
        }
    }
}
