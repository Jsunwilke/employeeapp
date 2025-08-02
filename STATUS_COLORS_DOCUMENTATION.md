# Iconik Status Colors Documentation

## Overview
This document defines the standardized color scheme for SD Card and Job Box statuses across all Iconik platforms (iOS and Web).

## SD Card Status Colors

| Status | Hex Code | RGB | SwiftUI Color | Description |
|--------|----------|-----|---------------|-------------|
| **Job Box** | `#FF9500` | rgb(255, 149, 0) | Orange | Card is in a job box |
| **Camera** | `#34C759` | rgb(52, 199, 89) | Green | Card is in camera |
| **Envelope** | `#FFCC00` | rgb(255, 204, 0) | Yellow | Card is in envelope |
| **Uploaded** | `#007AFF` | rgb(0, 122, 255) | Blue | Card data has been uploaded |
| **Cleared** | `#8E8E93` | rgb(142, 142, 147) | Gray | Card has been cleared |
| **Camera Bag** | `#AF52DE` | rgb(175, 82, 222) | Purple | Card is in camera bag |
| **Personal** | `#5856D6` | rgb(88, 86, 214) | Indigo | Personal use |

## Job Box Status Colors

| Status | Hex Code | RGB | SwiftUI Color | Description |
|--------|----------|-----|---------------|-------------|
| **Packed** | `#007AFF` | rgb(0, 122, 255) | Blue | Job box is packed |
| **Picked Up** | `#34C759` | rgb(52, 199, 89) | Green | Job box has been picked up |
| **Left Job** | `#FF9500` | rgb(255, 149, 0) | Orange | Job box has left the job |
| **Turned In** | `#8E8E93` | rgb(142, 142, 147) | Gray | Job box has been turned in |

## Implementation Examples

### iOS (SwiftUI)
```swift
// Using the StatusColors struct
Circle()
    .fill(StatusColors.color(for: "job box"))

// For job boxes
Circle()
    .fill(StatusColors.color(for: "packed", isJobBox: true))
```

### Web (CSS)
```css
/* SD Card Status Colors */
.status-job-box { background-color: #FF9500; }
.status-camera { background-color: #34C759; }
.status-envelope { background-color: #FFCC00; }
.status-uploaded { background-color: #007AFF; }
.status-cleared { background-color: #8E8E93; }
.status-camera-bag { background-color: #AF52DE; }
.status-personal { background-color: #5856D6; }

/* Job Box Status Colors */
.status-packed { background-color: #007AFF; }
.status-picked-up { background-color: #34C759; }
.status-left-job { background-color: #FF9500; }
.status-turned-in { background-color: #8E8E93; }
```

### Web (JavaScript/React)
```javascript
const StatusColors = {
    sdCard: {
        "job box": "#FF9500",
        "camera": "#34C759",
        "envelope": "#FFCC00",
        "uploaded": "#007AFF",
        "cleared": "#8E8E93",
        "camera bag": "#AF52DE",
        "personal": "#5856D6"
    },
    jobBox: {
        "packed": "#007AFF",
        "picked up": "#34C759",
        "left job": "#FF9500",
        "turned in": "#8E8E93"
    }
};

// Usage
const getStatusColor = (status, isJobBox = false) => {
    const colors = isJobBox ? StatusColors.jobBox : StatusColors.sdCard;
    return colors[status.toLowerCase()] || "#8E8E93";
};
```

## Design Rationale

1. **Consistency**: Same colors used across all platforms and views
2. **Accessibility**: Colors chosen for good contrast and visibility
3. **Meaningful**: Colors relate to status meaning (e.g., green for completed/picked up)
4. **System Colors**: Based on Apple's system colors for better iOS integration

## Notes
- Always use lowercase status names when looking up colors
- Default to gray (#8E8E93) if status is not found
- These colors should be used in all statistics, charts, and status indicators