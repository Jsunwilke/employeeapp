const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest, onCall } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions/logger');
const admin = require('firebase-admin');
const axios = require('axios');

// Initialize admin (only once)
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

// Import notification service
const { notificationService, NotificationType } = require('./notificationService');

// Import Captura stats functions
const capturaStats = require('./capturaStats');

// Import proofing email service
const proofingEmailService = require('./proofingEmailService');

// Function 1: Update Player Search Index when sports jobs change
exports.updatePlayerSearchIndex = onDocumentWritten('sportsJobs/{jobId}', async (event) => {
    const change = event.data;
    const jobId = event.params.jobId;
    const playerSearchIndexCollection = db.collection('playerSearchIndex');
    
    try {
        // Handle deletion
        if (!change.after) {
            console.log(`Job ${jobId} deleted, removing from search index`);
            
            // Delete all player index entries for this job
            const batch = db.batch();
            const oldIndexDocs = await playerSearchIndexCollection
                .where('jobId', '==', jobId)
                .get();
            
            oldIndexDocs.forEach(doc => {
                batch.delete(doc.ref);
            });
            
            await batch.commit();
            console.log(`Deleted ${oldIndexDocs.size} index entries for job ${jobId}`);
            return null;
        }
        
        // Get the job data
        const jobData = change.after.data();
        const roster = jobData.roster || [];
        
        // Prepare batch for efficient writes
        const batch = db.batch();
        
        // First, delete all existing index entries for this job
        // This handles cases where players are removed from the roster
        const existingIndexDocs = await playerSearchIndexCollection
            .where('jobId', '==', jobId)
            .get();
        
        existingIndexDocs.forEach(doc => {
            batch.delete(doc.ref);
        });
        
        // Create index entries for each player in the roster
        roster.forEach((player, index) => {
            // Skip players without last names (invalid entries)
            if (!player.lastName || !player.lastName.trim()) {
                return;
            }
            
            // Generate a unique ID for this player index entry
            const indexId = `${jobId}_${player.id || index}`;
            const indexRef = playerSearchIndexCollection.doc(indexId);
            
            // Create lowercase versions for case-insensitive search
            const searchableData = {
                // Player data
                playerId: player.id || `${jobId}_${index}`,
                firstName: player.firstName || '',
                lastName: player.lastName || '',
                fullName: `${player.firstName || ''} ${player.lastName || ''}`.trim(),
                teacher: player.teacher || '',
                group: player.group || '',
                email: player.email || '',
                phone: player.phone || '',
                imageNumbers: player.imageNumbers || '',
                notes: player.notes || '',
                
                // Lowercase search fields
                firstNameLower: (player.firstName || '').toLowerCase(),
                lastNameLower: (player.lastName || '').toLowerCase(),
                fullNameLower: `${player.firstName || ''} ${player.lastName || ''}`.toLowerCase().trim(),
                teacherLower: (player.teacher || '').toLowerCase(),
                groupLower: (player.group || '').toLowerCase(),
                emailLower: (player.email || '').toLowerCase(),
                
                // Job reference data
                jobId: jobId,
                schoolName: jobData.schoolName || '',
                schoolNameLower: (jobData.schoolName || '').toLowerCase(),
                sportName: jobData.sportName || '',
                sportNameLower: (jobData.sportName || '').toLowerCase(),
                seasonType: jobData.seasonType || '',
                seasonTypeLower: (jobData.seasonType || '').toLowerCase(),
                shootDate: jobData.shootDate || null,
                isArchived: jobData.isArchived || false,
                organizationID: jobData.organizationID || '',
                
                // Metadata
                indexedAt: admin.firestore.FieldValue.serverTimestamp(),
                playerIndex: index
            };
            
            batch.set(indexRef, searchableData);
        });
        
        // Commit all changes
        await batch.commit();
        
        console.log(`Updated search index for job ${jobId} with ${roster.filter(p => p.lastName && p.lastName.trim()).length} valid players`);
        return null;
        
    } catch (error) {
        console.error(`Error updating search index for job ${jobId}:`, error);
        throw error;
    }
});

// Function 2: Clean up orphaned index entries daily
exports.cleanupPlayerSearchIndex = onSchedule('every 24 hours', async (event) => {
    const playerSearchIndexCollection = db.collection('playerSearchIndex');
    const sportsJobsCollection = db.collection('sportsJobs');
    
    let deletedCount = 0;
    let batchCount = 0;
    
    try {
        // Get all index entries in batches to avoid memory issues
        let lastDoc = null;
        const batchSize = 1000;
        
        while (true) {
            let query = playerSearchIndexCollection
                .orderBy('indexedAt')
                .limit(batchSize);
            
            if (lastDoc) {
                query = query.startAfter(lastDoc);
            }
            
            const indexSnapshot = await query.get();
            
            if (indexSnapshot.empty) {
                break;
            }
            
            const batch = db.batch();
            
            for (const indexDoc of indexSnapshot.docs) {
                const indexData = indexDoc.data();
                
                // Check if the parent job still exists
                const jobDoc = await sportsJobsCollection.doc(indexData.jobId).get();
                
                if (!jobDoc.exists) {
                    batch.delete(indexDoc.ref);
                    batchCount++;
                    deletedCount++;
                    
                    // Firestore batch limit is 500
                    if (batchCount === 500) {
                        await batch.commit();
                        batchCount = 0;
                    }
                }
            }
            
            // Commit any remaining deletes
            if (batchCount > 0) {
                await batch.commit();
                batchCount = 0;
            }
            
            lastDoc = indexSnapshot.docs[indexSnapshot.docs.length - 1];
        }
        
        console.log(`Cleanup completed. Deleted ${deletedCount} orphaned index entries.`);
        return null;
        
    } catch (error) {
        console.error('Error during cleanup:', error);
        throw error;
    }
});

