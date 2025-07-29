import Foundation
import FirebaseFirestore

// Wrapper class to handle delayed listener registration
// Used by services that need to return a dummy listener when using cache
public class ListenerRegistrationWrapper: NSObject, ListenerRegistration {
    private let removalHandler: () -> Void
    
    public init(removalHandler: @escaping () -> Void) {
        self.removalHandler = removalHandler
    }
    
    public func remove() {
        removalHandler()
    }
}