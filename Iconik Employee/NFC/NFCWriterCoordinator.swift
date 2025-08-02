import Foundation
import CoreNFC
import SwiftUI

class NFCWriterCoordinator: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published var isWritingSuccessful: Bool = false
    @Published var errorMessage: String?
    
    private var session: NFCTagReaderSession?
    private var messageToWrite: NFCNDEFMessage?
    
    func beginWriting(with message: NFCNDEFMessage) {
        self.messageToWrite = message
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = "Hold your iPhone near the NFC tag to write."
        session?.begin()
    }
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isWritingSuccessful = false
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if tags.count > 1 {
            session.alertMessage = "More than one tag detected. Please try again."
            session.invalidate()
            return
        }
        
        guard let firstTag = tags.first else { return }
        
        session.connect(to: firstTag) { error in
            if let error = error {
                session.alertMessage = "Unable to connect to tag."
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            
            guard let ndefTag = self.getNDEFTag(from: firstTag) else {
                session.alertMessage = "Tag is not NDEF-compliant."
                session.invalidate()
                return
            }
            
            self.writeToNDEFTag(session: session, ndefTag: ndefTag)
        }
    }
    
    private func getNDEFTag(from rawTag: NFCTag) -> NFCNDEFTag? {
        switch rawTag {
        case .miFare(let mifareTag):
            return mifareTag as? NFCNDEFTag
        case .iso7816(let iso7816Tag):
            return iso7816Tag as? NFCNDEFTag
        case .iso15693(let iso15693Tag):
            return iso15693Tag as? NFCNDEFTag
        case .feliCa(let feliCaTag):
            return feliCaTag as? NFCNDEFTag
        @unknown default:
            return nil
        }
    }
    
    private func writeToNDEFTag(session: NFCTagReaderSession, ndefTag: NFCNDEFTag) {
        ndefTag.queryNDEFStatus { (status, capacity, error) in
            if let error = error {
                session.alertMessage = "Unable to query tag status."
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            
            switch status {
            case .readOnly:
                session.alertMessage = "Tag is read-only."
                session.invalidate()
            case .notSupported:
                session.alertMessage = "Tag is not NDEF-compliant."
                session.invalidate()
            case .readWrite:
                guard let message = self.messageToWrite else {
                    session.alertMessage = "No message to write."
                    session.invalidate()
                    return
                }
                
                ndefTag.writeNDEF(message) { error in
                    if let error = error {
                        session.alertMessage = "Write failed."
                        session.invalidate(errorMessage: error.localizedDescription)
                    } else {
                        session.alertMessage = "Write successful!"
                        DispatchQueue.main.async {
                            self.isWritingSuccessful = true
                        }
                        session.invalidate()
                    }
                }
            @unknown default:
                session.alertMessage = "Unsupported NDEF status."
                session.invalidate()
            }
        }
    }
}