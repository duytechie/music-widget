import AppKit
import ArtworkCore
import SwiftUI

private struct CachedArtwork: Codable {
    let track: Track
    let imageData: Data
}

@MainActor
final class ArtworkStore: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var track: Track?
    @Published private(set) var status = "Waiting for Apple Music"
    @Published private(set) var permissionDenied = false
    private var session = ArtworkSession()
    private var polling: Task<Void, Never>?
    private var hasContactedMusic = false
    private let cacheURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = base.appendingPathComponent("AlbumArtwork/last-artwork.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(CachedArtwork.self, from: data),
           let restoredImage = NSImage(data: cache.imageData) {
            image = restoredImage
            track = cache.track
            session.accept(PlaybackSnapshot(state: .paused, track: cache.track))
            session.finish(generation: session.generation)
        }
    }

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
        hasContactedMusic = false
        session.retryNow()
        status = "Connecting to Apple Music…"
    }

    private func refresh() async {
        guard !Task.isCancelled else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            status = image == nil ? "Open Apple Music to show artwork" : "Apple Music is closed · keeping last cover"
            return
        }
        // Don't repeatedly invoke a denied Apple Event. Explicit retry is available in the menu.
        guard !permissionDenied else { return }
        do {
            let snapshot = try await readMetadata()
            accept(snapshot)
            guard snapshot.state == .playing || snapshot.state == .paused,
                  session.shouldFetch(at: Date()), let requestedTrack = session.track else { return }
            let generation = session.generation
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("AlbumArtwork-\(UUID().uuidString).img")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            do {
                let output = try await runScript("artwork", extension: "applescript", language: "AppleScript", arguments: [
                    temporaryURL.path, requestedTrack.id, requestedTrack.title, requestedTrack.artist, requestedTrack.album
                ])
                let result = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                // Check again after the file write, including skips during artwork decoding.
                let current = try await readMetadata()
                accept(current)
                guard !Task.isCancelled, session.generation == generation,
                      current.state != .closed, current.track == requestedTrack else { return }
                guard result == "ok", let data = try? Data(contentsOf: temporaryURL),
                      let decoded = NSImage(data: data), decoded.isValid else {
                    session.failed(at: Date())
                    status = "Artwork unavailable · \(requestedTrack.title)"
                    return
                }
                guard session.finish(generation: generation) else { return }
                image = decoded
                track = requestedTrack
                persist(data: data, track: requestedTrack)
                updateStatus(current)
            } catch {
                session.failed(at: Date())
                throw error
            }
        } catch {
            guard !Task.isCancelled else { return }
            if let commandError = error as? CommandError, commandError.isPermissionDenied {
                permissionDenied = true
                status = "Allow access to Music in System Settings"
            } else {
                status = "Music unavailable · retrying"
            }
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
        case .closed: status = "Apple Music is closed · keeping last cover"
        case .stopped: status = "Playback stopped · keeping last cover"
        case .paused: status = "Paused · \(track?.title ?? "Apple Music")"
        case .playing:
            status = image == nil ? "Loading artwork…" : "\(track?.title ?? "Playing") · \(track?.artist ?? "Apple Music")"
        }
        if image == nil && session.attempts > 5 { status = "No artwork available for this track" }
    }

    private func readMetadata() async throws -> PlaybackSnapshot {
        // Give the user time to respond to the first system Automation prompt.
        let timeout: TimeInterval = hasContactedMusic ? 5 : 60
        defer { hasContactedMusic = true }
        let data = try await runScript("metadata", extension: "js", language: "JavaScript", timeout: timeout)
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

    private func persist(data: Data, track: Track) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(CachedArtwork(track: track, imageData: data))
            try encoded.write(to: cacheURL, options: .atomic)
        } catch {
            // Artwork remains visible if this Mac cannot persist the cache.
            status = "Artwork loaded · couldn't save cover for next launch"
        }
    }
}
