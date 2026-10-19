<p align="center">
  <img src="docs/banner.png" alt="Plevi TA" width="720">
</p>

# Plevi TA

Plevi TA is an app for iPhone, iPad and Apple TV that lets you browse and watch your [Tube Archivist](https://docs.tubearchivist.com) library. Tube Archivist is the self-hosted YouTube archive, and you point the app at the server you run yourself. It's an independent project and isn't affiliated with Tube Archivist.

You get the things you'd expect: Home, Channels, Playlists and Search, playback that remembers where you stopped and syncs your progress back to the server, and a watched filter. Here is what it does on top of that.

## What it can do

- **A Continue Watching row that's actually in order.** It sits at the top of Home and puts what you watched most recently first. The order syncs between your devices through iCloud, so what you started on the Apple TV is at the front on your phone. Tube Archivist doesn't record when you watched something, so the app keeps track itself. Videos you only watched in the web page keep their usual place.
- **A custom player with AV1 and VP9.** H.264 plays in Apple's own player. When a video is in a format Apple's player can't handle, the app switches to its own. One thing to know: 4K AV1 and VP9 won't play smoothly on current Apple TV hardware, because it can't decode them in hardware. 1080p works fine in testing.
- **Downloads on iPhone and iPad.** Save videos to watch offline. There's a Downloads screen with the queue and your saved videos, as a grid or a list, with the download speed while something is coming in.
- **Pin your favourites.** Put channels and playlists you care about on Home.
- **A video page with more on it.** What's next, if the video is in a playlist (or several), plus similar videos, the description, file details and comments.
- **SponsorBlock.** It uses the segments your server has already stored, and works online and offline. You choose which kinds to skip: sponsors, self-promotion, intros and outros.
- **Signing in your way.** Use an API token, a username and password, or the sign-in page of a server that sits behind a login. You can set a local and a remote address, and the app switches between them for you.
- **Made for slow connections.** Thumbnails, channel art and a copy of Home are kept on the device, so the app opens quickly and still shows pictures when the connection is poor or missing.
- **Apple TV.** A sidebar you can navigate with the remote, and a Top Shelf row.

## Privacy

You can check all of this in the source.

- **Network:** the app only talks to the server address you enter. There are no analytics, advertising or crash-reporting SDKs. The only other links are ones you tap yourself, like the Tube Archivist documentation.
- **Credentials:** your API token and session are kept in the Keychain. Server addresses and settings are stored on the device.
- **Diagnostics:** there is an optional playback log, kept on the device (Settings > Diagnostics on iPhone and iPad). It only leaves the device if you share it, and it never contains tokens or passwords.
- **Caches:** the artwork cache and the copy of Home stay on the device. The artwork cache has a size limit in Settings > Storage, and you can clear it there.
- **Plain HTTP:** the app allows plain HTTP, because many self-hosted servers run on a home network without TLS.

## What's in this repository

| Path | Contents |
| --- | --- |
| `Apps/Shared` | The SwiftUI screens shared by iPhone, iPad and Apple TV |
| `Apps/iOS`, `Apps/tvOS`, `Apps/TopShelf` | The app targets and the Top Shelf extension |
| `Packages/PleviCore` | The API client, models, stores, storage, downloads and the diagnostics log |
| `Fixtures` | Test data and a small mock Tube Archivist server (`mock_server.py`) |
| `Config`, `project.yml` | Build settings and the project definition |

## What isn't included

The playback engines are not published: the wrapper around Apple's player, the custom player and the local media proxy that feeds it. Because of that this repository doesn't build as an app. It's here to be read. The core package does build and pass its tests on its own:

```
cd Packages/PleviCore && swift test
```

## Licence

Copyright 2026 Upfarm Development. All rights reserved. The source is published so you can see what the app does, and no licence is granted for reuse.
