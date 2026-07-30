//  YearbookItemDetailView.swift
//  Iconik Employee — one checklist item, Ambient (AMB.10)
//
//  REPLACES the `Form`-based sheet that used to live at the bottom of
//  `YearbookItemRow.swift`; that file is deleted, and its row moved to
//  `Yearbook/YearbookKit.swift` where the lab mockup draws with it too.
//
//  THREE APPROVED BEHAVIOUR FIXES, all of them about a save that can fail. Each
//  is view-level orchestration of service methods that already exist — no new
//  service surface, and NEVER a whole-row write from the snapshot this sheet
//  opened with (the hazard AMB.5 shipped and had to fix).
//
//    a. SAVE AWAITS ITS WRITES AND DOES NOT DISMISS ON FAILURE. The old sheet
//       fired two sequential round-trips and dismissed unconditionally, even when
//       both failed — the photographer believed it saved. The text stays on screen
//       and the failure is stated inline.
//    b. TOGGLING COMPLETION SAVES YOUR EDITS TOO. The old `toggleCompletion`
//       discarded whatever had been typed into Notes and Image Numbers, silently.
//       The edits are written FIRST, each through its own targeted service method,
//       and a failure stops the toggle rather than half-applying it.
//    c. A SUCCESSFUL SAVE SHOWS UP. The view model now updates its local copy on
//       success (`updateLocalItem`), so the row behind this sheet reflects the
//       save immediately; before, nothing local changed and the value did not
//       appear until the whole screen was rebuilt.
//
//  DROPPED, approved: the raw `completed_by_session` UUID the old sheet printed
//  under "Session". It is a database key with no lookup behind it and no
//  photographer has ever needed it.

import SwiftUI

struct YearbookItemDetailView: View {
    /// The ID, not the item. The sheet reads the CURRENT item out of the view
    /// model on every body evaluation, so a successful save is visible here as
    /// well as on the row behind it — the old sheet held a `let` captured when it
    /// opened and could not show its own writes.
    let itemId: String
    @ObservedObject var viewModel: YearbookShootListViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var notes = ""
    @State private var imageNumbersText = ""
    @State private var isSaving = false
    @State private var failure: String?
    @State private var didPopulate = false

