# Changelog

Notable changes to Plevi TA, newest first.

Two numbers move independently, both set in `Config/Base.xcconfig`:
`MARKETING_VERSION` is the version, bumped by hand at a release milestone;
`CURRENT_PROJECT_VERSION` is the build, bumped every commit by
`Scripts/bump_build_number.sh`.

## 1.0.0 (202)

CHANGED

- SponsorBlock no longer has an on/off switch. It is on whenever one of its four types is selected.
- On iPad, Search is now a magnifying glass in the tab bar and opens with the keyboard ready.

FIXED

- The sign-in page now says the API token is under Settings → Application → Integrations.

## 1.0.0 (199)

CHANGED

- iPhone, iPad and Apple TV: Settings is tidier. The long explanatory notes under each group of settings are gone, leaving just the settings.
- iPhone, iPad and Apple TV: there is a new Integrations group in Settings. SponsorBlock has moved there from Playback. Tap SponsorBlock to see the on/off switch and the four kinds of segment it can skip (sponsors, self-promotion, intros and outros). The row shows whether it is On or Off.

## 1.0.0 (198)

CHANGED

- iPhone, iPad and Apple TV: the logo on the sign-in page is now the full-resolution app logo, so it is sharper, and it no longer has a shadow behind it. API Token is still the default way to sign in.

## 1.0.0 (197)

CHANGED

- iPhone, iPad and Apple TV: the first screen you see, the sign-in page, now shows the app's own logo at the top instead of a placeholder symbol.
- iPhone, iPad and Apple TV: API Token is now the default way to sign in, and is the first option in the switch. Username & Password is the second.

## 1.0.0 (196)

FIXED

- Apple TV: closing a video's "…" menu with Menu and pressing Menu again straight away no longer leaves the app. Focus takes a moment to come back to the button, and a press in that moment went to the system. It now goes back a page, as it does once the button is highlighted again.

## 1.0.0 (195)

Continue Watching order and pins now sync between devices that signed in differently.

FIXED

- iPhone, iPad and Apple TV: the Continue Watching order and your pinned playlists and channels are shared between your devices by the server's address. They used to be filed under the address you signed in with, so an iPhone and an Apple TV that signed in with different addresses never saw each other's. They now use the local address if one is set in Settings > Server, then the remote address, then the one you signed in with. What each device already had is carried over, so nothing is lost, and the two merge.

WORTH KNOWING

- For two devices to share, they need the same address in that order: if the Apple TV has a local address, the iPhone needs that same local address entered too (Settings > Server). Check Settings > About > Continue Watching sync: when both devices show the same server code, they share.
- Changing the local or remote address afterwards starts a new shared history under the new address, carrying over what the sign-in address held.

## 1.0.0 (194)

FIXED

- Apple TV: Settings > About > Continue Watching sync no longer says iCloud is off. Apple TV has no iCloud Drive, so that check could not be made there, even though the sync itself works. On iPhone and iPad the line now reads "iCloud Drive on" or "iCloud Drive off".

## 1.0.0 (193)

Continue Watching order, across devices.

FIXED

- iPhone, iPad and Apple TV: the Continue Watching order now follows what you watched on your other devices more reliably. A video you started on one device moves to the front on the other while Home is open, not only the next time the list reloads, and the app asks iCloud for anything new each time you come back to it.

NEW

- Settings > About > Continue Watching sync: shows a short code for the server, whether iCloud is on, how many videos the history holds and when it last heard from another device. If your iPhone and Apple TV show different codes they signed in with different addresses and keep separate histories; if one never says it heard from another device, iCloud is not delivering.

WORTH KNOWING

- Only videos started in this app are ordered. Ones watched in the Tube Archivist web page keep the server's order below them.
- iCloud delivers changes when it chooses, usually within seconds to a minute or two, and only if iCloud is on for both devices.

## 1.0.0 (192)

FIXED

- iPhone and iPad: long-pressing a video, channel or playlist no longer crashes the app. Build 191's new preview card was drawn without the data it needs and the app stopped the moment you pressed.

## 1.0.0 (191)

FIXED

- iPhone and iPad: "Save a Copy…" works from the Downloads screen. The file picker could not appear on top of that screen, so choosing it did nothing.
- iPhone, iPad: long-pressing a video, channel or playlist now lifts a clean preview of its card. Before, a stray frame showed for a moment and the enlarged title ran over the thumbnails next to it. This applies everywhere in the app.

WORTH KNOWING

- Tapping the preview itself closes the menu rather than opening the video. Tap the video normally to open it.

## 1.0.0 (190)

FIXED

- iPhone and iPad: the Saved tab of the Downloads screen now shows the watched checkmark and the progress bar on your saved videos. It asks the server how far through each one you are when it can, and remembers the answer so it still shows when you are offline.

## 1.0.0 (189)

An artwork cache that survives offline and relaunches.

NEW

- iPhone, iPad and Apple TV: thumbnails, channel avatars and channel art are now kept on the device, so they show on a slow connection and with no connection at all, including right after you reopen the app. Before, only videos you had saved offline kept their pictures.
- Settings > Storage > Artwork cache (on Apple TV, Settings > Storage): shows how much the cache uses, lets you set a maximum (100 MB, 250 MB, 500 MB, 1 GB or 2 GB; 500 MB to begin with) and has a Clear Artwork Cache button. When the cache is full the least recently used pictures are removed first.
- Pictures stay up to date: one older than a week is still shown straight away, then checked in the background, and if the server has a different one the old copy is replaced and not kept. A picture you have not looked at for three months is removed.

## 1.0.0 (188)

Home opens straight away, and refreshes in the background.

NEW

- iPhone, iPad and Apple TV: Home now remembers what it last showed (Continue Watching and the newest videos) and draws it the moment it opens, while the fresh list loads. On a slow connection you no longer wait on an empty screen. Nothing leaves the device.
- iPhone and iPad: Home is also refreshed in the background now and then, when iOS allows it, so it is up to date when you open the app. iOS decides when this runs, and it may run rarely if you do not open the app often.

WORTH KNOWING

- Two problems I could not find the cause of from the code are now logged in detail, so one occurrence is enough to diagnose them: a saved video that errors and restarts after you lock the phone, and downloads that stop when the app leaves the screen. If either happens, open Settings > Diagnostics > Share playback log right afterwards and send it over.
- Background refresh does not send your offline watch progress to the server yet; that still happens when you open the app with a connection.

## 1.0.0 (187)

A downloads library.

NEW

- iPhone and iPad: the Downloads button is now always there once you have saved a video, not only while something is downloading. Tap it and use the switch at the top: "Downloading" is the queue, and "Saved" lists your saved videos as a grid or a list, following the same setting as Home. Tap a saved video to open it. Long-press one to save a copy out of the app or remove the download.

## 1.0.0 (186)

Browser sign-in from the offline screen, and smoother downloading.

NEW

