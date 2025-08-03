const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest, onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// Initialize admin (only once)
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

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