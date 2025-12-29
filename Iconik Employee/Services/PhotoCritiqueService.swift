import Foundation
import Supabase
import Combine

class PhotoCritiqueService: ObservableObject {
    static let shared = PhotoCritiqueService()

    @Published var critiques: [Critique] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var filter: FilterType = .all

    private let supabase = SupabaseManager.shared.client
    private var channel: RealtimeChannelV2?

    enum FilterType: String, CaseIterable {
        case all = "All Examples"
        case good = "Good Examples"
        case improvement = "Needs Improvement"
    }

    private init() {}

    // Start listening for critiques for the current user
    func startListening() {
        guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
            print("No authenticated user found")
            return
        }

        let organizationId = UserManager.shared.getCachedOrganizationID()
        guard !organizationId.isEmpty else {
            print("No organization ID found, fetching...")
            UserManager.shared.getCurrentUserOrganizationID { [weak self] orgId in
                guard let orgId = orgId else {
                    print("Failed to get organization ID")
                    return
                }
                Task { @MainActor in
                    await self?.startListeningWithOrgId(userId: userId, organizationId: orgId)
                }
            }
            return
        }

        Task { @MainActor in
            await startListeningWithOrgId(userId: userId, organizationId: organizationId)
        }
    }

    @MainActor
    private func startListeningWithOrgId(userId: String, organizationId: String) async {
        isLoading = true
        error = nil

        do {
            // Fetch initial critiques
            let fetchedCritiques: [Critique] = try await supabase
                .from("photo_critiques")
                .select()
                .eq("target_photographer_id", value: userId.lowercased())
                .eq("organization_id", value: organizationId.lowercased())
                .eq("status", value: "published")
                .order("created_at", ascending: false)
                .execute()
                .value

            self.critiques = fetchedCritiques
            self.isLoading = false
            print("Loaded \(self.critiques.count) critiques")

            // Subscribe to realtime updates
            await subscribeToUpdates(userId: userId, organizationId: organizationId)
        } catch {
            self.isLoading = false
            self.error = error
            print("Error fetching critiques: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func subscribeToUpdates(userId: String, organizationId: String) async {
        // Remove existing channel if any
        if let existingChannel = channel {
            await existingChannel.unsubscribe()
        }

        // Create a new channel for photo_critiques changes
        channel = supabase.channel("photo_critiques_\(userId)")

        // Subscribe to changes
        let insertions = channel?.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "photo_critiques",
            filter: "target_photographer_id=eq.\(userId.lowercased())"
        )

        let updates = channel?.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "photo_critiques",
            filter: "target_photographer_id=eq.\(userId.lowercased())"
        )

        let deletions = channel?.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "photo_critiques",
            filter: "target_photographer_id=eq.\(userId.lowercased())"
        )

        // Handle insertions
        Task {
            guard let insertions = insertions else { return }
            for await insert in insertions {
                let record = insert.record
                if let data = try? JSONSerialization.data(withJSONObject: record.mapValues { $0.value }),
                   let critique = try? JSONDecoder().decode(Critique.self, from: data) {
                    await MainActor.run {
                        if critique.status == "published" && critique.organization_id.lowercased() == organizationId.lowercased() {
                            self.critiques.insert(critique, at: 0)
                        }
                    }
                }
            }
        }

        // Handle updates
        Task {
            guard let updates = updates else { return }
            for await update in updates {
                let record = update.record
                if let data = try? JSONSerialization.data(withJSONObject: record.mapValues { $0.value }),
                   let updatedCritique = try? JSONDecoder().decode(Critique.self, from: data) {
                    await MainActor.run {
                        if let index = self.critiques.firstIndex(where: { $0.id == updatedCritique.id }) {
                            if updatedCritique.status == "published" {
                                self.critiques[index] = updatedCritique
                            } else {
                                self.critiques.remove(at: index)
                            }
                        }
                    }
                }
            }
        }

        // Handle deletions
        Task {
            guard let deletions = deletions else { return }
            for await deletion in deletions {
                let oldRecord = deletion.oldRecord
                if case .string(let deletedId) = oldRecord["id"] {
                    await MainActor.run {
                        self.critiques.removeAll { $0.id == deletedId }
                    }
                }
            }
        }

        // Subscribe to channel
        await channel?.subscribe()
    }

    // Stop listening for changes
    func stopListening() {
        if let channel = channel {
            Task {
                await channel.unsubscribe()
            }
        }
        channel = nil
    }

    // Get filtered critiques based on current filter
    var filteredCritiques: [Critique] {
        switch filter {
        case .all:
            return critiques
        case .good:
            return critiques.filter { $0.isGoodExample }
        case .improvement:
            return critiques.filter { !$0.isGoodExample }
        }
    }

    // Calculate statistics
    var statistics: CritiqueStats {
        CritiqueStats(
            total: critiques.count,
            goodExamples: critiques.filter { $0.isGoodExample }.count,
            needsImprovement: critiques.filter { !$0.isGoodExample }.count
        )
    }

    // Refresh critiques
    func refresh() {
        stopListening()
        startListening()
    }

    // Get a specific critique by ID
    func getCritique(by id: String) -> Critique? {
        critiques.first { $0.id == id }
    }
}
