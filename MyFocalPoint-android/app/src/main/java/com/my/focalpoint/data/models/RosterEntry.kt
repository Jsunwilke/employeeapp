package com.my.focalpoint.data.models

import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentId
import com.google.gson.annotations.SerializedName

data class RosterEntry(
    @SerializedName("firstName")
    val firstName: String = "",  // Subject ID (e.g., "101", "102")

    @SerializedName("lastName")
    val lastName: String = "",  // Player name (e.g., "Alice Smith")

    @SerializedName("graduationYear")
    val graduationYear: String = "",

    @SerializedName("grade")
    val grade: String = "",

    val photoUrl: String? = null,
    val timestamp: Timestamp = Timestamp.now()
)

data class SportsRoster(
    @DocumentId
    val id: String = "",
    val organizationId: String = "",
    val teamName: String = "",
    val season: String = "",
    val sport: String = "",
    val entries: List<RosterEntry> = emptyList(),
    val createdAt: Timestamp = Timestamp.now(),
    val createdBy: String = "",
    val lastModified: Timestamp = Timestamp.now()
)
