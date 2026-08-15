package com.redshoxx.streamflow.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class ReceiverController(context: Context) {
    data class UiState(
        val title: String = "Bereit zum Verbinden",
        val mediaUrl: String? = null,
        val isPlaying: Boolean = false,
        val positionMs: Long = 0,
        val durationMs: Long = 0,
        val playbackState: Int = Player.STATE_IDLE,
        val volume: Float = 1f,
        val error: String? = null,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val player = ExoPlayer.Builder(context.applicationContext).build()
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    init {
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) = publish()
            override fun onPlaybackStateChanged(playbackState: Int) = publish()
            override fun onPlayerError(error: PlaybackException) {
                _state.value = _state.value.copy(error = error.errorCodeName)
                publish()
            }
        })
    }

    fun player(): ExoPlayer = player

    fun load(url: String, title: String?) = runOnPlayerThread {
        requireSupportedMediaUrl(url)
        val item = MediaItem.Builder().setUri(url).build()
        player.setMediaItem(item)
        player.prepare()
        player.playWhenReady = true
        _state.value = _state.value.copy(
            title = title?.trim()?.take(256)?.takeIf { it.isNotBlank() } ?: "Medienwiedergabe",
            mediaUrl = url,
            error = null,
        )
        publish()
    }

    fun play() = runOnPlayerThread {
        player.play()
        publish()
    }

    fun pause() = runOnPlayerThread {
        player.pause()
        publish()
    }

    fun stop() = runOnPlayerThread {
        player.stop()
        player.clearMediaItems()
        _state.value = UiState(volume = player.volume)
        publish()
    }

    fun seek(positionMs: Long) = runOnPlayerThread {
        player.seekTo(positionMs.coerceAtLeast(0))
        publish()
    }

    fun setVolume(volume: Float) = runOnPlayerThread {
        player.volume = volume.coerceIn(0f, 1f)
        publish()
    }

    fun snapshot(): UiState = callOnPlayerThread {
        publish()
        _state.value
    }

    private fun requireSupportedMediaUrl(url: String) {
        val scheme = runCatching { URI(url).scheme?.lowercase() }.getOrNull()
        require(scheme == "http" || scheme == "https") { "unsupported_media_url" }
    }

    private fun publish() {
        _state.value = _state.value.copy(
            isPlaying = player.isPlaying,
            positionMs = player.currentPosition.coerceAtLeast(0),
            durationMs = player.duration.coerceAtLeast(0),
            playbackState = player.playbackState,
            volume = player.volume,
        )
    }

    private fun runOnPlayerThread(block: () -> Unit) {
        callOnPlayerThread {
            block()
            Unit
        }
    }

    private fun <T> callOnPlayerThread(block: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()

        val value = AtomicReference<T>()
        val failure = AtomicReference<Throwable?>()
        val latch = CountDownLatch(1)
        val posted = mainHandler.post {
            try {
                value.set(block())
            } catch (error: Throwable) {
                failure.set(error)
            } finally {
                latch.countDown()
            }
        }
        check(posted) { "player_thread_unavailable" }

        try {
            check(latch.await(3, TimeUnit.SECONDS)) { "player_thread_timeout" }
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw IllegalStateException("player_thread_interrupted", error)
        }

        failure.get()?.let { throw it }
        return value.get()
    }

    fun release() = runOnPlayerThread { player.release() }
}
