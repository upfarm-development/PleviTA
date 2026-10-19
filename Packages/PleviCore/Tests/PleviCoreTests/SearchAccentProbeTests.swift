
import Foundation
import Testing
@testable import PleviCore

@Suite("SearchAccentProbe")
struct SearchAccentProbeTests {

    // MARK: - Folding

    @Test("folds decorated vowels and separate letters alike")
    func foldingCoversSeparateLetters() {
        #expect(SearchAccentProbe.fold("Škoda") == "skoda")
        #expect(SearchAccentProbe.fold("Bjørn Nyland") == "bjorn nyland")
        #expect(SearchAccentProbe.fold("Tromsø") == "tromso")
        #expect(SearchAccentProbe.fold("Ålesund") == "alesund")
        #expect(SearchAccentProbe.fold("Łódź") == "lodz")
        #expect(SearchAccentProbe.fold("München") == "munchen")
    }

    /// Pinned deliberately: this is the exact comparison that would have silently lost the
    /// reporter's most-watched channel.
    @Test("diacritic folding alone would not have been enough")
    func diacriticFoldingIsInsufficient() {
        let diacritic = "Bjørn Nyland".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        #expect(diacritic != "bjorn nyland")
        #expect(SearchAccentProbe.fold("Bjørn Nyland") == "bjorn nyland")
    }

    @Test("folding does not depend on the current locale")
    func foldingIsLocaleIndependent() {
        // No locale is passed anywhere in `fold`; this pins that the transform itself is
        // stable, so a Turkish or Norwegian device cannot get a different answer.
        #expect(SearchAccentProbe.fold("İstanbul") == "istanbul")
        #expect(SearchAccentProbe.fold("SKODA") == "skoda")
    }

    // MARK: - Probe construction

    @Test("a word whose first letter has no accented forms gets exactly one probe")
    func singleProbeWhenNoLeadingForms() {
        #expect(SearchAccentProbe.probes(for: "bjorn") == ["bjorn b"])
    }

    @Test("a word whose first letter has accented forms gets the plain probe plus each form")
    func probesSubstituteTheFirstLetter() {
        #expect(SearchAccentProbe.probes(for: "skoda") == ["skoda s", "skoda š", "skoda ś"])
    }

    @Test("the probe count is capped")
    func probeCountIsCapped() {
        let probes = SearchAccentProbe.probes(for: "alesund")
        #expect(probes.count == SearchAccentProbe.maximumProbes)
        #expect(probes.first == "alesund a")
    }

    @Test("only the final word is widened, since earlier terms already get fuzziness")
    func onlyTheFinalWordIsWidened() {
        #expect(SearchAccentProbe.probes(for: "road trip bjorn") == ["road trip bjorn b"])
    }

    @Test("a query that already carries accents is left alone")
    func accentedQueryNeedsNoProbe() {
        #expect(SearchAccentProbe.probes(for: "škoda").isEmpty)
        #expect(SearchAccentProbe.probes(for: "Bjørn").isEmpty)
    }

    @Test("a query carrying TA operator syntax is never rewritten")
    func operatorSyntaxIsUntouched() {
        #expect(SearchAccentProbe.probes(for: "channel:skoda").isEmpty)
        #expect(SearchAccentProbe.probes(for: "full:skoda").isEmpty)
        #expect(SearchAccentProbe.probes(for: "skoda fuzzy:2").isEmpty)
    }

    @Test("a short final word is not widened — its prefix matches too much to be useful")
    func shortWordsAreNotWidened() {
        #expect(SearchAccentProbe.probes(for: "sk").isEmpty)
        #expect(SearchAccentProbe.probes(for: "bjorn ny").isEmpty)
    }

    // MARK: - Filtering probe hits

    @Test("the sieve keeps the accented hit and drops the fuzzy near-miss")
    func matchesSeparatesRescueFromNoise() {
        #expect(SearchAccentProbe.matches("Bjørn Nyland", query: "bjorn"))
        #expect(!SearchAccentProbe.matches("Cupra Born 58 Geilo test", query: "bjorn"))
        #expect(SearchAccentProbe.matches("Škoda Peaq | 936 km on a Single Charge", query: "skoda"))
    }

    @Test("every word of the query has to appear")
    func matchesRequiresEveryWord() {
        #expect(SearchAccentProbe.matches("Škoda Peaq range test", query: "skoda peaq"))
        #expect(!SearchAccentProbe.matches("Škoda Epiq range test", query: "skoda peaq"))
    }
}

@Suite("SearchResults widening")
struct SearchResultsWideningTests {
    private func video(_ id: String, _ title: String) -> Video {
        Video(youtubeId: id, title: title)
    }

    @Test("filtering a probe's results drops what does not match the user's own words")
    func filteringDropsNoise() {
        let probeHits = SearchResults(
            videoResults: [video("a", "Škoda Peaq"), video("b", "Cupra Born 58")],
            channelResults: [Channel(channelId: "c1", channelName: "Škoda")],
            playlistResults: []
        )
        let kept = probeHits.filtered(matching: "skoda")
        #expect(kept.videoResults?.map(\.id) == ["a"])
        #expect(kept.channelResults?.map(\.id) == ["c1"])
    }

    @Test("appending adds only what is new, and keeps the server's own order first")
    func appendingDedupesById() {
        let primary = SearchResults(videoResults: [video("a", "Skoda Enyaq")])
        let widened = SearchResults(videoResults: [video("a", "Skoda Enyaq"), video("z", "Škoda Peaq")])
        let combined = primary.appending(widened)
        #expect(combined.videoResults?.map(\.id) == ["a", "z"])
    }

    @Test("appending nothing changes nothing")
    func appendingEmptyIsANoOp() {
        let primary = SearchResults(videoResults: [video("a", "Skoda Enyaq")])
        #expect(primary.appending(SearchResults()) == primary)
    }
}
