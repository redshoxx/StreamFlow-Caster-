package com.redshoxx.streamflow.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.PlayerView

class MainActivity : ComponentActivity() {
    private lateinit var controller: ReceiverController
    private lateinit var server: ReceiverHttpServer
    private lateinit var advertiser: NsdAdvertiser
    private lateinit var pairingCodeStore: PairingCodeStore
    private val port = 38743

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        controller = ReceiverController(this)
        pairingCodeStore = PairingCodeStore(this)
        server = ReceiverHttpServer(
            port = port,
            controller = controller,
            pairingCode = pairingCodeStore.code,
        ).also { it.start(NanoTimeout.SOCKET_READ_TIMEOUT, false) }
        advertiser = NsdAdvertiser(this).also { it.start(port) }

        setContent {
            MaterialTheme {
                val state by controller.state.collectAsState()
                Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
                    AndroidView(
                        factory = { context ->
                            PlayerView(context).apply {
                                player = controller.player()
                                useController = true
                            }
                        },
                        modifier = Modifier.fillMaxSize(),
                    )

                    if (state.mediaUrl == null) {
                        Column(
                            modifier = Modifier.align(Alignment.Center).padding(48.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Text("STREAMFLOW", color = Color.White, style = MaterialTheme.typography.displaySmall)
                            Text("Bereit zum Verbinden", color = Color.White, style = MaterialTheme.typography.headlineMedium)
                            Text(
                                "Öffne StreamFlow auf deinem Smartphone, wähle diesen Fernseher und gib einmalig den Kopplungscode ein.",
                                color = Color.LightGray,
                            )
                            Text(
                                "Kopplungscode: ${formatPairingCode(pairingCodeStore.code)}",
                                color = Color.White,
                                style = MaterialTheme.typography.headlineSmall,
                            )
                        }
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        advertiser.stop()
        server.stop()
        controller.release()
        super.onDestroy()
    }

    private fun formatPairingCode(code: String): String = code.chunked(4).joinToString(" ")

    private object NanoTimeout {
        const val SOCKET_READ_TIMEOUT = 5000
    }
}
