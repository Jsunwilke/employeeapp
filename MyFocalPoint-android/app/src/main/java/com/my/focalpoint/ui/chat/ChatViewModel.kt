package com.my.focalpoint.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.my.focalpoint.data.repositories.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import io.getstream.chat.android.client.ChatClient
import io.getstream.chat.android.models.User
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ChatUiState(
    val isConnected: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class ChatViewModel @Inject constructor(
    private val chatClient: ChatClient,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    fun connectUser() {
        viewModelScope.launch {
            try {
                val firebaseUser = authRepository.currentUser
                    ?: throw Exception("No authenticated user")

                val user = User(
                    id = firebaseUser.uid,
                    name = firebaseUser.displayName ?: "",
                    image = firebaseUser.photoUrl?.toString() ?: ""
                )

                // In production, get this token from your backend
                val token = chatClient.devToken(user.id)

                chatClient.connectUser(user, token).await()

                _uiState.value = ChatUiState(isConnected = true)
            } catch (e: Exception) {
                _uiState.value = ChatUiState(
                    isConnected = false,
                    error = e.message
                )
            }
        }
    }

    fun disconnectUser() {
        viewModelScope.launch {
            chatClient.disconnect(flushPersistence = false).await()
            _uiState.value = ChatUiState(isConnected = false)
        }
    }
}
