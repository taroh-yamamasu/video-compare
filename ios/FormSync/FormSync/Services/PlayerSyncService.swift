import AVFoundation
import Foundation

@MainActor
final class PlayerSyncService {
    let leftPlayer: AVPlayer
    let rightPlayer: AVPlayer

    var onPlaybackEnded: (() -> Void)?
    var onTimelineTick: ((Double) -> Void)?
    var onActualTimeTick: ((VideoSide, Double) -> Void)?

    private let leftDurationSeconds: Double
    private let rightDurationSeconds: Double
    private var endObservers: [NSObjectProtocol] = []
    private var timeObservers: [(AVPlayer, Any)] = []
    private var playbackRate: PlaybackRate = .normal
    private var syncSettings = SyncSettings()
    private var loopRange = LoopRange()
    private var isLoopSeeking = false
    private var isDriftCorrecting = false

    init(
        leftURL: URL,
        rightURL: URL,
        leftDurationSeconds: Double,
        rightDurationSeconds: Double
    ) {
        self.leftPlayer = AVPlayer(url: leftURL)
        self.rightPlayer = AVPlayer(url: rightURL)
        self.leftDurationSeconds = leftDurationSeconds
        self.rightDurationSeconds = rightDurationSeconds

        leftPlayer.actionAtItemEnd = .pause
        rightPlayer.actionAtItemEnd = .pause

        observePlaybackEnd(for: leftPlayer)
        observePlaybackEnd(for: rightPlayer)
        observeTimeline(for: .left, player: leftPlayer)
        observeTimeline(for: .right, player: rightPlayer)
    }

    deinit {
        for observer in endObservers {
            NotificationCenter.default.removeObserver(observer)
        }

        for (player, observer) in timeObservers {
            player.removeTimeObserver(observer)
        }
    }

    func play(rate: PlaybackRate) {
        playbackRate = rate
        leftPlayer.playImmediately(atRate: rate.rawValue)
        rightPlayer.playImmediately(atRate: rate.rawValue)
    }

    func pause() {
        leftPlayer.pause()
        rightPlayer.pause()
    }

    func player(for side: VideoSide) -> AVPlayer {
        side == .left ? leftPlayer : rightPlayer
    }

    func play(side: VideoSide, rate: PlaybackRate) {
        playbackRate = rate
        player(for: side).playImmediately(atRate: rate.rawValue)
    }

    func pause(side: VideoSide) {
        player(for: side).pause()
    }

    func seek(timelineSeconds: Double, syncSettings: SyncSettings, toleranceSeconds: Double = 0) async {
        self.syncSettings = syncSettings

        let leftActual = clamp(
            timelineSeconds - syncSettings.leftOffsetSeconds,
            lower: 0,
            upper: leftDurationSeconds
        )
        let rightActual = clamp(
            timelineSeconds - syncSettings.rightOffsetSeconds,
            lower: 0,
            upper: rightDurationSeconds
        )

        async let leftSeek: Void = seek(leftPlayer, to: leftActual, toleranceSeconds: toleranceSeconds)
        async let rightSeek: Void = seek(rightPlayer, to: rightActual, toleranceSeconds: toleranceSeconds)
        _ = await (leftSeek, rightSeek)
    }

    func seek(side: VideoSide, to actualSeconds: Double, toleranceSeconds: Double = 0) async {
        let duration = side == .left ? leftDurationSeconds : rightDurationSeconds
        await seek(
            player(for: side),
            to: clamp(actualSeconds, lower: 0, upper: duration),
            toleranceSeconds: toleranceSeconds
        )
    }

    func seek(
        leftActualSeconds: Double,
        rightActualSeconds: Double,
        toleranceSeconds: Double = 0
    ) async {
        async let leftSeek: Void = seek(
            leftPlayer,
            to: clamp(leftActualSeconds, lower: 0, upper: leftDurationSeconds),
            toleranceSeconds: toleranceSeconds
        )
        async let rightSeek: Void = seek(
            rightPlayer,
            to: clamp(rightActualSeconds, lower: 0, upper: rightDurationSeconds),
            toleranceSeconds: toleranceSeconds
        )
        _ = await (leftSeek, rightSeek)
    }

