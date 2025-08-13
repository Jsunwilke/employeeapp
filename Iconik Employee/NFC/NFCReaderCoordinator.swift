import Foundation
import CoreNFC
import SwiftUI

class NFCReaderCoordinator: NSObject, NFCNDEFReaderSessionDelegate, ObservableObject {
    @Published var scannedCardNumber: String?
    @Published var errorMessage: String?
    var session: NFCNDEFReaderSession?
    
    func beginScanning() {
        guard NFCNDEFReaderSession.readingAvailable else {
            self.errorMessage = "NFC scanning is not supported on this device."
            return
        }
        
        // IMPORTANT CHANGE: Setting invalidateAfterFirstRead to false
        // This allows us to manually invalidate for faster UI dismissal
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near the NFC tag."
        session?.begin()
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorFirstNDEFTagRead {
            return
        }
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first, message.records.count == 1 else {
            DispatchQueue.main.async {
                self.errorMessage = "Unexpected tag format. Please scan a valid tag."
            }
            
            // OPTIMIZATION: Immediately invalidate the session to dismiss the UI
            session.invalidate()
            return
        }
        
        let record = message.records.first!
        let payloadData = record.payload
        
        guard payloadData.count > 0 else {
            DispatchQueue.main.async {
                self.errorMessage = "Tag payload is empty."
            }
            
            // OPTIMIZATION: Immediately invalidate the session to dismiss the UI
            session.invalidate()
            return
        }
        
        let statusByte = payloadData[0]
        let languageCodeLength = Int(statusByte & 0x3F)
        
        guard payloadData.count >= 1 + languageCodeLength + 1 else {
            DispatchQueue.main.async {
                self.errorMessage = "Tag payload is too short."
            }
            
            // OPTIMIZATION: Immediately invalidate the session to dismiss the UI
            session.invalidate()
            return
        }
        
        let textRange = Range(uncheckedBounds: (lower: 1 + languageCodeLength, upper: payloadData.count))
        let textData = payloadData.subdata(in: textRange)
        
        if let cardNumber = String(data: textData, encoding: .utf8) {
            let trimmed = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                DispatchQueue.main.async {
                    self.errorMessage = "No card number found on tag."
                }
            } else {
                // OPTIMIZATION: Get the data first, then invalidate quickly
                let finalCardNumber = trimmed
                
                // OPTIMIZATION: First invalidate for faster UI dismissal (silently)
                session.invalidate()
                
                // THEN update our state, which will trigger the UI to show the form
                DispatchQueue.main.async {
                    self.scannedCardNumber = finalCardNumber
                }
                
                return
            }
        } else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to decode tag text."
            }
        }
        
        // OPTIMIZATION: Always invalidate quickly for error cases
        session.invalidate()
    }
}