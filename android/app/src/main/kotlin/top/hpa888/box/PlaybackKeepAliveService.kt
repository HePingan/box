package top.hpa888.box

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 后台播放 / 息屏播放的保活（⑥B）。
 *
 * 为什么必须有它：Android 12+ 会把退到后台的普通进程「冻结」，14+ 更严 ——
 * 光靠播放器自己，息屏一会儿就断声。挂前台服务 + 媒体通知才是正路。
 *
 * 一个必须记住的时机约束：**必须在 App 还在前台时就 startForegroundService**。
 * 「等切后台再挂」会抛 ForegroundServiceStartNotAllowedException。
 * 所以 Dart 侧是「一开播就 start」，不是「切后台才 start」。
 *
 * 也可以从**前台**直接进来：这里不是被系统杀进程时才用，
 * 用户一直看着画面时它也在跑（通知就是那条常驻媒体通知）。
 *
 * 通知 ID 与其它保活服务分开：视频下载 1001、远端传输 1002、漫画下载 1003、
 * **后台播放 1004**。各管各的状态机，互不踩。
 *
 * 注意：注释里不要出现斜杠加星号的片段 —— Kotlin 块注释可嵌套，
 * 会让外层注释永不闭合、构建直接失败（286 P3 踩过一次）。
 */
class PlaybackKeepAliveService : Service() {
    companion object {
        private const val TAG = "BoxPlaybackKeepAlive"
        const val CHANNEL_ID = "video_playback_channel"
        const val NOTIFICATION_ID = 1004

        const val ACTION_TOGGLE = "top.hpa888.box.playback.TOGGLE"
        const val ACTION_PREVIOUS = "top.hpa888.box.playback.PREVIOUS"
        const val ACTION_NEXT = "top.hpa888.box.playback.NEXT"

        private const val REQUEST_CONTENT = 7401
        private const val REQUEST_TOGGLE = 7402
        private const val REQUEST_PREVIOUS = 7403
        private const val REQUEST_NEXT = 7404

        /** 看门狗：多久没动静就自己收工 —— Dart 侧异常退出时不留下常驻通知。 */
        private const val IDLE_TIMEOUT_MS = 30 * 60 * 1000L

        @Volatile
        private var running = false

        @Volatile
        private var instance: PlaybackKeepAliveService? = null

        @Volatile
        private var currentTitle = "正在播放"

        @Volatile
        private var currentText = "正在后台播放"

        @Volatile
        private var currentPlaying = true

        /** Dart 侧的命令回调（由 [PlaybackNotificationChannel] 装/卸）。 */
        @Volatile
        var onCommand: ((String) -> Unit)? = null

        fun isRunning(): Boolean = running

        /** 起前台服务（已在跑就只更新文案）。 */
        fun start(
            context: Context,
            title: String,
            text: String,
            playing: Boolean,
        ) {
            currentTitle = title
            currentText = text
            currentPlaying = playing
            val intent = Intent(context, PlaybackKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (t: Throwable) {
                // 后台启动前台服务被拒（Android 12+）在这里兜住：播放不受影响，
                // 只是失去保活。
                Log.w(TAG, "启动播放保活失败: ${t.javaClass.simpleName}: ${t.message}")
            }
        }

        /** 更新通知（换集、播放/暂停）；服务没在跑则无操作。 */
        fun update(
            context: Context,
            title: String,
            text: String,
            playing: Boolean,
        ) {
            currentTitle = title
            currentText = text
            currentPlaying = playing
            instance?.bumpWatchdog()
            if (!running) return
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                manager.notify(NOTIFICATION_ID, buildNotification(context))
            } catch (t: Throwable) {
                Log.w(TAG, "更新播放通知失败: ${t.message}")
            }
        }

        /** 收工并撤掉通知（回到前台 / 用户关掉后台播放 / 离开播放器）。 */
        fun stop(context: Context) {
            running = false
            try {
                context.stopService(Intent(context, PlaybackKeepAliveService::class.java))
            } catch (t: Throwable) {
                Log.w(TAG, "停止播放保活失败: ${t.message}")
            }
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                manager.cancel(NOTIFICATION_ID)
            } catch (t: Throwable) {
                Log.w(TAG, "撤掉播放通知失败: ${t.message}")
            }
        }

