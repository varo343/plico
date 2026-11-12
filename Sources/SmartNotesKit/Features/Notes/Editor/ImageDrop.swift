import AppKit
import UniformTypeIdentifiers

/// Reading pictures out of drags, pastes and the open panel.
///
/// The order matters: a drag carries a small preview of what is dragged as
/// image data, so the real file (a file URL, or a file the source app promises
/// to write, like the screenshot thumbnail or a browser) always wins over it.
enum ImageDrop {
    /// Image data types, in order of preference (TIFF last: drag previews use it).
    private static let dataTypes: [NSPasteboard.PasteboardType] = [
        .png, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier), .tiff,
    ]
    /// Pasteboard types that can carry a picture: a file, a promised file, or the image itself.
    static var pasteboardTypes: [NSPasteboard.PasteboardType] {
        let promised: [NSPasteboard.PasteboardType] = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return [NSPasteboard.PasteboardType.fileURL] + promised + dataTypes
    }
    private static var imageFiles: [NSPasteboard.ReadingOptionKey: Any] { [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ] }

    /// What a drag or a paste carries, read while its pasteboard is available.
    struct Payload {
        var files: [URL] = []
        var promises: [NSFilePromiseReceiver] = []
        var data: Data?

        var isEmpty: Bool { files.isEmpty && promises.isEmpty && data == nil }
    }

    /// The pasteboard holds image files, promised image files or image data.
    static func hasImages(_ pasteboard: NSPasteboard) -> Bool {
        !payload(from: pasteboard).isEmpty
    }

    /// `ignoringText`: for a paste, image data that comes with text (a copied
    /// web page or document) is that text's decoration, so it is not a picture.
    static func payload(from pasteboard: NSPasteboard, ignoringText: Bool = false) -> Payload {
        var payload = Payload()
        payload.files = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFiles) as? [URL] ?? []
        if !payload.files.isEmpty { return payload }
        payload.promises = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? [])
            .filter { receiver in receiver.fileTypes.contains { UTType($0)?.conforms(to: .image) == true } }
        if ignoringText, payload.promises.isEmpty, pasteboard.availableType(from: [.string, .rtf, .html]) != nil { return payload }
        // Kept beside promises as a fallback if the source app never writes its file.
        payload.data = pasteboard.availableType(from: dataTypes).flatMap { pasteboard.data(forType: $0) }
        return payload
    }

    /// Image bytes available right away (files and image data); promised
    /// files need `load(_:)`.
    static func immediateData(_ payload: Payload) -> [Data] {
        let files = payload.files.compactMap { try? Data(contentsOf: $0) }
        return files.isEmpty ? payload.data.map { [$0] } ?? [] : files
    }

    /// Every picture in the payload, waiting for promised files to be written.
    @MainActor
    static func load(_ payload: Payload) async -> [Data] {
        guard payload.files.isEmpty, !payload.promises.isEmpty else { return immediateData(payload) }
        var result: [Data] = []
        for receiver in payload.promises {
            result += await receive(receiver)
        }
        return result.isEmpty ? immediateData(payload) : result
    }

    /// Asks the source app to write its promised files into a temporary folder.
    @MainActor
    private static func receive(_ receiver: NSFilePromiseReceiver) async -> [Data] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PlicoDrops-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let collector = PromiseCollector(expected: max(receiver.fileTypes.count, 1))
        return await withCheckedContinuation { continuation in
            collector.onFinish = { continuation.resume(returning: $0) }
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: collector.queue) { url, error in
                collector.add(error == nil ? try? Data(contentsOf: url) : nil)
            }
            // A source app that never delivers must not hang the drop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { collector.finish() }
        }
    }

    /// Prepared off the main thread: big photos are scaled down (see `NoteImage.importing`).
    static func images(from data: [Data]) async -> [NoteImage] {
        await Task.detached(priority: .userInitiated) { data.compactMap { NoteImage.importing($0) } }.value
    }

    /// The pictures in a SwiftUI drop: image files, else the best image type
    /// each item offers (a promised PNG or JPEG before a TIFF preview).
    @MainActor
    static func data(from providers: [NSItemProvider]) async -> [Data] {
        var result: [Data] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await fileURL(from: provider),
               UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
               let data = try? Data(contentsOf: url) {
                result.append(data)
                continue
            }
            let types = provider.registeredTypeIdentifiers.filter { UTType($0)?.conforms(to: .image) == true }
            let preferred = types.filter { UTType($0)?.conforms(to: .tiff) == false } + types.filter { UTType($0)?.conforms(to: .tiff) == true }
            for type in preferred {
                var data = await fileData(from: provider, type: type)
                if data == nil { data = await imageData(from: provider, type: type) }
                if let data {
                    result.append(data)
                    break
                }
            }
        }
        return result
    }

    @MainActor
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    /// The file is only there during the callback, so it's read right away.
    @MainActor
    private static func fileData(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                continuation.resume(returning: url.flatMap { try? Data(contentsOf: $0) })
            }
        }
    }

    @MainActor
    private static func imageData(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
        }
    }

    /// Format ▸ Insert Image… and "/image": an open panel for picture files.
    @MainActor
    static func pick() async -> [NoteImage] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Insert"
        panel.message = "Choose pictures to put in the note"
        guard panel.runModal() == .OK else { return [] }
        let urls = panel.urls
        return await images(from: urls.compactMap { try? Data(contentsOf: $0) })
    }
}

/// Gathers promised files as the source app writes them; finishes once, when
/// all have arrived or on timeout.
private final class PromiseCollector: @unchecked Sendable {
    let queue = OperationQueue()
    var onFinish: (([Data]) -> Void)?
    private let lock = NSLock()
    private let expected: Int
    private var received: [Data] = []
    private var count = 0
    private var isFinished = false

    init(expected: Int) {
        self.expected = expected
        queue.qualityOfService = .userInitiated
    }

    func add(_ data: Data?) {
        lock.lock()
        count += 1
        if let data { received.append(data) }
        let done = count >= expected
        lock.unlock()
        if done { finish() }
    }

    func finish() {
        lock.lock()
        guard !isFinished else { return lock.unlock() }
        isFinished = true
        let result = received
        let callback = onFinish
        lock.unlock()
        callback?(result)
    }
}
