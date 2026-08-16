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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
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
                Box(modifier = Modifier.fillMaxSize().background(StreamFlowBackground)) {
                    if (networkAccessGranted && networkStartError == null && state.mediaUrl != null) {
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
                            IdleDashboard(pairingCodeStore.code)
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun IdleDashboard(pairingCode: String) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(StreamFlowBackground)
                .padding(horizontal = 54.dp, vertical = 36.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .background(StreamFlowBlue, RoundedCornerShape(11.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "▶",
                        color = Color.White,
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
                Spacer(Modifier.width(12.dp))
                Text(
                    "StreamFlow TV",
                    color = Color.White,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(Modifier.weight(1f))
                Text("Startseite", color = StreamFlowBlue, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.width(28.dp))
                Text("Medien", color = StreamFlowMuted)
                Spacer(Modifier.width(28.dp))
                Text("Einstellungen", color = StreamFlowMuted)
            }

            Spacer(Modifier.height(34.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(300.dp),
                horizontalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Surface(
                    modifier = Modifier
                        .weight(1.3f)
                        .fillMaxSize(),
                    color = StreamFlowSurface,
                    shape = RoundedCornerShape(22.dp),
                ) {
                    Column(
                        modifier = Modifier.padding(30.dp),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            "BEREIT ZUM STREAMEN",
                            color = StreamFlowBlue,
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.height(10.dp))
                        Text(
                            "Deine Medien.\nDein Fernseher.",
                            color = Color.White,
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.height(14.dp))
                        Text(
                            "Öffne StreamFlow auf deinem Smartphone, wähle diesen Fernseher und starte die Wiedergabe.",
                            color = StreamFlowMuted,
                            style = MaterialTheme.typography.bodyLarge,
                        )
                    }
                }

                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxSize(),
                    color = StreamFlowBlueDark,
                    shape = RoundedCornerShape(22.dp),
                ) {
                    Column(
                        modifier = Modifier.padding(28.dp),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            "VERBINDUNG",
                            color = Color(0xFF8FC1FF),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.height(10.dp))
                        Text(
                            "Kopplungscode",
                            color = Color.White,
                            style = MaterialTheme.typography.headlineSmall,
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            formatPairingCode(pairingCode),
                            color = Color.White,
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.height(14.dp))
                        Surface(
                            color = Color.White.copy(alpha = 0.10f),
                            shape = RoundedCornerShape(999.dp),
                        ) {
                            Text(
                                "● Receiver online",
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                                color = Color(0xFF9CE7B3),
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(20.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                DashboardStatusCard(
                    modifier = Modifier.weight(1f),
                    title = "Receiver",
                    subtitle = "Android TV • Google TV • Fire TV",
                )
                DashboardStatusCard(
                    modifier = Modifier.weight(1f),
                    title = "Streaming",
                    subtitle = "HLS • DASH • Direktlinks",
                )
                DashboardStatusCard(
                    modifier = Modifier.weight(1f),
                    title = "Lokale Dateien",
                    subtitle = "Mit Range-Seeking",
                )
                DashboardStatusCard(
                    modifier = Modifier.weight(1f),
                    title = "Steuerung",
                    subtitle = "Play • Seek • Lautstärke",
                )
            }

            Spacer(Modifier.weight(1f))
            Text(
                "StreamFlow ${BuildConfig.VERSION_NAME}  •  Sicheres Pairing  •  Universal Casting Receiver",
                color = StreamFlowMuted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }

    @Composable
    private fun DashboardStatusCard(
        modifier: Modifier,
        title: String,
        subtitle: String,
    ) {
        Surface(
            modifier = modifier.height(92.dp),
            color = StreamFlowSurface,
            shape = RoundedCornerShape(17.dp),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 15.dp),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    title,
                    color = Color.White,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    subtitle,
                    color = StreamFlowMuted,
                    style = MaterialTheme.typography.bodySmall,
                )
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
                color = StreamFlowMuted,
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
        val StreamFlowBackground = Color(0xFF06101B)
        val StreamFlowSurface = Color(0xFF0E1B29)
        val StreamFlowBlue = Color(0xFF4592FF)
        val StreamFlowBlueDark = Color(0xFF0B3A73)
        val StreamFlowMuted = Color(0xFFA7B4C3)
    }
}
