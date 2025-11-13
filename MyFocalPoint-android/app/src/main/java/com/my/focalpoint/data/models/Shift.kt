package com.my.focalpoint.data.models

import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentId
import com.google.firebase.firestore.GeoPoint

data class ShiftLocation(
    val address: String = "",
    val geoPoint: GeoPoint = GeoPoint(0.0, 0.0)
) {
    val latitude: Double get() = geoPoint.latitude
    val longitude: Double get() = geoPoint.longitude
}

data class Shift(
    @DocumentId
    val id: String = "",
    val organizationId: String = "",
    val title: String = "",
    val description: String = "",
    val startTime: Timestamp = Timestamp.now(),
    val endTime: Timestamp = Timestamp.now(),
    val location: ShiftLocation? = null,
    val assignedEmployees: List<String> = emptyList(),
    val createdBy: String = "",
    val createdAt: Timestamp = Timestamp.now()
)