- iPhone and iPad: the banner on the offline Saved Videos screen now has a "Sign in via browser" button. If your server sits behind a login page (SSO) and the session has expired, you can sign in again from there instead of having to sign out. Tap the banner text to read the whole message, and Retry shows a spinner while it tries.
- iPhone and iPad: the download cards show the download speed, for example "120 MB of 480 MB · 2.4 MB/s".

FIXED

- iPhone and iPad: the app is smoother while videos download. Each progress update used to redraw most of the app and write to storage twice a second per download; progress is now kept separately and only the downloads screen redraws.
- iPhone and iPad: long-press menus on videos should no longer flash while a download is running, which was the same cause. If they still flash with nothing downloading, tell me.

## 1.0.0 (185)

Offline progress bars, and deleting a video keeps your place.

FIXED

- iPhone and iPad: watch progress now shows on saved videos when you are offline. The progress bar on the video's thumbnail was missing in the Saved Videos list and on the video page, because the saved copy of a video holds no progress. It is now filled in from where you last stopped watching on this device.
- iPhone and iPad: deleting a video from its page now returns you to the list you came from with the video gone and your scroll position kept. Before, the list still showed the deleted video until it reloaded, and the reload sent you back to the top.

## 1.0.0 (184)

CHANGED

- Apple TV: the filter row on Channels now looks like the one on Playlists: the same text size and weight on the filter chips, the same chip colours, and the "36 channels · A–Z" sort control as a capsule button instead of plain text.

## 1.0.0 (183)

Two Apple TV fixes.

FIXED

- Apple TV: Settings. After opening a settings group (Playback, say), pressing Menu now takes you back to the settings list. It used to jump to the side menu, so there was no way back.
- Apple TV: pressing Select on Channels or Playlists in the side menu now puts focus on the first channel or playlist instead of on the filters above it.

## 1.0.0 (181)

The Apple TV menu now switches pages as you move down it.

CHANGED

- Apple TV: moving focus onto a menu icon shows that page straight away, with no need to press Select. Press Select (or Right) to go into the page.
- Apple TV: opening Channels or Playlists now puts focus on the first channel or playlist, as Home does with its first video, instead of on the filters above it.
- Apple TV: the focused channel in Channels gets a lighter grey tint, so it is easier to see which one is selected.

FIXED

- Apple TV: in Playlists, the channel name and checkmark under a focused playlist were partly hidden by the row below. The rows are now spaced far enough apart.

## 1.0.0 (180)

The Apple TV sidebar no longer expands.

CHANGED

- Apple TV: the left menu is now a fixed strip of icons that stays as it is when you move onto it. Move focus left onto it, swipe up or down to a section and press to go there; the page behind is no longer dimmed and nothing slides over it. The focused icon is highlighted in white.
- Apple TV: the pinned playlists and channels are no longer listed in the menu. They are still on Home, in the Pinned row.

## 1.0.0 (179)

FIXED

- iPhone and iPad: the "…" button on the video page no longer jumps. If you scrolled while its menu was open, the button vanished and slid back into place a moment after its row; it now stays put and scrolls with the page.

## 1.0.0 (178)

NEW

- iPhone and iPad: Settings > Diagnostics. A detailed playback log is now recorded on the device: what the player, network and device were doing while you watch (buffering, stalls, dropped frames, network changes, memory, temperature, and more). If a video stutters, open Settings > Diagnostics > Share playback log and send it over. It is on by default and stays on the device until you share or clear it.

## 1.0.0 (177)

NEW

- iPhone, iPad and Apple TV: the "Can't Reach Server" screen now has an "Add a remote address" button (or "Edit server addresses" once you have one). If you signed in on your home network and are now away, enter the address that works from outside and tap Save and Retry; it reconnects straight away.

FIXED

- iPhone and iPad: "Sign in via browser" on the "Can't Reach Server" screen now opens your remote address when you have one, instead of always opening the local address it just failed to reach.
- iPhone, iPad and Apple TV: your saved local and remote addresses are no longer cleared when you reopen the app after editing them to differ from the address you first signed in with.

## 1.0.0 (176)

FIXED

- Apple TV: the settings dropdowns show their names again ("Sort Home by", "Home order", "Video type" and the rest), next to their current value. Build 174 fixed the dropdowns opening the sidebar, but left only the values on screen with no names.

## 1.0.0 (175)

FIXED

- Apple TV: the thumbnails of your pinned playlists and channels in the sidebar menu now slide in together with their names, instead of showing a grey box and popping in a moment later.

## 1.0.0 (174)

FIXED

- Apple TV: tapping into a setting now actually opens it. Build 173's fix only addressed the settings rows rendering under the sidebar visually — the real cause was the settings dropdowns themselves, whose old presentation had a brief gap in focus that the sidebar was grabbing and never releasing.

## 1.0.0 (173)

FIXED

- Apple TV: a focused playlist or channel card no longer clips its channel-name line at the bottom.
- Apple TV: Settings screens (Home, Browsing, Search, Playback, About) no longer render underneath the sidebar menu.
- Apple TV: tapping into a setting no longer opens the sidebar menu instead — settings can be adjusted again.

## 1.0.0 (172)

FIXED

- Apple TV: choosing a section (Home, Channels, Playlists) from the sidebar menu while that section's page is still loading — most noticeably the first time you visit it — no longer leaves the menu open with focus stuck on Search. The menu now waits for the page to actually take focus, however long that takes, instead of guessing a fixed delay.

## 1.0.0 (171)

CHANGED

- iPhone, iPad and Apple TV: Sign Out moved from Settings > About to Settings > Server, next to the rest of what describes this server.

## 1.0.0 (170)

FIXED

- iPhone, iPad and Apple TV: signing into a different Tube Archivist server no longer leaves the previous server's Local/Remote addresses showing in Settings > Server. They're now replaced as soon as you sign into a server they don't belong to; signing back into a server they do belong to still keeps them, as before.

## 1.0.0 (169)

FIXED

- iPhone, iPad and Apple TV: a playlist with no description no longer shows the word "False" where its description would go.

## 1.0.0 (168)

FIXED

- iPhone, iPad and Apple TV: a video you've started now shows how far in you are, as a bar along the bottom of its thumbnail, wherever it appears: Newly added on Home, Search, Similar videos and your saved videos, as well as Continue watching, playlists and channels where it already did. The same video used to show the bar under Continue watching and not under Newly added.

## 1.0.0 (167)

FIXED

- Apple TV: opening the sidebar with Left now always lands on the section you're in, instead of whichever row was level with where you were, which lower on a page was Settings. Menu already did.
- Apple TV: Left opens the sidebar from anywhere on a page. From a row of cards near the bottom of the screen it used to do nothing.
- Apple TV: choosing a section or a pinned item in the sidebar now takes you to that page. Focus used to stay behind in the sidebar, on Search.

## 1.0.0 (166)

CHANGED

- Apple TV: pressing Right to leave the sidebar now returns you to the item you were on before you opened it, instead of the top of the page, whether you opened it with Left or with Menu.
- Apple TV: the sidebar's panel now slides in from the left edge when it opens, and slides back out when it closes.

## 1.0.0 (165)

FIXED

