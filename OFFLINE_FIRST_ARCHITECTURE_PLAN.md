# Enterprise-Grade Offline-First Architecture for iOS Sports Shoot

**Goal:** Implement Instagram/Google Photos-level offline reliability with local-first architecture, pending sync queue, and conflict resolution.

---

## Architecture Overview

**Principle:** ALL data operations happen locally first. Server sync is background concern.

**Components to Build:**
1. **Local Cache Layer** (CoreData/SQLite) - Source of truth
2. **Pending Sync Queue** - Tracks unsynced changes
3. **Background Sync Service** - Retries failed syncs
4. **Conflict Resolver** - Handles multi-user edits
5. **Auto-Caching** - Opening shoot = automatic offline availability

---

## Phase 1: Local-First Data Layer (Week 1)

### 1.1 CoreData Schema
**New File:** `SportsShootDataModel.xcdatamodeld`

**Entities:**
- `CachedShoot` - Replaces JSON file cache
  - id, title, location, date, status, roster (relationship)
  - lastSyncedAt, modifiedAt, isFullyCached
- `CachedRosterEntry` - Individual roster entries
  - id, shootId, firstName, lastName, grade, imageNumbers
  - modifiedAt, isSynced
- `PendingChange` - Queue of unsynced edits
  - id, shootId, entryId, changeType (update/create/delete)
  - changeData (JSON), attemptCount, lastAttemptAt
  - createdAt, priority

**Migration:** Convert existing JSON cache to CoreData on app launch

### 1.2 Local Repository Layer
**New File:** `LocalSportsShootRepository.swift`

**Methods:**
```swift
class LocalSportsShootRepository {
    // CRUD operations - all synchronous, instant
    func saveShoot(_ shoot: SportsShoot) -> Bool
    func getShoot(id: String) -> SportsShoot?
    func updateRosterEntry(shootId: String, entry: RosterEntry) -> Bool
    func deleteShoot(id: String) -> Bool

    // Sync tracking
    func markAsSynced(shootId: String)
    func getShoots(needingSync: Bool) -> [SportsShoot]

    // Download status
    func isFullyCached(shootId: String) -> Bool
    func markFullyCached(shootId: String)
}
```

**Key:** All UI operations use LocalRepository. No direct Firestore calls.

---

## Phase 2: Pending Sync Queue (Week 1)

### 2.1 Pending Changes Manager
**New File:** `PendingSyncManager.swift`

**Responsibilities:**
- Track all edits made while offline
- Queue changes with retry logic
- Persist queue to CoreData (survives app restart)

**Methods:**
```swift
class PendingSyncManager {
    func queueChange(
        shootId: String,
        entryId: String,
        changeType: ChangeType,
        data: [String: Any]
    )

    func getPendingChanges(for shootId: String) -> [PendingChange]
    func removePendingChange(id: String)
    func retryFailedChanges()

    // Status
    var hasPendingChanges: Bool
    var pendingChangeCount: Int
}

enum ChangeType {
    case updateEntry
    case createEntry
    case deleteEntry
    case updateShootMetadata
}
```

### 2.2 Edit Flow (New Pattern)
```swift
// OLD (current broken approach):
SportsShootService.updateRosterEntry() → Firestore → Cache

// NEW (local-first):
User edits → LocalRepository.updateRosterEntry() → UI updates instantly
          → PendingSyncManager.queueChange()
          → BackgroundSyncService syncs when online
```

---

## Phase 3: Background Sync Service (Week 2)

### 3.1 Sync Service
**New File:** `BackgroundSyncService.swift`

**Features:**
- Monitors network status
- Processes pending queue when online
- Exponential backoff on failures
- Batch syncing for efficiency
- Conflict detection

**Methods:**
```swift
class BackgroundSyncService {
    static let shared = BackgroundSyncService()

    func startMonitoring()
    func syncNow() async
    private func processPendingQueue() async
    private func syncShoot(_ shoot: SportsShoot) async -> SyncResult
    private func syncRosterEntry(_ change: PendingChange) async -> SyncResult

    // State
    var isSyncing: Bool
    var lastSyncAt: Date?
    var failedSyncCount: Int
}

enum SyncResult {
    case success
    case conflict(serverVersion: RosterEntry)
    case failure(error: Error, shouldRetry: Bool)
}
```

### 3.2 Sync Strategy
**Order:**
1. Sync shoot metadata first
2. Sync roster entries in order of modification
3. Mark synced in CoreData
4. Remove from pending queue
5. Notify UI of sync status

**Retry Logic:**
- Attempt 1: Immediate
- Attempt 2: After 5 seconds
- Attempt 3: After 30 seconds
- Attempt 4+: After 5 minutes
- Max 10 attempts before manual intervention required

---

## Phase 4: Conflict Resolution (Week 2)

### 4.1 Conflict Detector
**New File:** `ConflictResolver.swift`

**Scenarios:**
1. **Same field edited by multiple users**
   - Strategy: Last-write-wins with timestamp
   - Show warning: "Someone else modified this entry"

