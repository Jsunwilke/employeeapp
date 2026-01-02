#!/usr/bin/env node

/**
 * Step 2: Import sportsJobs data to Supabase
 * Reads from firebase-export.json and inserts into:
 * - sports_jobs
 * - roster_entries
 * - group_images
 */

const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');
const { v4: uuidv4, v5: uuidv5 } = require('uuid');

// Supabase configuration
const SUPABASE_URL = 'https://nofegnmrgnanpznavlqy.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

// UUID namespace for deterministic UUID generation from Firebase IDs
const UUID_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

if (!SUPABASE_SERVICE_KEY) {
    console.error('Error: SUPABASE_SERVICE_KEY environment variable is required');
    console.error('');
    console.error('Get it from: https://supabase.com/dashboard/project/nofegnmrgnanpznavlqy/settings/api');
    console.error('Look for "service_role" key under "Project API keys"');
    console.error('');
    console.error('Then run: export SUPABASE_SERVICE_KEY="your-key-here"');
    process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

// Convert Firebase document ID to UUID (deterministic)
function firebaseIdToUuid(firebaseId) {
    if (!firebaseId) return uuidv4();
    return uuidv5(firebaseId, UUID_NAMESPACE);
}

// Parse timestamp to ISO date string
function parseTimestamp(timestamp) {
    if (!timestamp) return null;

    // Handle ISO string
    if (typeof timestamp === 'string') {
        const date = new Date(timestamp);
        return isNaN(date.getTime()) ? null : date.toISOString();
    }

    // Handle Firestore Timestamp objects
    if (timestamp._seconds !== undefined) {
        return new Date(timestamp._seconds * 1000).toISOString();
    }

    if (timestamp.seconds !== undefined) {
        return new Date(timestamp.seconds * 1000).toISOString();
    }

    return null;
}

// Transform Firebase sportsJob to Supabase sports_jobs format
function transformSportsJob(firebaseDoc) {
    const id = firebaseIdToUuid(firebaseDoc._id);

    return {
        id,
        organization_id: firebaseDoc.organizationID || firebaseDoc.organization_id || '',
        school_name: firebaseDoc.schoolName || firebaseDoc.school_name || '',
        school_id: firebaseDoc.schoolId || firebaseDoc.school_id || null,
        sport_name: firebaseDoc.sportName || firebaseDoc.sport_name || '',
        season_type: firebaseDoc.seasonType || firebaseDoc.season_type || null,
        shoot_date: parseTimestamp(firebaseDoc.shootDate || firebaseDoc.shoot_date),
        location: firebaseDoc.location || '',
        photographer: firebaseDoc.photographer || '',
        additional_notes: firebaseDoc.additionalNotes || firebaseDoc.additional_notes || '',
        session_id: null,
        is_archived: firebaseDoc.isArchived === true || firebaseDoc.is_archived === true,
        created_at: parseTimestamp(firebaseDoc.createdAt || firebaseDoc.created_at) || new Date().toISOString(),
        updated_at: parseTimestamp(firebaseDoc.updatedAt || firebaseDoc.updated_at) || new Date().toISOString()
    };
}

// Transform Firebase roster entry to Supabase roster_entries format
function transformRosterEntry(entry, sportsJobId, sortOrder) {
    const entryId = entry.id ? firebaseIdToUuid(entry.id) : uuidv4();

    return {
        id: entryId,
        sports_job_id: sportsJobId,
        last_name: entry.lastName || entry.last_name || '',
        first_name: entry.firstName || entry.first_name || '',
        teacher: entry.teacher || '',
        group_name: entry.group || entry.group_name || '',
        email: entry.email || null,
        phone: entry.phone || null,
        image_numbers: entry.imageNumbers || entry.image_numbers || '',
        notes: entry.notes || '',
        sort_order: sortOrder,
        version: 1,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
    };
}

// Transform Firebase group image to Supabase group_images format
function transformGroupImage(image, sportsJobId, sortOrder) {
    const imageId = image.id ? firebaseIdToUuid(image.id) : uuidv4();

    return {
        id: imageId,
        sports_job_id: sportsJobId,
        description: image.description || '',
        image_numbers: image.imageNumbers || image.image_numbers || '',
        notes: image.notes || '',
        sport: image.sport || null,
        gender: image.gender || null,
        team_level: image.teamLevel || image.team_level || null,
        sort_order: sortOrder,
        version: 1,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
    };
}

// Insert data in batches with retry
async function batchInsert(tableName, data, batchSize = 50) {
    let inserted = 0;
    let errors = 0;

    for (let i = 0; i < data.length; i += batchSize) {
        const batch = data.slice(i, i + batchSize);

        try {
            const { error } = await supabase
                .from(tableName)
                .upsert(batch, { onConflict: 'id' });

            if (error) {
                console.error(`  Error in batch ${Math.floor(i/batchSize) + 1}:`, error.message);
                errors += batch.length;
            } else {
                inserted += batch.length;
            }
        } catch (e) {
            console.error(`  Exception in batch ${Math.floor(i/batchSize) + 1}:`, e.message);
            errors += batch.length;
        }

        // Progress indicator
        if ((i + batchSize) % 200 === 0 || i + batchSize >= data.length) {
            console.log(`  Progress: ${Math.min(i + batchSize, data.length)}/${data.length}`);
        }
    }

    return { inserted, errors };
}

async function main() {
    console.log('Supabase Import Script');
    console.log('======================\n');

    // Read exported data
    const exportPath = path.join(__dirname, 'firebase-export.json');

    if (!fs.existsSync(exportPath)) {
        console.error('Error: firebase-export.json not found');
        console.error('Run "node export-firebase.js" first');
        process.exit(1);
    }

    console.log('Reading firebase-export.json...');
    const jobs = JSON.parse(fs.readFileSync(exportPath, 'utf8'));
    console.log(`Found ${jobs.length} sports jobs to import\n`);

    // Prepare data
    const sportsJobsData = [];
    const rosterEntriesData = [];
    const groupImagesData = [];

    for (const job of jobs) {
        const transformedJob = transformSportsJob(job);
        sportsJobsData.push(transformedJob);

        const roster = job.roster || [];
        roster.forEach((entry, index) => {
            rosterEntriesData.push(transformRosterEntry(entry, transformedJob.id, index));
        });

        const groupImages = job.groupImages || [];
        groupImages.forEach((image, index) => {
            groupImagesData.push(transformGroupImage(image, transformedJob.id, index));
        });
    }

    console.log('Data prepared:');
    console.log(`  - ${sportsJobsData.length} sports jobs`);
    console.log(`  - ${rosterEntriesData.length} roster entries`);
    console.log(`  - ${groupImagesData.length} group images\n`);

    // Insert sports_jobs first (parent table)
    console.log('Inserting sports_jobs...');
    const jobsResult = await batchInsert('sports_jobs', sportsJobsData);
    console.log(`  ✓ Inserted: ${jobsResult.inserted}, Errors: ${jobsResult.errors}\n`);

    // Insert roster_entries
    console.log('Inserting roster_entries...');
    const rosterResult = await batchInsert('roster_entries', rosterEntriesData);
    console.log(`  ✓ Inserted: ${rosterResult.inserted}, Errors: ${rosterResult.errors}\n`);

    // Insert group_images
    console.log('Inserting group_images...');
    const imagesResult = await batchInsert('group_images', groupImagesData);
    console.log(`  ✓ Inserted: ${imagesResult.inserted}, Errors: ${imagesResult.errors}\n`);

    // Summary
    console.log('=== Migration Complete ===');
    console.log(`Sports Jobs: ${jobsResult.inserted} inserted, ${jobsResult.errors} errors`);
    console.log(`Roster Entries: ${rosterResult.inserted} inserted, ${rosterResult.errors} errors`);
    console.log(`Group Images: ${imagesResult.inserted} inserted, ${imagesResult.errors} errors`);

    if (jobsResult.errors + rosterResult.errors + imagesResult.errors === 0) {
        console.log('\n✅ All data migrated successfully!');
    } else {
        console.log('\n⚠️  Some records had errors. Check the output above.');
    }
}

main().catch(console.error);
