package com.my.focalpoint.domain.usecases.auth

import com.google.firebase.Timestamp
import com.my.focalpoint.data.models.UserProfile
import com.my.focalpoint.data.repositories.AuthRepository
import com.my.focalpoint.data.repositories.UserRepository
import javax.inject.Inject

class SignInUseCase @Inject constructor(
    private val authRepository: AuthRepository,
    private val userRepository: UserRepository
) {

    suspend operator fun invoke(email: String, password: String): Result<UserProfile> {
        // Sign in with Firebase
        val signInResult = authRepository.signInWithEmailAndPassword(email, password)
        if (signInResult.isFailure) {
            return Result.failure(signInResult.exceptionOrNull()!!)
        }

        val firebaseUser = signInResult.getOrNull()!!

        // Get or create user profile
        val profileResult = userRepository.getCurrentUserProfile()

        return if (profileResult.isSuccess) {
            profileResult
        } else {
            // Create new user profile
            val newProfile = UserProfile(
                id = firebaseUser.uid,
                email = firebaseUser.email ?: "",
                displayName = firebaseUser.displayName ?: "",
                organizationId = "", // Will be set later
                role = "employee",
                photoUrl = firebaseUser.photoUrl?.toString(),
                createdAt = Timestamp.now()
            )

            userRepository.createOrUpdateUserProfile(newProfile)
            Result.success(newProfile)
        }
    }
}