2. **Entry deleted remotely but edited locally**
   - Strategy: Recreate with local changes
   - Show warning: "Entry was deleted, recreating"

3. **Shoot archived remotely but edited locally**
   - Strategy: Block sync, require user decision
   - Show error: "Shoot archived, cannot sync changes"

**Methods:**
```swift
class ConflictResolver {
    func detectConflict(
        local: RosterEntry,
        remote: RosterEntry
    ) -> ConflictType?

    func resolveConflict(
        _ conflict: ConflictType,
        strategy: ResolutionStrategy
    ) -> RosterEntry
}

enum ConflictType {
    case bothModified(local: RosterEntry, remote: RosterEntry)
    case deletedRemotely(local: RosterEntry)
    case shootArchived
}

enum ResolutionStrategy {
    case keepLocal
    case keepRemote
    case merge
    case askUser
}
```

### 4.2 Conflict UI
**Show conflict banner:**
- "Sync conflict detected for [Entry Name]"
- Options: Keep My Changes / Use Server Version / Review

---

## Phase 5: Auto-Caching on Open (Week 3)

### 5.1 Opening a Shoot = Automatic Download
**Principle:** No separate "Download" button - opening a shoot automatically caches it for offline use.

**Implementation in SportsShootDetailView:**

**Scenario 1: Online + First Time Opening**
```swift
1. User taps shoot in list
2. Fetch from Firestore
3. Show "Loading shoot..." (1-2 seconds)
4. Cache to CoreData automatically
5. Show shoot detail view
6. ✅ Now available offline for future opens
```

**Scenario 2: Online + Previously Opened**
```swift
1. Load from CoreData instantly (no spinner!)
2. Background: Fetch latest from Firestore
3. If updates found → re-cache, refresh UI
4. ✅ Fast and stays up-to-date
```

**Scenario 3: Offline + Previously Opened**
```swift
1. Load from CoreData instantly
2. ✅ Works perfectly, all edits save to queue
3. Show "📡 Offline" indicator
```

**Scenario 4: Offline + Never Opened Before** ⚠️
```swift
1. Check CoreData → not found
2. Try Firestore → no network
3. ❌ Show error alert:

   "Shoot Not Available Offline"
   "This shoot hasn't been downloaded yet.
    Please connect to the internet to open it."

   [OK]
```

### 5.2 Shoot List Offline Indicators
**Add visual feedback to shoot list:**

```swift
// In SportsShootListView row
HStack {
    Text(shoot.title)
    Spacer()
    if localRepo.isFullyCached(shootId: shoot.id) {
        Image(systemName: "arrow.down.circle.fill")
            .foregroundColor(.green)
            .help("Available offline")
    }
}
```

**Visual feedback:**
- ✓ Green download icon = Can open offline
- No icon = Must be online to open first time

### 5.3 Smart Pre-caching (Background)
**Auto-cache in background when on WiFi:**
- Active shoots (status: in-progress)
- Shoots for today/tomorrow
- Recent shoots (last 7 days)

**Background download:**
- Download when on WiFi only
- Low priority queue
- Cancel if storage low
- User never sees this - happens automatically

---

## Phase 6: UI/UX Enhancements (Week 3)

### 6.1 Sync Status Indicator
**Add to SportsShootDetailView:**
```swift
// Top bar status
HStack {
    if syncService.hasPendingChanges {
        Label("2 pending changes", systemImage: "arrow.clockwise")
            .foregroundColor(.orange)
    } else if syncService.isSyncing {
        ProgressView()
        Text("Syncing...")
    } else if isOfflineMode {
        Label("Offline", systemImage: "wifi.slash")
            .foregroundColor(.gray)
    } else {
        Label("Synced", systemImage: "checkmark.circle")
            .foregroundColor(.green)
    }
}
```

### 6.2 Loading States
**On shoot open:**
```swift
func loadShoot(id: String) {
    // Try local cache first
    if let cachedShoot = localRepo.getShoot(id: id) {
        // Load instantly from cache (no spinner!)
        self.shoot = cachedShoot

        // If online, fetch updates in background
        if isOnline {
            fetchAndUpdateFromFirestore(id)
        }
    } else {
        // Not in cache - must fetch from Firestore
        if !isOnline {
            // Show error: "Shoot Not Available Offline"
            showOfflineError()
            return
        }

        // Show "Loading shoot..."
        isLoading = true
        fetchFromFirestore(id) { shoot in
            // Cache it automatically
            localRepo.saveShoot(shoot)
            localRepo.markFullyCached(shootId: id)
            self.shoot = shoot
            isLoading = false
        }
    }
}
```

**Instant edits:**
- No loading spinners on edits
- Optimistic UI updates (edit shows immediately)
- Background sync indicator only
- Cache saves synchronously (instant)

### 6.3 Error Handling
**User-visible errors:**
- **"Shoot Not Available Offline"** - Shoot never opened before, no network
- "Unable to sync. Will retry automatically." - Sync failed, queued for retry
- "Sync conflict detected. Tap to review." - Conflict needs user resolution
- "Storage full. Cannot cache shoot." - Device storage issue

