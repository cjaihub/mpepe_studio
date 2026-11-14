package com.oneova.app

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Payment device key (build log D1): a P-256 key made inside the Android
 * Keystore (StrongBox when the phone has it) that can only sign after a strong
 * biometric. The private key never leaves the secure hardware; the app gets the
 * public key and Google's attestation chain, and signatures over the exact bytes
 * the server sends. Enrolling a new fingerprint or face invalidates the key.
 */
class DeviceKeyChannel(private val activity: FragmentActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.oneova.app/device_key")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "available" -> result.success(available())
                    "exists" -> result.success(keyStore().containsAlias(alias(call.argument<String>("alias"))))
                    "delete" -> {
                        val a = alias(call.argument<String>("alias"))
                        if (keyStore().containsAlias(a)) keyStore().deleteEntry(a)
                        result.success(true)
                    }
                    "create" -> result.success(
                        create(alias(call.argument<String>("alias")), decode(call.argument<String>("challenge")))
                    )
                    "sign" -> sign(
                        alias(call.argument<String>("alias")),
                        decode(call.argument<String>("data")),
                        call.argument<String>("title") ?: "Confirm it's you",
                        call.argument<String>("subtitle") ?: "",
                        result,
                    )
                    else -> result.notImplemented()
                }
            } catch (e: IllegalArgumentException) {
                result.error("bad_args", e.message, null)
            } catch (e: Exception) {
                result.error("device_key", e.javaClass.simpleName, null)
            }
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun alias(v: String?): String {
        require(v != null && Regex("^[A-Za-z0-9_.-]{1,64}$").matches(v)) { "alias" }
        return "oneova_pay_$v"
    }

    private fun decode(v: String?): ByteArray {
        require(!v.isNullOrEmpty() && v.length <= 8192) { "data" }
        return Base64.decode(v, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun encode(b: ByteArray): String = Base64.encodeToString(b, Base64.NO_WRAP)

    private fun available(): String =
        when (BiometricManager.from(activity).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "ready"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "not_enrolled"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE, BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "no_hardware"
            else -> "unavailable"
        }

    private fun spec(alias: String, challenge: ByteArray, strongBox: Boolean): KeyGenParameterSpec {
        val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .setAttestationChallenge(challenge)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Every signature needs its own biometric check (no time window).
            b.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            b.setUserAuthenticationValidityDurationSeconds(-1)
        }
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) b.setIsStrongBoxBacked(true)
        return b.build()
    }

    private fun create(alias: String, challenge: ByteArray): Map<String, Any> {
        val ks = keyStore()
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
        val gen = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        val pair = try {
            gen.initialize(spec(alias, challenge, strongBox = true))
            gen.generateKeyPair()
        } catch (e: Exception) {
            // No StrongBox (StrongBoxUnavailableException), or StrongBox can't make
            // this key: use the TEE. The attestation says which one it is.
            if (ks.containsAlias(alias)) ks.deleteEntry(alias)
            gen.initialize(spec(alias, challenge, strongBox = false))
            gen.generateKeyPair()
        }
        val chain = ks.getCertificateChain(alias)?.map { encode(it.encoded) } ?: emptyList()
        return mapOf("publicKey" to encode(pair.public.encoded), "attestation" to chain)
    }

    private fun sign(alias: String, data: ByteArray, title: String, subtitle: String, result: MethodChannel.Result) {
        val key = keyStore().getKey(alias, null) as? PrivateKey
        if (key == null) {
            result.error("no_key", "not registered", null)
            return
        }
        val sig = Signature.getInstance("SHA256withECDSA")
        try {
            sig.initSign(key)
        } catch (e: KeyPermanentlyInvalidatedException) {
            // A fingerprint or face was added or removed: the key is gone for good.
            keyStore().deleteEntry(alias)
            result.error("invalidated", "biometrics changed", null)
            return
        }
        var answered = false
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                if (answered) return
                answered = true
                try {
                    val s = r.cryptoObject?.signature ?: throw IllegalStateException("no signature")
                    s.update(data)
                    result.success(encode(s.sign()))
                } catch (e: Exception) {
                    result.error("sign_failed", e.javaClass.simpleName, null)
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                if (answered) return
                answered = true
                val c = when (code) {
                    BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON, BiometricPrompt.ERROR_CANCELED -> "cancelled"
                    BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
                    else -> "auth_error"
                }
                result.error(c, msg.toString(), null)
            }
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title.take(60))
            .apply { if (subtitle.isNotEmpty()) setSubtitle(subtitle.take(80)) }
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .setNegativeButtonText("Cancel")
            .setConfirmationRequired(true)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(sig))
    }
}
