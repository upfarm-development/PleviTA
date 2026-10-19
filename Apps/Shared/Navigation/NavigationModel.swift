// Where "which tab, and how deep in it" lives, so that no view rebuild can throw it away.

import SwiftUI
import PleviCore

@MainActor
@Observable
final class NavigationModel {
    /// The selected tab.
    var selectedSection: AppSection = .home

    /// Bumped when the tvOS sidebar hands focus to the page after Select, so a page that wants a
    /// particular first item (Channels, Playlists) can put focus there. Left to itself, tvOS picks the
    /// top-leading focusable thing, which on those pages is the filter row.
    var pageEntryRequest = 0

    /// One `NavigationStack` path per section. Absent means "at the root",
    /// so a section that has never been visited needs no entry.
    var paths: [AppSection: [Route]] = [:]

    func path(for section: AppSection) -> [Route] {
        paths[section] ?? []
    }

    /// A binding a `NavigationStack` can own directly. Writing an empty array
    /// clears the entry rather than storing `[]`, so `paths` stays a record of
    /// only the sections actually holding a route.
    func binding(for section: AppSection) -> Binding<[Route]> {
        Binding(
            get: { [weak self] in self?.paths[section] ?? [] },
            set: { [weak self] newValue in
                guard let self else { return }
                if newValue.isEmpty {
                    self.paths.removeValue(forKey: section)
                } else {
                    self.paths[section] = newValue
                }
            }
        )
    }

    /// Where the thing currently playing lives, recorded when playback starts.
    struct PlayingLocation: Equatable {
        var section: AppSection
        var route: Route
    }
    var playing: PlayingLocation?

    /// Brings a route to the top of its section and selects that section.
    func reveal(_ route: Route, in section: AppSection) {
        // The no-op test comes first on purpose.
        if selectedSection == section, path(for: section).last == route { return }
        selectedSection = section
        var existing = path(for: section)
        if existing.last == route { return }
        if let index = existing.firstIndex(of: route) {
            existing.removeSubrange((index + 1)...)
        } else {
            existing.append(route)
        }
        paths[section] = existing
    }

    // MARK: - Restoring across a relaunch

    /// Where the user was, small enough to keep in `UserDefaults`.
    private struct Snapshot: Codable {
        var selectedSection: String
        var path: [Route]
        var savedAt: Date
        var build: String
    }

    private static let defaultsKey = "navigation.snapshot"

    /// `CFBundleVersion` — the build number bumped on every commit, so any update at all
    /// invalidates a saved place, not just a marketing-version change.
    private static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// Called whenever the user moves, so a relaunch can pick up where they were.
    func persist(to defaults: UserDefaults = .standard, now: Date = .now) {
        let snapshot = Snapshot(
            selectedSection: selectedSection.rawValue,
            path: paths[selectedSection] ?? [],
            savedAt: now,
            build: Self.currentBuild
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Restores a previous session's place, if `NavigationRestorePolicy` still considers it one.
    func restore(from defaults: UserDefaults = .standard, now: Date = .now) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        let decision = NavigationRestorePolicy.decide(
            savedAt: snapshot.savedAt,
            savedBuild: snapshot.build,
            now: now,
            currentBuild: Self.currentBuild
        )
        guard decision == .restore else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        guard let section = AppSection(rawValue: snapshot.selectedSection) else { return }
        selectedSection = section
        // Only this section's stack. Every other tab opens at its root, which is what was
        // asked for and also what the snapshot now carries.
        paths = [section: snapshot.path]
    }
}
