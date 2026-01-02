#!/usr/bin/env node

/**
 * Firebase to Supabase Migration Script
 * Migrates sportsJobs collection from Firebase to Supabase tables:
 * - sports_jobs
 * - roster_entries
 * - group_images
 */

const { execSync } = require('child_process');
const { createClient } = require('@supabase/supabase-js');
const { v4: uuidv4, v5: uuidv5 } = require('uuid');

// Supabase configuration
const SUPABASE_URL = 'https://nofegnmrgnanpznavlqy.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

// UUID namespace for deterministic UUID generation from Firebase IDs
const UUID_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'; // DNS namespace

if (!SUPABASE_SERVICE_KEY) {
    console.error('Error: SUPABASE_SERVICE_KEY environment variable is required');
    console.error('Set it with: export SUPABASE_SERVICE_KEY="your-service-role-key"');
    process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

// Convert Firebase document ID to UUID (deterministic)
function firebaseIdToUuid(firebaseId) {
    return uuidv5(firebaseId, UUID_NAMESPACE);
}

// Parse Firebase timestamp to ISO date string
function parseFirebaseTimestamp(timestamp) {
    if (!timestamp) return null;

    // Handle Firestore Timestamp objects
    if (timestamp._seconds !== undefined) {
        return new Date(timestamp._seconds * 1000).toISOString();
    }

    // Handle seconds/nanoseconds format
    if (timestamp.seconds !== undefined) {
        return new Date(timestamp.seconds * 1000).toISOString();
    }

    // Handle ISO string
    if (typeof timestamp === 'string') {
        return new Date(timestamp).toISOString();
    }

    // Handle Date object
    if (timestamp instanceof Date) {
        return timestamp.toISOString();
    }

    return null;
}

// Fetch all documents from Firebase using CLI
async function fetchFirebaseData() {
    console.log('Fetching data from Firebase using CLI...');

    try {
        // Use Firebase CLI to get a list of documents
        // First, let's try using the REST API with the CLI token
        const tokenResult = execSync('firebase login:ci --no-localhost 2>/dev/null || echo "USE_EXISTING"', {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'pipe']
        }).trim();

        let token;
        if (tokenResult === 'USE_EXISTING') {
            // Get token from existing login
            const configPath = require('os').homedir() + '/.config/configstore/firebase-tools.json';
            const fs = require('fs');
            if (fs.existsSync(configPath)) {
                const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
                token = config.tokens?.refresh_token;
            }
        } else {
            token = tokenResult;
        }

        // Use REST API to fetch documents
        const projectId = 'focal-point-c452c';
        const collectionPath = 'sportsJobs';

        const https = require('https');

        return new Promise((resolve, reject) => {
            // First get an access token
            getAccessToken(token).then(accessToken => {
                const options = {
                    hostname: 'firestore.googleapis.com',
                    path: `/v1/projects/${projectId}/databases/(default)/documents/${collectionPath}?pageSize=1000`,
                    method: 'GET',
                    headers: {
                        'Authorization': `Bearer ${accessToken}`
                    }
                };

                const req = https.request(options, (res) => {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => {
                        try {
                            const parsed = JSON.parse(data);
                            if (parsed.error) {
                                reject(new Error(parsed.error.message));
                                return;
                            }
                            resolve(parsed.documents || []);
                        } catch (e) {
                            reject(e);
                        }
                    });
                });

                req.on('error', reject);
                req.end();
            }).catch(reject);
        });
    } catch (error) {
        console.error('Error fetching Firebase data:', error.message);
        throw error;
    }
}

// Get access token from refresh token
function getAccessToken(refreshToken) {
    return new Promise((resolve, reject) => {
        const https = require('https');
        const querystring = require('querystring');

        const postData = querystring.stringify({
            grant_type: 'refresh_token',
            refresh_token: refreshToken,
            client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
            client_secret: ''  // Firebase CLI client secret is empty
        });

        const options = {
            hostname: 'oauth2.googleapis.com',
            path: '/token',
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(postData)
            }
        };

        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const parsed = JSON.parse(data);
                    if (parsed.access_token) {
                        resolve(parsed.access_token);
                    } else {
                        reject(new Error('Failed to get access token: ' + JSON.stringify(parsed)));
                    }
                } catch (e) {
                    reject(e);
                }
            });
        });

        req.on('error', reject);
        req.write(postData);
        req.end();
    });
}

// Convert Firestore REST API document to plain object
function firestoreDocToObject(doc) {
    if (!doc || !doc.fields) return null;

    const result = {};
    const docPath = doc.name.split('/');
    result._id = docPath[docPath.length - 1]; // Get document ID from path

    for (const [key, value] of Object.entries(doc.fields)) {
        result[key] = parseFirestoreValue(value);
    }

    return result;
}

// Parse Firestore value types
function parseFirestoreValue(value) {
    if (value.stringValue !== undefined) return value.stringValue;
    if (value.integerValue !== undefined) return parseInt(value.integerValue);
    if (value.doubleValue !== undefined) return value.doubleValue;
    if (value.booleanValue !== undefined) return value.booleanValue;
    if (value.nullValue !== undefined) return null;
    if (value.timestampValue !== undefined) return value.timestampValue;
    if (value.arrayValue !== undefined) {
        return (value.arrayValue.values || []).map(parseFirestoreValue);
    }
    if (value.mapValue !== undefined) {
        const obj = {};
        for (const [k, v] of Object.entries(value.mapValue.fields || {})) {
            obj[k] = parseFirestoreValue(v);
        }
        return obj;
    }
    return null;
}

