import AVFoundation
import EdexDomainSupport
import Foundation

@MainActor
final class EdexAudioService {
    private let assetDirectory: URL
    private var players: [EdexAudioCue: AVAudioPlayer] = [:]
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
        }

        for cue in plan.update {
            players[cue]?.volume = Float(catalog.effectiveVolume(for: cue))
        }

        for cue in plan.load {
            guard let url = resolver.url(for: cue) else { continue }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = Float(catalog.effectiveVolume(for: cue))
                player.prepareToPlay()
                players[cue] = player
            } catch {
                // Match the legacy proxy behavior: unavailable sounds are no-ops.
                continue
            }
        }
    }

    @discardableResult
    func play(_ cue: EdexAudioCue) -> Bool {
        guard let player = players[cue] else { return false }
        player.currentTime = 0
        return player.play()
    }

    nonisolated private static func defaultAssetDirectory() -> URL {
        if let bundleURL = Bundle.main.url(forResource: "stdout", withExtension: "wav", subdirectory: "audio") {
            return bundleURL.deletingLastPathComponent()
        }

        // SwiftPM dev runs execute from `.build`; use the repository audio assets
        // until packaging moves these files into the native app bundle.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // eDEXNative
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("src/assets/audio", isDirectory: true)
    }
}
