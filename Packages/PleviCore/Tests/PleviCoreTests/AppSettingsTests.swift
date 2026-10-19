
import Foundation
import Testing
@testable import PleviCore

@MainActor
@Suite("AppSettings")
struct AppSettingsTests {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suiteName = "com.plevi.ta.tests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Watched filter scoping

    @Test("a screen with no override of its own reads the persisted default")
    func watchedFilterFallsBackToTheDefault() {
        let settings = AppSettings(defaults: makeDefaults(#function))
        settings.hideWatched = true
        for scope in WatchedFilterScope.allCases {
            #expect(settings.hideWatched(in: scope))
        }
        settings.hideWatched = false
        for scope in WatchedFilterScope.allCases {
            #expect(!settings.hideWatched(in: scope))
        }
    }

    @Test("one screen's filter does not move another's")
    func watchedFilterIsPerScope() {
        let settings = AppSettings(defaults: makeDefaults(#function))
        settings.hideWatched = false
        settings.setHideWatched(true, in: .channelVideos)
        #expect(settings.hideWatched(in: .channelVideos))
        #expect(!settings.hideWatched(in: .home))
        #expect(!settings.hideWatched(in: .playlistEntries))
        #expect(!settings.hideWatched, "the persisted default must be untouched")
    }

    @Test("an override lasts the session and no longer — it never reaches UserDefaults")
    func watchedFilterOverrideIsNotPersisted() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.hideWatched = false
        first.setHideWatched(true, in: .home)
        #expect(first.hideWatched(in: .home))

        // A second instance over the same defaults stands in for a relaunch.
        let relaunched = AppSettings(defaults: defaults)
        #expect(!relaunched.hideWatched(in: .home), "the override must not survive a relaunch")
        #expect(!relaunched.hideWatched)
    }

    @Test("changing the setting in Settings clears every screen's override")
    func settingsTogglePreemptsOverrides() {
        // An explicit trip to Settings is the user saying what they want everywhere. A
        // screen nudged an hour earlier should not quietly keep ignoring it.
        let settings = AppSettings(defaults: makeDefaults(#function))
        settings.hideWatched = false
        settings.setHideWatched(true, in: .home)
        settings.setHideWatched(true, in: .channelVideos)

        settings.hideWatched = true
        #expect(settings.hideWatched(in: .home))
        #expect(settings.hideWatched(in: .channelVideos))

        settings.hideWatched = false
        for scope in WatchedFilterScope.allCases {
            #expect(!settings.hideWatched(in: scope), "\(scope) kept a stale override")
        }
    }

    @Test("sponsorBlockCategories starts empty (off), and round-trips")
    func sponsorBlockCategoriesPersists() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        #expect(first.sponsorBlockCategories.isEmpty)
        first.sponsorBlockCategories = [.sponsor, .intro]
        #expect(AppSettings(defaults: defaults).sponsorBlockCategories == [.sponsor, .intro])
    }

    @Test("every category switched off survives a relaunch instead of reverting to the default")
    func sponsorBlockCategoriesEmptySurvives() {
        // The distinction the nil-check in `init` carries: "never written" takes the default
        // set, "the user turned them all off" must stay off. Collapsing the two would silently
        // re-enable skipping for anyone who cleared it one row at a time.
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.sponsorBlockCategories = []
        #expect(AppSettings(defaults: defaults).sponsorBlockCategories.isEmpty)
    }

    @Test("defaults match the specified values")
    func defaultsMatchPlan() {
        let settings = AppSettings(defaults: makeDefaults(#function))
        #expect(settings.homeSortField == .downloaded)
        #expect(settings.homeSortOrder == .desc)
        #expect(settings.hideWatched == false)
        #expect(settings.channelsSubscribedOnly == false)
        #expect(settings.playlistsSubscribedOnly == false)
        #expect(settings.autoPlayNext == true)
        #expect(settings.videoTypeFilter == nil)
        #expect(settings.homeViewStyle == .grid)
        #expect(settings.channelsViewStyle == .grid)
        #expect(settings.playlistsViewStyle == .grid)
        #expect(settings.playlistsSortField == .name)
        #expect(settings.playlistsSortOrder == .asc)
        // Matches Home's own defaults (downloaded/desc) but is its own
        // setting, tracked independently — see `channelVideoSortField`'s
        // own doc comment.
        #expect(settings.channelVideoSortField == .downloaded)
        #expect(settings.channelVideoSortOrder == .desc)
        #expect(settings.playlistDetailSortField == .playlistOrder)
        #expect(settings.playlistDetailSortOrder == .asc)
        // Today's implicit, unchanged Videos/Channels/Playlists order for
        // anyone who never touches the new "Search" Settings section.
        #expect(settings.searchResultsOrder == [.video, .channel, .playlist])
        #expect(settings.playlistNavSkipWatched == true)
        #expect(settings.appTheme == .system)
        #expect(settings.continueWatchingStyle == .carousel)
        #expect(settings.fallbackPlayerMode == .automatic)
        #expect(settings.resumeBehavior == .alwaysResume)
        // Off by default: this changes what plays without being asked, so it opts in.
        #expect(settings.sponsorBlockEnabled == false)
        // Off by default: a save can be hundreds of MB to several GB and shouldn't spend a
        // cellular plan without being asked.
        #expect(settings.allowCellularDownloads == false)
    }

    @Test("playlistNavSkipWatched and appTheme persist across a fresh instance")
    func newSettingsPersist() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.playlistNavSkipWatched = false
        first.appTheme = .dark

        let second = AppSettings(defaults: defaults)
        #expect(second.playlistNavSkipWatched == false)
        #expect(second.appTheme == .dark)
    }

    @Test("fallbackPlayerMode persists across a fresh instance")
    func fallbackPlayerModePersists() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.fallbackPlayerMode = .always

        let second = AppSettings(defaults: defaults)
        #expect(second.fallbackPlayerMode == .always)
    }

    @Test("appTheme falls back to .system when UserDefaults holds an unrecognised string")
    func appThemeFallsBackOnCorruptedStorage() {
        let defaults = makeDefaults(#function)
        defaults.set("sepia", forKey: "settings.appTheme")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.appTheme == .system)
    }

    @Test("resumeBehavior persists across a fresh instance")
    func resumeBehaviorPersists() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.resumeBehavior = .ask

        let second = AppSettings(defaults: defaults)
        #expect(second.resumeBehavior == .ask)
    }

    @Test("resumeBehavior falls back to .alwaysResume when UserDefaults holds an unrecognised string")
    func resumeBehaviorFallsBackOnCorruptedStorage() {
        let defaults = makeDefaults(#function)
        defaults.set("someday", forKey: "settings.resumeBehavior")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.resumeBehavior == .alwaysResume)
    }

    @Test("SponsorBlock is on exactly when a category is selected")
    func sponsorBlockFollowsCategories() {
        let defaults = makeDefaults(#function)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.sponsorBlockEnabled == false)
        settings.sponsorBlockCategories = [.intro]
        #expect(settings.sponsorBlockEnabled == true)
        #expect(AppSettings(defaults: defaults).sponsorBlockEnabled == true)
        settings.sponsorBlockCategories = []
        #expect(AppSettings(defaults: defaults).sponsorBlockEnabled == false)
    }

    @Test("an old install with the master switch off does not start skipping, and keeps nothing selected")
    func oldSwitchOffMigratesToOff() {
        let defaults = makeDefaults(#function)
        defaults.set(false, forKey: "settings.sponsorBlockEnabled")
        defaults.set(["sponsor", "selfpromo"], forKey: "settings.sponsorBlockCategories")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.sponsorBlockEnabled == false)
        #expect(settings.sponsorBlockCategories.isEmpty)
    }

    @Test("an old install with the master switch on keeps its categories")
    func oldSwitchOnKeepsCategories() {
        let defaults = makeDefaults(#function)
        defaults.set(true, forKey: "settings.sponsorBlockEnabled")
        defaults.set(["sponsor", "intro"], forKey: "settings.sponsorBlockCategories")
        #expect(AppSettings(defaults: defaults).sponsorBlockCategories == [.sponsor, .intro])
    }

    @Test("a choice made after the migration is not undone on the next launch")
    func migrationRunsOnce() {
        let defaults = makeDefaults(#function)
        defaults.set(false, forKey: "settings.sponsorBlockEnabled")
        let first = AppSettings(defaults: defaults)
        first.sponsorBlockCategories = [.sponsor]
        #expect(AppSettings(defaults: defaults).sponsorBlockCategories == [.sponsor])
    }

    @Test("allowCellularDownloads persists across a fresh instance")
    func allowCellularDownloadsPersists() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.allowCellularDownloads = true

        let second = AppSettings(defaults: defaults)
        #expect(second.allowCellularDownloads == true)
    }

    @Test("searchResultsOrder persists a reordering across a fresh instance")
    func searchResultsOrderPersists() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.searchResultsOrder = [.playlist, .video, .channel]

        let second = AppSettings(defaults: defaults)
        #expect(second.searchResultsOrder == [.playlist, .video, .channel])
    }

    @Test("searchResultsOrder falls back to the default when UserDefaults holds something invalid")
    func searchResultsOrderFallsBackOnCorruptedStorage() {
        let defaults = makeDefaults(#function)
        // Simulates a stale/foreign array — missing a case, a duplicate, and an unrecognized raw value.
        defaults.set(["video", "video", "nonsense"], forKey: "settings.searchResultsOrder")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.searchResultsOrder == [.video, .channel, .playlist])
    }

    @Test("continueWatchingStyle persists across a fresh instance, defaulting to .carousel")
    func continueWatchingStylePersists() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        #expect(first.continueWatchingStyle == .carousel)
        first.continueWatchingStyle = .list

        let second = AppSettings(defaults: defaults)
        #expect(second.continueWatchingStyle == .list)
    }

    @Test("continueWatchingStyle falls back to .carousel when UserDefaults holds an unrecognised string")
    func continueWatchingStyleFallsBackOnCorruptedStorage() {
        let defaults = makeDefaults(#function)
        defaults.set("grid", forKey: "settings.continueWatchingStyle")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.continueWatchingStyle == .carousel)
    }

    @Test("the four new sort settings persist independently of each other and of Home's own sort")
    func sortSettingsPersistIndependently() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.homeSortField = .published
        first.homeSortOrder = .asc
        first.playlistsSortField = .channel
        first.playlistsSortOrder = .desc
        first.channelVideoSortField = .published
        first.channelVideoSortOrder = .asc
        first.playlistDetailSortField = .title
        first.playlistDetailSortOrder = .desc

        let second = AppSettings(defaults: defaults)
        #expect(second.homeSortField == .published)
        #expect(second.homeSortOrder == .asc)
        #expect(second.playlistsSortField == .channel)
        #expect(second.playlistsSortOrder == .desc)
        #expect(second.channelVideoSortField == .published)
        #expect(second.channelVideoSortOrder == .asc)
        #expect(second.playlistDetailSortField == .title)
        #expect(second.playlistDetailSortOrder == .desc)
    }

    @Test("per-page view styles persist independently across a fresh instance")
    func viewStylesPersistIndependently() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.homeViewStyle = .list
        // Channels/Playlists deliberately left at their .grid default, to prove toggling one page's style doesn't affect the others.
        #expect(first.channelsViewStyle == .grid)
        #expect(first.playlistsViewStyle == .grid)

        let second = AppSettings(defaults: defaults)
        #expect(second.homeViewStyle == .list)
        #expect(second.channelsViewStyle == .grid)
        #expect(second.playlistsViewStyle == .grid)
    }

    @Test("seeds hideWatched/showSubedOnly/showSubedOnlyPlaylists from /api/user/me/ once")
    func seedsFromServerOnce() {
        let settings = AppSettings(defaults: makeDefaults(#function))
        settings.seedFromServerIfNeeded(UserConfig(hideWatched: true, showSubedOnly: true, showSubedOnlyPlaylists: true))
        #expect(settings.hideWatched == true)
        #expect(settings.channelsSubscribedOnly == true)
        #expect(settings.playlistsSubscribedOnly == true)

        // A later config (e.g. a second login) must NOT override a value the
        // user has since changed locally in Settings.
        settings.hideWatched = false
        settings.seedFromServerIfNeeded(UserConfig(hideWatched: true, showSubedOnly: false, showSubedOnlyPlaylists: false))
        #expect(settings.hideWatched == false)
    }

    @Test("resetServerSeed allows seeding again after sign-out")
    func resetAllowsReseed() {
        let settings = AppSettings(defaults: makeDefaults(#function))
        settings.seedFromServerIfNeeded(UserConfig(hideWatched: true))
        settings.resetServerSeed()
        settings.hideWatched = false
        settings.seedFromServerIfNeeded(UserConfig(hideWatched: true))
        #expect(settings.hideWatched == true)
    }

    @Test("persists across a fresh instance reading the same UserDefaults")
    func persistsAcrossInstances() {
        let defaults = makeDefaults(#function)
        let first = AppSettings(defaults: defaults)
        first.hideWatched = true
        first.homeSortField = .published

        let second = AppSettings(defaults: defaults)
        #expect(second.hideWatched == true)
        #expect(second.homeSortField == .published)
    }
}
