//
//  QRScannerView.swift
//  Iconik Employee
//
//  Equipment Management Feature - QR Code Scanner View
//

import SwiftUI
import AVFoundation

struct QRScannerView: View {
    var onCodeScanned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = true
    @State private var torchOn = false
    @State private var lastScannedCode: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera view
                QRScannerCameraView(
                    isScanning: $isScanning,
                    torchOn: $torchOn,
                    onCodeScanned: { code in
                        guard lastScannedCode != code else { return }
                        lastScannedCode = code

                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)

                        // Check if it's an equipment QR code
                        if code.hasPrefix("EQ-") {
                            onCodeScanned(code)
                        }
                    }
                )
                .ignoresSafeArea()

                // Overlay
                VStack {
                    Spacer()

                    // Scan frame
                    ZStack {
                        // Dimmed background
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .mask(
                                HoleShapeMask(holeSize: CGSize(width: 250, height: 250))
                                    .fill(style: FillStyle(eoFill: true))
                            )

                        // Scan frame border
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 250, height: 250)

                        // Corner accents
                        scannerCorners
                    }

                    Spacer()

                    // Instructions
                    VStack(spacing: 12) {
                        Text("Scan Equipment QR Code")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Position the QR code within the frame")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        torchOn.toggle()
                    } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var scannerCorners: some View {
        ZStack {
            // Top-left corner
            CornerShape()
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 40, height: 40)
                .offset(x: -105, y: -105)

            // Top-right corner
            CornerShape()
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(90))
                .offset(x: 105, y: -105)

            // Bottom-left corner
            CornerShape()
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
                .offset(x: -105, y: 105)

            // Bottom-right corner
            CornerShape()
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(180))
                .offset(x: 105, y: 105)
        }
    }
}

// MARK: - Corner Shape

struct CornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Hole Shape Mask

struct HoleShapeMask: Shape {
    var holeSize: CGSize

    func path(in rect: CGRect) -> Path {
        var shape = Rectangle().path(in: rect)
        let holeRect = CGRect(
            x: rect.midX - holeSize.width / 2,
            y: rect.midY - holeSize.height / 2,
            width: holeSize.width,
            height: holeSize.height
        )
        shape.addRoundedRect(in: holeRect, cornerSize: CGSize(width: 20, height: 20))
        return shape
    }
}

// MARK: - QR Scanner Camera View

struct QRScannerCameraView: UIViewRepresentable {
    @Binding var isScanning: Bool
    @Binding var torchOn: Bool
    var onCodeScanned: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black

        let captureSession = AVCaptureSession()
        context.coordinator.captureSession = captureSession

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            return view
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return view
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return view
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return view
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update torch
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            try? device.lockForConfiguration()
            device.torchMode = torchOn ? .on : .off
            device.unlockForConfiguration()
        }

        // Stop scanning when isScanning is false
        if !isScanning {
            context.coordinator.stopSession()
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Critical: Stop and clean up the capture session when view is removed
        coordinator.stopSession()
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var onCodeScanned: (String) -> Void

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  metadataObject.type == .qr,
                  let stringValue = metadataObject.stringValue else {
                return
            }

            onCodeScanned(stringValue)
        }

        // Stop the capture session
        func stopSession() {
            guard let session = captureSession, session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }

        // Clean up resources to prevent memory leaks
        func cleanup() {
            stopSession()

            // Remove preview layer
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil

            // Remove inputs and outputs
            if let session = captureSession {
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
            }

            captureSession = nil
        }

        deinit {
            cleanup()
        }
    }
}

// MARK: - Preview

struct QRScannerView_Previews: PreviewProvider {
    static var previews: some View {
        QRScannerView { code in
            print("Scanned: \(code)")
        }
    }
}
