package com.airbridge.update

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Fetches and validates the update manifest. Runs ONLY when the user taps
 * "Check for updates" — never on a timer or at startup (transparency rule).
 *
 * Deliberately a plain OkHttpClient with system CA trust: PinnedTls pins
 * paired-device certs for LAN peers; the update server is public HTTPS.
 */
class UpdateChecker(
    private val manifestUrl: String = DEFAULT_MANIFEST_URL,
    private val publicKeyRawBase64: String = UPDATE_PUBLIC_KEY_B64
) {
    sealed class CheckResult {
        data class UpdateAvailable(val manifest: UpdateManifest) : CheckResult()
        object UpToDate : CheckResult()
        data class Failed(val reason: String) : CheckResult()
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    suspend fun check(installedVersionCode: Int): CheckResult = withContext(Dispatchers.IO) {
        try {
            val manifestBytes = fetch(manifestUrl) ?: return@withContext CheckResult.Failed("manifest fetch failed")
            val sigText = fetch("$manifestUrl.sig")?.decodeToString()?.trim()
                ?: return@withContext CheckResult.Failed("signature fetch failed")
            if (!UpdateManifest.verifySignature(manifestBytes, sigText, publicKeyRawBase64)) {
                return@withContext CheckResult.Failed("signature invalid")
            }
            val manifest = UpdateManifest.parse(manifestBytes.decodeToString())
            if (manifest.isNewerThan(installedVersionCode)) CheckResult.UpdateAvailable(manifest)
            else CheckResult.UpToDate
        } catch (e: Exception) {
            CheckResult.Failed(e.message ?: e.javaClass.simpleName)
        }
    }

    private fun fetch(url: String): ByteArray? =
        client.newCall(Request.Builder().url(url).build()).execute().use { resp ->
            if (!resp.isSuccessful) null else resp.body.bytes()
        }

    companion object {
        const val DEFAULT_MANIFEST_URL = "https://updates.vintrhall.com/airbridge/manifest.json"
        const val UPDATE_PUBLIC_KEY_B64 = "842aa+wK7BUs8CVyg/d2cgyKYC6IGQ2kiYgeyR9YxTo="
    }
}
