import Foundation

// MARK: - Listener Registration Wrapper
// This class wraps Supabase realtime channel subscriptions to provide
// a consistent API for managing listeners

class ListenerRegistrationWrapper {
    private let removeAction: () -> Void

    init(removeAction: @escaping () -> Void) {
        self.removeAction = removeAction
    }

    func remove() {
        removeAction()
    }
}
