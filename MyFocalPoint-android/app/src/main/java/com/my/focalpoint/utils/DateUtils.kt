package com.my.focalpoint.utils

import com.google.firebase.Timestamp
import java.text.SimpleDateFormat
import java.util.*

object DateUtils {

    private val dateFormatter = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
    private val timeFormatter = SimpleDateFormat("h:mm a", Locale.getDefault())
    private val dateTimeFormatter = SimpleDateFormat("MMM dd, yyyy • h:mm a", Locale.getDefault())
    private val fullDateFormatter = SimpleDateFormat("EEEE, MMMM dd, yyyy", Locale.getDefault())

    /**
     * Format timestamp to date string
     */
    fun formatDate(timestamp: Timestamp): String {
        return dateFormatter.format(timestamp.toDate())
    }

    /**
     * Format timestamp to time string
     */
    fun formatTime(timestamp: Timestamp): String {
        return timeFormatter.format(timestamp.toDate())
    }

    /**
     * Format timestamp to date and time string
     */
    fun formatDateTime(timestamp: Timestamp): String {
        return dateTimeFormatter.format(timestamp.toDate())
    }

    /**
     * Format timestamp to full date string
     */
    fun formatFullDate(timestamp: Timestamp): String {
        return fullDateFormatter.format(timestamp.toDate())
    }

    /**
     * Get relative time string (e.g., "2 hours ago", "Yesterday")
     */
    fun getRelativeTimeString(timestamp: Timestamp): String {
        val now = System.currentTimeMillis()
        val time = timestamp.toDate().time
        val diff = now - time

        return when {
            diff < 60 * 1000 -> "Just now"
            diff < 60 * 60 * 1000 -> "${diff / (60 * 1000)} minutes ago"
            diff < 24 * 60 * 60 * 1000 -> "${diff / (60 * 60 * 1000)} hours ago"
            diff < 2 * 24 * 60 * 60 * 1000 -> "Yesterday"
            diff < 7 * 24 * 60 * 60 * 1000 -> "${diff / (24 * 60 * 60 * 1000)} days ago"
            else -> formatDate(timestamp)
        }
    }

    /**
     * Check if timestamp is today
     */
    fun isToday(timestamp: Timestamp): Boolean {
        val calendar = Calendar.getInstance()
        val today = calendar.get(Calendar.DAY_OF_YEAR)

        calendar.time = timestamp.toDate()
        val thatDay = calendar.get(Calendar.DAY_OF_YEAR)

        return today == thatDay
    }

    /**
     * Check if timestamp is in the past
     */
    fun isPast(timestamp: Timestamp): Boolean {
        return timestamp.toDate().time < System.currentTimeMillis()
    }
}
