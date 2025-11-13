package com.my.focalpoint.domain.usecases.auth

import com.my.focalpoint.data.repositories.AuthRepository
import javax.inject.Inject

class PasswordResetUseCase @Inject constructor(
    private val authRepository: AuthRepository
) {
    suspend operator fun invoke(email: String): Result<Unit> {
        if (email.isBlank()) {
            return Result.failure(Exception("Email cannot be empty"))
        }
        return authRepository.sendPasswordResetEmail(email)
    }
}
