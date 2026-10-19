<p align="center">
  <img src="docs/banner.png" alt="Plevi TA" width="720">
</p>

# Plevi TA

Plevi TA is an iPhone, iPad and Apple TV client for [Tube Archivist](https://docs.tubearchivist.com), the self-hosted YouTube archive. It connects to a Tube Archivist server that you run yourself.

## What it does

- Browse Home, Channels, Playlists and Search, with sorting, filtering and a watched filter.
- Play videos with progress synced back to the server, and resume where you stopped.
- Save videos for offline viewing (iPhone and iPad).
- Pin playlists and channels to Home.
- Use a local and a remote server address, with automatic switching between them.
- Sign in with username and password, an API token, or through the sign-in page of a gated server.
- Skip sponsor segments, using the segment data the server has already stored.
- Apple TV: a left sidebar, a Top Shelf row and a remote-driven interface.

## Privacy and data handling

These points can be checked in this source.

- **Network:** the app talks only to the server address you enter. There are no analytics, advertising or crash-reporting SDKs. The only other links are ones you tap, such as the Tube Archivist documentation.
- **Credentials:** the API token and session credentials are stored in the Keychain. Server addresses and settings are stored in UserDefaults.
- **Diagnostics:** an optional playback log is kept on the device (Settings > Diagnostics on iPhone and iPad). It leaves the device only if you share it, and it never contains tokens or passwords.
- **On-device caches:** thumbnails and channel art, and a copy of what Home last showed, are kept on the device so the app is quick on a slow connection. The artwork cache has a size limit in Settings > Storage and can be cleared there. Nothing in them leaves the device.
- **Plain HTTP:** App Transport Security allows plain HTTP, because many self-hosted servers run on a home network without TLS.

## Layout

| Path | Contents |
| --- | --- |
| `Apps/Shared` | SwiftUI screens shared by iOS, iPadOS and tvOS |
| `Apps/iOS`, `Apps/tvOS`, `Apps/TopShelf` | App targets and the Top Shelf extension |
| `Packages/PleviCore` | API client, models, stores, persistence, offline downloads, policies, diagnostics log |
| `Fixtures` | Synthetic test data and a local mock Tube Archivist server (`mock_server.py`) |
| `Config`, `project.yml` | Build settings and the XcodeGen project definition |

## What is not included

The playback engines are not published: the wrapper around the system player, the VLC-based compatibility player and the local media proxy. This tree therefore does not build as an app, and it is published to be read. The core package does build and test on its own:

```
cd Packages/PleviCore && swift test
```

## Licence

Copyright 2026 Upfarm Development. All rights reserved. The source is published for transparency, and no licence is granted for reuse.
