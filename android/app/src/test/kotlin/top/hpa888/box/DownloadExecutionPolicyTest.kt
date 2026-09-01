package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException

class DownloadExecutionPolicyTest {
    @Test
    fun `starts oldest queued task only when a concurrency slot is free`() {
        val queuedTasks = listOf(
            policyTask(id = "new", createdAt = 20),
            policyTask(id = "old", createdAt = 10),
        )

        // activeCount=1 means one slot used out of MAX_CONCURRENT_TASKS(2) → 1 more allowed
        assertEquals(listOf("old"), DownloadExecutionPolicy.nextTaskIds(queuedTasks, activeCount = 1))
        // activeCount=2 → no slots left
        assertEquals(emptyList<String>(), DownloadExecutionPolicy.nextTaskIds(queuedTasks, activeCount = 2))
        // activeCount=0 → both slots open
        assertEquals(listOf("old", "new"), DownloadExecutionPolicy.nextTaskIds(queuedTasks, activeCount = 0))
    }

    @Test
    fun `classifies retryable transport failures and caps exponential backoff`() {
        val timeout = DownloadExecutionPolicy.classifyFailure(SocketTimeoutException("slow"))
        val client = DownloadExecutionPolicy.classifyFailure(DownloadHttpException(404, "missing"))

        assertTrue(timeout.retryable)
        assertEquals("网络超时，将自动重试", timeout.userMessage)
        assertFalse(client.retryable)
        assertEquals("资源不存在或已失效（HTTP 404）", client.userMessage)
        assertEquals(1_000L, DownloadExecutionPolicy.retryDelayMillis(1))
        assertEquals(4_000L, DownloadExecutionPolicy.retryDelayMillis(3))
        assertEquals(8_000L, DownloadExecutionPolicy.retryDelayMillis(9))
        assertTrue(DownloadExecutionPolicy.classifyFailure(IOException("offline")).retryable)
    }

    @Test
    fun `requires safety reserve before writing a known size file`() {
        assertTrue(DownloadExecutionPolicy.hasEnoughSpace(availableBytes = 200, requiredBytes = 100, reserveBytes = 50))
        assertFalse(DownloadExecutionPolicy.hasEnoughSpace(availableBytes = 149, requiredBytes = 100, reserveBytes = 50))
    }

    private fun policyTask(id: String, createdAt: Long) = DownloadTask(
        id = id, sourceId = "", vodId = "", vodName = "", sourceName = "", episodeName = id,
        mediaUrl = "https://example.test/$id.mp4", referer = "", status = "queued",
        downloadedBytes = 0, totalBytes = 0, downloadSpeedBytesPerSecond = 0, localPath = "",
        errorMessage = "", isPlaybackActive = false, createdAt = createdAt, updatedAt = createdAt,
    )
}