- Apple TV: on a video that's in more than one playlist, scrolling to the end of the "In this playlist" cards now stops at the last card. It used to carry on into the next playlist and send the focus up to the playlist's name.

CHANGED

- Apple TV: to switch playlist there, press Up from the cards to the ‹ › buttons beside the playlist name and click one. That is now the only way to switch.

## 1.0.0 (164)

FIXED

- Apple TV: the channel name and publish date under a focused Continue Watching or Pinned card no longer get cut off.

## 1.0.0 (163)

ADDED

- Apple TV: choosing the section you're already in from the sidebar, such as Home while on a video opened from Home, goes back to that section's own screen.

CHANGED

- Apple TV: the sidebar is now on screen on every page, including a video's, channel's or playlist's page, where it used to disappear.
- Apple TV: the sidebar opens into a panel styled after Apple's own: a floating glass panel listing the sections, Settings and your pinned playlists and channels, with the screen behind it dimmed. The small rail it closes to is unchanged.

## 1.0.0 (162)

FIXED

- Apple TV: Home can be navigated again. In 161 it opened with the sort button selected and no press of the remote moved anywhere.
- Apple TV: the sidebar now sits close to the left edge of the screen, as designed, instead of well in from it. Screens reached from the sidebar now use the margins they were designed with, which are narrower than in 161.

## 1.0.0 (161)

ADDED

- Apple TV: navigation is now a left sidebar instead of the top tab bar, in the style of the Plex Apple TV app. Press Left (or Menu) at Home, Channels, Playlists, Search or Settings to open it; it shows your pinned playlists and channels too.

## 1.0.0 (160)

FIXED

- iPhone and iPad: confirmation pop-ups now point at what you tapped, instead of at the middle of the screen or the list above it. That covers Remove All Downloads, Remove Watched and Sign Out in Settings; Mark All Watched and Save All in a playlist's or channel's "…" menu; and Delete or Delete and Ignore on a video, whether from a long press or from the "…" on its own page.
- iPhone and iPad: if deleting a video or adding it to a playlist fails, the error now shows as an ordinary alert in the middle of the screen.

## 1.0.0 (159)

FIXED

- iPhone and iPad: swiping down in full screen in the compatibility player now actually leaves full screen. In build 158 the player followed your finger and then sprang back. A quick flick down works too.

## 1.0.0 (158)

ADDED

