import Foundation

/// Writes a user-triggered backup: a dated folder with `notes.json` (lossless)
/// and one Markdown file per note (`Trash/` for trashed notes).
@MainActor
public enum DataExporter {
    public struct Result: Equatable {
        public var folder: URL
        public var noteCount: Int
    }

    public static func export(_ notes: [Note], into parent: URL, now: Date = .now) throws -> Result {
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash)) + " " +
            now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).replacingOccurrences(of: ":", with: "")
        var folder = parent.appendingPathComponent("Smart Notes Export \(stamp)", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("Smart Notes Export \(stamp) \(suffix)", isDirectory: true)
            suffix += 1
        }
        let markdown = folder.appendingPathComponent("Markdown", isDirectory: true)
        let trash = markdown.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        try NoteExport.json(notes, exportedAt: now).write(to: folder.appendingPathComponent("notes.json"), options: .atomic)
        var usedActive = Set<String>()
        var usedTrash = Set<String>()
        for note in notes {
            let directory = note.isTrashed ? trash : markdown
            let name = note.isTrashed ? NoteExport.fileName(for: note, used: &usedTrash) : NoteExport.fileName(for: note, used: &usedActive)
            try NoteExport.markdown(note).write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        if usedTrash.isEmpty { try? FileManager.default.removeItem(at: trash) }
        return Result(folder: folder, noteCount: notes.count)
    }
}
