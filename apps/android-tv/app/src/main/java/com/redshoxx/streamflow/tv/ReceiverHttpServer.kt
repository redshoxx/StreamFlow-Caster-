package com.redshoxx.streamflow.tv

import android.os.SystemClock
import fi.iki.elonen.NanoHTTPD
import java.net.URI
import java.security.MessageDigest
import org.json.JSONObject

class ReceiverHttpServer(
    port: Int,
    private val controller: ReceiverController,
    private val pairingCode: String,
) : NanoHTTPD(port) {

    private data class AuthWindow(var startedAtMs: Long, var failures: Int)

    private val authLock = Any()
    private val authWindows = mutableMapOf<String, AuthWindow>()

    override fun serve(session: IHTTPSession): Response {
        return try {
            if (session.method == Method.GET && session.uri == "/api/v1/health") {
                return json(
                    200,
                    JSONObject()
                        .put("ok", true)
                        .put("protocol", 2)
                        .put("pairingRequired", true),
                )
            }

            if (session.uri.startsWith("/api/v1/") && !isAuthorized(session)) {
                return json(401, JSONObject().put("error", "pairing_required"))
            }

            when {
                session.method == Method.GET && session.uri == "/api/v1/status" -> status()
                session.method == Method.POST && session.uri == "/api/v1/load" -> {
                    val body = bodyJson(session)
                    val url = body.optString("url").trim()
                    if (!isSupportedMediaUrl(url)) {
                        json(400, JSONObject().put("error", "invalid_url"))
                    } else {
                        controller.load(url, body.optString("title").take(256))
                        json(200, JSONObject().put("ok", true))
                    }
                }
                session.method == Method.POST && session.uri == "/api/v1/play" -> ok { controller.play() }
                session.method == Method.POST && session.uri == "/api/v1/pause" -> ok { controller.pause() }
                session.method == Method.POST && session.uri == "/api/v1/stop" -> ok { controller.stop() }
                session.method == Method.POST && session.uri == "/api/v1/seek" -> {
                    val position = bodyJson(session)
                        .optLong("positionMs", 0)
                        .coerceIn(0, MAX_SEEK_MS)
                    ok { controller.seek(position) }
                }
                session.method == Method.POST && session.uri == "/api/v1/volume" -> {
                    val requested = bodyJson(session).optDouble("volume", Double.NaN)
                    if (!requested.isFinite() || requested < 0.0 || requested > 1.0) {
                        json(400, JSONObject().put("error", "invalid_volume"))
                    } else {
                        ok { controller.setVolume(requested.toFloat()) }
                    }
                }
                else -> json(404, JSONObject().put("error", "not_found"))
            }
        } catch (_: IllegalArgumentException) {
            json(400, JSONObject().put("error", "invalid_request"))
        } catch (_: Exception) {
            json(500, JSONObject().put("error", "receiver_error"))
        }
    }

    private fun status(): Response {
        val state = controller.snapshot()
        return json(
            200,
            JSONObject()
                .put("title", state.title)
                .put("mediaUrl", state.mediaUrl)
                .put("isPlaying", state.isPlaying)
                .put("positionMs", state.positionMs)
                .put("durationMs", state.durationMs)
                .put("playbackState", state.playbackState)
                .put("volume", state.volume)
                .put("error", state.error),
        )
    }

    private fun bodyJson(session: IHTTPSession): JSONObject {
        val declaredLength = session.headers["content-length"]?.toLongOrNull()
        if (declaredLength != null && declaredLength > MAX_BODY_BYTES) {
            throw IllegalArgumentException("request_too_large")
        }

        val files = mutableMapOf<String, String>()
        session.parseBody(files)
        val raw = files["postData"] ?: "{}"
        require(raw.length <= MAX_BODY_BYTES) { "request_too_large" }
        return JSONObject(raw)
    }

    private fun isSupportedMediaUrl(url: String): Boolean {
        if (url.isBlank() || url.length > MAX_URL_LENGTH) return false
        val scheme = runCatching { URI(url).scheme?.lowercase() }.getOrNull()
        return scheme == "http" || scheme == "https"
    }

    private fun isAuthorized(session: IHTTPSession): Boolean {
        val remote = session.remoteIpAddress.ifBlank { "unknown" }
        val provided = session.headers[PAIRING_HEADER].orEmpty()
        val now = SystemClock.elapsedRealtime()

        synchronized(authLock) {
            val state = authWindows.getOrPut(remote) { AuthWindow(now, 0) }
            if (now - state.startedAtMs >= AUTH_WINDOW_MS) {
                state.startedAtMs = now
                state.failures = 0
            }

            if (state.failures >= MAX_AUTH_FAILURES) return false

            if (secureEquals(provided, pairingCode)) {
                authWindows.remove(remote)
                return true
            }

            state.failures += 1
            return false
        }
    }

    private fun secureEquals(left: String, right: String): Boolean =
        MessageDigest.isEqual(left.toByteArray(Charsets.UTF_8), right.toByteArray(Charsets.UTF_8))

    private fun ok(block: () -> Unit): Response {
        block()
        return json(200, JSONObject().put("ok", true))
    }

    private fun json(code: Int, payload: JSONObject): Response =
        newFixedLengthResponse(
            Response.Status.lookup(code),
            "application/json; charset=utf-8",
            payload.toString(),
        ).apply {
            addHeader("Cache-Control", "no-store")
            addHeader("X-Content-Type-Options", "nosniff")
        }

    companion object {
        private const val PAIRING_HEADER = "x-streamflow-pairing-code"
        private const val MAX_BODY_BYTES = 16 * 1024L
        private const val MAX_URL_LENGTH = 8192
        private const val MAX_SEEK_MS = 7L * 24 * 60 * 60 * 1000
        private const val AUTH_WINDOW_MS = 60_000L
        private const val MAX_AUTH_FAILURES = 10
    }
}
