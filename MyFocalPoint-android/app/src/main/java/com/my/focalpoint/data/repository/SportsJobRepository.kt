package com.my.focalpoint.data.repository

import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.my.focalpoint.data.models.SportsJob
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SportsJobRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
    private val auth: FirebaseAuth
) {

    /**
     * Create a new sports job
     */
    suspend fun createJob(
        rosterId: String,
        jobType: String,
        notes: String = "",
        assignedUserId: String? = null,
        assignedPhotographer: String? = null
    ): Result<String> {
        return try {
            val currentUserId = auth.currentUser?.uid
                ?: return Result.failure(Exception("User not authenticated"))

            val jobData = hashMapOf(
                "rosterId" to rosterId,
                "jobType" to jobType,
                "notes" to notes,
                "status" to "pending",
                "assignedUserId" to (assignedUserId ?: currentUserId),
                "assignedPhotographer" to assignedPhotographer,
                "createdBy" to currentUserId,
                "createdAt" to Timestamp.now(),
                "photoCount" to 0,
                "completedPhotoCount" to 0,
                "completedAt" to null
            )

            val docRef = firestore.collection("sports_jobs")
                .add(jobData)
                .await()

            Result.success(docRef.id)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Get all jobs for the current user
     */
    suspend fun getJobsForCurrentUser(): Result<List<SportsJob>> {
        return try {
            val currentUserId = auth.currentUser?.uid
                ?: return Result.failure(Exception("User not authenticated"))

            val snapshot = firestore.collection("sports_jobs")
                .whereEqualTo("assignedUserId", currentUserId)
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .get()
                .await()

            val jobs = snapshot.documents.mapNotNull { doc ->
                doc.toObject(SportsJob::class.java)?.copy(id = doc.id)
            }

            Result.success(jobs)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Get a specific job by ID
     */
    suspend fun getJobById(jobId: String): Result<SportsJob> {
        return try {
            val snapshot = firestore.collection("sports_jobs")
                .document(jobId)
                .get()
                .await()

            val job = snapshot.toObject(SportsJob::class.java)?.copy(id = snapshot.id)
                ?: return Result.failure(Exception("Job not found"))

            Result.success(job)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Get all jobs for a specific roster
     */
    suspend fun getJobsForRoster(rosterId: String): Result<List<SportsJob>> {
        return try {
            val snapshot = firestore.collection("sports_jobs")
                .whereEqualTo("rosterId", rosterId)
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .get()
                .await()

            val jobs = snapshot.documents.mapNotNull { doc ->
                doc.toObject(SportsJob::class.java)?.copy(id = doc.id)
            }

            Result.success(jobs)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Update job status
     */
    suspend fun updateJobStatus(jobId: String, status: String): Result<Unit> {
        return try {
            val updates = hashMapOf<String, Any>(
                "status" to status
            )

            if (status == "completed") {
                updates["completedAt"] = Timestamp.now()
            }

            firestore.collection("sports_jobs")
                .document(jobId)
                .update(updates)
                .await()

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Update job photo counts
     */
    suspend fun updatePhotoCount(
        jobId: String,
        photoCount: Int,
        completedPhotoCount: Int
    ): Result<Unit> {
        return try {
            firestore.collection("sports_jobs")
                .document(jobId)
                .update(
                    mapOf(
                        "photoCount" to photoCount,
                        "completedPhotoCount" to completedPhotoCount
                    )
                )
                .await()

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Delete a job
     */
    suspend fun deleteJob(jobId: String): Result<Unit> {
        return try {
            firestore.collection("sports_jobs")
                .document(jobId)
                .delete()
                .await()

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Assign job to a photographer
     */
    suspend fun assignJobToPhotographer(
        jobId: String,
        userId: String,
        photographerName: String
    ): Result<Unit> {
        return try {
            firestore.collection("sports_jobs")
                .document(jobId)
                .update(
                    mapOf(
                        "assignedUserId" to userId,
                        "assignedPhotographer" to photographerName,
                        "status" to "in_progress"
                    )
                )
                .await()

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