// Function 3: Rebuild entire search index (for maintenance)
exports.rebuildPlayerSearchIndex = onRequest(async (req, res) => {
    // Add authentication check
    const authToken = req.headers.authorization;
    const expectedToken = process.env.REBUILD_TOKEN || 'iconik-rebuild-secret-token-2024';
    
    if (authToken !== `Bearer ${expectedToken}`) {
        res.status(403).send('Unauthorized');
        return;
    }
    
    // Only allow POST requests
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    
    const sportsJobsCollection = db.collection('sportsJobs');
    const playerSearchIndexCollection = db.collection('playerSearchIndex');
    
    try {
        console.log('Starting search index rebuild...');
        
        // First, clear the entire index in batches
        let deletedCount = 0;
        while (true) {
            const existingIndex = await playerSearchIndexCollection.limit(500).get();
            if (existingIndex.empty) break;
            
            const batch = db.batch();
            existingIndex.docs.forEach(doc => {
                batch.delete(doc.ref);
                deletedCount++;
            });
            await batch.commit();
        }
        
        console.log(`Deleted ${deletedCount} existing index entries`);
        
        // Get all sports jobs
        const jobsSnapshot = await sportsJobsCollection.get();
        let totalIndexed = 0;
        
        // Process in batches to avoid timeout
        const batchSize = 50;
        const jobs = jobsSnapshot.docs;
        
        for (let i = 0; i < jobs.length; i += batchSize) {
            const batch = db.batch();
            const jobBatch = jobs.slice(i, i + batchSize);
            
            for (const jobDoc of jobBatch) {
                const jobData = jobDoc.data();
                const jobId = jobDoc.id;
                const roster = jobData.roster || [];
                
                roster.forEach((player, index) => {
                    // Skip players without last names (invalid entries)
                    if (!player.lastName || !player.lastName.trim()) {
                        return;
                    }
                    
                    const indexId = `${jobId}_${player.id || index}`;
                    const indexRef = playerSearchIndexCollection.doc(indexId);
                    
                    const searchableData = {
                        // Player data
                        playerId: player.id || `${jobId}_${index}`,
                        firstName: player.firstName || '',
                        lastName: player.lastName || '',
                        fullName: `${player.firstName || ''} ${player.lastName || ''}`.trim(),
                        teacher: player.teacher || '',
                        group: player.group || '',
                        email: player.email || '',
                        phone: player.phone || '',
                        imageNumbers: player.imageNumbers || '',
                        notes: player.notes || '',
                        
                        // Lowercase search fields
                        firstNameLower: (player.firstName || '').toLowerCase(),
                        lastNameLower: (player.lastName || '').toLowerCase(),
                        fullNameLower: `${player.firstName || ''} ${player.lastName || ''}`.toLowerCase().trim(),
                        teacherLower: (player.teacher || '').toLowerCase(),
                        groupLower: (player.group || '').toLowerCase(),
                        emailLower: (player.email || '').toLowerCase(),
                        
                        // Job reference data
                        jobId: jobId,
                        schoolName: jobData.schoolName || '',
                        schoolNameLower: (jobData.schoolName || '').toLowerCase(),
                        sportName: jobData.sportName || '',
                        sportNameLower: (jobData.sportName || '').toLowerCase(),
                        seasonType: jobData.seasonType || '',
                        seasonTypeLower: (jobData.seasonType || '').toLowerCase(),
                        shootDate: jobData.shootDate || null,
                        isArchived: jobData.isArchived || false,
                        organizationID: jobData.organizationID || '',
                        
                        // Metadata
                        indexedAt: admin.firestore.FieldValue.serverTimestamp(),
                        playerIndex: index
                    };
                    
                    batch.set(indexRef, searchableData);
                    totalIndexed++;
                });
            }
            
            await batch.commit();
            console.log(`Processed ${Math.min(i + batchSize, jobs.length)} of ${jobs.length} jobs`);
        }
        
        res.status(200).json({
            success: true,
            message: `Successfully rebuilt search index with ${totalIndexed} player entries from ${jobs.length} jobs`,
            stats: {
                jobsProcessed: jobs.length,
                playersIndexed: totalIndexed,
                deletedEntries: deletedCount
            }
        });
        
    } catch (error) {
        console.error('Error rebuilding search index:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Function 4: Get search index statistics (for monitoring)
exports.getSearchIndexStats = onRequest(async (req, res) => {
    try {
        const playerSearchIndexCollection = db.collection('playerSearchIndex');
        const sportsJobsCollection = db.collection('sportsJobs');
        
        // Get total index entries
        const indexSnapshot = await playerSearchIndexCollection.count().get();
        const totalIndexEntries = indexSnapshot.data().count;
        
        // Get total jobs
        const jobsSnapshot = await sportsJobsCollection.count().get();
        const totalJobs = jobsSnapshot.data().count;
        
        // Get breakdown by organization
        const orgBreakdown = {};
        const orgQuery = await playerSearchIndexCollection
            .select('organizationID')
            .get();
        
        orgQuery.docs.forEach(doc => {
            const orgId = doc.data().organizationID;
            orgBreakdown[orgId] = (orgBreakdown[orgId] || 0) + 1;
        });
        
        res.status(200).json({
            totalIndexEntries,
            totalJobs,
            organizationBreakdown: orgBreakdown,
            lastUpdated: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('Error getting search index stats:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Function 5: Automatic PTO Processing (runs daily at midnight)
exports.processAutomaticPTO = onSchedule('0 0 * * *', async (event) => {
    console.log('Starting automatic PTO processing...');
    
    const organizationsCollection = db.collection('organizations');
    const timeEntriesCollection = db.collection('timeEntries');
    const ptoBalancesCollection = db.collection('ptoBalances');
    
    let processedOrganizations = 0;
    let processedUsers = 0;
    let totalPTOHoursAdded = 0;
    
    try {
        const today = new Date();
        const todayStr = formatDateUTC(today);
        
        // Get all organizations with active PTO settings
        const orgsSnapshot = await organizationsCollection
            .where('ptoSettings.enabled', '==', true)
            .get();
        
        console.log(`Found ${orgsSnapshot.size} organizations with PTO enabled`);
        
        for (const orgDoc of orgsSnapshot.docs) {
            const orgData = orgDoc.data();
            const orgId = orgDoc.id;
            const ptoSettings = orgData.ptoSettings;
            const payPeriodSettings = orgData.payPeriodSettings;
            
            // Skip if no pay period settings configured
            if (!payPeriodSettings || !payPeriodSettings.isActive) {
                console.log(`Skipping org ${orgId}: No active pay period settings`);
                continue;
            }
            
            try {
                // Check if any pay period ended today
                const currentPeriod = getCurrentPayPeriod(payPeriodSettings, today);
                
                if (!currentPeriod || currentPeriod.end !== todayStr) {
                    console.log(`Skipping org ${orgId}: No pay period ending today`);
                    continue;
                }
                
                console.log(`Processing org ${orgId}: Pay period ${currentPeriod.label} ended today`);
                
                // Get all active users in the organization
                const usersSnapshot = await db.collection('users')
                    .where('organizationID', '==', orgId)
                    .where('isActive', '==', true)
                    .get();
                
                console.log(`Found ${usersSnapshot.size} active users in org ${orgId}`);
                
                // Process each user
                for (const userDoc of usersSnapshot.docs) {
                    const userId = userDoc.id;
                    
                    try {
                        const ptoHoursAdded = await processPTOForUser(
                            userId, 
                            orgId, 
                            currentPeriod, 
                            ptoSettings,
                            timeEntriesCollection,
                            ptoBalancesCollection
                        );
                        
                        if (ptoHoursAdded > 0) {
                            processedUsers++;
                            totalPTOHoursAdded += ptoHoursAdded;
                            console.log(`Added ${ptoHoursAdded} PTO hours for user ${userId}`);
                        }
                        
                    } catch (userError) {
                        console.error(`Error processing PTO for user ${userId}:`, userError);
                        // Continue processing other users
                    }
                }
                
                processedOrganizations++;
                console.log(`Completed processing org ${orgId}`);
                
            } catch (orgError) {
                console.error(`Error processing org ${orgId}:`, orgError);
                // Continue processing other organizations
            }
        }
        
        console.log(`Automatic PTO processing completed:`, {
            processedOrganizations,
            processedUsers,
            totalPTOHoursAdded
        });
        
        return null;
        
    } catch (error) {
        console.error('Error during automatic PTO processing:', error);
        throw error;
    }
});

/**
 * Process PTO for a single user in a pay period
 */
async function processPTOForUser(userId, orgId, payPeriod, ptoSettings, timeEntriesCollection, ptoBalancesCollection) {
    // Get or create PTO balance document
    const balanceId = `${orgId}_${userId}`;
    const balanceRef = ptoBalancesCollection.doc(balanceId);
    const balanceDoc = await balanceRef.get();
    
    let currentBalance;
    let processedPeriods = [];
    
    if (!balanceDoc.exists) {
        // Create initial balance
        currentBalance = {
            userId,
            organizationID: orgId,
            totalBalance: 0,
            usedThisYear: 0,
            pendingBalance: 0,
            bankingBalance: 0,
            processedPeriods: [],
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        };
    } else {
        currentBalance = balanceDoc.data();
        processedPeriods = currentBalance.processedPeriods || [];
        // Ensure bankingBalance exists for existing documents (backwards compatibility)
        if (typeof currentBalance.bankingBalance === 'undefined' || currentBalance.bankingBalance === null) {
            currentBalance.bankingBalance = 0;
        }
        // Ensure totalBalance exists and is not NaN
        if (typeof currentBalance.totalBalance === 'undefined' || currentBalance.totalBalance === null || isNaN(currentBalance.totalBalance)) {
            currentBalance.totalBalance = 0;
        }
    }
    
    // Check if this pay period was already processed
    const periodId = `${payPeriod.start}_${payPeriod.end}`;
    const alreadyProcessed = processedPeriods.some(p => 
        p.startDate === payPeriod.start && p.endDate === payPeriod.end
    );
    
    if (alreadyProcessed) {
        console.log(`Pay period ${periodId} already processed for user ${userId}`);
        return 0;
    }
    
    // Get time entries for this user in the pay period
    console.log(`Searching for time entries: userId=${userId}, orgId=${orgId}, dates=${payPeriod.start} to ${payPeriod.end}`);
    
    const timeEntriesSnapshot = await timeEntriesCollection
        .where('userId', '==', userId)
        .where('organizationID', '==', orgId)
        .where('date', '>=', payPeriod.start)
        .where('date', '<=', payPeriod.end)
        .where('status', '==', 'clocked-out')
        .get();
    
    console.log(`Found ${timeEntriesSnapshot.size} time entries for user ${userId}`);
    
    // Calculate total hours worked in this period
    let totalHoursWorked = 0;
    timeEntriesSnapshot.docs.forEach(doc => {
        const entry = doc.data();
        console.log(`Time entry: date=${entry.date}, status=${entry.status}, duration=${entry.duration}, clockIn=${entry.clockInTime}, clockOut=${entry.clockOutTime}`);
        
        let durationSeconds = entry.duration;
        
        // If duration is missing but we have clock times, calculate it
        if ((!durationSeconds || durationSeconds <= 0) && entry.clockInTime && entry.clockOutTime) {
            let clockIn, clockOut;
            
            // Handle Firestore Timestamp objects vs regular dates/strings
            if (entry.clockInTime && typeof entry.clockInTime.toDate === 'function') {
                clockIn = entry.clockInTime.toDate();
            } else if (entry.clockInTime) {
                clockIn = new Date(entry.clockInTime);
            }
            
            if (entry.clockOutTime && typeof entry.clockOutTime.toDate === 'function') {
                clockOut = entry.clockOutTime.toDate();
            } else if (entry.clockOutTime) {
                clockOut = new Date(entry.clockOutTime);
            }
            
            // Validate dates before calculation
            if (clockIn && clockOut && !isNaN(clockIn.getTime()) && !isNaN(clockOut.getTime()) && clockOut > clockIn) {
                durationSeconds = (clockOut.getTime() - clockIn.getTime()) / 1000; // Convert to seconds
                console.log(`Calculated duration: ${durationSeconds} seconds (${durationSeconds/3600} hours)`);
            } else {
                console.log(`Invalid clock times for entry: clockIn=${entry.clockInTime}, clockOut=${entry.clockOutTime}`);
                durationSeconds = 0;
            }
        }
        
        if (durationSeconds && durationSeconds > 0) {
            totalHoursWorked += durationSeconds / 3600; // Convert seconds to hours
        }
    });
    
    // Calculate PTO using cumulative hour banking
    const { accrualRate = 1, accrualPeriod = 40, maxAccrual = 240 } = ptoSettings;
    
    // Ensure we have valid numbers for calculation
    const currentBankingBalance = currentBalance.bankingBalance || 0;
    const currentPTOBalance = currentBalance.totalBalance || 0;
    
    // Add current period hours to banking balance
    const newBankingBalance = currentBankingBalance + totalHoursWorked;
    
    // Calculate PTO earned from total banking balance
    const ptoEarned = Math.floor(newBankingBalance / accrualPeriod) * accrualRate;
    
    // Calculate remaining banking balance after PTO conversion
    const remainingBankingBalance = newBankingBalance % accrualPeriod;
    
    // Calculate new total PTO balance (respect max accrual)
    const newTotalBalance = Math.min(currentPTOBalance + ptoEarned, maxAccrual);
    const actualPTOAdded = newTotalBalance - currentPTOBalance;
    
    console.log(`Banking calculation for user ${userId}:`);
    console.log(`  Previous banking: ${currentBankingBalance} hours`);
    console.log(`  Current period: ${totalHoursWorked} hours`);
    console.log(`  New banking total: ${newBankingBalance} hours`);
    console.log(`  PTO earned: ${ptoEarned} hours`);
    console.log(`  Remaining banking: ${remainingBankingBalance} hours`);
    console.log(`  Previous PTO balance: ${currentPTOBalance} hours`);
    console.log(`  New PTO balance: ${newTotalBalance} hours`);
    console.log(`  PTO added to balance: ${actualPTOAdded} hours`);
    
    if (actualPTOAdded <= 0 && totalHoursWorked <= 0) {
        console.log(`No hours worked for user ${userId}: ${totalHoursWorked} hours`);
        return 0;
    }
    
    // Add processed period to history
    const newProcessedPeriod = {
        startDate: payPeriod.start,
        endDate: payPeriod.end,
        label: payPeriod.label,
        hoursWorked: totalHoursWorked,
        ptoEarned: actualPTOAdded,
        bankingBalance: remainingBankingBalance,
        processedAt: new Date()
    };
    
    const updatedProcessedPeriods = [...processedPeriods, newProcessedPeriod];
    
    // Update balance document
    const updatedBalance = {
        ...currentBalance,
        totalBalance: newTotalBalance,
        bankingBalance: remainingBankingBalance,
        processedPeriods: updatedProcessedPeriods,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    };
    
    await balanceRef.set(updatedBalance);
    
    console.log(`User ${userId}: ${totalHoursWorked} hours worked → ${actualPTOAdded} PTO hours added (new balance: ${newTotalBalance}, banking: ${remainingBankingBalance})`);
    
    return actualPTOAdded;
}

/**
 * Get current pay period for a given date
 */
function getCurrentPayPeriod(payPeriodSettings, targetDate = new Date()) {
    if (!payPeriodSettings || !payPeriodSettings.isActive) {
        return null;
    }
    
    const { type, config } = payPeriodSettings;
    const today = formatDateUTC(targetDate);
    
    // Get a range around the target date to find the period
    const rangeStart = new Date(targetDate);
    rangeStart.setDate(rangeStart.getDate() - 35);
    const rangeEnd = new Date(targetDate);
    rangeEnd.setDate(rangeEnd.getDate() + 35);
    
    const periods = calculatePayPeriodBoundaries(
        formatDateUTC(rangeStart),
        formatDateUTC(rangeEnd),
        payPeriodSettings
    );
    
    // Find the period that includes the target date
    return periods.find(period => period.start <= today && period.end >= today) || null;
}

/**
 * Calculate pay period boundaries (simplified version for Cloud Functions)
 */
function calculatePayPeriodBoundaries(startDate, endDate, payPeriodSettings) {
    const { type, config } = payPeriodSettings;
    const periods = [];
    
    // Ensure dates are properly parsed
    const start = typeof startDate === 'string' ? new Date(startDate) : new Date(startDate);
    const end = typeof endDate === 'string' ? new Date(endDate) : new Date(endDate);
    
    // Validate dates
    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
        throw new Error(`Invalid dates in calculatePayPeriodBoundaries: start=${startDate}, end=${endDate}`);
    }
    
    switch (type) {
        case 'weekly':
            generateWeeklyPeriods(start, end, config, periods);
            break;
        case 'bi-weekly':
            generateBiWeeklyPeriods(start, end, config, periods);
            break;
        case 'semi-monthly':
            generateSemiMonthlyPeriods(start, end, config, periods);
            break;
        case 'monthly':
            generateMonthlyPeriods(start, end, config, periods);
            break;
    }
    
    return periods;
}

/**
 * Generate weekly pay periods (simplified)
 */
function generateWeeklyPeriods(start, end, config, periods) {
    let current = getWeekStart(start, config.dayOfWeek || 1);
    
    while (current <= end) {
        const periodEnd = new Date(current);
        periodEnd.setDate(periodEnd.getDate() + 6);
        periodEnd.setHours(23, 59, 59, 999);

        periods.push({
            start: formatDateUTC(current),
            end: formatDateUTC(periodEnd),
            label: `Week of ${formatDateForLabel(current)}`
        });

        current.setDate(current.getDate() + 7);
    }
}

/**
 * Generate bi-weekly pay periods (simplified)
 */
function generateBiWeeklyPeriods(start, end, config, periods) {
    // Ensure reference date is properly parsed
    const referenceDate = typeof config.startDate === 'string' ? new Date(config.startDate) : new Date(config.startDate);
    
    // Validate reference date
    if (isNaN(referenceDate.getTime())) {
        throw new Error(`Invalid reference date in bi-weekly config: ${config.startDate}`);
    }
    
    const daysDiff = Math.floor((start.getTime() - referenceDate.getTime()) / (1000 * 60 * 60 * 24));
    const periodNumber = Math.floor(daysDiff / 14);
    
    let current = new Date(referenceDate);
    current.setDate(current.getDate() + (periodNumber * 14));
    
    if (current > start) {
        current.setDate(current.getDate() - 14);
    }
    
    while (current <= end) {
        const periodEnd = new Date(current);
        periodEnd.setDate(periodEnd.getDate() + 13);
        periodEnd.setHours(23, 59, 59, 999);

        if (periodEnd >= start) {
            periods.push({
                start: formatDateUTC(current),
                end: formatDateUTC(periodEnd),
                label: `${formatDateForLabel(current)} - ${formatDateForLabel(periodEnd)}`
            });
        }

        current.setDate(current.getDate() + 14);
    }
}

/**
 * Generate semi-monthly pay periods (simplified)
 */
function generateSemiMonthlyPeriods(start, end, config, periods) {
    const startYear = start.getFullYear();
    const startMonth = start.getMonth();
    const endYear = end.getFullYear();
    const endMonth = end.getMonth();

    for (let year = startYear; year <= endYear; year++) {
        const monthStart = year === startYear ? startMonth : 0;
        const monthEnd = year === endYear ? endMonth : 11;

        for (let month = monthStart; month <= monthEnd; month++) {
            // First period
            const firstStart = new Date(year, month, config.firstDate || 1);
            const firstEnd = new Date(year, month, (config.secondDate || 15) - 1);
            firstEnd.setHours(23, 59, 59, 999);

            if (firstEnd >= start && firstStart <= end) {
                periods.push({
                    start: formatDateUTC(firstStart),
                    end: formatDateUTC(firstEnd),
                    label: `${getMonthName(month)} ${config.firstDate || 1}-${(config.secondDate || 15) - 1}, ${year}`
                });
            }

            // Second period
            const secondStart = new Date(year, month, config.secondDate || 15);
            const lastDayOfMonth = new Date(year, month + 1, 0).getDate();
            const secondEnd = new Date(year, month, lastDayOfMonth);
            secondEnd.setHours(23, 59, 59, 999);

            if (secondEnd >= start && secondStart <= end) {
                periods.push({
                    start: formatDateUTC(secondStart),
                    end: formatDateUTC(secondEnd),
                    label: `${getMonthName(month)} ${config.secondDate || 15}-${lastDayOfMonth}, ${year}`
                });
            }
        }
    }
}

/**
 * Generate monthly pay periods (simplified)
 */
function generateMonthlyPeriods(start, end, config, periods) {
    const startYear = start.getFullYear();
    const startMonth = start.getMonth();
    const endYear = end.getFullYear();
    const endMonth = end.getMonth();

    for (let year = startYear; year <= endYear; year++) {
        const monthStart = year === startYear ? startMonth : 0;
        const monthEnd = year === endYear ? endMonth : 11;

        for (let month = monthStart; month <= monthEnd; month++) {
            const periodStart = new Date(year, month, config.dayOfMonth || 1);
            const periodEnd = new Date(year, month + 1, (config.dayOfMonth || 1) - 1);
            
            if (periodEnd.getDate() !== (config.dayOfMonth || 1) - 1) {
                periodEnd.setDate(0); // Last day of the month
            }
            
            periodEnd.setHours(23, 59, 59, 999);

            if (periodEnd >= start && periodStart <= end) {
                periods.push({
                    start: formatDateUTC(periodStart),
                    end: formatDateUTC(periodEnd),
                    label: `${getMonthName(month)} ${year}`
                });
            }
        }
    }
}

/**
 * Utility functions for Cloud Functions
 */
function formatDateUTC(date) {
    // Handle both Date objects and strings
    if (typeof date === 'string') {
        date = new Date(date);
    }
    
    // Validate date before formatting
    if (!date || isNaN(date.getTime())) {
        throw new Error(`Invalid date provided to formatDateUTC: ${date}`);
    }
    
    return date.toISOString().split('T')[0];
}

function formatDateForLabel(date) {
    return date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
    });
}

function getWeekStart(date, startDayOfWeek = 1) {
    const result = new Date(date);
    const currentDay = result.getDay();
    const diff = (currentDay - startDayOfWeek + 7) % 7;
    result.setDate(result.getDate() - diff);
    result.setHours(0, 0, 0, 0);
    return result;
}

function getMonthName(monthIndex) {
    const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[monthIndex];
}

// Function 4: Search Daily Reports with Server-Side Pagination
exports.searchDailyReports = onCall({
    cors: true,
    memory: '512MB',
    timeoutSeconds: 60
}, async (request) => {
    const startTime = Date.now();
    
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        const {
            organizationId,
            searchQuery = '',
            page = 1,
            limit = 50,
            filters = {},
            sortBy = 'timestamp',
            sortOrder = 'desc'
        } = request.data;

        // Validate required parameters
        if (!organizationId) {
            throw new Error('Organization ID is required');
        }

        // Validate pagination parameters
        const pageNum = Math.max(1, parseInt(page));
        const limitNum = Math.min(100, Math.max(1, parseInt(limit))); // Max 100 per page
        const offset = (pageNum - 1) * limitNum;

        // Build base query
        let query = db.collection('dailyJobReports')
            .where('organizationID', '==', organizationId);

        // Apply filters
        if (filters.photographer) {
            query = query.where('yourName', '==', filters.photographer);
        }

        if (filters.school) {
            query = query.where('schoolOrDestination', '==', filters.school);
        }

        if (filters.startDate) {
            const startDate = admin.firestore.Timestamp.fromDate(new Date(filters.startDate));
            query = query.where('timestamp', '>=', startDate);
        }

        if (filters.endDate) {
            const endDate = admin.firestore.Timestamp.fromDate(new Date(filters.endDate + 'T23:59:59'));
            query = query.where('timestamp', '<=', endDate);
        }

        // Apply sorting
        const sortField = sortBy === 'date' ? 'timestamp' : sortBy;
        const sortDirection = sortOrder === 'asc' ? 'asc' : 'desc';
        query = query.orderBy(sortField, sortDirection);

        // Get total count for pagination (if no search query)
        let totalCount = 0;
        if (!searchQuery.trim()) {
            try {
                const countQuery = await query.count().get();
                totalCount = countQuery.data().count;
            } catch (error) {
                console.warn('Count query failed, using fallback method:', error);
                // Fallback: estimate based on query results
                const allResults = await query.limit(1000).get();
                totalCount = allResults.size;
            }
        }

        // Apply pagination
        query = query.offset(offset).limit(limitNum);

        // Execute main query
        const snapshot = await query.get();
        let reports = [];

        snapshot.forEach(doc => {
            const data = doc.data();
            reports.push({
                id: doc.id,
                ...data,
                // Convert Firestore timestamps to ISO strings for JSON serialization
                timestamp: data.timestamp?.toDate?.()?.toISOString() || data.timestamp,
                date: data.date?.toDate?.()?.toISOString() || data.date,
                startDate: data.startDate?.toDate?.()?.toISOString() || data.startDate,
                endDate: data.endDate?.toDate?.()?.toISOString() || data.endDate,
                createdAt: data.createdAt?.toDate?.()?.toISOString() || data.createdAt,
                updatedAt: data.updatedAt?.toDate?.()?.toISOString() || data.updatedAt
            });
        });

        // Apply search filtering if search query provided
        if (searchQuery.trim()) {
            const searchTerm = searchQuery.toLowerCase();
            reports = reports.filter(report => {
                const searchableFields = [
                    report.yourName,
                    report.schoolOrDestination,
                    Array.isArray(report.jobDescriptions) ? report.jobDescriptions.join(' ') : '',
                    Array.isArray(report.extraItems) ? report.extraItems.join(' ') : '',
                    report.photoshootNoteText,
                    report.jobDescriptionText,
                    report.jobBoxAndCameraCards,
                    report.sportsBackgroundShot,
                    report.cardsScannedChoice
                ];

                return searchableFields.some(field => 
                    field && String(field).toLowerCase().includes(searchTerm)
                );
            });

            // Update total count for search results
            totalCount = reports.length;
        }

        // Calculate pagination metadata
        const totalPages = Math.ceil(totalCount / limitNum);
        const hasNextPage = pageNum < totalPages;
        const hasPrevPage = pageNum > 1;

        const executionTime = Date.now() - startTime;

        // Return structured response
        return {
            reports,
            pagination: {
                currentPage: pageNum,
                totalPages,
                totalResults: totalCount,
                resultsPerPage: limitNum,
                hasNextPage,
                hasPrevPage
            },
            searchMeta: {
                query: searchQuery,
                executionTime,
                cached: false,
                appliedFilters: filters
            }
        };

    } catch (error) {
        console.error('Error in searchDailyReports:', error);
        throw new Error(`Search failed: ${error.message}`);
    }
});

// Function 5: Send Flag Notification (Callable)
exports.sendFlagNotificationCallable = onCall({
    cors: true,
    enforceAppCheck: false, // Enable in production
}, async (request) => {
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        const { targetUserID, flagNote, flaggedBy } = request.data;

        // Validate required parameters
        if (!targetUserID || !flagNote) {
            throw new Error('Missing required parameters: targetUserID and flagNote');
        }

        // Security check: Verify the caller has permission to flag users
        // This could check if the caller is a manager or has specific permissions
        const callerDoc = await db.collection('users').doc(request.auth.uid).get();
        if (!callerDoc.exists) {
            throw new Error('Caller user not found');
        }

        const callerData = callerDoc.data();
        // Add your permission logic here, for example:
        // if (!callerData.isManager && !callerData.canFlagUsers) {
        //     throw new Error('Insufficient permissions to flag users');
        // }

        // Format and send the notification
        const notification = notificationService.formatNotification(NotificationType.FLAG, {
            flagNote,
            flaggedBy: flaggedBy || request.auth.uid
        });

        const result = await notificationService.sendToUser(targetUserID, notification);

        // Log the flag action for audit purposes
        await db.collection('auditLogs').add({
            action: 'user_flagged',
            targetUserId: targetUserID,
            performedBy: request.auth.uid,
            flagNote,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            notificationSent: result.success
        });

        return {
            success: result.success,
            message: result.success ? 'Notification sent successfully' : 'Failed to send notification',
            error: result.error
        };

    } catch (error) {
        logger.error('Error in sendFlagNotificationCallable:', error);
        throw new Error(error.message);
    }
});

// Function 6: Send Chat Notification (Callable)
exports.sendChatNotificationCallable = onCall({
    cors: true,
    enforceAppCheck: false, // Enable in production
}, async (request) => {
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        const { conversationId, messageText, recipientIds } = request.data;

        // Validate required parameters
        if (!conversationId || !messageText || !recipientIds || !Array.isArray(recipientIds)) {
            throw new Error('Missing required parameters');
        }

        // Get sender information
        const senderDoc = await db.collection('users').doc(request.auth.uid).get();
        if (!senderDoc.exists) {
            throw new Error('Sender user not found');
        }

        const senderData = senderDoc.data();
        const senderName = `${senderData.firstName || ''} ${senderData.lastName || ''}`.trim() || 'Unknown';

        // Filter out the sender from recipients
        const filteredRecipients = recipientIds.filter(id => id !== request.auth.uid);

        if (filteredRecipients.length === 0) {
            return { success: true, message: 'No recipients to notify' };
        }

        // Format and send notifications
        const notification = notificationService.formatNotification(NotificationType.CHAT_MESSAGE, {
            conversationId,
            messageText,
            senderId: request.auth.uid,
            senderName
        });

        const results = await notificationService.sendToUsers(filteredRecipients, notification);

        return {
            success: true,
            results: results.summary,
            message: `Notifications sent to ${results.summary.sent} users`
        };

    } catch (error) {
        logger.error('Error in sendChatNotificationCallable:', error);
        throw new Error(error.message);
    }
});

// Function 7: Send Session Notification (Callable)
exports.sendSessionNotificationCallable = onCall({
    cors: true,
    enforceAppCheck: false, // Enable in production
}, async (request) => {
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        const { sessionId, notificationType, changeType, assignedUserIds } = request.data;

        // Validate required parameters
        if (!sessionId || !notificationType || !assignedUserIds || !Array.isArray(assignedUserIds)) {
            throw new Error('Missing required parameters');
        }

        // Get session details
        const sessionDoc = await db.collection('sessions').doc(sessionId).get();
        if (!sessionDoc.exists) {
            throw new Error('Session not found');
        }

        const sessionData = sessionDoc.data();

        // Format notification based on type
        let notification;
        if (notificationType === 'new') {
            notification = notificationService.formatNotification(NotificationType.SESSION_NEW, {
                sessionId,
                schoolName: sessionData.schoolName,
                date: sessionData.date,
                time: sessionData.startTime
            });
        } else if (notificationType === 'update') {
            notification = notificationService.formatNotification(NotificationType.SESSION_UPDATE, {
                sessionId,
                changeType: changeType || 'updated',
                schoolName: sessionData.schoolName
            });
        } else {
            throw new Error('Invalid notification type');
        }

        // Send to assigned users
        const results = await notificationService.sendToUsers(assignedUserIds, notification);

        return {
            success: true,
            results: results.summary,
            message: `Notifications sent to ${results.summary.sent} users`
        };

    } catch (error) {
        logger.error('Error in sendSessionNotificationCallable:', error);
        throw new Error(error.message);
    }
});

// Function 8: Clock In Reminder - Scheduled Function
exports.clockInReminder = onSchedule('*/5 * * * *', async (event) => {
    logger.info('Running clock-in reminder check...');
    
    try {
        const now = new Date();
        const oneHourFromNow = new Date(now.getTime() + 60 * 60 * 1000);
        
        // Query sessions that:
        // 1. Start within the next hour
        // 2. Haven't been notified yet
        // 3. Have assigned photographers
        const sessionsSnapshot = await db.collection('sessions')
            .where('startDate', '>=', now)
            .where('startDate', '<=', oneHourFromNow)
            .where('clockInReminderSent', '==', false)
            .get();
        
        logger.info(`Found ${sessionsSnapshot.size} sessions needing clock-in reminders`);
        
        const notificationPromises = [];
        
        for (const sessionDoc of sessionsSnapshot.docs) {
            const sessionData = sessionDoc.data();
            const sessionId = sessionDoc.id;
            
            // Get assigned photographer IDs
            const photographerIds = sessionData.photographers?.map(p => p.id).filter(id => id) || [];
            
            if (photographerIds.length === 0) {
                logger.warn(`Session ${sessionId} has no assigned photographers`);
                continue;
            }
            
            // Calculate leave time for each photographer
            for (const photographerId of photographerIds) {
                // Get user's home address
                const userDoc = await db.collection('users').doc(photographerId).get();
                if (!userDoc.exists) continue;
                
                const userData = userDoc.data();
                const homeAddress = userData.homeAddress || userData.coordinates;
                
                if (!homeAddress) {
                    logger.warn(`User ${photographerId} has no home address set`);
                    continue;
                }
                
                // Calculate travel time (this is a simplified version - you may want to use a maps API)
                // For now, we'll use a default 30 minutes before session start
                const leaveTime = new Date(sessionData.startDate.toDate().getTime() - 30 * 60 * 1000);
                
                // Check if it's time to send the reminder (within 5 minutes of leave time)
                const timeDiff = leaveTime.getTime() - now.getTime();
                if (timeDiff > 0 && timeDiff <= 5 * 60 * 1000) {
                    // Send reminder notification
                    const notification = notificationService.formatNotification(NotificationType.CLOCK_REMINDER, {
                        reminderType: 'clock_in',
                        sessionId,
                        schoolName: sessionData.schoolName
                    });
                    
                    notificationPromises.push(
                        notificationService.sendToUser(photographerId, notification)
                            .then(result => {
                                logger.info(`Clock-in reminder sent to user ${photographerId} for session ${sessionId}`);
                                return result;
                            })
                            .catch(error => {
                                logger.error(`Failed to send clock-in reminder to user ${photographerId}:`, error);
                                return { success: false, error: error.message };
                            })
                    );
                }
            }
            
            // Mark session as notified
            await sessionDoc.ref.update({
                clockInReminderSent: true,
                clockInReminderSentAt: admin.firestore.FieldValue.serverTimestamp()
            });
        }
        
        // Wait for all notifications to complete
        const results = await Promise.all(notificationPromises);
        const successCount = results.filter(r => r.success).length;
        
        logger.info(`Clock-in reminder check completed. Sent ${successCount} notifications.`);
        
    } catch (error) {
        logger.error('Error in clockInReminder:', error);
        throw error;
    }
});

// Function 9: Clock Out Reminder - Scheduled Function (8 PM daily)
exports.clockOutReminder = onSchedule('0 20 * * *', async (event) => {
    logger.info('Running clock-out reminder check at 8 PM...');
    
    try {
        const today = formatDateUTC(new Date());
        
        // Get all organizations to check
        const orgsSnapshot = await db.collection('organizations').get();
        
        for (const orgDoc of orgsSnapshot.docs) {
            const orgId = orgDoc.id;
            
            // Query time entries that are still clocked in today
            const clockedInEntries = await db.collection('timeEntries')
                .where('organizationID', '==', orgId)
                .where('date', '==', today)
                .where('status', '==', 'clocked-in')
                .get();
            
            logger.info(`Found ${clockedInEntries.size} users still clocked in for org ${orgId}`);
            
            // Group by user to avoid multiple notifications
            const userIds = new Set();
            clockedInEntries.docs.forEach(doc => {
                userIds.add(doc.data().userId);
            });
            
            // Send notifications
            for (const userId of userIds) {
                const notification = notificationService.formatNotification(NotificationType.CLOCK_REMINDER, {
                    reminderType: 'clock_out'
                });
                
                try {
                    await notificationService.sendToUser(userId, notification);
                    logger.info(`Clock-out reminder sent to user ${userId}`);
                } catch (error) {
                    logger.error(`Failed to send clock-out reminder to user ${userId}:`, error);
                }
            }
        }
        
        logger.info('Clock-out reminder check completed.');
        
    } catch (error) {
        logger.error('Error in clockOutReminder:', error);
        throw error;
    }
});

// Function 10: Daily Report Reminder - Scheduled Function (7:30 PM daily)
exports.dailyReportReminder = onSchedule('30 19 * * *', async (event) => {
    logger.info('Running daily report reminder check at 7:30 PM...');
    
    try {
        const today = formatDateUTC(new Date());
        
        // Get all organizations
        const orgsSnapshot = await db.collection('organizations').get();
        
        for (const orgDoc of orgsSnapshot.docs) {
            const orgId = orgDoc.id;
            
            // Get all users who had sessions today
            const sessionsToday = await db.collection('sessions')
                .where('organizationID', '==', orgId)
                .where('date', '==', today)
                .get();
            
            // Extract unique user IDs from sessions
            const usersWithSessions = new Set();
            sessionsToday.docs.forEach(doc => {
                const photographers = doc.data().photographers || [];
                photographers.forEach(p => {
                    if (p.id) usersWithSessions.add(p.id);
                });
            });
            
            if (usersWithSessions.size === 0) {
                logger.info(`No users with sessions today for org ${orgId}`);
                continue;
            }
            
            // Check which users have already submitted reports
            const reportsToday = await db.collection('dailyJobReports')
                .where('organizationID', '==', orgId)
                .where('date', '==', today)
                .get();
            
            const usersWithReports = new Set();
            reportsToday.docs.forEach(doc => {
                usersWithReports.add(doc.data().userId);
            });
            
            // Find users who need reminders
            const usersNeedingReminder = [...usersWithSessions].filter(
                userId => !usersWithReports.has(userId)
            );
            
            logger.info(`Found ${usersNeedingReminder.length} users needing report reminders in org ${orgId}`);
            
            // Send reminders
            for (const userId of usersNeedingReminder) {
                // Count their sessions for today
                const userSessionsCount = sessionsToday.docs.filter(doc => {
                    const photographers = doc.data().photographers || [];
                    return photographers.some(p => p.id === userId);
                }).length;
                
                const notification = notificationService.formatNotification(NotificationType.REPORT_REMINDER, {
                    date: today,
                    sessionsCount: userSessionsCount
                });
                
                try {
                    await notificationService.sendToUser(userId, notification);
                    logger.info(`Report reminder sent to user ${userId}`);
                } catch (error) {
                    logger.error(`Failed to send report reminder to user ${userId}:`, error);
                }
            }
        }
        
        logger.info('Daily report reminder check completed.');
        
    } catch (error) {
        logger.error('Error in dailyReportReminder:', error);
        throw error;
    }
});

// Function 11: Session Change Detection - Firestore Trigger
exports.detectSessionChanges = onDocumentWritten('sessions/{sessionId}', async (event) => {
    const sessionId = event.params.sessionId;
    const beforeData = event.data.before?.data();
    const afterData = event.data.after?.data();
    
    // Skip if session was deleted
    if (!afterData) {
        logger.info(`Session ${sessionId} was deleted`);
        return;
    }
    
    // Handle new sessions
    if (!beforeData) {
        logger.info(`New session ${sessionId} created`);
        
        // Check if session is published
        if (!afterData.isPublished) {
            logger.info(`New session ${sessionId} is unpublished - skipping notification`);
            return;
        }
        
        // Get assigned photographer IDs from the new session
        const photographerIds = afterData.photographers?.map(p => p.id).filter(id => id) || [];
        
        if (photographerIds.length === 0) {
            logger.info(`New session ${sessionId} has no assigned photographers`);
            return;
        }
        
        // Send new session notification
        const notification = notificationService.formatNotification(NotificationType.SESSION_NEW, {
            sessionId,
            schoolName: afterData.schoolName,
            date: afterData.date,
            time: afterData.startTime
        });
        
        const results = await notificationService.sendToUsers(photographerIds, notification);
        
        logger.info(`New session notifications sent for ${sessionId}: ${results.summary.sent} successful`);
        return;
    }
    
    try {
        // Check what changed
        const changes = [];
        
        // Published status change
        if (beforeData.isPublished === false && afterData.isPublished === true) {
            changes.push('published');
        }
        
        // Time change
        if (beforeData.startTime !== afterData.startTime || beforeData.endTime !== afterData.endTime) {
            changes.push('time changed');
        }
        
        // Location change
        if (beforeData.location !== afterData.location || beforeData.schoolName !== afterData.schoolName) {
            changes.push('location changed');
        }
        
        // Notes change
        if (beforeData.notes !== afterData.notes) {
            changes.push('notes updated');
        }
        
        // Date change
        if (beforeData.date !== afterData.date) {
            changes.push('date changed');
        }
        
        // Check for photographer-specific notes changes
        const beforePhotographersMap = new Map();
        const afterPhotographersMap = new Map();
        
        // Build maps of photographer notes
        beforeData.photographers?.forEach(p => {
            if (p.id) beforePhotographersMap.set(p.id, p.notes || '');
        });
        afterData.photographers?.forEach(p => {
            if (p.id) afterPhotographersMap.set(p.id, p.notes || '');
        });
        
        // Check for photographer notes changes
        afterPhotographersMap.forEach((afterNotes, photographerId) => {
            const beforeNotes = beforePhotographersMap.get(photographerId) || '';
            if (beforeNotes !== afterNotes) {
                changes.push('photographer notes updated');
                logger.info(`Photographer ${photographerId} notes changed from "${beforeNotes}" to "${afterNotes}"`);
            }
        });
        
        // Skip if no relevant changes
        if (changes.length === 0) {
            logger.info(`Session ${sessionId} updated but no notification-worthy changes`);
            return;
        }
        
        // Skip notifications if session is still unpublished
        if (!afterData.isPublished) {
            logger.info(`Session ${sessionId} is unpublished - skipping notification despite changes`);
            return;
        }
        
        // Get assigned photographer IDs
        const photographerIds = afterData.photographers?.map(p => p.id).filter(id => id) || [];
        
        if (photographerIds.length === 0) {
            logger.info(`Session ${sessionId} has no assigned photographers`);
            return;
        }
        
        // Send update notification
        const notification = notificationService.formatNotification(NotificationType.SESSION_UPDATE, {
            sessionId,
            changeType: changes.join(', '),
            schoolName: afterData.schoolName
        });
        
        const results = await notificationService.sendToUsers(photographerIds, notification);
        
        logger.info(`Session change notifications sent for ${sessionId}: ${results.summary.sent} successful`);
        
    } catch (error) {
        logger.error(`Error detecting session changes for ${sessionId}:`, error);
        throw error;
    }
});

// Function 12: Chat Message Notification - Firestore Trigger
exports.onNewChatMessage = onDocumentCreated('messages/{conversationId}/messages/{messageId}', async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
        logger.info('No data in chat message event');
        return;
    }
    
    const messageData = snapshot.data();
    const conversationId = event.params.conversationId;
    const messageId = event.params.messageId;
    
    logger.info(`New chat message in conversation ${conversationId}: ${messageId}`);
    
    try {
        // Skip system messages
        if (messageData.type === 'system') {
            logger.info('Skipping notification for system message');
            return;
        }
        
        // Skip if no sender information
        if (!messageData.senderId) {
            logger.warn('Message missing senderId');
            return;
        }
        
        // Get conversation to find participants
        const conversationDoc = await db.collection('conversations').doc(conversationId).get();
        if (!conversationDoc.exists) {
            logger.error(`Conversation ${conversationId} not found`);
            return;
        }
        
        const conversationData = conversationDoc.data();
        const participants = conversationData.participants || [];
        
        // Filter out the sender
        const recipientIds = participants.filter(id => id !== messageData.senderId);
        
        if (recipientIds.length === 0) {
            logger.info('No recipients to notify (sender is only participant)');
            return;
        }
        
        logger.info(`Sending chat notifications to ${recipientIds.length} recipients`);
        
        // Format and send notifications
        const notification = notificationService.formatNotification(NotificationType.CHAT_MESSAGE, {
            conversationId,
            messageText: messageData.text || '',
            senderId: messageData.senderId,
            senderName: messageData.senderName || 'Someone'
        });
        
        const results = await notificationService.sendToUsers(recipientIds, notification);
        
        logger.info(`Chat notifications sent: ${results.summary.sent} successful, ${results.summary.failed} failed`);
        
    } catch (error) {
        logger.error(`Error sending chat notifications for message ${messageId}:`, error);
        // Don't throw - we don't want to retry notification sends
    }
});

// ======================================
// CAPTURA API PROXY FUNCTIONS
// ======================================

// Cache for OAuth tokens
let capturaTokenCache = {
    token: null,
    expiresAt: null
};

/**
 * Get Captura OAuth token with caching
 */
async function getCapturaAccessToken() {
    // Check if we have a valid cached token
    if (capturaTokenCache.token && capturaTokenCache.expiresAt && new Date() < capturaTokenCache.expiresAt) {
        logger.info('Using cached Captura token');
        return capturaTokenCache.token;
    }

    logger.info('Fetching new Captura token');

    // Get credentials from environment config or fallback to hardcoded values
    const clientId = process.env.CAPTURA_CLIENT_ID || '1ab255f1-5a89-4ae8-b454-4da98b64afcb';
    const clientSecret = process.env.CAPTURA_CLIENT_SECRET || '18458cffbe1e0fe82b2c99d4ead741cc8271640b0020d8f61035945be374675913a32303e32ce6c6a78d88c91554419e19cd458ce28d490302d2c1dd020df03d';
    const tokenUrl = 'https://api.imagequix.com/api/oauth/token';

    try {
        const response = await axios.post(tokenUrl, 
            new URLSearchParams({
                grant_type: 'client_credentials',
                client_id: clientId,
                client_secret: clientSecret
            }).toString(),
            {
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded'
                }
            }
        );

        const { access_token, expires_in = 3600 } = response.data;
        
        // Cache the token with expiration
        capturaTokenCache.token = access_token;
        capturaTokenCache.expiresAt = new Date(Date.now() + (expires_in - 300) * 1000); // 5 min buffer
        
        logger.info('Captura token obtained successfully');
        return access_token;
    } catch (error) {
        logger.error('Error getting Captura token:', error.response?.data || error.message);
        throw new Error('Failed to authenticate with Captura API');
    }
}

