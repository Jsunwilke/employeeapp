#!/bin/bash
#
# AMB.8 PARITY WALK — run against the NEW screens, not the old ones.
#
# Writing a parity inventory does not protect anything; only RUNNING it against
# the redesign does. AMB.7 lost five capabilities inside its own redesigns and the
# operator found four of them by asking "where is X?". The fifth was only found
# because a check like this finally got run.
#
# Every line below is a capability from AMB_BATCH2_PARITY.md's Time Off inventory,
# read from the ORIGINAL source before the redesign. A FAIL means the redesign
# dropped something. Deliberate drops are listed at the bottom as EXPECTED-GONE,
# each with the reason, and this script asserts they are gone rather than silently
# not looking for them.
#
# Usage: scripts/parity_timeoff.sh
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
LIST="Iconik Employee/TimeOff/Views/MyTimeOffRequestsView.swift"
APPR="Iconik Employee/TimeOff/Views/TimeOffApprovalView.swift"
FORM="Iconik Employee/TimeOff/Views/TimeOffRequestView.swift"
DETAIL="Iconik Employee/TimeOff/Views/TimeOffDetailView.swift"
PTO="Iconik Employee/Settings/PTOBalanceView.swift"
KIT="Iconik Employee/TimeOff/TimeOffKit.swift"
RULES="Iconik Employee/TimeOff/TimeOffRules.swift"
PRES="Iconik Employee/TimeOff/TimeOffPresentation.swift"

kept () { # $1 = capability, $2 = file, [-i] $3 = pattern
  # CODE ONLY. `gone()` was taught to strip comments and this was not, so several
  # checks passed on the PROSE THAT DESCRIBES THE FIX rather than the fix: the
  # @MainActor check matched its own doc comment, and the realtime-clear check
  # matched a comment containing the words it grepped for. An audit proved it by
  # deleting the fixes and watching the checks still pass — which is the only way
  # to know an assertion asserts anything.
  local flags=""
  if [ "$3" = "-i" ]; then flags="-i"; set -- "$1" "$2" "$4"; fi
  if sed -e 's|//.*||' -e 's|^[[:space:]]*#.*||' "$2" 2>/dev/null | grep -q $flags "$3"; then
    PASS=$((PASS+1)); printf '  ok    %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  LOST  %s   [%s ~ %s]\n' "$1" "$(basename "$2")" "$3"
  fi
}

