package com.my.focalpoint.utils

object Constants {

    // Firestore Collections
    object Collections {
        const val USERS = "users"
        const val SHIFTS = "shifts"
        const val SPORTS_ROSTERS = "sports_rosters"
        const val SPORTS_JOBS = "sports_jobs"
    }

    // Deep Link Schemes
    object DeepLinks {
        const val SCHEME = "iconikemployee"
        const val HOST_SHIFT = "shift"
        const val HOST_CHAT = "chat"
    }

    // Notification Channels
    object NotificationChannels {
        const val CHAT = "chat_notifications"
        const val SHIFTS = "shift_notifications"
        const val GENERAL = "general_notifications"
    }

    // SharedPreferences Keys
    object PreferenceKeys {
        const val LAST_SYNC = "last_sync"
        const val FCM_TOKEN = "fcm_token"
        const val USER_ID = "user_id"
    }

    // Request Codes
    object RequestCodes {
        const val CAMERA_PERMISSION = 1001
        const val STORAGE_PERMISSION = 1002
        const val LOCATION_PERMISSION = 1003
        const val NOTIFICATION_PERMISSION = 1004
    }

    // Claude API
    object Claude {
        const val MODEL = "claude-sonnet-4-5-20250929"
        const val MAX_TOKENS = 4096
        const val API_VERSION = "2023-06-01"
    }

    // Image Processing
    object ImageProcessing {
        const val MAX_SIZE_KB = 5000
        const val DEFAULT_QUALITY = 90
    }

    // Roster
    object Roster {
        const val DEFAULT_STARTING_ID = 101
    }

    // App Info
    object App {
        const val NAME = "MyFocalPoint"
        const val SUPPORT_EMAIL = "support@myfocalpoint.com"
    }
}
