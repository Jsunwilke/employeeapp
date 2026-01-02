#!/usr/bin/env node

/**
 * Step 1: Export sportsJobs from Firebase using CLI authentication
 * Saves to firebase-export.json
 */

const https = require('https');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT_ID = 'focal-point-c452c';
const COLLECTION = 'sportsJobs';

// Get Firebase CLI access token (already stored from login)
function getFirebaseAccessToken() {
    const configPath = path.join(os.homedir(), '.config/configstore/firebase-tools.json');

    if (!fs.existsSync(configPath)) {
        throw new Error('Firebase CLI not configured. Run "firebase login" first.');
    }

    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

    if (!config.tokens || !config.tokens.access_token) {
        throw new Error('No Firebase access token found. Run "firebase login" first.');
    }

    // Check if token might be expired
    const expiresAt = config.tokens.expires_at || 0;
    if (expiresAt < Date.now()) {
        console.log('Note: Access token may be expired. Run "firebase login --reauth" if you get auth errors.');
    }

    return config.tokens.access_token;
}

// Fetch documents from Firestore REST API (with pagination)
async function fetchDocuments(accessToken, pageToken = null) {
    return new Promise((resolve, reject) => {
        let path = `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${COLLECTION}?pageSize=300`;
        if (pageToken) {
            path += `&pageToken=${encodeURIComponent(pageToken)}`;
        }

        const options = {
            hostname: 'firestore.googleapis.com',
            path,
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
                        reject(new Error(parsed.error.message || JSON.stringify(parsed.error)));
                        return;
                    }
                    resolve({
                        documents: parsed.documents || [],
                        nextPageToken: parsed.nextPageToken
                    });
                } catch (e) {
                    reject(new Error('Failed to parse response: ' + data.substring(0, 500)));
                }
            });
        });

        req.on('error', reject);
        req.end();
    });
}

// Parse Firestore value types to plain JS values
function parseFirestoreValue(value) {
    if (!value) return null;
    if (value.stringValue !== undefined) return value.stringValue;
    if (value.integerValue !== undefined) return parseInt(value.integerValue, 10);
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

// Convert Firestore REST document to plain object
function documentToObject(doc) {
    if (!doc || !doc.fields) return null;

    const result = {};

    // Extract document ID from path
    const docPath = doc.name.split('/');
    result._id = docPath[docPath.length - 1];

    for (const [key, value] of Object.entries(doc.fields)) {
        result[key] = parseFirestoreValue(value);
    }

    return result;
}

async function main() {
    console.log('Firebase Export Script');
    console.log('======================\n');

    try {
        // Get Firebase CLI access token (already stored from login)
        console.log('Reading Firebase CLI credentials...');
        const accessToken = getFirebaseAccessToken();
        console.log('✓ Using stored access token\n');

        // Fetch all documents with pagination
        console.log(`Fetching documents from ${COLLECTION}...`);
        let allDocuments = [];
        let pageToken = null;
        let pageNum = 1;

        do {
            const result = await fetchDocuments(accessToken, pageToken);
            allDocuments = allDocuments.concat(result.documents);
            console.log(`  Page ${pageNum}: ${result.documents.length} documents`);
            pageToken = result.nextPageToken;
            pageNum++;
        } while (pageToken);

        console.log(`\n✓ Fetched ${allDocuments.length} total documents\n`);

        // Convert to plain objects
        const jobs = allDocuments.map(documentToObject).filter(Boolean);

        // Log summary
        let totalRoster = 0;
        let totalGroupImages = 0;

        for (const job of jobs) {
            const rosterCount = (job.roster || []).length;
            const groupCount = (job.groupImages || []).length;
            totalRoster += rosterCount;
            totalGroupImages += groupCount;
            console.log(`  ${job.schoolName || 'Unknown'} - ${job.sportName || 'No Sport'}: ${rosterCount} roster, ${groupCount} groups`);
        }

        console.log('\n--- Summary ---');
        console.log(`Sports Jobs: ${jobs.length}`);
        console.log(`Total Roster Entries: ${totalRoster}`);
        console.log(`Total Group Images: ${totalGroupImages}`);

        // Save to file
        const outputPath = path.join(__dirname, 'firebase-export.json');
        fs.writeFileSync(outputPath, JSON.stringify(jobs, null, 2));
        console.log(`\n✓ Saved to: ${outputPath}`);
        console.log('\nNext step: Run "npm run import" with your Supabase service key');

    } catch (error) {
        console.error('\n❌ Error:', error.message);
        process.exit(1);
    }
}

main();
