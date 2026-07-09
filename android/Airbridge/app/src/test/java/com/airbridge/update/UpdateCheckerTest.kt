package com.airbridge.update

import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class UpdateCheckerTest {
    private val kp = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
    private val pubB64 = Base64.getEncoder()
        .encodeToString(kp.public.encoded.takeLast(32).toByteArray())

    private fun manifestJson(code: Int) = """
        {"version":"9.9.9","versionCode":$code,"publishedAt":"2026-07-09",
         "android":{"url":"https://example.com/a.apk","sha256":"ab","size":1},
         "macos":{"url":"https://example.com/a.zip","sha256":"cd","size":1},
         "changelog":{"pl":["P"],"en":["I"]}}
    """.trimIndent()

    private fun sign(body: String): String {
        val sig = Signature.getInstance("Ed25519")
            .apply { initSign(kp.private); update(body.toByteArray()) }.sign()
        return Base64.getEncoder().encodeToString(sig)
    }

    private fun server(body: String, sig: String) = MockWebServer().apply {
        enqueue(MockResponse(body = body))
        enqueue(MockResponse(body = sig))
        start()
    }

    @Test fun `newer version yields UpdateAvailable`() = runBlocking {
        val body = manifestJson(20900)
        val s = server(body, sign(body))
        val result = UpdateChecker(s.url("/manifest.json").toString(), pubB64).check(20800)
        assertTrue(result is UpdateChecker.CheckResult.UpdateAvailable)
        s.close()
    }

    @Test fun `same version yields UpToDate`() = runBlocking {
        val body = manifestJson(20800)
        val s = server(body, sign(body))
        val result = UpdateChecker(s.url("/manifest.json").toString(), pubB64).check(20800)
        assertTrue(result is UpdateChecker.CheckResult.UpToDate)
        s.close()
    }

    @Test fun `bad signature yields Failed`() = runBlocking {
        val body = manifestJson(20900)
        val s = server(body, sign(manifestJson(20901)))  // signature over different bytes
        val result = UpdateChecker(s.url("/manifest.json").toString(), pubB64).check(20800)
        assertTrue(result is UpdateChecker.CheckResult.Failed)
        s.close()
    }
}