// Transform Firebase sportsJob to Supabase sports_jobs format
function transformSportsJob(firebaseDoc) {
    const id = firebaseIdToUuid(firebaseDoc._id);

    return {
        id,
        organization_id: firebaseDoc.organizationID || firebaseDoc.organization_id,
        school_name: firebaseDoc.schoolName || firebaseDoc.school_name || '',
        school_id: firebaseDoc.schoolId || firebaseDoc.school_id || null,
        sport_name: firebaseDoc.sportName || firebaseDoc.sport_name || '',
        season_type: firebaseDoc.seasonType || firebaseDoc.season_type || null,
        shoot_date: parseFirebaseTimestamp(firebaseDoc.shootDate || firebaseDoc.shoot_date),
        location: firebaseDoc.location || '',
        photographer: firebaseDoc.photographer || '',
        additional_notes: firebaseDoc.additionalNotes || firebaseDoc.additional_notes || '',
        session_id: null, // Migrated data won't have session links
        is_archived: firebaseDoc.isArchived === true || firebaseDoc.is_archived === true,
        created_at: parseFirebaseTimestamp(firebaseDoc.createdAt || firebaseDoc.created_at) || new Date().toISOString(),
        updated_at: parseFirebaseTimestamp(firebaseDoc.updatedAt || firebaseDoc.updated_at) || new Date().toISOString()
    };
}

// Transform Firebase roster entry to Supabase roster_entries format
function transformRosterEntry(entry, sportsJobId, sortOrder) {
    const entryId = entry.id ? firebaseIdToUuid(entry.id) : uuidv4();

    return {
        id: entryId,
        sports_job_id: sportsJobId,
        last_name: entry.lastName || entry.last_name || '',
        first_name: entry.firstName || entry.first_name || '', // Maps to Subject ID in new schema
        teacher: entry.teacher || '', // Maps to Special in new schema
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

// Main migration function
async function migrate() {
    console.log('Starting Firebase to Supabase migration...\n');

    try {
        // Fetch all documents from Firebase
        const firebaseDocs = await fetchFirebaseData();
        console.log(`Found ${firebaseDocs.length} sports jobs in Firebase\n`);

        if (firebaseDocs.length === 0) {
            console.log('No documents to migrate.');
            return;
        }

        // Convert to plain objects
        const sportsJobs = firebaseDocs.map(firestoreDocToObject).filter(Boolean);

        // Prepare data for Supabase
        const sportsJobsData = [];
        const rosterEntriesData = [];
        const groupImagesData = [];

        for (const job of sportsJobs) {
            // Transform main job
            const transformedJob = transformSportsJob(job);
            sportsJobsData.push(transformedJob);

            // Transform roster entries
            const roster = job.roster || [];
            roster.forEach((entry, index) => {
                rosterEntriesData.push(transformRosterEntry(entry, transformedJob.id, index));
            });

            // Transform group images
            const groupImages = job.groupImages || [];
            groupImages.forEach((image, index) => {
                groupImagesData.push(transformGroupImage(image, transformedJob.id, index));
            });

            console.log(`Processed: ${job.schoolName || 'Unknown School'} - ${job.sportName || 'No Sport'}`);
            console.log(`  - ${roster.length} roster entries`);
            console.log(`  - ${groupImages.length} group images`);
        }

        console.log('\n--- Migration Summary ---');
        console.log(`Sports Jobs: ${sportsJobsData.length}`);
        console.log(`Roster Entries: ${rosterEntriesData.length}`);
        console.log(`Group Images: ${groupImagesData.length}`);

        // Insert into Supabase
        console.log('\nInserting into Supabase...');

        // Insert sports_jobs
        if (sportsJobsData.length > 0) {
            const { error: jobsError } = await supabase
                .from('sports_jobs')
                .upsert(sportsJobsData, { onConflict: 'id' });

            if (jobsError) {
                console.error('Error inserting sports_jobs:', jobsError);
            } else {
                console.log(`✓ Inserted ${sportsJobsData.length} sports jobs`);
            }
        }

        // Insert roster_entries
        if (rosterEntriesData.length > 0) {
            // Insert in batches of 100
            for (let i = 0; i < rosterEntriesData.length; i += 100) {
                const batch = rosterEntriesData.slice(i, i + 100);
                const { error: rosterError } = await supabase
                    .from('roster_entries')
                    .upsert(batch, { onConflict: 'id' });

                if (rosterError) {
                    console.error(`Error inserting roster_entries batch ${i/100 + 1}:`, rosterError);
                }
            }
            console.log(`✓ Inserted ${rosterEntriesData.length} roster entries`);
        }

        // Insert group_images
        if (groupImagesData.length > 0) {
            // Insert in batches of 100
            for (let i = 0; i < groupImagesData.length; i += 100) {
                const batch = groupImagesData.slice(i, i + 100);
                const { error: imagesError } = await supabase
                    .from('group_images')
                    .upsert(batch, { onConflict: 'id' });

                if (imagesError) {
                    console.error(`Error inserting group_images batch ${i/100 + 1}:`, imagesError);
                }
            }
            console.log(`✓ Inserted ${groupImagesData.length} group images`);
        }

        console.log('\n✅ Migration completed successfully!');

    } catch (error) {
        console.error('\n❌ Migration failed:', error.message);
        process.exit(1);
    }
}

// Run migration
migrate();
