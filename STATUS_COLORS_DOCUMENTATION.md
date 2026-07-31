# Iconik status colours — the iOS↔web contract

Last settled: **2026-07-30** (operator ruling, AMB.11 batch-4 sitting).

Two vocabularies, one contract each. Both are shared with the web app: a change
on either side is a cross-client change, not a style choice.

## Job box statuses

| Status | Hex | Note |
|---|---|---|
| **Packed** | `#6B7FD7` | calm periwinkle |
| **Picked Up** | `#0B8BA8` | teal |
| **Left Job** | `#F09A2B` | amber |
| **Turned In** | `#31A15D` | green |

The ruling that fixed these:

- **No grey for any status.** Grey read as "inert" on Packed, which is the most
  common state in the table (674 of 1,059 live rows).
- **Green is reserved for Turned In.** It is the one stage that means finished.
  Nothing else may take it — the retired map's green Picked Up is exactly what
  the reservation exists to prevent.
- The other three stages take **unique calming colours** chosen to sit with that
  green.

**Authoritative Swift source: `JobBoxTripStage.meterTint` in
`Iconik Employee/JobBox/JobBoxProgressMeter.swift`.** There is no second job-box
map any more. `StatusColors.jobBoxColors` / `jobBoxHexColors` — which disagreed
with the shipped meter on three of these four statuses — were **deleted**
2026-07-30, along with the unused hex accessors.

`#7A8794` is **not a status colour**: it is the never-scanned / unreadable-status
fallback, used when a box has no readable scan on its current trip.

**The web app must follow in a follow-on change** so the two clients cannot
disagree about the same box again.

## SD card statuses (unchanged)

| Status | Hex |
|---|---|
| Job Box | `#FF9500` |
| Camera | `#34C759` |
| Envelope | `#FFCC00` |
| Uploaded | `#007AFF` |
| Cleared | `#8E8E93` |
| Camera Bag | `#AF52DE` |
| Personal | `#5856D6` |

Authoritative Swift source: `StatusColors.sdCardColors`
(`Iconik Employee/NFC/StatusColors.swift`), read through
`StatusColors.color(forSDStatus:)`. Unknown status → grey `#8E8E93`. Lookup keys
are lowercase.
