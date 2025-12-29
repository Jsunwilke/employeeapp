# Migration Lessons Learned

## Phase 5 Failures - What Went Wrong

During the Phase 5 migration (Templates & Daily Job Reports), several critical issues were missed that broke functionality. This document captures the lessons learned to prevent repeating these mistakes.

---

## The Mistakes

### 1. Mechanical Replacement Without Flow Tracing
**What happened:** Replaced Firestore calls with Supabase service calls without tracing the full execution path.

**Example:** In `MyJobReportsView.swift`, the code was:
```swift
.onAppear {
    if let currentUserId = UserManager.shared.getCurrentUserIDUnified() {
        userId = currentUserId  // Set here
    }
    loadReports()  // Called immediately - but userId is still nil!
}
```
The `loadReports()` function checks `guard let userId = userId` which fails because the state update hasn't propagated yet.

**Lesson:** Always trace the execution flow: UI event → state changes → function calls → async operations → UI updates.

### 2. Assumed Existing Code Was Correct
**What happened:** The race condition with `userId` existed before the migration, but wasn't caught during review.

**Lesson:** When migrating code, don't assume the existing logic is correct. Review the flow as if writing it fresh.

### 3. Checklist Mentality
**What happened:** Focused on "update file X, update file Y" without verifying each file actually worked end-to-end.

**Lesson:** Each file update should be verified as a complete unit, not just syntactically correct.

### 4. Didn't Verify Integration Points
**What happened:** Checked that services existed (TeamService, SessionService, SchoolService) but didn't verify the actual calls in views were passing correct parameters and handling responses.

**Lesson:** For each service call, verify:
- Correct parameters are passed
- Parameters have valid values at call time
- Response is properly handled
- UI is updated on MainActor

---

## Pre-Migration Checklist

Before updating any file during a migration:

### 1. Trace Data Flow
- [ ] Where does the data come from? (user input, service call, etc.)
- [ ] What state variables are involved?
- [ ] When are state variables initialized vs when are they used?
- [ ] Is there a race condition between state setting and usage?

### 2. Verify State Initialization Order
- [ ] When is `userId` set? Before or after it's used?
- [ ] When is `organizationID` set? Before or after it's used?
- [ ] Are there any `guard let` statements that could fail due to timing?

### 3. Check Async Flow
- [ ] Does the async call happen at the right time?
- [ ] Is the response handled on MainActor for UI updates?
- [ ] Are errors properly caught and displayed to user?
- [ ] Is there loading state feedback?

### 4. Verify Service Calls
- [ ] Is the correct service method being called?
- [ ] Are all required parameters available and non-nil?
- [ ] Does the response type match what the view expects?
- [ ] Are JSONB arrays being decoded correctly?

### 5. Test Mental Execution
Step through the code line by line:
1. View appears
2. onAppear runs
3. State is set (or not?)
4. Function is called
5. Guard statements pass (or fail?)
6. Async call is made
7. Response is received
8. UI is updated

---

## Common Pitfalls

### SwiftUI State Timing
```swift
// WRONG - userId is nil when loadData() runs
.onAppear {
    userId = getCurrentUserId()
    loadData()  // userId state hasn't updated yet!
}

// RIGHT - use Task to ensure state is set first
.onAppear {
    userId = getCurrentUserId()
}
.onChange(of: userId) { newValue in
    if newValue != nil {
        loadData()
    }
}

// OR - pass userId directly instead of relying on state
.onAppear {
    if let currentUserId = getCurrentUserId() {
        loadData(userId: currentUserId)
    }
}
```

### Silent Failures
```swift
// WRONG - fails silently
guard let userId = userId else {
    print("No user ID")  // User sees nothing
    return
}

// RIGHT - show error to user
guard let userId = userId else {
    errorMessage = "Unable to load: not signed in"
    return
}
```

### Missing Loading States
```swift
// WRONG - no feedback during load
func loadReports() {
    Task {
        reports = try await service.getReports()
    }
}

// RIGHT - show loading state
func loadReports() {
    isLoading = true
    Task {
        defer { isLoading = false }
        do {
            reports = try await service.getReports()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

---

## Quality Over Speed

**IMPORTANT:** It is better to take extra time to verify each file works correctly than to rush through updates and create broken functionality.

For each file:
1. Read the entire file first
2. Understand the current flow
3. Identify all integration points
4. Make changes carefully
5. Mentally trace execution after changes
6. Verify no race conditions exist

---

## When Updating Views That Load Data

Always verify these questions:

1. **What data does this view need?**
2. **Where does each piece of data come from?**
3. **When is each piece of data available?**
4. **What happens if data is missing?**
5. **Does the user see feedback during loading?**
6. **Does the user see errors if something fails?**

---

## Supabase Model NULL Handling

### The Problem
When decoding Supabase responses, if ANY non-optional field in your Swift model has a NULL value in the database, the entire decode fails silently.

**Example - This will fail if ANY user has NULL last_name:**
```swift
struct TeamMember: Codable {
    let id: String
    let first_name: String
    let last_name: String  // NOT optional - decode fails if NULL!
    let role: String       // NOT optional - decode fails if NULL!
}
```

**Fix - Make potentially-NULL fields optional:**
```swift
struct TeamMember: Codable {
    let id: String
    let first_name: String
    let last_name: String?  // Optional - NULL values decoded as nil
    let role: String?       // Optional - NULL values decoded as nil

    // Computed property to handle nil
    var fullName: String {
        if let lastName = last_name, !lastName.isEmpty {
            return "\(first_name) \(lastName)"
        }
        return first_name
    }
}
```

### Pre-Migration Model Checklist

Before using any Codable model with Supabase:

1. **Check the database schema** - Which columns allow NULL?
2. **Mark nullable fields as optional** - Use `String?`, `Bool?`, `Date?`, etc.
3. **Add computed properties** - Handle nil values with defaults
4. **Test with production data** - Some users might have incomplete profiles

### Common Fields That May Be NULL

- `last_name` - Not everyone has a last name on record
- `role` - Might not be set initially
- `display_name` - Often optional
- `phone` - Users may not provide
- `photo_url` - Users may not upload photos
- `notes` - Optional text fields
- `updated_at` - May be NULL before first update