- iPhone and iPad: in the compatibility player (the one for videos the built-in player can't play), swiping down in full screen now leaves full screen, as it already did in the built-in player.

FIXED

- iPhone and iPad: videos under "In this playlist" on a video's page now show their published date next to the length, like the Similar videos below them.

## 1.0.0 (157)

ADDED

- iPhone, iPad and Apple TV: playlists and channels can now be pinned to Home, from the long-press menu on any playlist/channel card or from the "…" menu on a playlist's or channel's own screen. Pinned items show up in a "Pinned" shelf under Continue Watching, synced between your own devices.

## 1.0.0 (156)

ADDED

- iPhone and iPad: downloads waiting in the Downloads list can now be dragged into a different order, to change what saves next.

FIXED

- iPhone and iPad: downloads now run three at a time instead of all at once, which was what made the app sluggish while saving a whole channel.
- iPhone and iPad: saving a whole channel and locking the phone right away no longer leaves most of it undownloaded by morning — the rest keeps going while the app is in the background.
- iPhone and iPad: turning "Allow cellular downloads" on while videos were stuck waiting for Wi-Fi now actually starts them, instead of leaving them stuck until Wi-Fi came back.

## 1.0.0 (155)

FIXED

- iPhone and iPad: the Downloads list now shows a real progress bar and the bytes so far, instead of spinning at 0 B and then jumping straight to done.

CHANGED

- iPhone and iPad: the Downloads button sits with the other header controls now, next to the show/hide watched eye, rather than on its own at the left.

## 1.0.0 (154)

ADDED

- iPhone and iPad: Settings → Storage → Saved videos now opens a list of what is downloaded, grouped by channel and largest first. Tap a channel to see its videos, swipe to remove a single video or a whole channel, and there is a "Remove All Downloads" button.

## 1.0.0 (153)

FIXED

- iPhone and iPad: a saved video you watched while online now resumes where you left it when you open it with no network. It only resumed the other way round — watch offline, go online — because the position was kept locally only when sending it to the server had failed.

## 1.0.0 (152)

CHANGED

- iPhone and iPad: a downloaded video now shows a small arrow on its thumbnail wherever it appears — Home, a channel, a playlist, search — instead of being listed in a separate "Saved for offline" row on Home. That row is gone; the full list is still there when the app can't reach the server.

## 1.0.0 (151)

ADDED

- iPhone and iPad: a Downloads button appears at the left of the Home, Channels and Playlists headers while anything is downloading, and opens a list showing how far along each one is, with Cancel and Retry. It disappears again when the queue is empty. Until now a download in progress was invisible anywhere in the app unless the server was unreachable.

## 1.0.0 (150)

FIXED

- Coming back from a video now returns you to where you were in a playlist or a channel, instead of the top. The list was being thrown away and rebuilt on every return, which also made the screen flash a spinner. The row you watched still updates.

## 1.0.0 (149)

FIXED

- iPhone and iPad: opening a saved video with no network no longer shows comments, similar videos and playlist navigation as three error panels under the player. They are hidden instead.
- iPhone and iPad: Settings → Storage now shows space used by videos saved for a server you no longer sign in to, and can remove them. That space was previously invisible and impossible to reclaim from inside the app.

## 1.0.0 (148)

FIXED

- iPhone and iPad: a download that finishes while the app is closed is now kept. It was being downloaded, checked, and then silently thrown away.
- iPhone and iPad: a download that was interrupted and resumed is no longer rejected when it finishes.
- iPhone and iPad: reopening the app with no network now offers to resume a saved video where you left it, instead of starting from the beginning.
- "Save All to iPhone" now says how many videos and roughly how much space before it starts, refuses when there isn't room, and prepares them a few at a time instead of all at once.

## 1.0.0 (147)

FIXED

- Apple TV: pressing a tab at the top of the screen while on a video now goes there, instead of the video page pulling focus back down to Play.

## 1.0.0 (146)

CHANGED

- Apple TV: the selected video or button grows a little more than it used to, so it is clearer where you are.

## 1.0.0 (145)

ADDED

- iPhone and iPad: videos can be saved to the device and watched with no network. A "Save to iPhone" item on a video, a list of what you have saved, and the app opening on that list rather than a "can't reach server" wall when it cannot reach the server. Your position syncs back once you are online again.

## 1.0.0 (144)

CHANGED

- Apple TV: comments appear ten at a time, with "Load More Comments" between batches. Selecting individual comments was tried and reverted — comments with replies and comments without ended up highlighting in different places, which looked worse than the problem it solved.

## 1.0.0 (143)

FIXED

- Apple TV: you can move the remote through comments one at a time now, and the screen follows. A comment could not be selected before, so there was nothing to stop on while passing them — and after loading more, the new ones scrolled off the top while the button you had just pressed stayed in view.

## 1.0.0 (142)

CHANGED

- Apple TV: comments now appear five at a time rather than fifteen, with "Load More Comments" between each batch. A comment itself cannot be selected with the remote, so a long run of them was crossed in a single jump; the button is something to stop on every five.

## 1.0.0 (141)

FIXED

- Apple TV: the blue marker behind the video you are currently on now grows with the card when you select it, instead of staying at its old size while the card grew out of it.

## 1.0.0 (140)

FIXED

- Apple TV: the first and last card in the "In this playlist" carousel are no longer cut off when you select them. Similar videos was fixed in the last build; this one sits inside a swipeable page of a fixed height and needed the room left inside it instead.

## 1.0.0 (139)

CHANGED

- Apple TV: scrolling back up a video's page no longer tries to return it to the layout it opens with. Making that work also moved where the page starts, and the opening view is worth more.

FIXED

- Apple TV: the first and last card in a carousel are no longer cut off when you select them. The previous attempt at this did not work — padding moves where a list crops its contents, it does not stop it cropping.

## 1.0.0 (138)

FIXED

- Apple TV: the first and last card in a carousel are no longer cut off when you select them. Selecting a card makes it grow slightly, and at the ends of a row it had nowhere to grow into.
- Apple TV: scrolling back up a video's page now returns it to exactly where it opens, rather than leaving the information sitting lower down the screen.

## 1.0.0 (137)

CHANGED

- Apple TV: Similar videos and "In this playlist" are now carousels you scroll sideways, instead of lists. Crossing either one took a press per item with the remote; now it takes one. The playlist numbers moved onto the cards so you can still see where you are.

FIXED

- Apple TV: scrolling back up a video's page returns it to the layout it opens with, where the information sits in the lower third over the thumbnail. Before, once you had scrolled down there was no way back to it.

## 1.0.0 (136)

FIXED

- A channel's video list now shows how far into a video you are, the same bar the playlist list and Continue watching draw.

## 1.0.0 (135)

FIXED

- A playlist's video list now shows how far into a video you are, the same blue bar Continue watching draws. Only the finished checkmark showed before, so a video you were halfway through looked untouched.
- The "In this playlist" list on a video's own screen shows that bar too. It had no resume indicator at all.

## 1.0.0 (134)

FIXED

- Playing a video from outside your home network works again when your server sits behind a reverse proxy with its own sign-in, and you sign in to Tube Archivist with an API token. The player sent the token but not the proxy's session cookie, so the proxy refused it — browsing and thumbnails worked, only playback failed.

## 1.0.0 (133)

FIXED

- Apple TV: the Username & Password / API Token buttons on the sign-in screen now show which one the remote is on, instead of the system's white highlight under a white capsule.
- Apple TV: a comment's "N replies" button now shows when it is selected. It is one of only two things that can be selected in the whole comments card, and it had no highlight of its own.
- Apple TV: a video's title in the playlist list now brightens when the remote is on it, as it was always meant to.
- Apple TV: "Sign Out" on the can't-reach-server screen is a proper button now, rather than red text under a white plate.

## 1.0.0 (132)

CHANGED

- Apple TV: a video's page is one column now — the playlist, then Similar videos, then Comments, each full width. Comments used to sit in a column of their own beside the other two, and from inside it there was often no way across to Similar videos, or no way into Comments at all.

FIXED

- Apple TV: the arrows for moving between a video's playlists now show which one the remote is on, instead of the system's white highlight.

## 1.0.0 (131)

ADDED

- Search now also finds accented spellings. Typing "Skoda" finds "Škoda", and "bjorn" finds "Bjørn Nyland" — which used to return nothing at all.

FIXED

- Apple TV: a focused sort, show/hide watched or More button now turns white with dark text, instead of changing almost imperceptibly.
- Apple TV: a channel's Videos/Streams/Shorts tabs now show which one the remote is on. The highlight they were meant to have could never draw, and the system's white plate showed instead.

## 1.0.0 (130)

FIXED

- Apple TV: the "Show More" button under a description is no longer cut off when you select it. It was drawing the system's white highlight plate, which is wider than the button and got clipped by the card edge.
- Apple TV: the cards no longer jump when you show or hide watched videos. The eye and the struck-through eye are not the same height, and the button was sizing itself to whichever one it was showing.
- Search: typing a character and then deleting it within a moment no longer shows results for the text you deleted.
- Search: a full-text-only result no longer leaves a blank screen with no explanation.

CHANGED

- Apple TV: the "Show More" button now spans the width of its card, so it can be reached from anywhere below it with the remote.

## 1.0.0 (129)

CHANGED

- iPhone, iPad and Apple TV: video and audio now show their bitrate on the Published/Views/Likes/Runtime row — "h264 · 1080p · 2,3 Mbps" rather than the byte rate, in your own region's number format.
- iPad and Apple TV: that row no longer divides itself into equal columns. Published/Views/Likes/Runtime pack to the left, Size/Video/Audio sit at the right, and the space left over falls between the two groups.

## 1.0.0 (128)

CHANGED

- iPhone, iPad and Apple TV: the "Mark as Watched" button is gone from the video screen. It did the same thing as "Mark Watched" in the three-dot menu right beside it, at the size of a main action.
- iPhone, iPad and Apple TV: the three-dot menu now sits at the end of the Published/Views/Likes/Runtime row instead of on a line of its own.
- iPad and Apple TV: file size, video and audio now appear as three more cells on that same row, rather than a separate File details card. iPhone keeps the card, where there is no room for seven cells.

## 1.0.0 (127)

CHANGED

- Apple TV: the sort, show/hide watched and More controls sit at the left of their row now. On the right they could not be reached by remote at all when a channel had two or fewer videos, and there was no way up to them from the left-hand videos.
- Apple TV: the show/hide watched control is the same eye as on iPhone and iPad. It used to say "Show watched" where the phone showed a struck-through eye — the same state, described the opposite way round.
- Apple TV: a video's information starts about two thirds down the screen, over a top-to-bottom shade, so the thumbnail is visible behind it and the title and its buttons sit in the lower third.

## 1.0.0 (126)

CHANGED

- Apple TV: the sort, show/hide watched and More controls now sit in filled capsules like the chips beside them, instead of plain grey text. They were hard to pick out from across a room until focus landed on them.

## 1.0.0 (125)

CHANGED

- Apple TV: Continue watching is a carousel you scroll sideways, like on iPhone and iPad, rather than a grid stacked above Newly added. Its cards are a little larger than the Newly added cards below them, matching the other platforms exactly.

## 1.0.0 (124)

FIXED

- iPhone, iPad and Apple TV: scrubbing back to before a sponsor segment skips it again. Once a segment had been skipped it stayed skipped for the rest of the video, so going back and watching that part played the sponsor in full.

## 1.0.0 (123)

FIXED

- iPhone, iPad and Apple TV: videos resume where you left off again. Build 122's sponsor-skip fix had let a skip fire before the video reached its saved position, sending you back to the start.

## 1.0.0 (122)

FIXED

- iPhone, iPad and Apple TV: Sponsor block now actually skips segments in the built-in player. It has never worked there — only in the compatibility player — however the setting was configured.

## 1.0.0 (121)

FIXED

- iPhone, iPad and Apple TV: changing Settings → Playback → "Compatibility player" now takes effect on the video you are already looking at, instead of only on the next one you open. Choosing "Always" and returning to a video you had open kept using the built-in player.

## 1.0.0 (120)

CHANGED

- iPhone, iPad and Apple TV: the app only returns you to where you were if you were there recently — within half an hour. Come back the next morning and it opens on Home.
- iPhone, iPad and Apple TV: updating the app forgets where you were.
- iPhone, iPad and Apple TV: only the tab you were actually in is remembered. A channel or playlist you left earlier is no longer waiting behind its tab when you come back.

## 1.0.0 (119)

CHANGED

- iPhone, iPad and Apple TV: opening a video from a list now slides in with the page already drawn, instead of flashing an empty page and a spinner first. The details still refresh from your server behind what you are looking at.

## 1.0.0 (118)

FIXED

- iPhone and iPad: starting Picture in Picture from full screen now drops you back into the app, so you can scroll comments while the video keeps playing. It used to leave the full-screen player covering the app with a "playing in picture in picture" message.

## 1.0.0 (117)

ADDED

- iPhone, iPad and Apple TV: the show/hide watched button is now on Home too, in the same place as on a channel and a playlist.

CHANGED

- iPhone, iPad and Apple TV: the show/hide watched buttons are now per screen and last only until you quit the app. Home, a channel and a playlist each keep their own, and none of them changes the "Hide watched videos" setting any more — that setting is the starting point they all begin from.

## 1.0.0 (116)

FIXED

- iPhone and iPad: the app no longer crashes when the built-in player goes full screen. This has been broken since build 105, whether or not Sponsor block was switched on.

CHANGED

- The show/hide watched button's icon now states what you are looking at rather than what tapping does: a struck-through eye means watched videos are hidden.

## 1.0.0 (115)

ADDED

- iPhone, iPad and Apple TV: a channel now has the same three-dot menu a playlist has, holding "Mark All Watched" and "Refresh Channel".
- iPhone, iPad and Apple TV: a show/hide watched videos button sits beside sort on both a channel and a playlist.

CHANGED

- iPhone, iPad and Apple TV: a channel's "Mark All Watched" button has moved off the page and into that three-dot menu, matching a playlist.

## 1.0.0 (114)

CHANGED

- The "Ignore" action is gone from the video menu. A video you have downloaded is not going to be downloaded again, so ignoring one without deleting it did nothing — and the server silently refused it anyway. "Delete and ignore" is unchanged and now verified working.

## 1.0.0 (113)

ADDED

- Apple TV: a channel's video grid has its own sort control, on the same row as the Videos/Streams/Shorts tabs.

CHANGED

- Apple TV: a channel shows four videos per row instead of five, the same size as the cards on Home.

## 1.0.0 (112)

CHANGED

- Apple TV: in playlist and list rows a video's duration now sits next to its published date, instead of a badge covering most of the thumbnail.

## 1.0.0 (111)

FIXED

- iPhone, iPad and Apple TV: "Ignore" and "Delete and ignore" now actually stop a video downloading again — they were asking the server for a mode it only accepts for a video still queued for download, which one already in your library never is.
- iPhone, iPad and Apple TV: an ordinary error from your server is no longer reported as a sign-in page sitting in front of it, unless it really is one.

## 1.0.0 (110)

CHANGED

- Apple TV: Continue watching cards are larger than the Newly added cards below them, the way they already are on iPhone and iPad. The row now shows three at a time instead of four.

## 1.0.0 (109)

FIXED

- Apple TV: Channels and Playlists now leave the same gap under their filter row, matching the fix made for iPhone and iPad in 108.

## 1.0.0 (108)

Spacing fixes under the page headlines.

FIXED

- iPhone and iPad: the Settings list no longer sits too close under the "Settings" headline.
- iPhone and iPad: the Settings list no longer shifts up and down when you open a settings group or come back from one.
- iPad: the gap under the "Settings" headline is no longer oversized, and now matches the other pages.
- iPhone and iPad: Playlists and Channels now leave the same gap between the page headline and the filter row.

## 1.0.0 (107)

Choose which kinds of segment get skipped, and two fixes to how they are chosen.

ADDED

- iPhone, iPad and Apple TV: Settings → Playback → "Sponsor block" now lists the categories it can skip — Sponsor, Unpaid/Self Promotion, Intermission/Intro Animation and Endcards/Credits — each with its own switch. The names are SponsorBlock's own.
- Intros and endcards are off until you turn them on, so nothing changes unless you ask for it.

CHANGED

- The "Skip sponsor segments" switch is now called "Sponsor block", and acts as the master switch for the categories under it.

FIXED

- iPhone, iPad and Apple TV: an intro or outro that starts within a second of a sponsor segment is no longer skipped along with it. Segments that sit close together are only treated as one when they are the same kind.
- iPhone, iPad and Apple TV: a settings screen now updates as you change something on it, instead of waiting until you leave and come back.

## 1.0.0 (105)

Skip sponsor and self-promotion segments, using data your Tube Archivist server already has.

ADDED

- iPhone, iPad and Apple TV: a "Skip sponsor segments" toggle in Settings → Playback, off by default. Only sponsor and self-promotion segments are skipped — intros and outros are never touched.

KNOWN

- Videos your server downloaded (or last reindexed) before SponsorBlock was switched on have nothing to skip, and the app cannot fetch segments for them on its own.

## 1.0.0 (104)

Apple TV now matches your television to what is playing.

ADDED

- Apple TV: if you have Match Content switched on in tvOS Settings → Video and Audio, the television now switches to the frame rate and dynamic range of the video you are playing, instead of leaving everything in whatever mode the Apple TV was already in.
- Apple TV: the television is handed back to its normal mode when you leave the player.

KNOWN

- Apple TV: videos that need the compatibility player — AV1, Opus, WebM/MKV — cannot be matched, because only the built-in player can tell the television what a video needs.

## 1.0.0 (103)

Settings is now one row per group, and a bigger duration badge on Apple TV.

CHANGED

- iPhone, iPad and Apple TV: Settings shows one row per group — Server, Browsing, Search, Playback and About — and you tap into a group to find its settings, instead of every setting on one long page.
- iPhone and iPad: Theme stays at the top of Settings, where it was.
- Apple TV: the duration badge on video thumbnails is larger and readable from the sofa.

## 1.0.0 (101)

Settings regrouped by what each setting affects, and the Video screen settings removed.

CHANGED

- iPhone, iPad and Apple TV: Settings is now five groups instead of eleven — Theme, Server, Browsing, Search and Playback — grouped by what each setting affects rather than by which screen it appears on.
- iPhone, iPad and Apple TV: the local and remote addresses now sit with the server they belong to, instead of in their own section below it.
- iPhone, iPad and Apple TV: Home's and a playlist's sort rows now say which one they sort, and "Hide watched videos" sits with the other filters.
- iPhone, iPad and Apple TV: "Continue watching" and "Recently played first" moved to Playback.

REMOVED

- iPhone, iPad and Apple TV: Settings → "Video screen" is gone, and every section on a video's page is now always shown.

## 1.0.0 (100)

Fixes to both players and to the new video actions menu, all found by using them.

FIXED

- iPhone and iPad: leaving the built-in player's full screen now shrinks the video back into the
  page and keeps playing, instead of stopping it.
- iPad: leaving full screen no longer leaves the tab bar and back button sitting higher up the
  screen.
- Apple TV: the compatibility player no longer washes the picture white when its controls hide.
- Apple TV: clicking the touchpad now pauses and resumes.
- Apple TV: skipping ten seconds with a swipe now works while the controls are on screen.
- iPhone, iPad and Apple TV: touching and holding a video opens its menu without also opening
  the video.
- iPhone, iPad and Apple TV: Continue Watching's recently-played order no longer resets when you
  change network, and now reaches the Apple TV Home Screen row.
- Confirming Delete twice no longer sends the request twice.

CHANGED

- Apple TV: compatibility-player video looks slightly sharper again, after a decode shortcut
  that never fixed 4K stutter was removed.

## 1.0.0 (93)

The compatibility player reaches the Apple TV.

ADDED

- Apple TV: videos your Tube Archivist library can't play with the built-in player — AV1, Opus,
  WebM/MKV — now play using the same bundled compatibility player iPhone and iPad have had,
  with its own remote-friendly controls: Play/Pause, skip ±10 seconds, playback speed, and a
  subtitle picker. Settings → Playback → "Compatibility player" now applies on Apple TV too.
  Previously these videos just explained why they couldn't play.

## 1.0.0 (92)

Three changes on every platform — a menu of real actions on every video, a choice about whether
Play should ask before resuming, and Continue Watching's recently-played order finally reaching
the Apple TV — plus one fewer button competing with Apple TV's own remote, and two playback
fixes.

ADDED

- iPhone, iPad and Apple TV: long-press any video — a card, a list row, a playlist entry — for
  Ignore, Delete, Delete and Ignore, and Add to Playlist, alongside Mark Watched and Open
  Channel. The same six actions are also behind a "…" button on the video's own screen.
  Deleting removes the file from Tube Archivist and cannot be undone; Ignore stops it from
  being downloaded again without deleting what you already have, and can be undone from Tube
  Archivist's own web interface. All three ask for confirmation first and name the video.
- Settings → Playback: "Resuming videos" — Always Resume or Ask, which shows a Resume/Start
  Over prompt before playing a video with saved progress.

CHANGED

- Apple TV: the Resume/Start Over prompt no longer appears by default when you press Play on a
  video with saved progress — it now resumes silently, matching iPhone and iPad. Set
  "Resuming videos" to Ask in Settings to bring the prompt back.
- iPhone and iPad: a video you had barely started (under ten seconds) or had all but finished
  (past 95%) now starts from the beginning instead of resuming. Those are the same two ranges
  the app has always refused to save progress in, so the position it was resuming from could
  only ever have come from somewhere else.

FIXED

- Apple TV: playing something now moves it to the front of Continue Watching, here and on your
  other devices, matching what iPhone and iPad have done since build 80. Playing on the Apple TV
  previously updated nothing — Continue Watching there, and everywhere else, kept its old order
  no matter what you watched on it.
- iPhone and iPad: a video you watched fullscreen, left, and came straight back to now plays
  again. It used to show a player with no picture and no Play button to tap, and the only way
  out was to open a different video first.
- Apple TV: leaving the player and pressing Play again, without navigating away first, now
  resumes where you actually stopped. It used to pick up from wherever the previous session
  had left off, and the position you just watched to was often never sent to the server at all.
- Apple TV: the Continue Watching row on the Home Screen — the one outside the app, above the
  app icon — now leads with what you watched most recently too, matching the row inside the
  app. It also picks its five videos after sorting rather than before, so something you just
  resumed no longer misses the row by being far down the server's own order.

REMOVED

- Apple TV: the "x" button on the full-screen player is gone. Press the remote's Menu button to
  leave the player, the same way you already leave every other screen in the app.

## 1.0.0 (90)

Five fixes from an audit for other instances of the bug fixed in 85 — a part
of the app quietly not carrying the sign-in the rest of it already has, or a
failure reaching you with nothing attached that explains it.

FIXED

- iPhone, iPad and Apple TV: signing in with your Tube Archivist username and
  password no longer signs you out of an SSO login sitting in front of the
  server. It used to happen the moment your account turned out to be an admin
  one, and the app carried on as if the sign-in had worked — every screen and
  every thumbnail failing on a session that had just reported success. Signing
  out did the same, so the next sign-in failed before you had done anything.

- Apple TV: playing a video the Apple TV can't decode — WebM, MKV, VP9, AV1,
  Opus — now says so on the player screen. It used to open a black screen with
  a close button and no explanation, indefinitely.

- Apple TV: a video that fails partway now shows the reason over the player
  instead of leaving you to guess.

- iPhone and iPad: "Retry" on a playback error actually retries. It used to
  clear the error message without restarting anything, leaving a black box or a
  video playing sound with no picture, and no way to get the explanation back.

- Apple TV: when something in front of your server answers instead of Tube
  Archivist, the message no longer tells you to use a browser sign-in that only
  exists on iPhone and iPad. It points at what works on Apple TV instead.

- Apple TV: the Continue Watching row on the Home Screen works when you signed
  in with a username and password. It could only ever appear for accounts that
  had an API token, and showed nothing at all otherwise.

## 1.0.0 (85)

The compatibility player gets past an SSO login in front of your server.

FIXED

- iPhone and iPad: videos that need the compatibility player — AV1, Opus,
  WebM/MKV — play when your Tube Archivist sits behind an SSO login, such as a
  Pangolin or other reverse proxy. Away from home they stopped a few seconds in
  with "Playback stopped unexpectedly", while every other video played fine.
  The compatibility player was the one part of the app fetching video without
  the sign-in the rest of the app had already done, so the proxy's login page
  came back in place of the video. At home the app reaches the server directly
  and never meets that login, which is why this only ever showed up on cellular.

- iPhone and iPad: if a login page does ever arrive where a video should be,
  the error now says so rather than "Playback stopped unexpectedly".

## 1.0.0 (80)

Continue Watching leads with what you were actually watching, and Picture in
Picture stops dropping playback.

ADDED

- iPhone, iPad and Apple TV: Continue Watching now starts with what you watched
  most recently, newest first, instead of an order that never meant anything.
  It syncs through iCloud, so finishing something on the Apple TV moves it on
  your iPhone too. Tube Archivist doesn't record when you watched something, so
  videos you played in its web interface keep their usual place in the row.

- Settings → Home → "Recently played first" turns that off.

FIXED

- iPhone and iPad: bringing a video back from Picture in Picture keeps it
  playing. It used to come back and stop a second later if the app had been
  showing something else.

- iPhone and iPad: Picture in Picture started from full screen returns to full
  screen, instead of to the video's page.

## 1.0.0 (77)

More of the same: when the compatibility player can't play something, it should
always say so, and say why.

FIXED

- iPhone and iPad: if the compatibility player couldn't set up the local
  connection it plays through, it waited on a blank player indefinitely
  without ever saying anything. It now gives up after a few seconds and
  reports what went wrong.

- iPhone and iPad: the reason a video stopped is no longer overwritten before
  you can read it, and it now also covers a video that starts and then stops
  partway rather than one that never starts at all.

## 1.0.0 (76)

A diagnostic build: when the compatibility player can't play something, it now
says why.

CHANGED

- iPhone and iPad: when the compatibility player stops, the message names the
  reason — what the server answered, or what went wrong reaching it — instead
  of only "Playback stopped unexpectedly", which was true of every cause and
  useful for none.

FIXED

- iPhone and iPad: a video the compatibility player couldn't set up properly
  used to be handed to it anyway and fail a second later looking like an
  unrelated problem. It now says what actually went wrong.

## 1.0.0 (75)

Everything since build 68 — a compatibility player for the videos the built-in
one can't play, and the last of the Apple TV selection fixes.

ADDED

- iPhone and iPad: videos the built-in player can't play (AV1, Opus,
  WebM/MKV) now play through a bundled VLC-based compatibility player,
  instead of showing a silent black box. It has the same controls as the
  built-in one — tap to show them, skip ten seconds either way, a scrubber,
  playback speed and subtitles — and still reports progress and resumes
  where you left off.

