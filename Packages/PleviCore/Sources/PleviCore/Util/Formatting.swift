
import Foundation

public enum PleviFormatting {
    /// `total_size`/`Video.mediaSize` (bytes) -> a short human-readable string ("4.5 GiB") using the design system's own binary-unit labels.
    public static func byteCount(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 B" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let formattedValue = unitIndex == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(formattedValue) \(units[unitIndex])"
    }

    /// `total_duration` (seconds) -> a short human-readable approximation ("3d 4h", "45m"), not an exact `mm:ss`.
    public static func approximateDuration(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: seconds) ?? "—"
    }

    /// `published` / `*_last_refresh` arrive as a formatted string, not a Unix timestamp.
    public static func displayDate(from raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]

        let date = isoWithFractional.date(from: raw) ?? iso.date(from: raw) ?? dateOnly.date(from: raw)
        if let date {
            return date.formatted(date: .abbreviated, time: .omitted)
        }

        // Defensive fallback for an unrecognized shape: strip an obvious
        // time component rather than showing it, without claiming to have
        // actually parsed a date.
        if let tIndex = raw.firstIndex(of: "T") {
            return String(raw[raw.startIndex..<tIndex])
        }
        return raw
    }

    /// A video's duration (seconds) -> a clock-style badge string ("4:05", "1:02:03").
    public static func clockDuration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// A video's duration -> a thumbnail duration-badge string, on every platform.
    public static func durationBadge(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        guard hours > 0 else { return clockDuration(seconds: seconds) }
        let minutes = (total % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    public static func dataRate(bitsPerSecond: Int) -> String {
        guard bitsPerSecond > 0 else { return "0 B/s" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var value = Double(bitsPerSecond) / 8
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        // Whole bytes/sec read oddly with a decimal ("512.0 B/s"); every
        // larger unit keeps one decimal place, matching the spec's own
        // "564.5 KiB/s" example.
        let formattedValue = unitIndex == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(formattedValue) \(units[unitIndex])/s"
    }

    public static func bitRate(bitsPerSecond: Int, locale: Locale = .current) -> String {
        guard bitsPerSecond > 0 else { return "0 kbps" }
        if bitsPerSecond >= 1_000_000 {
            let mbps = Double(bitsPerSecond) / 1_000_000
            return "\(decimal(mbps, locale: locale)) Mbps"
        }
        if bitsPerSecond >= 1_000 {
            return "\(Int((Double(bitsPerSecond) / 1_000).rounded())) kbps"
        }
        return "\(bitsPerSecond) bps"
    }

    /// One decimal place, with the locale's own separator, and no trailing ".0" — "2,3",
    /// but "12" rather than "12,0" once the number is big enough not to need it.
    private static func decimal(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value >= 10 ? 0 : 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    /// `view_count`/`like_count` -> a short abbreviation ("926K", "1.2K", "999") via Foundation's own locale-aware compact notation.
    public static func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}
