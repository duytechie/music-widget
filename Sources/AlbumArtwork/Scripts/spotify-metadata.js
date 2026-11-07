// Reads Spotify's current track without launching Spotify or changing playback.
const spotify = Application('Spotify');
if (!spotify.running()) {
    JSON.stringify({ state: 'closed' });
} else {
    const state = spotify.playerState();
    if (state !== 'playing' && state !== 'paused') {
        JSON.stringify({ state: 'stopped' });
    } else {
        const track = spotify.currentTrack();
        let artworkURL = '';
        try { artworkURL = track.artworkUrl() || ''; } catch (_) {}
        JSON.stringify({
            state: state,
            track: {
                id: track.id() || '',
                title: track.name() || '',
                artist: track.artist() || '',
                album: track.album() || ''
            },
            artworkURL: artworkURL
        });
    }
}
