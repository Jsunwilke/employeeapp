const admin = require('firebase-admin');
const { logger } = require('firebase-functions');

// Initialize messaging if not already initialized
const messaging = admin.messaging();
const db = admin.firestore();

// Constants for notification configuration
const MAX_RETRY_ATTEMPTS = 3;
const RETRY_DELAY_MS = 1000;
const BATCH_SIZE = 500; // FCM limit
const NOTIFICATION_TTL = 86400; // 24 hours in seconds

// Notification types enum
const NotificationType = {
    FLAG: 'flag',
    CHAT_MESSAGE: 'chat_message',
    SESSION_NEW: 'session_new',
    SESSION_UPDATE: 'session_update',
    CLOCK_REMINDER: 'clock_reminder',
    REPORT_REMINDER: 'report_reminder'
};

/**
 * Core notification service for sending push notifications
 */
class NotificationService {
    /**
     * Send a notification to a single user
     * @param {string} userId - The user ID to send to
     * @param {Object} notification - The notification payload
     * @param {string} notification.title - Notification title
     * @param {string} notification.body - Notification body
     * @param {Object} notification.data - Additional data payload
     * @param {string} notification.type - Notification type from NotificationType
     * @param {number} notification.badge - Badge count (optional)
     * @param {string} notification.sound - Sound file name (optional)
     * @returns {Promise<Object>} Result of the send operation
     */
    async sendToUser(userId, notification) {
        try {
            // Validate input
            if (!userId || !notification.title || !notification.body || !notification.type) {
                throw new Error('Missing required notification parameters');
            }

            // Get user's FCM token
            const userDoc = await db.collection('users').doc(userId).get();
            if (!userDoc.exists) {
                throw new Error(`User ${userId} not found`);
            }

            const userData = userDoc.data();
            const fcmToken = userData.fcmToken;

            if (!fcmToken) {
                logger.warn(`User ${userId} has no FCM token`);
                return { success: false, error: 'No FCM token' };
            }

            // Check user preferences
            const preferences = await this.getUserNotificationPreferences(userId);
            if (!preferences.enabled || !preferences.types[notification.type]) {
                logger.info(`Notifications disabled for user ${userId} type ${notification.type}`);
                return { success: false, error: 'Notifications disabled by user' };
            }

            // Check quiet hours
            if (this.isInQuietHours(preferences)) {
                logger.info(`Skipping notification for user ${userId} - quiet hours`);
                return { success: false, error: 'Quiet hours active' };
            }

            // Send the notification
            const result = await this.sendWithRetry(fcmToken, notification);

            // Log the notification
            await this.logNotification(userId, notification, result);

            return result;

        } catch (error) {
            logger.error('Error sending notification to user:', error);
            throw error;
        }
    }

    /**
     * Send notifications to multiple users
     * @param {string[]} userIds - Array of user IDs
     * @param {Object} notification - The notification payload
     * @returns {Promise<Object>} Results of the batch send
     */
    async sendToUsers(userIds, notification) {
        try {
            // Remove duplicates
            const uniqueUserIds = [...new Set(userIds)];
            
            // Get all user documents
            const userDocs = await db.collection('users')
                .where(admin.firestore.FieldPath.documentId(), 'in', uniqueUserIds)
                .get();

            // Extract tokens and preferences
            const tokenMap = new Map();
            const validTokens = [];

            for (const doc of userDocs.docs) {
                const userData = doc.data();
                const fcmToken = userData.fcmToken;
                
                if (fcmToken) {
                    const preferences = await this.getUserNotificationPreferences(doc.id);
                    if (preferences.enabled && preferences.types[notification.type] && !this.isInQuietHours(preferences)) {
                        tokenMap.set(fcmToken, doc.id);
                        validTokens.push(fcmToken);
                    }
                }
            }

            if (validTokens.length === 0) {
                return { success: true, results: [], message: 'No valid tokens found' };
            }

            // Send in batches
            const results = await this.sendInBatches(validTokens, notification, tokenMap);

            return {
                success: true,
                results,
                summary: {
                    requested: uniqueUserIds.length,
                    sent: results.filter(r => r.success).length,
                    failed: results.filter(r => !r.success).length
                }
            };

        } catch (error) {
            logger.error('Error sending notifications to users:', error);
            throw error;
        }
    }

