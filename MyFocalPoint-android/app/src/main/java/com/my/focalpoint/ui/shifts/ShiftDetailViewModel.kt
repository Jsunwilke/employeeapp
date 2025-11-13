package com.my.focalpoint.ui.shifts

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.my.focalpoint.data.models.Shift
import com.my.focalpoint.data.repositories.ShiftRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ShiftDetailUiState(
    val isLoading: Boolean = true,
    val shift: Shift? = null,
    val error: String? = null
)

@HiltViewModel
class ShiftDetailViewModel @Inject constructor(
    private val shiftRepository: ShiftRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(ShiftDetailUiState())
    val uiState: StateFlow<ShiftDetailUiState> = _uiState.asStateFlow()

    fun loadShift(shiftId: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)

            val result = shiftRepository.getShift(shiftId)

            _uiState.value = if (result.isSuccess) {
                ShiftDetailUiState(
                    isLoading = false,
                    shift = result.getOrNull(),
                    error = null
                )
            } else {
                ShiftDetailUiState(
                    isLoading = false,
                    shift = null,
                    error = result.exceptionOrNull()?.message
                )
            }
        }
    }
}
