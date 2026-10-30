import Foundation

public struct Track: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String

    public init(id: String, title: String, artist: String, album: String) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
    }
}

public struct PlaybackSnapshot: Decodable, Sendable {
    public enum State: String, Decodable, Sendable { case playing, paused, stopped, closed }
    public let state: State
    public let track: Track?

    public init(state: State, track: Track? = nil) {
        self.state = state
        self.track = track
    }
}

/// A successful cover is retained on pause/stop/close; a new track gets a clean slate.
public struct ArtworkSession {
    public private(set) var track: Track?
    public private(set) var generation = 0
    public private(set) var hasArtwork = false
    public private(set) var attempts = 0
    private var retryAt = Date.distantPast
    private static let retryDelays: [TimeInterval] = [1, 2, 4, 8, 16]

    public init() {}

    @discardableResult
    public mutating func accept(_ snapshot: PlaybackSnapshot) -> Bool {
        guard let next = snapshot.track, next != track else { return false }
        track = next
        generation += 1
        hasArtwork = false
        attempts = 0
        retryAt = .distantPast
        return true
    }

    public func shouldFetch(at date: Date) -> Bool {
        track != nil && !hasArtwork && attempts <= Self.retryDelays.count && date >= retryAt
    }

    public mutating func failed(at date: Date) {
        if attempts < Self.retryDelays.count {
            retryAt = date.addingTimeInterval(Self.retryDelays[attempts])
        } else {
            retryAt = .distantFuture
        }
        attempts += 1
    }

    @discardableResult
    public mutating func finish(generation resultGeneration: Int) -> Bool {
        guard generation == resultGeneration else { return false }
        hasArtwork = true
        return true
    }

    public mutating func retryNow() {
        attempts = 0
        retryAt = .distantPast
    }
}