- iPhone and iPad: the compatibility player appears on the lock screen and
  in Control Center, with title, artwork, a progress bar, play and pause,
  skip ten seconds either way and dragging to a position. Headphone controls
  work too.

- Settings → Playback → "Compatibility player": Automatic uses it only when
  it's needed, Always uses it for every video, Never turns it off.

- iPhone and iPad: a video that needs the compatibility player says so in
  File details, and if you've turned it off, the video's page offers to turn
  it back on.

- Apple TV: a video it can't play says so on the video's page.

- Settings → Playlists: a sort, matching the Home rows above it. The setting
  was already shared across platforms; what was missing was a way to reach
  it on Apple TV.

- Settings → About: VLCKit and its licence.

CHANGED

- Apple TV: a playlist's sort and ⋯ menus moved into the page itself,
  aligned with everything else, instead of sitting in a toolbar strip the
  selection never crossed.

FIXED

- Apple TV: the sort and ⋯ menus on a playlist can be selected. They did
  nothing at all before.

- Apple TV: the selection can get back above a video's description, instead
  of being stuck below "Show More" with the remote's back button the only
  way out.

- Apple TV: File details stays readable when selected. It used to be white
  text on the near-white selection plate.

- Apple TV: full-width rows no longer grow when selected. Growing pushed
  them past the edge of what encloses them and the overflow was cut, which
  is why a playlist number like "216" read as "16".

