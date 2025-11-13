package com.my.focalpoint.ui.sports

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.my.focalpoint.ui.common.LoadingIndicator
import com.my.focalpoint.utils.DateUtils

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SportsJobDetailScreen(
    jobId: String,
    viewModel: SportsJobDetailViewModel = hiltViewModel(),
    onNavigateToMultiPhotoImport: () -> Unit,
    onNavigateBack: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(jobId) {
        viewModel.loadJob(jobId)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Job Details") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { padding ->
        when {
            uiState.isLoading -> {
                LoadingIndicator()
            }
            uiState.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = uiState.error ?: "Unknown error",
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
            uiState.job != null -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    // Job Status Card
                    Card(
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "Job Type",
                                    style = MaterialTheme.typography.titleMedium
                                )
                                JobStatusBadge(status = uiState.job?.status ?: "")
                            }

                            Text(
                                text = uiState.job?.jobType?.replaceFirstChar { it.uppercase() } ?: "",
                                style = MaterialTheme.typography.headlineMedium
                            )

                            Divider()

                            // Progress
                            Text(
                                text = "Photo Progress",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )

                            LinearProgressIndicator(
                                progress = if (uiState.job?.photoCount ?: 0 > 0) {
                                    (uiState.job?.completedPhotoCount?.toFloat() ?: 0f) /
                                    (uiState.job?.photoCount?.toFloat() ?: 1f)
                                } else 0f,
                                modifier = Modifier.fillMaxWidth()
                            )

                            Text(
                                text = "${uiState.job?.completedPhotoCount} of ${uiState.job?.photoCount} photos completed",
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }

                    // Details Card
                    Card(
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Text(
                                text = "Details",
                                style = MaterialTheme.typography.titleMedium
                            )

                            DetailRow(
                                label = "Created",
                                value = uiState.job?.createdAt?.let { DateUtils.formatDateTime(it) } ?: ""
                            )

                            uiState.job?.completedAt?.let { completedAt ->
                                DetailRow(
                                    label = "Completed",
                                    value = DateUtils.formatDateTime(completedAt)
                                )
                            }

                            uiState.job?.assignedPhotographer?.let { photographer ->
                                DetailRow(
                                    label = "Photographer",
                                    value = photographer
                                )
                            }

                            if (!uiState.job?.notes.isNullOrBlank()) {
                                Divider()
                                Text(
                                    text = "Notes",
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(
                                    text = uiState.job?.notes ?: "",
                                    style = MaterialTheme.typography.bodyMedium
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    // Action Buttons
                    if (uiState.job?.status != "completed") {
                        Button(
                            onClick = onNavigateToMultiPhotoImport,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Icon(Icons.Default.CloudUpload, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Import Photos")
                        }
                    }

                    if (uiState.job?.status == "in_progress") {
                        OutlinedButton(
                            onClick = { viewModel.markAsComplete(jobId) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Icon(Icons.Default.CheckCircle, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Mark as Complete")
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}
