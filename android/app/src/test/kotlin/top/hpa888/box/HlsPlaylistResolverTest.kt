package top.hpa888.box

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HlsPlaylistResolverTest {
    @Test
    fun `resolves master playlist and media segments against their parent URLs`() {
        val masterUrl = "https://cdn.example.test/show/index.m3u8"
        val master = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=800000
            2000k/hls/mixed.m3u8
        """.trimIndent()
        assertTrue(HlsPlaylistResolver.isMasterPlaylist(master))
        val variantUrl = HlsPlaylistResolver.selectVariantUrl(masterUrl, master)
        assertEquals(
            "https://cdn.example.test/show/2000k/hls/mixed.m3u8",
            variantUrl,
        )

        val media = """
            #EXTM3U
            #EXTINF:4.0,
            part000.ts
            #EXTINF:5.0,
            https://other.example.test/part001.ts
            #EXT-X-ENDLIST
        """.trimIndent()
        val segments = HlsPlaylistResolver.mediaSegmentUrls(variantUrl, media)
        assertEquals(
            listOf(
                "https://cdn.example.test/show/2000k/hls/part000.ts",
                "https://other.example.test/part001.ts",
            ),
            segments,
        )
        assertTrue(HlsPlaylistResolver.isCompleteVodPlaylist(media))
    }
}