        private fun buildNotification(context: Context): Notification {
            val contentIntent = PendingIntent.getActivity(
                context,
                REQUEST_CONTENT,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_NEW_TASK
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle(currentTitle)
                .setContentText(currentText)
                .setContentIntent(contentIntent)
                .setOngoing(true)
                .setSilent(true)
                .setShowWhen(false)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .addAction(
                    android.R.drawable.ic_media_previous,
                    "上一集",
                    servicePendingIntent(context, ACTION_PREVIOUS, REQUEST_PREVIOUS),
                )
                .addAction(
                    if (currentPlaying) {
                        android.R.drawable.ic_media_pause
                    } else {
                        android.R.drawable.ic_media_play
                    },
                    if (currentPlaying) "暂停" else "播放",
                    servicePendingIntent(context, ACTION_TOGGLE, REQUEST_TOGGLE),
                )
                .addAction(
                    android.R.drawable.ic_media_next,
                    "下一集",
                    servicePendingIntent(context, ACTION_NEXT, REQUEST_NEXT),
                )

            return builder.build()
        }

        /** 通知按钮：直接打到服务上（App 在后台也能收到）。 */
        private fun servicePendingIntent(
            context: Context,
            action: String,
            requestCode: Int,
        ): PendingIntent = PendingIntent.getService(
            context,
            requestCode,
            Intent(context, PlaybackKeepAliveService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastUpdateAt = System.currentTimeMillis()
    private var audioManager: AudioManager? = null

    private val watchdog = object : Runnable {
        override fun run() {
            val idle = System.currentTimeMillis() - lastUpdateAt
            if (!running || idle > IDLE_TIMEOUT_MS) {
                Log.i(TAG, "看门狗收工（空闲 ${idle}ms）")
                stop(this@PlaybackKeepAliveService)
                return
            }
            handler.postDelayed(this, 60 * 1000L)
        }
    }

    /**
     * 音频焦点：被别人抢走（来电、其它 App 放音）时告诉 Dart 侧让路。
     * 我们只负责「说一声」，暂停与否由 Dart 决定 —— 策略留在能测的一侧。
     */
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            -> emit(PlaybackNotificationChannel.COMMAND_AUDIO_FOCUS_LOST)

            else -> Unit
        }
    }

    private fun emit(command: String) {
        handler.post {
            try {
                onCommand?.invoke(command)
            } catch (t: Throwable) {
                Log.w(TAG, "投递播放命令失败: ${t.message}")
            }
        }
    }

    fun bumpWatchdog() {
        lastUpdateAt = System.currentTimeMillis()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        requestAudioFocus()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> {
                emit(PlaybackNotificationChannel.COMMAND_TOGGLE)
                bumpWatchdog()
                return START_NOT_STICKY
            }
            ACTION_PREVIOUS -> {
                emit(PlaybackNotificationChannel.COMMAND_PREVIOUS)
                bumpWatchdog()
                return START_NOT_STICKY
            }
            ACTION_NEXT -> {
                emit(PlaybackNotificationChannel.COMMAND_NEXT)
                bumpWatchdog()
                return START_NOT_STICKY
            }
        }

        running = true
        bumpWatchdog()
        ensureForeground()
        handler.removeCallbacks(watchdog)
        handler.postDelayed(watchdog, 60 * 1000L)
        // 不被系统重启：播放状态由 Flutter 侧掌握，重启一个没有播放的服务
        // 只会留下一条摘不掉的通知。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(watchdog)
        running = false
        instance = null
        abandonAudioFocus()
        super.onDestroy()
    }

    /** Android 8+ 要求 startForegroundService 后 ~5s 内必须 startForeground。 */
    private fun ensureForeground() {
        val notification = buildNotification(this)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "进前台失败: ${t.javaClass.simpleName}: ${t.message}")
        }
    }

    private fun requestAudioFocus() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            audioManager = am
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "请求音频焦点失败: ${t.message}")
        }
    }

    private fun abandonAudioFocus() {
        try {
            @Suppress("DEPRECATION")
            audioManager?.abandonAudioFocus(focusListener)
        } catch (t: Throwable) {
            Log.w(TAG, "释放音频焦点失败: ${t.message}")
        }
        audioManager = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "后台播放",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "息屏或切到别的 App 时继续播放" }
            manager.createNotificationChannel(channel)
        }
    }
}
