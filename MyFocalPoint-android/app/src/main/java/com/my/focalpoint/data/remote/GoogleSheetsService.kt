package com.my.focalpoint.data.remote

import android.content.Context
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.api.client.http.javanet.NetHttpTransport
import com.google.api.client.googleapis.auth.oauth2.GoogleCredential
import com.google.api.client.json.gson.GsonFactory
import com.google.api.services.sheets.v4.Sheets
import com.google.api.services.sheets.v4.SheetsScopes
import com.google.api.services.sheets.v4.model.ValueRange
import com.my.focalpoint.data.models.RosterEntry
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GoogleSheetsService @Inject constructor(
    @ApplicationContext private val context: Context
) {

    private val sheetsService: Sheets by lazy {
        val account = GoogleSignIn.getLastSignedInAccount(context)
        val credential = GoogleCredential().setAccessToken(account?.account?.name)

        Sheets.Builder(
            NetHttpTransport(),
            GsonFactory.getDefaultInstance(),
            credential
        )
            .setApplicationName("MyFocalPoint")
            .build()
    }

    suspend fun exportRosterToSheet(
        spreadsheetId: String,
        roster: List<RosterEntry>,
        sheetRange: String = "Sheet1!A1"
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            // Create header row
            val values: MutableList<MutableList<Any>> = mutableListOf(
                mutableListOf("Subject ID", "Name", "Graduation Year", "Grade")
            )

            // Add roster entries
            roster.forEach { entry ->
                values.add(mutableListOf(
                    entry.firstName,
                    entry.lastName,
                    entry.graduationYear,
                    entry.grade
                ))
            }

            val body = ValueRange().setValues(values as List<List<Any>>)

            sheetsService.spreadsheets().values()
                .update(spreadsheetId, sheetRange, body)
                .setValueInputOption("RAW")
                .execute()

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun createSpreadsheet(title: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val spreadsheet = com.google.api.services.sheets.v4.model.Spreadsheet()
                .setProperties(
                    com.google.api.services.sheets.v4.model.SpreadsheetProperties()
                        .setTitle(title)
                )

            val result = sheetsService.spreadsheets()
                .create(spreadsheet)
                .execute()

            Result.success(result.spreadsheetId)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
