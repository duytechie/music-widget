import XCTest
import CoreGraphics
@testable import ArtworkCore

final class ArtworkCoreTests: XCTestCase {
    private let first = Track(id: "a", title: "One", artist: "Artist", album: "Album")
    private let second = Track(id: "b", title: "Two", artist: "Artist", album: "Album")

    func testKeepCoverAcrossPauseStopAndClose() {
        var session = ArtworkSession()
        session.accept(.init(state: .playing, track: first))
        XCTAssertTrue(session.finish(generation: session.generation))
        let generation = session.generation
        for snapshot in [PlaybackSnapshot(state: .paused, track: first), .init(state: .stopped), .init(state: .closed)] {
            XCTAssertFalse(session.accept(snapshot))
            XCTAssertEqual(session.track, first)
            XCTAssertTrue(session.hasArtwork)
            XCTAssertEqual(session.generation, generation)
            XCTAssertFalse(session.shouldFetch(at: Date()))
        }
    }

    func testRapidSkippingRejectsStaleArtworkIncludingReturnToSameSong() {
        var session = ArtworkSession()
        session.accept(.init(state: .playing, track: first))
        let originalGeneration = session.generation
        session.accept(.init(state: .playing, track: second))
        session.accept(.init(state: .playing, track: first))
        XCTAssertFalse(session.finish(generation: originalGeneration))
        XCTAssertFalse(session.hasArtwork)
        XCTAssertTrue(session.finish(generation: session.generation))
    }

    func testMissingArtworkUsesBoundedBackoffAndResetsOnTrackChange() {
        var session = ArtworkSession()
        let start = Date(timeIntervalSince1970: 100)
        session.accept(.init(state: .playing, track: first))
        XCTAssertTrue(session.shouldFetch(at: start))
        session.failed(at: start)
        XCTAssertFalse(session.shouldFetch(at: start.addingTimeInterval(0.9)))
        XCTAssertTrue(session.shouldFetch(at: start.addingTimeInterval(1)))
        session.failed(at: start.addingTimeInterval(1))
        XCTAssertFalse(session.shouldFetch(at: start.addingTimeInterval(2.9)))
        XCTAssertTrue(session.shouldFetch(at: start.addingTimeInterval(3)))
        for _ in 0..<4 { session.failed(at: start) }
        XCTAssertFalse(session.shouldFetch(at: start.addingTimeInterval(3600)))
        session.accept(.init(state: .playing, track: second))
        XCTAssertTrue(session.shouldFetch(at: start))
        XCTAssertEqual(session.attempts, 0)
    }

    func testMetadataHandlesUnicodeQuotesAndNewlines() throws {
        let json = #"{"state":"playing","track":{"id":"123","title":"A \"quote\"\nnext line","artist":"Björk","album":"私の音楽"}}"#
        let value = try JSONDecoder().decode(PlaybackSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(value.track?.title, "A \"quote\"\nnext line")
        XCTAssertEqual(value.track?.artist, "Björk")
        XCTAssertEqual(value.track?.album, "私の音楽")
    }

    func testPermissionErrorDetection() {
        XCTAssertTrue(CommandError.failed(1, "Not authorized to send Apple events to Music. (-1743)").isPermissionDenied)
        XCTAssertFalse(CommandError.failed(1, "No artwork. (-1728)").isPermissionDenied)
    }

    func testPositionRecoversWhenSavedDisplayDisappears() {
        let primary = CGRect(x: 0, y: 30, width: 1512, height: 900)
        let oldFrame = CGRect(x: 1900, y: 400, width: 164, height: 164)
        let fitted = TilePlacement.fit(oldFrame, visibleScreens: [primary])
        XCTAssertTrue(primary.contains(fitted))
        XCTAssertEqual(fitted.origin, CGPoint(x: 1332, y: 750))
    }

    func testOpenDesktopDropPreservesPointerPosition() {
        let screen = CGRect(x: 0, y: 30, width: 1512, height: 900)
        let drop = CGRect(x: 233, y: 517, width: 164, height: 164)
        let result = TilePlacement.drop(drop, visibleScreens: [screen])
        XCTAssertFalse(result.showsGuide)
        XCTAssertEqual(result.frame, drop)
    }

    func testPositionClampsToItsOwnScreenIncludingNegativeCoordinates() {
        let primary = CGRect(x: 0, y: 30, width: 1512, height: 900)
        let secondary = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let oldFrame = CGRect(x: -1300, y: 730, width: 164, height: 164)
        let fitted = TilePlacement.fit(oldFrame, visibleScreens: [primary, secondary])
        XCTAssertTrue(secondary.contains(fitted))
        XCTAssertEqual(fitted.origin, CGPoint(x: -1264, y: 620))
    }

    func testAlignsWithNativeWidgetsAndSkipsOccupiedCells() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let calendar = CGRect(x: 1332, y: 196, width: 164, height: 164)
        let batteries = calendar.offsetBy(dx: 0, dy: -180)
        let widgets = [batteries, calendar]
        let above = calendar.offsetBy(dx: 0, dy: 180)
        for drop in [above.offsetBy(dx: -17, dy: 11), calendar.offsetBy(dx: 0, dy: 10), above] {
            XCTAssertEqual(TilePlacement.fit(drop, visibleScreens: [screen], widgets: widgets), above)
        }
    }

    func testGuideUsesNearbyWidgetInAnIndependentlyPositionedGroup() {
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 1000)
        let distant = CGRect(x: 100, y: 780, width: 164, height: 164)
        let wide = CGRect(x: 523, y: 412, width: 344, height: 164)
        let slot = CGRect(x: 703, y: 232, width: 164, height: 164)
        let nearby = TilePlacement.drop(slot.offsetBy(dx: 17, dy: 12), visibleScreens: [screen], widgets: [distant, wide])
        XCTAssertTrue(nearby.showsGuide)
        XCTAssertEqual(nearby.frame, slot)
        let outside = slot.offsetBy(dx: 0, dy: -98)
        let free = TilePlacement.drop(outside, visibleScreens: [screen], widgets: [distant, wide])
        XCTAssertFalse(free.showsGuide)
        XCTAssertEqual(free.frame, outside)
    }

    func testRightEdgeOffersAnInsetGuideOnItsOwnDisplay() {
        let secondary = CGRect(x: -1200, y: 10, width: 1200, height: 900)
        let frame = CGRect(x: -164, y: 511, width: 164, height: 164)
        let drop = TilePlacement.drop(frame, visibleScreens: [CGRect(x: 0, y: 0, width: 1600, height: 1000), secondary])
        XCTAssertTrue(drop.showsGuide)
        XCTAssertEqual(drop.frame.origin, CGPoint(x: -180, y: 550))
    }

    func testRunnerReturnsOutputAndReportsFailure() async throws {
        let data = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["cover"], timeout: 2)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "cover")
        do {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], timeout: 2)
            XCTFail("Expected nonzero exit")
        } catch CommandError.failed(let code, _) {
            XCTAssertNotEqual(code, 0)
        }
    }

    func testRunnerTimesOutAndCanRunAgain() async throws {
        let start = Date()
        do {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch CommandError.timedOut {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let data = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["recovered"], timeout: 2)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "recovered")
    }

    func testRunnerCancellationStopsChild() async throws {
        let task = Task { try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 20) }
        try await Task.sleep(for: .milliseconds(50))
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch CommandError.cancelled {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
