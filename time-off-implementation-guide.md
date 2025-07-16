# Time Off Request System - Implementation Guide for iOS

## Overview
The Time Off Request system allows photographers to request time off and managers to approve/deny these requests. Both pending and approved time off appear on the schedule calendar with distinct visual styling for easy identification and interaction.

## Key Features (Updated)
- ✅ **Real-time notifications**: Badge shows pending count with live updates
- ✅ **Calendar integration**: Both pending and approved requests visible on calendar
- ✅ **Visual distinction**: 
  - **Pending**: Dotted blue border, transparent background
  - **Approved Partial Day**: Orange diagonal stripes
  - **Approved Full Day**: Gray diagonal stripes
- ✅ **Interactive calendar**: Click time off entries to view details/cancel/delete
- ✅ **Partial day support**: Time range selection with proper validation
- ✅ **Permission-based actions**: Users can manage their own requests, admins can manage all

## Firestore Collection Structure

### Collection: `timeOffRequests`

#### Document Structure
```json
{
  "id": "auto-generated-document-id",
  "organizationID": "string",
  "photographerId": "string", 
  "photographerName": "string",
  "photographerEmail": "string",
  "startDate": "timestamp",
  "endDate": "timestamp", 
  "reason": "string",
  "notes": "string (optional)",
  "status": "pending | approved | denied | cancelled",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  
  // Partial day fields (only present when isPartialDay is true)
  "isPartialDay": "boolean (optional, default: false)",
  "startTime": "string (format: 'HH:MM', only when isPartialDay is true)",
  "endTime": "string (format: 'HH:MM', only when isPartialDay is true)",
  
  // Approval fields (only present when approved)
  "approvedBy": "string",
  "approverName": "string", 
  "approvedAt": "timestamp",
  
  // Denial fields (only present when denied)
  "deniedBy": "string",
  "denierName": "string",
  "deniedAt": "timestamp",
  "denialReason": "string"
}
```

#### Field Descriptions
- **organizationID**: Links request to specific organization
- **photographerId**: User ID of person requesting time off
- **photographerName**: Display name for UI purposes
- **photographerEmail**: Contact information
- **startDate**: First day of time off (inclusive)
- **endDate**: Last day of time off (inclusive) - same as startDate for partial day requests
- **reason**: Predefined reasons (see enum below)
- **notes**: Optional additional information
- **status**: Current state of the request
- **isPartialDay**: Boolean flag indicating if this is a partial day request
- **startTime**: Time when partial day time off begins (format: "HH:MM")
- **endTime**: Time when partial day time off ends (format: "HH:MM")
- **createdAt/updatedAt**: Audit timestamps

#### Reason Enum Values
- "Vacation"
- "Sick Leave"
- "Personal Day"
- "Family Emergency"
- "Medical Appointment"
- "Other"

#### Status Enum Values
- "pending" - Awaiting manager approval
- "approved" - Manager approved the request
- "denied" - Manager denied the request
- "cancelled" - Photographer cancelled their own request

## Security Rules

```javascript
// Time Off Requests collection rules
match /timeOffRequests/{requestId} {
  // Read: All users in organization can see requests
  allow read: if request.auth != null && 
                 belongsToSameOrg(request.auth.uid, resource.data.organizationID);
  
  // Create: Users can only create their own requests
  allow create: if request.auth != null && 
                   request.auth.uid == request.resource.data.photographerId &&
                   belongsToSameOrg(request.auth.uid, request.resource.data.organizationID) &&
                   request.resource.data.status == 'pending';
  
  // Update: Users can edit their pending requests, managers can approve/deny
  allow update: if request.auth != null && 
                   belongsToSameOrg(request.auth.uid, resource.data.organizationID) &&
                   (
                     // Users can update their own pending requests
                     (request.auth.uid == resource.data.photographerId && 
                      resource.data.status == 'pending') ||
                     // Managers can approve/deny
                     isAdminOrManager(request.auth.uid)
                   );
  
  // Delete: Only admins
  allow delete: if request.auth != null && 
                   isAdmin(request.auth.uid) &&
                   belongsToSameOrg(request.auth.uid, resource.data.organizationID);
}
```

## User Workflows

### 1. Photographer Requesting Time Off

#### UI Flow:
1. User taps "Request Time Off" button
2. Modal/screen appears with form fields:
   - Start Date (date picker, minimum: today)
   - End Date (date picker, minimum: start date) - *hidden when partial day is checked*
   - **Partial Day Toggle** (checkbox: "Partial day only (specify time range)")
   - **Time Range Fields** (shown only when partial day is checked):
     - Start Time (time picker)
     - End Time (time picker)
   - Reason (dropdown with predefined options)
   - Notes (optional text field)
