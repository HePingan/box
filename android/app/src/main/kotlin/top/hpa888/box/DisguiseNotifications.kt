package top.hpa888.box

import android.content.Context

/**
 * 通知文案伪装。
 *
 * 为什么单独一个对象：前台服务的通知（视频下载、传输、漫画缓存、后台播放、
 * 答题助手）都带着**真应用的业务字样**，伪装开着的时候它们在锁屏和通知栏上
 * 直接暴露「这不是计算器」。这里给所有通知标题/正文留一个统一的出口，
 * 开启伪装时换成计算器该有的措辞。
 *
 * 已知边界（改不动，也不要假装能改）：
 * - **通知渠道名**在系统设置里是「视频下载」等字样，创建后只能由用户或
 *   删渠道重建来改变，这里不动（删了重建会丢掉用户设置的静音/优先级）；
 * - 通知的**应用名**由系统按 `android:label` 显示，伪装期间 label 已经是
 *   「计算器」，所以这一项是安全的。
 */
object DisguiseNotifications {

    /** 伪装时统一的标题：一支计算器在后台跑前台服务是合理的（比如长算）。 */
    private const val FAKE_TITLE = "计算器"

    /** 伪装时的正文：不透露任何业务内容。 */
    private const val FAKE_TEXT = "运算进行中"

    fun title(context: Context, real: String): String =
        if (DisguiseController.isEnabledForNotifications(context)) FAKE_TITLE else real

    fun text(context: Context, real: String?): String? =
        if (DisguiseController.isEnabledForNotifications(context)) FAKE_TEXT else real
}
