//  WriteNFCView.swift
//  Iconik Employee — writing a number onto a tag
//
//  AMB.11 conversion. The NDEF payload construction, the number-range validation
//  and the save-seed logic are BYTE-IDENTICAL to what shipped (D12) — including
//  the SD suggestion's `max(1001, min(2000, …))` pin, which is named in the
//  approved design as unchanged.
//
//  WHAT CHANGED, all from the operator-approved `JobBoxMockup` Write surface:
//    - the form is an `AmbientFormSection`, and the Write button is a full-width
//      capsule in the REGISTERED feature colour that STAYS while writing. It used
//      to be REPLACED by a bare `ProgressView()`, so the control vanished rather
//      than dimming;
//    - the nested `NavigationView` is gone (the container owns the one bar), and
//      with it this view's own `navigationTitle`;
//    - N32: dismissal no longer branches on `alertMessage.contains("successfully")`.
//      An explicit `lastWriteSucceeded` Bool drives it;
//    - N5 (approved): a writer availability guard. `NFCWriterCoordinator` has
//      none at all, unlike the reader, so the button was live on hardware that
//      cannot write;
//    - approved PROPOSED: an OFFLINE state. Writing a tag offline succeeds on the
//      hardware and the record silently takes the offline queue path, while the
//      alert said "saved successfully". It now says QUEUED.
//
//  ONE DELIBERATE DEVIATION (audit round, 2026-07-30): a FAILED suggestion fetch
//  no longer falls back to 3001 / 1001 and pre-fills the field with it. That
//  fallback presented a near-certain duplicate as though the database had
//  answered; the field is now left empty and the suggestion line says the fetch
//  failed. The successful paths, including the 1001-2000 pin and the
//  empty-table's 1001, are untouched.
//
//  STATE-MACHINE FIX (§1.16 item 5, suspected and unverifiable without a device):
//  `nfcWriter.isWritingSuccessful` was never reset to false by the view, and
//  `.onChange` cannot re-fire on an unchanged value — so the SECOND write in one
//  visit saved no record. It is reset here as soon as it has been handled.

import SwiftUI
import CoreNFC

struct WriteNFCView: View {
    @StateObject var nfcWriter = NFCWriterCoordinator()
    @State private var cardNumber: String = ""
    @State private var suggestedCardNumber: String = ""
    @State private var suggestedBoxNumber: String = ""
    /// Set when the suggestion fetch FAILED (audit round). It used to fall back
    /// to 3001 / 1001 and PRE-FILL the field with it — a number that is almost
    /// certainly already written on a tag, offered as if the database had
    /// answered. The field is now left empty and this says why.
    @State private var suggestionFailure: String?
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    /// Replaces the string match on the alert copy (N32).
    @State private var lastWriteSucceeded = false
    @State private var isJobBox = false

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var offlineManager = OfflineDataManager.shared

    private var tint: Color { FeatureTheme.color(for: "scan") }