3. **Partial Day Logic**:
   - When partial day is checked, end date automatically matches start date
   - Time fields become required
   - End time must be after start time
4. System checks for conflicts with existing sessions
5. If conflicts exist, show warning but allow submission
6. User taps "Submit Request"
7. Request is saved with status "pending"

#### API Calls:
```javascript
// Create new request (with partial day support)
const requestData = {
  organizationID: user.organizationID,
  photographerId: user.id,
  photographerName: `${user.firstName} ${user.lastName}`,
  photographerEmail: user.email,
  startDate: new Date(startDate),
  endDate: isPartialDay ? new Date(startDate) : new Date(endDate), // Same date for partial day
  reason: selectedReason,
  notes: notesText,
  status: 'pending',
  isPartialDay: isPartialDay,
  // Only include time fields for partial day requests
  ...(isPartialDay && {
    startTime: startTime, // Format: "09:00"
    endTime: endTime       // Format: "12:00"
  }),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp()
};

await addDoc(collection(firestore, 'timeOffRequests'), requestData);
```

#### Conflict Detection:
```javascript
// Check for existing sessions during time off period
const conflictQuery = query(
  collection(firestore, 'sessions'),
  where('organizationID', '==', organizationID),
  where('photographers', 'array-contains', { id: photographerId })
);
// Filter results by date range in client code
```

### 2. Manager Approval/Denial

#### UI Flow:
1. Manager sees badge notification with pending count
2. Taps "Time Off" button to open approval screen
3. Screen shows two tabs:
   - **Pending**: List of requests awaiting approval
   - **History**: Past approved/denied requests
4. For each pending request, manager sees:
   - Photographer name and email
   - Date range and duration
   - Reason and notes
   - Approve/Deny buttons
5. For approval: Single tap approves immediately
6. For denial: Tap opens dialog requiring denial reason

#### API Calls:
```javascript
// Approve request
await updateDoc(doc(firestore, 'timeOffRequests', requestId), {
  status: 'approved',
  approvedBy: managerId,
  approverName: `${manager.firstName} ${manager.lastName}`,
  approvedAt: serverTimestamp(),
  updatedAt: serverTimestamp()
});

// Deny request
await updateDoc(doc(firestore, 'timeOffRequests', requestId), {
  status: 'denied',
  deniedBy: managerId,
  denierName: `${manager.firstName} ${manager.lastName}`,
  deniedAt: serverTimestamp(),
  denialReason: denialText,
  updatedAt: serverTimestamp()
});
```

### 3. Calendar Integration

#### Display Logic:
- **Show both pending and approved time off** on calendar with different visual styling
- **Pending requests**: Dotted border outline with transparent background (clickable for cancellation)
- **Approved requests**: Filled with distinctive patterns (clickable for details/deletion)
- **Approved partial day**: Orange diagonal stripes
- **Approved full day**: Gray diagonal stripes
- Time off blocks should be **clickable** but not draggable
- Show for date range: startDate through endDate (inclusive)

#### Data Fetching:
```javascript
// Get all time off for calendar date range (pending + approved)
const timeOffQuery = query(
  collection(firestore, 'timeOffRequests'),
  where('organizationID', '==', organizationID),
  where('status', 'in', ['pending', 'approved']), // Include both statuses
  where('startDate', '<=', dateRangeEnd),
  where('endDate', '>=', dateRangeStart)
);

// Real-time listener for automatic updates
const timeOffListener = onSnapshot(timeOffQuery, (snapshot) => {
  const requests = snapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data()
  }));
  updateCalendarTimeOff(requests);
});
```

#### Calendar Entry Format:
```javascript
// Convert time off to calendar entries with proper status and styling info
const timeOffEntries = timeOffRequests.map(request => {
  const entries = [];
  const currentDate = new Date(request.startDate);
  const endDate = new Date(request.endDate);
  
  while (currentDate <= endDate) {
    // Create title with time info for partial day requests
    const title = request.isPartialDay 
      ? `Time Off: ${request.reason} (${formatTime(request.startTime)} - ${formatTime(request.endTime)})`
      : `Time Off: ${request.reason}`;
    
    entries.push({
      id: `timeoff-${request.id}-${currentDate.toISOString().split('T')[0]}`,
      sessionId: request.id, // For operations like cancel/delete
      title: title,
      date: currentDate.toISOString().split('T')[0],
      startTime: request.isPartialDay ? request.startTime : '09:00',
      endTime: request.isPartialDay ? request.endTime : '17:00',
      photographerId: request.photographerId,
      photographerName: request.photographerName,
      sessionType: 'timeoff',
      status: request.status, // CRITICAL: Pass actual status for styling
      isTimeOff: true,
      isPartialDay: request.isPartialDay || false,
      reason: request.reason,
      notes: request.notes
    });
    
    currentDate.setDate(currentDate.getDate() + 1);
  }
  
  return entries;
}).flat();
```

