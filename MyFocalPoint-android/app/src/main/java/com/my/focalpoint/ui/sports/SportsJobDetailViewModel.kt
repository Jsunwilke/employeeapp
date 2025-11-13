package com.my.focalpoint.ui.sports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.my.focalpoint.data.models.SportsJob
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject

data class SportsJobDetailUiState(
    val isLoading: Boolean = false,
    val job: SportsJob? = null,
    val error: String? = null
)

@HiltViewModel
class SportsJobDetailViewModel @Inject constructor(
    private val firestore: FirebaseFirestore
) : ViewModel() {

    private val _uiState = MutableStateFlow(SportsJobDetailUiState())
    val uiState: StateFlow<SportsJobDetailUiState> = _uiState.asStateFlow()

    fun loadJob(jobId: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            try {
                val snapshot = firestore.collection("sports_jobs")
                    .document(jobId)
                    .get()
                    .await()

                val job = snapshot.toObject(SportsJob::class.java)?.copy(id = snapshot.id)

                if (job != null) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        job = job
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = "Job not found"
                    )
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load job"
                )
            }
        }
    }

    fun markAsComplete(jobId: String) {
        viewModelScope.launch {
            try {
                firestore.collection("sports_jobs")
                    .document(jobId)
                    .update(
                        mapOf(
                            "status" to "completed",
                            "completedAt" to Timestamp.now()
                        )
                    )
                    .await()

                // Reload the job to get updated state
                loadJob(jobId)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    error = e.message ?: "Failed to mark job as complete"
                )
            }
        }
    }
}
