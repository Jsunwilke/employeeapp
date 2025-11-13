package com.my.focalpoint.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.my.focalpoint.ui.auth.LoginScreen
import com.my.focalpoint.ui.shifts.*
import com.my.focalpoint.ui.sports.*
import com.my.focalpoint.ui.chat.*
import com.my.focalpoint.ui.profile.ProfileScreen
import com.my.focalpoint.ui.settings.SettingsScreen
import com.my.focalpoint.ui.settings.OrganizationSettingsScreen

// Bottom navigation items
sealed class BottomNavItem(
    val screen: Screen,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val label: String
) {
    object Shifts : BottomNavItem(Screen.Shifts, Icons.Default.Schedule, "Shifts")
    object Sports : BottomNavItem(Screen.Sports, Icons.Default.SportsBasketball, "Sports")
    object Chat : BottomNavItem(Screen.Chat, Icons.Default.Chat, "Chat")
    object Profile : BottomNavItem(Screen.Profile, Icons.Default.Person, "Profile")
}

val bottomNavItems = listOf(
    BottomNavItem.Shifts,
    BottomNavItem.Sports,
    BottomNavItem.Chat,
    BottomNavItem.Profile
)

@Composable
fun MainNavigation(
    startDestination: String = Screen.Login.route
) {
    val navController = rememberNavController()
    var isAuthenticated by remember { mutableStateOf(false) }

    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
        // Auth
        composable(Screen.Login.route) {
            LoginScreen(
                onLoginSuccess = {
                    isAuthenticated = true
                    navController.navigate(Screen.Shifts.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                }
            )
        }

        // Main app with bottom navigation
        composable(Screen.Shifts.route) {
            MainScaffold(navController, currentScreen = Screen.Shifts)
        }
        composable(Screen.Sports.route) {
            MainScaffold(navController, currentScreen = Screen.Sports)
        }
        composable(Screen.Chat.route) {
            MainScaffold(navController, currentScreen = Screen.Chat)
        }
        composable(Screen.Profile.route) {
            MainScaffold(navController, currentScreen = Screen.Profile)
        }

        // Shift screens
        composable(
            route = Screen.ShiftDetail.route,
            arguments = listOf(navArgument("shiftId") { type = NavType.StringType })
        ) { backStackEntry ->
            val shiftId = backStackEntry.arguments?.getString("shiftId") ?: return@composable
            ShiftDetailScreen(
                shiftId = shiftId,
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(Screen.CreateShift.route) {
            CreateShiftScreen(
                onNavigateBack = { navController.popBackStack() },
                onShiftCreated = { shiftId ->
                    navController.navigate(Screen.ShiftDetail.createRoute(shiftId)) {
                        popUpTo(Screen.Shifts.route)
                    }
                }
            )
        }

        // Sports screens
        composable(Screen.RosterImport.route) {
            RosterImportScreen(
                organizationId = "default_org",
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.RosterDetail.route,
            arguments = listOf(navArgument("rosterId") { type = NavType.StringType })
        ) { backStackEntry ->
            val rosterId = backStackEntry.arguments?.getString("rosterId") ?: return@composable
            RosterDetailScreen(
                rosterId = rosterId,
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.MultiPhotoImport.route,
            arguments = listOf(navArgument("jobId") { type = NavType.StringType })
        ) { backStackEntry ->
            val jobId = backStackEntry.arguments?.getString("jobId") ?: return@composable
            MultiPhotoImportScreen(
                jobId = jobId,
                onNavigateBack = { navController.popBackStack() },
                onComplete = { navController.popBackStack() }
            )
        }

        composable(Screen.SportsJobList.route) {
            SportsJobListScreen(
                onNavigateToJobDetail = { jobId ->
                    navController.navigate(Screen.SportsJobDetail.createRoute(jobId))
                },
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.SportsJobDetail.route,
            arguments = listOf(navArgument("jobId") { type = NavType.StringType })
        ) { backStackEntry ->
            val jobId = backStackEntry.arguments?.getString("jobId") ?: return@composable
            SportsJobDetailScreen(
                jobId = jobId,
                onNavigateToMultiPhotoImport = { navController.navigate(Screen.MultiPhotoImport.createRoute(jobId)) },
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Chat screens
        composable(
            route = Screen.ChatDetail.route,
            arguments = listOf(navArgument("channelId") { type = NavType.StringType })
        ) { backStackEntry ->
            val channelId = backStackEntry.arguments?.getString("channelId") ?: return@composable
            ChatScreen(
                channelId = channelId,
                onBackPressed = { navController.popBackStack() }
            )
        }

        // Settings
        composable(Screen.Settings.route) {
            SettingsScreen(
                onNavigateBack = { navController.popBackStack() },
                onNavigateToOrganization = { navController.navigate(Screen.OrganizationSettings.route) }
            )
        }

        composable(Screen.OrganizationSettings.route) {
            OrganizationSettingsScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
    }
}

@Composable
fun MainScaffold(
    navController: NavHostController,
    currentScreen: Screen
) {
    Scaffold(
        bottomBar = {
            NavigationBar {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination

                bottomNavItems.forEach { item ->
                    NavigationBarItem(
                        icon = { Icon(item.icon, contentDescription = item.label) },
                        label = { Text(item.label) },
                        selected = currentDestination?.hierarchy?.any { it.route == item.screen.route } == true,
                        onClick = {
                            navController.navigate(item.screen.route) {
                                // Pop up to the start destination and save state
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                // Avoid multiple copies
                                launchSingleTop = true
                                // Restore state when reselecting
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        when (currentScreen) {
            Screen.Shifts -> ShiftListScreen(
                modifier = Modifier.padding(innerPadding),
                onNavigateToShiftDetail = { shiftId ->
                    navController.navigate(Screen.ShiftDetail.createRoute(shiftId))
                },
                onNavigateToCreateShift = {
                    navController.navigate(Screen.CreateShift.route)
                }
            )
            Screen.Sports -> SportsMainScreen(
                modifier = Modifier.padding(innerPadding),
                onNavigateToRosterImport = {
                    navController.navigate(Screen.RosterImport.route)
                },
                onNavigateToJobList = {
                    navController.navigate(Screen.SportsJobList.route)
                }
            )
            Screen.Chat -> ChatListScreen(
                onNavigateToChannel = { channelId ->
                    navController.navigate(Screen.ChatDetail.createRoute(channelId))
                }
            )
            Screen.Profile -> ProfileScreen(
                onNavigateToLogin = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(0) { inclusive = true }
                    }
                }
            )
            else -> {}
        }
    }
}
