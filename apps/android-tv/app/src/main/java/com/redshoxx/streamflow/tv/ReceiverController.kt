package com.redshoxx.streamflow.tv

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
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
    )

    private val player = ExoPlayer.Builder(context).build()
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    init {
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) = publish()
            override fun onPlaybackStateChanged(playbackState: Int) = publish()
        })
    }

    fun player(): ExoPlayer = player

    fun load(url: String, title: String?) {
        val item = MediaItem.Builder().setUri(url).build()
        player.setMediaItem(item)
        player.prepare()
        player.playWhenReady = true
        _state.value = _state.value.copy(title = title?.takeIf { it.isNotBlank() } ?: "Medienwiedergabe", mediaUrl = url)
        publish()
    }

    fun play() { player.play(); publish() }
    fun pause() { player.pause(); publish() }
    fun stop() { player.stop(); publish() }
    fun seek(positionMs: Long) { player.seekTo(positionMs.coerceAtLeast(0)); publish() }

    fun snapshot(): UiState {
        publish()
        return _state.value
    }

    private fun publish() {
        _state.value = _state.value.copy(
            isPlaying = player.isPlaying,
            positionMs = player.currentPosition.coerceAtLeast(0),
            durationMs = player.duration.coerceAtLeast(0),
            playbackState = player.playbackState,
        )
    }

    fun release() = player.release()
}
