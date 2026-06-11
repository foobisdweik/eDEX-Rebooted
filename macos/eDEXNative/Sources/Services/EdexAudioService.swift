import AVFoundation
import EdexDomainSupport
import Foundation

@MainActor
final class EdexAudioService {
    private let assetDirectory: URL
    private var players: [EdexAudioCue: [AVAudioPlayer]] = [:]
    private var nextVoiceIndex: [EdexAudioCue: Int] = [:]
    private var catalog = EdexAudioCatalog()

    init(assetDirectory: URL = EdexAudioService.defaultAssetDirectory()) {
        self.assetDirectory = assetDirectory
    }

    func configure(settings: EdexAudioSettings) {
        catalog = EdexAudioCatalog(settings: settings)
        let resolver = EdexAudioAssetResolver(assetDirectory: assetDirectory)
        let plan = catalog.updatePlan(existing: Set(players.keys))

        for cue in plan.remove {
            players[cue] = nil
            nextVoiceIndex[cue] = nil
        }

        for cue in plan.update {
            players[cue]?.forEach { player in
                player.volume = Float(catalog.effectiveVolume(for: cue))
            }
        }

        for cue in plan.load {
            guard let url = resolver.url(for: cue) else { continue }
            do {
                let voices = try (0..<EdexAudioVoicePolicy.voiceCount(for: cue)).map { _ in
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.volume = Float(catalog.effectiveVolume(for: cue))
                    player.prepareToPlay()
                    return player
                }
                players[cue] = voices
                nextVoiceIndex[cue] = 0
            } catch {
                // Match the legacy proxy behavior: unavailable sounds are no-ops.
                continue
            }
        }
    }

    @discardableResult
    func play(_ cue: EdexAudioCue) -> Bool {
        guard let voices = players[cue], !voices.isEmpty else { return false }
        let index = nextVoiceIndex[cue, default: 0] % voices.count
        let player = voices[index]
        nextVoiceIndex[cue] = (index + 1) % voices.count
        player.currentTime = 0
        return player.play()
    }

    nonisolated private static func defaultAssetDirectory() -> URL {
        if let bundleURL = Bundle.main.url(forResource: "stdout", withExtension: "wav", subdirectory: "audio") {
            return bundleURL.deletingLastPathComponent()
        }

        // SwiftPM dev runs execute from `.build`; use the repository audio assets
        // until packaging moves these files into the native app bundle.
        return EdexBundledAssets.audioDirectory(from: #filePath)
    }
}
