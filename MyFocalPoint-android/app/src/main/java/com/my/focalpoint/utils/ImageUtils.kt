package com.my.focalpoint.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import java.io.ByteArrayOutputStream

object ImageUtils {

    /**
     * Convert image URI to Base64 string for Claude API
     */
    fun uriToBase64(uri: Uri, context: Context, maxSizeKB: Int = 5000): String {
        val inputStream = context.contentResolver.openInputStream(uri)
            ?: throw IllegalArgumentException("Cannot open input stream for URI: $uri")

        // Decode bitmap
        var bitmap = BitmapFactory.decodeStream(inputStream)
        inputStream.close()

        // Compress if needed
        var quality = 90
        var outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)

        // Reduce quality if image is too large
        while (outputStream.toByteArray().size / 1024 > maxSizeKB && quality > 10) {
            quality -= 10
            outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
        }

        val bytes = outputStream.toByteArray()
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    /**
     * Get MIME type from URI
     */
    fun getMimeType(uri: Uri, context: Context): String {
        return context.contentResolver.getType(uri) ?: "image/jpeg"
    }

    /**
     * Convert MIME type to format expected by Claude API
     */
    fun normalizeMimeType(mimeType: String): String {
        return when {
            mimeType.contains("png", ignoreCase = true) -> "image/png"
            mimeType.contains("jpeg", ignoreCase = true) -> "image/jpeg"
            mimeType.contains("jpg", ignoreCase = true) -> "image/jpeg"
            mimeType.contains("webp", ignoreCase = true) -> "image/webp"
            else -> "image/jpeg"
        }
    }
}
