package com.my.focalpoint.data.remote

import com.my.focalpoint.BuildConfig
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.POST

interface ClaudeApiService {
    @POST("v1/messages")
    suspend fun sendMessage(
        @Header("x-api-key") apiKey: String = BuildConfig.CLAUDE_API_KEY,
        @Header("anthropic-version") version: String = "2023-06-01",
        @Body request: ClaudeRequest
    ): ClaudeResponse
}

data class ClaudeRequest(
    val model: String = "claude-sonnet-4-5-20250929",
    val max_tokens: Int = 4096,
    val messages: List<ClaudeMessage>
)

data class ClaudeMessage(
    val role: String,  // "user" or "assistant"
    val content: List<ClaudeContent>
)

sealed class ClaudeContent {
    data class Text(
        val type: String = "text",
        val text: String
    ) : ClaudeContent()

    data class Image(
        val type: String = "image",
        val source: ClaudeImageSource
    ) : ClaudeContent()
}

data class ClaudeImageSource(
    val type: String = "base64",
    val media_type: String,  // "image/jpeg" or "image/png"
    val data: String  // Base64 encoded image
)

data class ClaudeResponse(
    val id: String,
    val type: String,
    val role: String,
    val content: List<ClaudeResponseContent>,
    val model: String,
    val stop_reason: String?,
    val usage: ClaudeUsage?
)

data class ClaudeResponseContent(
    val type: String,  // "text"
    val text: String
)

data class ClaudeUsage(
    val input_tokens: Int,
    val output_tokens: Int
)
