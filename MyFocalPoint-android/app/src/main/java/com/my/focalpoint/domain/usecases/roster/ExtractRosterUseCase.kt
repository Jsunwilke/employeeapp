package com.my.focalpoint.domain.usecases.roster

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.my.focalpoint.BuildConfig
import com.my.focalpoint.data.models.RosterEntry
import com.my.focalpoint.data.remote.*
import com.my.focalpoint.utils.ImageUtils
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject

class ExtractRosterUseCase @Inject constructor(
    private val claudeApiService: ClaudeApiService,
    @ApplicationContext private val context: Context
) {

    companion object {
        private const val TAG = "ExtractRosterUseCase"
    }

    /**
     * Extract roster from a single image
     */
    suspend fun extractFromImage(
        imageUri: Uri,
        startingSubjectId: Int = 101
    ): Result<List<RosterEntry>> {
        return try {
            // Validate API key
            validateApiKey()

            Log.d(TAG, "Processing image: $imageUri")

            // Convert image to Base64
            val base64Image = ImageUtils.uriToBase64(imageUri, context)
            val mimeType = ImageUtils.getMimeType(imageUri, context)
            val normalizedMimeType = ImageUtils.normalizeMimeType(mimeType)

            Log.d(TAG, "Image converted to Base64, MIME type: $normalizedMimeType")

            // Create Claude API request
            val request = createRosterExtractionRequest(base64Image, normalizedMimeType)

            // Call Claude API
            Log.d(TAG, "Sending request to Claude API...")
            val response = claudeApiService.sendMessage(request = request)

            Log.d(TAG, "Received response from Claude API")
            Log.d(TAG, "Response: ${response.content.firstOrNull()?.text}")

            // Parse response
            val jsonText = response.content.firstOrNull()?.text
                ?: throw Exception("No response content from Claude")

            val entries = parseRosterJson(jsonText)
            Log.d(TAG, "Parsed ${entries.size} roster entries")

            // Sort and assign IDs
            val processedEntries = sortAndAssignIds(entries, startingSubjectId)

            Result.success(processedEntries)
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting roster", e)
            Result.failure(e)
        }
    }

    /**
     * Extract roster from multiple images and combine
     */
    suspend fun extractFromImages(
        imageUris: List<Uri>,
        startingSubjectId: Int = 101
    ): Result<List<RosterEntry>> {
        return try {
            validateApiKey()

            val allEntries = mutableListOf<RosterEntry>()

            imageUris.forEachIndexed { index, uri ->
                Log.d(TAG, "Processing image ${index + 1}/${imageUris.size}")

                val result = extractFromImage(uri, startingSubjectId = 0)  // Use 0 temporarily
                if (result.isSuccess) {
                    allEntries.addAll(result.getOrNull() ?: emptyList())
                } else {
                    // Log error but continue with other images
                    Log.e(TAG, "Failed to extract from image $index", result.exceptionOrNull())
                }
            }

            // Sort all entries together and assign sequential IDs
            val processedEntries = sortAndAssignIds(allEntries, startingSubjectId)

            Result.success(processedEntries)
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting from multiple images", e)
            Result.failure(e)
        }
    }

    private fun validateApiKey() {
        val apiKey = BuildConfig.CLAUDE_API_KEY

        // Check for empty key
        if (apiKey.isEmpty()) {
            throw IllegalStateException("Claude API key is empty")
        }

        // Check for un-substituted variable
        if (apiKey.contains("$(") || apiKey.contains("BuildConfig")) {
            throw IllegalStateException("Claude API key not properly substituted: $apiKey")
        }

        // Check format
        if (!apiKey.startsWith("sk-ant-api03-")) {
            throw IllegalStateException("Invalid Claude API key format")
        }
    }

    private fun createRosterExtractionRequest(
        base64Image: String,
        mimeType: String
    ): ClaudeRequest {
        val prompt = buildRosterExtractionPrompt()

        return ClaudeRequest(
            model = "claude-sonnet-4-5-20250929",
            max_tokens = 4096,
            messages = listOf(
                ClaudeMessage(
                    role = "user",
                    content = listOf(
                        ClaudeContent.Image(
                            source = ClaudeImageSource(
                                type = "base64",
                                media_type = mimeType,
                                data = base64Image
                            )
                        ),
                        ClaudeContent.Text(
                            text = prompt
                        )
                    )
                )
            )
        )
    }

    private fun buildRosterExtractionPrompt(): String {
        return """
            Extract all player information from this sports roster image.

            Return ONLY a valid JSON array with this exact structure:
            [
              {
                "firstName": "",
                "lastName": "Full Player Name Here",
                "graduationYear": "YYYY",
                "grade": "grade level"
              }
            ]

            IMPORTANT RULES:
            1. Put the player's FULL NAME in the "lastName" field
            2. Leave "firstName" as an empty string (it will be assigned as a subject ID later)
            3. Extract graduation year if visible (format: YYYY like "2025", "2026", etc.)
            4. Extract grade if visible (like "9", "10", "11", "12", or "Freshman", "Sophomore", etc.)
            5. If graduation year or grade are not visible, use empty string ""
            6. Return ONLY the JSON array, no other text before or after
            7. Make sure the JSON is valid and properly formatted

            Example correct output:
            [
              {"firstName": "", "lastName": "John Smith", "graduationYear": "2025", "grade": "12"},
              {"firstName": "", "lastName": "Jane Doe", "graduationYear": "2026", "grade": "11"}
            ]
        """.trimIndent()
    }

    private fun parseRosterJson(jsonText: String): List<RosterEntry> {
        try {
            // Find the JSON array in the response
            val startIndex = jsonText.indexOf('[')
            val endIndex = jsonText.lastIndexOf(']')

            if (startIndex == -1 || endIndex == -1) {
                throw Exception("No JSON array found in response")
            }

            val jsonArray = jsonText.substring(startIndex, endIndex + 1)
            Log.d(TAG, "Extracted JSON: $jsonArray")

            // Parse with Gson
            val gson = Gson()
            val type = object : TypeToken<List<RosterEntry>>() {}.type
            val entries: List<RosterEntry> = gson.fromJson(jsonArray, type)

            if (entries.isEmpty()) {
                throw Exception("No roster entries found in response")
            }

            return entries
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing JSON: $jsonText", e)
            throw Exception("Failed to parse roster data: ${e.message}")
        }
    }

    /**
     * Sort entries alphabetically by lastName and assign sequential subject IDs
     *
     * This matches iOS behavior:
     * - Sort by lastName (which contains the full player name)
     * - Assign sequential IDs starting from startingSubjectId (default 101)
     * - IDs go in firstName field (ALICE=101, BOB=102, etc.)
     */
    private fun sortAndAssignIds(
        entries: List<RosterEntry>,
        startingSubjectId: Int
    ): List<RosterEntry> {
        return entries
            .sortedBy { it.lastName.lowercase() }
            .mapIndexed { index, entry ->
                entry.copy(firstName = (startingSubjectId + index).toString())
            }
    }
}
