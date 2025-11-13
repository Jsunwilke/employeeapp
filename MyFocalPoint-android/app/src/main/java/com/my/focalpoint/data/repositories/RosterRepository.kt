package com.my.focalpoint.data.repositories

import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.my.focalpoint.data.models.SportsRoster
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RosterRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
    private val authRepository: AuthRepository
) {

    private val rostersCollection = firestore.collection("sports_rosters")

    fun getRostersForOrganization(orgId: String): Flow<List<SportsRoster>> = callbackFlow {
        val listener = rostersCollection
            .whereEqualTo("organizationId", orgId)
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }

                val rosters = snapshot?.documents?.mapNotNull { doc ->
                    doc.toObject(SportsRoster::class.java)?.copy(id = doc.id)
                } ?: emptyList()

                trySend(rosters)
            }

        awaitClose { listener.remove() }
    }

    suspend fun saveRoster(roster: SportsRoster): Result<String> {
        return try {
            val currentUser = authRepository.currentUser
                ?: return Result.failure(Exception("Not authenticated"))

            val rosterWithMetadata = roster.copy(
                createdBy = currentUser.uid,
                createdAt = Timestamp.now(),
                lastModified = Timestamp.now()
            )

            val docRef = rostersCollection.add(rosterWithMetadata).await()
            Result.success(docRef.id)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getRoster(rosterId: String): Result<SportsRoster> {
        return try {
            val doc = rostersCollection.document(rosterId).get().await()
            val roster = doc.toObject(SportsRoster::class.java)?.copy(id = doc.id)

            roster?.let {
                Result.success(it)
            } ?: Result.failure(Exception("Roster not found"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun updateRoster(roster: SportsRoster): Result<Unit> {
        return try {
            val updatedRoster = roster.copy(lastModified = Timestamp.now())
            rostersCollection.document(roster.id).set(updatedRoster).await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun deleteRoster(rosterId: String): Result<Unit> {
        return try {
            rostersCollection.document(rosterId).delete().await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