    private var tint: Color { YearbookStyle.tint }
    private var item: YearbookItem? { viewModel.item(id: itemId) }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: tint, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let item {
                            hero(item)
                            statusSection(item)
                            attributionSection(item)
                            imagesSection
                            notesSection
                            toggleButton(item)
                            if let failure {
                                YearbookInlineFailure(message: failure)
                            }
                        } else {
                            AmbientEmptyState(
                                title: "Item not found",
                                message: "This item is no longer on the list.",
                                systemImage: "questionmark.folder")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Cancel stays LIVE during a save (AMB.10 review — while
                    // saving, Save becomes a ProgressView, so a disabled Cancel
                    // left NO enabled control on a hung connection; the old
                    // sheet always kept Cancel tappable).
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save(thenToggle: false) } }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: populateOnce)
    }

    /// Populated ONCE. Re-populating on every appearance would overwrite what is
    /// being typed the moment the view model publishes anything.
    private func populateOnce() {
        guard !didPopulate, let item else { return }
        didPopulate = true
        notes = item.notes ?? ""
        imageNumbersText = (item.imageNumbers ?? []).joined(separator: ", ")
    }

    // MARK: - 1. The hero

    private func hero(_ item: YearbookItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.system(size: 20, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // THE INVERSION: `required` is the default and carries no badge.
                if YearbookRules.showsOptionalBadge(item) {
                    AmbientBadge(text: "Optional", tint: .secondary)
                }
            }
            Text(item.category)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }

    // MARK: - 2. Status

    private func statusSection(_ item: YearbookItem) -> some View {
        AmbientFormSection(title: "Status",
                           status: item.completed ? "Completed" : "Incomplete",
                           statusTint: item.completed ? tint : .orange) {
            HStack(spacing: 8) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.completed
                                     ? AnyShapeStyle(tint)
                                     : AnyShapeStyle(Color.secondary))
                Text(item.completed ? "Photographed" : "Still to shoot")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
        }
    }

    /// Photographer and date. The raw session UUID is dropped (approved).
    @ViewBuilder
    private func attributionSection(_ item: YearbookItem) -> some View {
        if item.completed {
            AmbientFormSection(title: "Completed by",
                               status: item.photographerName ?? "Unknown",
                               statusTint: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Photographer").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Text(item.photographerName ?? "Unknown").font(.subheadline)
                    }
                    Divider()
                    HStack {
                        Text("Date").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        // Date AND time — the old sheet showed both, and "which of
                        // the day's sessions shot this" is the time's whole job (D12).
                        Text(item.completedDate.map { Formatters.mediumDateTime.string(from: $0) } ?? "—")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - 3. The editable fields

    private var imageNumbersArray: [String] {
        YearbookRules.parseImageNumbers(imageNumbersText)
    }

    private var imagesSection: some View {
        let count = imageNumbersArray.count
        return AmbientFormSection(title: "Image numbers",
                                  status: count == 0 ? "none" : "\(count)",
                                  statusTint: count == 0 ? nil : .blue) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("4102, 4103, 4110", text: $imageNumbersText)
                    .font(.subheadline)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                Text("Frame numbers, comma separated. Nothing here stores a photo.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var notesSection: some View {
        let written = YearbookRules.hasNote(notes)
        return AmbientFormSection(title: "Notes",
                                  status: written ? "written" : "optional",
                                  statusTint: written ? .orange : nil) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.subheadline)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                if notes.isEmpty {
                    Text("What was shot, what is still missing, who to ask.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - 4. The toggle

    private func toggleButton(_ item: YearbookItem) -> some View {
        VStack(spacing: 6) {
            Button {
                Task { await save(thenToggle: true) }
            } label: {
                Label(item.completed ? "Mark as Incomplete" : "Mark as Complete",
                      systemImage: item.completed ? "circle" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a filled primary control, not a card.
                    .background(Capsule().fill(item.completed ? Color.red : tint))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .opacity(isSaving ? 0.6 : 1)

            if hasUnsavedEdits(item) {
                Text("Your unsaved notes and image numbers are saved with this too.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Saving

    private func hasUnsavedEdits(_ item: YearbookItem) -> Bool {
        notesValue != storedNotes(item) || imageNumbersArray != (item.imageNumbers ?? [])
    }

    /// An empty editor means NO note, which is what the service stores as NULL.
    private var notesValue: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
    }

    /// FOUND ON DEVICE: rows written by the web app carry an EMPTY STRING rather
    /// than NULL, so comparing the editor's nil against a stored "" reported an
    /// unsaved edit on an untouched item — the caption appeared under the toggle
    /// button on a sheet nobody had typed in, and Save would have fired a pointless
    /// whole-row write. A blank stored note and no note are the same thing, which
    /// is exactly what `YearbookRules.hasNote` says about the badge.
    private func storedNotes(_ item: YearbookItem) -> String? {
        YearbookRules.hasNote(item.notes) ? item.notes : nil
    }

    /// Writes the edited fields, each through its own targeted service method, and
    /// only then toggles. A failure REPORTS and stops — it never dismisses, and it
    /// never leaves the sheet claiming a state it did not reach.
    private func save(thenToggle: Bool) async {
        guard let item, !isSaving else { return }
        isSaving = true
        failure = nil
        // Deliberately NOT clearing `viewModel.error` here: that banner may be
        // reporting a different item's failed write on the checklist behind this
        // sheet, and starting a save on THIS item must not erase it. This sheet's
        // failures arrive as return values below, so the shared error is never
        // needed here.
        defer { isSaving = false }

        // Tracks whether an EARLIER write in this same save landed, so a failure
        // message never claims a save that was not even attempted — this sheet's
        // whole job is stating the truth about what landed.
        var savedText = false

        if notesValue != storedNotes(item) {
            if let error = await viewModel.updateItemNotes(item, notes: notesValue, publishError: false) {
                failure = failureMessage("Couldn't save your note.", error)
                return
            }
            savedText = true
        }

        if imageNumbersArray != (item.imageNumbers ?? []) {
            // The item is re-read rather than reused: the note write above has
            // already updated the local copy, and a second write from the older
            // value is exactly the stale-snapshot hazard this sheet exists to
            // avoid. Only the id is used by the service, but the value read here
            // must still be the current one.
            let current = viewModel.item(id: itemId) ?? item
            if let error = await viewModel.updateItemImageNumbers(current, imageNumbers: imageNumbersArray, publishError: false) {
                failure = failureMessage(savedText
                                         ? "Your note saved, but the image numbers didn't."
                                         : "Couldn't save the image numbers.", error)
                return
            }
            savedText = true
        }

        if thenToggle {
            let current = viewModel.item(id: itemId) ?? item
            if let error = await viewModel.toggleItemCompletion(current, publishError: false) {
                failure = failureMessage(savedText
                                         ? "Your text saved, but the completion didn't."
                                         : "Couldn't update the completion.", error)
                return
            }
            // Deliberately NOT dismissed: the status section above flips, so the
            // toggle can be seen to have worked. The old sheet dismissed on toggle
            // whether or not the write succeeded.
            AmbientHaptics.impact(.medium)
            return
        }

        dismiss()
    }

    /// THIS call's failure, not the shared one — the zero-row write guard's own
    /// sentence is more useful than anything this screen could invent — plus what
    /// is still true about the text on screen.
    private func failureMessage(_ lead: String, _ error: Error) -> String {
        "\(lead) \(error.localizedDescription) Your text is still here — try again."
    }
}

// MARK: - Preview
struct YearbookItemDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = YearbookShootListViewModel.preview
        return YearbookItemDetailView(
            itemId: viewModel.selectedShootList?.items.first?.id ?? "",
            viewModel: viewModel)
    }
}
