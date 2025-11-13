package com.my.focalpoint.ui.sports

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.util.UUID
import javax.inject.Inject

data class MultiPhotoImportUiState(
    val isUploading: Boolean = false,
    val uploadProgress: Float = 0f,
    val isComplete: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class MultiPhotoImportViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val firestore: FirebaseFirestore,
    private val storage: FirebaseStorage
) : ViewModel() {

    private val _uiState = MutableStateFlow(MultiPhotoImportUiState())
    val uiState: StateFlow<MultiPhotoImportUiState> = _uiState.asStateFlow()

    private var selectedPhotos: List<Uri> = emptyList()

    fun setPhotos(photos: List<Uri>) {
        selectedPhotos = photos
    }

    fun uploadPhotos(jobId: String) {
        if (selectedPhotos.isEmpty()) {
            _uiState.value = _uiState.value.copy(error = "No photos selected")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isUploading = true,
                uploadProgress = 0f,
                error = null
            )

            try {
                val totalPhotos = selectedPhotos.size
                var uploadedCount = 0

                for (photoUri in selectedPhotos) {
                    // Upload to Firebase Storage
                    val fileName = "sports_photos/${jobId}/${UUID.randomUUID()}.jpg"
                    val storageRef = storage.reference.child(fileName)

                    val inputStream = context.contentResolver.openInputStream(photoUri)
                    if (inputStream != null) {
                        val uploadTask = storageRef.putStream(inputStream)
                        uploadTask.await()
                        inputStream.close()

                        val downloadUrl = storageRef.downloadUrl.await().toString()

                        // Create photo record in Firestore
                        val photoData = mapOf(
                            "jobId" to jobId,
                            "imageUrl" to downloadUrl,
                            "storagePath" to fileName,
                            "uploadedAt" to Timestamp.now(),
                            "status" to "pending",
                            "matchedRosterEntryId" to null
                        )

                        firestore.collection("sports_photos")
                            .add(photoData)
                            .await()

                        uploadedCount++
                        _uiState.value = _uiState.value.copy(
                            uploadProgress = uploadedCount.toFloat() / totalPhotos.toFloat()
                        )
                    }
                }

                // Update job with new photo count
                firestore.collection("sports_jobs")
                    .document(jobId)
                    .update("photoCount", FieldValue.increment(totalPhotos.toLong()))
                    .await()

                _uiState.value = _uiState.value.copy(
                    isUploading = false,
                    isComplete = true
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isUploading = false,
                    error = e.message ?: "Failed to upload photos"
                )
            }
        }
    }
}
