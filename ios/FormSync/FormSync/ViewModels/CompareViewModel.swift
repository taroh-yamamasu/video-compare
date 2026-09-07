import AVFoundation
import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class CompareViewModel: ObservableObject {
    @Published var playbackState = PlaybackState()
    @Published var settings: CompareSettings
    @Published var overlaySettings = OverlaySettings()
    @Published var compareMode: CompareMode = .setup
    @Published var errorMessage: String?
    @Published var isExporting = false
    @Published var exportProgress = ExportProgress.idle
    @Published var isLoadingReplacement = false
    @Published var toastMessage: String?
    @Published private(set) var hasMeaningfulComparisonActivity = false
    @Published private(set) var hasExportFailure = false
    @Published private(set) var leftSlot: VideoSlotState
    @Published private(set) var rightSlot: VideoSlotState
    @Published private(set) var playerSyncService: PlayerSyncService

    private var settingsStore: SettingsStore
    private let videoPickerService: VideoPickerService
    private let exportService: ExportService
    private let sessionStore: CompareSessionStore
    private var session: CompareSession?
    private let ownsTemporaryVideos: Bool
    let isSample: Bool
    private var scrubSeekTask: Task<Void, Never>?
    private var pendingScrubTimelineSeconds: Double?
    private var shouldResumeAfterScrub = false
    private var slotScrubSeekTasks: [VideoSide: Task<Void, Never>] = [:]
    private var pendingSlotScrubSeconds: [VideoSide: Double] = [:]
    private var shouldResumeSlotAfterScrub: [VideoSide: Bool] = [:]
    private var sessionSaveTask: Task<Void, Never>?

    init(
        leftVideo: VideoItem,
        rightVideo: VideoItem,
        session: CompareSession? = nil,
        ownsTemporaryVideos: Bool = true,
        isSample: Bool = false,
        settingsStore: SettingsStore = SettingsStore(),
        videoPickerService: VideoPickerService = VideoPickerService(),
        exportService: ExportService = ExportService(),
        sessionStore: CompareSessionStore = CompareSessionStore()
    ) {
        if let session {
            self.leftSlot = Self.makeSlot(side: .left, video: leftVideo, sessionSlot: session.leftSlot)
            self.rightSlot = Self.makeSlot(side: .right, video: rightVideo, sessionSlot: session.rightSlot)
            self.settings = session.settings
            self.overlaySettings = session.overlaySettings
            self.compareMode = session.compareMode
        } else {
            self.leftSlot = VideoSlotState(side: .left, video: leftVideo)
            self.rightSlot = VideoSlotState(side: .right, video: rightVideo)

            var initialSettings = CompareSettings()
            initialSettings.playbackRate = settingsStore.lastPlaybackRate
            initialSettings.displayMode = settingsStore.lastDisplayMode
            self.settings = initialSettings
        }

        self.session = session
        self.ownsTemporaryVideos = ownsTemporaryVideos
        self.isSample = isSample
        self.settingsStore = settingsStore
        self.videoPickerService = videoPickerService
        self.exportService = exportService
        self.sessionStore = sessionStore
        self.playerSyncService = Self.makePlayerSyncService(leftVideo: leftVideo, rightVideo: rightVideo)

        playbackState.playbackRate = settings.playbackRate.rawValue
        recalculateTimelineBounds()
        if compareMode == .synced, !(leftSlot.hasSyncPoint && rightSlot.hasSyncPoint) {
            compareMode = .setup
        }
        if let session {
            playbackState.timelineSeconds = clampedTimeline(session.timelineSeconds)
            updateSlotTimes(forTimeline: playbackState.timelineSeconds)
        }
        configurePlayerSyncService()
        restorePlayerPositions()
    }

    deinit {
        MainActor.assumeIsolated {
            scrubSeekTask?.cancel()
            slotScrubSeekTasks.values.forEach { $0.cancel() }
            sessionSaveTask?.cancel()
            playerSyncService.releasePlayers()
            if ownsTemporaryVideos {
                TemporaryFileCleanup.removeTemporaryVideos([leftSlot.video, rightSlot.video])
            }
        }
    }

    var canStartSyncedCompare: Bool {
        leftSlot.hasSyncPoint && rightSlot.hasSyncPoint
    }

    var videoPairIdentity: String {
        [leftSlot.video.id.uuidString, rightSlot.video.id.uuidString]
            .sorted()
            .joined(separator: ":")
    }

    var isSyncedCompareActive: Bool {
        compareMode == .synced
    }

    var normalizedDisplayTime: Double {
        playbackState.timelineSeconds - playbackState.timelineLowerBound
    }

    var canExportLoopRange: Bool {
        settings.loopRange.isEnabled
            && settings.loopRange.isComplete
            && loopValidationError(for: settings.loopRange) == nil
    }

    func player(for side: VideoSide) -> AVPlayer {
        playerSyncService.player(for: side)
    }

    func slot(for side: VideoSide) -> VideoSlotState {
        side == .left ? leftSlot : rightSlot
    }

    func replaceVideo(on side: VideoSide, with item: PhotosPickerItem) async {
        pause()
        compareMode = .setup
        isLoadingReplacement = true
        errorMessage = nil
        toastMessage = nil
        let previousVideo = slot(for: side).video
        var loadedReplacementVideo: VideoItem?

        do {
            let pickedVideo = try await videoPickerService.loadVideo(from: item)
            loadedReplacementVideo = pickedVideo
            let video: VideoItem
            if let session {
                video = try sessionStore.copyVideoToSession(
                    pickedVideo,
                    sessionID: session.id,
                    side: side,
                    replacing: previousVideo.url.lastPathComponent
                )
                TemporaryFileCleanup.removeIfTemporary(pickedVideo.url)
                loadedReplacementVideo = nil
            } else {
                video = pickedVideo
            }

            if side == .left {
                leftSlot = VideoSlotState(side: .left, video: video)
            } else {
                rightSlot = VideoSlotState(side: .right, video: video)
            }

            recreatePlayerSyncService()
            recalculateTimelineBounds()
            playbackState.timelineSeconds = 0
            if ownsTemporaryVideos {
                TemporaryFileCleanup.removeIfTemporary(previousVideo.url)
            }
            persistSession()
            toastMessage = L10n.format("Replaced %@.", slot(for: side).label)
        } catch let error as AppError {
            if let loadedReplacementVideo {
                TemporaryFileCleanup.removeIfTemporary(loadedReplacementVideo.url)
            }
            errorMessage = error.errorDescription
        } catch {
            if let loadedReplacementVideo {
                TemporaryFileCleanup.removeIfTemporary(loadedReplacementVideo.url)
            }
            errorMessage = AppError.videoLoadFailed.errorDescription
        }

        isLoadingReplacement = false
    }

    func clearMessage() {
        errorMessage = nil
        toastMessage = nil
    }

    func toggleSlotPlayback(_ side: VideoSide) {
        let slot = slot(for: side)
        if slot.isPlaying {
            playerSyncService.pause(side: side)
            setSlot(side, isPlaying: false)
        } else {
            playerSyncService.play(side: side, rate: settings.playbackRate)
            setSlot(side, isPlaying: true)
        }
    }

    func seekSlot(_ side: VideoSide, to actualSeconds: Double) async {
        let clamped = clampedActualTime(actualSeconds, for: side)
        await playerSyncService.seek(side: side, to: clamped)
        setSlot(side, currentTimeSeconds: clamped)

        if compareMode == .synced, canStartSyncedCompare {
            await seekNormalized(to: clamped - slot(for: side).syncPointSeconds)
        }
    }

    func beginSlotScrubbing(_ side: VideoSide) {
        shouldResumeSlotAfterScrub[side] = slot(for: side).isPlaying
        playerSyncService.pause(side: side)
        playerSyncService.cancelPendingSeeks(for: side)
        setSlot(side, isPlaying: false)
    }

    func scrubSlot(_ side: VideoSide, to actualSeconds: Double) {
        let clamped = clampedActualTime(actualSeconds, for: side)
        setSlot(side, currentTimeSeconds: clamped)
        pendingSlotScrubSeconds[side] = clamped
        startSlotScrubSeekLoopIfNeeded(for: side)
    }

    func endSlotScrubbing(_ side: VideoSide) async {
        slotScrubSeekTasks[side]?.cancel()
        slotScrubSeekTasks[side] = nil
        pendingSlotScrubSeconds[side] = nil
        playerSyncService.cancelPendingSeeks(for: side)

        let target = slot(for: side).currentTimeSeconds
        await playerSyncService.seek(side: side, to: target)
        setSlot(side, currentTimeSeconds: target)

        if shouldResumeSlotAfterScrub[side] == true {
            playerSyncService.play(side: side, rate: settings.playbackRate)
            setSlot(side, isPlaying: true)
        }

        shouldResumeSlotAfterScrub[side] = nil
    }

    func stepSlot(_ side: VideoSide, direction: Int) async {
        playerSyncService.pause(side: side)
        setSlot(side, isPlaying: false)

        let playerTime = player(for: side).currentTime().seconds
        let currentTime = playerTime.isFinite ? playerTime : slot(for: side).currentTimeSeconds
        let nextTime = currentTime + Double(direction) * settings.stepSeconds
        await seekSlot(side, to: nextTime)
    }

    func setSyncPoint(_ side: VideoSide) {
        playerSyncService.pause(side: side)
        setSlot(side, isPlaying: false)
        let playerTime = player(for: side).currentTime().seconds
        let currentTime = playerTime.isFinite ? playerTime : slot(for: side).currentTimeSeconds

        if side == .left {
            leftSlot.syncPointSeconds = clampedActualTime(currentTime, for: .left)
            leftSlot.hasSyncPoint = true
        } else {
            rightSlot.syncPointSeconds = clampedActualTime(currentTime, for: .right)
            rightSlot.hasSyncPoint = true
        }

        recalculateTimelineBounds()
        playbackState.timelineSeconds = 0
        if leftSlot.hasSyncPoint && rightSlot.hasSyncPoint {
            seekToSyncPointPreview()
        } else {
            setSlot(side, currentTimeSeconds: slot(for: side).syncPointSeconds)
        }
        toastMessage = L10n.format("Set the reference point for %@.", slot(for: side).label)
        errorMessage = nil
        persistSession()
    }

    func clearSyncPoint(_ side: VideoSide) {
        playerSyncService.pause(side: side)
        setSlot(side, isPlaying: false)

        if side == .left {
            leftSlot.hasSyncPoint = false
            leftSlot.syncPointSeconds = 0
        } else {
            rightSlot.hasSyncPoint = false
            rightSlot.syncPointSeconds = 0
        }

        recalculateTimelineBounds()
        playbackState.timelineSeconds = 0
        toastMessage = nil
        errorMessage = nil
        persistSession()
    }

    func startSyncedCompare() async {
        guard canStartSyncedCompare else {
            errorMessage = String(localized: "Set a reference point in each video.")
            return
        }

        pause()
        compareMode = .synced
        recalculateTimelineBounds()
        playbackState.timelineSeconds = playbackState.timelineLowerBound
        await seekNormalized(to: playbackState.timelineSeconds)
        toastMessage = String(localized: "Comparison started.")
        errorMessage = nil
        persistSession()
    }

    func exitSyncedCompare() {
        pause()
        compareMode = .setup
        seekToSyncPointPreview()
        toastMessage = String(localized: "Returned to reference point setup.")
        persistSession()
    }

    func togglePlayback() async {
        guard compareMode == .synced else {
            return
        }

        if playbackState.isPlaying {
            pause()
            return
        }

        await playSynced()
    }

    func pause() {
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        pendingScrubTimelineSeconds = nil
        slotScrubSeekTasks.values.forEach { $0.cancel() }
        slotScrubSeekTasks.removeAll()
        pendingSlotScrubSeconds.removeAll()
        shouldResumeSlotAfterScrub.removeAll()
        playerSyncService.cancelPendingSeeks()
        playerSyncService.pause()
        playbackState.isPlaying = false
        leftSlot.isPlaying = false
        rightSlot.isPlaying = false
    }

    func beginScrubbing() {
        shouldResumeAfterScrub = playbackState.isPlaying
        pause()
    }

    func scrub(to timelineSeconds: Double) {
        let clampedSeconds = clampedTimeline(timelineSeconds)
        playbackState.timelineSeconds = clampedSeconds
        updateSlotTimes(forTimeline: clampedSeconds)

        pendingScrubTimelineSeconds = clampedSeconds
        startScrubSeekLoopIfNeeded()
    }

    func endScrubbing() async {
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        pendingScrubTimelineSeconds = nil
        playerSyncService.cancelPendingSeeks()
        await seekNormalized(to: playbackState.timelineSeconds)

        if shouldResumeAfterScrub {
            playerSyncService.play(rate: settings.playbackRate)
            playbackState.isPlaying = true
            leftSlot.isPlaying = true
            rightSlot.isPlaying = true
        }

        shouldResumeAfterScrub = false
    }

    func stepTimeline(_ direction: Int) async {
        let delta = Double(direction) * settings.stepSeconds
        await seekNormalized(to: playbackState.timelineSeconds + delta)
    }

    func setStepSeconds(_ seconds: Double) {
        settings.stepSeconds = min(max(seconds, 0.001), 1)
        persistSession()
    }

    func swapVideos() async {
        let wasPlaying = playbackState.isPlaying
        pause()

        let previousLeft = leftSlot
        leftSlot = VideoSlotState(
            side: .left,
            video: rightSlot.video,
            currentTimeSeconds: rightSlot.currentTimeSeconds,
            syncPointSeconds: rightSlot.syncPointSeconds,
            hasSyncPoint: rightSlot.hasSyncPoint,
            viewScale: rightSlot.viewScale,
            viewOffsetX: rightSlot.viewOffsetX,
            viewOffsetY: rightSlot.viewOffsetY
        )
        rightSlot = VideoSlotState(
            side: .right,
            video: previousLeft.video,
            currentTimeSeconds: previousLeft.currentTimeSeconds,
            syncPointSeconds: previousLeft.syncPointSeconds,
            hasSyncPoint: previousLeft.hasSyncPoint,
            viewScale: previousLeft.viewScale,
            viewOffsetX: previousLeft.viewOffsetX,
            viewOffsetY: previousLeft.viewOffsetY
        )

        recreatePlayerSyncService()
        recalculateTimelineBounds()
        await seekNormalized(to: playbackState.timelineSeconds)
        toastMessage = String(localized: "The videos were swapped.")
        persistSession()

        if wasPlaying, compareMode == .synced {
            playerSyncService.play(rate: settings.playbackRate)
            playbackState.isPlaying = true
            leftSlot.isPlaying = true
            rightSlot.isPlaying = true
        }
    }

    func setPlaybackRate(_ rate: PlaybackRate) {
        settings.playbackRate = rate
        playbackState.playbackRate = rate.rawValue
        settingsStore.lastPlaybackRate = rate
        playerSyncService.setPlaybackRate(rate)
        errorMessage = nil
        persistSession()
    }

    func setDisplayMode(_ mode: DisplayMode) {
        guard settings.displayMode != mode else {
            return
        }

        let wasPlaying = playbackState.isPlaying
        if compareMode == .synced {
            pause()
        }

        if compareMode == .synced, mode == .overlayPreview {
            let syncPointTimeline = clampedTimeline(0)
            playbackState.timelineSeconds = syncPointTimeline
            settings.displayMode = mode
            settingsStore.lastDisplayMode = mode
            toastMessage = nil
            persistSession()

            Task { @MainActor in
                await seekNormalized(to: syncPointTimeline)
            }
            return
        }

        settings.displayMode = mode
        settingsStore.lastDisplayMode = mode
        persistSession()

        guard compareMode == .synced else {
            return
        }

        Task { @MainActor in
            await seekNormalized(to: playbackState.timelineSeconds)
            if wasPlaying {
                await playSynced()
            }
        }
    }

    func markLoopStart() {
        settings.loopRange.startSeconds = clampedTimeline(playbackState.timelineSeconds)
        if let end = settings.loopRange.endSeconds, end <= settings.loopRange.startSeconds ?? 0 {
            settings.loopRange.isEnabled = false
        }
        playerSyncService.updateLoopRange(settings.loopRange)
        toastMessage = String(localized: "Loop start set.")
        errorMessage = nil
        persistSession()
    }

    func markLoopEnd() {
        settings.loopRange.endSeconds = clampedTimeline(playbackState.timelineSeconds)
        if let start = settings.loopRange.startSeconds, settings.loopRange.endSeconds ?? 0 <= start {
            settings.loopRange.isEnabled = false
            errorMessage = AppError.invalidLoopRange.errorDescription
        } else {
            toastMessage = String(localized: "Loop end set.")
            errorMessage = nil
        }
        playerSyncService.updateLoopRange(settings.loopRange)
        persistSession()
    }

    func toggleLoop() {
        if settings.loopRange.isEnabled {
            settings.loopRange.isEnabled = false
            playerSyncService.updateLoopRange(settings.loopRange)
            toastMessage = String(localized: "Loop turned off.")
            persistSession()
            return
        }

        let nextLoopRange = loopRangeForActivation()
        if let validationError = loopValidationError(for: nextLoopRange) {
            errorMessage = validationError.errorDescription
            settings.loopRange.isEnabled = false
            playerSyncService.updateLoopRange(settings.loopRange)
            persistSession()
            return
        }

        settings.loopRange = nextLoopRange
        settings.loopRange.isEnabled = true
        playerSyncService.updateLoopRange(settings.loopRange)
        if nextLoopRange.startSeconds == playbackState.timelineLowerBound,
           nextLoopRange.endSeconds == playbackState.timelineUpperBound {
            toastMessage = String(localized: "Full timeline loop turned on.")
        } else {
            toastMessage = String(localized: "Loop turned on.")
        }
        errorMessage = nil
        persistSession()
    }

    func clearLoop() {
        settings.loopRange = LoopRange()
        playerSyncService.clearLoopRange()
        toastMessage = String(localized: "Loop cleared.")
        errorMessage = nil
        persistSession()
    }

    func updateViewScale(_ side: VideoSide, delta: Double) {
        var slot = slot(for: side)
        slot.viewScale = clampedViewScale(slot.viewScale + delta)
        if slot.viewScale <= 1 {
            slot.viewOffsetX = 0
            slot.viewOffsetY = 0
        }
        setSlot(slot)
        scheduleSessionPersistence()
    }

    func setViewScale(_ side: VideoSide, scale: Double) {
        var slot = slot(for: side)
        slot.viewScale = clampedViewScale(scale)
        if slot.viewScale <= 1 {
            slot.viewOffsetX = 0
            slot.viewOffsetY = 0
        }
        setSlot(slot)
        scheduleSessionPersistence()
    }

    func resetViewTransform(_ side: VideoSide) {
        var slot = slot(for: side)
        slot.viewScale = 1
        slot.viewOffsetX = 0
        slot.viewOffsetY = 0
        setSlot(slot)
        persistSession()
    }

    func panView(_ side: VideoSide, translation: CGSize) {
        var slot = slot(for: side)
        guard slot.viewScale > 1 else {
            return
        }

        slot.viewOffsetX += translation.width
        slot.viewOffsetY += translation.height
        setSlot(slot)
        scheduleSessionPersistence()
    }

    func updateOverlayEditingSide(_ side: VideoSide) {
        overlaySettings.editingSide = side
        persistSession()
    }

    func nudgeOverlayPosition(x: Double = 0, y: Double = 0) {
        updateOverlayTransform {
            $0.translateX += x
            $0.translateY += y
        }
    }

    func nudgeOverlayScale(_ delta: Double) {
        updateOverlayTransform {
            $0.scale += delta
        }
    }

    func nudgeOverlayRotation(_ deltaDegrees: Double) {
        updateOverlayTransform {
            $0.rotationDegrees += deltaDegrees
        }
    }

    func updateOverlayTransform(_ patch: (inout OverlayTransform) -> Void) {
        var transform = overlaySettings.transform(for: overlaySettings.editingSide)
        patch(&transform)
        transform.opacity = min(max(transform.opacity, 0), 1)
        transform.scale = min(max(transform.scale, 0.5), 2)
        transform.translateX = min(max(transform.translateX, -240), 240)
        transform.translateY = min(max(transform.translateY, -240), 240)
        transform.rotationDegrees = normalizedRotationDegrees(transform.rotationDegrees)
        overlaySettings.setTransform(transform, for: overlaySettings.editingSide)
        scheduleSessionPersistence()
    }

    func exportToPhotoLibrary(options: ExportOptions) async {
        do {
            _ = try await withExportSession(options: options) { request in
                let result = try await makeExportResult(for: request)
                exportProgress = ExportProgress(fraction: 1, message: String(localized: "Saving to Photos…"))
                try Task.checkCancellation()
                try await exportService.saveToPhotoLibrary(result)
                try? FileManager.default.removeItem(at: result.url)
                return result
            }
            toastMessage = String(localized: "Saved to Photos.")
            errorMessage = nil
        } catch {
            handleExportError(error)
        }
    }

    func exportForSharing(options: ExportOptions) async -> ExportResult? {
        do {
            let result = try await withExportSession(options: options) { request in
                try await makeExportResult(for: request)
            }
            toastMessage = String(localized: "Export complete.")
            errorMessage = nil
            return result
        } catch {
            handleExportError(error)
            return nil
        }
    }

    func persistSession() {
        sessionSaveTask?.cancel()
        sessionSaveTask = nil
        saveSessionImmediately()
    }

    func markTrialUseConsumed() {
        guard var session, !session.isTrialHistory else {
            return
        }

        session.trialUseConsumed = true
        self.session = session
        persistSession()
    }

    private func saveSessionImmediately() {
        guard var session else {
            return
        }

        session.updatedAt = Date()
        session.leftSlot = CompareSessionSlot(slot: leftSlot)
        session.rightSlot = CompareSessionSlot(slot: rightSlot)
        session.settings = settings
        session.overlaySettings = overlaySettings
        session.compareMode = compareMode
        session.timelineSeconds = playbackState.timelineSeconds

        do {
            try sessionStore.save(session)
            self.session = session
        } catch {
            errorMessage = AppError.sessionSaveFailed.errorDescription
        }
    }

    private func withExportSession<T>(
        options: ExportOptions,
        operation: (ExportRequest) async throws -> T
    ) async throws -> T {
        guard !isExporting else {
            throw AppError.videoExportFailed
        }

        pause()
        isExporting = true
        exportProgress = ExportProgress(fraction: 0, message: String(localized: "Preparing export…"))
        errorMessage = nil
        toastMessage = nil
        defer {
            isExporting = false
            exportProgress = .idle
        }

        let request = try makeExportRequest(options: options)
        return try await operation(request)
    }

    private func makeExportResult(for request: ExportRequest) async throws -> ExportResult {
        return try await exportService.export(request) { [weak self] progress in
            self?.exportProgress = progress
        }
    }

    private func makeExportRequest(options: ExportOptions) throws -> ExportRequest {
        guard canStartSyncedCompare, playbackState.hasValidTimelineRange else {
            throw AppError.noComparableRange
        }

        var normalizedOptions = options
        if normalizedOptions.format == .image {
            normalizedOptions.range = .currentFrame
            normalizedOptions.audioSource = .none
        }

        if normalizedOptions.range == .loop, !canExportLoopRange {
            throw AppError.exportRangeUnavailable
        }

        let outputSize = normalizedOptions.resolution.outputSize(for: settings.displayMode)
        return ExportRequest(
            leftURL: leftSlot.video.url,
            rightURL: rightSlot.video.url,
            timelineSeconds: playbackState.timelineSeconds,
            timelineRange: playbackState.timelineRange,
            loopRange: settings.loopRange,
            syncSettings: syncSettingsFromSyncPoints(),
            layout: settings.displayMode,
            overlaySettings: overlaySettings,
            options: normalizedOptions,
            outputSize: outputSize
        )
    }

    private func handleExportError(_ error: Error) {
        if Task.isCancelled {
            toastMessage = AppError.exportCancelled.errorDescription
            errorMessage = nil
            return
        }

        hasExportFailure = true

        if let appError = error as? AppError {
            if appError == .exportCancelled {
                toastMessage = appError.errorDescription
                errorMessage = nil
            } else {
                errorMessage = appError.errorDescription
            }
        } else {
            errorMessage = AppError.videoExportFailed.errorDescription
        }
    }

    private func playSynced() async {
        guard canStartSyncedCompare else {
            errorMessage = String(localized: "Set a reference point in each video.")
            return
        }

        await seekNormalized(to: playbackState.timelineSeconds)
        playerSyncService.play(rate: settings.playbackRate)
        hasMeaningfulComparisonActivity = true
        playbackState.isPlaying = true
        leftSlot.isPlaying = true
        rightSlot.isPlaying = true
    }

    private func seekNormalized(to timelineSeconds: Double) async {
        let clampedSeconds = clampedTimeline(timelineSeconds)
        playbackState.timelineSeconds = clampedSeconds
        let syncSettings = syncSettingsFromSyncPoints()
        await playerSyncService.seek(timelineSeconds: clampedSeconds, syncSettings: syncSettings)
        updateSlotTimes(forTimeline: clampedSeconds)
    }

    private func startScrubSeekLoopIfNeeded() {
        guard scrubSeekTask == nil else {
            return
        }

        scrubSeekTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard let targetTimelineSeconds = pendingScrubTimelineSeconds else {
                    break
                }

                pendingScrubTimelineSeconds = nil
                await playerSyncService.seek(
                    timelineSeconds: targetTimelineSeconds,
                    syncSettings: syncSettingsFromSyncPoints(),
                    toleranceSeconds: 0.04
                )
                guard !Task.isCancelled else {
                    break
                }
                updateSlotTimes(forTimeline: targetTimelineSeconds)
            }

            scrubSeekTask = nil
        }
    }

    private func startSlotScrubSeekLoopIfNeeded(for side: VideoSide) {
        guard slotScrubSeekTasks[side] == nil else {
            return
        }

        slotScrubSeekTasks[side] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard let targetSeconds = pendingSlotScrubSeconds[side] else {
                    break
                }

                pendingSlotScrubSeconds[side] = nil
                await playerSyncService.seek(side: side, to: targetSeconds, toleranceSeconds: 0.04)
                guard !Task.isCancelled else {
                    break
                }
                setSlot(side, currentTimeSeconds: targetSeconds)
            }

            slotScrubSeekTasks[side] = nil
        }
    }

    private func updateSlotTimes(forTimeline timelineSeconds: Double) {
        leftSlot.currentTimeSeconds = clampedActualTime(timelineSeconds + leftSlot.syncPointSeconds, for: .left)
        rightSlot.currentTimeSeconds = clampedActualTime(timelineSeconds + rightSlot.syncPointSeconds, for: .right)
    }

    private func seekToSyncPointPreview() {
        Task { @MainActor in
            await playerSyncService.seek(
                leftActualSeconds: leftSlot.syncPointSeconds,
                rightActualSeconds: rightSlot.syncPointSeconds
            )
            leftSlot.currentTimeSeconds = leftSlot.syncPointSeconds
            rightSlot.currentTimeSeconds = rightSlot.syncPointSeconds
        }
    }

    private func handlePlaybackEnded() {
        playbackState.isPlaying = false
        leftSlot.isPlaying = false
        rightSlot.isPlaying = false
    }

    private func handleTimelineTick(_ timelineSeconds: Double) {
        guard playbackState.isPlaying, compareMode == .synced else {
            return
        }

        playbackState.timelineSeconds = clampedTimeline(timelineSeconds)
    }

    private func handleActualTimeTick(side: VideoSide, actualSeconds: Double) {
        setSlot(side, currentTimeSeconds: clampedActualTime(actualSeconds, for: side))
    }

    private func recalculateTimelineBounds() {
        let lowerBound = max(-leftSlot.syncPointSeconds, -rightSlot.syncPointSeconds)
        let upperBound = min(
            leftSlot.video.durationSeconds - leftSlot.syncPointSeconds,
            rightSlot.video.durationSeconds - rightSlot.syncPointSeconds
        )

        if upperBound > lowerBound {
            playbackState.timelineLowerBound = lowerBound
            playbackState.timelineUpperBound = upperBound
        } else {
            playbackState.timelineLowerBound = 0
            playbackState.timelineUpperBound = max(1, min(leftSlot.video.durationSeconds, rightSlot.video.durationSeconds))
        }

        playbackState.timelineSeconds = clampedTimeline(playbackState.timelineSeconds)
    }

    private func clampedTimeline(_ value: Double) -> Double {
        min(max(value, playbackState.timelineLowerBound), playbackState.timelineUpperBound)
    }

    private func clampedActualTime(_ value: Double, for side: VideoSide) -> Double {
        let duration = slot(for: side).video.durationSeconds
        return min(max(value, 0), duration)
    }

    private func clampedViewScale(_ value: Double) -> Double {
        min(max(value, 1), 4)
    }

    private func normalizedRotationDegrees(_ value: Double) -> Double {
        var degrees = value.truncatingRemainder(dividingBy: 360)
        if degrees > 180 {
            degrees -= 360
        } else if degrees < -180 {
            degrees += 360
        }
        return degrees
    }

    private func syncSettingsFromSyncPoints() -> SyncSettings {
        SyncSettings(
            leftOffsetSeconds: -leftSlot.syncPointSeconds,
            rightOffsetSeconds: -rightSlot.syncPointSeconds
        )
    }

    private static func makeSlot(
        side: VideoSide,
        video: VideoItem,
        sessionSlot: CompareSessionSlot
    ) -> VideoSlotState {
        VideoSlotState(
            side: side,
            video: video,
            currentTimeSeconds: sessionSlot.currentTimeSeconds,
            syncPointSeconds: sessionSlot.syncPointSeconds,
            hasSyncPoint: sessionSlot.hasSyncPoint,
            viewScale: sessionSlot.viewScale,
            viewOffsetX: sessionSlot.viewOffsetX,
            viewOffsetY: sessionSlot.viewOffsetY
        )
    }

    private static func makePlayerSyncService(leftVideo: VideoItem, rightVideo: VideoItem) -> PlayerSyncService {
        PlayerSyncService(
            leftURL: leftVideo.url,
            rightURL: rightVideo.url,
            leftDurationSeconds: leftVideo.durationSeconds,
            rightDurationSeconds: rightVideo.durationSeconds
        )
    }

    private func restorePlayerPositions() {
        Task { @MainActor in
            if compareMode == .synced, canStartSyncedCompare {
                await seekNormalized(to: playbackState.timelineSeconds)
            } else {
                await playerSyncService.seek(
                    leftActualSeconds: leftSlot.currentTimeSeconds,
                    rightActualSeconds: rightSlot.currentTimeSeconds
                )
            }
        }
    }

    private func scheduleSessionPersistence() {
        guard session != nil else {
            return
        }

        sessionSaveTask?.cancel()
        sessionSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            sessionSaveTask = nil
            saveSessionImmediately()
        }
    }

    private func recreatePlayerSyncService() {
        playerSyncService.releasePlayers()
        playerSyncService = Self.makePlayerSyncService(leftVideo: leftSlot.video, rightVideo: rightSlot.video)
        configurePlayerSyncService()
    }

    private func configurePlayerSyncService() {
        playerSyncService.updateSyncSettings(syncSettingsFromSyncPoints())
        playerSyncService.updateLoopRange(settings.loopRange)
        playerSyncService.setPlaybackRate(settings.playbackRate)
        playerSyncService.onPlaybackEnded = { [weak self] in
            self?.handlePlaybackEnded()
        }
        playerSyncService.onTimelineTick = { [weak self] timelineSeconds in
            self?.handleTimelineTick(timelineSeconds)
        }
        playerSyncService.onActualTimeTick = { [weak self] side, actualSeconds in
            self?.handleActualTimeTick(side: side, actualSeconds: actualSeconds)
        }
    }

    private func loopValidationError(for loopRange: LoopRange) -> AppError? {
        guard let start = loopRange.startSeconds else {
            return .loopMissingStart
        }

        guard let end = loopRange.endSeconds else {
            return .loopMissingEnd
        }

        guard end > start else {
            return .invalidLoopRange
        }

        guard playbackState.timelineRange.contains(start), playbackState.timelineRange.contains(end) else {
            return .loopRangeOutOfBounds
        }

        return nil
    }

    private func loopRangeForActivation() -> LoopRange {
        var loopRange = settings.loopRange
        loopRange.startSeconds = clampedTimeline(loopRange.startSeconds ?? playbackState.timelineLowerBound)
        loopRange.endSeconds = clampedTimeline(loopRange.endSeconds ?? playbackState.timelineUpperBound)
        loopRange.isEnabled = true
        return loopRange
    }

    private func setSlot(_ slot: VideoSlotState) {
        switch slot.side {
        case .left:
            leftSlot = slot
        case .right:
            rightSlot = slot
        }
    }

    private func setSlot(_ side: VideoSide, currentTimeSeconds: Double) {
        var slot = slot(for: side)
        slot.currentTimeSeconds = currentTimeSeconds
        setSlot(slot)
    }

    private func setSlot(_ side: VideoSide, isPlaying: Bool) {
        var slot = slot(for: side)
        slot.isPlaying = isPlaying
        setSlot(slot)
    }
}
