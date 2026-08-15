package com.redshoxx.streamflow.tv

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.PlayerView

class MainActivity : ComponentActivity() {
    private lateinit var controller: ReceiverController
    private lateinit var pairingCodeStore: PairingCodeStore
    private var server: ReceiverHttpServer? = null
    private var advertiser: NsdAdvertiser? = null
    private var networkAccessGranted by mutableStateOf(false)
    private var networkPermissionDenied by mutableStateOf(false)
    private var networkStartError by mutableStateOf<String?>(null)
    private val port = 38743

    private val localNetworkPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            networkAccessGranted = granted
            networkPermissionDenied = !granted
            if (granted) {
                startReceiverNetwork()
            } else {
                stopReceiverNetwork()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        controller = ReceiverController(this)
        pairingCodeStore = PairingCodeStore(this)
        syncLocalNetworkAccess(requestIfMissing = true)

        setContent {
            MaterialTheme {
                val state by controller.state.collectAsState()
                Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
                    if (networkAccessGranted && networkStartError == null) {
                        AndroidView(
                            factory = { context ->
                                PlayerView(context).apply {
                                    player = controller.player()
                                    useController = true
                                }
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    }

                    when {
                        !networkAccessGranted -> {
                            ReceiverMessage(
                                title = "Lokales Netzwerk erforderlich",
                                body = if (networkPermissionDenied) {
                                    "Der Zugriff wurde abgelehnt. StreamFlow TV benötigt ihn, damit dein Smartphone diesen Fernseher im Heimnetz finden und steuern kann."
                                } else {
                                    "Erlaube den Zugriff auf dein lokales Netzwerk, damit dein Smartphone diesen Fernseher finden und Medien übertragen kann."
                                },
                                buttonLabel = "Zugriff erlauben",
                                onButtonClick = ::requestLocalNetworkAccess,
                            )
                        }

                        networkStartError != null -> {
                            ReceiverMessage(
                                title = "Netzwerkdienst nicht verfügbar",
                                body = networkStartError!!,
                                buttonLabel = "Erneut versuchen",
                                onButtonClick = ::startReceiverNetwork,
                            )
                        }

                        state.mediaUrl == null -> {
                            Column(
                                modifier = Modifier.align(Alignment.Center).padding(48.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Text(
                                    "STREAMFLOW",
                                    color = Color.White,
                                    style = MaterialTheme.typography.displaySmall,
                                )
                                Text(
                                    "Bereit zum Verbinden",
                                    color = Color.White,
                                    style = MaterialTheme.typography.headlineMedium,
                                )
                                Text(
                                    "Öffne StreamFlow auf deinem Smartphone, wähle diesen Fernseher und gib einmalig den Kopplungscode ein.",
                                    color = Color.LightGray,
                                    textAlign = TextAlign.Center,
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
    }

    override fun onResume() {
        super.onResume()
        if (::controller.isInitialized) {
            syncLocalNetworkAccess(requestIfMissing = false)
        }
    }

    @Composable
    private fun ReceiverMessage(
        title: String,
        body: String,
        buttonLabel: String,
        onButtonClick: () -> Unit,
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(48.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                "STREAMFLOW",
                color = Color.White,
                style = MaterialTheme.typography.displaySmall,
            )
            Text(
                title,
                modifier = Modifier.padding(top = 14.dp),
                color = Color.White,
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
            )
            Text(
                body,
                modifier = Modifier.padding(top = 14.dp),
                color = Color.LightGray,
                textAlign = TextAlign.Center,
            )
            Button(
                modifier = Modifier.padding(top = 18.dp),
                onClick = onButtonClick,
            ) {
                Text(buttonLabel)
            }
        }
    }

    private fun syncLocalNetworkAccess(requestIfMissing: Boolean) {
        if (Build.VERSION.SDK_INT < ANDROID_17_API_LEVEL ||
            checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED
        ) {
            networkAccessGranted = true
            networkPermissionDenied = false
            startReceiverNetwork()
            return
        }

        networkAccessGranted = false
        stopReceiverNetwork()
        if (requestIfMissing) requestLocalNetworkAccess()
    }

    private fun requestLocalNetworkAccess() {
        if (Build.VERSION.SDK_INT < ANDROID_17_API_LEVEL) {
            networkAccessGranted = true
            networkPermissionDenied = false
            startReceiverNetwork()
            return
        }

        if (checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED) {
            networkAccessGranted = true
            networkPermissionDenied = false
            startReceiverNetwork()
            return
        }

        localNetworkPermissionLauncher.launch(Manifest.permission.ACCESS_LOCAL_NETWORK)
    }

    private fun startReceiverNetwork() {
        if (!networkAccessGranted || server != null || advertiser != null) return

        networkStartError = null
        try {
            val newServer = ReceiverHttpServer(
                port = port,
                controller = controller,
                pairingCode = pairingCodeStore.code,
            ).also { it.start(NanoTimeout.SOCKET_READ_TIMEOUT, false) }
            server = newServer

            val newAdvertiser = NsdAdvertiser(this)
            advertiser = newAdvertiser
            newAdvertiser.start(port) { errorCode ->
                runOnUiThread {
                    if (advertiser === newAdvertiser) {
                        stopReceiverNetwork()
                        networkStartError =
                            "StreamFlow TV konnte die Geräteerkennung im lokalen Netzwerk nicht registrieren (Fehler $errorCode). Versuche es erneut."
                    }
                }
            }
        } catch (_: Exception) {
            stopReceiverNetwork()
            networkStartError =
                "StreamFlow TV konnte den lokalen Receiver-Dienst nicht starten. Prüfe die Netzwerkverbindung und versuche es erneut."
        }
    }

    private fun stopReceiverNetwork() {
        advertiser?.stop()
        advertiser = null
        server?.stop()
        server = null
    }

    override fun onDestroy() {
        stopReceiverNetwork()
        controller.release()
        super.onDestroy()
    }

    private fun formatPairingCode(code: String): String = code.chunked(4).joinToString(" ")

    private object NanoTimeout {
        const val SOCKET_READ_TIMEOUT = 5000
    }

    private companion object {
        const val ANDROID_17_API_LEVEL = 37
    }
}
