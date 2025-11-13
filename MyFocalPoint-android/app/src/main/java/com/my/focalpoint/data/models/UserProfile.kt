package com.my.focalpoint.data.models

import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentId

data class UserProfile(
    @DocumentId
    val id: String = "",
    val email: String = "",
    val displayName: String = "",
    val organizationId: String = "",
    val role: String = "employee",
    val photoUrl: String? = null,
    val createdAt: Timestamp = Timestamp.now()
)
