package com.oneova.app

import android.content.Context
import android.location.Geocoder
import android.os.Build
import android.telephony.TelephonyManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Country signals for the KYC country detector, all on the phone (no third
 * party, no API key): SIM country, mobile network country, and the phone's own
 * reverse geocoder for a GPS fix the app already has permission for.
 */
class CountrySignalsChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.oneova.app/country_signals")
    private val io = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "telephony" -> {
                    val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                    result.success(
                        mapOf(
                            "sim" to (tm?.simCountryIso ?: "").uppercase(Locale.ROOT),
                            "network" to (tm?.networkCountryIso ?: "").uppercase(Locale.ROOT),
                        )
                    )
                }
                "countryAt" -> {
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    if (lat == null || lng == null || !Geocoder.isPresent()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val main = android.os.Handler(android.os.Looper.getMainLooper())
                    val geocoder = Geocoder(context, Locale.ENGLISH)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        geocoder.getFromLocation(lat, lng, 1, object : Geocoder.GeocodeListener {
                            override fun onGeocode(list: MutableList<android.location.Address>) {
                                main.post { result.success(list.firstOrNull()?.countryCode?.uppercase(Locale.ROOT)) }
                            }

                            override fun onError(errorMessage: String?) {
                                main.post { result.success(null) }
                            }
                        })
                    } else {
                        io.execute {
                            val code = try {
                                @Suppress("DEPRECATION")
                                geocoder.getFromLocation(lat, lng, 1)?.firstOrNull()?.countryCode?.uppercase(Locale.ROOT)
                            } catch (e: Exception) {
                                null
                            }
                            main.post { result.success(code) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
