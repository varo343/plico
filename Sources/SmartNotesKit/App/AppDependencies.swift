import Foundation
import SwiftData

/// Composition root: owns the model container and hands out repositories.
@MainActor
public final class AppDependencies {
    public let modelContainer: ModelContainer
    public let notes: NoteRepository
    public let externalItems: ExternalItemRepository
    public let integrationStates: IntegrationStateRepository
    public let settings: SettingsStore
    public let outlookSession: OutlookSession
    public let outlookPreferences: OutlookPreferences
    public let isInMemory: Bool

    public init(modelContainer: ModelContainer, settings: SettingsStore, isInMemory: Bool,
                outlookSession: OutlookSession? = nil, outlookPreferences: OutlookPreferences = OutlookPreferences()) {
        self.modelContainer = modelContainer
        // Saves are explicit (autosave debounce lives in the editor layer).
        modelContainer.mainContext.autosaveEnabled = false
        self.notes = SwiftDataNoteRepository(container: modelContainer)
        self.externalItems = SwiftDataExternalItemRepository(container: modelContainer)
        self.integrationStates = SwiftDataIntegrationStateRepository(container: modelContainer)
        self.settings = settings
        self.isInMemory = isInMemory
        self.outlookSession = outlookSession ?? OutlookSession(tokenStore: KeychainTokenStore())
        self.outlookPreferences = outlookPreferences
    }

    /// Permanently removes all local data: notes (including Trash), cached
    /// Outlook items, sync state and settings. Callers must confirm with the user first.
    public func deleteAllData() throws {
        try notes.deleteAll()
        let context = modelContainer.mainContext
        try context.fetch(FetchDescriptor<ExternalItemRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<IntegrationStateRecord>()).forEach(context.delete)
        try context.save()
        settings.save(.defaults)
    }

    /// The real on-disk store in Application Support.
    public static func live() throws -> AppDependencies {
        let url = try PersistenceController.defaultStoreURL()
        let container = try PersistenceController.makeContainer(.onDisk(url))
        return AppDependencies(modelContainer: container, settings: UserDefaultsSettingsStore(), isInMemory: false)
    }

    /// Throwaway store for tests, previews and demos. Settings are isolated too.
    public static func inMemory(seedSampleData: Bool = false, now: Date = .now) throws -> AppDependencies {
        let container = try PersistenceController.makeContainer(.inMemory)
        let suite = "SmartNotes.InMemory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let deps = AppDependencies(
            modelContainer: container,
            settings: UserDefaultsSettingsStore(defaults: defaults),
            isInMemory: true,
            outlookSession: OutlookSession(tokenStore: InMemoryTokenStore()),
            outlookPreferences: OutlookPreferences(defaults: defaults)
        )
        if seedSampleData {
            for note in SampleData.notes(now: now) {
                try deps.notes.save(note)
            }
        }
        return deps
    }

    /// Chooses the store from launch arguments:
    /// `--sample-data` seeds an in-memory store (never touches real notes),
    /// `--in-memory` uses an empty in-memory store.
    public static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppDependencies {
        if arguments.contains("--sample-data") {
            return try inMemory(seedSampleData: true)
        }
        if arguments.contains("--in-memory") {
            return try inMemory()
        }
        return try live()
    }
}
