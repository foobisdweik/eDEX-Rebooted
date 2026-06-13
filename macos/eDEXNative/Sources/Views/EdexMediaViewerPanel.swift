import AppKit
import AVFoundation
import AVKit
import EdexDomainSupport
import EdexRenderingSupport
import ImageIO
import SwiftUI

/// In-app media viewer modal — image preview plus AVKit audio/video playback with
/// the legacy control bar (play/pause, scrub, time, volume, fullscreen).
struct EdexMediaViewerView: View {
    @Bindable var state: ShellState
    let theme: NativeTheme

    @State private var loadedImage: NSImage?
    @State private var imageLoadFailed = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var lastInteraction = Date()
    @State private var hideControlsLoop: Task<Void, Never>?
    @State private var timeObserverToken: Any?
    @State private var observedPlayer: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            mediaSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsControlBar, controlBarVisible {
                controlBar
                    .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .augmentedSurface(
            style: .panel(vh: 8),
            fill: theme.terminalBackground.opacity(0.7),
            stroke: theme.accent
        )
        .onHover { hovering in
            if hovering { revealControls() }
        }
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
        .task(id: imageLoadKey) {
            await loadImageIfNeeded()
        }
        .onAppear {
            beginPlaybackObservation()
            startHideControlsLoop()
            lastInteraction = Date()
        }
        .onDisappear {
            endPlaybackObservation()
            hideControlsLoop?.cancel()
            hideControlsLoop = nil
        }
        .onChange(of: state.mediaViewerExpanded) { _, expanded in
            if !expanded {
                controlsVisible = true
            }
            lastInteraction = Date()
        }
        .onChange(of: state.mediaViewerPath) { _, _ in
            endPlaybackObservation()
            beginPlaybackObservation()
        }
    }

