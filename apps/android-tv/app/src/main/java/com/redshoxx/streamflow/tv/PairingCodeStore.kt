package com.redshoxx.streamflow.tv

import android.content.Context
import java.security.SecureRandom

class PairingCodeStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        "streamflow_receiver",
        Context.MODE_PRIVATE,
    )

    val code: String = preferences.getString(KEY, null)
        ?.takeIf(::isValid)
        ?: generate().also { generated ->
            preferences.edit().putString(KEY, generated).apply()
        }

    private fun generate(): String {
        val value = SecureRandom().nextInt(100_000_000)
        return value.toString().padStart(8, '0')
    }

    private fun isValid(value: String): Boolean =
        value.length == 8 && value.all(Char::isDigit)

    companion object {
        private const val KEY = "pairing_code_v1"
    }
}