keptIn () { # $1 = capability, $2 = file, $3 = function name, $4 = pattern
  # SCOPED TO ONE FUNCTION. A bare file-wide grep is why three checks passed with
  # the very defect they named re-inserted: `raise(error.localizedDescription)`
  # lives in TWO functions, so reverting approve's left review's behind and the
  # check never noticed. A check that cannot distinguish the site it names is not
  # a check. Extracts the function body by brace depth, then greps inside it.
  local body
  body=$(awk -v fn="func $3(" -v vr="var $3: " '
    index($0, fn) || index($0, vr) { inside=1 }
    inside { print; n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth+=n-m; if (depth<=0 && seen) exit; if (n>0) seen=1 }
  ' "$2" 2>/dev/null | sed -e 's|//.*||')
  if printf '%s' "$body" | grep -q "$4"; then
    PASS=$((PASS+1)); printf '  ok    %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  LOST  %s   [%s in %s() ~ %s]\n' "$1" "$(basename "$2")" "$3" "$4"
  fi
}

keptCount () { # $1 = capability, $2 = file, $3 = pattern, $4 = minimum occurrences
  # FOR A PATTERN THAT LEGITIMATELY APPEARS MORE THAN ONCE. A bare grep for
  # `errorMessage = ""` passed on the @Published property declaration alone, so the
  # check could not fail while the property existed — it asserted nothing. Counting
  # is what distinguishes "the clears are present" from "the variable exists".
  local n
  n=$(sed -e 's|//.*||' "$2" 2>/dev/null | grep -c "$3")
  if [ "$n" -ge "$4" ]; then
    PASS=$((PASS+1)); printf '  ok    %s (%s occurrences, need %s)\n' "$1" "$n" "$4"
  else
    FAIL=$((FAIL+1)); printf '  LOST  %s   [%s ~ %s occurrences, need %s]\n' "$1" "$(basename "$2")" "$n" "$4"
  fi
}

gone () { # $1 = capability, $2 = file, $3 = pattern that must NOT appear
  # CODE ONLY — comment lines are stripped first. Every deliberate removal in this
  # phase is explained in a comment that NAMES the thing removed, so a naive grep
  # reports the explanation as the construct and the check fails on its own
  # documentation. (The drift gate carries the mirror image of this trap: a long
  # comment must not hide a construct from the rule.) Caught by running this.
  if sed -e 's|//.*||' "$2" 2>/dev/null | grep -q "$3"; then
    FAIL=$((FAIL+1)); printf '  STILL THERE  %s\n' "$1"
  else
    PASS=$((PASS+1)); printf '  ok    (deliberately gone) %s\n' "$1"
  fi
}

echo "MyTimeOffRequestsView — the employee list"
kept "New Time Off Request button, always present"   "$LIST" 'New Time Off Request'
kept "All chip"                                       "$LIST" '"All"'
kept "the five status chips come from filterOptions"  "$LIST" 'TimeOffStatus.filterOptions'
kept "chips always rendered, only the badge is conditional" "$KIT" 'if count > 0'
kept "chip row scrolls horizontally"                  "$LIST" 'ScrollView(.horizontal'
kept "Create First Request"                           "$LIST" 'Create First Request'
kept "…conditional on NO filter being active"         "$LIST" 'if let selectedStatus'
kept "pull to refresh"                                "$LIST" 'refreshable'
kept "Edit pill"                                      "$LIST" 'onEdit:'
kept "Cancel pill"                                    "$LIST" 'onCancel:'
kept "…with a confirmation alert"                     "$LIST" 'Are you sure you want to cancel'
kept "Keep Request (the alert's cancel label)"         "$LIST" 'Keep Request'
kept "unfiltered empty title"                         "$LIST" 'No Time Off Requests'
kept "unfiltered empty message"                       "$LIST" "haven't submitted any time off requests yet"
kept "filtered empty title"                           "$LIST" 'No \\(selectedStatus.displayName) Requests'
kept "filtered empty message"                         "$LIST" "don't have any"
kept "loading copy"                                   "$LIST" 'Loading your requests...'
kept "newest-first order"                             "$LIST" 'TimeOffOrder.employeeList'
kept "cancel success message"                         "$LIST" 'Request cancelled successfully'

echo
echo "The shared card (both lists draw it)"
kept "reason icon carries its own colour"             "$KIT" 'model.reason.symbol'
kept "date label"                                     "$KIT" 'model.dateLabel'
kept "Partial badge"                                  "$KIT" '"Partial"'
kept "time label"                                     "$KIT" 'model.timeLabel'
kept "duration label"                                 "$KIT" 'model.durationLabel'
kept "PTO hours on the card"                          "$KIT" 'PTO hours'
kept "status badge"                                   "$KIT" 'model.status.label'
# The capability is that the note is SHOWN, not that it is truncated. The fix
# round removed `.lineLimit(2)` because neither list navigates to the detail
# screen, so the hidden remainder was unreachable — a manager read two lines of a
# four-line family-emergency explanation and had no way to see the rest.
kept "notes shown in full (no route to the rest existed)" "$KIT" 'model.notes'
kept "Approved by NAME"                               "$RULES" 'Approved by'
kept "In review by NAME"                              "$RULES" 'In review by'
kept "Denied by NAME"                                 "$RULES" 'Denied by'
kept "attribution needs BOTH name and date"           "$RULES" 'guard let name, let date'
kept "denial reason line"                             "$KIT" 'Reason: '
kept "cancelled rows recede"                          "$KIT" 'receded'
kept "manager Approve"                                "$KIT" '"Approve"'
kept "manager Deny"                                   "$KIT" '"Deny"'
kept "manager Put in Review"                          "$KIT" 'Put in Review'
kept "photographer shown on the manager card only"    "$KIT" 'showsPhotographer'

echo
echo "TimeOffApprovalView — the manager queue"
kept "three tabs"                                     "$APPR" 'case history'
kept "red count badges"                               "$APPR" 'Color.red'
kept "History deliberately carries no badge"          "$APPR" 'case .history: return 0'
kept "pull to refresh"                                "$APPR" 'refreshable'
kept "FIFO order for pending"                         "$APPR" 'TimeOffOrder.managerQueue'
kept "history sorted by when it was actioned"         "$APPR" 'TimeOffOrder.history'
kept "Put in Review wired only on the Pending tab"    "$APPR" 'tab == .pending ?'
kept "denial reason REQUIRED"                         "$APPR" 'required'
kept "empty: All Caught Up!"                          "$APPR" 'All Caught Up!'
kept "empty: No Requests In Review"                   "$APPR" 'No Requests In Review'
kept "empty: No History"                              "$APPR" 'No History'
kept "loading copy"                                   "$APPR" 'Loading requests...'
kept "approve success message"                        "$APPR" 'Request approved successfully'
kept "deny success message"                           "$APPR" 'Request denied successfully'
kept "review success message"                         "$APPR" 'Request placed in review'

echo
echo "TimeOffRequestView — create AND edit, one form"
kept "Full Day / Partial Day picker"                  "$FORM" 'Full Day'
kept "switching to partial forces end = start"        "$FORM" 'if partial { endDate = startDate }'
kept "partial mode: one Date picker"                  "$FORM" '"Date"'
kept "full mode: Start Date"                          "$FORM" 'Start Date'
kept "full mode: End Date"                            "$FORM" 'End Date'
kept "start bounded to today or later"                "$FORM" 'range: Date()...'
kept "end bounded BY start"                           "$FORM" 'range: startDate...'
kept "moving start past end drags end"                "$FORM" 'if newValue > endDate { endDate = newValue }'
kept "Start Time"                                     "$FORM" 'Start Time'
kept "End Time"                                       "$FORM" 'End Time'
kept "end <= start auto-repairs to start + 1h"        "$RULES" 'end = start.adding(minutes: 60)'
kept "read-only Duration row"                         "$FORM" '"Duration"'
kept "duration inclusive of both endpoints"           "$RULES" 'return max(1, days + 1)'
kept "six reasons, each with icon and colour"         "$FORM" 'TimeOffReason.allReasons'
kept "Notes, optional, min height 80"                 "$FORM" 'minHeight: 80'
kept "Use PTO Balance toggle"                         "$FORM" 'Use PTO Balance'
kept "…defaulting to ON"                              "$FORM" 'isPaidTimeOff = true'
kept "current balance row"                            "$FORM" 'Available now'
kept "…omitted entirely when the balance is nil"      "$FORM" 'if let balance = currentPTOBalance'
kept "PTO hours field"                                "$FORM" 'PTO Hours Requested'
kept "…auto-filled but manual entry wins"             "$RULES" 'guard !isUserEdited else { return }'
kept "insufficient-PTO message"                       "$FORM" 'not have sufficient PTO'
kept "future-accrual message"                         "$FORM" "haven't accrued yet"
kept "Summary: Type"                                  "$FORM" '"Type", value:'
kept "Summary: Dates"                                 "$FORM" '"Dates"'
kept "Summary: Duration"                              "$FORM" '"Duration"'
kept "Summary: Reason"                                "$FORM" '"Reason"'
kept "30-minute partial-day minimum gates Submit"     "$RULES" 'minimumMinutes = 30'
kept "full-day requests are NEVER blocked"            "$RULES" 'guard span.isPartialDay else { return .allowed }'
kept "edit mode title"                                "$FORM" 'Edit Request'
kept "create success message"                         "$FORM" 'Time off request submitted successfully!'
kept "update success message"                         "$FORM" 'Time off request updated successfully!'

echo
echo "TimeOffDetailView — reached from the Schedule"
kept "date in full style"                             "$DETAIL" 'Formatters.longDate'
kept "time range or Full Day"                         "$DETAIL" 'Full Day'
kept "photographer row"                               "$DETAIL" 'Photographer'
kept "reason shown"                                   "$DETAIL" 'reasonDisplay.label'
kept "notes row omitted when empty"                   "$DETAIL" 'if !timeOffEntry.notes.isEmpty'
# Case-insensitive deliberately: the ORIGINAL app wrote "Partial Day Request" and
# the approved mockup wrote "Partial day request". The design audit flagged the
# capitalisation as a divergence from the spec and the fix round adopted the
# mockup's. The CAPABILITY being asserted is that the screen says which kind of
# request this is — not which house style it says it in. A parity check that
# pins prose exactly turns every approved copy edit into a false loss.
kept "partial/full day request line"                  "$DETAIL" -i 'partial day request'
kept "status shown"                                   "$DETAIL" 'statusDisplay.label'
kept "Cancel Request, conditional on pending"         "$DETAIL" 'timeOffEntry.status == .pending'
kept "confirmation says it cannot be undone"          "$DETAIL" 'cannot be undone'
kept "ownership check preserved verbatim (TOF.1)"     "$DETAIL" 'UserDefaults.standard.string(forKey: "userID")'

echo
echo "PTOBalanceView — in Settings, and now also from Time Off"
kept "current balance hero"                           "$PTO" 'hours available'
kept "Total Balance"                                  "$PTO" 'Total Balance'
kept "Pending Requests, conditional on > 0"           "$PTO" 'balance.pendingBalance > 0'
kept "Available to Use"                               "$PTO" 'Available to Use'
kept "Banking Balance, conditional"                   "$PTO" 'balance.bankingBalance > 0'
kept "Total accrued"                                  "$PTO" 'Total accrued'
kept "…and it says so where the used figure was"      "$PTO" 'are not tracked on this device'
kept "accrual policy card, conditional on enabled"    "$PTO" 'settings.enabled'
kept "accrual rate copy"                              "$PTO" 'formattedAccrualRate'
kept "max accrual copy"                               "$PTO" 'formattedMaxAccrual'
kept "rollover copy"                                  "$PTO" 'formattedRolloverPolicy'
kept "date picker, 30 days out by default"            "$PTO" '30 \* 24 \* 60 \* 60'
# Relabelled "Projected total balance": the figure projects `totalBalance` while
# the hero shows `availableBalance`, and an unqualified label invited the reader to
# compare two different quantities.
kept "balance projection"                             "$PTO" 'Projected total balance'
kept "you will accrue N more hours"                   "$PTO" 'You will accrue'
kept "error state with Retry"                         "$PTO" 'Retry'
kept "loading copy"                                   "$PTO" 'Loading PTO information...'

echo
echo "Domain logic carried forward deliberately"
kept "a full day is 8 PTO hours"                      "$RULES" 'hoursPerFullDay: Double = 8'
kept "the manager queue is FIFO"                      "$RULES" 'static func managerQueue'
kept "the employee list is newest-first"              "$RULES" 'static func employeeList'
kept "PTO defaults ON for a new request"              "$FORM" 'isPaidTimeOff = true'
kept "denial requires a reason"                       "$APPR" 'guard !reason.isEmpty'

echo
echo "NEW — states that did not exist and should have"
kept "the list shows a load FAILURE instead of an empty state" "$LIST" 'TimeOffFailureBanner'
kept "the queue shows a load FAILURE too"             "$APPR" 'TimeOffFailureBanner'
kept "a failed balance is not drawn as 0.0"           "$KIT" 'Balance unavailable'
kept "the balance leads the surface"                  "$LIST" 'TimeOffBalanceLead'

echo
echo "NEW — cross-client repairs (the web app writes these)"
kept "web reason vocabulary recognised"               "$RULES" 'case "sick", "sick leave"'
kept "web denial stamps the APPROVAL columns"         "$PRES" 'approver_name, date: approved_at, status: .denied'
kept "an unknown status is not shown as Pending"      "$KIT" 'case unrecognised'
kept "empty-string photographer name handled"         "$PRES" 'name.isEmpty ? "Unknown"'

echo
echo "Fix round — findings from the three audits, asserted so they cannot silently return"
kept "double-submit guard on approve/deny/review"     "$APPR" 'inFlight'
kept "…and the card shows the write is in flight"     "$KIT" 'actionsBusy'
kept "a failed deny is shown INSIDE the sheet"        "$APPR" 'denialError'
kept "the typed denial reason is cleared on dismiss"  "$APPR" 'onDismiss:'
kept "PTO hours refill when the stored value is zero" "$FORM" 'isUserEdited: storedHours != 0'
kept "the PTO toggle recalculates"                    "$FORM" 'onChange(of: isPaidTimeOff)'
kept "TimeOfDay clamps to 23:59 so it round-trips"    "$RULES" '24 \* 60 - 1'
kept "unparseable partial-day times say so"           "$PRES" 'Time not set'
kept "the reason LABEL is on the card, not just an icon" "$KIT" 'model.reason.label'
kept "attribution dates carry the year"               "$KIT" 'Formatters.mediumDate'
# ASSERTS THE PROPERTY, NOT A STRING. The first version of this check grepped for
# 'await MainActor.run' and passed on a single occurrence anywhere in the file —
# it would NOT have caught the bug it was written for, which was the in-flight
# guard being RELEASED in a `defer` outside any of those wrappers. The property
# actually wanted is that the three action methods are main-actor isolated, so the
# whole Task body (defer included) is on the main actor by construction.
kept "approve/deny/review are @MainActor isolated"    "$APPR" '@MainActor'
kept "the guard is released on every exit"            "$APPR" 'defer { inFlight.remove'
kept "the deny sheet cannot be dismissed mid-write"   "$APPR" 'interactiveDismissDisabled'
kept "…nor cancelled mid-write"                       "$APPR" 'disabled(inFlight.contains(request.id))'
# QUEUED, not suppressed. The first version of this fix wrote
# `showingAlert = (requestToDeny == nil)`, which DISCARDED the message when a sheet
# was up — so a failed approve vanished silently, which is worse than the problem
# it solved. The message is now held and flushed when the sheet closes.
kept "a message arriving while a sheet is up is QUEUED" "$APPR" 'queuedAlerts.append(message)'
keptIn "…and the flush is reachable from the alert"   "$APPR" flushQueuedAlert 'showingAlert = true'
kept "the deny sheet shows its own busy state"        "$APPR" 'Denying…'
kept "Retry forces a network fetch, not a cache hit"  "Iconik Employee/TimeOff/Services/TimeOffService.swift" 'lastCacheUpdate = nil'
keptCount "errorMessage cleared on ALL FOUR success paths" "Iconik Employee/TimeOff/Services/TimeOffService.swift" 'errorMessage = ""' 5
kept "dates carry a year outside the current one"     "$PRES" 'Formatters.mediumDate.string'
kept "…and a range is formatted as ONE unit"          "$PRES" 'rangeString'
kept "the lab draws dates through the same formatter" "Iconik Employee/DesignLab/DesignLabSampleData.swift" 'TimeOffDateLabel.rangeString'
kept "the shortfall is measured on the displayed base" "$FORM" 'projectedAvailable'
kept "the accrual line is measured from its own base"  "$PTO" 'projectedBalance - balance.balance'
kept "accrual footnote only for an accrual org"       "$PTO" 'settings.usesAccrualSystem'

keptIn "approve reports FAILURE as failure, not success" "$APPR" approveRequest 'raise(error.localizedDescription)'
keptIn "review reports FAILURE as failure too"         "$APPR" putRequestInReview 'raise(error.localizedDescription)'
keptIn "the flush CONSUMES what it shows"              "$APPR" flushQueuedAlert 'queuedAlerts.removeFirst()'
kept "the flush will not fire over a live alert"       "$APPR" 'newValue == nil, !showingAlert'
kept "the LIST screen enumerates ALL its presentations" "$LIST" 'private var isPresentingSomething'
keptIn "…and queues against that enumeration"         "$LIST" cancelRequest 'if isPresentingSomething'
kept "the list screen guards double-cancel"           "$LIST" 'inFlight.insert(request.id)'
kept "…and the card shows it"                         "$LIST" 'actionsBusy: inFlight.contains'
# BOTH branches, counted: `if actionsBusy {` appears in the manager branch too, so
# a file-wide grep passed with the employee branch sabotaged. The whole point of
# this check is that the guard is on BOTH.
keptCount "BOTH card branches honour actionsBusy"     "$KIT" 'if actionsBusy {' 2
kept "the detail sheet guards double-cancel"          "$DETAIL" 'guard !isCancelling'
kept "raise() has no unread success parameter"         "$APPR" 'private func raise(_ message: String)'

echo
echo "Operator /code-review round — 8 findings, asserted so they cannot return"
keptIn "the fetch reports its own flag, so the empty state cannot lie" "Iconik Employee/TimeOff/Services/TimeOffService.swift" startListeningToRequests 'isFetchingList = true'
kept "…and it is SEPARATE from the shared isLoading"  "Iconik Employee/TimeOff/Services/TimeOffService.swift" 'var isFetchingList'
kept "the list screen reads the fetch flag"           "$LIST" 'isFetchingList'
kept "the queue screen reads it too"                  "$APPR" 'isFetchingList'
# FOUR: the declaration, `remaining`, the mathRow, and PTOStanding's availableNow.
# It was 5 while `projectedAvailable` recovered the reservation by subtracting from
# it; removing that derivation is what dropped the count, which is the threshold
# doing its job rather than a regression.
keptCount "edit mode does not double-subtract, at ALL FOUR sites" "$FORM" 'availableForThisRequest' 4
keptCount "the reservation is added, never re-derived"  "$FORM" 'ownReservation' 3
kept "…including the shortfall message's own base"    "$FORM" 'availableNow: availableForThisRequest'
kept "the reservation is ONE named source, not derived" "$FORM" 'private var ownReservation'
gone "…and is never recovered by subtraction"         "$FORM" 'availableForThisRequest - balance.availableBalance'
kept "…and the row above it uses the same figure"     "$FORM" 'availableForThisRequest, .secondary)'
kept "…labelled honestly in edit mode"                "$FORM" '"Available for this request"'
keptCount "the queues are ARRAYS, not single slots"   "$APPR" 'queuedAlerts' 6
keptCount "…on the list screen too"                   "$LIST" 'queuedAlerts' 4
kept "pushing does NOT tear down the realtime channel" "$LIST" 'guard destination == nil else { return }'
kept "the queue is flushed when the push pops"        "$LIST" 'if newValue == nil { flushQueuedAlert() }'
keptCount "EVERY presentation surface has a flush hook" "$LIST" 'flushQueuedAlert()' 4
# `tabBar` is a computed var, so keptIn (which looks for `func name(`) cannot scope
# to it. Asserted as a pair instead: the gesture exists, and it is NOT on the
# ScrollView — which is the property that matters, since attaching it there is what
# this repo's own design system warns against.
keptIn "swipe between tabs lives on the STRIP"        "$APPR" tabBar 'highPriorityGesture'

echo
echo "EXPECTED-GONE — dropped deliberately, each with a reason in the file"
gone "Schedule Conflicts section (checkForConflicts always returns [])" "$FORM" 'Schedule Conflicts'
gone "Delete Time Off (every press was a guaranteed 403)"               "$DETAIL" 'Delete Time Off'
gone "the old hand-rolled card in the list file"                        "$LIST" 'struct TimeOffRequestCard'
gone "Color(colorName) asset lookups that never resolved"               "$LIST" 'Color(request.statusEnum.colorName)'
gone "rawValue.capitalized, which shipped as \"Underreview\""             "$DETAIL" 'rawValue.capitalized'
# A REMOVAL, not a loss: the old tile rendered `usedThisYear`, which sits outside
# CodingKeys and is always 0. Pointing it at the real `used` column made it a
# differently wrong number, because nothing writes that column either — iOS drops
# it on every update and the web app never touches it. A confident wrong number on
# a payroll screen is worse than none, so the tile is gone and the screen says why.
gone "the Used This Year tile (a column nothing maintains)"              "$PTO" 'Used this year'
gone "bounce suppression that killed pull-to-refresh"                   "$LIST" 'ambientNoBounceWhenShort'
gone "the dead onDelete parameter"                                      "$DETAIL" 'onDelete'

echo
echo "$PASS passed, $FAIL lost"
if [ "$FAIL" -gt 0 ]; then echo "PARITY FAILED"; exit 1; fi
echo "PARITY OK"
