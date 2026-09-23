import Foundation

enum RecordingState {
    case idle, starting, recording, stopping

    var canStop: Bool { self == .starting || self == .recording }
    var isActive: Bool { self != .idle }
}

/// Mutated on the main thread. A token fences callbacks from cancelled sessions.
struct RecordingLifecycle {
    private(set) var state: RecordingState = .idle
    private(set) var sessionID: UUID?

    mutating func begin() -> UUID? {
        guard state == .idle else { return nil }
        let id = UUID()
        sessionID = id
        state = .starting
        return id
    }

    mutating func didStart(_ id: UUID) -> Bool {
        guard sessionID == id, state == .starting else { return false }
        state = .recording
        return true
    }

    mutating func requestStop() -> UUID? {
        guard state.canStop, let id = sessionID else { return nil }
        state = .stopping
        return id
    }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard sessionID == id else { return false }
        state = .idle
        sessionID = nil
        return true
    }
}
