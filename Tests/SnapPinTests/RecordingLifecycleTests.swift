import Foundation
import Testing
@testable import SnapPin

struct RecordingLifecycleTests {
    @Test func normalStartStopAndExport() throws {
        var lifecycle = RecordingLifecycle()
        #expect(!lifecycle.state.isActive)
        let pendingID = lifecycle.begin()
        let id = try #require(pendingID)
        #expect(lifecycle.state == .starting)
        #expect(lifecycle.state.canStop)
        #expect(lifecycle.didStart(id) == true)
        #expect(lifecycle.state == .recording)
        #expect(lifecycle.requestStop() == id)
        #expect(lifecycle.state == .stopping)
        #expect(lifecycle.state.isActive)
        #expect(!lifecycle.state.canStop)
        #expect(lifecycle.begin() == nil) // Export still owns its frames.
        #expect(lifecycle.finish(id) == true)
        #expect(lifecycle.state == .idle)
    }

    @Test func secondF2CancelsPendingStartup() throws {
        var lifecycle = RecordingLifecycle()
        let pendingID = lifecycle.begin()
        let id = try #require(pendingID)
        #expect(lifecycle.requestStop() == id)
        #expect(lifecycle.didStart(id) == false)
        #expect(lifecycle.state == .stopping)
        #expect(lifecycle.requestStop() == nil)
        #expect(lifecycle.finish(id) == true)
        #expect(!lifecycle.state.isActive)
    }

    @Test func oldCallbacksCannotAffectNewSession() throws {
        var lifecycle = RecordingLifecycle()
        let firstID = lifecycle.begin()
        let old = try #require(firstID)
        #expect(lifecycle.finish(old) == true)
        let nextID = lifecycle.begin()
        let current = try #require(nextID)
        #expect(current != old)
        #expect(lifecycle.didStart(old) == false)
        #expect(lifecycle.finish(old) == false)
        #expect(lifecycle.sessionID == current)
        #expect(lifecycle.state == .starting)
        #expect(lifecycle.didStart(current) == true)
    }

    @Test func repeatedF2CannotStartOverlappingStreams() throws {
        var lifecycle = RecordingLifecycle()
        for _ in 0..<100 {
            let pendingID = lifecycle.begin()
            let id = try #require(pendingID)
            #expect(lifecycle.begin() == nil)
            #expect(lifecycle.requestStop() == id)
            #expect(lifecycle.requestStop() == nil)
            #expect(lifecycle.begin() == nil)
            #expect(lifecycle.finish(id) == true)
            #expect(lifecycle.finish(id) == false)
        }
    }

    @Test func failureRestoresIdleFromEveryPhase() throws {
        for phase in [RecordingState.starting, .recording, .stopping] {
            var lifecycle = RecordingLifecycle()
            let pendingID = lifecycle.begin()
            let id = try #require(pendingID)
            if phase != .starting { #expect(lifecycle.didStart(id) == true) }
            if phase == .stopping { #expect(lifecycle.requestStop() == id) }
            #expect(lifecycle.finish(id) == true)
            #expect(!lifecycle.state.isActive)
            #expect(lifecycle.sessionID == nil)
        }
    }
}
