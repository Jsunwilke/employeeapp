package com.my.focalpoint.data.repositories

import com.google.firebase.firestore.FirebaseFirestore
import com.my.focalpoint.data.models.UserProfile
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class UserRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
    private val authRepository: AuthRepository
) {

    private val usersCollection = firestore.collection("users")

    suspend fun getCurrentUserProfile(): Result<UserProfile> {
        return try {
            val currentUser = authRepository.currentUser
                ?: return Result.failure(Exception("No authenticated user"))

            val document = usersCollection.document(currentUser.uid).get().await()
            val profile = document.toObject(UserProfile::class.java)

            profile?.let {
                Result.success(it)
            } ?: Result.failure(Exception("User profile not found"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun createOrUpdateUserProfile(profile: UserProfile): Result<Unit> {
        return try {
            usersCollection.document(profile.id).set(profile).await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
