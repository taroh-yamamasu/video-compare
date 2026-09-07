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
