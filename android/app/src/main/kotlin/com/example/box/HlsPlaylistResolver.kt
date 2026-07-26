package com.example.box

import java.net.URI

/** Resolves a VOD HLS master playlist into the concrete media playlist and TS URLs. */
internal object HlsPlaylistResolver {
    fun selectVariantUrl(masterUrl: String, playlist: String): String {
        return playlist.lineSequence()
            .map(String::trim)
            .firstOrNull { it.isNotEmpty() && !it.startsWith("#") }
            ?.let { resolve(masterUrl, it) }
            ?: throw IllegalArgumentException("HLS 主播放列表中没有可下载的清晰度")
    }

    fun mediaSegmentUrls(playlistUrl: String, playlist: String): List<String> =
        playlist.lineSequence()
            .map(String::trim)
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .map { resolve(playlistUrl, it) }
            .toList()

    fun isMasterPlaylist(playlist: String): Boolean =
        playlist.lineSequence().any { it.trim().startsWith("#EXT-X-STREAM-INF") }

    fun isCompleteVodPlaylist(playlist: String): Boolean =
        playlist.lineSequence().any { it.trim() == "#EXT-X-ENDLIST" }

    private fun resolve(baseUrl: String, reference: String): String =
        URI(baseUrl).resolve(reference).toString()
}
