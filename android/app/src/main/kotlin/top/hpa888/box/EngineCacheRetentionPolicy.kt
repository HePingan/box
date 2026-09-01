package top.hpa888.box

/**
 * MainActivity.onDestroy 该不该丢掉 quiz_engine 的 FlutterEngine 缓存。
 *
 * 抽成纯函数的原因：这个判定原先内联在 onDestroy 里，而 onDestroy 依赖
 * Android 框架，纯 JVM 单测碰不到。此前 P0FixLogicTest 声称验证它，实际
 * 是在测试方法内部重写了一遍 if 再断言自己的局部变量——生产代码改坏了
 * 那个测试照样绿。
 *
 * 判定本身的由来：用户切到驾考/考试 App 时 MainActivity 常被 destroy，
 * 但无障碍服务还在跑。若这时移除引擎缓存，
 * QuizAccessibilityService.resolveChannel() 就拿不到 FlutterEngine，
 * onQuestionCaptured 等回调会静默丢失——表现为「启用成功但不抓题」。
 */
object EngineCacheRetentionPolicy {

    /**
     * @param accessibilityServiceRunning 无障碍答题服务当前是否在运行
     * @return true 表示可以安全移除 quiz_engine 缓存
     */
    fun shouldEvictEngineCache(accessibilityServiceRunning: Boolean): Boolean =
        !accessibilityServiceRunning
}
