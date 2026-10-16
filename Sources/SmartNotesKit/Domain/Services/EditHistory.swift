import Foundation

/// Note-level undo/redo for the block editor. Stores snapshots of the blocks
/// taken *before* each change. Consecutive typing in one block within a short
/// interval is coalesced into a single undo step; structural edits never are.
public struct EditHistory {
    public struct Caret: Equatable, Sendable {
        public var blockID: UUID
        public var offset: Int

        public init(blockID: UUID, offset: Int) {
            self.blockID = blockID
            self.offset = offset
        }
    }

    public struct Snapshot: Equatable {
        public var blocks: [NoteBlock]
        public var caret: Caret?

        public init(blocks: [NoteBlock], caret: Caret?) {
            self.blocks = blocks
            self.caret = caret
        }
    }

    public enum Kind: Equatable {
        case typing(blockID: UUID)
        case structural
    }

    public let limit: Int
    public let coalescingInterval: TimeInterval
    public private(set) var undoStack: [Snapshot] = []
    public private(set) var redoStack: [Snapshot] = []
    private var lastKind: Kind?
    private var lastTime: Date?

    public init(limit: Int = 200, coalescingInterval: TimeInterval = 2) {
        self.limit = limit
        self.coalescingInterval = coalescingInterval
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Call before applying a change, with the state as it is now.
    public mutating func record(before snapshot: Snapshot, kind: Kind, at time: Date) {
        redoStack.removeAll()
        if case .typing = kind, kind == lastKind, let lastTime, time.timeIntervalSince(lastTime) < coalescingInterval {
            self.lastTime = time
            return
        }
        undoStack.append(snapshot)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        lastKind = kind
        lastTime = time
    }

    /// Returns the state to restore; `current` becomes redoable.
    public mutating func undo(current: Snapshot) -> Snapshot? {
        guard let snapshot = undoStack.popLast() else { return nil }
        redoStack.append(current)
        lastKind = nil
        return snapshot
    }

    public mutating func redo(current: Snapshot) -> Snapshot? {
        guard let snapshot = redoStack.popLast() else { return nil }
        undoStack.append(current)
        lastKind = nil
        return snapshot
    }

    /// Ends the current typing run (e.g. the caret moved elsewhere).
    public mutating func breakCoalescing() {
        lastKind = nil
    }
}
