// Access by path also works when Launch Services hasn't registered Music's name.
const music = Application('/System/Applications/Music.app');
if (!music.running()) {
    JSON.stringify({ state: 'closed' });
} else {
    const state = music.playerState();
    if (state !== 'playing' && state !== 'paused') {
        JSON.stringify({ state: 'stopped' });
    } else {
        const track = music.currentTrack();
        let id = '';
        try { id = track.persistentID(); } catch (_) {}
        if (!id) { try { id = String(track.id()); } catch (_) {} }
        JSON.stringify({
            state: state,
            track: {
                id: id,
                title: track.name() || '',
                artist: track.artist() || '',
                album: track.album() || ''
            }
        });
    }
}
