import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture in a note (an `.image` block): the image file's bytes as they
/// were dropped or pasted, scaled down first when they are very large.
public struct NoteImage: Hashable, Sendable, Codable {
    /// Names this picture for caches and saving; not the block's ID.
    public let id: UUID
    public let data: Data

    /// Nil when `data` is not an image the system can read.
    public init?(data: Data, id: UUID = UUID()) {
        guard Self.pixelSize(of: data) != nil else { return nil }
        self.id = id
        self.data = data
    }

    /// Restores a stored picture without checking it again.
    init(storedData data: Data, id: UUID) {
        self.id = id
        self.data = data
    }

    /// Width and height in pixels, before any EXIF rotation.
    public static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// A new picture from dropped or pasted bytes. Photos larger than
    /// `maxPixelSize` on their long side, or heavier than `maxBytes`, are
    /// scaled down (keeping transparency) so notes stay quick to open and save;
    /// formats that aren't compact (TIFF, BMP…) become PNG or JPEG.
    public static func importing(_ data: Data, maxPixelSize: Int = 3200, maxBytes: Int = 6_000_000) -> NoteImage? {
        guard let size = pixelSize(of: data), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Compact formats are kept as they are; TIFF and the like (a screenshot on the clipboard) are re-encoded.
        let type = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)
        let isCompact = [UTType.png, .jpeg, .heic, .gif, .webP].contains { type?.conforms(to: $0) == true }
        guard !isCompact || Int(max(size.width, size.height)) > maxPixelSize || data.count > maxBytes else { return NoteImage(data: data) }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, Int(max(size.width, size.height))),
              ] as CFDictionary) else { return NoteImage(data: data) }
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let output = NSMutableData()
        let outputType = hasAlpha ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithData(output, outputType.identifier as CFString, 1, nil) else { return NoteImage(data: data) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return NoteImage(data: data) }
        return NoteImage(data: output as Data)
    }

    /// Hashes the ID and size only: hashing every byte of a photo is wasted work.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(data.count)
    }

    /// Same: a picture's bytes never change under its ID, so they aren't
    /// compared byte by byte (blocks are compared on every editor update).
    public static func == (lhs: NoteImage, rhs: NoteImage) -> Bool {
        lhs.id == rhs.id && lhs.data.count == rhs.data.count
    }
}
