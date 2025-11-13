package com.my.focalpoint.ui.sports

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.my.focalpoint.data.models.RosterEntry
import com.my.focalpoint.data.models.SportsRoster
import com.my.focalpoint.data.repositories.RosterRepository
import com.my.focalpoint.domain.usecases.roster.ExtractRosterUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class RosterImportUiState(
    val isLoading: Boolean = false,
    val roster: List<RosterEntry> = emptyList(),
    val error: String? = null,
    val successMessage: String? = null
)

@HiltViewModel
class RosterImportViewModel @Inject constructor(
    private val extractRosterUseCase: ExtractRosterUseCase,
    private val rosterRepository: RosterRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(RosterImportUiState())
    val uiState: StateFlow<RosterImportUiState> = _uiState.asStateFlow()

    fun processImage(imageUri: Uri, startingSubjectId: Int = 101) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                error = null,
                successMessage = null
            )

            val result = extractRosterUseCase.extractFromImage(imageUri, startingSubjectId)

            _uiState.value = if (result.isSuccess) {
                RosterImportUiState(
                    isLoading = false,
                    roster = result.getOrNull() ?: emptyList(),
                    error = null
                )
            } else {
                RosterImportUiState(
                    isLoading = false,
                    roster = emptyList(),
                    error = "Failed to extract roster: ${result.exceptionOrNull()?.message}"
                )
            }
        }
    }

    fun processMultipleImages(imageUris: List<Uri>, startingSubjectId: Int = 101) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                error = null,
                successMessage = null
            )

            val result = extractRosterUseCase.extractFromImages(imageUris, startingSubjectId)

            _uiState.value = if (result.isSuccess) {
                RosterImportUiState(
                    isLoading = false,
                    roster = result.getOrNull() ?: emptyList(),
                    error = null
                )
            } else {
                RosterImportUiState(
                    isLoading = false,
                    roster = emptyList(),
                    error = "Failed to extract roster: ${result.exceptionOrNull()?.message}"
                )
            }
        }
    }

    fun saveRoster(
        teamName: String,
        season: String,
        sport: String,
        organizationId: String
    ) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            val roster = SportsRoster(
                organizationId = organizationId,
                teamName = teamName,
                season = season,
                sport = sport,
                entries = _uiState.value.roster
            )

            val result = rosterRepository.saveRoster(roster)

            _uiState.value = if (result.isSuccess) {
                _uiState.value.copy(
                    isLoading = false,
                    successMessage = "Roster saved successfully",
                    error = null
                )
            } else {
                _uiState.value.copy(
                    isLoading = false,
                    error = "Failed to save roster: ${result.exceptionOrNull()?.message}"
                )
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    fun clearSuccess() {
        _uiState.value = _uiState.value.copy(successMessage = null)
    }
}
