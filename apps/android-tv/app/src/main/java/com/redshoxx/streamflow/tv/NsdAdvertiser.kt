package com.redshoxx.streamflow.tv

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build

class NsdAdvertiser(context: Context) {
    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var listener: NsdManager.RegistrationListener? = null

    private val manufacturer = Build.MANUFACTURER.orEmpty().trim()
    private val model = Build.MODEL.orEmpty().trim().ifEmpty { "Android TV" }
    private val isFireTv = manufacturer.equals("Amazon", ignoreCase = true) ||
        model.startsWith("AFT", ignoreCase = true) ||
        model.contains("Fire TV", ignoreCase = true)

    private val receiverName: String
        get() = if (isFireTv) {
            "Fire TV - $model"
        } else {
            "StreamFlow TV - $model"
        }

    fun start(port: Int, onFailure: (Int) -> Unit = {}) {
        stop()
        val info = NsdServiceInfo().apply {
            serviceName = receiverName
            serviceType = "_streamflow._tcp."
            setPort(port)
            setAttribute("version", "1.1.0")
            setAttribute("protocol", "2")
            setAttribute("pairing", "required")
            setAttribute("deviceClass", if (isFireTv) "firetv" else "androidtv")
            setAttribute("manufacturer", manufacturer.take(40))
            setAttribute("model", model.take(40))
        }
        val registration = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) = Unit

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                if (listener === this) {
                    listener = null
                    onFailure(errorCode)
                }
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
        }
        listener = registration
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, registration)
    }

    fun stop() {
        listener?.let { runCatching { nsd.unregisterService(it) } }
        listener = null
    }
}
