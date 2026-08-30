package top.hpa888.box

import java.io.IOException
import java.net.SocketTimeoutException

/**
 * Download execution policy: concurrency control, space pre-check, failure classification.
 */
object DownloadExecutionPolicy {

    /** Maximum concurrent download threads. */
    const val MAX_CONCURRENT_TASKS = 2

    /** Safety reserve in bytes that must remain free on the device. */
    const val STORAGE_RESERVE_BYTES = 50L * 1024 * 1024 // 50 MB

    /** Maximum retry attempts for transient failures (0 = no retry). */
    const val MAX_RETRIES = 3

    /**
     * Returns task IDs that should be started next, based on active thread count.
     * Queued tasks are sorted by createdAt then id (oldest first).
     */
    fun nextTaskIds(
        queuedTasks: List<DownloadTask>,
        activeCount: Int,
        maxConcurrent: Int = MAX_CONCURRENT_TASKS,
    ): List<String> {
        if (activeCount >= maxConcurrent) return emptyList()
        val sorted = queuedTasks.sortedWith(compareBy({ it.createdAt }, { it.id }))
        return sorted.take(maxConcurrent - activeCount).map { it.id }
    }

    /**
     * Checks whether [requiredBytes] can fit given current available space and a safety reserve.
     */
    fun hasEnoughSpace(availableBytes: Long, requiredBytes: Long, reserveBytes: Long = STORAGE_RESERVE_BYTES): Boolean {
        return availableBytes >= (requiredBytes + reserveBytes)
    }

    /**
     * Classifies a failure into retryable vs non-retryable with a user-facing message.
     */
    data class FailureClassification(
        val retryable: Boolean,
        val userMessage: String,
    )

    fun classifyFailure(throwable: Throwable): FailureClassification {
        return when (throwable) {
            is DownloadHttpException ->
                when (throwable.statusCode) {
                    404 -> FailureClassification(false, "资源不存在或已失效（HTTP ${throwable.statusCode}）")
                    403 -> FailureClassification(false, "访问被拒绝（HTTP ${throwable.statusCode}）")
                    401 -> FailureClassification(false, "需要登录才能下载（HTTP ${throwable.statusCode}）")
                    in 500..599 ->
                        FailureClassification(true, "服务器错误（HTTP ${throwable.statusCode}），将自动重试")
                    else ->
                        FailureClassification(false, "下载失败（HTTP ${throwable.statusCode}）")
                }
            is SocketTimeoutException ->
                FailureClassification(true, "网络超时，将自动重试")
            is java.net.UnknownHostException,
            is java.net.ConnectException ->
                FailureClassification(true, "网络连接不可用，请检查网络后重试")
            is IOException ->
                FailureClassification(true, "网络异常：${safeMessage(throwable)}")
            is IllegalArgumentException ->
                when (throwable.message?.lowercase()) {
                    "直播流暂不支持离线下载" ->
                        FailureClassification(false, "直播流暂不支持离线下载")
                    else ->
                        FailureClassification(false, throwable.message ?: "参数错误")
                }
            else ->
                FailureClassification(false, throwable.message ?: "未知错误")
        }
    }

    /**
     * Calculates exponential backoff delay in milliseconds for a given retry attempt (1-based).
     * Formula: min(1000 * 2^(attempt-1), 8000) — caps at 8 seconds.
     */
    fun retryDelayMillis(attempt: Int): Long {
        return minOf(1000L * (1L shl (attempt - 1)), 8000L)
    }

    private fun safeMessage(throwable: Throwable): String {
        val msg = throwable.message ?: ""
        // Strip potentially sensitive paths or URLs from IOException messages.
        return msg.take(60)
    }
}

/** HTTP error with a specific status code. */
class DownloadHttpException(
    val statusCode: Int,
    message: String,
) : IOException(message)
