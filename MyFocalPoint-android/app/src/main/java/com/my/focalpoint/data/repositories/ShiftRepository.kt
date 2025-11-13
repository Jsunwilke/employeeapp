package com.my.focalpoint.data.repositories

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.my.focalpoint.data.models.Shift
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ShiftRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
    private val authRepository: AuthRepository
) {

    private val shiftsCollection = firestore.collection("shifts")

    fun getShiftsForOrganization(orgId: String): Flow<List<Shift>> = callbackFlow {
        val listener = shiftsCollection
            .whereEqualTo("organizationId", orgId)
            .orderBy("startTime", Query.Direction.DESCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }

                val shifts = snapshot?.documents?.mapNotNull { doc ->
                    doc.toObject(Shift::class.java)?.copy(id = doc.id)
                } ?: emptyList()

                trySend(shifts)
            }

        awaitClose { listener.remove() }
    }

    fun getShiftsForUser(userId: String): Flow<List<Shift>> = callbackFlow {
        val listener = shiftsCollection
            .whereArrayContains("assignedEmployees", userId)
            .orderBy("startTime", Query.Direction.DESCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }

                val shifts = snapshot?.documents?.mapNotNull { doc ->
                    doc.toObject(Shift::class.java)?.copy(id = doc.id)
                } ?: emptyList()

                trySend(shifts)
            }

        awaitClose { listener.remove() }
    }

    suspend fun createShift(shift: Shift): Result<String> {
        return try {
            val currentUser = authRepository.currentUser
                ?: return Result.failure(Exception("Not authenticated"))

            val shiftWithUser = shift.copy(createdBy = currentUser.uid)
            val docRef = shiftsCollection.add(shiftWithUser).await()
            Result.success(docRef.id)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getShift(shiftId: String): Result<Shift> {
        return try {
            val doc = shiftsCollection.document(shiftId).get().await()
            val shift = doc.toObject(Shift::class.java)?.copy(id = doc.id)
            shift?.let {
                Result.success(it)
            } ?: Result.failure(Exception("Shift not found"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun updateShift(shift: Shift): Result<Unit> {
        return try {
            shiftsCollection.document(shift.id).set(shift).await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun deleteShift(shiftId: String): Result<Unit> {
        return try {
            shiftsCollection.document(shiftId).delete().await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