    @ViewBuilder
    private var mediaSurface: some View {
        switch state.mediaViewerKind {
        case .image:
            imageContent
        case .video:
            ZStack {
                if let player = state.mediaViewerPlayer {
                    EdexAVPlayerSurface(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: state.mediaViewerExpanded ? 320 : 220, maxHeight: .infinity)
        case .audio:
            Spacer(minLength: 0)
        case .none:
            unsupportedText
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let loadedImage {
            Image(nsImage: loadedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if imageLoadFailed {
            unsupportedText
        } else {
            Text("Loading…")
                .font(.custom(theme.fonts.terminal, size: 12))
                .foregroundStyle(theme.terminalForeground.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        }
    }

    private var unsupportedText: some View {
        Text("Unsupported")
            .font(.custom(theme.fonts.terminal, size: 13))
            .foregroundStyle(theme.accent.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
    }

    private var showsControlBar: Bool {
        switch state.mediaViewerKind {
        case .audio, .video: return true
        default: return false
        }
    }

    private var controlBarVisible: Bool {
        !state.mediaViewerExpanded || controlsVisible
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            controlButton(
                named: MediaPlayerSupport.playPauseIconName(isPlaying: isPlaying),
                fallback: isPlaying ? "pause.fill" : "play.fill"
            ) {
                state.toggleMediaPlayback()
                isPlaying = state.mediaViewerIsPlaying
                revealControls()
            }

            MediaProgressBar(
                fraction: MediaPlayerSupport.progressFraction(current: currentTime, duration: effectiveDuration),
                theme: theme
            ) { fraction in
                state.seekMedia(fraction: fraction)
                revealControls()
            }
            .frame(maxWidth: .infinity)

            Text(MediaPlayerSupport.timeHMS(currentTime))
                .font(.custom(theme.fonts.terminal, size: 11))
                .foregroundStyle(theme.terminalForeground.opacity(0.88))
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)

            controlButton(
                named: MediaPlayerSupport.volumeIconName(
                    volume: state.mediaViewerVolume,
                    muted: state.mediaViewerMuted
                ),
                fallback: state.mediaViewerMuted || state.mediaViewerVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
            ) {
                state.toggleMediaMute()
                revealControls()
            }

            MediaVolumeBar(
                volume: state.mediaViewerMuted ? 0 : state.mediaViewerVolume,
                theme: theme
            ) { value in
                state.setMediaVolume(value)
                revealControls()
            }
            .frame(width: 72)

            if state.mediaViewerKind == .video {
                controlButton(
                    named: state.mediaViewerExpanded ? "fullscreen-exit" : "fullscreen",
                    fallback: state.mediaViewerExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                ) {
                    state.toggleMediaExpanded()
                    revealControls()
                }
            }
        }
        .padding(.top, 10)
    }

    private var effectiveDuration: Double {
        let measured = duration > 0 ? duration : state.mediaViewerDuration
        return measured
    }

    @ViewBuilder
    private func controlButton(named: String, fallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let icon = FileIconProvider.shared.controlImage(named: named, theme: theme) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
    }

    /// Hashable key so the image (re)loads when either the path or the expanded
    /// state changes; a tuple can't conform to Equatable for `.task(id:)`.
    private var imageLoadKey: String {
        "\(state.mediaViewerExpanded ? "1" : "0")|\(state.mediaViewerPath ?? "")"
    }

    private func loadImageIfNeeded() async {
        loadedImage = nil
        imageLoadFailed = false
        guard state.mediaViewerKind == .image, let path = state.mediaViewerPath else { return }
        let expanded = state.mediaViewerExpanded
        // NSScreen is AppKit and must be read on the MainActor; capture the
        // scale here and pass it into the detached decode.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = await Task.detached(priority: .userInitiated) {
            Self.loadThumbnail(path: path, expanded: expanded, scale: scale)
        }.value
        guard !Task.isCancelled else { return }
        if let image {
            loadedImage = image
            imageLoadFailed = false
        } else {
            loadedImage = nil
            imageLoadFailed = true
        }
    }

    private nonisolated static func loadThumbnail(path: String, expanded: Bool, scale: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let baseEdge = expanded ? 960.0 : 640.0
        let maxPixel = Int((baseEdge * scale).rounded())
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private func beginPlaybackObservation() {
        endPlaybackObservation()
        guard let player = state.mediaViewerPlayer else { return }
        observedPlayer = player
        refreshDuration(from: player)
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        isPlaying = player.rate > 0
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            currentTime = seconds.isFinite ? max(0, seconds) : 0
            isPlaying = player.rate > 0
            refreshDuration(from: player)
        }
        // No autoplay — the legacy player opened paused, showing the play
        // glyph, for audio and video alike.
    }

    private func endPlaybackObservation() {
        if let player = observedPlayer, let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        observedPlayer = nil
        timeObserverToken = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    private func refreshDuration(from player: AVPlayer) {
        let seconds = player.currentItem?.duration.seconds ?? 0
        if seconds.isFinite, seconds > 0 {
            duration = seconds
        }
    }

    private func revealControls() {
        controlsVisible = true
        lastInteraction = Date()
    }

    private func startHideControlsLoop() {
        guard hideControlsLoop == nil else { return }
        hideControlsLoop = Task {
            while !Task.isCancelled {
                if state.mediaViewerExpanded {
                    let remaining = lastInteraction.addingTimeInterval(2).timeIntervalSinceNow
                    if remaining <= 0 {
                        controlsVisible = false
                        try? await Task.sleep(for: .milliseconds(250))
                    } else {
                        try? await Task.sleep(for: .seconds(remaining))
                    }
                } else {
                    // Collapsed: controls stay visible, so there's nothing to
                    // hide — poll slowly just to notice an expand toggle.
                    controlsVisible = true
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
}

// MARK: - AVPlayer surface

private struct EdexAVPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        context.coordinator.playerToken = ObjectIdentifier(player)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let token = ObjectIdentifier(player)
        guard context.coordinator.playerToken != token else { return }
        context.coordinator.playerToken = token
        nsView.player = player
    }

    final class Coordinator {
        var playerToken: ObjectIdentifier?
    }
}

// MARK: - Scrub + volume bars

private struct MediaProgressBar: View {
    let fraction: Double
    let theme: NativeTheme
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width.isFinite && geo.size.width > 0 ? geo.size.width : 1
            let active = dragFraction ?? fraction
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.accent.opacity(0.18))
                Rectangle()
                    .fill(theme.accent.opacity(0.88))
                    .frame(width: max(0, width * active))
            }
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = scrubFraction(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        let target = scrubFraction(at: value.location.x, width: width)
                        dragFraction = nil
                        onSeek(target)
                    }
            )
        }
        .frame(height: 8)
    }

    private func scrubFraction(at x: CGFloat, width: CGFloat) -> Double {
        let raw = Double(x / width)
        return min(max(raw, 0), 1)
    }
}

private struct MediaVolumeBar: View {
    let volume: Double
    let theme: NativeTheme
    let onChange: (Double) -> Void

    @State private var dragVolume: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width.isFinite && geo.size.width > 0 ? geo.size.width : 1
            let active = dragVolume ?? volume
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.accent.opacity(0.18))
                Rectangle()
                    .fill(theme.accent.opacity(0.88))
                    .frame(width: max(0, width * active))
            }
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragVolume = MediaPlayerSupport.clampVolume(Double(value.location.x / width))
                    }
                    .onEnded { value in
                        let target = MediaPlayerSupport.clampVolume(Double(value.location.x / width))
                        dragVolume = nil
                        onChange(target)
                    }
            )
        }
        .frame(height: 8)
    }
}
