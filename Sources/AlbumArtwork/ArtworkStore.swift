import AppKit
import ArtworkCore
import SwiftUI

private struct CachedArtwork: Codable {
    let track: Track
    let imageData: Data
    /// Missing in caches written before Spotify support; those came from Apple Music.
    let source: PlayerSource?
}

@MainActor
final class ArtworkStore: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var track: Track?
    @Published private(set) var source: PlayerSource?
    @Published private(set) var status = "Waiting for Apple Music or Spotify"
    @Published private(set) var permissionDenied = false
    private var session = ArtworkSession()
    private var selector = SourceSelector()
    private var polling: Task<Void, Never>?
    private var contactedSources = Set<PlayerSource>()
    private var deniedSources = Set<PlayerSource>()
    private let cacheURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = base.appendingPathComponent("AlbumArtwork/last-artwork.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(CachedArtwork.self, from: data),
           let restoredImage = NSImage(data: cache.imageData) {
            image = restoredImage
            track = cache.track
            source = cache.source ?? .appleMusic
            selector = SourceSelector(current: source)
            session.accept(PlaybackSnapshot(state: .paused, track: cache.track))
            session.finish(generation: session.generation)
        }
    }

    private var playerName: String { source?.displayName ?? "Apple Music" }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let started = Date()
                await self?.refresh()
                let delay = max(0.1, 1 - Date().timeIntervalSince(started))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
    }

    func retryPermission() {
        permissionDenied = false
        deniedSources.removeAll()
        contactedSources.removeAll()
        session.retryNow()
        status = "Connecting to music players…"
    }

    private func refresh() async {
        guard !Task.isCancelled else { return }
        let running = PlayerSource.allCases.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).isEmpty
        }
        guard !running.isEmpty else {
            status = image == nil ? "Open Apple Music or Spotify to show artwork" : "\(playerName) is closed · keeping last cover"
            return
        }

        // Don't repeatedly invoke a denied Apple Event. Explicit retry is available in the menu.
        var snapshots: [PlayerSource: PlaybackSnapshot] = [:]
        var readFailed = false
        for player in running where !deniedSources.contains(player) {
            do {
                snapshots[player] = try await readMetadata(player)
            } catch {
                guard !Task.isCancelled else { return }
                if let commandError = error as? CommandError, commandError.isPermissionDenied {
                    deniedSources.insert(player)
                } else {
                    readFailed = true
                }
            }
        }
        permissionDenied = !deniedSources.isEmpty

        guard let active = selector.choose(snapshots), let snapshot = snapshots[active] else {
            if permissionDenied {
                let names = PlayerSource.allCases.filter(deniedSources.contains).map(\.displayName)
                status = "Allow access to \(names.joined(separator: " and ")) in System Settings"
            } else if readFailed {
                status = "Music player unavailable · retrying"
            } else {
                status = image == nil ? "Play a song in Apple Music or Spotify" : "\(playerName) is closed · keeping last cover"
            }
            return
        }
        source = active
        accept(snapshot)
        guard snapshot.state == .playing || snapshot.state == .paused,
              session.shouldFetch(at: Date()), let requestedTrack = session.track else { return }
        let generation = session.generation

        do {
            let data = try await fetchArtwork(from: active, for: requestedTrack, snapshot: snapshot)
            // Check again after the download, including skips while it was in flight.
            let current = try await readMetadata(active)
            accept(current)
            guard !Task.isCancelled, session.generation == generation,
                  current.state != .closed, current.track == requestedTrack else { return }
            guard let data, let decoded = NSImage(data: data), decoded.isValid else {
                session.failed(at: Date())
                status = "Artwork unavailable · \(requestedTrack.title)"
                return
            }
            guard session.finish(generation: generation) else { return }
            image = decoded
            track = requestedTrack
            persist(data: data, track: requestedTrack, source: active)
            updateStatus(current)
        } catch {
            guard !Task.isCancelled else { return }
            session.failed(at: Date())
            if let commandError = error as? CommandError, commandError.isPermissionDenied {
                deniedSources.insert(active)
                permissionDenied = true
                status = "Allow access to \(active.displayName) in System Settings"
            } else {
                status = "Artwork unavailable · retrying"
            }
        }
    }

    /// Returns nil when the player reports no artwork or a different track.
    private func fetchArtwork(from player: PlayerSource, for requestedTrack: Track, snapshot: PlaybackSnapshot) async throws -> Data? {
        switch player {
        case .spotify:
            guard SpotifyArtwork.validatedURL(snapshot.artworkURL) != nil else { return nil }
            return try await SpotifyArtworkLoader.load(snapshot.artworkURL)
        case .appleMusic:
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("AlbumArtwork-\(UUID().uuidString).img")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let output = try await runScript("artwork", extension: "applescript", language: "AppleScript", arguments: [
                temporaryURL.path, requestedTrack.id, requestedTrack.title, requestedTrack.artist, requestedTrack.album
            ])
            let result = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard result == "ok" else { return nil }
            return try? Data(contentsOf: temporaryURL)
        }
    }

    private func accept(_ snapshot: PlaybackSnapshot) {
        if session.accept(snapshot) {
            image = nil
            track = snapshot.track
            // A new track must never resurrect the previous track's cover on relaunch.
            try? FileManager.default.removeItem(at: cacheURL)
        }
        updateStatus(snapshot)
    }

    private func updateStatus(_ snapshot: PlaybackSnapshot) {
        switch snapshot.state {
        case .closed: status = "\(playerName) is closed · keeping last cover"
        case .stopped: status = "Playback stopped · keeping last cover"
        case .paused: status = "Paused · \(track?.title ?? playerName)"
        case .playing:
            status = image == nil ? "Loading artwork…" : "\(track?.title ?? "Playing") · \(track?.artist ?? playerName)"
        }
        if image == nil && session.attempts > 5 { status = "No artwork available for this track" }
    }

    private func readMetadata(_ player: PlayerSource) async throws -> PlaybackSnapshot {
        // Give the user time to respond to the first system Automation prompt for each player.
        let timeout: TimeInterval = contactedSources.contains(player) ? 5 : 60
        defer { contactedSources.insert(player) }
        let name = player == .spotify ? "spotify-metadata" : "metadata"
        let data = try await runScript(name, extension: "js", language: "JavaScript", timeout: timeout)
        return try JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    private func runScript(_ name: String, extension ext: String, language: String, arguments: [String] = [], timeout: TimeInterval = 5) async throws -> Data {
        let packagedScript = Bundle.main.resourceURL?.appendingPathComponent("Scripts/\(name).\(ext)")
        let script = packagedScript.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Scripts")
        guard let script else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-l", language, script.path] + arguments, timeout: timeout)
    }

    private func persist(data: Data, track: Track, source: PlayerSource) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(CachedArtwork(track: track, imageData: data, source: source))
            try encoded.write(to: cacheURL, options: .atomic)
        } catch {
            // Artwork remains visible if this Mac cannot persist the cache.
            status = "Artwork loaded · couldn't save cover for next launch"
        }
    }
}