// Function 13: Get Captura Orders
exports.getCapturaOrders = onCall({
    cors: true,
    maxInstances: 10,
}, async (request) => {
    let url = ''; // Define url at function scope
    
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }
        
        // Get account ID from environment or use default
        const accountId = process.env.CAPTURA_ACCOUNT_ID || 'J98TA9W';
        
        // Get access token
        const accessToken = await getCapturaAccessToken();
        
        // Extract parameters
        const { 
            start = 1, 
            end = 500, // Increased to handle more orders per day
            orderStartDate,
            orderEndDate,
            orderType,
            paymentStatus
        } = request.data || {};
        
        // Handle date formatting if dates are provided as Date objects or strings
        let formattedStartDate = orderStartDate;
        let formattedEndDate = orderEndDate;
        
        // Convert JavaScript Date strings to YYYY-MM-DD format
        if (orderStartDate instanceof Date || (typeof orderStartDate === 'string' && orderStartDate.includes('GMT'))) {
            const dateObj = new Date(orderStartDate);
            formattedStartDate = dateObj.toISOString().split('T')[0];
        }
        
        if (orderEndDate instanceof Date || (typeof orderEndDate === 'string' && orderEndDate.includes('GMT'))) {
            const dateObj = new Date(orderEndDate);
            formattedEndDate = dateObj.toISOString().split('T')[0];
        }
        
        // Add one day to end date to make it inclusive (API treats end date as exclusive)
        if (formattedEndDate) {
            logger.info(`Original end date: ${formattedEndDate}`);
            const endDateObj = new Date(formattedEndDate + 'T00:00:00'); // Ensure we parse as UTC
            endDateObj.setUTCDate(endDateObj.getUTCDate() + 1); // Use UTC date to avoid timezone issues
            const adjustedEndDate = endDateObj.toISOString().split('T')[0];
            logger.info(`Adjusting end date from ${formattedEndDate} to ${adjustedEndDate} for inclusive range`);
            formattedEndDate = adjustedEndDate;
        }
        
        // Build request parameters - only include filters if provided
        const params = {
            start: start.toString(),
            end: end.toString()
        };

        // Only add date filters if they are provided
        if (formattedStartDate) params.orderStartDate = formattedStartDate;
        if (formattedEndDate) params.orderEndDate = formattedEndDate;
        if (orderType) params.orderType = orderType;
        if (paymentStatus) params.paymentStatus = paymentStatus;
        
        const hasDateFilters = !!(formattedStartDate || formattedEndDate);

        const queryString = new URLSearchParams(params).toString();
        url = `https://api.imagequix.com/api/v1/account/${accountId}/order?${queryString}`;
        
        logger.info(`=== CAPTURA API REQUEST DEBUG ===`);
        logger.info(`URL: ${url}`);
        logger.info('Request parameters:', JSON.stringify(params, null, 2));
        logger.info(`Has date filters: ${hasDateFilters}`);

        const response = await axios.get(url, {
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json'
            },
            timeout: 30000 // 30 second timeout
        });

        logger.info(`=== CAPTURA API RESPONSE DEBUG ===`);
        logger.info('Response status:', response.status);
        
        // Comprehensive response structure logging
        const responseDebug = {
            hasData: !!response.data,
            dataType: typeof response.data,
            topLevelKeys: response.data ? Object.keys(response.data) : []
        };
        
        // Check for orders field
        if (response.data?.orders !== undefined) {
            responseDebug.orders = {
                exists: true,
                isArray: Array.isArray(response.data.orders),
                length: Array.isArray(response.data.orders) ? response.data.orders.length : 'not-array',
                firstOrderKeys: response.data.orders?.[0] ? Object.keys(response.data.orders[0]) : []
            };
        }
        
        // Check for data field
        if (response.data?.data !== undefined) {
            responseDebug.dataField = {
                exists: true,
                isArray: Array.isArray(response.data.data),
                length: Array.isArray(response.data.data) ? response.data.data.length : 'not-array'
            };
            
            if (Array.isArray(response.data.data) && response.data.data.length > 0) {
                responseDebug.dataField.firstItemKeys = Object.keys(response.data.data[0]);
                responseDebug.dataField.firstItemHasOrders = !!response.data.data[0].orders;
                if (response.data.data[0].orders) {
                    responseDebug.dataField.firstItemOrdersCount = response.data.data[0].orders.length;
                }
            }
        }
        
        // Check for pagination fields
        responseDebug.pagination = {
            total: response.data?.total,
            start: response.data?.start,
            end: response.data?.end
        };
        
        // Check for address fields
        responseDebug.hasAddresses = {
            billTo: !!response.data?.billTo,
            shipTo: !!response.data?.shipTo
        };
        
        logger.info('Response structure:', JSON.stringify(responseDebug, null, 2));
        
        // If response is small enough, log it entirely for debugging
        const responseSize = JSON.stringify(response.data).length;
        if (responseSize < 2000) {
            logger.info('Full response (small enough to log):', JSON.stringify(response.data, null, 2));
        } else {
            logger.info(`Response too large to log fully (${responseSize} chars)`);
        }

        // Handle different response formats based on actual structure
        // First priority: Check if we have direct format (orders array at top level)
        if (response.data?.orders && Array.isArray(response.data.orders)) {
            // Direct format - orders at top level (unfiltered requests)
            logger.info('=== USING DIRECT FORMAT HANDLER ===');
            logger.info(`Direct format contains ${response.data.orders.length} orders`);
            
            return {
                success: true,
                data: response.data
            };
        }
        // Second priority: Check if we have the wrapped format with date filters
        else if (response.data?.data && Array.isArray(response.data.data) && response.data.total !== undefined) {
            // Date filtered format - data array contains orders directly
            logger.info('=== USING DATE FILTERED FORMAT HANDLER ===');
            logger.info(`Found ${response.data.data.length} orders in data array`);
            logger.info(`Total orders reported: ${response.data.total}`);
            
            // The data array contains the orders directly when date filters are used
            const orders = response.data.data;
            
            // Log the date range of orders we received
            if (orders.length > 0) {
                const orderDates = orders.map(o => o.orderDate?.split(' ')[0]).filter(Boolean);
                const uniqueDates = [...new Set(orderDates)].sort();
                logger.info(`=== ORDER DATES RETURNED ===`);
                logger.info(`Requested: ${params.orderStartDate} to ${params.orderEndDate}`);
                logger.info(`Received ${orders.length} orders with dates: ${uniqueDates.join(', ')}`);
                logger.info(`Date range in response: ${uniqueDates[0]} to ${uniqueDates[uniqueDates.length - 1]}`);
            }
            
            // Return in the format expected by the service (consistent with direct format)
            return {
                success: true,
                data: {
                    orders: orders,
                    total: response.data.total,
                    start: response.data.start,
                    end: response.data.end,
                    // Extract billTo/shipTo from first order if available
                    billTo: orders[0]?.billTo || null,
                    shipTo: orders[0]?.shipTo || null,
                    accountID: accountId
                }
            };
        }
        // Third priority: Check if we have the batch format (for backfill function)
        else if (response.data?.data && Array.isArray(response.data.data)) {
            // This might be the batch format used by backfill
            logger.info('=== CHECKING FOR BATCH FORMAT ===');
            
            // Check if first item has orders array (batch format)
            if (response.data.data[0]?.orders && Array.isArray(response.data.data[0].orders)) {
                logger.info('Detected batch format with nested orders arrays');
                
                const allOrders = [];
                response.data.data.forEach((batchItem, index) => {
                    if (batchItem.orders && Array.isArray(batchItem.orders)) {
                        logger.info(`Batch item ${index}: extracting ${batchItem.orders.length} orders`);
                        
                        // Merge billTo/shipTo from batch item with each order
                        const ordersWithContext = batchItem.orders.map(order => ({
                            ...order,
                            billTo: batchItem.billTo || order.billTo,
                            shipTo: batchItem.shipTo || order.shipTo,
                            accountID: batchItem.accountID || order.accountID
                        }));
                        allOrders.push(...ordersWithContext);
                    }
                });
                
                logger.info(`Total orders extracted from batch format: ${allOrders.length}`);
                
                return {
                    success: true,
                    data: {
                        orders: allOrders,
                        total: response.data.total || allOrders.length,
                        start: response.data.start,
                        end: response.data.end,
                        billTo: response.data.data[0]?.billTo,
                        shipTo: response.data.data[0]?.shipTo,
                        accountID: accountId
                    }
                };
            } else {
                logger.warn('Data array exists but first item has no orders array - treating as empty response');
            }
        }
        
        // Unexpected format
        logger.error('=== UNEXPECTED RESPONSE FORMAT ===');
        logger.error('Cannot find orders in response. Structure:', responseDebug);
        
        // If response is small, log it for debugging
        if (responseSize < 5000) {
            logger.error('Full response for debugging:', JSON.stringify(response.data, null, 2));
        }
        
        // Return empty result instead of throwing error
        logger.warn('Returning empty result due to unexpected format');
        return {
            success: true,
            data: {
                orders: [],
                total: 0,
                billTo: null,
                shipTo: null,
                accountID: accountId
            }
        };
    } catch (error) {
        // Log detailed error information
        logger.error('Error in getCapturaOrders:', {
            status: error.response?.status,
            statusText: error.response?.statusText,
            data: error.response?.data,
            message: error.message,
            url: url
        });
        
        if (error.response?.status === 401) {
            // Clear token cache on auth error
            capturaTokenCache = { token: null, expiresAt: null };
            throw new Error('Authentication failed - invalid token');
        }
        
        if (error.response?.status === 404) {
            throw new Error(`Orders endpoint not found. The API endpoint may be incorrect: ${url}`);
        }
        
        throw new Error(error.response?.data?.message || error.message || 'Failed to fetch orders');
    }
});

