# Push Notifications Implementation

## Overview

This document describes the push notification system implemented for the Iconik Employee app. The system uses Firebase Cloud Messaging (FCM) for iOS push notifications with a comprehensive backend infrastructure for various notification types.

## Notification Types

### 1. Flag Notifications
- **Trigger**: When a user is flagged by a manager
- **Recipients**: The flagged user
- **Payload**: Flag note and who flagged them
- **Function**: `sendFlagNotificationCallable`

### 2. Chat Notifications
- **Trigger**: When a new message is sent in a conversation
- **Recipients**: All conversation participants except the sender
- **Payload**: Message preview, sender name, conversation ID
- **Function**: `sendChatNotificationCallable`
- **Auto-triggered**: Yes, when messages are sent via ChatService

### 3. Session Notifications

#### New Session
- **Trigger**: When a new session is created
- **Recipients**: Only users assigned to the session
- **Payload**: Session details (school, date, time)
- **Function**: `sendSessionNotificationCallable` with type "new"

#### Session Updates
- **Trigger**: When session details change (time, location, notes, date)
- **Recipients**: Only users assigned to the session
- **Payload**: Change type and session details
- **Function**: `sendSessionNotificationCallable` with type "update"
- **Auto-triggered**: Yes, via `detectSessionChanges` Firestore trigger

### 4. Clock Reminders

#### Clock-In Reminder
- **Trigger**: Calculated leave time based on session start and travel time
- **Recipients**: Users assigned to upcoming sessions
- **Schedule**: Every 5 minutes checking sessions in next hour
- **Function**: `clockInReminder` (scheduled)

#### Clock-Out Reminder
- **Trigger**: 8:00 PM daily if still clocked in
- **Recipients**: Users with active clock-in status
- **Function**: `clockOutReminder` (scheduled)

### 5. Daily Report Reminder
- **Trigger**: 7:30 PM daily
- **Recipients**: Users who had sessions but haven't submitted daily report
- **Function**: `dailyReportReminder` (scheduled)

## Architecture

### Backend (Firebase Functions)

1. **Core Service** (`notificationService.js`)
   - Centralized notification handling
   - Token validation and management
   - Error handling with retry logic
   - User preference checking
   - Quiet hours support
   - Batch sending for efficiency

2. **Callable Functions**
   - `sendFlagNotificationCallable`
   - `sendChatNotificationCallable`
   - `sendSessionNotificationCallable`

3. **Scheduled Functions**
   - `clockInReminder` - Runs every 5 minutes
   - `clockOutReminder` - Runs at 8 PM daily
   - `dailyReportReminder` - Runs at 7:30 PM daily

4. **Firestore Triggers**
   - `detectSessionChanges` - Monitors session document changes

### iOS App

1. **PushNotificationManager.swift**
   - Handles all notification types
   - Routes notifications to appropriate handlers
   - Posts local notifications for UI updates

2. **FCM Token Management**
   - Token saved on app startup (RootView.swift)
   - Token refreshed automatically
   - Token saved to user document in Firestore

3. **Notification Handlers**
   - Flag notifications
   - Chat notifications
   - Session notifications (new and updates)
   - Clock reminders
   - Report reminders

## User Preferences

Users can control notifications through preferences stored at:
`users/{userId}/preferences/notifications`

Default structure:
```javascript
{
  enabled: true,
  types: {
    flag: true,
    chat_message: true,
    session_new: true,
    session_update: true,
    clock_reminder: true,
    report_reminder: true
  },
  quietHours: {
    enabled: false,
    start: "22:00",
    end: "07:00"
  },
  timezone: "America/New_York"
}
```

## Logging and Analytics

All notifications are logged to `notificationLogs` collection with:
- User ID
- Notification type
- Timestamp
- Success/failure status
- Error details (if failed)
- Metadata

## Security

- All callable functions require authentication
- Permission checks for flag notifications
- Organization boundaries respected
- No sensitive data in notification payloads

## Testing

To test notifications:

1. **Flag Notification**: Flag a user from the manager view
2. **Chat Notification**: Send a message in any conversation
3. **Session Notification**: Create or update a session
4. **Clock Reminder**: Wait for scheduled time or adjust clock
5. **Report Reminder**: Have sessions without reports at 7:30 PM

## Future Enhancements

1. Add UI for notification preferences
2. Implement notification analytics dashboard
3. Add email fallback for critical notifications
4. Support for web push notifications
5. Rich notifications with images
6. Quick actions from notifications

## Troubleshooting

1. **No FCM Token**: Check if user is signed in and token fetch is successful
2. **Notifications Not Received**: Verify user preferences and quiet hours
3. **Scheduled Functions**: Check Cloud Scheduler logs in Firebase Console
4. **Invalid Tokens**: Tokens are automatically removed on failure

## Deployment

1. Deploy Firebase Functions:
   ```bash
   firebase deploy --only functions
   ```

2. Ensure iOS app has push notification capability enabled

3. Configure APNs certificates in Firebase Console

4. Test in development before production deployment