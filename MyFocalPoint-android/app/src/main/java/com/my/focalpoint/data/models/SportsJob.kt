package com.my.focalpoint.data.models

import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentId

data class SportsJob(
    @DocumentId
    val id: String = "",
    val rosterId: String = "",
    val organizationId: String = "",
    val jobType: String = "individual",  // "team" or "individual"
    val status: String = "pending",  // "pending", "in_progress", "completed"
    val assignedPhotographer: String? = null,  // User ID
    val photoCount: Int = 0,
    val completedPhotoCount: Int = 0,
    val createdAt: Timestamp = Timestamp.now(),
    val completedAt: Timestamp? = null,
    val notes: String = ""
)