// Function 14: Get Single Captura Order
exports.getCapturaOrder = onCall({
    cors: true,
    maxInstances: 10,
}, async (request) => {
    let url = ''; // Define url at function scope
    
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        const { orderId } = request.data;

        if (!orderId) {
            throw new Error('Order ID is required');
        }

        // Get account ID from environment or use default
        const accountId = process.env.CAPTURA_ACCOUNT_ID || 'J98TA9W';

        // Get access token
        const accessToken = await getCapturaAccessToken();

        // Make request to Captura API - using 'order' not 'orders'
        url = `https://api.imagequix.com/api/v1/account/${accountId}/order/${orderId}`;
        
        logger.info(`Fetching order ${orderId} from Captura`);
        
        const response = await axios.get(url, {
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json'
            }
        });

        logger.info(`Captura order ${orderId} fetched successfully`);
        
        // Log the structure to understand it better
        logger.info('Order response structure:', {
            hasOrders: !!response.data.orders,
            hasBillTo: !!response.data.billTo,
            hasShipTo: !!response.data.shipTo,
            hasItems: !!response.data.items,
            itemsCount: response.data.items?.length || 0,
            directFields: Object.keys(response.data || {}),
            // Check if it's nested in orders array
            firstOrderHasItems: response.data.orders?.[0]?.items ? response.data.orders[0].items.length : 'N/A'
        });

        return {
            success: true,
            data: response.data
        };

    } catch (error) {
        // Log detailed error information
        logger.error('Error in getCapturaOrder:', {
            status: error.response?.status,
            statusText: error.response?.statusText,
            data: error.response?.data,
            headers: error.response?.headers,
            message: error.message,
            url: url
        });
        
        if (error.response?.status === 401) {
            // Clear token cache on auth error
            capturaTokenCache = { token: null, expiresAt: null };
            throw new Error('Authentication failed - invalid token');
        }
        
        if (error.response?.status === 404) {
            throw new Error(`Order endpoint not found. The API endpoint may be incorrect: ${url}`);
        }
        
        throw new Error(error.response?.data?.message || error.message || 'Failed to fetch order');
    }
});

