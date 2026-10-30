-- The destination is supplied as an argv value, never interpolated into code.
-- Check the track both before and after extraction to reject a skip mid-request.
on run argv
    set destination to item 1 of argv
    set expectedID to item 2 of argv
    set expectedTitle to item 3 of argv
    set expectedArtist to item 4 of argv
    set expectedAlbum to item 5 of argv
    if not application "/System/Applications/Music.app" is running then return "stale"
    tell application "/System/Applications/Music.app"
        if player state is stopped then return "stale"
        set musicTrack to current track
        if not my matchesTrack(musicTrack, expectedID, expectedTitle, expectedArtist, expectedAlbum) then return "stale"
        if (count artworks of musicTrack) is 0 then return "missing"
        set imageData to raw data of artwork 1 of musicTrack
        if not my matchesTrack(current track, expectedID, expectedTitle, expectedArtist, expectedAlbum) then return "stale"
    end tell
    set outputFile to open for access POSIX file destination with write permission
    try
        set eof outputFile to 0
        write imageData to outputFile
        close access outputFile
    on error messageText number errorNumber
        try
            close access outputFile
        end try
        error messageText number errorNumber
    end try
    return "ok"
end run

on matchesTrack(musicTrack, expectedID, expectedTitle, expectedArtist, expectedAlbum)
    tell application "/System/Applications/Music.app"
        set actualID to ""
        try
            set actualID to persistent ID of musicTrack
        end try
        if actualID is "" then
            try
                set actualID to (database ID of musicTrack) as text
            end try
        end if
        return actualID is expectedID and name of musicTrack is expectedTitle and artist of musicTrack is expectedArtist and album of musicTrack is expectedAlbum
    end tell
end matchesTrack
