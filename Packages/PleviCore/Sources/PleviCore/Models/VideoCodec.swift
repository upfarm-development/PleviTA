
import Foundation

public enum VideoCodec: String, CaseIterable, Codable, Sendable {
    case h264, h265, vp9, av1

    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .h265: "H.265 (HEVC)"
        case .vp9: "VP9"
        case .av1: "AV1"
        }
    }

    /// Reads the codec name Tube Archivist reports for a stream: ffprobe's short names (`h264`,
    /// `hevc`, `vp9`, `av1`) or the four-character tags that appear in a codec string (`avc1`,
    /// `hev1`, `vp09`, `av01`). Nil for anything else, which is then never treated as one of these.
    public init?(streamCodec: String) {
        let name = streamCodec.lowercased()
        switch true {
        case name.hasPrefix("h264"), name.hasPrefix("avc"): self = .h264
        case name.hasPrefix("hevc"), name.hasPrefix("h265"), name.hasPrefix("hev1"), name.hasPrefix("hvc1"): self = .h265
        case name.hasPrefix("vp9"), name.hasPrefix("vp09"): self = .vp9
        case name.hasPrefix("av1"), name.hasPrefix("av01"): self = .av1
        default: return nil
        }
    }
}

extension VideoCodec {
    /// "AV1", "H.264 or AV1", "H.264, VP9 or AV1".
    public static func list(_ codecs: [VideoCodec]) -> String {
        let names = codecs.map(\.displayName)
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " or " + last
    }
}

extension Video {
    /// The codec of the file's video stream, when the server said and it is one of the known ones.
    public var videoCodec: VideoCodec? {
        streams?.first { $0.type == "video" }?.codec.flatMap(VideoCodec.init(streamCodec:))
    }
}
