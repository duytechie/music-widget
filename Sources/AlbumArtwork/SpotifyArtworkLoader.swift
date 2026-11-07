import ArtworkCore
import Foundation

/// Downloads the cover image Spotify reports for its current track.
/// Only Spotify image CDN URLs are fetched; no API key, account, or catalog request is used.
enum SpotifyArtworkLoader {
    enum LoadError: Error { case invalidURL, badResponse, tooLarge }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func load(_ urlString: String?) async throws -> Data {
        guard let url = SpotifyArtwork.validatedURL(urlString) else { throw LoadError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LoadError.badResponse }
        guard data.count <= SpotifyArtwork.maximumBytes else { throw LoadError.tooLarge }
        return data
    }
}