    /// N5. The reader has the app's one availability check; the writer had none.
    private var writerAvailable: Bool { NFCTagReaderSession.readingAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !offlineManager.isOnline { offlineBanner }

                AmbientFormSection(title: "Write to a tag",
                                   status: cardNumber.isEmpty ? "required" : cardNumber,
                                   statusTint: cardNumber.isEmpty ? .orange : nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Item Type", selection: $isJobBox) {
                            Text("SD Card").tag(false)
                            Text("Job Box").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: isJobBox) { _ in
                            // Clear the card number when switching types
                            cardNumber = ""
                            fetchSuggestedNumber()
                        }

                        TextField(isJobBox ? "Enter Job Box Number (3001+)" : "Enter SD Card Number (1001-2000)",
                                  text: $cardNumber)
                            .font(.subheadline)
                            .keyboardType(.numberPad)

                        // Show appropriate suggestion based on type
                        if let suggestionFailure {
                            Text(suggestionFailure)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !suggestedCardNumber.isEmpty && !isJobBox {
                            Text("Suggested SD Card Number: \(suggestedCardNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !suggestedBoxNumber.isEmpty && isJobBox {
                            Text("Suggested Job Box Number: \(suggestedBoxNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if writerAvailable {
                    writeButton
                } else {
                    unavailableCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
        .onChange(of: nfcWriter.isWritingSuccessful) { success in
            if success {
                // Reset immediately so a SECOND write in the same visit can fire
                // this again — `.onChange` will not re-run on an unchanged value,
                // and the coordinator only clears the flag on an invalidation
                // error. See the file header.
                nfcWriter.isWritingSuccessful = false
                saveRecordAfterWriting()
            }
        }
        .onChange(of: nfcWriter.errorMessage) { error in
            if let errorMessage = error {
                lastWriteSucceeded = false
                alertMessage = errorMessage
                showAlert = true
                // Reset once handled, the same reason as `isWritingSuccessful`
                // above (audit round): nothing cleared this, and `.onChange`
                // cannot re-fire on an unchanged value — so two IDENTICAL
                // consecutive failures raised the alert once and the second
                // attempt looked like it had simply done nothing.
                nfcWriter.errorMessage = nil
            }
        }
        .onAppear {
            fetchSuggestedNumber()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK"), action: {
                      if lastWriteSucceeded {
                          lastWriteSucceeded = false
                          dismiss()
                      }
                  }))
        }
    }

    // MARK: - Surfaces

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline Mode").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if offlineManager.syncPending {
                Text("• Sync Pending").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            }
        }
        .foregroundStyle(.white)
        .ambientCard(density: .compact, fill: .tint(.red), fillWidth: true)
    }

    private var writeButton: some View {
        Button(action: validateAndWriteNFC) {
            HStack(spacing: 8) {
                if isSaving { ProgressView().tint(.white) }
                // "Saving…", not "Hold your iPhone near the tag…" (audit round):
                // `isSaving` is raised in `saveRecordAfterWriting`, which runs
                // AFTER the tag write has already succeeded. The hold-near-tag
                // prompt is CoreNFC's own system sheet and this button must not
                // claim to be it.
                Text(isSaving ? "Saving…" : "Write NFC")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            // ambient-allow: the primary action — a control, not a container.
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private var unavailableCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "pencil.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("This device can't write tags")
                .font(.headline)
            Text("Writing a tag needs NFC hardware, which iPads do not have. Use an iPhone to write a tag; Manual Entry records a box or a card by number on any device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)
    }

    // MARK: - Writing

    private func validateAndWriteNFC() {
        // Validate number is in the correct range based on type
        if isJobBox {
            guard let number = Int(cardNumber), number >= NFCRoutingRules.jobBoxNumberFloor else {
                lastWriteSucceeded = false
                alertMessage = "Please enter a valid job box number (3001 or greater)."
                showAlert = true
                return
            }
        } else {
            guard let number = Int(cardNumber),
                  NFCRoutingRules.sdCardNumberRange.contains(number) else {
                lastWriteSucceeded = false
                alertMessage = "Please enter a valid SD card number (between 1001-2000)."
                showAlert = true
                return
            }
        }

        writeNFC()
    }

    func writeNFC() {
        let languageCode = "en"
        guard let langData = languageCode.data(using: .utf8),
              let textData = cardNumber.data(using: .utf8) else {
            lastWriteSucceeded = false
            alertMessage = "Unable to create NDEF payload."
            showAlert = true
            return
        }

        let statusByte = UInt8(langData.count)
        var payloadBytes = Data([statusByte])
        payloadBytes.append(langData)
        payloadBytes.append(textData)

        guard let typeData = "T".data(using: .utf8) else {
            lastWriteSucceeded = false
            alertMessage = "Unable to create type data."
            showAlert = true
            return
        }

        let ndefPayload = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: typeData,
            identifier: Data(),
            payload: payloadBytes
        )

        let message = NFCNDEFMessage(records: [ndefPayload])
        nfcWriter.beginWriting(with: message)
    }

    func saveRecordAfterWriting() {
        isSaving = true
        let timestamp = Date()
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isSaving = false
            lastWriteSucceeded = false
            alertMessage = "User organization not found."
            showAlert = true
            return
        }

        // A write that lands while offline takes the offline queue path. The
        // alert says QUEUED rather than "saved successfully", which is what it
        // used to say on exactly the same code path.
        let queued = !offlineManager.isOnline

        if isJobBox {
            // Save Job Box record
            DatabaseManager.shared.saveJobBoxRecord(
                timestamp: timestamp,
                photographer: "",
                boxNumber: cardNumber,
                school: "",
                schoolId: nil,
                status: "Packed",
                organizationID: orgID,
                userId: userManager.getCurrentUserID() ?? ""
            ) { result in
                isSaving = false
                switch result {
                case .success:
                    lastWriteSucceeded = true
                    alertMessage = queued
                        ? "Tag written. Job box record queued — it will save when you're back online."
                        : "Job box record saved successfully."
                case .failure(let error):
                    lastWriteSucceeded = false
                    alertMessage = "Failed to save job box record: \(error.localizedDescription)"
                }
                showAlert = true
            }
        } else {
            // Save SD Card record
            DatabaseManager.shared.saveRecord(
                timestamp: timestamp,
                photographer: "",
                cardNumber: cardNumber,
                school: "",
                status: "Cleared",
                uploadedFromJasonsHouse: "",
                uploadedFromAndysHouse: "",
                organizationID: orgID,
                userId: userManager.getCurrentUserID() ?? ""
            ) { result in
                isSaving = false
                switch result {
                case .success:
                    lastWriteSucceeded = true
                    alertMessage = queued
                        ? "Tag written. SD card record queued — it will save when you're back online."
                        : "SD card record saved successfully."
                case .failure(let error):
                    lastWriteSucceeded = false
                    alertMessage = "Failed to save SD card record: \(error.localizedDescription)"
                }
                showAlert = true
            }
        }
    }

    /// What a FAILED suggestion says. It replaces the "Suggested …" line rather
    /// than joining it: there is no suggestion to show.
    private static let suggestionFailureMessage =
        "Couldn't fetch a suggestion — check the number is unused."

    func fetchSuggestedNumber() {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            // WAS A SILENT RETURN (audit round, same class as SearchView's and
            // Manual Entry's): no suggestion appeared and nothing said why, so
            // the field read as "there is no next number" rather than "we
            // couldn't ask". The number must still be typed by hand and checked,
            // which is exactly what the failure line says.
            suggestedCardNumber = ""
            suggestedBoxNumber = ""
            suggestionFailure = Self.suggestionFailureMessage
            return
        }

        suggestionFailure = nil

        if isJobBox {
            // Fetch highest job box number
            DatabaseManager.shared.getHighestBoxNumber(organizationID: orgID) { result in
                switch result {
                case .success(let highestNumber):
                    DispatchQueue.main.async {
                        self.suggestionFailure = nil
                        self.suggestedBoxNumber = String(highestNumber + 1)
                        if self.cardNumber.isEmpty {
                            self.cardNumber = String(highestNumber + 1)
                        }
                    }
                case .failure(let error):
                    print("Error fetching highest box number:", error.localizedDescription)
                    // NO FALLBACK NUMBER (audit round). This used to pre-fill the
                    // job-box floor as though it were an answer, so a failed fetch
                    // handed the photographer a number the org almost certainly
                    // already uses.
                    DispatchQueue.main.async {
                        self.suggestedBoxNumber = ""
                        self.suggestionFailure = Self.suggestionFailureMessage
                    }
                }
            }
        } else {
            // Fetch highest SD card number
            DatabaseManager.shared.fetchRecords(field: "all", value: "", organizationID: orgID) { result in
                switch result {
                case .success(let records):
                    let numbers = records.compactMap { Int($0.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    if let maxNumber = numbers.max() {
                        let suggestion = maxNumber + 1
                        // Ensure suggestion stays in range 1001-2000. UNCHANGED and
                        // named in the approved design: once the org reaches card
                        // 2000 this pins there and pre-fills a duplicate.
                        let validSuggestion = max(1001, min(2000, suggestion))
                        DispatchQueue.main.async {
                            self.suggestionFailure = nil
                            self.suggestedCardNumber = String(validSuggestion)
                            if self.cardNumber.isEmpty {
                                self.cardNumber = String(validSuggestion)
                            }
                        }
                    } else {
                        // An EMPTY table is a real answer — the first card is
                        // 1001 — so this branch keeps its suggestion. Only the
                        // failure below loses one.
                        DispatchQueue.main.async {
                            self.suggestionFailure = nil
                            self.suggestedCardNumber = "1001"
                            if self.cardNumber.isEmpty {
                                self.cardNumber = "1001"
                            }
                        }
                    }
                case .failure(let error):
                    print("Error fetching records for suggestion:", error.localizedDescription)
                    // NO FALLBACK NUMBER (audit round), as above: 1001 offered
                    // after a failed fetch is a duplicate waiting to happen.
                    DispatchQueue.main.async {
                        self.suggestedCardNumber = ""
                        self.suggestionFailure = Self.suggestionFailureMessage
                    }
                }
            }
        }
    }
}
