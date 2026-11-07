import Foundation

/// A desktop music player whose current cover can be shown.
public enum PlayerSource: String, Codable, CaseIterable, Sendable {
    case appleMusic
    case spotify

    public var bundleIdentifier: String {
        switch self {
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    public var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

/// Decides which player's cover is shown when more than one player is running.
///
/// A playing player always wins. Otherwise the current player is kept, even when it is
/// paused or closed, so quitting one app never swaps in another app's paused cover.
public struct SourceSelector: Sendable {
    public private(set) var current: PlayerSource?

    public init(current: PlayerSource? = nil) {
        self.current = current
    }

    public mutating func choose(_ snapshots: [PlayerSource: PlaybackSnapshot]) -> PlayerSource? {
        if let current, snapshots[current]?.state == .playing { return current }
        if let playing = PlayerSource.allCases.first(where: { snapshots[$0]?.state == .playing }) {
            current = playing
            return playing
        }
        if current == nil {
            current = PlayerSource.allCases.first(where: { snapshots[$0]?.track != nil })
        }
        return current
    }
}

/// Spotify's scripting interface exposes a cover URL rather than image data.
public enum SpotifyArtwork {
    /// Hosts Spotify serves album images from. Anything else is rejected.
    static let allowedHostSuffixes = ["scdn.co", "spotifycdn.com"]
    public static let maximumBytes = 10 * 1024 * 1024

    public static func validatedURL(_ string: String?) -> URL? {
        guard let string, let components = URLComponents(string: string),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              allowedHostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }
}
