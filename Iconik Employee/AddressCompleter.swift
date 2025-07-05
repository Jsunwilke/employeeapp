import Foundation
import MapKit

class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    
    private let completer: MKLocalSearchCompleter = {
        let comp = MKLocalSearchCompleter()
        comp.resultTypes = .address
        return comp
    }()
    
    override init() {
        super.init()
        completer.delegate = self
    }
    
    var queryFragment: String = "" {
        didSet {
            print("Updating query fragment: \(queryFragment)")
            completer.queryFragment = queryFragment
        }
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.suggestions = completer.results
            print("Suggestions updated: \(self.suggestions.map({ $0.title }))")
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Error in address completer: \(error.localizedDescription)")
    }
}

