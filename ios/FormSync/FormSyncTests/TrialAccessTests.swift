import XCTest
@testable import FormSync

final class TrialAccessTests: XCTestCase {
    @MainActor
    func testTrialStopsAfterThreeUses() {
        let identifier = UUID().uuidString
        let defaults = UserDefaults(suiteName: identifier)!
        defaults.removePersistentDomain(forName: identifier)
        let store = InMemoryTrialUsageStore()
        let manager = PurchaseManager(defaults: defaults, trialUsageStore: store)

        XCTAssertEqual(manager.remainingTrialUses, 3)
        XCTAssertTrue(manager.consumeTrialUse())
        XCTAssertTrue(manager.consumeTrialUse())
        XCTAssertTrue(manager.consumeTrialUse())
        XCTAssertFalse(manager.consumeTrialUse())
        XCTAssertEqual(manager.remainingTrialUses, 0)
    }

    @MainActor
    func testTrialUsageRestoresFromKeychain() {
        let identifier = UUID().uuidString
        let defaults = UserDefaults(suiteName: identifier)!
        defaults.removePersistentDomain(forName: identifier)
        let store = InMemoryTrialUsageStore()
        let firstManager = PurchaseManager(defaults: defaults, trialUsageStore: store)

        XCTAssertTrue(firstManager.consumeTrialUse())
        XCTAssertTrue(firstManager.consumeTrialUse())

        defaults.removePersistentDomain(forName: identifier)
        let restoredManager = PurchaseManager(defaults: defaults, trialUsageStore: store)
        XCTAssertEqual(restoredManager.remainingTrialUses, 1)
    }

    @MainActor
    func testProFeatureRequiresActiveTrialContext() {
        let manager = makeManager()

        XCTAssertFalse(manager.canUse(.overlay))
        XCTAssertTrue(manager.canUse(.overlay, hasTrialAccess: true))
    }

    @MainActor
    func testSampleComparisonDoesNotConsumeTrialUse() {
        let manager = makeManager()

        XCTAssertTrue(manager.beginFullFeatureComparison(isSample: true))
        XCTAssertEqual(manager.remainingTrialUses, 3)
    }

    #if DEBUG
    @MainActor
    func testDebugResetRestoresAllTrialUses() {
        let manager = makeManager()
        XCTAssertTrue(manager.consumeTrialUse())
        XCTAssertEqual(manager.remainingTrialUses, 2)

        manager.resetTrialForTesting()

        XCTAssertEqual(manager.remainingTrialUses, 3)
    }
    #endif

