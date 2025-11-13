package com.my.focalpoint.ui.sports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.firestore.FirebaseFirestore
import com.my.focalpoint.data.models.SportsRoster
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject

data class RosterDetailUiState(
    val isLoading: Boolean = false,
    val roster: SportsRoster? = null,
    val error: String? = null
)

@HiltViewModel
class RosterDetailViewModel @Inject constructor(
    private val firestore: FirebaseFirestore
) : ViewModel() {

    private val _uiState = MutableStateFlow(RosterDetailUiState())
    val uiState: StateFlow<RosterDetailUiState> = _uiState.asStateFlow()

    fun loadRoster(rosterId: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            try {
                val snapshot = firestore.collection("sports_rosters")
                    .document(rosterId)
                    .get()
                    .await()

                val roster = snapshot.toObject(SportsRoster::class.java)

                if (roster != null) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        roster = roster
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = "Roster not found"
                    )
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load roster"
                )
            }
        }
    }
}
