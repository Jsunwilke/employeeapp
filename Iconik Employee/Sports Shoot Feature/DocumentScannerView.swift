//
//  DocumentScannerView.swift
//  Iconik Employee
//
//  Created by administrator on 5/16/25.
//


//
//  DocumentScannerView.swift
//  Iconik Employee
//
//  Created by administrator on 5/16/25.
//

import SwiftUI
import UIKit
import VisionKit

// A SwiftUI wrapper for VNDocumentCameraViewController
struct DocumentScannerView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    var onScan: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scannerViewController = VNDocumentCameraViewController()
        scannerViewController.delegate = context.coordinator
        return scannerViewController
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // Nothing to update
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        
        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Convert scanned pages to UIImages
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: i)
                images.append(image)
            }
            
            // Pass the scanned images back
            parent.onScan(images)
            
            // Dismiss the scanner
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("Document scanner failed with error: \(error.localizedDescription)")
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
