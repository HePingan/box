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

/**
 * 漫画离线下载的保活（2026-10-02）。
 *
 * 为什么要它：离线下载是 Flutter 侧（Dart）的任务，app 一退到后台、系统内存吃紧就会回收
 * 进程，下到一半的队列直接没了（用户回来只看到进度不动了）。下载期间挂一个前台服务，
 * 系统就不会随便杀这个进程。
 *
 * 为什么**再起一个服务**而不是复用 [TransferKeepAliveService] / [VideoDownloadService]：
 * 同一个模式（通知渠道 + 5s 内 startForeground + 进程内静态状态），但各管各的状态机。
 * 复用的话两边的通知与"running"会互相踩（一边收工撤掉通知，另一边还在下），
 * 通知 ID 也分开：视频 1001、远端存储传输 1002、漫画下载 **1003**。
 *
 * 三道防线（都是被真实用户场景逼出来的，见 284 P1）：
 *  1. `startForegroundService` 后必须在 ~5s 内 `startForeground`，否则 Android 8+
 *     直接抛 ForegroundServiceDidNotStartInTimeException 杀服务 → [ensureForeground]；
 *  2. Flutter 侧异常退出可能来不及调 stop → **看门狗**：超过 [IDLE_TIMEOUT_MS]
 *     没有更新就自己收工，绝不留下一个常驻通知；
 *  3. 服务没起来时的 update/stop 一律当无操作，不抛异常（Dart 侧也不该为此报错）。
 *
 * 另外，本服务多一个 [finish]：整队下完之后**留一条可划掉的通知**（"下载完成"），
 * 而不是像传输那样直接撤掉 —— 用户切走了，唯一能知道他下完了的办法就是这条通知。
 */
class ComicKeepAliveService : Service() {
    companion object {
        private const val TAG = "BoxComicKeepAlive"
        const val CHANNEL_ID = "comic_download_channel"
        const val NOTIFICATION_ID = 1003

        /** 看门狗：多久没有更新就自己收工（Flutter 侧异常退出的兜底）。 */
        private const val IDLE_TIMEOUT_MS = 10 * 60 * 1000L

        @Volatile
        private var running = false

        /**
         * 正在跑的那个服务实例。
         *
         * 收工**必须直接打在这个实例上**（见 [finish]）：走 `startService` 送 intents 的话，
         * app 已经在后台时会被 Android 8+ 的后台启动限制拒掉 —— 而"用户切走了、
         * 这时候才下完"正是最需要它的场景。实例在 [onCreate]/[onDestroy] 里挂/摘。
         */
        @Volatile
        private var instance: ComicKeepAliveService? = null

        @Volatile
        private var currentTitle = "漫画下载中"

        @Volatile
        private var currentText = "正在下载…"

        fun isRunning(): Boolean = running

        /** 起前台服务（已在跑就只更新文案）。 */
        fun start(context: Context, title: String, text: String) {
            currentTitle = title
            currentText = text
            val intent = Intent(context, ComicKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "启动保活服务失败: ${t.javaClass.simpleName}: ${t.message}")
            }
        }

        /** 更新通知文案（进度）；服务没在跑则无操作。 */
        fun update(context: Context, text: String) {
            currentText = text
            if (!running) return
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildNotification(context, ongoing = true))
        }

        /**
         * 收工，但**留一条可划掉的通知**（"下载完成 / 有 N 话失败"）。
         *
         * 顺序与理由：先把那条常驻通知换成 `ongoing=false` 的（同 ID 覆盖），
         * 再让服务用 `stopForeground(DETACH)` 脱开前台 —— **直接 `stopService` 的话，
         * 前台通知会跟着服务被系统一起摘掉**，用户就看不到"下载完成"了。
         */
        fun finish(context: Context, title: String, text: String) {
            currentTitle = title
            currentText = text
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val svc = instance
            if (!running || svc == null) {
                // 服务没起来（比如下载太快、或后台限制拒绝启动）：也要让用户看到结果 ——
                // 通知权限没给就算了，不弹任何东西也不报错。
                try {
                    manager.notify(NOTIFICATION_ID, buildNotification(context, ongoing = false))
                } catch (t: Throwable) {
                    Log.w(TAG, "补一条完成通知失败: ${t.message}")
                }
                return
            }
            manager.notify(NOTIFICATION_ID, buildNotification(context, ongoing = false))
            svc.handler.post { svc.executeFinish() }
        }

        /** 收工并撤掉通知（用户暂停/取消：不用告诉他"完成"）。 */
        fun stop(context: Context) {
            running = false
            try {
                context.stopService(Intent(context, ComicKeepAliveService::class.java))
            } catch (t: Throwable) {
                Log.w(TAG, "停止保活服务失败: ${t.message}")
            }
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(NOTIFICATION_ID)
        }

        private fun buildNotification(
            context: Context,
            ongoing: Boolean,
        ): android.app.Notification =
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(currentTitle)
                .setContentText(currentText)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(ongoing)
                .setAutoCancel(!ongoing)
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
                stop(this@ComicKeepAliveService)
                return
            }
            handler.postDelayed(this, 60 * 1000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
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
        instance = null
        super.onDestroy()
    }

    /**
     * 收工：**脱开前台**（DETACH = 通知留在通知栏，不跟着服务消失）并退出。
     *
     * 用 DETACH 而不是让通知随服务一起被摘掉：这条通知是"下完了"的唯一凭据。
     */
    private fun executeFinish() {
        handler.removeCallbacks(watchdog)
        running = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
        stopSelf()
    }

    /** Android 8+ 要求 startForegroundService 后 ~5s 内必须 startForeground。 */
    private fun ensureForeground() {
        val notification = buildNotification(this, ongoing = true)
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
                "漫画下载",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "漫画离线下载期间保持后台运行" }
            manager.createNotificationChannel(channel)
        }
    }
}
