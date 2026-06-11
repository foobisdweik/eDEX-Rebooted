import Foundation

public enum EdexAudioCue: String, CaseIterable, Sendable {
    case stdout
    case stdin
    case folder
    case granted
    case keyboard
    case theme
    case expand
    case panels
    case scan
    case denied
    case info
    case alarm
    case error

    public var assetName: String {
        "\(rawValue).wav"
    }

    public var isFeedbackCue: Bool {
        switch self {
        case .stdout, .stdin, .folder, .granted:
            true
        case .keyboard, .theme, .expand, .panels, .scan, .denied, .info, .alarm, .error:
            false
        }
    }

    public var cueGain: Double {
        switch self {
        case .stdout, .stdin:
            0.4
        case .folder, .granted, .keyboard, .theme, .expand, .panels, .scan, .denied, .info, .alarm, .error:
            1.0
        }
    }
}

public struct EdexAudioSettings: Decodable, Equatable, Sendable {
    public var audio: Bool
    public var audioVolume: Double
    public var disableFeedbackAudio: Bool

    public init(audio: Bool = true, audioVolume: Double = 1.0, disableFeedbackAudio: Bool = false) {
        self.audio = audio
        self.audioVolume = Self.safeVolume(audioVolume)
        self.disableFeedbackAudio = disableFeedbackAudio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            audio: try container.decodeIfPresent(Bool.self, forKey: .audio) ?? true,
            audioVolume: try container.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 1.0,
            disableFeedbackAudio: try container.decodeIfPresent(Bool.self, forKey: .disableFeedbackAudio) ?? false
        )
    }

    private enum CodingKeys: String, CodingKey {
        case audio
        case audioVolume
        case disableFeedbackAudio
    }

    private static func safeVolume(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return min(max(value, 0.0), 1.0)
    }
}

public struct EdexAudioCatalog: Sendable {
    public let settings: EdexAudioSettings

    public init(settings: EdexAudioSettings = EdexAudioSettings()) {
        self.settings = settings
    }

    public func shouldLoad(_ cue: EdexAudioCue) -> Bool {
        guard settings.audio else { return false }
        if settings.disableFeedbackAudio && cue.isFeedbackCue {
            return false
        }
        return true
    }

    public func effectiveVolume(for cue: EdexAudioCue) -> Double {
        guard shouldLoad(cue) else { return 0.0 }
        return settings.audioVolume * cue.cueGain
    }

    public func updatePlan(existing: Set<EdexAudioCue>) -> EdexAudioUpdatePlan {
        var load = Set<EdexAudioCue>()
        var update = Set<EdexAudioCue>()
        var remove = Set<EdexAudioCue>()

        for cue in EdexAudioCue.allCases {
            if shouldLoad(cue) {
                if existing.contains(cue) {
                    update.insert(cue)
                } else {
                    load.insert(cue)
                }
            } else if existing.contains(cue) {
                remove.insert(cue)
            }
        }

        return EdexAudioUpdatePlan(load: load, update: update, remove: remove)
    }
}

public struct EdexAudioUpdatePlan: Equatable, Sendable {
    public var load: Set<EdexAudioCue>
    public var update: Set<EdexAudioCue>
    public var remove: Set<EdexAudioCue>
}

public enum EdexAudioVoicePolicy {
    public static func voiceCount(for cue: EdexAudioCue) -> Int {
        switch cue {
        case .stdin, .keyboard:
            4
        case .stdout, .folder, .granted, .theme, .expand, .panels, .scan, .denied, .info, .alarm, .error:
            1
        }
    }
}

public struct EdexAudioAssetResolver: Sendable {
    public let assetDirectory: URL

    public init(assetDirectory: URL) {
        self.assetDirectory = assetDirectory
    }

    public func url(for cue: EdexAudioCue) -> URL? {
        let url = assetDirectory.appendingPathComponent(cue.assetName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