#### Visual Styling Guide:
```javascript
// Apply different styles based on status and type
const getTimeOffStyle = (timeOffEntry) => {
  const baseStyle = {
    padding: 4,
    borderRadius: 4,
    marginBottom: 4,
    fontSize: 12,
    cursor: 'pointer', // Clickable for interaction
    transition: 'all 0.15s ease',
    opacity: 0.8
  };

  if (timeOffEntry.status === 'pending') {
    // Pending: Dotted border, transparent background
    return {
      ...baseStyle,
      backgroundColor: 'transparent',
      border: '2px dashed #007bff',
      color: '#007bff',
      fontWeight: '500'
    };
  } else if (timeOffEntry.status === 'approved') {
    // Approved: Filled with patterns
    if (timeOffEntry.isPartialDay) {
      // Partial day: Orange stripes
      return {
        ...baseStyle,
        backgroundColor: '#fff4e6',
        backgroundImage: 'repeating-linear-gradient(45deg, #fff4e6, #fff4e6 8px, #ffe0b3 8px, #ffe0b3 16px)',
        border: '1px solid #ff9800',
        color: '#e65100'
      };
    } else {
      // Full day: Gray stripes
      return {
        ...baseStyle,
        backgroundColor: '#e0e0e0',
        backgroundImage: 'repeating-linear-gradient(45deg, #e0e0e0, #e0e0e0 10px, #d0d0d0 10px, #d0d0d0 20px)',
        border: '1px solid #bbb',
        color: '#666'
      };
    }
  }
};
```

#### Time Off Interaction Handling:
```javascript
// Handle time off entry clicks
const handleTimeOffClick = (timeOffEntry) => {
  // Show details modal with different actions based on status
  if (timeOffEntry.status === 'pending') {
    showTimeOffDetailsModal(timeOffEntry, {
      allowCancel: canModifyRequest(timeOffEntry),
      primaryAction: 'cancel',
      primaryActionText: 'Cancel Request',
      primaryActionColor: 'warning'
    });
  } else if (timeOffEntry.status === 'approved') {
    showTimeOffDetailsModal(timeOffEntry, {
      allowDelete: canModifyRequest(timeOffEntry),
      primaryAction: 'delete',
      primaryActionText: 'Delete Time Off',
      primaryActionColor: 'danger'
    });
  }
};

// Permission check for time off modifications
const canModifyRequest = (timeOffEntry) => {
  const isOwnRequest = timeOffEntry.photographerId === currentUser.id;
  const isAdmin = ['admin', 'manager', 'owner'].includes(currentUser.role);
  return isOwnRequest || isAdmin;
};

// Cancel pending request
const cancelTimeOffRequest = async (requestId) => {
  await updateDoc(doc(firestore, 'timeOffRequests', requestId), {
    status: 'cancelled',
    cancelledAt: serverTimestamp(),
    updatedAt: serverTimestamp()
  });
};

// Delete approved request (sets to cancelled)
const deleteTimeOffRequest = async (requestId) => {
  await cancelTimeOffRequest(requestId); // Same operation
};
```

#### Time Off Details Modal:
```javascript
// Modal content for time off details
const TimeOffDetailsModal = ({ timeOffEntry, permissions, onClose, onAction }) => {
  return (
    <Modal>
      <Header>
        <Title>Time Off Details</Title>
        <StatusBadge status={timeOffEntry.status} />
      </Header>
      
      <Body>
        <DetailRow icon="calendar">
          <Label>Date</Label>
          <Value>{formatDate(timeOffEntry.date)}</Value>
        </DetailRow>
        
        {timeOffEntry.isPartialDay && (
          <DetailRow icon="clock">
            <Label>Time Range</Label>
            <Value>{formatTime(timeOffEntry.startTime)} - {formatTime(timeOffEntry.endTime)}</Value>
          </DetailRow>
        )}
        
        <DetailRow icon="user">
          <Label>Photographer</Label>
          <Value>{timeOffEntry.photographerName}</Value>
        </DetailRow>
        
        <DetailRow icon="file-text">
          <Label>Reason</Label>
          <Value>{timeOffEntry.reason}</Value>
        </DetailRow>
        
        {timeOffEntry.notes && (
          <DetailRow icon="file-text">
            <Label>Notes</Label>
            <Value>{timeOffEntry.notes}</Value>
          </DetailRow>
        )}
        
        <TypeBadge isPartialDay={timeOffEntry.isPartialDay} />
      </Body>
      
      <Footer>
        <SecondaryButton onPress={onClose}>Close</SecondaryButton>
        {permissions.allowCancel && timeOffEntry.status === 'pending' && (
          <WarningButton onPress={() => onAction('cancel')}>
            Cancel Request
          </WarningButton>
        )}
        {permissions.allowDelete && timeOffEntry.status === 'approved' && (
          <DangerButton onPress={() => onAction('delete')}>
            Delete Time Off
          </DangerButton>
        )}
      </Footer>
    </Modal>
  );
};
```