    /**
     * Send notifications in batches to respect FCM limits
     */
    async sendInBatches(tokens, notification, tokenMap) {
        const results = [];
        
        for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
            const batch = tokens.slice(i, i + BATCH_SIZE);
            
            // Send individually instead of batch due to FCM batch endpoint issues
            const sendPromises = batch.map(async (token) => {
                const userId = tokenMap.get(token);
                const individualMessage = {
                    token: token,
                    notification: {
                        title: notification.title,
                        body: notification.body
                    },
                    data: {
                        ...notification.data,
                        type: notification.type,
                        timestamp: new Date().toISOString()
                    },
                    apns: {
                        payload: {
                            aps: {
                                alert: {
                                    title: notification.title,
                                    body: notification.body
                                },
                                badge: notification.badge || 0,
                                sound: notification.sound || 'default',
                                'content-available': 1
                            }
                        }
                    },
                    android: {
                        notification: {
                            sound: notification.sound || 'default',
                            priority: 'high'
                        },
                        ttl: NOTIFICATION_TTL * 1000
                    }
                };

                try {
                    const messageId = await messaging.send(individualMessage);
                    return { userId, success: true, messageId };
                } catch (error) {
                    // Handle invalid tokens
                    if (error.code === 'messaging/invalid-registration-token' ||
                        error.code === 'messaging/registration-token-not-registered') {
                        this.removeInvalidToken(userId).catch(err => 
                            logger.error(`Failed to remove invalid token for user ${userId}:`, err)
                        );
                    }
                    return { userId, success: false, error: error.message };
                }
            });

            // Wait for all individual sends to complete
            const batchResults = await Promise.all(sendPromises);
            results.push(...batchResults);

            // Log batch results
            const successCount = batchResults.filter(r => r.success).length;
            logger.info(`Batch processed: ${successCount} success, ${batchResults.length - successCount} failed`);
        }

