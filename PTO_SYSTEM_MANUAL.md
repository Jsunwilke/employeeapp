# PTO System Implementation Manual for iOS App

## Table of Contents
1. [System Overview](#system-overview)
2. [Data Models](#data-models)
3. [Firebase Collections](#firebase-collections)
4. [Core Functionality](#core-functionality)
5. [API Endpoints](#api-endpoints)
6. [User Workflows](#user-workflows)
7. [UI Components](#ui-components)
8. [Business Logic](#business-logic)
9. [Implementation Checklist](#implementation-checklist)

---

## System Overview

The PTO (Paid Time Off) system is a comprehensive time-off management solution integrated into the photography studio management platform. It handles:

- **PTO Balance Tracking**: Automatic accrual based on hours worked
- **Time Off Requests**: Employee-initiated requests with approval workflow
- **Calendar Integration**: Visual display of approved time off on schedule
- **Conflict Detection**: Automatic checking for session conflicts
- **Admin Management**: Balance adjustments and policy configuration

### Key Features
- ✅ Automatic PTO accrual based on hours worked
- ✅ Request submission with approval workflow
- ✅ Real-time balance tracking
- ✅ Session conflict detection
- ✅ Manager approval/denial system
- ✅ Calendar integration with visual indicators
- ✅ Banking system for excess PTO
- ✅ Year-end rollover policies

---

## Data Models

### PTO Balance Document
```javascript
// Collection: ptoBalances
// Document ID: {organizationID}_{userId}
{
  id: "org123_user456",
  userId: "user456",
  organizationID: "org123",
  totalBalance: 64.5,        // Current available PTO hours
  pendingBalance: 16,        // Hours reserved for pending requests
  usedThisYear: 24,         // Hours used in current year
  bankingBalance: 8,        // Excess hours over max accrual
  processedPeriods: ["2024-01", "2024-02"], // Processed pay periods
  createdAt: Timestamp,
  lastUpdated: Timestamp
}
```

### Time Off Request Document
```javascript
// Collection: timeOffRequests
{
  id: "request789",
  organizationID: "org123",
  photographerId: "user456",
  photographerName: "John Smith",
  startDate: Timestamp,     // Start date of time off
  endDate: Timestamp,       // End date of time off
  reason: "Vacation",       // Employee-provided reason
  notes: "Family trip to Hawaii",
  status: "pending",        // pending, under_review, approved, denied, cancelled
  isPartialDay: false,      // Full day vs partial day
  startTime: "09:00",       // For partial days
  endTime: "17:00",         // For partial days
  isPaidTimeOff: true,      // Whether using PTO balance
  ptoHoursRequested: 16,    // PTO hours to deduct
  
  // Approval workflow fields
  approvedBy: "admin123",
  approverName: "Jane Manager",
  approvedAt: Timestamp,
  deniedBy: null,
  denierName: null,
  deniedAt: null,
  denialReason: null,
  reviewedBy: null,
  reviewerName: null,
  reviewedAt: null,
  
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### PTO Settings (in Organization Document)
```javascript
// Part of organization document
{
  ptoSettings: {
    enabled: true,
    accrualRate: 1,          // Hours earned per accrual period
    accrualPeriod: 40,       // Hours worked to earn PTO
    maxAccrual: 240,         // Maximum PTO hours (30 days)
    rolloverPolicy: "limited", // none, limited, unlimited
    rolloverLimit: 80,       // Max hours to rollover (if limited)
    yearlyAllotment: 0,      // Yearly grant (alternative to accrual)
    bankingEnabled: true,    // Allow banking excess hours
    maxBanking: 40          // Maximum banking hours
  }
}
```

---

## Firebase Collections

### Primary Collections
1. **`ptoBalances`** - User PTO balance records
2. **`timeOffRequests`** - Time off request submissions
3. **`organizations`** - Contains PTO settings
4. **`sessions`** - Used for conflict detection
5. **`timeEntries`** - Used for PTO accrual calculations

### Security Rules
```javascript
// Firestore Security Rules (abbreviated)
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // PTO Balances - users can read own, admins can modify
    match /ptoBalances/{balanceId} {
      allow read: if request.auth != null && 
        (resource.data.userId == request.auth.uid || isAdmin());
      allow write: if request.auth != null && isAdmin();
    }
    
    // Time Off Requests - users can CRUD own, admins can approve/deny
    match /timeOffRequests/{requestId} {
      allow read: if request.auth != null && 
        (resource.data.photographerId == request.auth.uid || isAdmin());
      allow create: if request.auth != null && 
        request.resource.data.photographerId == request.auth.uid;
      allow update: if request.auth != null && 
        (resource.data.photographerId == request.auth.uid || isAdmin());
    }
  }
}
```

---

## Core Functionality

### 1. PTO Accrual System

**Automatic Accrual Logic:**
```javascript
// Example: 1 hour PTO per 40 hours worked
const hoursWorked = 40;
const accrualRate = 1;      // From organization settings
const accrualPeriod = 40;   // From organization settings
const maxAccrual = 240;     // From organization settings

const ptoEarned = (hoursWorked / accrualPeriod) * accrualRate;
const newBalance = Math.min(currentBalance + ptoEarned, maxAccrual);

// Excess goes to banking if enabled
const excess = currentBalance + ptoEarned - maxAccrual;
const bankingAmount = excess > 0 ? excess : 0;
```

**Key Functions:**
- `getPTOBalance(userId, organizationID)` - Get current balance
- `addPTOHours(userId, organizationID, hours, reason)` - Manual adjustment
- `calculateProjectedPTO(balance, settings, hours, periods)` - Future projection

### 2. Time Off Request Workflow

**Request Lifecycle:**
1. **Pending** → Employee submits request
2. **Under Review** → Manager reviewing (optional)
3. **Approved** → Manager approves, PTO deducted
4. **Denied** → Manager denies, PTO released
5. **Cancelled** → Employee cancels, PTO released

**Conflict Detection:**
```javascript
// Check for existing sessions during requested dates
const conflicts = await checkTimeOffConflicts(
  organizationId, 
  photographerId, 
  startDate, 
  endDate
);

// Returns array of conflicting sessions
if (conflicts.length > 0) {
  // Show warning to user
  // Allow override for emergencies
}
```

### 3. PTO Reservation System

**Reserve → Use → Release Pattern:**
```javascript
// When request is submitted
await reservePTOHours(userId, organizationID, hoursRequested);

// When request is approved
await usePTOHours(userId, organizationID, hoursRequested);

// When request is denied/cancelled
await releasePTOHours(userId, organizationID, hoursRequested);
```

---

## API Endpoints

### PTO Balance Management

#### Get PTO Balance
```javascript
// Function: getPTOBalance
// Parameters: userId, organizationID
// Returns: PTO balance object
// Cache: Uses ptoCacheService for performance

const balance = await getPTOBalance(userProfile.id, organization.id);
```

#### Add PTO Hours (Admin Only)
```javascript
// Function: addPTOHours
// Parameters: userId, organizationID, hours, reason
// Returns: Updated balance
// Side Effects: Clears cache

const newBalance = await addPTOHours(
  "user123", 
  "org456", 
  8, 
  "Holiday bonus"
);
```

### Time Off Request Management

#### Create Time Off Request
```javascript
// Function: createTimeOffRequest
// Parameters: requestData object
// Returns: Created request with ID
// Side Effects: Reserves PTO hours if isPaidTimeOff

const request = await createTimeOffRequest({
  organizationID: organization.id,
  photographerId: userProfile.id,
  photographerName: userProfile.firstName,
  startDate: new Date("2024-03-15"),
  endDate: new Date("2024-03-16"),
  reason: "Vacation",
  notes: "Spring break trip",
  isPaidTimeOff: true,
  ptoHoursRequested: 16
});
```

#### Get Time Off Requests
```javascript
// Function: getTimeOffRequests
// Parameters: organizationId, filters (optional)
// Returns: Array of requests
// Cache: Uses timeOffCacheService

// Get all requests
const allRequests = await getTimeOffRequests(organization.id);

// Get filtered requests
const pendingRequests = await getTimeOffRequests(organization.id, {
  status: "pending"
});
```

#### Approve/Deny Requests (Admin Only)
```javascript
// Approve request
const approved = await approveTimeOffRequest(
  requestId, 
  adminId, 
  adminName
);

// Deny request
const denied = await denyTimeOffRequest(
  requestId, 
  adminId, 
  adminName, 
  "Insufficient coverage"
);
```

---

## User Workflows

### 1. Employee Submitting Time Off Request

**Step-by-Step Process:**
1. **Open Time Off Modal**
   - From calendar or dashboard
   - Shows current PTO balance

2. **Fill Request Details**
   - Select date range
   - Choose full/partial day
   - Enter reason and notes
   - Specify if using PTO

3. **Conflict Check**
   - System checks for session conflicts
   - Shows warnings if conflicts found
   - Allows emergency override

4. **Submit Request**
   - PTO hours reserved from balance
   - Request enters "pending" status
   - Manager notification sent

5. **Track Status**
   - View in requests list
   - Receive notifications on status changes

### 2. Manager Approving Requests

**Approval Workflow:**
1. **View Pending Requests**
   - Dashboard shows pending count
   - Access approval modal from calendar or list

2. **Review Request Details**
   - Employee info and dates
   - Reason and notes
   - Session conflicts highlighted
   - Coverage implications

3. **Make Decision**
   - Approve: PTO deducted, calendar updated
   - Deny: PTO released, denial reason required
   - Under Review: Mark for further consideration

4. **Notification**
   - Employee notified of decision
   - Calendar automatically updated

### 3. Viewing PTO Balance

**Balance Display:**
- Current available hours
- Hours pending approval
- Hours used this year
- Banking balance (if applicable)
- Projected balance based on scheduled hours

---

## UI Components

### 1. PTO Balance Widget (Dashboard)
```swift
// iOS Implementation Concept
struct PTOBalanceView: View {
    @State private var ptoBalance: PTOBalance?
    @State private var loading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                Text("PTO Balance")
                    .font(.headline)
            }
            
            if let balance = ptoBalance {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(balance.totalBalance, specifier: "%.1f")")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("hours available")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Banking: \(balance.bankingBalance)")
                        Spacer()
                        Text("Used: \(balance.usedThisYear)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
```

### 2. Time Off Request Form
```swift
struct TimeOffRequestForm: View {
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var reason = ""
    @State private var notes = ""
    @State private var isPartialDay = false
    @State private var isPaidTimeOff = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Request Details") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    
                    TextField("Reason", text: $reason)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
                
                Section("Options") {
                    Toggle("Partial Day", isOn: $isPartialDay)
                    Toggle("Use PTO Balance", isOn: $isPaidTimeOff)
                }
                
                Section("Summary") {
                    HStack {
                        Text("Days Requested:")
                        Spacer()
                        Text("\(calculateDays())")
                    }
                    
                    if isPaidTimeOff {
                        HStack {
                            Text("PTO Hours:")
                            Spacer()
                            Text("\(calculatePTOHours())")
                        }
                    }
                }
            }
            .navigationTitle("Request Time Off")
            .navigationBarItems(
                leading: Button("Cancel") { /* dismiss */ },
                trailing: Button("Submit") { /* submit request */ }
            )
        }
    }
}
```

### 3. Calendar Integration
```swift
// Display time off on calendar
struct CalendarDayView: View {
    let date: Date
    let sessions: [Session]
    let timeOffEntries: [TimeOffEntry]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Regular sessions
            ForEach(sessions) { session in
                SessionRowView(session: session)
            }
            
            // Time off entries
            ForEach(timeOffEntries) { timeOff in
                HStack {
                    Image(systemName: "person.fill.xmark")
                        .foregroundColor(.orange)
                    Text(timeOff.photographerName)
                    Spacer()
                    Text(timeOff.status.uppercased())
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(timeOff.status))
                        .cornerRadius(4)
                }
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "approved": return .green
        case "pending": return .orange
        case "denied": return .red
        default: return .gray
        }
    }
}
```

---

## Business Logic

### 1. Accrual Calculation
```javascript
/**
 * Calculate PTO accrual based on hours worked
 * Standard: 1 hour PTO per 40 hours worked
 * Max accrual: 240 hours (30 days)
 * Banking: Excess hours saved separately
 */
function calculatePTOAccrual(hoursWorked, settings, currentBalance) {
  const { accrualRate, accrualPeriod, maxAccrual, bankingEnabled, maxBanking } = settings;
  
  // Calculate earned PTO
  const ptoEarned = (hoursWorked / accrualPeriod) * accrualRate;
  
  // Apply to balance with cap
  const potentialBalance = currentBalance + ptoEarned;
  const newBalance = Math.min(potentialBalance, maxAccrual);
  
  // Handle banking if enabled
  let bankingHours = 0;
  if (bankingEnabled && potentialBalance > maxAccrual) {
    bankingHours = Math.min(potentialBalance - maxAccrual, maxBanking);
  }
  
  return {
    newBalance,
    bankingHours,
    ptoEarned
  };
}
```

### 2. Conflict Detection
```javascript
/**
 * Check for scheduling conflicts when requesting time off
 * Returns conflicts that require manager attention
 */
async function detectTimeOffConflicts(photographerId, startDate, endDate, organizationId) {
  // Query sessions for photographer in date range
  const sessions = await getSessionsForPhotographer(
    photographerId, 
    startDate, 
    endDate, 
    organizationId
  );
  
  const conflicts = sessions.filter(session => {
    const sessionDate = session.date;
    return sessionDate >= startDate && sessionDate <= endDate && !session.isTimeOff;
  });
  
  return conflicts.map(session => ({
    sessionId: session.id,
    date: session.date,
    schoolName: session.schoolName,
    sessionType: session.sessionType,
    startTime: session.startTime,
    endTime: session.endTime,
    severity: calculateConflictSeverity(session)
  }));
}

function calculateConflictSeverity(session) {
  // High priority sessions (e.g., yearbook deadlines)
  if (session.sessionType === 'yearbook' || session.priority === 'high') {
    return 'high';
  }
  // Regular sessions
  return 'medium';
}
```

### 3. Approval Logic
```javascript
/**
 * Business rules for automatic approval/denial
 * Can be customized per organization
 */
function shouldAutoApprove(request, ptoBalance, conflicts) {
  // Never auto-approve if insufficient PTO balance
  if (request.isPaidTimeOff && ptoBalance.totalBalance < request.ptoHoursRequested) {
    return { autoApprove: false, reason: 'Insufficient PTO balance' };
  }
  
  // Never auto-approve if high-priority conflicts
  const highPriorityConflicts = conflicts.filter(c => c.severity === 'high');
  if (highPriorityConflicts.length > 0) {
    return { autoApprove: false, reason: 'High priority session conflicts' };
  }
  
  // Auto-approve single days with sufficient balance and no conflicts
  const requestDays = calculateDaysBetween(request.startDate, request.endDate);
  if (requestDays === 1 && conflicts.length === 0 && ptoBalance.totalBalance >= request.ptoHoursRequested) {
    return { autoApprove: true, reason: 'Single day with no conflicts' };
  }
  
  // Default to manual approval
  return { autoApprove: false, reason: 'Requires manager review' };
}
```

---

## Implementation Checklist

### Phase 1: Core Data Models
- [ ] Create PTO Balance model/struct
- [ ] Create Time Off Request model/struct  
- [ ] Create PTO Settings model/struct
- [ ] Implement Firestore document mapping
- [ ] Add input validation and error handling

### Phase 2: Firebase Integration
- [ ] Implement PTO balance Firebase queries
- [ ] Implement time off request CRUD operations
- [ ] Add real-time listeners for balance updates
- [ ] Add real-time listeners for request status changes
- [ ] Implement caching layer for performance

### Phase 3: Business Logic
- [ ] Implement PTO accrual calculations
- [ ] Add conflict detection logic
- [ ] Create approval workflow engine
- [ ] Add PTO reservation/release system
- [ ] Implement balance validation

### Phase 4: UI Components
- [ ] Build PTO balance display widget
- [ ] Create time off request form
- [ ] Implement calendar integration
- [ ] Add request approval interface (admin)
- [ ] Create request history/status view

### Phase 5: User Workflows
- [ ] Employee request submission flow
- [ ] Manager approval workflow
- [ ] Balance viewing and tracking
- [ ] Calendar conflict visualization
- [ ] Notification system integration

### Phase 6: Testing & Optimization
- [ ] Unit tests for business logic
- [ ] Integration tests with Firebase
- [ ] UI testing for all workflows
- [ ] Performance optimization
- [ ] Edge case handling

---

## Technical Notes

### Caching Strategy
The web app uses a sophisticated caching system to minimize Firebase reads:
- **PTO Balances**: Cached per organization with 4-hour expiration
- **Time Off Requests**: Cached per user and organization
- **Cache Invalidation**: Automatic on data updates

### Performance Considerations
- Use predictable document IDs: `{organizationID}_{userId}`
- Batch operations where possible
- Implement optimistic updates for better UX
- Use pagination for large request lists

### Security Best Practices
- Validate all user inputs
- Enforce proper access controls via Firestore rules
- Log all admin actions for audit trail
- Encrypt sensitive data in transit and at rest

### Error Handling
- Network connectivity issues
- Firebase quota/rate limiting
- Invalid date ranges
- Insufficient permissions
- Data validation failures

This manual provides the foundation for implementing the PTO system in your iOS app. The system is designed to be robust, scalable, and user-friendly while maintaining data integrity and security.