// Function 15: Get Captura Order Statistics
// NOTE: This endpoint might not exist in the Captura API
// You may need to fetch orders and calculate statistics locally
exports.getCapturaOrderStats = onCall({
    cors: true,
    maxInstances: 10,
}, async (request) => {
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        const { dateRange = 'month' } = request.data;

        // For now, throw an error indicating this endpoint doesn't exist
        // TODO: Implement statistics calculation by fetching orders and computing stats
        throw new Error('Statistics endpoint not implemented. The Captura API may not have a dedicated statistics endpoint.');

        // Alternative implementation could be:
        // 1. Fetch orders with date filters
        // 2. Calculate statistics (total orders, revenue, etc.) in the function
        // 3. Return computed statistics

    } catch (error) {
        logger.error('Error in getCapturaOrderStats:', error.message);
        throw error;
    }
});

// Function 16: Test Captura API Endpoints (for debugging)
exports.testCapturaEndpoints = onCall({
    cors: true,
    maxInstances: 1,
}, async (request) => {
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        // Get access token
        const accessToken = await getCapturaAccessToken();
        const accountId = process.env.CAPTURA_ACCOUNT_ID || 'J98TA9W';
        
        // Test different possible endpoint formats
        const endpoints = [
            // Base URL without any parameters
            `https://api.imagequix.com/api/v1/account/${accountId}/orders`,
            
            // With minimal parameters
            `https://api.imagequix.com/api/v1/account/${accountId}/orders?page=1`,
            `https://api.imagequix.com/api/v1/account/${accountId}/orders?page=1&pageSize=50`,
            
            // With full parameters like current implementation
            `https://api.imagequix.com/api/v1/account/${accountId}/orders?page=1&pageSize=50&sortBy=orderDate&sortOrder=desc`,
            
            // Alternative URL structures
            `https://api.imagequix.com/api/v1/accounts/${accountId}/orders`,
            `https://api.imagequix.com/api/v1/orders?accountId=${accountId}`,
            `https://api.imagequix.com/api/orders?accountId=${accountId}`,
            `https://api.imagequix.com/api/account/${accountId}/orders`,
            `https://api.imagequix.com/v1/account/${accountId}/orders`,
            
            // Singular form
            `https://api.imagequix.com/api/v1/account/${accountId}/order`,
            
            // Development URL
            `https://api.imagequix-dev.com/api/v1/account/${accountId}/orders`,
        ];
        
        const results = [];
        
        for (const endpoint of endpoints) {
            try {
                logger.info(`Testing endpoint: ${endpoint}`);
                const response = await axios.get(endpoint, {
                    headers: {
                        'Authorization': `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    timeout: 5000
                });
                
                results.push({
                    endpoint,
                    success: true,
                    status: response.status,
                    hasData: !!response.data
                });
                
                logger.info(`Success: ${endpoint} returned status ${response.status}`);
            } catch (error) {
                results.push({
                    endpoint,
                    success: false,
                    status: error.response?.status,
                    error: error.response?.statusText || error.message
                });
                
                logger.info(`Failed: ${endpoint} - ${error.response?.status} ${error.response?.statusText || error.message}`);
            }
        }
        
        return {
            success: true,
            token: accessToken ? 'Token obtained successfully' : 'No token',
            results
        };
        
    } catch (error) {
        logger.error('Error in testCapturaEndpoints:', error);
        throw new Error(error.message || 'Failed to test endpoints');
    }
});

// Function 17: Get Captura Orders Simple (without parameters)
exports.getCapturaOrdersSimple = onCall({
    cors: true,
    maxInstances: 10,
}, async (request) => {
    let url = ''; // Define url at function scope
    
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }

        // Get account ID from environment or use default
        const accountId = process.env.CAPTURA_ACCOUNT_ID || 'J98TA9W';

        // Get access token
        const accessToken = await getCapturaAccessToken();

        // Try base URL without any parameters first
        url = `https://api.imagequix.com/api/v1/account/${accountId}/orders`;
        
        logger.info(`Testing simple orders fetch from: ${url}`);
        
        const response = await axios.get(url, {
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
        });

        logger.info(`Simple orders fetch successful. Status: ${response.status}`);
        logger.info(`Response data structure:`, {
            hasData: !!response.data,
            dataType: typeof response.data,
            keys: response.data ? Object.keys(response.data) : [],
            ordersCount: response.data?.orders?.length || response.data?.length || 'unknown'
        });

        return {
            success: true,
            url: url,
            status: response.status,
            data: response.data
        };

    } catch (error) {
        // Log detailed error information
        logger.error('Error in getCapturaOrdersSimple:', {
            status: error.response?.status,
            statusText: error.response?.statusText,
            data: error.response?.data,
            headers: error.response?.headers,
            message: error.message,
            url: url
        });
        
        return {
            success: false,
            url: url,
            status: error.response?.status,
            error: error.response?.data?.message || error.message || 'Failed to fetch orders',
            details: error.response?.data
        };
    }
});

// Export Captura stats functions
exports.syncDailyOrders = capturaStats.syncDailyOrders;
exports.backfillHistoricalData = capturaStats.backfillHistoricalData;

// ======================================
// PROOFING GALLERY EMAIL NOTIFICATIONS
// ======================================

/**
 * Cloud Function triggered when a proofGallery document is updated
 * Checks if the gallery status changed to "approved" and sends notifications
 */
exports.onProofGalleryUpdate = onDocumentWritten('proofGalleries/{galleryId}', async (event) => {
    // For v2 functions, the structure is different
    const galleryId = event.params.galleryId;
    
    try {
        // Check if we have the data
        if (!event.data) {
            console.log('No data in event');
            return null;
        }
        
        const change = event.data;
        
        // Skip if document was deleted
        if (!change.after) {
            console.log(`Gallery ${galleryId} deleted`);
            return null;
        }
        
        const beforeData = change.before ? change.before.data() : null;
        const afterData = change.after.data();
        
        // Skip if this is a new document (not an update)
        if (!beforeData) {
            console.log(`Gallery ${galleryId} created (not an update)`);
            return null;
        }
        
        // Check if status changed to approved
        if (beforeData.status !== 'approved' && afterData.status === 'approved') {
            console.log(`Gallery ${galleryId} approved. Sending notifications...`);
            
            // Get organization ID
            const organizationId = afterData.organizationId || afterData.organizationID;
            if (!organizationId) {
                console.error('No organization ID found for gallery');
                return null;
            }
            
            // Get team members who should be notified
            const notifiableMembers = await getNotifiableTeamMembers(organizationId);
            
            if (notifiableMembers.length === 0) {
                console.log('No team members have notifications enabled');
                return null;
            }
            
            console.log(`Found ${notifiableMembers.length} team members to notify`);
            
            // Prepare gallery details for email
            const galleryDetails = {
                id: galleryId,
                name: afterData.name,
                schoolName: afterData.schoolName,
                totalImages: afterData.totalImages,
                approvedBy: afterData.lastApprovedBy || 'Client',
                approvedDate: new Date().toISOString()
            };
            
            // Send batch emails
            const results = await proofingEmailService.sendBatchProofingApprovalEmails(
                notifiableMembers,
                galleryDetails
            );
            
            // Log the notification event
            await logProofingNotificationActivity(galleryId, notifiableMembers.length, results);
            
            console.log(`Successfully sent ${results.successful} emails, ${results.failed} failed`);
            return {
                success: true,
                sent: results.successful,
                failed: results.failed
            };
        }
        
        return null;
    } catch (error) {
        // Safer error logging
        const errorMessage = error ? (error.message || String(error)) : 'Unknown error';
        const safeGalleryId = galleryId || 'unknown';
        console.error(`Error in onProofGalleryUpdate for gallery ${safeGalleryId}:`, errorMessage);
        if (error && error.stack) {
            console.error('Stack trace:', error.stack);
        }
        // Don't throw error to prevent function retry
        return { error: errorMessage };
    }
});

/**
 * Optional: HTTP endpoint for manual trigger (for testing)
 */
exports.sendProofingApprovalEmailManual = onCall({
    cors: true,
    enforceAppCheck: false,
}, async (request) => {
    try {
        // Validate authentication
        if (!request.auth) {
            throw new Error('Authentication required');
        }
        
        const { galleryId, organizationId } = request.data;
        
        if (!galleryId || !organizationId) {
            throw new Error('Gallery ID and Organization ID are required');
        }
        
        // Get gallery data
        const galleryDoc = await db.collection('proofGalleries')
            .doc(galleryId)
            .get();
        
        if (!galleryDoc.exists) {
            throw new Error('Gallery not found');
        }
        
        const galleryData = galleryDoc.data();
        
        // Get notifiable team members
        const teamMembers = await getNotifiableTeamMembers(organizationId);
        
        if (teamMembers.length === 0) {
            return {
                success: true,
                message: 'No team members have notifications enabled',
                sent: 0
            };
        }
        
        // Send emails
        const results = await proofingEmailService.sendBatchProofingApprovalEmails(
            teamMembers,
            {
                id: galleryId,
                name: galleryData.name,
                schoolName: galleryData.schoolName,
                totalImages: galleryData.totalImages,
                approvedBy: galleryData.lastApprovedBy || 'Client',
                approvedDate: new Date().toISOString()
            }
        );
        
        return {
            success: true,
            message: `Emails sent to ${results.successful} recipients`,
            sent: results.successful,
            failed: results.failed,
            results: results.details
        };
    } catch (error) {
        logger.error('Error in sendProofingApprovalEmailManual:', error);
        throw new Error(`Failed to send approval emails: ${error.message}`);
    }
});

/**
 * Helper function to get team members with notifications enabled
 */
async function getNotifiableTeamMembers(organizationId) {
    try {
        const snapshot = await db.collection('users')
            .where('organizationID', '==', organizationId)
            .where('notifyOnProofingApproval', '==', true)
            .get();
        
        const teamMembers = [];
        snapshot.forEach(doc => {
            const data = doc.data();
            if (data.email) {
                teamMembers.push({
                    id: doc.id,
                    email: data.email,
                    firstName: data.firstName || '',
                    lastName: data.lastName || '',
                    displayName: data.displayName || `${data.firstName} ${data.lastName}`
                });
            }
        });
        
        return teamMembers;
    } catch (error) {
        console.error('Error getting notifiable team members:', error);
        return [];
    }
}

/**
 * Log notification activity to Firestore
 */
async function logProofingNotificationActivity(galleryId, recipientCount, results) {
    try {
        await db.collection('proofActivity').add({
            galleryId,
            action: 'notifications_sent',
            recipientCount,
            successful: results.successful,
            failed: results.failed,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            details: `Sent approval notifications to ${recipientCount} team members`
        });
    } catch (error) {
        console.error('Error logging notification activity:', error);
        // Don't throw - logging shouldn't break the notification flow
    }
}

// Function: Send Photo Critique Notification when new critique is created
exports.onPhotoCritiqueCreated = onDocumentCreated('photoCritiques/{critiqueId}', async (event) => {
    const critique = event.data.data();
    const critiqueId = event.params.critiqueId;
    
    try {
        // Get the target photographer's user document
        const userDoc = await db.collection('users')
            .doc(critique.targetPhotographerId)
            .get();
        
        if (!userDoc.exists) {
            console.log(`Target photographer ${critique.targetPhotographerId} not found`);
            return null;
        }
        
        const userData = userDoc.data();
        const fcmToken = userData?.fcmToken;
        
        if (!fcmToken) {
            console.log(`No FCM token for photographer ${critique.targetPhotographerId}`);
            return null;
        }
        
        // Determine the message based on example type
        const isGoodExample = critique.exampleType === 'example';
        const exampleTypeText = isGoodExample ? 'good example' : 'needs improvement';
        
        // Create the notification message
        const message = {
            notification: {
                title: 'New Training Photo',
                body: `${critique.submitterName} sent you a ${exampleTypeText} photo with feedback`
            },
            data: {
                type: 'photo_critique',
                critiqueId: critiqueId,
                submitterName: critique.submitterName,
                exampleType: critique.exampleType,
                targetPhotographerId: critique.targetPhotographerId,
                targetPhotographerName: critique.targetPhotographerName
            },
            token: fcmToken,
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1
                    }
                }
            }
        };
        
        // Send the notification
        const response = await admin.messaging().send(message);
        console.log(`Photo critique notification sent successfully to ${critique.targetPhotographerName}:`, response);
        
        // Log the notification activity
        await db.collection('notificationLogs').add({
            type: 'photo_critique',
            critiqueId: critiqueId,
            recipientId: critique.targetPhotographerId,
            recipientName: critique.targetPhotographerName,
            submitterName: critique.submitterName,
            exampleType: critique.exampleType,
            fcmToken: fcmToken.substring(0, 10) + '...', // Store partial token for debugging
            status: 'sent',
            response: response,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
        
        return { success: true, messageId: response };
        
    } catch (error) {
        console.error('Error sending photo critique notification:', error);
        
        // Log the error
        await db.collection('notificationLogs').add({
            type: 'photo_critique',
            critiqueId: critiqueId,
            recipientId: critique.targetPhotographerId,
            status: 'error',
            error: error.message,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
        
        return { success: false, error: error.message };
    }
});