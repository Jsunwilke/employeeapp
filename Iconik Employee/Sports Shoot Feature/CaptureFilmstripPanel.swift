//
//  CaptureFilmstripPanel.swift
//  Iconik Employee
//
//  Landscape-only filmstrip showing ALL captured photos grouped by subject.
//  Shared between PoserStationView (non-sports) and FPSportsRosterView_iPad (sports).
//  Photos arrive via WebSocket thumbnails — no additional data fetching needed.
//
//  Layout matches Production app: images first, then subject header below with
//  move arrows to reassign images between adjacent segments.
//

import SwiftUI

// MARK: - Data Model

struct FilmstripSegment: Identifiable {
    let id: String           // subject ID
    let subjectName: String
    let photoCount: Int
    let thumbnails: [CaptureThumb]
}

// MARK: - Filmstrip Panel

struct CaptureFilmstripPanel: View {
    let segments: [FilmstripSegment]
    let activeSubjectName: String?
    let onTapPhoto: (String, String, [CaptureThumb]) -> Void  // (subjectId, subjectName, thumbs)
    let onMoveImage: ((String, String, Int) -> Void)?          // (fromSubjectId, toSubjectId, imageNumber)

    private var totalPhotos: Int {
        segments.reduce(0) { $0 + $1.photoCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Panel header
            HStack {
                Image(systemName: "film")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Captures")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(totalPhotos)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            // Active subject name
            if let name = activeSubjectName, !name.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.08))
            }

            Divider()

            // Content
            if segments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No photos yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { si, segment in
                                // Images first (above the header)
                                ForEach(segment.thumbnails) { thumb in
                                    thumbnailCell(thumb, segment: segment)
                                        .padding(.horizontal, 6)
                                        .padding(.bottom, 4)
                                }

                                // Subject header below images (acts as divider)
                                segmentHeader(segment, index: si)
                            }
                        }
                    }
                    .onChange(of: totalPhotos) { _ in
                        if let first = segments.first {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 240)
        .background(Color(.systemBackground))
    }

    // MARK: - Segment Header (below images, with move arrows)

    private func segmentHeader(_ segment: FilmstripSegment, index si: Int) -> some View {
        HStack(spacing: 0) {
            // Up arrow — claim last image from segment above into this segment
            let canMoveUp = si > 0 && !(segments[si - 1].thumbnails.isEmpty)
            Button(action: {
                guard canMoveUp, let thumb = segments[si - 1].thumbnails.last, let imgNum = thumb.imageNumber else { return }
                onMoveImage?(segments[si - 1].id, segment.id, imgNum)
            }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(!canMoveUp)
            .opacity(canMoveUp ? 1.0 : 0.3)

            // Subject name + count
            Text(segment.subjectName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(segment.photoCount)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color(.systemGray5)))

            // Down arrow — claim first image from segment below into this segment
            let canMoveDown = si < segments.count - 1 && !(segments[si + 1].thumbnails.isEmpty)
            Button(action: {
                guard canMoveDown, let thumb = segments[si + 1].thumbnails.first, let imgNum = thumb.imageNumber else { return }
                onMoveImage?(segments[si + 1].id, segment.id, imgNum)
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(!canMoveDown)
            .opacity(canMoveDown ? 1.0 : 0.3)
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .id(segment.id)
    }

    // MARK: - Thumbnail Cell

    private func thumbnailCell(_ thumb: CaptureThumb, segment: FilmstripSegment) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: thumb.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Image number overlay
            if let num = thumb.imageNumber {
                Text("#\(num)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTapPhoto(segment.id, segment.subjectName, segment.thumbnails)
        }
    }
}