- Apple TV: "In This Playlist" shows where you actually are. On a video
  two-thirds through a playlist it claimed "218 / 218", counting only
  unwatched videos while describing itself as the whole playlist.

- iPhone, iPad and Apple TV: a playlist sorted by a date the server doesn't
  have keeps playlist order, instead of being shuffled into an order with no
  meaning.

- Apple TV: a selected row inside a card is no longer cut off as it grows,
  comment text is the right size beside its timestamp, and the video screen
  no longer gives up a sixth of the screen to empty margin.

## 1.0.0 (68)

Everything since build 63, mostly Apple TV and a run of playback fixes.

CHANGED

- Apple TV: the sort control on Home and Playlists is a compact caption on
  the first section's heading line, instead of a round button on a row of
  its own.

- iPhone and iPad: the playlist card on a video page follows the sort you
  chose on the Playlists screen, so a playlist sorted by publish date reads
  that way here too instead of always showing playlist order.

- iPhone and iPad: tapping an expanded video description collapses it again,
  so a long one no longer has to be scrolled to the bottom to reach "Show
  Less".

- Settings: "Sign Out" moved to the bottom of the screen.

- iPhone and iPad: Home, Channels, Playlists and Settings now start their
  page titles at the same height and the same size.

FIXED

- Apple TV: Channels works again. Opening a channel showed one enormous
  banner filling the screen with no way to scroll down to the videos.

