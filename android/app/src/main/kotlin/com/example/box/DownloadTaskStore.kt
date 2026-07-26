package com.example.box

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Small durable store for native download snapshots. Flutter keeps its own Hive
 * view, but this store makes pause/resume survive Android service/process death.
 */
class DownloadTaskStore(context: Context) {
    private val stateFile = File(context.filesDir, "video_downloads/tasks.json")

    @Synchronized
    fun writeAll(tasks: Collection<DownloadTask>) {
        stateFile.parentFile?.mkdirs()
        val array = JSONArray()
        tasks.forEach { task -> array.put(toJson(task)) }
        val temporary = File(stateFile.parentFile, "${stateFile.name}.tmp")
        temporary.writeText(array.toString(), Charsets.UTF_8)
        if (!temporary.renameTo(stateFile)) {
            stateFile.writeText(array.toString(), Charsets.UTF_8)
            temporary.delete()
        }
    }

    @Synchronized
    fun readAll(): List<DownloadTask> {
        if (!stateFile.exists()) return emptyList()
        return try {
            val array = JSONArray(stateFile.readText(Charsets.UTF_8))
            buildList {
                for (index in 0 until array.length()) {
                    add(fromJson(array.getJSONObject(index)))
                }
            }
        } catch (_: Exception) {
            // A damaged cache must never prevent the app from starting.
            emptyList()
        }
    }

    private fun toJson(task: DownloadTask) = JSONObject().apply {
        put("id", task.id)
        put("sourceId", task.sourceId)
        put("vodId", task.vodId)
        put("vodName", task.vodName)
        put("sourceName", task.sourceName)
        put("episodeName", task.episodeName)
        put("mediaUrl", task.mediaUrl)
        put("referer", task.referer)
        put("status", task.status)
        put("downloadedBytes", task.downloadedBytes)
        put("totalBytes", task.totalBytes)
        put("downloadSpeedBytesPerSecond", task.downloadSpeedBytesPerSecond)
        put("localPath", task.localPath)
        put("errorMessage", task.errorMessage)
        put("isPlaybackActive", task.isPlaybackActive)
        put("createdAt", task.createdAt)
        put("updatedAt", task.updatedAt)
    }

    private fun fromJson(json: JSONObject) = DownloadTask(
        id = json.optString("id"),
        sourceId = json.optString("sourceId"),
        vodId = json.optString("vodId"),
        vodName = json.optString("vodName"),
        sourceName = json.optString("sourceName"),
        episodeName = json.optString("episodeName"),
        mediaUrl = json.optString("mediaUrl"),
        referer = json.optString("referer"),
        status = json.optString("status", "paused"),
        downloadedBytes = json.optLong("downloadedBytes"),
        totalBytes = json.optLong("totalBytes"),
        downloadSpeedBytesPerSecond = json.optLong("downloadSpeedBytesPerSecond"),
        localPath = json.optString("localPath"),
        errorMessage = json.optString("errorMessage"),
        isPlaybackActive = json.optBoolean("isPlaybackActive"),
        createdAt = json.optLong("createdAt"),
        updatedAt = json.optLong("updatedAt")
    )
}
