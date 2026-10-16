import Foundation
import SwiftData

public enum PersistenceError: Error, LocalizedError {
    case storeUnavailable(underlying: Error)
    case undecodableBlock(id: UUID, underlying: Error)
    case noteNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .storeUnavailable(let error):
            "The notes database could not be opened. (\(error.localizedDescription))"
        case .undecodableBlock(let id, _):
            "A note block (\(id.uuidString)) could not be read."
        case .noteNotFound:
            "The note no longer exists."
        }
    }
}

/// Creates the SwiftData container.
public enum PersistenceController {
    public enum Storage {
        case inMemory
        case onDisk(URL)
    }

    /// `~/Library/Application Support/SmartNotes/SmartNotes.store`
    public static func defaultStoreURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("SmartNotes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("SmartNotes.store")
    }

    public static func makeContainer(_ storage: Storage) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SmartNotesSchemaV1.self)
        let configuration: ModelConfiguration
        switch storage {
        case .inMemory:
            // A unique name keeps in-memory stores (e.g. per test) isolated.
            configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        case .onDisk(let url):
            configuration = ModelConfiguration(schema: schema, url: url)
        }
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SmartNotesMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            throw PersistenceError.storeUnavailable(underlying: error)
        }
    }
}
