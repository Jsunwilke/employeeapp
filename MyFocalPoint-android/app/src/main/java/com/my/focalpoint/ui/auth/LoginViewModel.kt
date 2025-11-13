package com.my.focalpoint.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.my.focalpoint.data.models.UserProfile
import com.my.focalpoint.data.repositories.AuthRepository
import com.my.focalpoint.domain.usecases.auth.SignInUseCase
import com.my.focalpoint.domain.usecases.auth.PasswordResetUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LoginUiState(
    val isLoading: Boolean = false,
    val isLoggedIn: Boolean = false,
    val userProfile: UserProfile? = null,
    val error: String? = null
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val signInUseCase: SignInUseCase,
    private val authRepository: AuthRepository,
    private val passwordResetUseCase: PasswordResetUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(LoginUiState())
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    init {
        checkAuthStatus()
    }

    private fun checkAuthStatus() {
        val currentUser = authRepository.currentUser
        _uiState.value = _uiState.value.copy(isLoggedIn = currentUser != null)
    }

    fun signInWithEmailPassword(email: String, password: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            // Basic validation
            if (email.isBlank() || password.isBlank()) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = "Email and password cannot be empty"
                )
                return@launch
            }

            val result = signInUseCase(email, password)

            _uiState.value = if (result.isSuccess) {
                LoginUiState(
                    isLoading = false,
                    isLoggedIn = true,
                    userProfile = result.getOrNull(),
                    error = null
                )
            } else {
                LoginUiState(
                    isLoading = false,
                    isLoggedIn = false,
                    userProfile = null,
                    error = result.exceptionOrNull()?.message
                )
            }
        }
    }

    fun sendPasswordReset(email: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            val result = passwordResetUseCase(email)

            _uiState.value = _uiState.value.copy(
                isLoading = false,
                error = if (result.isSuccess) {
                    "Password reset email sent. Check your inbox."
                } else {
                    result.exceptionOrNull()?.message
                }
            )
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }
}
