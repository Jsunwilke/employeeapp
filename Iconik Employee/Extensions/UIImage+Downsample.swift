import UIKit

extension UIImage {
    /// Resize so the longest side is at most `maxDimension`, preserving aspect
    /// ratio, then JPEG-encode. Upload sites were encoding full-resolution
    /// camera images (often 12 MP+), producing multi-MB uploads and memory
    /// spikes; a 2048px longest side is plenty for viewing and keeps files
    /// small. Images already within the limit are only re-encoded, not upscaled.
    func downsampledJPEGData(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else {
            return jpegData(compressionQuality: quality)
        }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                 // newSize is already in pixels
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