        return results;
    }

    /**
     * Send notification with retry logic
     */
    async sendWithRetry(token, notification, attempt = 1) {
        try {
            const message = {
                token,
                notification: {
                    title: notification.title,
                    body: notification.body
                },
                data: {
                    ...notification.data,
                    type: notification.type,
                    timestamp: new Date().toISOString()
                },
                apns: {
                    payload: {
                        aps: {
                            alert: {
                                title: notification.title,
                                body: notification.body
                            },
                            badge: notification.badge || 0,
                            sound: notification.sound || 'default',
                            'content-available': 1
                        }
                    }
                },
                android: {
                    notification: {
                        sound: notification.sound || 'default',
                        priority: 'high'
                    }
                }
            };

            const messageId = await messaging.send(message);
            return { success: true, messageId };

        } catch (error) {
            if (attempt < MAX_RETRY_ATTEMPTS && this.isRetryableError(error)) {
                logger.warn(`Retrying notification send, attempt ${attempt + 1}/${MAX_RETRY_ATTEMPTS}`);
                await this.delay(RETRY_DELAY_MS * attempt); // Exponential backoff
                return this.sendWithRetry(token, notification, attempt + 1);
            }

            return { success: false, error: error.message };
        }
    }

    /**
     * Get user notification preferences with defaults
     */
    async getUserNotificationPreferences(userId) {
        try {
            const prefDoc = await db.collection('users').doc(userId)
                .collection('preferences').doc('notifications').get();

            if (prefDoc.exists) {
                return prefDoc.data();
            }

            // Return defaults if no preferences set
            return {
                enabled: true,
                types: {
                    [NotificationType.FLAG]: true,
                    [NotificationType.CHAT_MESSAGE]: true,
                    [NotificationType.SESSION_NEW]: true,
                    [NotificationType.SESSION_UPDATE]: true,
                    [NotificationType.CLOCK_REMINDER]: true,
                    [NotificationType.REPORT_REMINDER]: true
                },
                quietHours: {
                    enabled: false,
                    start: '22:00',
                    end: '07:00'
                },
                timezone: 'America/New_York'
            };

        } catch (error) {
            logger.error('Error getting user preferences:', error);
            // Return defaults on error
            return {
                enabled: true,
                types: Object.values(NotificationType).reduce((acc, type) => {
                    acc[type] = true;
                    return acc;
                }, {}),
                quietHours: { enabled: false }
            };
        }
    }

    /**
     * Check if current time is within user's quiet hours
     */
    isInQuietHours(preferences) {
        if (!preferences.quietHours?.enabled) {
            return false;
        }

        const now = new Date();
        const timezone = preferences.timezone || 'America/New_York';
        
        // Convert to user's timezone
        const userTime = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
        const currentHour = userTime.getHours();
        const currentMinute = userTime.getMinutes();
        const currentTimeMinutes = currentHour * 60 + currentMinute;

        // Parse quiet hours
        const [startHour, startMinute] = preferences.quietHours.start.split(':').map(Number);
        const [endHour, endMinute] = preferences.quietHours.end.split(':').map(Number);
        const startMinutes = startHour * 60 + startMinute;
        const endMinutes = endHour * 60 + endMinute;

        // Handle overnight quiet hours
        if (startMinutes > endMinutes) {
            return currentTimeMinutes >= startMinutes || currentTimeMinutes < endMinutes;
        } else {
            return currentTimeMinutes >= startMinutes && currentTimeMinutes < endMinutes;
        }
    }

    /**
     * Log notification for analytics and debugging
     */
    async logNotification(userId, notification, result) {
        try {
            await db.collection('notificationLogs').add({
                userId,
                type: notification.type,
                title: notification.title,
                body: notification.body,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
                success: result.success,
                error: result.error || null,
                messageId: result.messageId || null,
                metadata: notification.data || {}
            });
        } catch (error) {
            logger.error('Error logging notification:', error);
            // Don't throw - logging failure shouldn't stop notification
        }
    }

    /**
     * Remove invalid FCM token from user document
     */
    async removeInvalidToken(userId) {
        await db.collection('users').doc(userId).update({
            fcmToken: admin.firestore.FieldValue.delete()
        });
        logger.info(`Removed invalid FCM token for user ${userId}`);
    }

    /**
     * Check if error is retryable
     */
    isRetryableError(error) {
        const retryableCodes = [
            'messaging/internal-error',
            'messaging/server-unavailable',
            'messaging/too-many-requests'
        ];
        return retryableCodes.includes(error.code);
    }

    /**
     * Delay helper for retry logic
     */
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * Format notification for specific types
     */
    formatNotification(type, data) {
        switch (type) {
            case NotificationType.FLAG:
                return {
                    title: '⚠️ Account Flagged',
                    body: data.flagNote || 'Your account has been flagged. Please check the app for details.',
                    type: NotificationType.FLAG,
                    data: {
                        flaggedBy: data.flaggedBy,
                        flagNote: data.flagNote
                    }
                };

            case NotificationType.CHAT_MESSAGE:
                return {
                    title: data.senderName || 'New Message',
                    body: data.messageText?.substring(0, 100) || 'You have a new message',
                    type: NotificationType.CHAT_MESSAGE,
                    data: {
                        conversationId: data.conversationId,
                        senderId: data.senderId,
                        senderName: data.senderName
                    }
                };

            case NotificationType.SESSION_NEW:
                return {
                    title: 'New Session Added',
                    body: `New session at ${data.schoolName} on ${data.date}`,
                    type: NotificationType.SESSION_NEW,
                    data: {
                        sessionId: data.sessionId,
                        schoolName: data.schoolName,
                        date: data.date,
                        time: data.time
                    }
                };

            case NotificationType.SESSION_UPDATE:
                return {
                    title: 'Session Updated',
                    body: `${data.schoolName} session ${data.changeType}`,
                    type: NotificationType.SESSION_UPDATE,
                    data: {
                        sessionId: data.sessionId,
                        changeType: data.changeType,
                        schoolName: data.schoolName
                    }
                };

            case NotificationType.CLOCK_REMINDER:
                if (data.reminderType === 'clock_in') {
                    return {
                        title: 'Time to Leave',
                        body: `Leave now for your session at ${data.schoolName}`,
                        type: NotificationType.CLOCK_REMINDER,
                        sound: 'reminder.wav',
                        data: {
                            reminderType: 'clock_in',
                            sessionId: data.sessionId,
                            schoolName: data.schoolName
                        }
                    };
                } else {
                    return {
                        title: 'Clock Out Reminder',
                        body: 'Don\'t forget to clock out for today',
                        type: NotificationType.CLOCK_REMINDER,
                        sound: 'reminder.wav',
                        data: {
                            reminderType: 'clock_out'
                        }
                    };
                }

            case NotificationType.REPORT_REMINDER:
                return {
                    title: 'Daily Report Reminder',
                    body: 'Please fill out your daily job report',
                    type: NotificationType.REPORT_REMINDER,
                    data: {
                        date: data.date,
                        sessionsCount: data.sessionsCount
                    }
                };

            default:
                throw new Error(`Unknown notification type: ${type}`);
        }
    }
}

// Export singleton instance
module.exports = {
    notificationService: new NotificationService(),
    NotificationType
};