- Apple TV: the white box around the selected item is gone for good, and
  selected items keep readable text.

- Apple TV: Play and Mark as Watched on a video screen stay readable when
  selected, instead of turning white on a near-white background.

- Apple TV: Settings can be scrolled back up past "Sign Out" — it used to
  trap the selection there, with the remote's back button the only way out.

- iPhone and iPad: the app remembers which video page you were on and
  returns you to it, instead of starting at Home every time iOS has closed
  it in the background.

- iPhone and iPad: bringing a Picture in Picture video back to full screen
  returns to that video's page and keeps playing, instead of landing on Home
  with playback stopped.

- iPhone: the filter bars on Channels and Playlists are the same height.

- iPhone and iPad: the Settings screen uses the same background colour as
  the rest of the app in light mode.

## 1.0.0 (63)

Everything since build 60, mostly Apple TV selection fixes.

CHANGED

- Apple TV: the sort control sits on the same line as the first section
  heading instead of on its own row below the tab bar, where it was cut off
  at the right edge.

- Apple TV: open a video's channel from the ⋯ menu on the video screen. The
  channel name and logo under the title are no longer tappable.

- iPhone: a video's playlist pager and Similar Videos now genuinely share
  one card, with Comments below them both.

FIXED

- iPhone and iPad: Picture in Picture works. Sending a playing video to a
  floating window used to stop playback instantly.

- Apple TV: the white box around the selected item is gone. Selected videos,
  channels, playlists and rows keep their own text colours, which were
  unreadable on that white background.

- Apple TV: Play, Mark as Watched and the ⋯ menu on the video screen can be
  selected with the remote. They could not be reached at all before.

- Apple TV: opening a video puts the selection on Play, instead of jumping
  down to Show More in the description and scrolling the title off screen.

- iPhone: the filter bars on the Channels and Playlists screens are the same
  height as each other.

## 1.0.0 (60)

Everything since build 52, the last build with a changelog entry.

ADDED

- Settings → Search: the reorder rows show a drag-handle glyph, so it's
  clear they can be dragged.

CHANGED

- iPhone: a video's playlist pager and Similar Videos now sit together as
  one adjacent section, instead of being split apart by Comments.

- iPad: search has its own in-content field instead of the system's tab-bar
  search, since the system version made the whole tab bar disappear while
  typing with no way to switch sections.

- iPhone: the Playlists filter row (All/Regular/Custom/Subscribed) fits on
  one line now — Subscribed no longer needs a horizontal scroll to reach.

- Settings: "Hide watched videos" moved out of the Home section into its
  own, since it also applies to a channel's videos and a playlist's entries,
  not just Home.

- Settings → Video screen no longer supports reordering sections, only
  showing/hiding them — iPad and Apple TV already ignored the order for most
  sections, so the control mostly did nothing there.

