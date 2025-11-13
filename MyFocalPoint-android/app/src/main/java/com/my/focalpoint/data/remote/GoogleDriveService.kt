package com.my.focalpoint.data.remote

import android.content.Context
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.api.client.http.javanet.NetHttpTransport
import com.google.api.client.googleapis.auth.oauth2.GoogleCredential
import com.google.api.client.json.gson.GsonFactory
import com.google.api.services.drive.Drive
import com.google.api.services.drive.DriveScopes
import com.google.api.services.drive.model.File
import com.google.api.client.http.FileContent
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GoogleDriveService @Inject constructor(
    @ApplicationContext private val context: Context
) {

    private val driveService: Drive by lazy {
        val account = GoogleSignIn.getLastSignedInAccount(context)
        val credential = GoogleCredential().setAccessToken(account?.account?.name)

        Drive.Builder(
            NetHttpTransport(),
            GsonFactory.getDefaultInstance(),
            credential
        )
            .setApplicationName("MyFocalPoint")
            .build()
    }

    suspend fun uploadFile(
        file: java.io.File,
        mimeType: String,
        folderId: String? = null
    ): Result<String> = withContext(Dispatchers.IO) {
        try {
            val metadata = File().apply {
                name = file.name
                parents = folderId?.let { listOf(it) }
            }

            val mediaContent = FileContent(mimeType, file)

            val uploadedFile = driveService.files()
                .create(metadata, mediaContent)
                .setFields("id, webViewLink")
                .execute()

            Result.success(uploadedFile.id)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun createFolder(
        folderName: String,
        parentFolderId: String? = null
    ): Result<String> = withContext(Dispatchers.IO) {
        try {
            val metadata = File().apply {
                name = folderName
                mimeType = "application/vnd.google-apps.folder"
                parents = parentFolderId?.let { listOf(it) }
            }

            val folder = driveService.files()
                .create(metadata)
                .setFields("id")
                .execute()

            Result.success(folder.id)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
