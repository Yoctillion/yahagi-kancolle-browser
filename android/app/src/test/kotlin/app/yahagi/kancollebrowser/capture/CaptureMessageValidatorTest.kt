package app.yahagi.kancollebrowser.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureMessageValidatorTest {
    @Test
    fun timestampsPreserveUtcAndMillisecondPrecisionAcrossConcurrentCalls() {
        val executor = java.util.concurrent.Executors.newFixedThreadPool(8)
        val previous = java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("Asia/Tokyo"))
            val results = (0L..999L).map { millis ->
                executor.submit<String> { formatCaptureTimestamp(1_790_784_000_000L + millis) }
            }
            results.forEachIndexed { millis, result ->
                assertEquals(java.time.Instant.ofEpochMilli(1_790_784_000_000L + millis).toEpochMilli(),
                    java.time.Instant.parse(result.get(5, java.util.concurrent.TimeUnit.SECONDS)).toEpochMilli())
                assertTrue(result.get().matches(Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z")))
            }
            assertEquals("1970-01-01T00:00:00.000Z", formatCaptureTimestamp(0))
            assertEquals("1969-12-31T23:59:59.999Z", formatCaptureTimestamp(-1))
        } finally {
            java.util.TimeZone.setDefault(previous)
            executor.shutdownNow()
        }
    }

    @Test
    fun defaultClockWorksWhenJavaTimeIsUnavailableOnApi24And25() {
        val parent = CaptureMessageValidator::class.java.classLoader
        val legacyLoader = object : ClassLoader(parent) {
            override fun loadClass(name: String, resolve: Boolean): Class<*> {
                if (name.startsWith("java.time.")) throw ClassNotFoundException(name)
                if (!name.startsWith("app.yahagi.kancollebrowser.capture.")) {
                    return super.loadClass(name, resolve)
                }
                return synchronized(this) {
                    val type = findLoadedClass(name) ?: run {
                        val bytes = parent.getResourceAsStream(name.replace('.', '/') + ".class")!!
                            .use { it.readBytes() }
                        defineClass(name, bytes, 0, bytes.size)
                    }
                    if (resolve) resolveClass(type)
                    type
                }
            }
        }
        val type = legacyLoader.loadClass(CaptureMessageValidator::class.java.name)
        val validator = type.getConstructor().newInstance()
        val before = System.currentTimeMillis()
        val event = type.getMethod("validate", String::class.java, String::class.java)
            .invoke(validator, validMessage(), "https://w01y.kancolle-server.com") as Map<*, *>
        val capturedAt = event["capturedAt"] as String
        assertTrue(capturedAt.endsWith("Z"))
        val timestamp = java.time.Instant.parse(capturedAt).toEpochMilli()
        assertTrue(timestamp in before..System.currentTimeMillis())
    }

    @Test
    fun preservesDocumentCaptureSessionInStringAndBinaryMessages() {
        val validator = CaptureMessageValidator()
        val json = org.json.JSONObject(validMessage()).put("captureSessionId", "session-b")
            .put("captureDocumentId", "document-b").put("captureDocumentStartedAtEpochMs", 2000.5)
        assertEquals("session-b", validator.validate(json.toString(), "https://w01y.kancolle-server.com")?.get("captureSessionId"))
        assertEquals("document-b", validator.validate(json.toString(), "https://w01y.kancolle-server.com")?.get("captureDocumentId"))
        val response = json.getString("responseBody").toByteArray(Charsets.UTF_8)
        json.remove("responseBody")
        val metadata = json.toString().toByteArray(Charsets.UTF_8)
        val payload = java.nio.ByteBuffer.allocate(4 + metadata.size + response.size)
            .putInt(metadata.size).put(metadata).put(response).array()
        assertEquals("session-b", validator.validate(payload, "https://w01y.kancolle-server.com")?.get("captureSessionId"))
        assertEquals(2000.5, validator.validate(payload, "https://w01y.kancolle-server.com")?.get("captureDocumentStartedAtEpochMs"))
    }

    @Test
    fun validatesProtocolAndAddsTrustedNativeMetadata() {
        val validator = CaptureMessageValidator(
            clock = { "2026-07-30T10:00:00.000Z" },
        )

        val event = validator.validate(
            validMessage(),
            "https://w01y.kancolle-server.com",
        )

        assertNotNull(event)
        assertEquals(1, event?.get("version"))
        assertEquals("kcsapi_response", event?.get("kind"))
        assertEquals("/kcsapi/api_port/port", event?.get("path"))
        assertEquals(
            "https://w01y.kancolle-server.com",
            event?.get("sourceOrigin"),
        )
        assertEquals("2026-07-30T10:00:00.000Z", event?.get("capturedAt"))
        assertEquals(1L, event?.get("sequence"))
    }

    @Test
    fun removesSensitiveRequestParametersRecursively() {
        val validator = CaptureMessageValidator()

        val event = validator.validate(
            validMessage(
                requestParams = """
                    {
                      "api_verno": "1",
                      "api_token": "secret",
                      "nested": {
                        "api_starttime": "secret",
                        "safe": true
                      }
                    }
                """.trimIndent(),
            ),
            "https://w01y.kancolle-server.com",
        )

        val params = event?.get("requestParams") as Map<*, *>
        assertFalse(params.containsKey("api_token"))
        val nested = params["nested"] as Map<*, *>
        assertFalse(nested.containsKey("api_starttime"))
        assertTrue(nested["safe"] as Boolean)
    }

    @Test
    fun validatesBinaryEnvelopeWithoutConvertingTheResponseBodyToAString() {
        val validator = CaptureMessageValidator(
            clock = { "2026-07-30T10:00:00.000Z" },
        )
        val responseBody = "svdata={\"api_result\":1,\"api_data\":\"艦\"}"

        val event = validator.validate(
            validBinaryMessage(responseBody = responseBody),
            "https://w01y.kancolle-server.com",
        )

        assertNotNull(event)
        assertArrayEquals(
            responseBody.toByteArray(Charsets.UTF_8),
            event?.get("responseBodyBytes") as ByteArray,
        )
        assertFalse(event.containsKey("responseBody"))
    }

    @Test
    fun rejectsBinaryEnvelopeWithAnInvalidMetadataLength() {
        val validator = CaptureMessageValidator()
        val invalid = byteArrayOf(0, 0, 1, 0, 1, 2, 3)

        assertNull(
            validator.validate(
                invalid,
                "https://w01y.kancolle-server.com",
            ),
        )
        assertEquals(CaptureMessageFailure.INVALID_FORMAT, validator.lastFailure)
    }

    @Test
    fun rejectsBinaryMessagesOverTheByteLimit() {
        val validator = CaptureMessageValidator(maxMessageBytes = 16)

        assertNull(
            validator.validate(
                validBinaryMessage(),
                "https://w01y.kancolle-server.com",
            ),
        )
        assertEquals(CaptureMessageFailure.TOO_LARGE, validator.lastFailure)
    }

    @Test
    fun rejectsBinaryMetadataThatIsNotValidUtf8() {
        val invalidMetadata = byteArrayOf(0xC3.toByte(), 0x28)
        val payload = java.nio.ByteBuffer.allocate(6)
            .putInt(invalidMetadata.size)
            .put(invalidMetadata)
            .array()
        val validator = CaptureMessageValidator()

        assertNull(
            validator.validate(
                payload,
                "https://w01y.kancolle-server.com",
            ),
        )
        assertEquals(CaptureMessageFailure.INVALID_FORMAT, validator.lastFailure)
    }

    @Test
    fun removesSensitiveParametersFromBinaryMetadata() {
        val validator = CaptureMessageValidator()
        val event = validator.validate(
            validBinaryMessage(
                requestParams = """
                    {
                      "api_token": "secret",
                      "nested": {"api_starttime": "secret", "safe": 1}
                    }
                """.trimIndent(),
            ),
            "https://w01y.kancolle-server.com",
        )

        val params = event?.get("requestParams") as Map<*, *>
        assertFalse(params.containsKey("api_token"))
        val nested = params["nested"] as Map<*, *>
        assertFalse(nested.containsKey("api_starttime"))
        assertEquals(1, nested["safe"])
    }

    @Test
    fun rejectsObsoleteRequestInterceptMessages() {
        val validator = CaptureMessageValidator(
            clock = { "2026-07-30T10:00:00.000Z" },
        )
        val interceptMsg = """
            {
              "version": 1,
              "kind": "kcsapi_request_intercept",
              "path": "/kcsapi/api_req_map/start",
              "requestParams": {},
              "id": "123"
            }
        """.trimIndent()
        
        val event = validator.validate(interceptMsg, "https://w01y.kancolle-server.com")
        assertNull(event)
    }


    @Test
    fun rejectsWrongProtocolPathMethodAndTransport() {
        val validator = CaptureMessageValidator()

        assertNull(
            validator.validate(
                validMessage(version = 2),
                "https://w01y.kancolle-server.com",
            ),
        )
        assertNull(
            validator.validate(
                validMessage(path = "/analytics"),
                "https://w01y.kancolle-server.com",
            ),
        )
        assertNull(
            validator.validate(
                validMessage(method = "PUT"),
                "https://w01y.kancolle-server.com",
            ),
        )
        assertNull(
            validator.validate(
                validMessage(transport = "beacon"),
                "https://w01y.kancolle-server.com",
            ),
        )
    }

    @Test
    fun rejectsMessagesOverTheUtf8ByteLimit() {
        val validator = CaptureMessageValidator(maxMessageBytes = 32)

        assertNull(
            validator.validate(
                validMessage(responseBody = "舰".repeat(20)),
                "https://w01y.kancolle-server.com",
            ),
        )
        assertEquals(
            CaptureMessageFailure.TOO_LARGE,
            validator.lastFailure,
        )
    }

    private fun validMessage(
        version: Int = 1,
        path: String = "/kcsapi/api_port/port",
        method: String = "POST",
        transport: String = "xhr",
        responseBody: String = "svdata={\"api_result\":1}",
        requestParams: String = "{}",
    ): String {
        return """
            {
              "version": $version,
              "kind": "kcsapi_response",
              "method": "$method",
              "path": "$path",
              "requestParams": $requestParams,
              "responseBody": ${jsonString(responseBody)},
              "statusCode": 200,
              "transport": "$transport"
            }
        """.trimIndent()
    }

    private fun validBinaryMessage(
        responseBody: String = "svdata={\"api_result\":1}",
        requestParams: String = "{}",
    ): ByteArray {
        val metadata = """
            {
              "version": 1,
              "kind": "kcsapi_response",
              "method": "POST",
              "path": "/kcsapi/api_port/port",
              "requestParams": $requestParams,
              "statusCode": 200,
              "transport": "fetch"
            }
        """.trimIndent().toByteArray(Charsets.UTF_8)
        val body = responseBody.toByteArray(Charsets.UTF_8)
        return java.nio.ByteBuffer.allocate(4 + metadata.size + body.size)
            .putInt(metadata.size)
            .put(metadata)
            .put(body)
            .array()
    }

    private fun jsonString(value: String): String {
        return "\"" + value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"") + "\""
    }
}
