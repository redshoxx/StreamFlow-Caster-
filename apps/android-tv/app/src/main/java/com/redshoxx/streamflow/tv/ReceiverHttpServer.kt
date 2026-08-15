package com.redshoxx.streamflow.tv

import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject

class ReceiverHttpServer(
    port: Int,
    private val controller: ReceiverController,
) : NanoHTTPD(port) {

    override fun serve(session: IHTTPSession): Response {
        return try {
            when {
                session.method == Method.GET && session.uri == "/api/v1/status" -> status()
                session.method == Method.POST && session.uri == "/api/v1/load" -> {
                    val body = bodyJson(session)
                    val url = body.optString("url")
                    if (url.isBlank()) json(400, JSONObject().put("error", "missing_url"))
                    else {
                        controller.load(url, body.optString("title"))
                        json(200, JSONObject().put("ok", true))
                    }
                }
                session.method == Method.POST && session.uri == "/api/v1/play" -> ok { controller.play() }
                session.method == Method.POST && session.uri == "/api/v1/pause" -> ok { controller.pause() }
                session.method == Method.POST && session.uri == "/api/v1/stop" -> ok { controller.stop() }
                session.method == Method.POST && session.uri == "/api/v1/seek" -> {
                    val position = bodyJson(session).optLong("positionMs", 0)
                    ok { controller.seek(position) }
                }
                session.method == Method.POST && session.uri == "/api/v1/volume" -> {
                    val volume = bodyJson(session).optDouble("volume", 1.0).toFloat()
                    ok { controller.setVolume(volume) }
                }
                else -> json(404, JSONObject().put("error", "not_found"))
            }
        } catch (e: Exception) {
            json(500, JSONObject().put("error", "receiver_error"))
        }
    }

    private fun status(): Response {
        val state = controller.snapshot()
        return json(200, JSONObject()
            .put("title", state.title)
            .put("mediaUrl", state.mediaUrl)
            .put("isPlaying", state.isPlaying)
            .put("positionMs", state.positionMs)
            .put("durationMs", state.durationMs)
            .put("playbackState", state.playbackState)
            .put("volume", state.volume))
    }

    private fun bodyJson(session: IHTTPSession): JSONObject {
        val files = mutableMapOf<String, String>()
        session.parseBody(files)
        return JSONObject(files["postData"] ?: "{}")
    }

    private fun ok(block: () -> Unit): Response {
        block()
        return json(200, JSONObject().put("ok", true))
    }

    private fun json(code: Int, payload: JSONObject): Response =
        newFixedLengthResponse(
            Response.Status.lookup(code),
            "application/json",
            payload.toString(),
        ).apply {
            addHeader("Cache-Control", "no-store")
            addHeader("Access-Control-Allow-Origin", "*")
        }
}