    func testLegacySessionWithoutTrialFlagStillDecodes() throws {
        let session = CompareSession(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            title: "Legacy",
            leftSlot: makeSessionSlot(fileName: "left.mov"),
            rightSlot: makeSessionSlot(fileName: "right.mov"),
            settings: CompareSettings(),
            overlaySettings: OverlaySettings(),
            compareMode: .setup,
            timelineSeconds: 0
        )

        let encoded = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "trialUseConsumed")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CompareSession.self, from: legacyData)

        XCTAssertFalse(decoded.isTrialHistory)
    }

    func testV132SessionFixtureStillDecodes() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "session-v1.3.2", withExtension: "json")
        )
        let data = try Data(contentsOf: fixtureURL)
        let session = try JSONDecoder().decode(CompareSession.self, from: data)

        XCTAssertEqual(session.title, "KinePair 1.3.2 Session")
        XCTAssertEqual(session.compareMode, .synced)
        XCTAssertTrue(session.hasSyncPoints)
        XCTAssertFalse(session.isTrialHistory)
    }

    @MainActor
    func testLatestSessionUsesFirstVisibleSession() {
        let viewModel = HomeViewModel()
        let first = makeSession(title: "Latest", updatedAt: Date(timeIntervalSinceReferenceDate: 2))
        let second = makeSession(title: "Older", updatedAt: Date(timeIntervalSinceReferenceDate: 1))

        viewModel.sessions = [first, second]

        XCTAssertEqual(viewModel.latestSession?.id, first.id)
    }

    func testReviewRequestBecomesPendingAfterThirdComparison() {
        let identifier = UUID().uuidString
        let defaults = UserDefaults(suiteName: identifier)!
        defaults.removePersistentDomain(forName: identifier)
        let settings = SettingsStore(defaults: defaults)

        settings.markComparisonCompletedForReview()
        settings.markComparisonCompletedForReview()
        XCTAssertFalse(settings.consumePendingReviewRequest())

        settings.markComparisonCompletedForReview()
        XCTAssertTrue(settings.consumePendingReviewRequest())
        XCTAssertFalse(settings.consumePendingReviewRequest())
    }

    func testV13NoticeOnlyAppearsForReturningUsers() {
        let identifier = UUID().uuidString
        let defaults = UserDefaults(suiteName: identifier)!
        defaults.removePersistentDomain(forName: identifier)
        var settings = SettingsStore(defaults: defaults)

        XCTAssertFalse(settings.shouldShowV13UpdateNotice)
        settings.hasSeenOnboarding = true
        XCTAssertTrue(settings.shouldShowV13UpdateNotice)

        settings.markV13UpdateNoticeSeen()
        XCTAssertFalse(settings.shouldShowV13UpdateNotice)
    }

    func testSamplePairDoesNotOwnBundleVideosOrCreateHistory() {
        let pair = LoadedVideoPair(
            left: VideoItem(url: URL(fileURLWithPath: "/sample-a.mp4"), fileName: "Sample A"),
            right: VideoItem(url: URL(fileURLWithPath: "/sample-b.mp4"), fileName: "Sample B"),
            ownsTemporaryVideos: false,
            isSample: true
        )

        XCTAssertTrue(pair.isSample)
        XCTAssertFalse(pair.ownsTemporaryVideos)
        XCTAssertNil(pair.session)
    }

    func testComparisonDefaultsMigrateLegacyValuesAndResetIndependently() {
        let identifier = UUID().uuidString
        let defaults = UserDefaults(suiteName: identifier)!
        defaults.removePersistentDomain(forName: identifier)
        var settings = SettingsStore(defaults: defaults)
        settings.lastPlaybackRate = .half
        settings.lastDisplayMode = .stacked
        let preset = QuickExportPreset(
            format: .image,
            range: .currentFrame,
            resolution: .p720,
            audioSource: .none,
            destination: .share
        )
        settings.saveQuickExportPreset(preset)

        let migrated = settings.comparisonDefaults
        XCTAssertEqual(migrated.playbackRate, .half)
        XCTAssertEqual(migrated.displayMode, .stacked)
        XCTAssertEqual(migrated.stepSeconds, 0.1)

        settings.resetComparisonDefaults()
        XCTAssertEqual(settings.comparisonDefaults, ComparisonDefaults())
        XCTAssertEqual(settings.quickExportPreset, preset)
    }

    func testQuickExportPresetIsValidatedAgainstAccessAndLoopState() {
        let proVideo = QuickExportPreset(
            format: .video,
            range: .loop,
            resolution: .p1080,
            audioSource: .left,
            destination: .photoLibrary
        )
        let freeImage = QuickExportPreset(
            format: .image,
            range: .full,
            resolution: .p720,
            audioSource: .right,
            destination: .share
        )

        XCTAssertNil(proVideo.validated(hasFullAccess: false, canExportLoopRange: true))
        XCTAssertNil(proVideo.validated(hasFullAccess: true, canExportLoopRange: false))
        XCTAssertEqual(
            proVideo.validated(hasFullAccess: true, canExportLoopRange: true),
            proVideo
        )
        XCTAssertEqual(
            freeImage.validated(hasFullAccess: false, canExportLoopRange: false)?.range,
            .currentFrame
        )
        XCTAssertEqual(
            freeImage.validated(hasFullAccess: false, canExportLoopRange: false)?.audioSource,
            ExportAudioSource.none
        )
    }

    @MainActor
    func testSyncedSessionRestoresPhaseTimelineAndFraming() {
        var leftSlot = makeSessionSlot(fileName: "left.mov")
        leftSlot.hasSyncPoint = true
        leftSlot.syncPointSeconds = 0.25
        leftSlot.viewScale = 2
        leftSlot.viewOffsetX = 18
        leftSlot.viewOffsetY = 24
        var rightSlot = makeSessionSlot(fileName: "right.mov")
        rightSlot.hasSyncPoint = true
        rightSlot.syncPointSeconds = 0.5
        let session = CompareSession(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            title: "Synced",
            leftSlot: leftSlot,
            rightSlot: rightSlot,
            settings: CompareSettings(),
            overlaySettings: OverlaySettings(),
            compareMode: .synced,
            timelineSeconds: 0.75
        )
        let viewModel = CompareViewModel(
            leftVideo: VideoItem(url: URL(fileURLWithPath: "/left.mov"), fileName: "Left", durationSeconds: 2),
            rightVideo: VideoItem(url: URL(fileURLWithPath: "/right.mov"), fileName: "Right", durationSeconds: 2),
            session: session,
            ownsTemporaryVideos: false
        )

        XCTAssertEqual(viewModel.compareMode, .synced)
        XCTAssertEqual(viewModel.playbackState.timelineSeconds, 0.75)
        XCTAssertEqual(viewModel.leftSlot.viewScale, 2)
        XCTAssertEqual(viewModel.leftSlot.viewOffsetX, 18)
        XCTAssertEqual(viewModel.leftSlot.viewOffsetY, 24)
    }

    @MainActor
    func testClearingAReferencePointDisablesComparison() {
        let viewModel = CompareViewModel(
            leftVideo: VideoItem(url: URL(fileURLWithPath: "/sample-a.mp4"), fileName: "Sample A", durationSeconds: 1),
            rightVideo: VideoItem(url: URL(fileURLWithPath: "/sample-b.mp4"), fileName: "Sample B", durationSeconds: 1),
            ownsTemporaryVideos: false,
            isSample: true
        )

        viewModel.setSyncPoint(.left)
        viewModel.setSyncPoint(.right)
        XCTAssertTrue(viewModel.canStartSyncedCompare)

        viewModel.clearSyncPoint(.left)
        XCTAssertFalse(viewModel.canStartSyncedCompare)
        XCTAssertFalse(viewModel.leftSlot.hasSyncPoint)
    }

    @MainActor
    func testDisplayModeChangePreservesTimeline() async {
        let viewModel = CompareViewModel(
            leftVideo: VideoItem(url: URL(fileURLWithPath: "/sample-a.mp4"), fileName: "Sample A", durationSeconds: 2),
            rightVideo: VideoItem(url: URL(fileURLWithPath: "/sample-b.mp4"), fileName: "Sample B", durationSeconds: 2),
            ownsTemporaryVideos: false,
            isSample: true
        )
        viewModel.setSyncPoint(.left)
        viewModel.setSyncPoint(.right)
        await viewModel.startSyncedCompare()
        viewModel.playbackState.timelineSeconds = 0.75

        viewModel.setDisplayMode(.overlayPreview)

        XCTAssertEqual(viewModel.playbackState.timelineSeconds, 0.75)
    }

    private func makeSessionSlot(fileName: String) -> CompareSessionSlot {
        CompareSessionSlot(
            video: CompareSessionVideo(
                fileName: fileName,
                originalFileName: fileName,
                durationSeconds: 1
            )
        )
    }

    private func makeSession(title: String, updatedAt: Date) -> CompareSession {
        CompareSession(
            id: UUID(),
            createdAt: updatedAt,
            updatedAt: updatedAt,
            title: title,
            leftSlot: makeSessionSlot(fileName: "left.mov"),
            rightSlot: makeSessionSlot(fileName: "right.mov"),
            settings: CompareSettings(),
            overlaySettings: OverlaySettings(),
            compareMode: .setup,
            timelineSeconds: 0
        )
    }

    @MainActor
    private func makeManager() -> PurchaseManager {
        let identifier = UUID().uuidString
        let defaults = UserDefaults(suiteName: identifier)!
        defaults.removePersistentDomain(forName: identifier)
        return PurchaseManager(
            defaults: defaults,
            trialUsageStore: InMemoryTrialUsageStore()
        )
    }
}

private final class InMemoryTrialUsageStore: TrialUsageStoring {
    private var usedUses: Int?

    func loadUsedUses() -> Int? {
        usedUses
    }

    func saveUsedUses(_ usedUses: Int) -> Bool {
        self.usedUses = usedUses
        return true
    }
}