## Real-time Updates

### Firestore Listeners
Set up listeners for real-time updates:

```javascript
// Listen for all time off requests in organization
const timeOffListener = onSnapshot(
  query(
    collection(firestore, 'timeOffRequests'),
    where('organizationID', '==', organizationID)
  ),
  (snapshot) => {
    const requests = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    // Update all time off data
    updateAllTimeOffRequests(requests);
    
    // Update pending count for notification badge (real-time)
    const pendingCount = requests.filter(r => r.status === 'pending').length;
    updatePendingBadge(pendingCount);
    
    // Filter and update calendar display
    const calendarRequests = filterTimeOffForCalendar(requests, currentDateRange);
    updateCalendarTimeOff(calendarRequests);
    
    // Update approval modal if open
    if (isApprovalModalOpen) {
      updateApprovalModalData(requests);
    }
  },
  (error) => {
    console.error('Time off listener error:', error);
    // Handle connection errors gracefully
  }
);

// Filter time off for current calendar view
const filterTimeOffForCalendar = (allRequests, dateRange) => {
  return allRequests.filter(request => {
    // Show pending and approved requests on calendar
    if (!['pending', 'approved'].includes(request.status)) return false;
    
    const startDate = request.startDate.toDate ? request.startDate.toDate() : new Date(request.startDate);
    const endDate = request.endDate.toDate ? request.endDate.toDate() : new Date(request.endDate);
    
    // Check if request overlaps with visible date range
    return startDate <= dateRange.end && endDate >= dateRange.start;
  });
};
```

## User Permissions

### Role-Based Access:
- **All Users**: Can read time off requests in their organization
- **Photographers**: Can create and edit their own pending requests
- **Managers/Admins**: Can approve/deny any request in their organization
- **Admins Only**: Can delete requests

### Permission Checks:
```javascript
// Check if user can approve/deny requests
const canManageRequests = user.role === 'admin' || 
                         user.role === 'manager' || 
                         user.role === 'owner';

// Check if user can edit a specific request
const canEditRequest = request.photographerId === user.id && 
                      request.status === 'pending';
```

## UI Components Needed

### 1. Time Off Request Form
- Date pickers for start/end dates
- Dropdown for reason selection
- Text field for notes
- Conflict warning display
- Submit/cancel buttons

### 2. Manager Approval Screen
- Tab interface (Pending/History)
- Request cards with photographer info
- Approve/deny action buttons
- Denial reason dialog

### 3. Calendar Integration
- Visual distinction for time off blocks
- Non-interactive time off entries
- Tooltip/detail view for time off info

### 4. Notification Badge
- Show pending count for managers
- Update in real-time
- Clear visual indicator

## Error Handling

### Common Scenarios:
1. **Date Validation**: Start date cannot be in the past, end date must be after start date
2. **Conflict Warnings**: Show if sessions are scheduled during requested time off
3. **Permission Errors**: Handle unauthorized approval attempts
4. **Network Errors**: Offline handling and retry logic
5. **Validation Errors**: Required field validation

### Error Messages:
- "Start date cannot be in the past"
- "End date must be after start date"
- "Please provide a reason for your time off request"
- "You have X scheduled sessions during this period. Your manager will need to reassign these if approved."
- "Only managers can approve time off requests"

## Testing Scenarios

### Basic Functionality:
1. Create time off request with valid data
2. Approve request as manager
3. Deny request with reason
4. Cancel own pending request
5. View approved time off on calendar

### Edge Cases:
1. Single day time off request
2. Multi-week time off spanning months
3. Overlapping time off requests
4. Time off during scheduled sessions
5. Weekend/holiday time off requests

### Permission Testing:
1. Non-manager attempting to approve
2. Editing approved/denied requests
3. Cross-organization access attempts
4. Unauthenticated requests

## Performance Considerations

### Optimization Tips:
1. **Pagination**: For organizations with many requests, implement pagination
2. **Date Range Filtering**: Only fetch requests within visible calendar range
3. **Caching**: Cache approved time off for calendar display
4. **Batch Operations**: Group multiple approvals/denials when possible
5. **Offline Support**: Cache pending requests for offline viewing

### Firestore Limits:
- Maximum 500 documents per query (implement pagination if needed)
- Real-time listeners count toward connection limits
- Consider composite indexes for complex queries

This implementation guide should provide all the necessary information to implement the time off request system in your iOS app, maintaining consistency with the web version's functionality and data structure.