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
            // Convert scanned pages to UIImages, downsizing to avoid overloading the Claude API
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: i)
                let downsized = downsizeImage(image, maxDimension: 1600)
                images.append(downsized)
            }

            // Pass the scanned images back
            parent.onScan(images)

            // Dismiss the scanner
            parent.presentationMode.wrappedValue.dismiss()
        }

        // Downsize image to a max dimension — camera scans are very high res (3000-4000px)
        // and cause 529 "overloaded" errors when sent to Claude API at full size
        private func downsizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
            let maxSide = max(image.size.width, image.size.height)
            guard maxSide > maxDimension else { return image }
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
