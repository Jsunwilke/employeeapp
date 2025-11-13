package com.my.focalpoint.ui.sports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.my.focalpoint.data.models.SportsJob
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject

data class SportsJobListUiState(
    val isLoading: Boolean = false,
    val jobs: List<SportsJob> = emptyList(),
    val error: String? = null
)

@HiltViewModel
class SportsJobListViewModel @Inject constructor(
    private val firestore: FirebaseFirestore,
    private val auth: FirebaseAuth
) : ViewModel() {

    private val _uiState = MutableStateFlow(SportsJobListUiState())
    val uiState: StateFlow<SportsJobListUiState> = _uiState.asStateFlow()

    init {
        loadJobs()
    }

    private fun loadJobs() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            try {
                val currentUserId = auth.currentUser?.uid
                if (currentUserId == null) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = "User not authenticated"
                    )
                    return@launch
                }

                val snapshot = firestore.collection("sports_jobs")
                    .whereEqualTo("assignedUserId", currentUserId)
                    .orderBy("createdAt", Query.Direction.DESCENDING)
                    .get()
                    .await()

                val jobs = snapshot.documents.mapNotNull { doc ->
                    doc.toObject(SportsJob::class.java)?.copy(id = doc.id)
                }

                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    jobs = jobs
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load jobs"
                )
            }
        }
    }

    fun refresh() {
        loadJobs()
    }
}
