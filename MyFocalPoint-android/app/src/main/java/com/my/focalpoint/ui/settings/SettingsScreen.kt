package com.my.focalpoint.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateBack: () -> Unit,
    onNavigateToOrganization: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Account Section
            item {
                Text(
                    text = "Account",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(vertical = 8.dp)
                )
            }

            item {
                SettingsItem(
                    icon = Icons.Default.Person,
                    title = "Account Info",
                    subtitle = "Manage your account details",
                    onClick = { /* Navigate to account info */ }
                )
            }

            item {
                SettingsItem(
                    icon = Icons.Default.Photo,
                    title = "Upload Profile Photo",
                    subtitle = "Update your profile picture",
                    onClick = { /* Navigate to profile photo */ }
                )
            }

            // Organization Section
            item {
                Text(
                    text = "Organization",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
                )
            }

            item {
                SettingsItem(
                    icon = Icons.Default.Business,
                    title = "Organization Settings",
                    subtitle = "Manage organization details",
                    onClick = onNavigateToOrganization
                )
            }

            item {
                SettingsItem(
                    icon = Icons.Default.School,
                    title = "School Info",
                    subtitle = "View school information",
                    onClick = { /* Navigate to school info */ }
                )
            }

            // Time Off Section
            item {
                Text(
                    text = "Time Off",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
                )
            }

            item {
                SettingsItem(
                    icon = Icons.Default.Schedule,
                    title = "PTO Balance",
                    subtitle = "View your time off balance",
                    onClick = { /* Navigate to PTO balance */ }
                )
            }

            // App Section
            item {
                Text(
                    text = "App",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
                )
            }

            item {
                SettingsItem(
                    icon = Icons.Default.Settings,
                    title = "Quick Access Tab Bar",
                    subtitle = "Customize your tab bar",
                    onClick = { /* Navigate to tab bar config */ }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth()
    ) {
        ListItem(
            headlineContent = { Text(title) },
            supportingContent = { Text(subtitle) },
            leadingContent = {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            },
            trailingContent = {
                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = null
                )
            },
            modifier = Modifier.padding(vertical = 4.dp)
        )
    }
}
