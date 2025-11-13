package com.my.focalpoint.ui.shifts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.my.focalpoint.data.models.Shift
import com.my.focalpoint.data.repositories.AuthRepository
import com.my.focalpoint.data.repositories.ShiftRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ShiftListUiState(
    val isLoading: Boolean = true,
    val shifts: List<Shift> = emptyList(),
    val error: String? = null
)

@HiltViewModel
class ShiftListViewModel @Inject constructor(
    private val shiftRepository: ShiftRepository,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(ShiftListUiState())
    val uiState: StateFlow<ShiftListUiState> = _uiState.asStateFlow()

    init {
        loadShifts()
    }

    private fun loadShifts() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)

            try {
                val userId = authRepository.currentUser?.uid
                    ?: throw Exception("No authenticated user")

                shiftRepository.getShiftsForUser(userId).collect { shifts ->
                    _uiState.value = ShiftListUiState(
                        isLoading = false,
                        shifts = shifts,
                        error = null
                    )
                }
            } catch (e: Exception) {
                _uiState.value = ShiftListUiState(
                    isLoading = false,
                    shifts = emptyList(),
                    error = e.message
                )
            }
        }
    }

    fun refreshShifts() {
        loadShifts()
    }
}