    func cancelPendingSeeks() {
        leftPlayer.currentItem?.cancelPendingSeeks()
        rightPlayer.currentItem?.cancelPendingSeeks()
    }

    func cancelPendingSeeks(for side: VideoSide) {
        player(for: side).currentItem?.cancelPendingSeeks()
    }

    func setPlaybackRate(_ rate: PlaybackRate) {
        playbackRate = rate

        if leftPlayer.rate != 0 {
            leftPlayer.rate = rate.rawValue
        }

        if rightPlayer.rate != 0 {
            rightPlayer.rate = rate.rawValue
        }
    }

    func updateLoopRange(_ loopRange: LoopRange) {
        self.loopRange = loopRange
    }

    func clearLoopRange() {
        loopRange = LoopRange()
    }

    func releasePlayers() {
        pause()
        cancelPendingSeeks()
        leftPlayer.replaceCurrentItem(with: nil)
        rightPlayer.replaceCurrentItem(with: nil)
    }

    func updateSyncSettings(_ syncSettings: SyncSettings) {
        self.syncSettings = syncSettings
    }

    func currentTimelineSeconds() -> Double {
        let leftActual = leftPlayer.currentTime().seconds
        guard leftActual.isFinite else {
            return 0
        }

        return leftActual + syncSettings.leftOffsetSeconds
    }

    private func observePlaybackEnd(for player: AVPlayer) {
        guard let item = player.currentItem else {
            return
        }

        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if self.loopRange.isEnabled, self.loopRange.isComplete, let start = self.loopRange.startSeconds {
                    await self.seek(timelineSeconds: start, syncSettings: self.syncSettings)
                    self.play(rate: self.playbackRate)
                } else {
                    self.pause()
                    self.onPlaybackEnded?()
                }
            }
        }

        endObservers.append(observer)
    }

    private func observeTimeline(for side: VideoSide, player: AVPlayer) {
        let observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.handleTimelineTick(side: side, actualSeconds: time.seconds)
            }
        }
        timeObservers.append((player, observer))
    }

    private func handleTimelineTick(side: VideoSide, actualSeconds: Double) {
        guard actualSeconds.isFinite else {
            return
        }

        onActualTimeTick?(side, actualSeconds)

        guard side == .left else {
            return
        }

        let timelineSeconds = actualSeconds + syncSettings.leftOffsetSeconds

        if
            loopRange.isEnabled,
            loopRange.isComplete,
            let start = loopRange.startSeconds,
            let end = loopRange.endSeconds,
            timelineSeconds >= end,
            !isLoopSeeking
        {
            isLoopSeeking = true
            Task { @MainActor in
                let wasPlaying = self.leftPlayer.rate != 0 || self.rightPlayer.rate != 0
                await self.seek(timelineSeconds: start, syncSettings: self.syncSettings)
                self.onTimelineTick?(start)
                if wasPlaying {
                    self.play(rate: self.playbackRate)
                }
                self.isLoopSeeking = false
            }
            return
        }

        let desiredRightActual = clamp(
            timelineSeconds - syncSettings.rightOffsetSeconds,
            lower: 0,
            upper: rightDurationSeconds
        )
        let currentRightActual = rightPlayer.currentTime().seconds
        if
            currentRightActual.isFinite,
            rightPlayer.rate != 0,
            abs(currentRightActual - desiredRightActual) > 0.09,
            !isDriftCorrecting
        {
            isDriftCorrecting = true
            Task { @MainActor in
                await self.seek(self.rightPlayer, to: desiredRightActual, toleranceSeconds: 0.03)
                if self.leftPlayer.rate != 0 {
                    self.rightPlayer.rate = self.playbackRate.rawValue
                }
                self.isDriftCorrecting = false
            }
        }

        onTimelineTick?(timelineSeconds)
    }

    private func seek(_ player: AVPlayer, to seconds: Double, toleranceSeconds: Double = 0) async {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let tolerance = CMTime(seconds: max(0, toleranceSeconds), preferredTimescale: 600)
        await withCheckedContinuation { continuation in
            player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
                continuation.resume()
            }
        }
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
