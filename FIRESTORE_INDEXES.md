# Firestore Composite Indexes

This document lists the composite indexes required for the Iconik Employee app.

## Sessions Collection

### Index 1: Organization + Published Status
**Fields:**
- `organizationID` (Ascending)
- `isPublished` (Ascending)

**Purpose:** This index is required for filtering sessions by organization and published status. Without this index, queries that filter by both fields may fail.

**Query Example:**
```
db.collection("sessions")
  .whereField("organizationID", isEqualTo: "org123")
  .whereField("isPublished", isEqualTo: true)
```

**Note:** If you see an error like "The query requires an index", check the Firebase Console error message for a direct link to create the required index.

### Index 2: Organization + Date Range + Published Status
**Fields:**
- `organizationID` (Ascending)
- `date` (Ascending)
- `isPublished` (Ascending)

**Purpose:** This index supports date range queries with published status filtering.

## Creating Indexes

1. Go to the Firebase Console
2. Navigate to Firestore Database > Indexes
3. Click "Create Index" 
4. Add the fields as specified above
5. Wait for the index to finish building (can take several minutes)

Alternatively, if you encounter a missing index error in the app, the error message will include a direct link to create the required index.