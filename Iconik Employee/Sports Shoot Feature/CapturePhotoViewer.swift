//
//  CapturePhotoViewer.swift
//  Iconik Employee
//
//  Full-screen photo viewer for capture thumbnails.
//  Tap a thumbnail in the roster → view it full-screen with pinch/zoom.
//  Filmstrip at bottom for browsing multiple captures per subject.
//  "Use for Banner" writes "Banner: XXXX" into the athlete's notes.
//

import SwiftUI
import UIKit
import Photos

struct CapturePhotoViewer: View {
    let subjectName: String
    let thumbs: [CaptureThumb]
    @Binding var isPresented: Bool
    var onBannerSelected: ((Int) -> Void)? = nil
    var onMoveRequested: ((Int) -> Void)? = nil  // imageNumber — caller shows athlete picker

    // Current image index — init to last image
    @State private var selectedIndex: Int

    // Zoom/pan state (reset on image change)
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    // Banner
    @State private var bannerImageNumber: Int? = nil  // currently selected banner
    @State private var showBannerConfirm = false

    // Save
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""

    init(subjectName: String, thumbs: [CaptureThumb], isPresented: Binding<Bool>, onBannerSelected: ((Int) -> Void)? = nil, onMoveRequested: ((Int) -> Void)? = nil) {
        self.subjectName = subjectName
        self.thumbs = thumbs
        self._isPresented = isPresented
        self.onBannerSelected = onBannerSelected
        self.onMoveRequested = onMoveRequested
        self._selectedIndex = State(initialValue: max(0, thumbs.count - 1))
    }

    private var currentThumb: CaptureThumb {
        guard selectedIndex >= 0, selectedIndex < thumbs.count else {
            return thumbs.last ?? CaptureThumb(image: UIImage(), imageNumber: nil)
        }
        return thumbs[selectedIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Main image
            Image(uiImage: currentThumb.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, thumbs.count > 1 ? 84 : 0)
                .scaleEffect(scale)
                .offset(x: offset.width + dragOffset.width,
                        y: offset.height + dragOffset.height)
                .gesture(pinchGesture)
                .gesture(scale > 1.0 ? panGesture : nil)
                .gesture(scale == 1.0 ? dismissGesture : nil)
                .onTapGesture(count: 2) { doubleTapZoom() }

            // Top bar
            VStack {
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subjectName)
                            .font(.headline)
                            .foregroundColor(.white)
                        if let imgNum = currentThumb.imageNumber {
                            Text("Image #\(imgNum)" + (bannerImageNumber == imgNum ? " — Banner" : ""))
                                .font(.caption)
                                .foregroundColor(bannerImageNumber == imgNum ? .yellow : .white.opacity(0.7))
                        } else if thumbs.count > 1 {
                            Text("\(selectedIndex + 1) of \(thumbs.count)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    // Banner button — only show if this image has an image number
                    if let imgNum = currentThumb.imageNumber {
                        Button(action: {
                            bannerImageNumber = imgNum
                            onBannerSelected?(imgNum)
                            showBannerConfirm = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: bannerImageNumber == imgNum ? "flag.fill" : "flag")
                                    .font(.system(size: 16))
                                Text("Banner")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(bannerImageNumber == imgNum ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(bannerImageNumber == imgNum ? Color.yellow : Color.white.opacity(0.25))
                            .clipShape(Capsule())
                        }
                        .frame(height: 44)
                    }

                    Menu {
                        if let imgNum = currentThumb.imageNumber, onMoveRequested != nil {
                            Button(action: { onMoveRequested?(imgNum) }) {
                                Label("Move to Another Athlete", systemImage: "arrow.right.arrow.left")
                            }
                        }
                        Button(action: { saveToPhotos() }) {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        if thumbs.count > 1 {
                            Button(action: { saveAllToPhotos() }) {
                                Label("Save All (\(thumbs.count))", systemImage: "square.and.arrow.down.on.square")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }

            // Filmstrip at bottom (only when multiple images)
            if thumbs.count > 1 {
                VStack {
                    Spacer()
                    filmstripView
                }
            }
        }
        .alert("Banner Selected", isPresented: $showBannerConfirm) {
            Button("OK") { }
        } message: {
            if let num = bannerImageNumber {
                Text("Banner: \(num) saved to \(subjectName)'s notes")
            }
        }
        .alert("Save Photo", isPresented: $showSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveAlertMessage)
        }
    }

    // MARK: - Filmstrip

    private var filmstripView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(thumbs.enumerated()), id: \.offset) { index, thumb in
                        ZStack(alignment: .bottom) {
                            Image(uiImage: thumb.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(index == selectedIndex ? Color.white : Color.clear, lineWidth: 3)
                                )
                                .opacity(index == selectedIndex ? 1.0 : 0.6)

                            // Banner indicator on filmstrip
                            if let imgNum = thumb.imageNumber, imgNum == bannerImageNumber {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow)
                                    .padding(2)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .offset(y: -2)
                            }
                        }
                        .id(index)
                        .onTapGesture {
                            selectImage(index)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.black.opacity(0.7))
            .onChange(of: selectedIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Image Selection

    private func selectImage(_ index: Int) {
        guard index >= 0, index < thumbs.count else { return }
        scale = 1.0
        offset = .zero
        lastOffset = .zero
        dragOffset = .zero
        selectedIndex = index
    }

    // MARK: - Gestures

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale *= delta
            }
            .onEnded { _ in
                lastScale = 1.0
                withAnimation(.spring()) {
                    scale = min(max(scale, 1), 4)
                    if scale == 1.0 {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(vertical) > 100 && abs(vertical) > abs(horizontal) {
                    isPresented = false
                } else if abs(horizontal) > 80 && abs(horizontal) > abs(vertical) && thumbs.count > 1 {
                    if horizontal < 0 && selectedIndex < thumbs.count - 1 {
                        selectImage(selectedIndex + 1)
                    } else if horizontal > 0 && selectedIndex > 0 {
                        selectImage(selectedIndex - 1)
                    }
                    withAnimation(.spring()) { dragOffset = .zero }
                } else {
                    withAnimation(.spring()) { dragOffset = .zero }
                }
            }
    }

    // MARK: - Actions

    private func doubleTapZoom() {
        withAnimation(.spring()) {
            if scale > 1 {
                scale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
            }
        }
    }

    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status == .authorized || status == .limited {
                UIImageWriteToSavedPhotosAlbum(currentThumb.image, nil, nil, nil)
                DispatchQueue.main.async {
                    saveAlertMessage = "Photo saved"
                    showSaveAlert = true
                }
            } else {
                DispatchQueue.main.async {
                    saveAlertMessage = "Photo library access required"
                    showSaveAlert = true
                }
            }
        }
    }

    private func saveAllToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status == .authorized || status == .limited {
                for thumb in thumbs {
                    UIImageWriteToSavedPhotosAlbum(thumb.image, nil, nil, nil)
                }
                DispatchQueue.main.async {
                    saveAlertMessage = "\(thumbs.count) photos saved"
                    showSaveAlert = true
                }
            } else {
                DispatchQueue.main.async {
                    saveAlertMessage = "Photo library access required"
                    showSaveAlert = true
                }
            }
        }
    }
}
