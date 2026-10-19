
import Foundation

public enum SearchAccentProbe {
    /// At most this many extra requests per search. One is the table-free probe; the rest are
    /// first-letter substitutions. Four keeps a home server's Elasticsearch honest — these
    /// fire on a debounced search, not per keystroke.
    public static let maximumProbes = 4

    /// Below this, a word's prefix matches so much of the library that the probe is noise
    /// rather than a rescue — "sk" alone returns 26 videos on the reporter's server.
    public static let minimumWordLength = 3

    /// Accented forms of the letters that can START a word, which is the only position the server's own fuzziness cannot cover (see this file's doc comment).
    static let leadingForms: [Character: [Character]] = [
        "a": ["å", "ä", "á", "æ"],
        "o": ["ø", "ö", "ó"],
        "e": ["é", "è", "ë"],
        "s": ["š", "ś"],
        "z": ["ž", "ź"],
        "c": ["č", "ć"],
        "u": ["ü", "ú"],
        "i": ["í", "ï"],
        "n": ["ñ"],
        "l": ["ł"],
        "t": ["ť"],
        "r": ["ř"],
        "d": ["ď"],
        "g": ["ğ"],
        "y": ["ý"],
    ]

    /// Transliterates to lowercase ASCII.
    public static func fold(_ text: String) -> String {
        text.applyingTransform(StringTransform(rawValue: "Latin-ASCII; Lower"), reverse: false)
            ?? text.lowercased()
    }

    /// The extra queries to run beside the user's own, or empty when there is nothing to widen.
    ///
    /// Returns the queries verbatim, ready to send — the caller does not reshape them.
    public static func probes(for rawQuery: String) -> [String] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // TA reads `channel:`, `playlist:`, `active:`, `full:` and `fuzzy:` out of the query before it ever reaches the matcher, and its parser is positional.
        guard !query.contains(":") else { return [] }

        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let finalWord = words.last, finalWord.count >= minimumWordLength else { return [] }

        // Already accented: the user typed the spelling the index holds, so the server's own
        // prefix query finds it and there is nothing to widen.
        guard fold(finalWord) == finalWord.lowercased() else { return [] }
        guard let first = finalWord.lowercased().first, first.isLetter else { return [] }

        // The table-free probe first: it covers every accent that is not on the first letter,
        // which is most of them, so it is the one that survives the cap.
        var probes = [query + " " + String(first)]
        for form in leadingForms[first, default: []] {
            guard probes.count < maximumProbes else { break }
            probes.append(query + " " + String(form))
        }
        return probes
    }

    /// Whether a probe's hit is actually what the user was looking for.
    public static func matches(_ text: String, query: String) -> Bool {
        let haystack = fold(text)
        let needles = fold(query).split(whereSeparator: \.isWhitespace)
        guard !needles.isEmpty else { return false }
        return needles.allSatisfy { haystack.contains($0) }
    }
}