- Home: removed the "See all" link next to Continue Watching and Newly
  Added — it didn't go anywhere.

- The empty search page shows just "Search Tube Archivist", without the
  extra description text underneath.

- Apple TV: the Server field and Sign-in method control on the login screen
  actually fit their own text now, and duplicate screen titles no longer
  overlap the content beneath them.

- Apple TV: a playlist's own page and a video's page are restructured to
  match iPad — a compact info card, a two-column video grid, and the
  playlist pager paired with Similar Videos, instead of three separate
  layouts.

FIXED

- Search results no longer briefly flash back to a loading spinner when
  returning to the Search tab, or coming back from a video or playlist
  pushed on top of it.

- "Hide watched videos" now also applies to the playlist pager on a video's
  own page, which kept showing watched videos regardless of the setting.

## 1.0.0 (52)

Everything since build 47, the last build with a changelog entry.

ADDED

- iPhone and iPad: playlist rows show a watched checkmark on the thumbnail,
  the same as every other video row.

CHANGED

- iPad: a video's playlist panel sits below Comments — or beside Similar
  Videos, when there aren't any — instead of a fixed panel next to the
  title, and only takes up as much room as it actually has videos for.

- iPhone and iPad: "In this playlist" now shows more of what's ahead than
  what's already watched — three videos after the current one and one
  before, by default, instead of split evenly.

- iPad: the Channels grid matches Home's own card size, instead of packing
  in smaller ones.

- iPhone and iPad: video rows show more of the channel name and date, no
  longer sharing one line that could cut off both.

- iPhone and iPad: a playlist's own page is far more compact — cover,
  title, owner, video count and Subscribed status take up a fraction of the
  space they used to, and Mark All Watched and refresh moved into a menu
  next to Sort.

FIXED

- iPhone and iPad: a video's duration badge no longer shows seconds once it
  passes an hour.

## 1.0.0 (47)

Everything since build 38, the last build with a changelog entry.

ADDED

- iPhone and iPad: video playback happens inline on the page instead of in a
  full-screen player, so the rest of the page can keep scrolling underneath it.

- iPad: a video's page shows a swipeable panel listing every playlist it
  belongs to, one page per playlist, next to the video.

- Apple TV: a Top Shelf entry on the Home Screen shows Continue Watching, and
  selecting one opens straight into that video.

- iPhone and iPad: Continue Watching on Home can be switched between a
  horizontal carousel and a full grid or list, from Settings.

- iPhone and iPad: which sections a video's page shows, and their order, can
  be set per person from Settings → Video screen.

CHANGED

- iPhone, iPad and Apple TV: the whole app has a new warm card look with a
  monospaced numbers style, replacing the previous one.

- iPhone and iPad: a video's title, channel, stats and description now sit
  together in one card instead of several separate ones below each other; the
  overflow menu is gone, leaving just Mark as Watched.

- iPhone and iPad: the page headline on Home, Channels and Playlists sits on
  the same line as the view and sort controls, instead of its own row above
  them.

- iPhone and iPad: a video, channel or playlist page no longer repeats its
  title next to the back button.

- iPhone and iPad: Continue Watching's cards are noticeably larger than Newly
  Added's, and no longer sit inside their own card frame.

- iPad: next to Comments, Similar Videos is a single column instead of a
  horizontal scroll, and File details collapses to one row to match iPhone's
  width.

FIXED

- iPhone and iPad: tapping maximise on an inline video no longer drops the
  picture and stops playback.

- iPhone and iPad: returning from full screen no longer resets an inline
  video to its resting thumbnail — it now shows exactly where it was.

- iPad: a video's Similar Videos no longer stretches to match a long Comments
  list next to it; it now stops after its own last video.

- iPad: the playlist panel is no longer its own scrollable area, so dragging
  on it scrolls the page like everywhere else.

## 1.0.0 (38)

Everything since build 27, the last build uploaded. iOS and tvOS now share one
bundle id, so this is a new App Store Connect entry — delete the old Plevi TA
before installing, and sign in again.

ADDED

- Apple TV: the app is now available on Apple TV, from the same TestFlight
  invite as iPhone and iPad.

- iPhone and iPad: a server behind an SSO login page can be signed into through
  an in-app browser, from the button under Sign In.

- iPhone and iPad: the browser sign-in is also available in Settings, under
  Connection, so a remote address added after signing in can get past its login
  page.

- iPhone and iPad: the address signed in with is filled in as the local or
  remote server automatically, rather than having to be typed again in Settings.

CHANGED

- iPhone and iPad: comments load fifteen at a time behind a Load More button,
  rather than every comment at once.

FIXED

- iPhone and iPad: signing in to a local address waits about fifteen seconds for
  local network access to be allowed, rather than failing with a connection
  error before the permission alert can be answered.

- iPhone and iPad: a server that answers with a login page now says something is
  sitting in front of it and points at the browser sign-in, rather than
  "Couldn't understand the server's response".

## 1.0.0 (27)

The first build to leave the development machine, so everything is new. Apple TV
is not in this build — it is a separate app record and still needs provisioning.

ADDED

- iPhone and iPad: Home opens on Continue Watching, followed by everything newly
  added to the server.

- iPhone and iPad: playback resumes at the position the server already holds,
  unless the video is already marked watched.

- iPhone and iPad: the position is reported back to the server every ten seconds
  and on pause, seek, backgrounding and closing, so other clients see it.

- iPhone and iPad: finishing a video marks it watched, and starts the next one
  when auto-play next is on.

- iPhone and iPad: audio keeps playing when the app is backgrounded.

- iPhone and iPad: timestamps and links in a description are tappable, and a
  timestamp seeks to that point.

- iPhone and iPad: comments are threaded, with replies collapsed under each
  comment.

- iPhone and iPad: a video in a playlist has Previous and Next controls, which
  can skip entries already watched.

- iPhone and iPad: a channel page shows only the tabs that channel has, out of
  Videos, Streams, Shorts and Playlists.

- iPhone and iPad: a whole channel can be marked watched in one action.

- iPhone and iPad: playlists keep the server's order and can be re-sorted
  locally by position, title or date.

- iPhone and iPad: playlist entries the server never downloaded are hidden
  rather than shown as rows that cannot be played.

- iPhone and iPad: search covers videos, channels and playlists at once, grouped
  by kind, in a section order set in Settings.

- iPhone and iPad: Home, Channels and Playlists each keep their own sort field,
  order and grid-or-list view style.

- iPhone and iPad: watched videos can be hidden everywhere a video list appears,
  including inside a playlist.

- iPhone and iPad: sign-in takes either an API token or a username and password,
  and the credential is kept in the Keychain.

- iPhone and iPad: a local and a remote address can both be set, and the app
  probes the local one on a short timeout when the network changes, falling back
  to the remote one.

- iPhone and iPad: the theme follows the system, or can be pinned to light or
  dark.

- iPhone and iPad: Dynamic Type is supported up to the accessibility sizes, with
  rows stacking instead of clipping where they no longer fit side by side.

- iPhone and iPad: VoiceOver labels throughout.
