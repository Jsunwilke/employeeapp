package com.my.focalpoint.ui.navigation

sealed class Screen(val route: String) {
    // Auth
    object Login : Screen("login")

    // Main tabs
    object Shifts : Screen("shifts")
    object Sports : Screen("sports")
    object Chat : Screen("chat")
    object Profile : Screen("profile")

    // Shift screens
    object ShiftDetail : Screen("shift/{shiftId}") {
        fun createRoute(shiftId: String) = "shift/$shiftId"
    }
    object CreateShift : Screen("shift/create")

    // Sports screens
    object RosterList : Screen("roster/list")
    object RosterImport : Screen("roster/import")
    object RosterDetail : Screen("roster/{rosterId}") {
        fun createRoute(rosterId: String) = "roster/$rosterId"
    }
    object MultiPhotoImport : Screen("photo/multi-import/{jobId}") {
        fun createRoute(jobId: String) = "photo/multi-import/$jobId"
    }
    object SportsJobList : Screen("sports/jobs")
    object SportsJobDetail : Screen("sports/job/{jobId}") {
        fun createRoute(jobId: String) = "sports/job/$jobId"
    }

    // Chat screens
    object ChatList : Screen("chat/list")
    object ChatDetail : Screen("chat/{channelId}") {
        fun createRoute(channelId: String) = "chat/$channelId"
    }

    // Settings
    object Settings : Screen("settings")
    object OrganizationSettings : Screen("settings/organization")
}
