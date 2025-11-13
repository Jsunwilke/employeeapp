package com.my.focalpoint.ui.chat

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import io.getstream.chat.android.compose.ui.messages.MessagesScreen
import io.getstream.chat.android.compose.viewmodel.messages.MessagesViewModelFactory

@Composable
fun ChatScreen(
    channelId: String,
    onBackPressed: () -> Unit
) {
    val context = LocalContext.current

    MessagesScreen(
        viewModelFactory = MessagesViewModelFactory(
            context = context,
            channelId = channelId,
            messageLimit = 30
        ),
        onBackPressed = onBackPressed,
        onHeaderTitleClick = { /* Show channel info */ }
    )
}