**Eliminated errors:**
- ❌ "Shoot not found in cache" - Never happens with new architecture
- ❌ "Failed to save" - All saves are local-first, always succeed

---

## Implementation Files

### New Files to Create:
1. `SportsShootDataModel.xcdatamodeld` - CoreData schema
2. `LocalSportsShootRepository.swift` - Local data layer
3. `PendingSyncManager.swift` - Sync queue
4. `BackgroundSyncService.swift` - Background sync
5. `ConflictResolver.swift` - Conflict handling
6. `SyncStatusView.swift` - UI components (sync indicator, offline error alert)

### Files to Modify:
1. `SportsShootDetailView.swift`
   - Use LocalRepository instead of SportsShootService
   - Add sync status UI (optional)
   - Remove network checks from edit flow
   - Auto-cache shoot on open
   - Show offline error if not cached

2. `SportsShootListView.swift`
   - Add offline availability indicator (green download icon)
   - Show which shoots are available offline

3. `SportsShootModel.swift`
   - Keep Firestore methods for sync service only
   - Add sync completion handlers
   - Remove direct UI calls

4. `OfflineManager.swift`
   - Deprecated (replaced by LocalRepository)
   - Migration code to CoreData

5. `AppDelegate.swift` / `App.swift`
   - Initialize BackgroundSyncService
   - Register background tasks
   - Migration on first launch

---

## UI/UX Changes Summary

### Minimal UI Additions (All Optional):

**1. Shoot List View - Offline Indicator**
- Green download icon next to cached shoots
- Shows users which shoots work offline
- Non-intrusive, minimal visual change

**2. Shoot Detail View - Sync Status** (Optional)
- Small indicator at top: "✓ Synced" / "⟳ Syncing..." / "📡 Offline"
- Can be hidden if preferred
- Informational only

**3. Offline Error Alert**
- Only appears when trying to open uncached shoot while offline
- Standard iOS alert with clear message

**No Changes to Core Edit UX:**
- Roster entry editing stays exactly the same
- Image number fields work identically
- No new buttons or complicated UI
- Just works better behind the scenes

---

## Testing Checklist

**Offline Mode:**
- [ ] Open shoot while online → works, auto-caches
- [ ] Reopen same shoot while offline → loads instantly from cache
- [ ] Edit entries while offline → saves to cache, queues for sync
- [ ] Force quit app, reopen offline → changes persist
- [ ] Multiple edits queue up properly
- [ ] Try to open new (uncached) shoot while offline → shows error alert
- [ ] Network returns → all queued changes sync automatically
- [ ] No "Shoot not found in cache" errors

**Sync:**
- [ ] Changes sync in background
- [ ] Retry on failure
- [ ] Batch sync multiple changes
- [ ] Sync status visible in UI

**Conflicts:**
- [ ] Two users edit same entry - last-write-wins
- [ ] Entry deleted remotely - recreates with local changes
- [ ] Proper warnings shown

**Download:**
- [ ] Can pre-download shoots
- [ ] Works offline after download
- [ ] Progress tracking accurate

**Edge Cases:**
- [ ] Storage full - graceful error
- [ ] Network dies mid-sync - queues properly
- [ ] App killed during sync - resumes on restart

---

## Migration Strategy

**Phase 1-2 (Weeks 1-2):** Can deploy incrementally
- CoreData + LocalRepo works alongside existing code
- Feature flag: `useOfflineFirstArchitecture`
- Test with beta users

**Phase 3-4 (Week 2-3):** Background sync is additive
- Doesn't break existing functionality
- Gradually roll out

**Phase 5-6 (Week 3-4):** Polish and optimization
- Can ship without this if needed

**Rollback Plan:** Feature flag allows instant disable

---

## Success Metrics

**Before:**
- "Shoot not found in cache" errors
- Lost edits when offline
- Slow edit responsiveness

**After:**
- 0 cache errors
- 100% edit retention
- Instant UI updates
- Background sync success rate >95%

---

## Estimated Timeline

**Total:** 3-4 weeks for full implementation
**Effort:** 1 senior iOS developer full-time

### Week-by-Week Breakdown:
- **Week 1:** Phase 1-2 (CoreData, LocalRepository, PendingSyncManager)
- **Week 2:** Phase 3-4 (BackgroundSyncService, ConflictResolver)
- **Week 3:** Phase 5-6 (OfflineDownloadManager, UI/UX)
- **Week 4:** Testing, polish, bug fixes

---

## Current Issue Root Cause

**Error:** "Shoot not found in cache"

**Why it happens:**
1. Shoot loads from Firestore (line 358 in SportsShootModel.swift)
2. Cache write happens asynchronously: `OfflineManager.shared.cacheShoot(sportsShoot) { _ in }`
3. Completion returns immediately (doesn't wait for cache)
4. User goes offline before cache write completes
5. No cached copy exists
6. Edit attempt fails with "Shoot not found in cache"

**This architecture eliminates that issue:**
- All data always in CoreData
- No "fire and forget" async caching
- Local-first means cache is always up-to-date
- No dependency on network timing
